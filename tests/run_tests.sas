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
