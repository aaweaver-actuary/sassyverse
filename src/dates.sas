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
    %test_summary;
%mend test_fmt_date;

%if %symexist(__unit_tests) %then %do;
  %if %superq(__unit_tests)=1 %then %do;
    %test_fmt_date;
  %end;
%end;