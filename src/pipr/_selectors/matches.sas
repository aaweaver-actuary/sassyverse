%macro _selector_matches(ds=, regex=, out_cols=);
  %local _regex _prx _re_ok;
  %global _sel_matches_re;

  %let _regex=%superq(regex);
  %_sel_require_nonempty(value=%superq(_regex), msg=matches() requires a non-empty regex pattern.);
  %_sel_regex_to_prx(regex=%superq(_regex), out_prx=_prx, default_flags=i);
  %_sel_require_nonempty(value=%superq(_prx), msg=matches() could not parse regex pattern.);

  %let _sel_matches_re=%superq(_prx);
  %let _re_ok=1;
  data _null_;
    _sel_re = prxparse(symget('_sel_matches_re'));
    if missing(_sel_re) then call symputx('_re_ok', 0, 'L');
    else call prxfree(_sel_re);
  run;
  %if &_re_ok = 0 %then %_abort(matches() received an invalid regex pattern: %superq(_regex));

  %_sel_collect_by_predicate(
    ds=&ds,
    predicate=%str(prxmatch(symget('_sel_matches_re'), strip(name)) > 0),
    out_cols=&out_cols,
    empty_msg=matches('%superq(_regex)') matched no columns in &ds.
  );
%mend;

%macro test_selector_matches;
  %_pipr_require_assert;

  %test_suite(Testing matches selector);
    %test_case(matches expands regex-based column matches);
      data work._smx;
        length policy_id 8 policy_code $8 home_state $2 claim_state $2 state_code $8 company_numb 8;
        policy_id=1;
        policy_code='P1';
        home_state='CA';
        claim_state='NV';
        state_code='S1';
        company_numb=99;
        output;
      run;

      %_selector_matches(ds=work._smx, regex=%str(state$), out_cols=_smx_cols);
      %assertEqual(%upcase(&_smx_cols.), HOME_STATE CLAIM_STATE);

      %_selector_matches(ds=work._smx, regex=%str(/^policy_/i), out_cols=_smx_cols2);
      %assertEqual(%upcase(&_smx_cols2.), POLICY_ID POLICY_CODE);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _smx; quit;
%mend test_selector_matches;

%_pipr_autorun_tests(test_selector_matches);
