/* MODULE DOC
File: src/pipr/_selectors/contains.sas

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
- _selector_contains
- _selector_like
- test_selector_contains

7) Expected side effects from running/include
- Defines 3 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: _pipr_autorun_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
*/
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

      %_selector_contains(ds=work._sco, needle=STATE, out_cols=_sco_cols2);
      %assertEqual(%upcase(&_sco_cols2.), HOME_STATE POLICY_STATE STATE_CODE);
    %test_summary;

    %test_case(like expands sql-like patterns);
      %_selector_like(ds=work._sco, pattern=%str(%state%), out_cols=_sco_like);
      %assertEqual(%upcase(&_sco_like.), HOME_STATE POLICY_STATE STATE_CODE);
    %test_summary;

    %test_case(like matching is case-insensitive);
      %_selector_like(ds=work._sco, pattern=%str(%STATE%), out_cols=_sco_like2);
      %assertEqual(%upcase(&_sco_like2.), HOME_STATE POLICY_STATE STATE_CODE);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _sco; quit;
%mend test_selector_contains;

%_pipr_autorun_tests(test_selector_contains);
