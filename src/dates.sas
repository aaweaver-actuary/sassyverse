%macro fmt_date(col);
    format &col. mmddyy10.;
%mend fmt_date;

%macro year(date);
    %let out=%sysfunc(year(&date.));
    &out.
%mend year;

%macro month(date);
    %let out=%sysfunc(month(&date.));
    &out.
%mend month;

%macro day(date);
    %let out=%sysfunc(day(&date.));
    &out.
%mend day;

%macro mdy(m, d, y);
    %let out=%sysfunc(mdy(&m., &d., &y.));
    &out.
%mend mdy;

%macro test_fmt_date;
    %if not %sysmacexist(assertTrue) %then %sbmod(assert);

    %test_suite(Test date macros:);
        %let date=%sysfunc(mdy(11, 26, 1987));

        %let expected_date=%mdy(11, 26, 1987);
        %assertEqual(&date., &expected_date.);

        %let expected_month=11;
        %let expected_day=26;
        %let expected_year=1987;

        %let actual_month=%month(&date.);
        %let actual_day=%day(&date.);
        %let actual_year=%year(&date.);
        
        %assertEqual(&expected_month., &actual_month.);
        %assertEqual(&expected_day., &actual_day.);
        %assertEqual(&expected_year., &actual_year.);

        %let leap=%mdy(2, 29, 2020);
        %assertEqual(%year(&leap.), 2020);
        %assertEqual(%month(&leap.), 2);
        %assertEqual(%day(&leap.), 29);

        data work._dt_fmt;
          d=&date.;
          %fmt_date(d);
          output;
        run;
        %assertTrue(%eval(%sysfunc(exist(work._dt_fmt))=1), fmt_date emitted valid FORMAT statement);
        proc datasets lib=work nolist; delete _dt_fmt; quit;
    %test_summary;
%mend test_fmt_date;

/* Macro to run date tests when __unit_tests is set */
%macro run_fmt_date_tests;
     %if %symexist(__unit_tests) %then %do;
        %if %superq(__unit_tests)=1 %then %do;
            %test_fmt_date;
        %end;
    %end;
%mend run_fmt_date_tests;

%run_fmt_date_tests;
