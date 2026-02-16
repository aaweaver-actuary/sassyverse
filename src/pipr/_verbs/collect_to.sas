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

    %test_case(collect_to accepts view input);
      data work._ct_vsrc;
        x=1; output;
        x=2; output;
      run;
      data work._ct_view / view=work._ct_view;
        set work._ct_vsrc;
      run;

      %collect_to(work._ct_out_view, data=work._ct_view);

      proc sql noprint;
        select count(*) into :_ct_view_cnt trimmed from work._ct_out_view;
      quit;
      %assertEqual(&_ct_view_cnt., 2);
    %test_summary;

    %test_case(collect_into alias and as_view output);
      %collect_into(work._ct_out_alias, data=work._ct_in, as_view=TRUE, validate=NO);
      %assertEqual(%sysfunc(exist(work._ct_out_alias, view)), 1);

      proc sql noprint;
        select count(*) into :_ct_alias_cnt trimmed from work._ct_out_alias;
      quit;
      %assertEqual(&_ct_alias_cnt., 1);
    %test_summary;

    %test_case(collect_to uses out= when provided);
      %collect_to(work._ct_unused, data=work._ct_in, out=work._ct_explicit, validate=YES, as_view=0);
      %assertEqual(%sysfunc(exist(work._ct_explicit)), 1);
      %assertEqual(%sysfunc(exist(work._ct_unused)), 0);
    %test_summary;

    %test_case(collect_to respects boolean-like as_view values);
      %collect_to(work._ct_bool_view, data=work._ct_in, as_view=TRUE, validate=NO);
      %assertEqual(%sysfunc(exist(work._ct_bool_view, view)), 1);
      %collect_to(work._ct_bool_table, data=work._ct_bool_view, as_view=OFF, validate=YES);
      %assertEqual(%sysfunc(exist(work._ct_bool_table)), 1);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist;
    delete _ct_in _ct_out _ct_vsrc _ct_out_view _ct_explicit _ct_bool_table;
    delete _ct_view _ct_out_alias _ct_bool_view / memtype=view;
  quit;
%mend test_collect_to;

%_pipr_autorun_tests(test_collect_to);
