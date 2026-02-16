%macro _selector_contains(ds=, needle=, out_cols=);
  %local _needle _where;
  %let _needle=%superq(needle);
  %_sel_require_nonempty(value=%superq(_needle), msg=contains() requires a non-empty substring.);
  %let _where=index(upcase(name), upcase("%superq(_needle)")) > 0;

  %_sel_query_cols(
    ds=&ds,
    where=%superq(_where),
    out_cols=&out_cols,
    empty_msg=contains('%superq(_needle)') matched no columns in &ds.
  );
%mend;

%macro _selector_like(ds=, pattern=, out_cols=);
  %local _pattern _where;
  %let _pattern=%superq(pattern);
  %_sel_require_nonempty(value=%superq(_pattern), msg=like() requires a non-empty SQL LIKE pattern.);
  %let _where=upcase(name) like upcase("%superq(_pattern)");

  %_sel_query_cols(
    ds=&ds,
    where=%superq(_where),
    out_cols=&out_cols,
    empty_msg=like('%superq(_pattern)') matched no columns in &ds.
  );
%mend;

%macro test_selector_contains;
  %_pipr_require_assert;

  %test_suite(Testing contains/like selectors);
    %test_case(contains expands matching substring columns);
      data work._sco;
        length home_state $2 policy_state $2 state_code $8 other 8;
        home_state='CA';
        policy_state='NV';
        state_code='S1';
        other=1;
        output;
      run;

      %_selector_contains(ds=work._sco, needle=state, out_cols=_sco_cols);
      %assertEqual(%upcase(&_sco_cols.), HOME_STATE POLICY_STATE STATE_CODE);
    %test_summary;

    %test_case(like expands sql-like patterns);
      %_selector_like(ds=work._sco, pattern=%str(%state%), out_cols=_sco_like);
      %assertEqual(%upcase(&_sco_like.), HOME_STATE POLICY_STATE STATE_CODE);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _sco; quit;
%mend test_selector_contains;

%_pipr_autorun_tests(test_selector_contains);
