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