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

%macro test_arrange;
  %sbmod(assert);

  %test_suite(Testing arrange);
    %test_case(arrange sorts ascending);
      data work._arr;
        input x;
        datalines;
2
1
3
;
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
  %test_summary;

  proc datasets lib=work nolist; delete _arr _arr_sorted; quit;
%mend test_arrange;

%test_arrange;