%macro mutate(stmt, data=, out=, validate=1, as_view=0);
  %_assert_ds_exists(&data);
  %if %length(&stmt)=0 %then %_abort(mutate() requires a statement block);

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

  %if &syserr > 4 %then %_abort(mutate() failed (SYSERR=&syserr).);
%mend;

%macro with_column(col_name, col_expr, data=, out=, validate=1, as_view=0);
  %mutate(stmt=%str(&col_name = &col_expr;), data=&data, out=&out, validate=&validate, as_view=&as_view);
%mend;

%macro test_mutate;
  %sbmod(assert);

  %test_suite(Testing mutate);
    %test_case(mutate adds column);
      data work._mut;
        input x;
        datalines;
2
4
;
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
  %test_summary;

  proc datasets lib=work nolist; delete _mut _mut2 _mut3; quit;
%mend test_mutate;

%test_mutate;