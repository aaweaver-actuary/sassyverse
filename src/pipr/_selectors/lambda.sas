/* MODULE DOC
File: src/pipr/_selectors/lambda.sas

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
- lambda
- _sel_lambda_normalize
- test_selector_lambda

7) Expected side effects from running/include
- Defines 3 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: _pipr_autorun_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
*/
/* Lambda helpers for selector predicates. */

%macro lambda() / parmbuff;
  %local _buf _out;
  %let _buf=%superq(syspbuff);
  data _null_;
    length raw $32767;
    raw = strip(symget('_buf'));
    if length(raw) >= 2 and substr(raw, 1, 1) = '(' and substr(raw, length(raw), 1) = ')' then
      raw = substr(raw, 2, length(raw) - 2);
    if upcase(substr(raw, 1, 5)) = 'EXPR=' then raw = substr(raw, 6);
    call symputx('_out', strip(raw), 'L');
  run;

  ~%superq(_out)
%mend;

%macro _sel_lambda_normalize(expr=, out_expr=);
  %if not %sysmacexist(_pipr_lambda_normalize) %then %_abort(selector lambda requires _pipr_lambda_normalize from util.sas.);
  %_pipr_lambda_normalize(expr=%superq(expr), out_expr=&out_expr);
%mend;

%macro test_selector_lambda;
  %_pipr_require_assert;

  %test_suite(Testing selector lambda helpers);
    %test_case(lambda wrapper and normalize);
      %let _lam=%lambda(%str(.is_char and prxmatch('/state/i', .name) > 0));
      %_sel_lambda_normalize(expr=%superq(_lam), out_expr=_lam_norm);

      %assertEqual(
        %superq(_lam_norm),
        %str(.is_char and prxmatch('/state/i', .name) > 0)
      );
    %test_summary;

    %test_case(lambda wrapper supports commas without extra quoting);
      %let _lam_c=%lambda(prxmatch('/state/i', .name) > 0);
      %_sel_lambda_normalize(expr=%superq(_lam_c), out_expr=_lam_norm_c);
      %assertEqual(%superq(_lam_norm_c), %str(prxmatch('/state/i', .name) > 0));
    %test_summary;

    %test_case(normalize supports lambda(...) wrapper);
      %_sel_lambda_normalize(
        expr=%str(lambda(.is_num and .name='POLICY_ID')),
        out_expr=_lam_norm2
      );
      %assertEqual(%superq(_lam_norm2), %str(.is_num and .name='POLICY_ID'));
    %test_summary;

    %test_case(lambda wrapper supports expr= named argument and normalize strips leading tilde);
      %let _lam_expr=%lambda(expr=%str(.is_char and .x='HOME_STATE'));
      %_sel_lambda_normalize(expr=%superq(_lam_expr), out_expr=_lam_norm3);
      %assertEqual(%superq(_lam_norm3), %str(.is_char and .x='HOME_STATE'));

      %_sel_lambda_normalize(expr=%str(~.is_char), out_expr=_lam_norm4);
      %assertEqual(%superq(_lam_norm4), %str(.is_char));
    %test_summary;
  %test_summary;
%mend test_selector_lambda;

%_pipr_autorun_tests(test_selector_lambda);
