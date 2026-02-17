/* MODULE DOC
File: src/pipr/_selectors/ends_with.sas

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
- _selector_ends_with
- test_selector_ends_with

7) Expected side effects from running/include
- Defines 2 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: _pipr_autorun_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
*/
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

    %test_case(ends_with matching is case-insensitive);
      %_selector_ends_with(ds=work._sew, suffix=CoDe, out_cols=_sew_cols2);
      %assertEqual(%upcase(&_sew_cols2.), POLICY_CODE HOME_CODE);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _sew; quit;
%mend test_selector_ends_with;

%_pipr_autorun_tests(test_selector_ends_with);
