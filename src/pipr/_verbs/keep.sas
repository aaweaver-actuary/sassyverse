/* keep/drop */
%macro keep(vars, data=, out=, validate=1, as_view=0);
  %_assert_ds_exists(&data);
  %if &validate %then %_assert_cols_exist(&data, &vars);

  %if &as_view %then %do;
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
  %sbmod(assert);

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
  %test_summary;

  proc datasets lib=work nolist; delete _keep _keep_ab; quit;
%mend test_keep;

%test_keep;