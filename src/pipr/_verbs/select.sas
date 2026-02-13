%macro select(cols, data=, out=, validate=1, as_view=0);
  %_assert_ds_exists(&data);
  %if &validate %then %_assert_cols_exist(&data, &cols);

  %if &as_view %then %do;
    data &out / view=&out;
      set &data(keep=&cols);
    run;
  %end;
  %else %do;
    data &out;
      set &data(keep=&cols);
    run;
  %end;

  %if &syserr > 4 %then %_abort(select() failed (SYSERR=&syserr).);
%mend;