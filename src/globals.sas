/* MODULE DOC
File: src/globals.sas

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
- init_global_var
- init_global_vars
- test_globals
- run_global_tests

7) Expected side effects from running/include
- Defines 4 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: run_global_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
*/
%macro init_global_var(variable);
	%if not %symexist(&variable.) %then %do;
		%global &variable.;
		%let &variable.=0;
	%end;
%mend init_global_var;

%macro init_global_vars;
	%let vars=imported__to_numb imported__logger imported__shell;

	%let N=%sysfunc(countw(&vars.));
	%do i=1 %to &N.;
		%let x=%sysfunc(scan(&vars., &i.));
		%init_global_var(&x.);
	%end;
%mend init_global_vars;

%macro test_globals;
	%if not %sysmacexist(assertTrue) %then %sbmod(assert);

	%test_suite(Testing globals.sas);
		%test_case(init_global_var sets to 0);
			%symdel __tmpvar / nowarn;
			%init_global_var(__tmpvar);
			%assertEqual(&__tmpvar., 0);
		%test_summary;

		%test_case(init_global_vars creates known flags);
			%init_global_vars;
			%assertTrue(%symexist(imported__to_numb), imported__to_numb exists);
			%assertTrue(%symexist(imported__logger), imported__logger exists);
			%assertTrue(%symexist(imported__shell), imported__shell exists);
		%test_summary;
	%test_summary;
%mend test_globals;

%macro run_global_tests;
%if %symexist(__unit_tests) %then %do;
  %if %superq(__unit_tests)=1 %then %do;
    %test_globals;
  %end;
%end;
%mend run_global_tests;

%run_global_tests;