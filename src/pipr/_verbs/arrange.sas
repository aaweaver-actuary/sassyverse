/* MODULE DOC
File: src/pipr/_verbs/arrange.sas

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
- _arrange_sort
- arrange
- sort
- test_arrange

7) Expected side effects from running/include
- Defines 4 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: _pipr_autorun_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
- When invoked, macros in this module can create or overwrite WORK datasets/views as part of pipeline operations.
*/
/* arrange(<BY list>)  -- cannot be a view (PROC SORT) */
%macro _arrange_sort(by_list, data=, out=);
  proc sort data=&data out=&out;
    by &by_list;
  run;
%mend;

%macro arrange(by_list, data=, out=, validate=1, as_view=0);
  %local _validate;
  %let _validate=%_pipr_bool(%superq(validate), default=1);
  %_assert_ds_exists(&data);
  %if &_validate %then %_assert_by_vars(&data, &by_list);

  %_arrange_sort(by_list=&by_list, data=&data, out=&out);

  %if &syserr > 4 %then %_abort(arrange() failed (SYSERR=&syserr).);
%mend;

%macro sort(by_list, data=, out=, validate=1, as_view=0);
  %arrange(by_list=&by_list, data=&data, out=&out, validate=&validate, as_view=&as_view);
%mend;

%macro test_arrange;
  %_pipr_require_assert;

  %test_suite(Testing arrange);
    %test_case(arrange sorts ascending);
      data work._arr;
        x=2; output;
        x=1; output;
        x=3; output;
      run;

      %arrange(x, data=work._arr, out=work._arr_sorted);

      data _null_;
        set work._arr_sorted end=last;
        if _n_=1 then call symputx('first_x', x);
        if last then call symputx('last_x', x);
      run;

      %assertEqual(&first_x., 1);
      %assertEqual(&last_x., 3);
    %test_summary;

    %test_case(arrange helper);
      %_arrange_sort(by_list=x, data=work._arr, out=work._arr_sorted2);

      data _null_;
        set work._arr_sorted2 end=last;
        if _n_=1 then call symputx('first_x2', x);
        if last then call symputx('last_x2', x);
      run;

      %assertEqual(&first_x2., 1);
      %assertEqual(&last_x2., 3);
    %test_summary;

    %test_case(sort alias supports descending and boolean validate flags);
      %sort(descending x, data=work._arr, out=work._arr_sorted_desc, validate=YES, as_view=1);

      data _null_;
        set work._arr_sorted_desc end=last;
        if _n_=1 then call symputx('first_x_desc', x);
        if last then call symputx('last_x_desc', x);
      run;

      %assertEqual(&first_x_desc., 3);
      %assertEqual(&last_x_desc., 1);
      %assertEqual(%sysfunc(exist(work._arr_sorted_desc, view)), 0);
    %test_summary;

    %test_case(arrange validate=NO still runs on valid by list);
      %arrange(x, data=work._arr, out=work._arr_sorted_nv, validate=NO);
      %assertEqual(%sysfunc(exist(work._arr_sorted_nv)), 1);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _arr _arr_sorted _arr_sorted2 _arr_sorted_desc _arr_sorted_nv; quit;
%mend test_arrange;

%_pipr_autorun_tests(test_arrange);
