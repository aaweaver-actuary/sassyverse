/* MODULE DOC
File: src/pipr/_verbs/drop_duplicates.sas

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
- _drop_duplicates_emit
- drop_duplicates
- test_drop_duplicates

7) Expected side effects from running/include
- Defines 3 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: _pipr_autorun_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
- When invoked, macros in this module can create or overwrite WORK datasets/views as part of pipeline operations.
*/
%macro _drop_duplicates_emit(by=, data=, out=, as_view=0);
  proc sql noprint;
    create
      %if &as_view %then view;
      %else table;
    &out as
    select distinct
      %if %length(%superq(by)) %then %do;
        &by
      %end;
      %else %do;
        *
      %end;
    from &data
    ;
  quit;
%mend;

%macro drop_duplicates(by=, data=, out=, validate=1, as_view=0);
  %local _validate _as_view;
  %let _validate=%_pipr_bool(%superq(validate), default=1);
  %let _as_view=%_pipr_bool(%superq(as_view), default=0);

  %_assert_ds_exists(&data);
  %if &_validate and %length(%superq(by)) %then %_assert_cols_exist(&data, &by);

  %_drop_duplicates_emit(by=%superq(by), data=&data, out=&out, as_view=&_as_view);

  %if &syserr > 4 %then %_abort(drop_duplicates() failed (SYSERR=&syserr).);
%mend;

%macro test_drop_duplicates;
  %_pipr_require_assert;

  %test_suite(Testing drop_duplicates);
    %test_case(drop_duplicates removes duplicate full rows);
      data work._dup;
        id=1; grp='A'; output;
        id=1; grp='A'; output;
        id=2; grp='B'; output;
      run;

      %drop_duplicates(data=work._dup, out=work._dup_all);

      proc sql noprint;
        select count(*) into :_dup_all_cnt trimmed from work._dup_all;
      quit;
      %assertEqual(&_dup_all_cnt., 2);
    %test_summary;

    %test_case(drop_duplicates supports by= keys);
      data work._dup_keys;
        id=1; grp='A'; amt=10; output;
        id=1; grp='A'; amt=20; output;
        id=2; grp='B'; amt=30; output;
      run;

      %drop_duplicates(by=id grp, data=work._dup_keys, out=work._dup_key_only);

      proc sql noprint;
        select count(*) into :_dup_key_cnt trimmed from work._dup_key_only;
        select upcase(name) into :_dup_key_cols separated by ' '
        from sashelp.vcolumn
        where libname='WORK' and memname='_DUP_KEY_ONLY'
        order by varnum;
      quit;
      %assertEqual(&_dup_key_cnt., 2);
      %assertEqual(&_dup_key_cols., ID GRP);
    %test_summary;

    %test_case(drop_duplicates supports as_view and string booleans);
      %drop_duplicates(by=id, data=work._dup_keys, out=work._dup_key_view, validate=YES, as_view=TRUE);
      %assertEqual(%sysfunc(exist(work._dup_key_view, view)), 1);

      proc sql noprint;
        select count(*) into :_dup_key_view_cnt trimmed from work._dup_key_view;
      quit;
      %assertEqual(&_dup_key_view_cnt., 2);
    %test_summary;

    %test_case(drop_duplicates validate=NO path on valid by list);
      %drop_duplicates(by=id, data=work._dup_keys, out=work._dup_key_nv, validate=NO, as_view=0);
      proc sql noprint;
        select count(*) into :_dup_key_nv_cnt trimmed from work._dup_key_nv;
      quit;
      %assertEqual(&_dup_key_nv_cnt., 2);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist;
    delete _dup _dup_all _dup_keys _dup_key_only _dup_key_nv;
    delete _dup_key_view / memtype=view;
  quit;
%mend test_drop_duplicates;

%_pipr_autorun_tests(test_drop_duplicates);
