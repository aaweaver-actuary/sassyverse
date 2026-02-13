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

%macro test_drop;
  %sbmod(assert);

  %test_suite(Testing drop);
    %test_case(drop removes specified columns);
      data work._drop;
        length a b c 8;
        a=1; b=2; c=3; output;
      run;

      %drop(c, data=work._drop, out=work._drop_ab);

      proc sql noprint;
        select count(*) into :_cnt_c trimmed
        from sashelp.vcolumn
        where libname="WORK" and memname="_DROP_AB" and upcase(name)="C";
      quit;

      %assertEqual(&_cnt_c., 0);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _drop _drop_ab; quit;
%mend test_drop;

%test_drop;