/* MODULE DOC
File: tests/run_tests.sas

1) Purpose in overall project
- Deterministic tests runner used to load the framework in test mode and execute module-level autorun tests.

2) High-level approach
- Sets __unit_tests=1, includes root entrypoint, and runs sassyverse initialization with controlled options.

3) Code organization and why this scheme was chosen
- Single public runner macro with simple argument parsing keeps CI/local invocation stable.
- Code is organized as helper macros first, public API second, and tests/autorun guards last to reduce contributor onboarding time and import risk.

4) Detailed pseudocode algorithm
- Validate base_path input and abort early if missing.
- Set __unit_tests flag to enable guarded module tests.
- Include root sassyverse entrypoint and initialize requested modules.
- Allow module files to auto-run their guarded tests.
- Return control with all assertion output in SAS log.

5) Acknowledged implementation deficits
- Relies on module-level test guards being implemented consistently.
- Coverage depends on each module exposing representative tests.
- Contributor docs are still text comments; there is no generated API reference yet.

6) Macros defined in this file
- sassyverse_run_tests

7) Expected side effects from running/include
- Defines 1 macro(s) in the session macro catalog.
- May create/update GLOBAL macro variable(s): __unit_tests.
- Executes top-level macro call(s) on include: sassyverse_run_tests.
*/
/* run_tests.sas - Deterministic test runner for sassyverse. */
%macro sassyverse_run_tests(base_path=, include_pipr=1);
  %global __unit_tests;
  %let __unit_tests=1;

  %if %length(%superq(base_path))=0 %then %do;
    %put ERROR: base_path= is required and should point to the sassyverse src folder.;
    %return;
  %end;

  %include "&base_path./../sassyverse.sas";
  %sassyverse_init(
    base_path=&base_path,
    include_pipr=&include_pipr,
    include_tests=1
  );
%mend sassyverse_run_tests;

/* Example:
%sassyverse_run_tests(base_path=S:/small_business/modeling/sassyverse/src);
*/
