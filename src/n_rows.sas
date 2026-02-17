/* MODULE DOC
File: src/n_rows.sas

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
- n_rows
- test_n_rows
- run_n_rows_tests

7) Expected side effects from running/include
- Defines 3 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: run_n_rows_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
*/
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
