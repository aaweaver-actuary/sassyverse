%macro rename(rename_pairs, data=, out=, validate=1, as_view=0);
  %_assert_ds_exists(&data);
  
  /* Parse rename pairs into old and new variable lists */
  %let old_vars=;
  %let new_vars=;
  %let num_pairs=%sysfunc(countw(&rename_pairs., %str( )));
  
  %do i=1 %to &num_pairs.;
    %let pair=%scan(&rename_pairs., &i., %str( ));
    %let old_var=%scan(&pair., 1, =);
    %let new_var=%scan(&pair., 2, =);
    
    %if &validate %then %do;
      %_assert_cols_exist(&data, &old_var.);
    %end;
    
    %let old_vars=&old_vars. &old_var.;
    %let new_vars=&new_vars. &new_var.;
  %end;

  /* Create rename statement */
  data &out
    %if &as_view %then / view=&out;
  ;
    set &data(rename=(%sysfunc(compbl(&old_vars.))=%sysfunc(compbl(&new_vars.))));
  run;

  %if &syserr > 4 %then %_abort(rename() failed (SYSERR=&syserr).);
%mend;

%macro test_rename;
  %sbmod(assert);

  %test_suite(Testing rename);
    %test_case(rename changes column names);
      data work._ren;
        length a b 8;
        a=1; b=2; output;
      run;

      %rename(a=x, data=work._ren, out=work._ren2);

      proc sql noprint;
        select count(*) into :_cnt_x trimmed
        from sashelp.vcolumn
        where libname="WORK" and memname="_REN2" and upcase(name)="X";
      quit;

      %assertEqual(&_cnt_x., 1);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _ren _ren2; quit;
%mend test_rename;

%test_rename;