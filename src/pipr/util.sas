/* MODULE DOC
File: src/pipr/util.sas

1) Purpose in overall project
- Shared pipr support utilities and validation helpers used across selectors, verbs, and pipeline execution.

2) High-level approach
- Provides focused helper macros for temporary names, boolean parsing, column/dataset checks, and common assertions.

3) Code organization and why this scheme was chosen
- General utilities are separated from strict validation helpers to keep call-sites readable and minimize circular dependencies.
- Code is organized as helper macros first, public API second, and tests/autorun guards last to reduce contributor onboarding time and import risk.

4) Detailed pseudocode algorithm
- Define helper macros for temp dataset naming and safe boolean parsing.
- Define dataset/column validation primitives with explicit error messages.
- Expose test/bootstrap helpers so module tests can run consistently.
- When requested by verbs/pipeline, run validations before executing heavy transformations.
- Fail fast on incompatible metadata (missing columns, key mismatches, etc.).

5) Acknowledged implementation deficits
- Validation helpers intentionally optimize for clarity over minimal runtime overhead.
- Some helper contracts rely on callers to pass normalized inputs.
- Contributor docs are still text comments; there is no generated API reference yet.

6) Macros defined in this file
- _abort
- _tmpds
- _pipr_split_parmbuff_segments
- _pipr_unbracket_csv_lists
- _pipr_in_unit_tests
- _pipr_require_assert
- _pipr_bool
- _pipr_autorun_tests
- test_pipr_util

7) Expected side effects from running/include
- Defines 8 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: _pipr_autorun_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
*/
/*
    Abort the SAS session with a given error message.
    Usage: %_abort(Some error occurred)
*/
%macro _abort(msg);
  %put ERROR: &msg;
  %abort cancel;
%mend;


/*
    Generate a temporary dataset name with a given prefix. The name is based on the current datetime to ensure uniqueness.
    Usage: %_tmpds(prefix=mytemp_)
*/
%macro _tmpds(prefix=_p);
  %sysfunc(cats(work., &prefix., %sysfunc(putn(%sysfunc(datetime()), hex16.))))
%mend;

/* Split a parenthesized macro parmbuff string into top-level comma segments. */
%macro _pipr_split_parmbuff_segments(buf=, out_n=, out_prefix=seg);
  %if %length(%superq(out_n)) %then %do;
    %if not %symexist(&out_n) %then %global &out_n;
  %end;

  data _null_;
    length buf seg $32767 ch quote $1;
    buf = symget('buf');

    if length(buf) >= 2 and substr(buf, 1, 1) = '(' and substr(buf, length(buf), 1) = ')' then
      buf = substr(buf, 2, length(buf) - 2);

    depth = 0;
    seg = '';
    quote = '';
   __seg_count = 0;

    do i = 1 to length(buf);
      ch = substr(buf, i, 1);

      if quote = '' then do;
        if ch = "'" or ch = '"' then quote = ch;
        else if ch = '(' then depth + 1;
        else if ch = ')' and depth > 0 then depth + (-1);
      end;
      else if ch = quote then quote = '';

      if quote = '' and depth = 0 and ch = ',' then do;
       __seg_count + 1;
        /* Segment names are dynamic; publish globally so callers can consume them reliably. */
        call symputx(cats(symget('out_prefix'),__seg_count), strip(seg), 'G');
        seg = '';
      end;
      else seg = cats(seg, ch);
    end;

    if length(strip(seg)) then do;
     __seg_count + 1;
      call symputx(cats(symget('out_prefix'),__seg_count), strip(seg), 'G');
    end;

    call symputx(symget('out_n'),__seg_count, 'F');
  run;
%mend;

%macro _pipr_ucl_prepare_input(text=, out_var=_pipr_ucl_in);
  %global &out_var _pipr_ucl_in_len;
  %let &out_var=%unquote(%superq(text));
  %let _pipr_ucl_in_len=%length(%superq(&out_var));
%mend;

%macro _pipr_ucl_transform(in_var=, out_var=, out_raw_var=);
  %global _pipr_ucl_srclen _pipr_ucl_outlen _pipr_ucl_outrawlen _pipr_ucl_emitcnt _pipr_ucl_pdepth _pipr_ucl_bdepth;
  %let _pipr_ucl_srclen=0;
  %let _pipr_ucl_outlen=0;
  %let _pipr_ucl_outrawlen=0;
  %let _pipr_ucl_emitcnt=0;
  %let _pipr_ucl_pdepth=0;
  %let _pipr_ucl_bdepth=0;

  data _null_;
    length src result raw_result $32767 ch quote $1;
    src = symget("&in_var");
    call symputx('_pipr_ucl_srclen', lengthn(src), 'G');

    result = '';
    raw_result = '';
    quote = '';
    paren_depth = 0;
    bracket_depth = 0;
    emit_count = 0;
    pos = 0;

    do i = 1 to lengthn(src);
      ch = substr(src, i, 1);
      emitted = 0;

      if quote = '' then do;
        if ch = "'" or ch = '"' then do;
          quote = ch;
          pos + 1;
          substr(result, pos, 1) = ch;
          emitted = 1;
        end;
        else if ch = '(' then do;
          paren_depth + 1;
          pos + 1;
          substr(result, pos, 1) = ch;
          emitted = 1;
        end;
        else if ch = ')' and paren_depth > 0 then do;
          paren_depth + (-1);
          pos + 1;
          substr(result, pos, 1) = ch;
          emitted = 1;
        end;
        else if ch = '[' then bracket_depth + 1;
        else if ch = ']' and bracket_depth > 0 then bracket_depth + (-1);
        else if ch = ',' and bracket_depth > 0 then do;
          pos + 1;
          substr(result, pos, 1) = ' ';
          emitted = 1;
        end;
        else do;
          pos + 1;
          substr(result, pos, 1) = ch;
          emitted = 1;
        end;
      end;
      else do;
        pos + 1;
        substr(result, pos, 1) = ch;
        emitted = 1;
        if ch = quote then quote = '';
      end;

      if emitted then emit_count + 1;
    end;

    if pos > 0 then raw_result = substr(result, 1, pos);
    else raw_result = '';

    call symputx('_pipr_ucl_outrawlen', lengthn(raw_result), 'G');
    call symputx("&out_raw_var", raw_result, 'G');

    result = compbl(strip(raw_result));
    call symputx('_pipr_ucl_outlen', lengthn(result), 'G');
    call symputx('_pipr_ucl_emitcnt', emit_count, 'G');
    call symputx('_pipr_ucl_pdepth', paren_depth, 'G');
    call symputx('_pipr_ucl_bdepth', bracket_depth, 'G');
    call symputx("&out_var", result, 'G');
  run;
%mend;

%macro _pipr_ucl_assign(out_text=, value=);
  %if %length(%superq(out_text)) %then %do;
    %if not %symexist(&out_text) %then %global &out_text;
    %let &out_text=%superq(value);
  %end;
%mend;

/* Convert bracket-wrapped comma lists to space-delimited lists.
   Example: right_keep=[a, b] -> right_keep=a b
   Brackets are removed only for top-level [...] segments outside quotes. */
%macro _pipr_unbracket_csv_lists(text=, out_text=);
  %global _pipr_ucl_in _pipr_ucl_out _pipr_ucl_out_raw;
  %_pipr_ucl_prepare_input(text=%superq(text), out_var=_pipr_ucl_in);
  %let _pipr_ucl_out=;
  %let _pipr_ucl_out_raw=;

  %if %sysmacexist(dbg) %then %do;
    %dbg(msg=%str(_pipr_unbracket_csv_lists: start out_text=%superq(out_text)));
    %dbg(msg=%str(_pipr_unbracket_csv_lists: raw input=%superq(_pipr_ucl_in)));
    %dbg(msg=%str(_pipr_unbracket_csv_lists: macro_input_len=&_pipr_ucl_in_len));
  %end;

  %_pipr_ucl_transform(in_var=_pipr_ucl_in, out_var=_pipr_ucl_out, out_raw_var=_pipr_ucl_out_raw);

  %if %length(%superq(_pipr_ucl_out))=0 and %length(%superq(_pipr_ucl_out_raw))>0 %then %do;
    %let _pipr_ucl_out=%sysfunc(compbl(%sysfunc(strip(%superq(_pipr_ucl_out_raw)))));
  %end;

  %_pipr_ucl_assign(out_text=%superq(out_text), value=%superq(_pipr_ucl_out));

  %if %sysmacexist(dbg) %then %do;
    %dbg(msg=%str(_pipr_unbracket_csv_lists: src_len=&_pipr_ucl_srclen out_raw_len=&_pipr_ucl_outrawlen out_len=&_pipr_ucl_outlen));
    %dbg(msg=%str(_pipr_unbracket_csv_lists: emit_count=&_pipr_ucl_emitcnt paren_depth=&_pipr_ucl_pdepth bracket_depth=&_pipr_ucl_bdepth));
    %dbg(msg=%str(_pipr_unbracket_csv_lists: normalized_raw=%superq(_pipr_ucl_out_raw)));
    %dbg(msg=%str(_pipr_unbracket_csv_lists: normalized=%superq(_pipr_ucl_out)));
    %if %length(%superq(out_text)) %then %dbg(msg=%str(_pipr_unbracket_csv_lists: assigned %superq(out_text)=%superq(&out_text)));
  %end;
%mend;

/* Returns 1 when unit tests are enabled for this session, else 0. */
%macro _pipr_in_unit_tests;
  %if %symexist(__unit_tests) %then %do;
    %if %superq(__unit_tests)=1 %then 1;
    %else 0;
  %end;
  %else 0;
%mend;

/* Standard test bootstrap for pipr modules. */
%macro _pipr_require_assert;
  %if not %sysmacexist(assertTrue) %then %sbmod(assert);
%mend;

/* Normalize common boolean-like values to 1/0. */
%macro _pipr_bool(value, default=0);
  %local _raw _up;
  %let _raw=%superq(value);
  %if %length(%superq(_raw))=0 %then &default;
  %else %do;
    %let _up=%upcase(%superq(_raw));
    %if %sysfunc(indexw(1 Y YES TRUE T ON, &_up)) > 0 %then 1;
    %else %if %sysfunc(indexw(0 N NO FALSE F OFF, &_up)) > 0 %then 0;
    %else &default;
  %end;
%mend;

/* Auto-run a test macro only when __unit_tests=1. */
%macro _pipr_autorun_tests(test_macro);
  %if %_pipr_in_unit_tests %then %do;
    %unquote(%nrstr(%)&test_macro);
  %end;
%mend;

%macro test_pipr_util;
  %_pipr_require_assert;
  %local _ut_saved _ps_n;

  %test_suite(Testing pipr util);
    %test_case(tmpds uses prefix and work);
      %let t=%_tmpds(prefix=_t_);
      %assertTrue(%eval(%index(&t, work._t_) = 1), tmpds starts with work._t_);
    %test_summary;

    %test_case(bool helper parses common values);
      %assertEqual(%_pipr_bool(1), 1);
      %assertEqual(%_pipr_bool(YES), 1);
      %assertEqual(%_pipr_bool(true), 1);
      %assertEqual(%_pipr_bool(on), 1);
      %assertEqual(%_pipr_bool(0), 0);
      %assertEqual(%_pipr_bool(NO), 0);
      %assertEqual(%_pipr_bool(OFF), 0);
      %assertEqual(%_pipr_bool(, default=1), 1);
      %assertEqual(%_pipr_bool(unknown, default=1), 1);
    %test_summary;

    %test_case(parmbuff splitter handles nested commas and quotes);
      %_pipr_split_parmbuff_segments(
        buf=%str(mutate(flag=ifc(x>1,1,0)), data=work._in, note='a,b'),
        out_n=_ps_n,
        out_prefix=_ps_seg
      );
      %assertEqual(&_ps_n., 3);
      %assertEqual(&_ps_seg1., mutate(flag=ifc(x>1,1,0)));
      %assertEqual(actual=&_ps_seg2., expected=%str(data=work._in));
      %assertEqual(actual=&_ps_seg3., expected=%str(note='a,b'));
    %test_summary;

    %test_case(parmbuff splitter supports local out_n names used by callers);
      %local _n;
      %_pipr_split_parmbuff_segments(
        buf=%str(name=a, args=b),
        out_n=_n,
        out_prefix=_ps_local
      );
      %assertEqual(&_n., 2);
      %assertEqual(actual=&_ps_local1., expected=%str(name=a));
      %assertEqual(actual=&_ps_local2., expected=%str(args=b));
    %test_summary;

    %test_case(bracket csv helper rewrites bracket lists);
      %_pipr_unbracket_csv_lists(
        text=%str(right_keep=[rpt_period_date, experian_bin], on=sb_policy_key)
      );
      %let _pul_norm=%superq(_pipr_ucl_out);
      %if %sysmacexist(dbg) %then %dbg(msg=%str(test_pipr_util: _pul_norm=%superq(_pul_norm)));
      %assertEqual(
        actual=%superq(_pul_norm),
        expected=%str(right_keep=rpt_period_date experian_bin, on=sb_policy_key)
      );
    %test_summary;

    %test_case(bracket csv helper preserves non-bracket spaces);
      %_pipr_unbracket_csv_lists(
        text=%str(right_keep=company_numb policy_sym policy_numb)
      );
      %let _pul_norm_space=%superq(_pipr_ucl_out);
      %if %sysmacexist(dbg) %then %dbg(msg=%str(test_pipr_util: _pul_norm_space=%superq(_pul_norm_space)));
      %assertEqual(
        actual=%superq(_pul_norm_space),
        expected=%str(right_keep=company_numb policy_sym policy_numb)
      );
    %test_summary;

    %test_case(ucl transform helper works directly);
      %global _ucl_test_in _ucl_test_out;
      %let _ucl_test_in=%str(right_keep=[rpt_period_date, experian_bin], on=sb_policy_key);
      %let _ucl_test_out=;
      %global _ucl_test_out_raw;
      %let _ucl_test_out_raw=;
      %_pipr_ucl_transform(in_var=_ucl_test_in, out_var=_ucl_test_out, out_raw_var=_ucl_test_out_raw);
      %assertTrue(%eval(%length(%superq(_ucl_test_out_raw)) > 0), ucl transform emits non-empty raw output);
      %assertEqual(
        actual=%superq(_ucl_test_out),
        expected=%str(right_keep=rpt_period_date experian_bin, on=sb_policy_key)
      );
    %test_summary;

    %test_case(ucl prepare helper unquotes input);
      %global _ucl_prepare;
      %let _ucl_prepare=;
      %_pipr_ucl_prepare_input(text=%str(right_keep=[a, b]), out_var=_ucl_prepare);
      %assertEqual(actual=%superq(_ucl_prepare), expected=%str(right_keep=[a, b]));
    %test_summary;

    %test_case(ucl assign helper writes caller macro var);
      %global _ucl_assign_out;
      %let _ucl_assign_out=;
      %_pipr_ucl_assign(out_text=_ucl_assign_out, value=%str(alpha beta));
      %assertEqual(actual=%superq(_ucl_assign_out), expected=%str(alpha beta));
    %test_summary;
  %test_summary;
%mend test_pipr_util;

%_pipr_autorun_tests(test_pipr_util);
