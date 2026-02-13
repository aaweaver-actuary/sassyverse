%macro filter(where_expr, data=, out=, validate=1, as_view=0);
  %_assert_ds_exists(&data);

  %if &as_view %then %do;
    data &out / view=&out;
      set &data;
      %if %length(&where_expr) %then %do;
        if (&where_expr);
      %end;
    run;
  %end;
  %else %do;
    data &out;
      set &data;
      %if %length(&where_expr) %then %do;
        if (&where_expr);
      %end;
    run;
  %end;

  %if &syserr > 4 %then %_abort(filter() failed (SYSERR=&syserr).);
%mend;

%macro where(where_expr, data=, out=, validate=1, as_view=0);
  %filter(where_expr=&where_expr, data=&data, out=&out, validate=&validate, as_view=&as_view);
%mend;

%macro where_not(where_expr, data=, out=, validate=1, as_view=0);
  %filter(where_expr=not (&where_expr), data=&data, out=&out, validate=&validate, as_view=&as_view);
%mend;

%macro mask(mask_expr, data=, out=, validate=1, as_view=0);
  %filter(where_expr=not (&mask_expr), data=&data, out=&out, validate=&validate, as_view=&as_view);
%mend;

%macro where_if(where_expr, condition, data=, out=, validate=1, as_view=0);
  %if &condition %then %do;
    %filter(where_expr=&where_expr, data=&data, out=&out, validate=&validate, as_view=&as_view);
  %end;
  %else %do;
    %filter(where_expr=, data=&data, out=&out, validate=&validate, as_view=&as_view);
  %end;
%mend;

%macro test_filter;
  %sbmod(assert);

  %test_suite(Testing filter);
    %test_case(filter and where_not);
      data work._flt;
        input x;
        datalines;
1
2
3
;
      run;

      %filter(x > 1, data=work._flt, out=work._flt_gt1);
      %where_not(x > 1, data=work._flt, out=work._flt_le1);

      proc sql noprint;
        select count(*) into :_cnt_gt1 trimmed from work._flt_gt1;
        select count(*) into :_cnt_le1 trimmed from work._flt_le1;
      quit;

      %assertEqual(&_cnt_gt1., 2);
      %assertEqual(&_cnt_le1., 1);
    %test_summary;

    %test_case(where_if condition toggles filter);
      %where_if(x > 1, 0, data=work._flt, out=work._flt_all);
      proc sql noprint;
        select count(*) into :_cnt_all trimmed from work._flt_all;
      quit;
      %assertEqual(&_cnt_all., 3);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _flt _flt_gt1 _flt_le1 _flt_all; quit;
%mend test_filter;

%test_filter;