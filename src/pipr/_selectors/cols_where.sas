/* MODULE DOC
File: src/pipr/_selectors/cols_where.sas

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
- _selector_cols_where
- test_selector_cols_where

7) Expected side effects from running/include
- Defines 2 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: _pipr_autorun_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
*/
%macro _selector_cols_where(ds=, predicate=, out_cols=);
  %local _pred;
  %_sel_cols_where_predicate(predicate=%superq(predicate), out_predicate=_pred);

  %_sel_collect_by_predicate(
    ds=&ds,
    predicate=%superq(_pred),
    out_cols=&out_cols,
    empty_msg=cols_where(%superq(predicate)) matched no columns in &ds.
  );
%mend;

%macro test_selector_cols_where;
  %_pipr_require_assert;

  %test_suite(Testing cols_where selector);
    %test_case(cols_where supports lambda shorthand and metadata placeholders);
      data work._scw;
        length policy_id 8 policy_code $8 home_state $2 claim_state $2 amount 8;
        policy_id=1;
        policy_code='A1';
        home_state='CA';
        claim_state='NV';
        amount=100;
        output;
      run;

      %_selector_cols_where(ds=work._scw, predicate=%str(~.is_char), out_cols=_scw_chars);
      %assertEqual(%upcase(&_scw_chars.), POLICY_CODE HOME_STATE CLAIM_STATE);

      %_selector_cols_where(ds=work._scw, predicate=%lambda(.is_num), out_cols=_scw_nums_all);
      %assertEqual(%upcase(&_scw_nums_all.), POLICY_ID AMOUNT);

      %_selector_cols_where(
        ds=work._scw,
        predicate=%str(lambda(.is_num and .name='POLICY_ID')),
        out_cols=_scw_nums
      );
      %assertEqual(%upcase(&_scw_nums.), POLICY_ID);

      %_selector_cols_where(
        ds=work._scw,
        predicate=%str(.is_char and prxmatch('/state/i', .name) > 0),
        out_cols=_scw_states
      );
      %assertEqual(%upcase(&_scw_states.), HOME_STATE CLAIM_STATE);

      %_selector_cols_where(
        ds=work._scw,
        predicate=%str(.is_char and prxmatch('/policy/i', .x) > 0),
        out_cols=_scw_x_alias
      );
      %assertEqual(%upcase(&_scw_x_alias.), POLICY_CODE);

      %_selector_cols_where(
        ds=work._scw,
        predicate=%str(.type='num' and .length=8 and .column='AMOUNT'),
        out_cols=_scw_num_meta
      );
      %assertEqual(%upcase(&_scw_num_meta.), AMOUNT);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _scw; quit;
%mend test_selector_cols_where;

%_pipr_autorun_tests(test_selector_cols_where);
