/* MODULE DOC
File: src/dates.sas

1) Purpose in overall project
- General-purpose core utility module used by sassyverse contributors and downstream workflows.

2) High-level approach
- Defines reusable macro helpers and their tests, with small wrappers around common SAS patterns.

3) Code organization and why this scheme was chosen
- Public macros are grouped by theme, followed by focused unit tests and guarded autorun hooks.
- Code is organized as helper macros first, public API second, and tests/autorun guards last to reduce contributor onboarding time and import risk.

4) Detailed pseudocode algorithm
- Define utility macros and any private helper macros they require.
- Where needed, lazily import dependencies (for example assert/logging helpers).
- Expose a small public API with deterministic text/data-step output.
- Include test macros that exercise nominal and edge cases.
- Run tests only when __unit_tests is enabled to avoid production noise.

5) Acknowledged implementation deficits
- Macro-language utilities have limited static guarantees and rely on disciplined caller inputs.
- Some historical APIs prioritize backward compatibility over perfect consistency.
- Contributor docs are still text comments; there is no generated API reference yet.

6) Macros defined in this file
- fmt_date
- year
- month
- day
- mdy
- test_fmt_date
- run_fmt_date_tests

7) Expected side effects from running/include
- Defines 7 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: run_fmt_date_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
*/
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
