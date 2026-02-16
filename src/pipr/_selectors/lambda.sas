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
  %local _in _out;
  %let _in=%superq(expr);

  data _null_;
    length raw inner $32767;
    raw = strip(symget('_in'));

    if prxmatch('/^lambda\s*\(.*\)$/i', raw) then do;
      openp = index(raw, '(');
      if openp > 0 and substr(raw, length(raw), 1) = ')' then
        raw = substr(raw, openp + 1, length(raw) - openp - 1);
    end;

    raw = strip(raw);
    if length(raw) > 0 and substr(raw, 1, 1) = '~' then raw = strip(substr(raw, 2));

    call symputx('_out', raw, 'L');
  run;

  %let &out_expr=%superq(_out);
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
