/* MODULE DOC
File: src/pipr/_verbs/rename.sas

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
- _rename_parse_pairs
- _rename_emit_data
- rename
- test_rename

7) Expected side effects from running/include
- Defines 4 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: _pipr_autorun_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
- When invoked, macros in this module can create or overwrite WORK datasets/views as part of pipeline operations.
*/
%macro _rename_parse_pairs(rename_pairs, out_old, out_map);
  %local i pair old_var new_var num_pairs old_list map;
  %global &out_old &out_map;

  %let old_list=;
  %let map=;
  %let num_pairs=%sysfunc(countw(%superq(rename_pairs), %str( ), q));
  %if &num_pairs = 0 %then %_abort(rename() requires rename_pairs=);

  %do i=1 %to &num_pairs.;
    %let pair=%scan(%superq(rename_pairs), &i., %str( ), q);
    %let old_var=%scan(%superq(pair), 1, =, q);
    %let new_var=%scan(%superq(pair), 2, =, q);

    %if %length(%superq(old_var))=0 or %length(%superq(new_var))=0 %then %do;
      %_abort(rename() requires pairs in old=new form. Bad token: %superq(pair).);
    %end;

    %let old_list=&old_list %superq(old_var);
    %let map=&map %superq(old_var)=%superq(new_var);
  %end;

  %let old_list=%sysfunc(compbl(&old_list));
  %let map=%sysfunc(compbl(&map));
  %_pipr_ucl_assign(out_text=%superq(out_old), value=&old_list);
  %_pipr_ucl_assign(out_text=%superq(out_map), value=&map);
%mend;

%macro _rename_emit_data(rename_map, data=, out=, as_view=0);
  data &out
    %if &as_view %then / view=&out;
  ;
    set &data(rename=(&rename_map));
  run;
%mend;

%macro rename(rename_pairs, data=, out=, validate=1, as_view=0);
  %local _validate _as_view;
  %let _validate=%_pipr_bool(%superq(validate), default=1);
  %let _as_view=%_pipr_bool(%superq(as_view), default=0);
  %_assert_ds_exists(&data);

  %_rename_parse_pairs(&rename_pairs., _rn_old, _rn_map);
  %if &_validate %then %_assert_cols_exist(&data, &&_rn_old);

  %_rename_emit_data(rename_map=&&_rn_map, data=&data, out=&out, as_view=&_as_view);

  %if &syserr > 4 %then %_abort(rename() failed (SYSERR=&syserr).);
%mend;

%macro test_rename;
  %_pipr_require_assert;

  %test_suite(Testing rename);
    %test_case(rename changes column names);
      data work._ren;
        length a b 8;
        a=1; b=2; output;
      run;

      %rename(rename_pairs=a=x, data=work._ren, out=work._ren2);

      proc sql noprint;
        select count(*) into :_cnt_x trimmed
        from sashelp.vcolumn
        where libname="WORK" and memname="_REN2" and upcase(name)="X";
      quit;

      %assertEqual(&_cnt_x., 1);
    %test_summary;

    %test_case(rename helper parse);
      %_rename_parse_pairs(%str(a=x b=y), _rp_old, _rp_map);
      %assertEqual(&_rp_old., a b);
      %assertEqual(&_rp_map., a=x b=y);
    %test_summary;

    %test_case(rename helper view);
      %_rename_emit_data(rename_map=a=x, data=work._ren, out=work._ren_view, as_view=1);
      %assertTrue(%eval(%sysfunc(exist(work._ren_view, view))=1), view created);
      proc sql noprint;
        select count(*) into :_cnt_view trimmed from work._ren_view;
      quit;
      %assertEqual(&_cnt_view., 1);
    %test_summary;

    %test_case(rename supports multiple pairs and validate=NO);
      %rename(rename_pairs=%str(a=x b=y), data=work._ren, out=work._ren3, validate=NO, as_view=0);
      proc sql noprint;
        select count(*) into :_cnt_xy trimmed
        from sashelp.vcolumn
        where libname="WORK" and memname="_REN3" and upcase(name) in ("X","Y");
      quit;
      %assertEqual(&_cnt_xy., 2);
    %test_summary;

    %test_case(rename supports as_view at verb level);
      %rename(rename_pairs=a=x, data=work._ren, out=work._ren_view2, validate=YES, as_view=TRUE);
      %assertEqual(%sysfunc(exist(work._ren_view2, view)), 1);
      proc sql noprint;
        select count(*) into :_cnt_view2 trimmed from work._ren_view2;
      quit;
      %assertEqual(&_cnt_view2., 1);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist;
    delete _ren _ren2 _ren3;
    delete _ren_view _ren_view2 / memtype=view;
  quit;
%mend test_rename;

%_pipr_autorun_tests(test_rename);
