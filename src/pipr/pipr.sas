/* MODULE DOC
File: src/pipr/pipr.sas

1) Purpose in overall project
- Core pipr pipeline engine that parses pipe expressions and executes verbs step-by-step.

2) High-level approach
- Parses parmbuff input into steps, infers source/target datasets, and delegates each verb to shared verb-dispatch helpers.

3) Code organization and why this scheme was chosen
- Private parse/planning/execution helpers precede the public pipe macro; tests live at the bottom for import-time safety.
- Code is organized as helper macros first, public API second, and tests/autorun guards last to reduce contributor onboarding time and import risk.

4) Detailed pseudocode algorithm
- Parse raw pipe expression into ordered steps and optional named args.
- Infer first input dataset and identify collect_to/collect_into output if present.
- Validate input/output metadata and construct execution plan.
- For each step, resolve verb and invoke shared dispatch helper.
- Manage temp datasets/views and cleanup according to flags.
- Emit errors early when a step fails to produce expected output.

5) Acknowledged implementation deficits
- Macro parsing for complex nested expressions remains sensitive to quoting edge cases.
- Step execution/debug output can still be verbose during heavy troubleshooting.
- Contributor docs are still text comments; there is no generated API reference yet.

6) Macros defined in this file
- _pipe_parse_parmbuff
- _pipe_split_parmbuff_segments
- _pipe_clean_value
- _pipe_first_step
- _pipe_is_data_step
- _pipe_steps_without_first
- _pipe_infer_data
- _pipe_get_last_step
- _pipe_is_collect_verb
- _pipe_collect_args
- _pipe_extract_collect_out
- _pipe_plan_step
- _pipe_steps_count
- _pipe_get_step
- _pipe_validate_inputs
- _pipe_execute_step
- _pipe_cleanup_temps
- _pipe_execute
- pipe
- _pipe_parse_parmbuff_test
- test_pipe_helpers
- test_pipe

Planner note
- Planner state/build/serialize/replay macros are centralized in src/pipr/plan.sas and included here when missing.

7) Expected side effects from running/include
- Defines 22 macro(s) in the session macro catalog.
- May create/update GLOBAL macro variable(s): _pp_steps, _pp_data, _pp_out, _pp_validate, _pp_use_views, _pp_view_output, _pp_debug, _pp_cleanup, _pd_steps, _pd_data, _pc_steps, _pc_out, ....
- Executes top-level macro call(s) on include: _pipr_autorun_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
- When invoked, macros in this module can create or overwrite WORK datasets/views as part of pipeline operations.
*/
/* Required includes are handled by sassyverse_init; keep this file standalone-safe if needed. */
%if not %sysmacexist(_abort) %then %do;
  %include 'util.sas';
%end;
%if not %sysmacexist(_assert_ds_exists) %then %do;
  %include 'validation.sas';
%end;
%if not %sysmacexist(_verb_supports_view) %then %do;
  %include '_verbs/utils.sas';
%end;
%if (not %sysmacexist(filter)) or (not %sysmacexist(mutate)) or (not %sysmacexist(select)) %then %do;
  %include 'verbs.sas';
%end;
%if not %sysmacexist(_pipe_plan_build) %then %do;
  %include 'plan.sas';
%end;

%macro _pipe_parse_parmbuff(
  steps_in=,
  data_in=,
  out_in=,
  validate_in=,
  use_views_in=,
  view_output_in=,
  debug_in=,
  cleanup_in=,
  out_steps=,
  out_data=,
  out_out=,
  out_validate=,
  out_use_views=,
  out_view_output=,
  out_debug=,
  out_cleanup=
);
  %local buf i _kind seg_head seg_val __seg_count;

  %_pipr_ucl_assign(out_text=%superq(out_steps), value=%superq(steps_in));
  %_pipr_ucl_assign(out_text=%superq(out_data), value=%superq(data_in));
  %_pipr_ucl_assign(out_text=%superq(out_out), value=%superq(out_in));
  %_pipr_ucl_assign(out_text=%superq(out_validate), value=%superq(validate_in));
  %_pipr_ucl_assign(out_text=%superq(out_use_views), value=%superq(use_views_in));
  %_pipr_ucl_assign(out_text=%superq(out_view_output), value=%superq(view_output_in));
  %_pipr_ucl_assign(out_text=%superq(out_debug), value=%superq(debug_in));
  %_pipr_ucl_assign(out_text=%superq(out_cleanup), value=%superq(cleanup_in));

  %let buf=%superq(syspbuff);
  %if %length(%superq(buf)) > 2 %then %do;
    %if not %sysmacexist(_pipr_parse_parmbuff) %then
      %_abort(pipe() requires pipr util helpers to be loaded.);
    %_pipr_parse_parmbuff(
      buf=%superq(buf),
      recognized=%str(DATA OUT VALIDATE USE_VIEWS VIEW_OUTPUT DEBUG CLEANUP STEPS),
      out_n=__seg_count,
      out_prefix=_ppb
    );

    %do i=1 %to &__seg_count;
      %let _kind=&&_ppb_kind&i;
      %let seg_head=&&_ppb_head&i;
      %let seg_val=&&_ppb_val&i;

      %if &_kind=N %then %do;
        %if &seg_head=DATA %then %_pipr_ucl_assign_strip(out_text=%superq(out_data), value=%superq(seg_val));
        %else %if &seg_head=OUT %then %_pipr_ucl_assign_strip(out_text=%superq(out_out), value=%superq(seg_val));
        %else %if &seg_head=VALIDATE %then %_pipr_ucl_assign_strip(out_text=%superq(out_validate), value=%superq(seg_val));
        %else %if &seg_head=USE_VIEWS %then %_pipr_ucl_assign_strip(out_text=%superq(out_use_views), value=%superq(seg_val));
        %else %if &seg_head=VIEW_OUTPUT %then %_pipr_ucl_assign_strip(out_text=%superq(out_view_output), value=%superq(seg_val));
        %else %if &seg_head=DEBUG %then %_pipr_ucl_assign_strip(out_text=%superq(out_debug), value=%superq(seg_val));
        %else %if &seg_head=CLEANUP %then %_pipr_ucl_assign_strip(out_text=%superq(out_cleanup), value=%superq(seg_val));
        %else %if &seg_head=STEPS %then %_pipr_ucl_assign_strip(out_text=%superq(out_steps), value=%superq(seg_val));
      %end;
      %else %if %length(%superq(&out_steps))=0 %then %_pipr_ucl_assign_strip(out_text=%superq(out_steps), value=%superq(seg_val));
    %end;
  %end;
%mend;

%macro _pipe_split_parmbuff_segments(buf=, out_n=, out_prefix=seg);
  %if %sysmacexist(_pipr_split_parmbuff) %then %do;
    %_pipr_split_parmbuff(
      buf=%superq(buf)
      , out_n=%superq(out_n)
      , out_prefix=%superq(out_prefix)
    );
  %end;
  %else %if %sysmacexist(_pipr_split_parmbuff_segments) %then %do;
    %_pipr_split_parmbuff_segments(
      buf=%superq(buf)
      , out_n=%superq(out_n)
      , out_prefix=%superq(out_prefix)
    );
  %end;
  %else %_abort(pipe() requires pipr util helpers to be loaded.);
%mend;

/* Remove control characters and compact whitespace for safer token handling. */
%macro _pipe_clean_value(value=, out=);
  %local _tmp;
  %let _tmp=%sysfunc(prxchange(%str(s/[^\x20-\x7E]+/ /), -1, %superq(value)));
  %let _tmp=%sysfunc(compbl(%superq(_tmp)));
  %_pipr_ucl_assign_strip(out_text=%superq(out), value=%superq(_tmp));
%mend;

%macro _pipe_first_step(steps=, out_step=);
  %local _step;
  %let _step=%scan(%superq(steps), 1, |, m);
  %_pipr_ucl_assign_strip(out_text=%superq(out_step), value=%superq(_step));
%mend;

%macro _pipe_is_data_step(step=, out_is=);
  %if %length(%superq(step)) and %index(%superq(step), %str(%()) = 0 %then %_pipr_ucl_assign(out_text=%superq(out_is), value=1);
  %else %_pipr_ucl_assign(out_text=%superq(out_is), value=0);
%mend;

%macro _pipe_steps_without_first(steps=, out_steps=);
  %local _n _i _token _new_steps;

  %let _n=%sysfunc(countw(%superq(steps), |, m));
  %let _new_steps=;

  %do _i=2 %to &_n;
    %let _token=%scan(%superq(steps), &_i, |, m);
    %if %length(%sysfunc(strip(%superq(_token)))) %then %do;
      %if %length(%superq(_new_steps)) %then %let _new_steps=&_new_steps | &_token;
      %else %let _new_steps=&_token;
    %end;
  %end;

  %_pipr_ucl_assign(out_text=%superq(out_steps), value=%superq(_new_steps));
%mend;

%macro _pipe_infer_data(steps_in=, data_in=, out_steps=, out_data=);
  %local first_step is_data new_steps;
  %_pipr_ucl_assign(out_text=%superq(out_steps), value=%superq(steps_in));
  %_pipr_ucl_assign(out_text=%superq(out_data), value=%superq(data_in));

  %if %length(%superq(data_in))=0 %then %do;
    %_pipe_first_step(steps=%superq(steps_in), out_step=first_step);
    %_pipe_is_data_step(step=%superq(first_step), out_is=is_data);

    %if &is_data %then %do;
      %_pipr_ucl_assign(out_text=%superq(out_data), value=%superq(first_step));
      %_pipe_steps_without_first(steps=%superq(steps_in), out_steps=new_steps);
      %_pipr_ucl_assign(out_text=%superq(out_steps), value=%superq(new_steps));
    %end;
  %end;
%mend;

%macro _pipe_get_last_step(steps=, out_last=, out_n=);
  %local _n;

  %let _n=%sysfunc(countw(%superq(steps), |, m));
  %if &_n > 0 %then %_pipr_ucl_assign(out_text=%superq(out_last), value=%scan(%superq(steps), &_n, |, m));
  %else %_pipr_ucl_assign(out_text=%superq(out_last), value=);
  %_pipr_ucl_assign(out_text=%superq(out_n), value=&_n);
%mend;

%macro _pipe_is_collect_verb(verb=, out_is=);
  %local _out;
  %if %length(%superq(out_is))=0 %then %let out_is=_pipe_is_collect_verb_out;
  %let _out=%sysfunc(indexw(COLLECT_TO COLLECT_INTO, %upcase(%superq(verb))));
  %_pipr_ucl_assign(out_text=%superq(out_is), value=&_out);
%mend;

%macro _pipe_collect_args(step=, out_args=);
  %local paren_pos _args;

  %let paren_pos=%index(%superq(step), %str(%());
  %if &paren_pos > 0 %then %do;
    %let _args=%substr(%superq(step), %eval(&paren_pos+1));
    %if %length(%superq(_args)) %then %let _args=%substr(%superq(_args), 1, %eval(%length(%superq(_args))-1));
  %end;
  %else %let _args=;

  %_pipr_ucl_assign(out_text=%superq(out_args), value=%superq(_args));
%mend;

%macro _pipe_extract_collect_out(steps_in=, out_in=, out_steps=, out_out=, out_collect_out=);
  %local n last_step last_verb _lv_len _lv_last args collect_out token new_steps i is_collect;

  %_pipe_clean_value(value=%superq(steps_in), out=&out_steps);
  %_pipe_clean_value(value=%superq(out_in), out=&out_out);
  %_pipr_ucl_assign(out_text=%superq(out_collect_out), value=);
  %let is_collect=0;

  %_pipe_get_last_step(steps=%superq(steps_in), out_last=last_step, out_n=n);
  %if &n > 0 %then %do;
    %let last_step=%sysfunc(strip(%superq(last_step)));
    %let last_verb=%upcase(%scan(%superq(last_step), 1, %str(%())));

    %let _lv_len=%length(%superq(last_verb));
    %if %eval(&_lv_len > 0) %then %do;
      %let _lv_last=%qsubstr(%superq(last_verb), &_lv_len, 1);
      %if "&_lv_last"=")" %then %let last_verb=%substr(%superq(last_verb), 1, %eval(&_lv_len-1));
    %end;
    %_pipe_is_collect_verb(verb=&last_verb, out_is=is_collect);

    %if &is_collect > 0 %then %do;
      %_pipe_collect_args(step=%superq(last_step), out_args=args);
      %let collect_out=%sysfunc(strip(%superq(args)));
      %_pipe_clean_value(value=%superq(collect_out), out=collect_out);

      %_pipr_ucl_assign(out_text=%superq(out_collect_out), value=%superq(collect_out));
      %if %length(%superq(out_in))=0 %then %_pipr_ucl_assign(out_text=%superq(out_out), value=%superq(collect_out));
      %else %put WARNING: collect_to() ignored because out= is already provided.;

      %let new_steps=;
      %do i=1 %to %eval(&n-1);
        %let token=%scan(%superq(steps_in), &i, |, m);
        %if %length(%sysfunc(strip(%superq(token)))) %then %do;
          %if %length(%superq(new_steps)) %then %let new_steps=&new_steps | &token;
          %else %let new_steps=&token;
        %end;
      %end;

      %_pipe_clean_value(value=%superq(new_steps), out=new_steps);
      %_pipr_ucl_assign(out_text=%superq(out_steps), value=%superq(new_steps));
    %end;
  %end;
%mend;

%macro _pipe_plan_step(
  i=,
  n=,
  out=,
  tmp1=,
  tmp2=,
  use_views=,
  view_output=,
  supports_view=,
  out_as_view=,
  out_next=
);
  %if &i = &n %then %do;
    %_pipr_ucl_assign(out_text=%superq(out_as_view), value=%sysfunc(ifc((&view_output=1) and (&supports_view>0), 1, 0)));
    %_pipr_ucl_assign(out_text=%superq(out_next), value=&out);
  %end;
  %else %do;
    %_pipr_ucl_assign(out_text=%superq(out_as_view), value=%sysfunc(ifc((&use_views=1) and (&supports_view>0), 1, 0)));
    %if %eval(%sysfunc(mod(&i, 2))=1) %then %_pipr_ucl_assign(out_text=%superq(out_next), value=&tmp1);
    %else %_pipr_ucl_assign(out_text=%superq(out_next), value=&tmp2);
  %end;
%mend;

%macro _pipe_steps_count(steps=, out_n=);
  %_pipr_ucl_assign(out_text=%superq(out_n), value=%sysfunc(countw(%superq(steps), |, m)));
%mend;

%macro _pipe_get_step(steps=, index=, out_step=);
  %_pipr_ucl_assign(out_text=%superq(out_step), value=%scan(%superq(steps), &index, |, m));
%mend;

%macro _pipe_validate_inputs(data=, out=, steps=, require_out=1);
  %if %length(%superq(data))=0 %then %_abort(pipe() requires a data input dataset.);
  %_assert_ds_exists(&data, error_msg=Input to pipe() is missing.);
  %if &require_out and %length(%superq(out))=0 %then %_abort(pipe() requires out= or a collect_to() step.);
%mend;

%macro _pipe_execute_step(
  step=,
  i=,
  n=,
  cur=,
  out=,
  tmp1=,
  tmp2=,
  use_views=,
  view_output=,
  debug=,
  validate=,
  out_next=
);
  %local verb supports_view as_view _nxt;

  %let verb=%scan(%superq(step), 1, %str(%());
  %if %length(%superq(verb))=0 %then %_abort(Bad step token: %superq(step));

  %let supports_view=%_verb_supports_view(&verb);

  %_pipe_plan_step(
    i=&i,
    n=&n,
    out=&out,
    tmp1=&tmp1,
    tmp2=&tmp2,
    use_views=&use_views,
    view_output=&view_output,
    supports_view=&supports_view,
    out_as_view=as_view,
    out_next=_nxt
  );

  %if &debug %then %do;
    %put NOTE: PIPE step &i/&n: %superq(step);
    %put NOTE:   verb=&verb supports_view=&supports_view planned_as_view=&as_view;
    %put NOTE:   in=&cur;
    %put NOTE:   out=&_nxt;
  %end;

  %_apply_step(%superq(step), &cur, &_nxt, &validate, &as_view);
  %_assert_ds_exists(&_nxt, error_msg=Step &i did not create expected output. Step token: %superq(step));

  %_pipr_ucl_assign(out_text=%superq(out_next), value=&_nxt);
%mend;

%macro _pipe_cleanup_temps(tmp1=, tmp2=, out=, cleanup=1);
  %if &cleanup %then %do;
    %if %upcase(&tmp1) ne %upcase(&out) %then %do;
      proc datasets lib=work nolist; delete %scan(&tmp1, 2, .); quit;
    %end;
    %if %upcase(&tmp2) ne %upcase(&out) %then %do;
      proc datasets lib=work nolist; delete %scan(&tmp2, 2, .); quit;
    %end;
  %end;
%mend;

%macro _pipe_execute(
  steps=,
  data=,
  out=,
  validate=1,
  use_views=1,
  view_output=0,
  debug=0,
  cleanup=1
);
  %local i n cur nxt tmp1 tmp2 step;

  %let tmp1=%_tmpds(prefix=_p1_);
  %let tmp2=%_tmpds(prefix=_p2_);
  %let cur=&data;

  %_pipe_steps_count(steps=%superq(steps), out_n=n);
  %if &n = 0 %then %_abort(pipe() requires steps= delimited by '|'.);

  %do i=1 %to &n;
    %_pipe_get_step(steps=%superq(steps), index=&i, out_step=step);
    %_pipe_execute_step(
      step=%superq(step),
      i=&i,
      n=&n,
      cur=&cur,
      out=&out,
      tmp1=&tmp1,
      tmp2=&tmp2,
      use_views=&use_views,
      view_output=&view_output,
      debug=&debug,
      validate=&validate,
      out_next=nxt
    );
    %let cur=&nxt;
  %end;

  %_pipe_cleanup_temps(tmp1=&tmp1, tmp2=&tmp2, out=&out, cleanup=&cleanup);
%mend;

%macro pipe(
  steps=,
  data=,
  out=,
  validate=1,
  use_views=1,
  view_output=0,
  debug=0,
  cleanup=1
) / parmbuff;
  %local steps_work data_work out_work validate_work use_views_work view_output_work debug_work cleanup_work;
  %local collect_out _execute _plan_stmt _plan_text;

  %_pipe_parse_parmbuff(
    steps_in=%superq(steps),
    data_in=%superq(data),
    out_in=%superq(out),
    validate_in=%superq(validate),
    use_views_in=%superq(use_views),
    view_output_in=%superq(view_output),
    debug_in=%superq(debug),
    cleanup_in=%superq(cleanup),
    out_steps=steps_work,
    out_data=data_work,
    out_out=out_work,
    out_validate=validate_work,
    out_use_views=use_views_work,
    out_view_output=view_output_work,
    out_debug=debug_work,
    out_cleanup=cleanup_work
  );

  %_pipe_infer_data(
    steps_in=%superq(steps_work),
    data_in=%superq(data_work),
    out_steps=steps_work,
    out_data=data_work
  );

  %_pipe_extract_collect_out(
    steps_in=%superq(steps_work),
    out_in=%superq(out_work),
    out_steps=steps_work,
    out_out=out_work,
    out_collect_out=collect_out
  );

  %_pipe_clean_value(value=%superq(data_work), out=data_work);
  %_pipe_clean_value(value=%superq(out_work), out=out_work);
  %_pipe_clean_value(value=%superq(steps_work), out=steps_work);

  %let validate_work=%_pipr_bool(%superq(validate_work), default=1);
  %let use_views_work=%_pipr_bool(%superq(use_views_work), default=1);
  %let view_output_work=%_pipr_bool(%superq(view_output_work), default=0);
  %let debug_work=%_pipr_bool(%superq(debug_work), default=0);
  %let cleanup_work=%_pipr_bool(%superq(cleanup_work), default=1);
  %let _execute=%sysfunc(ifc(%length(%superq(collect_out))>0,1,0));

  %_pipe_validate_inputs(data=&data_work, out=&out_work, steps=&steps_work, require_out=&_execute);

  %_pipe_plan_build(steps=%superq(steps_work), data=%superq(data_work));
  %_pipe_plan_get_stmt(out_stmt=_plan_stmt);
  %_pipe_plan_serialize(out_plan=_plan_text);
  %_pipe_plan_log(collect_out=%superq(collect_out), out=%superq(out_work));
  %if &debug_work %then %put NOTE: [PIPE.PLAN] serialized=%superq(_plan_text);

  %if not &_execute %then %return;

  %if %superq(_pipe_plan_supported)=1 %then %do;
    %_pipe_plan_execute(data=%superq(data_work), out=%superq(out_work), stmt=%superq(_plan_stmt), as_view=&view_output_work);
    %return;
  %end;

  %_pipe_execute(
    steps=%superq(steps_work),
    data=&data_work,
    out=&out_work,
    validate=&validate_work,
    use_views=&use_views_work,
    view_output=&view_output_work,
    debug=&debug_work,
    cleanup=&cleanup_work
  );
%mend;

/* ---------------------- */
/* Tests for pipr.sas     */
/* ---------------------- */

%macro _pipe_parse_parmbuff_test(
  steps=,
  data=,
  out=,
  validate=1,
  use_views=1,
  view_output=0,
  debug=0,
  cleanup=1
) / parmbuff;
  %local steps_work data_work out_work validate_work use_views_work view_output_work debug_work cleanup_work;

  %_pipe_parse_parmbuff(
    steps_in=%superq(steps),
    data_in=%superq(data),
    out_in=%superq(out),
    validate_in=&validate,
    use_views_in=&use_views,
    view_output_in=&view_output,
    debug_in=&debug,
    cleanup_in=&cleanup,
    out_steps=steps_work,
    out_data=data_work,
    out_out=out_work,
    out_validate=validate_work,
    out_use_views=use_views_work,
    out_view_output=view_output_work,
    out_debug=debug_work,
    out_cleanup=cleanup_work
  );

  %global _pp_steps _pp_data _pp_out _pp_validate _pp_use_views _pp_view_output _pp_debug _pp_cleanup;
  %let _pp_steps=&steps_work;
  %let _pp_data=&data_work;
  %let _pp_out=&out_work;
  %let _pp_validate=&validate_work;
  %let _pp_use_views=&use_views_work;
  %let _pp_view_output=&view_output_work;
  %let _pp_debug=&debug_work;
  %let _pp_cleanup=&cleanup_work;
%mend;

%macro test_pipe_helpers;
  %_pipr_require_assert;
  %global _pd_steps _pd_data _pc_steps _pc_out _pc_collect;
  %global _ps_n _ps_step _ps_as_view _ps_next;
  %global _pl_last _pl_n _pl_is _pl_args;
  %global _pe_next;
  %global _pb_n;
  %global _fi_step _fi_is _fi_rest;

  %test_suite(Testing pipe helpers);
    %test_case(parse parmbuff and keep commas);
      %_pipe_parse_parmbuff_test(
        work._pipe_in2
        | left_join(right=work._pipe_right, on=id, right_keep=z)
        | collect_to(work._pipe_out3)
        , use_views=0
        , cleanup=1
      );

      %let _pp_n=%sysfunc(countw(%superq(_pp_steps), |, m));
      %assertEqual(&_pp_n., 3);
      %assertEqual(&_pp_use_views., 0);
      %assertEqual(&_pp_cleanup., 1);
    %test_summary;

    %test_case(split parmbuff segments);
      %_pipe_split_parmbuff_segments(
        buf=%str(steps=filter(x>1), data=work._pipe_in, out=work._pipe_out),
        out_n=_pb_n,
        out_prefix=_pb_seg
      );
      %assertEqual(&_pb_n., 3);
      %assertEqual(&_pb_seg1., steps=filter(x>1));
      %assertEqual(&_pb_seg2., data=work._pipe_in);
      %assertEqual(&_pb_seg3., out=work._pipe_out);
    %test_summary;

    %test_case(parse steps with equals);
      %_pipe_parse_parmbuff_test(
        steps=filter(x > 1) | mutate(y = x * 2) | select(x y),
        data=work._pipe_in,
        out=work._pipe_out,
        use_views=0,
        cleanup=1
      );

      %let _pp_n2=%sysfunc(countw(%superq(_pp_steps), |, m));
      %assertEqual(&_pp_n2., 3);
      %assertEqual(&_pp_data., work._pipe_in);
      %assertEqual(&_pp_out., work._pipe_out);
    %test_summary;

    %test_case(infer data and collect_to);
      %_pipe_infer_data(
        steps_in=%str(work._pipe_in | select(x)),
        data_in=,
        out_steps=_pd_steps,
        out_data=_pd_data
      );
      %assertEqual(&_pd_data., work._pipe_in);
      %assertEqual(&_pd_steps., select(x));

      %_pipe_extract_collect_out(
        steps_in=%str(select(x) | collect_to(work._pipe_outx)),
        out_in=,
        out_steps=_pc_steps,
        out_out=_pc_out,
        out_collect_out=_pc_collect
      );
      %assertEqual(&_pc_out., work._pipe_outx);
      %assertEqual(&_pc_steps., select(x));
    %test_summary;

    %test_case(infer helper steps);
      %_pipe_first_step(steps=%str(work._pipe_in | select(x)), out_step=_fi_step);
      %_pipe_is_data_step(step=&_fi_step, out_is=_fi_is);
      %_pipe_steps_without_first(steps=%str(work._pipe_in | select(x)), out_steps=_fi_rest);
      %assertEqual(&_fi_step., work._pipe_in);
      %assertEqual(&_fi_is., 1);
      %assertEqual(&_fi_rest., select(x));

      %_pipe_first_step(steps=%str(filter(x > 1) | select(x)), out_step=_fi_step);
      %_pipe_is_data_step(step=&_fi_step, out_is=_fi_is);
      %assertEqual(&_fi_is., 0);
    %test_summary;

    %test_case(helper outputs safe with locals);
      %local steps_out data_out out_out collect_out;
      %let _steps=%str(decfile.policy_lookup | select(sb_policy_key) | collect_to(policy_keys));

      %_pipe_infer_data(
        steps_in=&_steps,
        data_in=,
        out_steps=steps_out,
        out_data=data_out
      );

      %_pipe_extract_collect_out(
        steps_in=&steps_out,
        out_in=,
        out_steps=steps_out,
        out_out=out_out,
        out_collect_out=collect_out
      );

      %put NOTE: pipe helper debug data_out=&data_out steps_out=&steps_out out_out=&out_out collect_out=&collect_out.;

      %assertEqual(&data_out., decfile.policy_lookup);
      %assertEqual(&collect_out., policy_keys);
      %assertEqual(&out_out., policy_keys);
      %assertEqual(&steps_out., select(sb_policy_key));
    %test_summary;

    %test_case(collect detection trims trailing paren and sets outputs);
      %local last_step last_verb is_collect args_out steps_out2 out_out2 collect_out2;
      %let last_step=%str(collect_to(policy_keys));

      %let last_verb=%upcase(%scan(%superq(last_step), 1, %str(%())));
      %if %qsubstr(%superq(last_verb), %length(%superq(last_verb)), 1)=) %then
        %let last_verb=%substr(%superq(last_verb), 1, %eval(%length(%superq(last_verb))-1));

      %_pipe_is_collect_verb(verb=&last_verb, out_is=is_collect);
      %_pipe_collect_args(step=%superq(last_step), out_args=args_out);

      %_pipe_extract_collect_out(
        steps_in=%str(select(x) | collect_to(policy_keys)),
        out_in=,
        out_steps=steps_out2,
        out_out=out_out2,
        out_collect_out=collect_out2
      );

      %put NOTE: collect detect debug last_verb=&last_verb is_collect=&is_collect args_out=&args_out steps_out2=&steps_out2 out_out2=&out_out2 collect_out2=&collect_out2.;

      %assertEqual(&is_collect., 1);
      %assertEqual(&args_out., policy_keys);
      %assertEqual(&collect_out2., policy_keys);
      %assertEqual(&out_out2., policy_keys);
      %assertEqual(&steps_out2., select(x));
    %test_summary;

    %test_case(parse collect_to without out= and ensure out_out populated);
      %local steps_work data_work out_work collect_out_work;

      %_pipe_parse_parmbuff(
        steps_in=%str(select(sb_policy_key) | collect_to(policy_keys)),
        data_in=decfile.policy_lookup,
        out_in=,
        validate_in=1,
        use_views_in=1,
        view_output_in=0,
        debug_in=0,
        cleanup_in=1,
        out_steps=steps_work,
        out_data=data_work,
        out_out=out_work,
        out_validate=validate_work,
        out_use_views=use_views_work,
        out_view_output=view_output_work,
        out_debug=debug_work,
        out_cleanup=cleanup_work
      );

      %_pipe_extract_collect_out(
        steps_in=%superq(steps_work),
        out_in=%superq(out_work),
        out_steps=steps_work,
        out_out=out_work,
        out_collect_out=collect_out_work
      );

      %put NOTE: collect regression debug steps_work=&steps_work out_work=&out_work collect_out_work=&collect_out_work data_work=&data_work.;

      %assertEqual(&steps_work., select(sb_policy_key));
      %assertEqual(&collect_out_work., policy_keys);
      %assertEqual(&out_work., policy_keys);
      %assertEqual(&data_work., decfile.policy_lookup);
    %test_summary;

    %test_case(strip control chars in steps and out names);
      %local steps_dirty steps_clean data_clean out_clean collect_out_clean validate_clean use_views_clean view_output_clean debug_clean cleanup_clean _pc_clean_cnt;

      data work._pc_clean_in;
        length sb_policy_key 8;
        sb_policy_key=1; output;
        sb_policy_key=2; output;
      run;

      data _null_;
        length s $200;
        s = 'select(sb_policy_key)' || byte(6) || ' | collect_to(policy_keys)' || byte(8);
        call symputx('steps_dirty', s, 'G');
      run;

      %_pipe_parse_parmbuff(
        steps_in=%superq(steps_dirty),
        data_in=work._pc_clean_in,
        out_in=,
        validate_in=1,
        use_views_in=0,
        view_output_in=0,
        debug_in=0,
        cleanup_in=1,
        out_steps=steps_clean,
        out_data=data_clean,
        out_out=out_clean,
        out_validate=validate_clean,
        out_use_views=use_views_clean,
        out_view_output=view_output_clean,
        out_debug=debug_clean,
        out_cleanup=cleanup_clean
      );

      %_pipe_infer_data(
        steps_in=%superq(steps_clean),
        data_in=%superq(data_clean),
        out_steps=steps_clean,
        out_data=data_clean
      );

      %_pipe_extract_collect_out(
        steps_in=%superq(steps_clean),
        out_in=%superq(out_clean),
        out_steps=steps_clean,
        out_out=out_clean,
        out_collect_out=collect_out_clean
      );

      %assertEqual(&steps_clean., select(sb_policy_key));
      %assertEqual(&out_clean., policy_keys);
      %assertEqual(&collect_out_clean., policy_keys);

      %_pipe_execute(
        steps=%superq(steps_clean),
        data=&data_clean,
        out=&out_clean,
        validate=1,
        use_views=0,
        view_output=0,
        debug=0,
        cleanup=1
      );

      proc sql noprint;
        select count(*) into :_pc_clean_cnt trimmed from work.policy_keys;
      quit;

      %assertEqual(&_pc_clean_cnt., 2);

      proc datasets lib=work nolist; delete _pc_clean_in policy_keys; quit;
    %test_summary;

    %test_case(step helpers and planning);
      %_pipe_steps_count(steps=%str(a() | b() | c()), out_n=_ps_n);
      %assertEqual(&_ps_n., 3);

      %_pipe_get_step(steps=%str(a() | b() | c()), index=2, out_step=_ps_step);
      %assertEqual(&_ps_step., b());

      %_pipe_plan_step(
        i=1,
        n=3,
        out=work._final,
        tmp1=work._t1,
        tmp2=work._t2,
        use_views=0,
        view_output=0,
        supports_view=1,
        out_as_view=_ps_as_view,
        out_next=_ps_next
      );
      %assertEqual(&_ps_as_view., 0);
      %assertEqual(&_ps_next., work._t1);

      %_pipe_plan_step(
        i=3,
        n=3,
        out=work._final,
        tmp1=work._t1,
        tmp2=work._t2,
        use_views=1,
        view_output=1,
        supports_view=1,
        out_as_view=_ps_as_view,
        out_next=_ps_next
      );
      %assertEqual(&_ps_as_view., 1);
      %assertEqual(&_ps_next., work._final);
    %test_summary;

    %test_case(collect helpers parsing);
      %_pipe_get_last_step(steps=%str(a() | collect_to(work._out)), out_last=_pl_last, out_n=_pl_n);
      %assertEqual(&_pl_n., 2);
      %assertEqual(&_pl_last., collect_to(work._out));

      %_pipe_is_collect_verb(verb=collect_to, out_is=_pl_is);
      %assertTrue(%eval(&_pl_is > 0), collect_to identified);

      %_pipe_collect_args(step=%str(collect_to(work._out)), out_args=_pl_args);
      %assertEqual(&_pl_args., work._out);

      %_pipe_is_collect_verb(verb=collect_into, out_is=_pl_is2);
      %assertTrue(%eval(&_pl_is2 > 0), collect_into identified);

      %_pipe_get_last_step(steps=%str(a() | collect_into(work._out2)), out_last=_pl_last2, out_n=_pl_n2);
      %assertEqual(&_pl_n2., 2);
      %assertEqual(&_pl_last2., collect_into(work._out2));
    %test_summary;

    %test_case(execute and cleanup helpers);
      data work._pe_in;
        x=1; output;
        x=2; output;
        x=3; output;
      run;

      %_pipe_execute_step(
        step=%str(filter(x > 1)),
        i=1,
        n=1,
        cur=work._pe_in,
        out=work._pe_out,
        tmp1=work._pe_t1,
        tmp2=work._pe_t2,
        use_views=0,
        view_output=0,
        debug=0,
        validate=1,
        out_next=_pe_next
      );

      %assertEqual(&_pe_next., work._pe_out);
      %assertTrue(%eval(%sysfunc(exist(work._pe_out))=1), execute step created output);

      proc sql noprint;
        select count(*) into :_pe_cnt trimmed from work._pe_out;
      quit;
      %assertEqual(&_pe_cnt., 2);

      data work._pc_t1; x=1; run;
      data work._pc_t2; x=1; run;
      %_pipe_cleanup_temps(tmp1=work._pc_t1, tmp2=work._pc_t2, out=work._pc_out, cleanup=1);
      %assertEqual(%sysfunc(exist(work._pc_t1)), 0);
      %assertEqual(%sysfunc(exist(work._pc_t2)), 0);
    %test_summary;

    %test_case(plan serialize and deserialize roundtrip);
      %local _plan_text;
      %_pipe_plan_build(
        steps=%str(filter(x > 1) | mutate(y = x * 2) | select(x y)),
        data=work._pe_in
      );
      %_pipe_plan_serialize(out_plan=_plan_text);

      %_pipe_plan_reset(data=work._placeholder);
      %_pipe_plan_deserialize(plan=%superq(_plan_text));

      %assertEqual(&_pipe_plan_data., work._pe_in);
      %assertEqual(&_pipe_plan_keep., x y);
      %assertEqual(&_pipe_plan_supported., 1);
      %assertTrue(%eval(%length(%superq(_pipe_plan_stmt)) > 0), stmt was restored);
      %assertTrue(%eval(%length(%superq(_pipe_plan_where)) > 0), where was restored);
    %test_summary;

    %test_case(plan replay executes serialized plan);
      %local _replay_plan;
      data work._pr_in;
        x=1; output;
        x=2; output;
        x=3; output;
      run;

      %_pipe_plan_build(
        steps=%str(filter(x > 1) | mutate(y = x * 10) | select(x y)),
        data=work._pr_in
      );
      %_pipe_plan_serialize(out_plan=_replay_plan);
      %_pipe_plan_replay(plan=%superq(_replay_plan), out=work._pr_out, as_view=0);

      proc sql noprint;
        select count(*) into :_pr_cnt trimmed from work._pr_out;
        select sum(y) into :_pr_sumy trimmed from work._pr_out;
      quit;

      %assertEqual(&_pr_cnt., 2);
      %assertEqual(&_pr_sumy., 50);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _pe_in _pe_out _pe_t1 _pe_t2 _pc_t1 _pc_t2 _pr_in _pr_out; quit;
%mend;

%macro test_pipe;
  %_pipr_require_assert;
  %local _sel_pipe_cols;

  %test_suite(Testing pipe);
    %test_case(simple pipeline with filter/mutate/select);
      data work._pipe_in;
        x=1; output;
        x=2; output;
        x=3; output;
      run;

      %pipe(
        work._pipe_in
        | filter(x > 1)
        | mutate(y = x * 2)
        | select(x y)
        | collect_to(work._pipe_out)
        , use_views=0,
        cleanup=1
      );

      proc sql noprint;
        select count(*) into :_cnt trimmed from work._pipe_out;
        select sum(y) into :_sum_y trimmed from work._pipe_out;
      quit;

      %assertEqual(&_cnt., 2);
      %assertEqual(&_sum_y., 10);
    %test_summary;

    %test_case(pipe supports view_output=1 on final step);
      %pipe(
        work._pipe_in
        | select(x)
        | collect_to(work._pipe_out_view_final)
        , use_views=1,
        view_output=1,
        debug=1,
        cleanup=1
      );

      %assertEqual(%sysfunc(exist(work._pipe_out_view_final, view)), 1);
      proc sql noprint;
        select count(*) into :_cnt_view_final trimmed from work._pipe_out_view_final;
      quit;
      %assertEqual(&_cnt_view_final., 3);
    %test_summary;

    %test_case(default use_views pipeline supports select then collect_to);
      data work._pipe_view_in;
        sb_policy_key=11; output;
        sb_policy_key=22; output;
      run;

      %pipe(
        work._pipe_view_in
        | select(sb_policy_key)
        | collect_to(work._pipe_view_out)
      );

      proc sql noprint;
        select count(*) into :_pipe_view_cnt trimmed from work._pipe_view_out;
      quit;

      %assertEqual(&_pipe_view_cnt., 2);
    %test_summary;

    %test_case(pipe supports drop_duplicates with lazy view output);
      data work._pipe_dup_in;
        id=1; output;
        id=1; output;
        id=2; output;
      run;

      %pipe(
        work._pipe_dup_in
        | drop_duplicates()
        | collect_to(work._pipe_dup_out_view)
        , use_views=1,
        view_output=1,
        cleanup=1
      );

      %assertEqual(%sysfunc(exist(work._pipe_dup_out_view, view)), 1);
      proc sql noprint;
        select count(*) into :_pipe_dup_cnt trimmed from work._pipe_dup_out_view;
      quit;
      %assertEqual(&_pipe_dup_cnt., 2);
    %test_summary;

    %test_case(pipe supports select positional commas then bare drop_duplicates);
      data work._pipe_keys_in;
        sb_policy_key=11; experian_bin=700; payload=1; output;
        sb_policy_key=11; experian_bin=700; payload=2; output;
        sb_policy_key=22; experian_bin=680; payload=3; output;
      run;

      %pipe(
        work._pipe_keys_in
        | select(sb_policy_key, experian_bin)
        | drop_duplicates
        | collect_to(work._pipe_keys_out)
        , use_views=0
        , cleanup=1
      );

      proc sql noprint;
        select count(*) into :_pipe_keys_cnt trimmed from work._pipe_keys_out;
        select upcase(name) into :_pipe_keys_cols separated by ' '
        from sashelp.vcolumn
        where libname='WORK' and memname='_PIPE_KEYS_OUT'
        order by varnum;
      quit;

      %assertEqual(&_pipe_keys_cnt., 2);
      %assertEqual(&_pipe_keys_cols., SB_POLICY_KEY EXPERIAN_BIN);
    %test_summary;

    %test_case(%nrstr(mutate with comma-based function expression without explicit %str));
      %pipe(
        work._pipe_in
        | mutate(flag = ifc(x > 2, 1, 0))
        | collect_to(work._pipe_out_ifc)
        , use_views=0,
        cleanup=1
      );

      proc sql noprint;
        select sum(flag) into :_sum_flag trimmed from work._pipe_out_ifc;
      quit;

      %assertEqual(&_sum_flag., 1);
    %test_summary;

    %test_case(mutate supports comma-delimited assignments in pipe);
      %pipe(
        work._pipe_in
        | mutate(a = x + 1, b = a * 2)
        | collect_to(work._pipe_out_multi)
        , use_views=0,
        cleanup=1
      );

      proc sql noprint;
        select sum(b) into :_sum_b_multi trimmed from work._pipe_out_multi;
      quit;

      %assertEqual(&_sum_b_multi., 18);
    %test_summary;

    %test_case(mutate supports compact comma-delimited assignments in pipe);
      %pipe(
        work._pipe_in
        | mutate(a=x+1,b=a*2)
        | collect_to(work._pipe_out_multi_compact)
        , use_views=0,
        cleanup=1
      );

      proc sql noprint;
        select sum(b) into :_sum_b_multi_compact trimmed from work._pipe_out_multi_compact;
      quit;

      %assertEqual(&_sum_b_multi_compact., 18);
    %test_summary;

    %test_case(pipe supports bare predicate helpers in filter and mutate);
      data work._pipe_pred;
        a=1; b=0; c=.; output;
        a=2; b=3; c=4; output;
        a=.; b=.; c=.; output;
      run;

      %pipe(
        work._pipe_pred
        | filter(if_any(cols=a b c, pred=is_zero()))
        | collect_to(work._pipe_pred_out)
        , use_views=0,
        cleanup=1
      );

      proc sql noprint;
        select count(*) into :_pipe_pred_n trimmed from work._pipe_pred_out;
      quit;
      %assertEqual(&_pipe_pred_n., 1);

      %pipe(
        work._pipe_in
        | mutate(flag = is_positive(x), in_2_3 = is_between(x, 2, 3))
        | collect_to(work._pipe_mut_pred)
        , use_views=0,
        cleanup=1
      );
      proc sql noprint;
        select sum(flag) into :_pipe_sum_flag trimmed from work._pipe_mut_pred;
        select sum(in_2_3) into :_pipe_sum_in_2_3 trimmed from work._pipe_mut_pred;
      quit;
      %assertEqual(&_pipe_sum_flag., 2);
      %assertEqual(&_pipe_sum_in_2_3., 1);
    %test_summary;

    %test_case(with_column supports mutate-style assignments in pipe);
      %pipe(
        work._pipe_in
        | with_column(a = x + 1, b = a * 2)
        | collect_to(work._pipe_out_wc_multi)
        , use_views=0,
        cleanup=1
      );

      proc sql noprint;
        select sum(b) into :_sum_b_wc_multi trimmed from work._pipe_out_wc_multi;
      quit;

      %assertEqual(&_sum_b_wc_multi., 18);
    %test_summary;

    %test_case(positional steps with collect_to);
      %pipe(
        work._pipe_in
        | filter(x > 1)
        | mutate(y = x * 2)
        | collect_to(work._pipe_out2)
        , use_views=0
        , cleanup=1
      );

      proc sql noprint;
        select count(*) into :_cnt2 trimmed from work._pipe_out2;
        select sum(y) into :_sum_y2 trimmed from work._pipe_out2;
      quit;

      %assertEqual(&_cnt2., 2);
      %assertEqual(&_sum_y2., 10);
    %test_summary;

    %test_case(positional steps with comma args);
      data work._pipe_right;
        id=1; z=5; output;
        id=2; z=6; output;
      run;

      data work._pipe_in2;
        id=1; x=10; output;
        id=2; x=20; output;
      run;

      %pipe(
        work._pipe_in2
        | left_join(right=work._pipe_right, on=id, right_keep=z)
        | collect_to(work._pipe_out3)
        , use_views=0
        , cleanup=1
      );

      proc sql noprint;
        select sum(z) into :_sum_z trimmed from work._pipe_out3;
      quit;

      %assertEqual(&_sum_z., 11);
    %test_summary;

    %test_case(string booleans are normalized);
      data work._pipe_bool_in;
        x=1; output;
        x=2; output;
        x=3; output;
      run;

      %pipe(
        work._pipe_bool_in
        | filter(x > 1)
        | collect_to(work._pipe_bool_out)
        , validate=TRUE,
        use_views=NO,
        cleanup=YES
      );

      proc sql noprint;
        select count(*) into :_cnt_bool trimmed from work._pipe_bool_out;
      quit;

      %assertEqual(&_cnt_bool., 2);
    %test_summary;

    %test_case(select supports selector expressions in pipe);
      data work._pipe_sel;
        length policy_id 8 policy_type $12 company_numb 8 state_code $8 home_code $8 home_state $2 other 8;
        policy_id=1;
        policy_type='A';
        company_numb=99;
        state_code='S1';
        home_code='H1';
        home_state='CA';
        other=5;
        output;
      run;

      %pipe(
        work._pipe_sel
        | select(starts_with('policy') company_numb ends_with('code') like('%state%'))
        | collect_into(work._pipe_sel_out)
        , use_views=0
        , cleanup=1
      );

      proc sql noprint;
        select upcase(name) into :_sel_pipe_cols separated by ' '
        from sashelp.vcolumn
        where libname="WORK" and memname="_PIPE_SEL_OUT"
        order by varnum;
      quit;

      %assertEqual(
        &_sel_pipe_cols.,
        POLICY_ID POLICY_TYPE COMPANY_NUMB STATE_CODE HOME_CODE HOME_STATE
      );
    %test_summary;

    %test_case(matches and cols_where selectors in pipe);
      data work._pipe_sel;
        length policy_id 8 policy_type $12 company_numb 8 state_code $8 home_code $8 home_state $2 other 8;
        policy_id=1;
        policy_type='A';
        company_numb=99;
        state_code='S1';
        home_code='H1';
        home_state='CA';
        other=5;
        output;
      run;

      %pipe(
        work._pipe_sel
        | select(matches('state$') cols_where(~.is_num))
        | collect_into(work._pipe_sel_out2)
        , use_views=0
        , cleanup=1
      );

      proc sql noprint;
        select upcase(name) into :_sel_pipe_cols2 separated by ' '
        from sashelp.vcolumn
        where libname="WORK" and memname="_PIPE_SEL_OUT2"
        order by varnum;
      quit;

      %assertEqual(
        &_sel_pipe_cols2.,
        HOME_STATE POLICY_ID COMPANY_NUMB OTHER
      );
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist;
    delete _pipe_in _pipe_out _pipe_view_in _pipe_view_out _pipe_out_ifc _pipe_out_multi _pipe_out_multi_compact _pipe_pred _pipe_pred_out _pipe_mut_pred _pipe_out_wc_multi _pipe_out2 _pipe_right _pipe_in2 _pipe_out3 _pipe_bool_in _pipe_bool_out _pipe_sel _pipe_sel_out _pipe_sel_out2 _pipe_dup_in _pipe_keys_in _pipe_keys_out;
    delete _pipe_out_view_final _pipe_dup_out_view / memtype=view;
  quit;
%mend test_pipe;

%_pipr_autorun_tests(test_pipe_helpers);
%_pipr_autorun_tests(test_pipe);
