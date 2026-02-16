%macro n_rows(ds);
    %let dsid = %sysfunc(open(&ds));
    %let nobs = %sysfunc(attrn(&dsid, nobs));
    %let rc = %sysfunc(close(&dsid));
    &nobs.
%mend n_rows;

%macro test_n_rows;
  %if %symexist(__unit_tests) %then %do;
    %if %superq(__unit_tests)=1 %then %do;
      %if not %sysmacexist(assertTrue) %then %sbmod(assert);

      data test_data;
        input col1 col2 col3 $;
        datalines;
1 1 a
2 2 b
3 3 c
4 4 d
;
      run;

      data test_data;
        set test_data;
        if _n_=2 then col1=.;
        if _n_=3 then do;
          col1=.;
          col2=.;
        end;
      run;

      data test2;
        set test_data;
        if col1=1;
      run;

      %test_suite(n_rows testing);
        %let n=%n_rows(test_data);
        %assertEqual(&n., 4);

        %let n=%n_rows(work.test_data);
        %assertEqual(&n., 4);

        %let n=%n_rows(test2);
        %assertEqual(&n., 1);

        data test_empty;
          length col1 8;
          stop;
        run;
        %let n=%n_rows(test_empty);
        %assertEqual(&n., 0);
      %test_summary;

      proc delete data=test_data test2 test_empty;
      run;
    %end;
  %end;
%mend test_n_rows;

/* Macro to run n_rows tests when __unit_tests is set */
%macro run_n_rows_tests;
  %if %symexist(__unit_tests) %then %do;
    %if %superq(__unit_tests)=1 %then %do;
      %test_n_rows;
    %end;
  %end;
%mend run_n_rows_tests;

%run_n_rows_tests;
