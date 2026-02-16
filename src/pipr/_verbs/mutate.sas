%macro _mutate_emit_data(stmt, data=, out=, as_view=0);
  %if &as_view %then %do;
    data &out / view=&out;
      set &data;
      &stmt
    run;
  %end;
  %else %do;
    data &out;
      set &data;
      &stmt
    run;
  %end;
%mend;

%macro _mutate_normalize_stmt(stmt, out_stmt);
  %local _raw _norm;
  %global &out_stmt;
  %let _raw=%sysfunc(strip(%superq(stmt)));
  %if %length(%superq(_raw))=0 %then %_abort(mutate() requires a non-empty expression or statement block.);

  data _null_;
    length raw norm $32767;
    raw = strip(symget('_raw'));
    if length(raw) > 0 and substr(raw, length(raw), 1) ne ';' then norm = cats(raw, ';');
    else norm = raw;
    call symputx('_norm', norm, 'L');
  run;

  %let &out_stmt=%superq(_norm);
%mend;

%macro mutate(stmt, data=, out=, validate=1, as_view=0);
  %local _as_view _stmt_norm;
  %let _as_view=%_pipr_bool(%superq(as_view), default=0);
  %_assert_ds_exists(&data);
  %_mutate_normalize_stmt(%superq(stmt), _stmt_norm);

  %_mutate_emit_data(stmt=&_stmt_norm, data=&data, out=&out, as_view=&_as_view);
  %if &syserr > 4 %then %_abort(mutate() failed (SYSERR=&syserr).);
%mend;

%macro with_column(col_name, col_expr, data=, out=, validate=1, as_view=0);
  %mutate(stmt=&col_name = &col_expr, data=&data, out=&out, validate=&validate, as_view=&as_view);
%mend;

%macro test_mutate;
  %_pipr_require_assert;

  %test_suite(Testing mutate);
    %test_case(mutate adds column);
      data work._mut;
        x=2; output;
        x=4; output;
      run;

      %mutate(y = x * 2, data=work._mut, out=work._mut2);

      proc sql noprint;
        select sum(y) into :_sum_y trimmed from work._mut2;
      quit;

      %assertEqual(&_sum_y., 12);
    %test_summary;

    %test_case(mutate supports expressions with commas without explicit %str);
      %mutate(y = ifc(x > 2, 1, 0), data=work._mut, out=work._mut_ifc);
      proc sql noprint;
        select sum(y) into :_sum_y_ifc trimmed from work._mut_ifc;
      quit;
      %assertEqual(&_sum_y_ifc., 1);
    %test_summary;

    %test_case(mutate remains compatible with explicit statement blocks);
      %mutate(%str(y = x * 3;), data=work._mut, out=work._mut3x);
      proc sql noprint;
        select sum(y) into :_sum_y_3x trimmed from work._mut3x;
      quit;
      %assertEqual(&_sum_y_3x., 18);
    %test_summary;

    %test_case(with_column alias);
      %with_column(z, x + 1, data=work._mut, out=work._mut3);
      proc sql noprint;
        select min(z) into :_min_z trimmed from work._mut3;
      quit;
      %assertEqual(&_min_z., 3);

      %with_column(flag, ifc(x > 2, 1, 0), data=work._mut, out=work._mut4);
      proc sql noprint;
        select sum(flag) into :_sum_flag_wc trimmed from work._mut4;
      quit;
      %assertEqual(&_sum_flag_wc., 1);
    %test_summary;

    %test_case(mutate helper view);
      %_mutate_emit_data(stmt=%str(z = x + 2;), data=work._mut, out=work._mut_view, as_view=1);
      %assertTrue(%eval(%sysfunc(exist(work._mut_view, view))=1), view created);
      proc sql noprint;
        select max(z) into :_max_z trimmed from work._mut_view;
      quit;
      %assertEqual(&_max_z., 6);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _mut _mut2 _mut_ifc _mut3x _mut3 _mut4 _mut_view; quit;
%mend test_mutate;

%_pipr_autorun_tests(test_mutate);
