/* MODULE DOC
File: src/pipr/_verbs/keep.sas

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
- keep
- test_keep

7) Expected side effects from running/include
- Defines 2 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: _pipr_autorun_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
- When invoked, macros in this module can create or overwrite WORK datasets/views as part of pipeline operations.
*/
/* keep/drop */
%macro keep(vars, data=, out=, validate=1, as_view=0);
  %local _validate _as_view;
  %let _validate=%_pipr_bool(%superq(validate), default=1);
  %let _as_view=%_pipr_bool(%superq(as_view), default=0);
  %_assert_ds_exists(&data);
  %if &_validate %then %_assert_cols_exist(&data, &vars);

  %if &_as_view %then %do;
    data &out / view=&out;
      set &data(keep=&vars);
    run;
  %end;
  %else %do;
    data &out;
      set &data(keep=&vars);
    run;
  %end;

  %if &syserr > 4 %then %_abort(keep() failed (SYSERR=&syserr).);
%mend;

%macro test_keep;
  %_pipr_require_assert;

  %test_suite(Testing keep);
    %test_case(keep retains specified columns);
      data work._keep;
        length a b c 8;
        a=1; b=2; c=3; output;
      run;

      %keep(a b, data=work._keep, out=work._keep_ab);

      proc sql noprint;
        select count(*) into :_cnt_cols trimmed
        from sashelp.vcolumn
        where libname="WORK" and memname="_KEEP_AB" and upcase(name) in ("A","B");
      quit;

      %assertEqual(&_cnt_cols., 2);
    %test_summary;

    %test_case(keep supports as_view and boolean flags);
      %keep(a b, data=work._keep, out=work._keep_ab_view, validate=YES, as_view=TRUE);
      %assertEqual(%sysfunc(exist(work._keep_ab_view, view)), 1);

      proc sql noprint;
        select count(*) into :_cnt_keep_view trimmed from work._keep_ab_view;
      quit;
      %assertEqual(&_cnt_keep_view., 1);
    %test_summary;

    %test_case(keep validate=NO path on valid columns);
      %keep(a, data=work._keep, out=work._keep_a_nv, validate=NO, as_view=0);
      proc sql noprint;
        select count(*) into :_cnt_keep_a trimmed
        from sashelp.vcolumn
        where libname="WORK" and memname="_KEEP_A_NV" and upcase(name)="A";
      quit;
      %assertEqual(&_cnt_keep_a., 1);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist;
    delete _keep _keep_ab _keep_a_nv;
    delete _keep_ab_view / memtype=view;
  quit;
%mend test_keep;

%_pipr_autorun_tests(test_keep);
