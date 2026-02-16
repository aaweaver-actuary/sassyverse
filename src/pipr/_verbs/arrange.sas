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
  %test_summary;

  proc datasets lib=work nolist; delete _arr _arr_sorted _arr_sorted2; quit;
%mend test_arrange;

%_pipr_autorun_tests(test_arrange);
