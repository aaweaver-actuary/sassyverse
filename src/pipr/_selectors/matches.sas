/* MODULE DOC
File: src/pipr/_selectors/matches.sas

1) Purpose in overall project
- Selector subsystem that converts tidyselect-like expressions into concrete column lists.

2) High-level approach
- Normalizes selector tokens/calls, maps them to metadata queries or predicate checks, and returns de-duplicated ordered column names.

3) Code organization and why this scheme was chosen
- Shared selector utilities hold parser/query logic; leaf selector modules stay small and focused on one selector behavior.
- Code is organized as helper macros first, public API second, and tests/autorun guards last to reduce contributor onboarding time and import risk.

4) Detailed pseudocode algorithm
- Normalize selector expression and tokenize respecting nested parentheses/quotes.
- For each token, detect selector call vs literal column name.
- Dispatch selector call to corresponding implementation macro.
- Query dictionary metadata or evaluate predicate against candidate columns.
- Append matches uniquely while preserving encountered order.
- Return final column list or raise explicit empty-selection error when required.

5) Acknowledged implementation deficits
- Selector grammar is intentionally constrained compared with full tidyselect semantics.
- Metadata-driven selection depends on dictionary table availability and naming normalization.
- Contributor docs are still text comments; there is no generated API reference yet.

6) Macros defined in this file
- _selector_matches
- test_selector_matches

7) Expected side effects from running/include
- Defines 2 macro(s) in the session macro catalog.
- May create/update GLOBAL macro variable(s): _sel_matches_re.
- Executes top-level macro call(s) on include: _pipr_autorun_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
*/
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

      %_selector_matches(ds=work._smx, regex=%str(/^POLICY_/), out_cols=_smx_cols3);
      %assertEqual(%upcase(&_smx_cols3.), POLICY_ID POLICY_CODE);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _smx; quit;
%mend test_selector_matches;

%_pipr_autorun_tests(test_selector_matches);
