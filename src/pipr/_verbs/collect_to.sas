%macro collect_to(out_name, data=, out=, validate=1, as_view=0);
  %local _as_view;
  %let _as_view=%_pipr_bool(%superq(as_view), default=0);
  %_assert_ds_exists(&data);
  %if %length(%superq(out))=0 %then %let out=&out_name;
  %if %length(%superq(out))=0 %then %_abort(collect_to() requires an output dataset name.);

  %if &_as_view %then %do;
    data &out / view=&out;
      set &data;
    run;
  %end;
  %else %do;
    data &out;
      set &data;
    run;
  %end;

  %if &syserr > 4 %then %_abort(collect_to() failed (SYSERR=&syserr).);
%mend;

%macro collect_into(out_name, data=, out=, validate=1, as_view=0);
  %collect_to(&out_name, data=&data, out=&out, validate=&validate, as_view=&as_view);
%mend;

%macro test_collect_to;
  %_pipr_require_assert;

  %test_suite(Testing collect_to);
    %test_case(collect_to writes output);
      data work._ct_in; x=1; output; run;

      %collect_to(work._ct_out, data=work._ct_in);

      %let _cnt=%sysfunc(attrn(%sysfunc(open(work._ct_out,i)), NLOBS));
      %assertEqual(&_cnt., 1);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _ct_in _ct_out; quit;
%mend test_collect_to;

%_pipr_autorun_tests(test_collect_to);
