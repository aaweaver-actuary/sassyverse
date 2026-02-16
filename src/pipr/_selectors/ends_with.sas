%macro _selector_ends_with(ds=, suffix=, out_cols=);
  %local _suffix _where;
  %let _suffix=%superq(suffix);
  %_sel_require_nonempty(value=%superq(_suffix), msg=ends_with() requires a non-empty suffix.);
  %let _where=upcase(name) like cats('%', upcase("%superq(_suffix)"));

  %_sel_query_cols(
    ds=&ds,
    where=%superq(_where),
    out_cols=&out_cols,
    empty_msg=ends_with('%superq(_suffix)') matched no columns in &ds.
  );
%mend;

%macro test_selector_ends_with;
  %_pipr_require_assert;

  %test_suite(Testing ends_with selector);
    %test_case(expands matching suffix columns);
      data work._sew;
        length policy_code $8 home_code $8 policy_id 8;
        policy_code='A';
        home_code='B';
        policy_id=1;
        output;
      run;

      %_selector_ends_with(ds=work._sew, suffix=code, out_cols=_sew_cols);
      %assertEqual(%upcase(&_sew_cols.), POLICY_CODE HOME_CODE);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _sew; quit;
%mend test_selector_ends_with;

%_pipr_autorun_tests(test_selector_ends_with);
