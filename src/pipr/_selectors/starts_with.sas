%macro _selector_starts_with(ds=, prefix=, out_cols=);
  %local _prefix _where;
  %let _prefix=%superq(prefix);
  %_sel_require_nonempty(value=%superq(_prefix), msg=starts_with() requires a non-empty prefix.);
  %let _where=upcase(name) like cats(upcase("%superq(_prefix)"), '%');

  %_sel_query_cols(
    ds=&ds,
    where=%superq(_where),
    out_cols=&out_cols,
    empty_msg=starts_with('%superq(_prefix)') matched no columns in &ds.
  );
%mend;

%macro test_selector_starts_with;
  %_pipr_require_assert;

  %test_suite(Testing starts_with selector);
    %test_case(expands matching prefix columns);
      data work._ssw;
        length policy_id 8 policy_type $12 company_numb 8;
        policy_id=1;
        policy_type='A';
        company_numb=99;
        output;
      run;

      %_selector_starts_with(ds=work._ssw, prefix=policy, out_cols=_ssw_cols);
      %assertEqual(%upcase(&_ssw_cols.), POLICY_ID POLICY_TYPE);
    %test_summary;

    %test_case(starts_with matching is case-insensitive);
      %_selector_starts_with(ds=work._ssw, prefix=PoLiCy, out_cols=_ssw_cols2);
      %assertEqual(%upcase(&_ssw_cols2.), POLICY_ID POLICY_TYPE);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _ssw; quit;
%mend test_selector_starts_with;

%_pipr_autorun_tests(test_selector_starts_with);
