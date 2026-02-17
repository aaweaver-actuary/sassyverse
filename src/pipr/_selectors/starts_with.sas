/* MODULE DOC
File: src/pipr/_selectors/starts_with.sas

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
- _selector_starts_with
- test_selector_starts_with

7) Expected side effects from running/include
- Defines 2 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: _pipr_autorun_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
*/
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
