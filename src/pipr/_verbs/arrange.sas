/* arrange(<BY list>)  -- cannot be a view (PROC SORT) */
%macro arrange(by_list, data=, out=, validate=1, as_view=0);
  %_assert_ds_exists(&data);
  %if &validate %then %_assert_by_vars(&data, &by_list);

  proc sort data=&data out=&out;
    by &by_list;
  run;

  %if &syserr > 4 %then %_abort(arrange() failed (SYSERR=&syserr).);
%mend;

%macro sort(by_list, data=, out=, validate=1, as_view=0);
  %arrange(by_list=&by_list, data=&data, out=&out, validate=&validate, as_view=&as_view);
%mend;