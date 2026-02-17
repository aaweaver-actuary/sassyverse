/* MODULE DOC
File: src/dryrun.sas

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
- dryrun
- test_dryrun
- __dryrun_echo
- run_dryrun_tests

7) Expected side effects from running/include
- Defines 4 macro(s) in the session macro catalog.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
*/
%macro dryrun(macro_name, args);
    %local result resolved_macro sq dq;

    /* Attempt to resolve the macro call */
    %let resolved_macro=%nrstr(%)&macro_name(%superq(args));

    /* Check for unmatched quotation marks */
    %let sq=%sysfunc(countc(%superq(resolved_macro), %str(%')));
    %if %sysfunc(mod(&sq, 2)) ne 0 %then %do;
        %put ERROR: Unmatched single quotation marks in the macro call.;
        %return;
    %end;
    %let dq=%sysfunc(countc(%superq(resolved_macro), %str(%")));
    %if %sysfunc(mod(&dq, 2)) ne 0 %then %do;
        %put ERROR: Unmatched double quotation marks in the macro call.;
        %return;
    %end;

    /* Resolve the macro call in a data step */
    data _null_;
        length _res $ 32767;
        _res = resolve(symget('resolved_macro'));
        call symputx('result', _res, 'L');
    run;

    /* Handle potential errors during resolution */
    %if &syserr ne 0 %then %do;
        %put ERROR: An error occurred while resolving the macro call.;
        %put ERROR: (&syserror.) &syserrortext.;
        %return;
    %end;

    /* Print the resolved macro call to the log */
    %put &result;
    &result
%mend dryrun;

%macro test_dryrun;
    %if not %sysmacexist(assertTrue) %then %sbmod(assert);

    %test_suite(Testing dryrun);
        %test_case(dryrun returns resolved macro call);
            %macro __dryrun_echo(x); &x %mend;
            %let out=%dryrun(__dryrun_echo, 123);
            %assertEqual(&out., 123);
        %test_summary;
    %test_summary;
%mend test_dryrun;

/* Macro to run dryrun tests when __unit_tests is set */
%macro run_dryrun_tests;
    %if %symexist(__unit_tests) %then %do;
        %if %superq(__unit_tests)=1 %then %do;
            %test_dryrun;
        %end;
    %end;
%mend run_dryrun_tests;

%run_dryrun_tests;