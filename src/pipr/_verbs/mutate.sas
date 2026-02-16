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

%macro mutate(stmt, data=, out=, validate=1, as_view=0);
  %local _as_view;
  %let _as_view=%_pipr_bool(%superq(as_view), default=0);
  %_assert_ds_exists(&data);
  %if %length(%superq(stmt))=0 %then %_abort(mutate() requires a statement block);

  %_mutate_emit_data(stmt=&stmt, data=&data, out=&out, as_view=&_as_view);
  %if &syserr > 4 %then %_abort(mutate() failed (SYSERR=&syserr).);
%mend;

%macro with_column(col_name, col_expr, data=, out=, validate=1, as_view=0);
  %mutate(stmt=%str(&col_name = &col_expr;), data=&data, out=&out, validate=&validate, as_view=&as_view);
%mend;

%macro test_mutate;
  %_pipr_require_assert;

  %test_suite(Testing mutate);
    %test_case(mutate adds column);
      data work._mut;
        x=2; output;
        x=4; output;
      run;

      %mutate(%str(y = x * 2;), data=work._mut, out=work._mut2);

      proc sql noprint;
        select sum(y) into :_sum_y trimmed from work._mut2;
      quit;

      %assertEqual(&_sum_y., 12);
    %test_summary;

    %test_case(with_column alias);
      %with_column(z, x + 1, data=work._mut, out=work._mut3);
      proc sql noprint;
        select min(z) into :_min_z trimmed from work._mut3;
      quit;
      %assertEqual(&_min_z., 3);
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

  proc datasets lib=work nolist; delete _mut _mut2 _mut3 _mut_view; quit;
%mend test_mutate;

%_pipr_autorun_tests(test_mutate);
