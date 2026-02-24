/* MODULE DOC
File: src/pipr/plan.sas

1) Purpose in overall project
- Central planner state/logic for pipe() lazy planning, serialization, replay, and optimizer hooks.

2) High-level approach
- Build a normalized plan from pipe steps, keep planner state in one module, and provide helpers to serialize/deserialize/replay plans.

3) Code organization and why this scheme was chosen
- Planner state mutators, build/apply, optimizer hooks, and replay helpers are grouped here to keep pipr.sas focused on orchestration.

4) Detailed pseudocode algorithm
- Reset planner state for a source dataset.
- For each step: parse verb/args and fold into plan fields when supported.
- Mark unsupported steps for fallback execution.
- Optionally run registered optimizer hooks over plan globals.
- Serialize plan to transportable text for logs/replay.
- Rehydrate serialized plan and execute one data-step builder output.

5) Acknowledged implementation deficits
- Serialized format is key-value text and not a strict JSON schema.
- Optimizer hook API is macro-based and intentionally minimal for portability.

6) Macros defined in this file
- _pipe_plan_reset
- _pipe_plan_add_where
- _pipe_plan_set_keep
- _pipe_plan_set_drop
- _pipe_plan_set_rename
- _pipe_plan_set_stmt
- _pipe_plan_mark_unsupported
- _pipe_plan_apply_step
- _pipe_plan_opt_register
- _pipe_plan_opt_apply
- _pipe_plan_build
- _pipe_plan_log
- _pipe_plan_set_options
- _pipe_data_step_builder_emit
- _pipe_plan_execute
- _pipe_plan_get_stmt
- _pipe_plan_serialize
- _pipe_plan_deserialize
- _pipe_plan_replay

7) Expected side effects from running/include
- Defines planner helper macros and global planner state variables.
*/
%if not %sysmacexist(_abort) %then %do;
  %put ERROR: plan.sas requires pipr util macros (_abort missing). Load via sassyverse_init(include_pipr=1).;
  %abort cancel;
%end;

%macro _pipe_plan_reset(data=);
  %global _pipe_plan_data _pipe_plan_keep _pipe_plan_drop _pipe_plan_rename _pipe_plan_where _pipe_plan_stmt;
  %global _pipe_plan_supported _pipe_plan_unsupported_steps _pipe_plan_optimizer_macros;
  %let _pipe_plan_data=%superq(data);
  %let _pipe_plan_keep=;
  %let _pipe_plan_drop=;
  %let _pipe_plan_rename=;
  %let _pipe_plan_where=;
  %let _pipe_plan_stmt=;
  %let _pipe_plan_supported=1;
  %let _pipe_plan_unsupported_steps=;
  %if not %symexist(_pipe_plan_optimizer_macros) %then %let _pipe_plan_optimizer_macros=;
%mend;

%macro _pipe_plan_add_where(expr=);
  %local _expr;
  %let _expr=%sysfunc(strip(%superq(expr)));
  %if %length(%superq(_expr))=0 %then %return;
  %if %length(%superq(_pipe_plan_where))=0 %then %let _pipe_plan_where=(%superq(_expr));
  %else %let _pipe_plan_where=%superq(_pipe_plan_where) and (%superq(_expr));
%mend;

%macro _pipe_plan_add_filter(expr=);
  %local _expr _stmt;
  %let _expr=%sysfunc(strip(%superq(expr)));
  %if %length(%superq(_expr))=0 %then %return;
  %if %length(%superq(_pipe_plan_stmt))=0 %then %_pipe_plan_add_where(expr=%superq(_expr));
  %else %do;
    %let _stmt=if not (%superq(_expr)) then delete;
    %_pipe_plan_set_stmt(stmt=%superq(_stmt));
  %end;
%mend;

%macro _pipe_plan_set_keep(cols=);
  %local _cols;
  %let _cols=%superq(cols);
  %if %sysmacexist(_pipr_normalize_list) %then %do;
    %_pipr_normalize_list(text=%superq(_cols), collapse_commas=1);
    %let _cols=%superq(_pipr_norm_out);
  %end;
  %let _pipe_plan_keep=%superq(_cols);
%mend;

%macro _pipe_plan_set_drop(cols=);
  %local _cols;
  %let _cols=%superq(cols);
  %if %sysmacexist(_pipr_normalize_list) %then %do;
    %_pipr_normalize_list(text=%superq(_cols), collapse_commas=1);
    %let _cols=%superq(_pipr_norm_out);
  %end;
  %let _pipe_plan_drop=%superq(_cols);
%mend;

%macro _pipe_plan_set_rename(pairs=);
  %local _old _map;
  %if %sysmacexist(_rename_parse_pairs) %then %do;
    %_rename_parse_pairs(%superq(pairs), _old, _map);
    %let _pipe_plan_rename=%superq(_map);
  %end;
  %else %let _pipe_plan_rename=%superq(pairs);
%mend;

%macro _pipe_plan_set_stmt(stmt=);
  %if %length(%superq(_pipe_plan_stmt))=0 %then %let _pipe_plan_stmt=%superq(stmt);
  %else %let _pipe_plan_stmt=%superq(_pipe_plan_stmt) %superq(stmt);
%mend;

%macro _pipe_plan_mark_unsupported(step=);
  %let _pipe_plan_supported=0;
  %if %length(%superq(_pipe_plan_unsupported_steps))=0 %then %let _pipe_plan_unsupported_steps=%superq(step);
  %else %let _pipe_plan_unsupported_steps=%superq(_pipe_plan_unsupported_steps) | %superq(step);
%mend;

%macro _pipe_plan_apply_step(step=);
  %local _verb _args _verb_uc _expr _stmt _last;
  %_step_parse(%superq(step), _verb, _args);
  %let _verb_uc=%upcase(%superq(_verb));

  %if &_verb_uc=SELECT or &_verb_uc=KEEP %then %do;
    %if %index(%superq(_args), %str(%()) > 0 %then %_pipe_plan_mark_unsupported(step=%superq(step));
    %else %_pipe_plan_set_keep(cols=%superq(_args));
  %end;
  %else %if &_verb_uc=DROP %then %_pipe_plan_set_drop(cols=%superq(_args));
  %else %if &_verb_uc=RENAME %then %_pipe_plan_set_rename(pairs=%superq(_args));
  %else %if &_verb_uc=FILTER or &_verb_uc=WHERE %then %do;
    %if %sysmacexist(_filter_expand_where) %then %_filter_expand_where(where_expr=%superq(_args), out_where=_expr);
    %else %let _expr=%superq(_args);
    %_pipe_plan_add_filter(expr=%superq(_expr));
  %end;
  %else %if &_verb_uc=WHERE_NOT or &_verb_uc=MASK %then %do;
    %if %sysmacexist(_filter_expand_where) %then %_filter_expand_where(where_expr=%superq(_args), out_where=_expr);
    %else %let _expr=%superq(_args);
    %_pipe_plan_add_filter(expr=not (%superq(_expr)));
  %end;
  %else %if &_verb_uc=MUTATE or &_verb_uc=WITH_COLUMN %then %do;
    %if %sysmacexist(_mutate_normalize_stmt) %then %_mutate_normalize_stmt(%superq(_args), _stmt);
    %else %let _stmt=%superq(_args);
    %if %sysmacexist(_mutate_expand_functions) %then %_mutate_expand_functions(stmt=%superq(_stmt), out_stmt=_stmt);
    %if %length(%superq(_stmt)) > 0 %then %do;
      %let _last=%qsubstr(%superq(_stmt), %length(%superq(_stmt)), 1);
      %if %superq(_last) ne %str(;) %then %let _stmt=%superq(_stmt)%str(;);
      %_pipe_plan_set_stmt(stmt=%superq(_stmt));
    %end;
  %end;
  %else %_pipe_plan_mark_unsupported(step=%superq(step));
%mend;

%macro _pipe_plan_opt_register(name=, macro=);
  %local _macro;
  %if %length(%superq(macro))=0 %then %return;
  %let _macro=%sysfunc(strip(%superq(macro)));
  %if %indexw(%upcase(%superq(_pipe_plan_optimizer_macros)), %upcase(%superq(_macro)), %str( ))=0 %then %do;
    %if %length(%superq(_pipe_plan_optimizer_macros))=0 %then %let _pipe_plan_optimizer_macros=%superq(_macro);
    %else %let _pipe_plan_optimizer_macros=%superq(_pipe_plan_optimizer_macros) %superq(_macro);
  %end;
%mend;

%macro _pipe_plan_opt_apply;
  %local _n _i _opt;
  %if not %symexist(_pipe_plan_optimizer_macros) %then %return;
  %let _n=%sysfunc(countw(%superq(_pipe_plan_optimizer_macros), %str( )));
  %do _i=1 %to &_n;
    %let _opt=%scan(%superq(_pipe_plan_optimizer_macros), &_i, %str( ));
    %if %sysmacexist(&_opt) %then %do;
      %&_opt;
    %end;
    %else %put WARNING: [PIPE.PLAN] optimizer macro %superq(_opt) is not defined.;
  %end;
%mend;

%macro _pipe_plan_build(steps=, data=);
  %local _n _i _step;
  %if not %sysmacexist(_step_parse) %then %_abort(_pipe_plan_build() requires _step_parse. Load pipr/_verbs/utils.sas or call sassyverse_init(include_pipr=1).);
  %_pipe_plan_reset(data=%superq(data));
  %_pipe_steps_count(steps=%superq(steps), out_n=_n);
  %do _i=1 %to &_n;
    %_pipe_get_step(steps=%superq(steps), index=&_i, out_step=_step);
    %if %length(%superq(_step)) %then %_pipe_plan_apply_step(step=%superq(_step));
  %end;
  %_pipe_plan_opt_apply;
%mend;

%macro _pipe_plan_log(collect_out=, out=);
  %put NOTE: [PIPE.PLAN] source=%superq(_pipe_plan_data);
  %put NOTE: [PIPE.PLAN] keep=%superq(_pipe_plan_keep);
  %put NOTE: [PIPE.PLAN] drop=%superq(_pipe_plan_drop);
  %put NOTE: [PIPE.PLAN] rename=%superq(_pipe_plan_rename);
  %put NOTE: [PIPE.PLAN] where=%superq(_pipe_plan_where);
  %put NOTE: [PIPE.PLAN] stmt=%superq(_pipe_plan_stmt);
  %put NOTE: [PIPE.PLAN] supported=%superq(_pipe_plan_supported);
  %if %length(%superq(_pipe_plan_unsupported_steps)) %then %put NOTE: [PIPE.PLAN] unsupported_steps=%superq(_pipe_plan_unsupported_steps);
  %if %length(%superq(collect_out)) %then %put NOTE: [PIPE.PLAN] collect_out=%superq(collect_out) (execute enabled);
  %else %put NOTE: [PIPE.PLAN] no collect step found (plan only; not executing).;
  %if %length(%superq(out)) %then %put NOTE: [PIPE.PLAN] out=%superq(out);
%mend;

%macro _pipe_plan_set_options(out_opts=);
  %local _opts;
  %let _opts=;
  %if %length(%superq(_pipe_plan_keep)) %then %let _opts=&_opts keep=%superq(_pipe_plan_keep);
  %if %length(%superq(_pipe_plan_drop)) %then %let _opts=&_opts drop=%superq(_pipe_plan_drop);
  %if %length(%superq(_pipe_plan_rename)) %then %let _opts=&_opts rename=(%superq(_pipe_plan_rename));
  %if %length(%superq(_pipe_plan_where)) %then %let _opts=&_opts where=(%superq(_pipe_plan_where));
  %let _opts=%sysfunc(compbl(%superq(_opts)));
  %_pipr_ucl_assign(out_text=%superq(out_opts), value=%superq(_opts));
%mend;

%macro _pipe_data_step_builder_emit(data=, out=, set_opts=, stmt=, as_view=0);
  data &out
    %if &as_view %then / view=&out;
  ;
    set &data %if %length(%superq(set_opts)) %then (%superq(set_opts));;
    %if %length(%superq(stmt)) %then %do;
      %unquote(%superq(stmt))
    %end;
  run;
%mend;

%macro _pipe_plan_execute(data=, out=, stmt=, as_view=0);
  %local _set_opts;
  %_pipe_plan_set_options(out_opts=_set_opts);
  %_pipe_data_step_builder_emit(data=%superq(data), out=%superq(out), set_opts=%superq(_set_opts), stmt=%superq(stmt), as_view=&as_view);
  %if &syserr > 4 %then %_abort(pipe() plan execution failed (SYSERR=&syserr).);
%mend;

%macro _pipe_plan_get_stmt(out_stmt=);
  %_pipr_ucl_assign(out_text=%superq(out_stmt), value=%superq(_pipe_plan_stmt));
%mend;

%macro _pipe_plan_escape(value=, out=);
  %local _in _out;
  %let _in=%superq(value);
  data _null_;
    length raw esc ch $32767;
    raw = symget('_in');
    esc = '';
    do _i = 1 to length(raw);
      ch = substr(raw, _i, 1);
      if ch = '^' then esc = cats(esc, '^^');
      else if ch = '|' then esc = cats(esc, '^p');
      else if ch = '=' then esc = cats(esc, '^e');
      else esc = cats(esc, ch);
    end;
    call symputx('_out', esc, 'L');
  run;
  %_pipr_ucl_assign(out_text=%superq(out), value=%superq(_out));
%mend;

%macro _pipe_plan_unescape(value=, out=);
  %local _in _out;
  %let _in=%superq(value);
  data _null_;
    length raw txt ch nxt $32767;
    raw = symget('_in');
    txt = '';
    i = 1;
    do while (i <= length(raw));
      ch = substr(raw, i, 1);
      if ch = '^' and i < length(raw) then do;
        nxt = substr(raw, i + 1, 1);
        if nxt = '^' then txt = cats(txt, '^');
        else if lowcase(nxt) = 'p' then txt = cats(txt, '|');
        else if lowcase(nxt) = 'e' then txt = cats(txt, '=');
        else txt = cats(txt, '^', nxt);
        i + 2;
      end;
      else do;
        txt = cats(txt, ch);
        i + 1;
      end;
    end;
    call symputx('_out', txt, 'L');
  run;
  %_pipr_ucl_assign(out_text=%superq(out), value=%superq(_out));
%mend;

%macro _pipe_plan_serialize(out_plan=);
  %local _plan _data _keep _drop _rename _where _stmt _supported _unsupported;
  %_pipe_plan_escape(value=%superq(_pipe_plan_data), out=_data);
  %_pipe_plan_escape(value=%superq(_pipe_plan_keep), out=_keep);
  %_pipe_plan_escape(value=%superq(_pipe_plan_drop), out=_drop);
  %_pipe_plan_escape(value=%superq(_pipe_plan_rename), out=_rename);
  %_pipe_plan_escape(value=%superq(_pipe_plan_where), out=_where);
  %_pipe_plan_escape(value=%superq(_pipe_plan_stmt), out=_stmt);
  %_pipe_plan_escape(value=%superq(_pipe_plan_supported), out=_supported);
  %_pipe_plan_escape(value=%superq(_pipe_plan_unsupported_steps), out=_unsupported);

  %let _plan=data=%superq(_data)||keep=%superq(_keep)||drop=%superq(_drop)||rename=%superq(_rename)||where=%superq(_where)||stmt=%superq(_stmt)||supported=%superq(_supported)||unsupported=%superq(_unsupported);
  %_pipr_ucl_assign(out_text=%superq(out_plan), value=%superq(_plan));
%mend;

%macro _pipe_plan_deserialize(plan=);
  %local _n _i _seg _k _v _vu _eq;
  %_pipe_plan_reset(data=);
  %let _n=%sysfunc(countw(%superq(plan), ||, m));
  %do _i=1 %to &_n;
    %let _seg=%scan(%superq(plan), &_i, ||, m);
    %let _eq=%index(%superq(_seg), =);
    %if &_eq > 0 %then %do;
      %let _k=%upcase(%substr(%superq(_seg), 1, %eval(&_eq-1)));
      %let _v=%substr(%superq(_seg), %eval(&_eq+1));
      %_pipe_plan_unescape(value=%superq(_v), out=_vu);
      %if &_k=DATA %then %let _pipe_plan_data=%superq(_vu);
      %else %if &_k=KEEP %then %let _pipe_plan_keep=%superq(_vu);
      %else %if &_k=DROP %then %let _pipe_plan_drop=%superq(_vu);
      %else %if &_k=RENAME %then %let _pipe_plan_rename=%superq(_vu);
      %else %if &_k=WHERE %then %let _pipe_plan_where=%superq(_vu);
      %else %if &_k=STMT %then %let _pipe_plan_stmt=%superq(_vu);
      %else %if &_k=SUPPORTED %then %let _pipe_plan_supported=%superq(_vu);
      %else %if &_k=UNSUPPORTED %then %let _pipe_plan_unsupported_steps=%superq(_vu);
    %end;
  %end;
%mend;

%macro _pipe_plan_replay(plan=, out=, as_view=0);
  %local _stmt;
  %if %length(%superq(out))=0 %then %_abort(_pipe_plan_replay() requires out=.);
  %_pipe_plan_deserialize(plan=%superq(plan));
  %if %superq(_pipe_plan_supported) ne 1 %then %_abort(_pipe_plan_replay() supports only supported plans.);
  %_pipe_plan_get_stmt(out_stmt=_stmt);
  %_pipe_plan_execute(data=%superq(_pipe_plan_data), out=%superq(out), stmt=%superq(_stmt), as_view=&as_view);
%mend;
