/* testthat.sas - Higher-level SAS macro testing with tests. */
%macro _testthat_bootstrap;
  %if not %sysmacexist(assertTrue) %then %sbmod(assert);
%mend _testthat_bootstrap;

%_testthat_bootstrap;

/* Return the (numeric) row count, or -1 if the data set cannot be opened. */
%macro nobs(ds);
  %local dsid n rc;
  %let dsid = %sysfunc(open(&ds, i));
  %if &dsid %then %do;
    /* NLOBS = logical obs (excludes deleted); use NOBS if you prefer physical */
    %let n = %sysfunc(attrn(&dsid, NLOBS));
    %let rc = %sysfunc(close(&dsid));
    &n
  %end;
  %else %do;
    -1
  %end;
%mend;

/* Boolean check: 1 if non-empty, 0 if empty, -1 if cannot open (or unknown). */
%macro tt_nonempty_bool(ds);
  %local _raw _n;
  %let _raw = %nobs(&ds);
  %let _n   = %sysfunc(inputn(&_raw, best32.));
  %if &_n > 0 %then 1;
  %else %if &_n < 0 %then -1;
  %else 0;
%mend;

/* Require that a dataset is non-empty. Logs assertion and optionally aborts. */
%macro tt_require_nonempty(ds, abort=YES);
  %local _raw _n msg;
  %let _raw = %nobs(&ds);
  %let _n   = %sysfunc(inputn(&_raw, best32.));

  /* Escape the semicolon in the message */
  %let msg  = Asserted that &ds contains at least 1 row%str(; )found &_n.;

  /* Pass the message safely */
  %assertTrue(%eval(&_n > 0), %superq(msg));

  /* Fail fast if requested */
  %if %upcase(&abort)=YES and %eval(&_n <= 0) %then %abort cancel;
%mend tt_require_nonempty;

/* Backward-compatible alias */
%macro tt_is_nonempty(ds);
  %tt_require_nonempty(&ds)
%mend tt_is_nonempty;

/* ---------------------- */
/* Tests for testthat.sas */
/* ---------------------- */
%macro test_testthat;
  %test_suite(Testing testthat.sas);

    /* nobs behavior for missing and empty -> non-empty */
    %test_case(nobs returns -1 for missing dataset);
      %let n_missing=%nobs(work.__missing_ds__);
      %assertTrue(%eval(&n_missing < 0), nobs returns -1 for a missing dataset);
    %test_summary;

    %test_case(nobs returns 0 for empty dataset and >0 after insert);
      /* Create an empty dataset (0 observations, valid descriptor) */
      data work._tt_tmp; stop; run;
      %let n0=%nobs(work._tt_tmp);
      %assertEqual(&n0, 0);

      /* Add a row */
      data work._tt_tmp; x=1; output; run;
      %let n1=%nobs(work._tt_tmp);
      %assertTrue(%eval(&n1 > 0), nobs > 0 after inserting a row);
    %test_summary;

    /* Test emptiness/non-emptiness WITHOUT producing a failure in the log. */
    %test_case(tt_nonempty_bool is 0 on empty and 1 after insert);
      data work._tt_tmp2; stop; run;

      %let b0=%tt_nonempty_bool(work._tt_tmp2);
      %assertEqual(&b0, 0);

      data work._tt_tmp2; x=1; output; run;

      %let b1=%tt_nonempty_bool(work._tt_tmp2);
      %assertEqual(&b1, 1);
    %test_summary;

    %test_case(tt_nonempty_bool returns -1 for missing dataset);
      %let b_missing=%tt_nonempty_bool(work.__missing_ds__);
      %assertEqual(&b_missing, -1);
    %test_summary;

    %test_case(tt_require_nonempty increments failures on empty when abort=NO);
      data work._tt_tmp5; stop; run;

      %let _bfCaseFail2=&testCaseFailures;
      %tt_require_nonempty(work._tt_tmp5, abort=NO);
      %let _afCaseFail2=&testCaseFailures;

      %assertEqual(%eval(&_afCaseFail2 - &_bfCaseFail2), 1);
    %test_summary;

    /* tt_require_nonempty should PASS and not add failures when dataset is non-empty */
    %test_case(tt_require_nonempty passes on non-empty and does not add failures);
      data work._tt_tmp3; x=1; output; run;

      %let _bfCaseFail=&testCaseFailures;
      %let _bfGlobFail=&testFailures;

      %tt_require_nonempty(work._tt_tmp3, abort=NO);

      %let _afCaseFail=&testCaseFailures;
      %let _afGlobFail=&testFailures;

      %assertEqual(%eval(&_afCaseFail - &_bfCaseFail), 0);
      %assertEqual(%eval(&_afGlobFail - &_bfGlobFail), 0);
    %test_summary;

    /* Alias macro should behave identically on non-empty dataset */
    %test_case(tt_is_nonempty alias passes on non-empty dataset);
      data work._tt_tmp4; x=1; output; run;

      %let _bfFail3=&testCaseFailures;
      %tt_is_nonempty(work._tt_tmp4); /* default abort=YES is safe since non-empty */
      %let _afFail3=&testCaseFailures;
      %assertEqual(%eval(&_afFail3 - &_bfFail3), 0);
    %test_summary;

  %test_summary;

  proc delete data=_tt_tmp _tt_tmp2 _tt_tmp3 _tt_tmp4 _tt_tmp5;
  run;
%mend test_testthat;

/* Macro to run testthat tests when __unit_tests is set */
%macro run_testthat_tests;
  %if %symexist(__unit_tests) %then %do;
    %if %superq(__unit_tests)=1 %then %do;
      %test_testthat;
    %end;
  %end;
%mend run_testthat_tests;

%run_testthat_tests;