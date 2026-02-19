/* MODULE DOC
File: src/is_equal.sas

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
- is_equal
- is_not_equal
- test_is_equal
- run_is_equal_tests

7) Expected side effects from running/include
- Defines 4 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: run_is_equal_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
*/
%MACRO is_equal(a, b);
    %local out a_val b_val is_num_a is_num_b;

    /* Check if parameters are provided */
    %if %superq(a)= OR %superq(b)= %then %do;
        %put ERROR: Both parameters are required.;
        %return;
    %end;

    /* Try numeric comparison only if both args are numeric-like */
    %let is_num_a=%sysfunc(verify(%superq(a),%str(0123456789.+-eE)));
    %let is_num_b=%sysfunc(verify(%superq(b),%str(0123456789.+-eE)));
    %if &is_num_a=0 and &is_num_b=0 %then %do;
        %let a_val=%sysevalf(%superq(a));
        %let b_val=%sysevalf(%superq(b));
        %if %sysevalf(&a_val = &b_val) %then %let out=1;
        %else %let out=0;
    %end;
    %else %do;
        /* Character comparison */
        %if %superq(a)=%superq(b) %then %let out=1;
        %else %let out=0;
    %end;

    &out
%MEND is_equal;

%MACRO is_not_equal(a, b);
	%let opposite=%is_equal(&a., &b.);
	%if &opposite=1 %then %let out=0;
	%else %let out=1;

	&out
%MEND is_not_equal;

%macro test_is_equal;
    %if not %sysmacexist(assertTrue) %then %sbmod(assert);

    %test_suite(Testing is_equal);
        %test_case(numeric comparisons);
            %assertEqual(%is_equal(10, 10), 1);
            %assertEqual(%is_equal(10.0, 10), 1);
            %assertEqual(%is_equal(10, 11), 0);
        %test_summary;

        %test_case(character comparisons);
            %assertEqual(%is_equal(abc, abc), 1);
            %assertEqual(%is_equal(abc, abcd), 0);
            %assertEqual(%is_not_equal(abc, abcd), 1);
        %test_summary;

        %test_case(mixed numeric and character comparisons);
            %assertEqual(%is_equal(10, abc), 0);
            %assertEqual(%is_equal(abc, 10), 0);
        %test_summary;
    %test_summary;
%mend test_is_equal;

/* Macro to run is_equal tests when __unit_tests is set */
%macro run_is_equal_tests;
    %if %symexist(__unit_tests) %then %do;
        %if %superq(__unit_tests)=1 %then %do;
            %test_is_equal;
        %end;
    %end;
%mend run_is_equal_tests;

%run_is_equal_tests;