%macro drop(vars, data=, out=, validate=1, as_view=0);
  %_assert_ds_exists(&data);
  %if &validate %then %_assert_cols_exist(&data, &vars);

  %if &as_view %then %do;
    data &out / view=&out;
      set &data(drop=&vars);
    run;
  %end;
  %else %do;
    data &out;
      set &data(drop=&vars);
    run;
  %end;

  %if &syserr > 4 %then %_abort(drop() failed (SYSERR=&syserr).);
%mend;