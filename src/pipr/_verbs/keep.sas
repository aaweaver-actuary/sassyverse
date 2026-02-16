/* keep/drop */
%macro keep(vars, data=, out=, validate=1, as_view=0);
  %local _validate _as_view;
  %let _validate=%_pipr_bool(%superq(validate), default=1);
  %let _as_view=%_pipr_bool(%superq(as_view), default=0);
  %_assert_ds_exists(&data);
  %if &_validate %then %_assert_cols_exist(&data, &vars);

  %if &_as_view %then %do;
    data &out / view=&out;
      set &data(keep=&vars);
    run;
  %end;
  %else %do;
    data &out;
      set &data(keep=&vars);
    run;
  %end;

  %if &syserr > 4 %then %_abort(keep() failed (SYSERR=&syserr).);
%mend;

%macro test_keep;
  %_pipr_require_assert;

  %test_suite(Testing keep);
    %test_case(keep retains specified columns);
      data work._keep;
        length a b c 8;
        a=1; b=2; c=3; output;
      run;

      %keep(a b, data=work._keep, out=work._keep_ab);

      proc sql noprint;
        select count(*) into :_cnt_cols trimmed
        from sashelp.vcolumn
        where libname="WORK" and memname="_KEEP_AB" and upcase(name) in ("A","B");
      quit;

      %assertEqual(&_cnt_cols., 2);
    %test_summary;

    %test_case(keep supports as_view and boolean flags);
      %keep(a b, data=work._keep, out=work._keep_ab_view, validate=YES, as_view=TRUE);
      %assertEqual(%sysfunc(exist(work._keep_ab_view, view)), 1);

      proc sql noprint;
        select count(*) into :_cnt_keep_view trimmed from work._keep_ab_view;
      quit;
      %assertEqual(&_cnt_keep_view., 1);
    %test_summary;

    %test_case(keep validate=NO path on valid columns);
      %keep(a, data=work._keep, out=work._keep_a_nv, validate=NO, as_view=0);
      proc sql noprint;
        select count(*) into :_cnt_keep_a trimmed
        from sashelp.vcolumn
        where libname="WORK" and memname="_KEEP_A_NV" and upcase(name)="A";
      quit;
      %assertEqual(&_cnt_keep_a., 1);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist;
    delete _keep _keep_ab _keep_a_nv;
    delete _keep_ab_view / memtype=view;
  quit;
%mend test_keep;

%_pipr_autorun_tests(test_keep);
