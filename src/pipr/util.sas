/* 
    Abort the SAS session with a given error message.
    Usage: %_abort(Some error occurred)
*/
%macro _abort(msg);
  %put ERROR: &msg;
  %abort cancel;
%mend;


/* 
    Generate a temporary dataset name with a given prefix. The name is based on the current datetime to ensure uniqueness.
    Usage: %_tmpds(prefix=mytemp_)
*/
%macro _tmpds(prefix=_p);
  %sysfunc(cats(work., &prefix., %sysfunc(putn(%sysfunc(datetime()), hex16.))))
%mend;

/* Returns 1 when unit tests are enabled for this session, else 0. */
%macro _pipr_in_unit_tests;
  %if %symexist(__unit_tests) %then %do;
    %if %superq(__unit_tests)=1 %then 1;
    %else 0;
  %end;
  %else 0;
%mend;

/* Standard test bootstrap for pipr modules. */
%macro _pipr_require_assert;
  %if not %sysmacexist(assertTrue) %then %sbmod(assert);
%mend;

/* Normalize common boolean-like values to 1/0. */
%macro _pipr_bool(value, default=0);
  %local _raw _up;
  %let _raw=%superq(value);
  %if %length(%superq(_raw))=0 %then &default;
  %else %do;
    %let _up=%upcase(%superq(_raw));
    %if %sysfunc(indexw(1 Y YES TRUE T ON, &_up)) > 0 %then 1;
    %else %if %sysfunc(indexw(0 N NO FALSE F OFF, &_up)) > 0 %then 0;
    %else &default;
  %end;
%mend;

/* Auto-run a test macro only when __unit_tests=1. */
%macro _pipr_autorun_tests(test_macro);
  %if %_pipr_in_unit_tests %then %do;
    %unquote(%nrstr(%)&test_macro);
  %end;
%mend;

%macro test_pipr_util;
  %_pipr_require_assert;

  %test_suite(Testing pipr util);
    %test_case(tmpds uses prefix and work);
      %let t=%_tmpds(prefix=_t_);
      %assertTrue(%eval(%index(&t, work._t_) = 1), tmpds starts with work._t_);
    %test_summary;

    %test_case(bool helper parses common values);
      %assertEqual(%_pipr_bool(1), 1);
      %assertEqual(%_pipr_bool(YES), 1);
      %assertEqual(%_pipr_bool(true), 1);
      %assertEqual(%_pipr_bool(0), 0);
      %assertEqual(%_pipr_bool(NO), 0);
      %assertEqual(%_pipr_bool(unknown, default=1), 1);
    %test_summary;
  %test_summary;
%mend test_pipr_util;

%_pipr_autorun_tests(test_pipr_util);
