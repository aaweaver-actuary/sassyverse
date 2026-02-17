/* MODULE DOC
File: src/pipr/_verbs/summarise.sas

1) Purpose in overall project
- Pipr verb implementations for table transformation steps (select/filter/mutate/join/etc.).

2) High-level approach
- Each verb macro normalizes inputs, validates required datasets/columns, and emits a DATA step/PROC implementation.

3) Code organization and why this scheme was chosen
- One file per verb keeps behavior isolated; shared helpers (validation/utils) prevent repeated parsing/dispatch logic.
- Code is organized as helper macros first, public API second, and tests/autorun guards last to reduce contributor onboarding time and import risk.

4) Detailed pseudocode algorithm
- Parse verb arguments (including parmbuff positional/named forms where supported).
- Validate source dataset and required columns when validate=1.
- Normalize expressions/selectors into executable SAS code.
- Emit DATA/PROC logic to produce output dataset or view.
- Return stable output target name so pipe executor can chain next step.
- Expose alias macros for ergonomic naming compatibility where needed.

5) Acknowledged implementation deficits
- Different verbs use different SAS backends (DATA step, PROC SQL, hash) which increases cognitive load.
- Advanced edge-case validation is still evolving for some argument combinations.
- Contributor docs are still text comments; there is no generated API reference yet.

6) Macros defined in this file
- _summarise_run
- summarise
- summarize
- test_summarise

7) Expected side effects from running/include
- Defines 4 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: _pipr_autorun_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
- When invoked, macros in this module can create or overwrite WORK datasets/views as part of pipeline operations.
*/
%macro _summarise_run(vars, stats, by=, data=, out=);
  proc summary data=&data nway;
    %if %length(%superq(by)) %then %do; class &by; %end;
    var &vars;
    output out=&out(drop=_type_ _freq_) &stats;
  run;
%mend;

%macro summarise(vars, by=, data=, out=, stats=, validate=1, as_view=0);
  %local _validate _as_view;
  %let _validate=%_pipr_bool(%superq(validate), default=1);
  %let _as_view=%_pipr_bool(%superq(as_view), default=0);
  %_assert_ds_exists(&data);
  %if %length(%superq(vars))=0 %then %_abort(summarise() requires vars=);
  %if %length(%superq(stats))=0 %then %_abort(summarise() requires stats=);
  %if &_as_view %then %_abort(summarise() does not support as_view=1);

  %if &_validate %then %do;
    %_assert_cols_exist(&data, &vars);
    %if %length(%superq(by)) %then %_assert_cols_exist(&data, &by);
  %end;

  %_summarise_run(vars=&vars, stats=&stats, by=&by, data=&data, out=&out);

  %if &syserr > 4 %then %_abort(summarise() failed (SYSERR=&syserr).);
%mend summarise;

%macro summarize(vars, by=, data=, out=, stats=, validate=1, as_view=0);
  %summarise(vars=&vars, by=&by, data=&data, out=&out, stats=&stats, validate=&validate, as_view=&as_view);
%mend summarize;

%macro test_summarise;
  %_pipr_require_assert;

  %test_suite(Testing summarise);
    %test_case(summarise aggregates by group);
      data work._sum;
        grp='A'; x=1; output;
        grp='A'; x=3; output;
        grp='B'; x=2; output;
      run;

      %summarise(
        vars=x,
        by=grp,
        data=work._sum,
        out=work._sum_out,
        stats=mean=avg sum=total
      );

      proc sql noprint;
        select avg into :_avg_a trimmed from work._sum_out where grp='A';
        select total into :_total_b trimmed from work._sum_out where grp='B';
      quit;

      %assertEqual(&_avg_a., 2);
      %assertEqual(&_total_b., 2);
    %test_summary;

    %test_case(summarize alias works);
      %summarize(
        vars=x,
        by=,
        data=work._sum,
        out=work._sum_out2,
        stats=mean=avg
      );

      proc sql noprint;
        select avg into :_avg_all trimmed from work._sum_out2;
      quit;

      %assertEqual(&_avg_all., 2);
    %test_summary;

    %test_case(summarise helper no by);
      %_summarise_run(vars=x, stats=sum=total, by=, data=work._sum, out=work._sum_helper);

      proc sql noprint;
        select total into :_total_helper trimmed from work._sum_helper;
      quit;

      %assertEqual(&_total_helper., 6);
    %test_summary;

    %test_case(summarise supports validate boolean flags);
      %summarise(
        vars=x,
        by=grp,
        data=work._sum,
        out=work._sum_out_nv,
        stats=sum=total,
        validate=NO,
        as_view=0
      );

      proc sql noprint;
        select sum(total) into :_sum_total_nv trimmed from work._sum_out_nv;
      quit;

      %assertEqual(&_sum_total_nv., 6);
    %test_summary;

    %test_case(summarize alias supports validate=YES);
      %summarize(
        vars=x,
        by=grp,
        data=work._sum,
        out=work._sum_out_alias,
        stats=sum=total,
        validate=YES,
        as_view=0
      );

      proc sql noprint;
        select sum(total) into :_sum_total_alias trimmed from work._sum_out_alias;
      quit;

      %assertEqual(&_sum_total_alias., 6);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _sum _sum_out _sum_out2 _sum_helper _sum_out_nv _sum_out_alias; quit;
%mend test_summarise;

%_pipr_autorun_tests(test_summarise);
