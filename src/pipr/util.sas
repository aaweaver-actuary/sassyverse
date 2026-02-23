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
- _pipr_tmpds
- _pipr_split_parmbuff
- _pipr_tokenize
- _pipr_tokenize_run
- _pipr_tokenize_assign
- _pipr_split_parmbuff_segments
- _pipr_parse_parmbuff
- _pipr_ucl_prepare_input
- _pipr_ucl_transform
- _pipr_ucl_assign
- _pipr_ucl_assign_strip
- _pipr_unbracket_csv_lists
- _pipr_normalize_list
- _pipr_in_unit_tests
- _pipr_require_assert
- _pipr_bool
- _pipr_require_nonempty
- _pipr_strip_matching_quotes
- _pipr_lambda_strip_wrapper
- _pipr_lambda_strip_tilde
- _pipr_lambda_normalize
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

%macro _pipr_tmpds(prefix=_p);
  %_tmpds(prefix=&prefix)
%mend;

%macro _pipr_split_parmbuff(buf=, out_n=, out_prefix=seg);
  %_pipr_split_parmbuff_segments(buf=%superq(buf), out_n=%superq(out_n), out_prefix=%superq(out_prefix));
%mend;

%macro _pipr_util_dbg_enabled;
  %if %symexist(_pipr_util_debug) %then %do;
    %_pipr_bool(%superq(_pipr_util_debug), default=0)
  %end;
  %else %if %symexist(log_level) and "%upcase(%superq(log_level))"="DEBUG" %then 1;
  %else 0;
%mend;

%macro _pipr_util_dbg(msg=);
  %if %_pipr_util_dbg_enabled %then %do;
    %put NOTE: [PIPR.UTIL] %superq(msg);
  %end;
%mend;

%macro _pipr_tokenize_run(expr=, out_prefix=tok, split_on_comma=1, split_on_ws=0, out_count=_pipr_tok_n);
  %local _pt_expr _pt_split_comma _pt_split_ws;
  %global _pipr_tok_expr _pipr_tok_count;
  %global &out_count;
  %let _pt_expr=%superq(expr);
  %let _pipr_tok_expr=%unquote(%superq(_pt_expr));
  %let _pipr_tok_count=0;
  %let _pt_split_comma=%_pipr_bool(%superq(split_on_comma), default=1);
  %let _pt_split_ws=%_pipr_bool(%superq(split_on_ws), default=0);

  %_pipr_util_dbg(msg=_pipr_tokenize_run start out_prefix=%superq(out_prefix) split_comma=&_pt_split_comma split_ws=&_pt_split_ws expr_len=%length(%superq(_pt_expr)));

  data _null_;
    length expr tok $32767 ch quote $1;
    expr = symget('_pipr_tok_expr');
    tok = '';
    quote = '';
    depth = 0;
    n = 0;

    do i = 1 to length(expr);
      ch = substr(expr, i, 1);

      if quote = '' then do;
        if ch = "'" or ch = '"' then quote = ch;
        else if ch = '(' then depth + 1;
        else if ch = ')' and depth > 0 then depth + (-1);
      end;
      else if ch = quote then quote = '';

      is_delim = 0;
      if quote = '' and depth = 0 then do;
        if (&_pt_split_comma) and ch = ',' then is_delim = 1;
        else if (&_pt_split_ws) and ch in (' ', '09'x, '0A'x, '0D'x) then is_delim = 1;
      end;

      if is_delim then do;
        if lengthn(strip(tok)) then do;
          n + 1;
          call symputx(cats("&out_prefix", n), strip(tok), 'G');
          tok = '';
        end;
      end;
      else tok = tok || ch;
    end;

    if lengthn(strip(tok)) then do;
      n + 1;
      call symputx(cats("&out_prefix", n), strip(tok), 'G');
    end;

    call symputx('_pipr_tok_count', n, 'G');
  run;

  %_pipr_ucl_assign(out_text=%superq(out_count), value=%superq(_pipr_tok_count));

  %_pipr_util_dbg(msg=_pipr_tokenize_run done out_count=%superq(out_count) value=%superq(&out_count));
%mend;

%macro _pipr_tokenize_assign(out_n=, count=);
  %_pipr_ucl_assign(out_text=%superq(out_n), value=%superq(count));
%mend;

/* Tokenize an expression at top-level (outside quotes/parentheses).
   Supports configurable delimiters (comma and/or whitespace). */
%macro _pipr_tokenize(expr=, out_n=, out_prefix=tok, split_on_comma=1, split_on_ws=0);
  %global _pipr_tok_n;

  %if %length(%superq(out_n)) %then %do;
    %if not %symexist(&out_n) %then %global &out_n;
  %end;

  %_pipr_tokenize_run(
    expr=%superq(expr),
    out_prefix=%superq(out_prefix),
    split_on_comma=%superq(split_on_comma),
    split_on_ws=%superq(split_on_ws),
    out_count=_pipr_tok_n
  );
  %_pipr_tokenize_assign(out_n=%superq(out_n), count=%superq(_pipr_tok_n));
%mend;

/* Split a parenthesized macro parmbuff string into top-level comma segments. */
%macro _pipr_split_parmbuff_segments(buf=, out_n=, out_prefix=seg);
  %global _pipr_sp_buf _pipr_sp_count;
  %let _pipr_sp_buf=%unquote(%superq(buf));
  %let _pipr_sp_count=0;
  %if %length(%superq(out_n)) %then %do;
    %if not %symexist(&out_n) %then %global &out_n;
  %end;

  data _null_;
    length buf seg $32767 ch quote $1;
    buf = symget('_pipr_sp_buf');

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
        if lengthn(strip(seg)) then do;
          __seg_count + 1;
          /* Segment names are dynamic; publish globally so callers can consume them reliably. */
          call symputx(cats("&out_prefix",__seg_count), strip(seg), 'G');
        end;
        seg = '';
      end;
      else seg = seg || ch;
    end;

    if lengthn(strip(seg)) then do;
      __seg_count + 1;
      call symputx(cats("&out_prefix",__seg_count), strip(seg), 'G');
    end;

    call symputx('_pipr_sp_count',__seg_count, 'G');
  run;

  %_pipr_ucl_assign(out_text=%superq(out_n), value=%superq(_pipr_sp_count));
%mend;

/* Parse parmbuff segments into a normalized stream of named/positional tokens.
   - recognized= is a space-delimited list of named keys (case-insensitive).
   - For each parsed token i, outputs:
       <out_prefix>_kind<i> : N (named) or P (positional)
       <out_prefix>_head<i> : normalized key for named tokens
       <out_prefix>_val<i>  : value payload
*/
%macro _pipr_parse_parmbuff(buf=, recognized=, out_n=, out_prefix=_pb);
  %local _seg_n _i _m _seg _head _eq _val _kind;

  %if not %sysmacexist(_pipr_split_parmbuff_segments) %then
    %_abort(_pipr_parse_parmbuff requires _pipr_split_parmbuff_segments from util.sas.);

  %_pipr_split_parmbuff_segments(
    buf=%superq(buf),
    out_n=_seg_n,
    out_prefix=_pb_seg
  );

  %let _m=0;
  %do _i=1 %to &_seg_n;
    %let _seg=%sysfunc(strip(%superq(_pb_seg&_i)));
    %if %length(%superq(_seg)) > 0 %then %do;
      %let _m=%eval(&_m + 1);
      %let _head=%upcase(%sysfunc(strip(%scan(%superq(_seg), 1, =))));
      %let _eq=%index(%superq(_seg), %str(=));

      %if %sysfunc(indexw(%superq(recognized), &_head)) > 0 %then %do;
        %let _kind=N;
        %if &_eq > 0 %then %let _val=%sysfunc(strip(%substr(%superq(_seg), %eval(&_eq+1))));
        %else %let _val=;
      %end;
      %else %do;
        %let _kind=P;
        %let _val=%superq(_seg);
        %let _head=;
      %end;

      %_pipr_ucl_assign(out_text=%superq(out_prefix)_kind&_m, value=%superq(_kind));
      %_pipr_ucl_assign(out_text=%superq(out_prefix)_head&_m, value=%superq(_head));
      %_pipr_ucl_assign(out_text=%superq(out_prefix)_val&_m, value=%superq(_val));
    %end;
  %end;

  %_pipr_ucl_assign(out_text=%superq(out_n), value=&_m);
%mend;

%macro _pipr_ucl_prepare_input(text=, out_var=_pipr_ucl_in);
  %_pipr_ucl_assign(out_text=%superq(out_var), value=%unquote(%superq(text)));
%mend;

%macro _pipr_ucl_transform(in_var=, out_var=, out_raw_var=);
  data _null_;
    length src result raw_result $32767 ch quote $1;
    src = symget("&in_var");

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

    call symputx("&out_raw_var", raw_result, 'G');

    result = compbl(strip(raw_result));
    call symputx("&out_var", result, 'G');
  run;
%mend;

%macro _pipr_ucl_assign(out_text=, value=);
  %if %length(%superq(out_text)) %then %do;
    %if not %symexist(&out_text) %then %global &out_text;
    %let &out_text=%superq(value);
  %end;
%mend;

%macro _pipr_ucl_assign_strip(out_text=, value=);
  %local _pipr_assign_strip;
  %let _pipr_assign_strip=%sysfunc(strip(%superq(value)));
  %_pipr_ucl_assign(out_text=%superq(out_text), value=%superq(_pipr_assign_strip));
%mend;

/* Convert bracket-wrapped comma lists to space-delimited lists.
   Example: right_keep=[a, b] -> right_keep=a b
   Brackets are removed only for top-level [...] segments outside quotes. */
%macro _pipr_unbracket_csv_lists(text=, out_text=);
  %global _pipr_ucl_in _pipr_ucl_out _pipr_ucl_out_raw;
  %_pipr_ucl_prepare_input(text=%superq(text), out_var=_pipr_ucl_in);
  %let _pipr_ucl_out=;
  %let _pipr_ucl_out_raw=;

  %_pipr_ucl_transform(in_var=_pipr_ucl_in, out_var=_pipr_ucl_out, out_raw_var=_pipr_ucl_out_raw);

  %if %length(%superq(_pipr_ucl_out))=0 and %length(%superq(_pipr_ucl_out_raw))>0 %then %do;
    %let _pipr_ucl_out=%sysfunc(prxchange(%str(s/\s+/ /), -1, %superq(_pipr_ucl_out_raw)));
    %let _pipr_ucl_out=%sysfunc(strip(%superq(_pipr_ucl_out)));
  %end;

  %_pipr_ucl_assign(out_text=%superq(out_text), value=%superq(_pipr_ucl_out));
%mend;

/* Centralized list normalization used across verbs/predicates/validation.
   - collapse_commas=0: preserve commas, enforce ", " spacing.
   - collapse_commas=1: treat commas/whitespace as separators, collapse to single spaces. */
%macro _pipr_normalize_list(text=, collapse_commas=0, out_text=);
  %global _pipr_norm_out;
  %local _collapse;

  %let _pipr_norm_out=%superq(text);
  %let _collapse=%_pipr_bool(%superq(collapse_commas), default=0);

  %if %sysmacexist(_pipr_unbracket_csv_lists) %then %do;
    %_pipr_unbracket_csv_lists(text=%superq(_pipr_norm_out));
    %let _pipr_norm_out=%superq(_pipr_ucl_out);
  %end;

  %if &_collapse %then %do;
    %let _pipr_norm_out=%sysfunc(prxchange(%str(s/[\s,]+/ /), -1, %superq(_pipr_norm_out)));
  %end;
  %else %do;
    %let _pipr_norm_out=%sysfunc(prxchange(%str(s/,\s*/,\, /), -1, %superq(_pipr_norm_out)));
    %let _pipr_norm_out=%sysfunc(prxchange(%str(s/\s+/ /), -1, %superq(_pipr_norm_out)));
  %end;

  %let _pipr_norm_out=%sysfunc(prxchange(%str(s/\s+/ /), -1, %superq(_pipr_norm_out)));
  %let _pipr_norm_out=%sysfunc(strip(%superq(_pipr_norm_out)));
  %_pipr_ucl_assign(out_text=%superq(out_text), value=%superq(_pipr_norm_out));
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

%macro _pipr_require_nonempty(value=, msg=Argument must be non-empty.);
  %if %length(%superq(value))=0 %then %_abort(%superq(msg));
%mend;

%macro _pipr_strip_matching_quotes(text=, out_text=);
  %local _in _out;
  %global _pipr_stripq_in;
  %let _in=%superq(text);
  %let _pipr_stripq_in=%superq(_in);

  data _null_;
    length raw $32767 q $1;
    raw = strip(symget('_pipr_stripq_in'));
    if length(raw) >= 2 then do;
      q = substr(raw, 1, 1);
      if (q = "'" or q = '"') and substr(raw, length(raw), 1) = q then
        raw = substr(raw, 2, length(raw) - 2);
    end;
    call symputx('_out', raw, 'L');
  run;

  %_pipr_ucl_assign(out_text=%superq(out_text), value=%superq(_out));
%mend;

%macro _pipr_lambda_normalize(expr=, out_expr=);
  %global _pipr_lambda_stage1 _pipr_lambda_stage2;
  %local _raw;
  %let _raw=%superq(expr);

  %_pipr_lambda_strip_wrapper(expr=%superq(_raw), out_expr=_pipr_lambda_stage1);
  %_pipr_lambda_strip_tilde(expr=%superq(_pipr_lambda_stage1), out_expr=_pipr_lambda_stage2);

  %_pipr_ucl_assign(out_text=%superq(out_expr), value=%superq(_pipr_lambda_stage2));
%mend;

%macro _pipr_lambda_strip_wrapper(expr=, out_expr=);
  %local _in _out;
  %global _pipr_lambda_wrap_in;
  %let _in=%superq(expr);
  %let _pipr_lambda_wrap_in=%superq(_in);

  data _null_;
    length raw $32767;
    raw = strip(symget('_pipr_lambda_wrap_in'));

    if prxmatch('/^lambda\s*\(.*\)$/i', raw) then do;
      openp = index(raw, '(');
      if openp > 0 and substr(raw, length(raw), 1) = ')' then
        raw = substr(raw, openp + 1, length(raw) - openp - 1);
    end;

    call symputx('_out', raw, 'L');
  run;

  %_pipr_ucl_assign(out_text=%superq(out_expr), value=%superq(_out));
%mend;

%macro _pipr_lambda_strip_tilde(expr=, out_expr=);
  %local _in _out;
  %global _pipr_lambda_tilde_in;
  %let _in=%superq(expr);
  %let _pipr_lambda_tilde_in=%superq(_in);

  data _null_;
    length raw $32767;
    raw = strip(symget('_pipr_lambda_tilde_in'));
    if length(raw) > 0 and substr(raw, 1, 1) = '~' then raw = strip(substr(raw, 2));
    call symputx('_out', raw, 'L');
  run;

  %_pipr_ucl_assign(out_text=%superq(out_expr), value=%superq(_out));
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

      %let t2=%_pipr_tmpds(prefix=_t2_);
      %assertTrue(%eval(%index(&t2, work._t2_) = 1), pipr_tmpds starts with work._t2_);
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

      %_pipr_split_parmbuff(
        buf=%str(name=a, args=b),
        out_n=_n,
        out_prefix=_ps_local_alias
      );
      %assertEqual(&_n., 2);
      %assertEqual(actual=&_ps_local_alias1., expected=%str(name=a));
      %assertEqual(actual=&_ps_local_alias2., expected=%str(args=b));
    %test_summary;

    %test_case(parmbuff parser classifies named and positional segments);
      %_pipr_parse_parmbuff(
        buf=%str(data=work._in, validate=NO, x > 1, out=work._out),
        recognized=%str(DATA OUT VALIDATE),
        out_n=_pp_n,
        out_prefix=_pp
      );

      %assertEqual(&_pp_n., 4);
      %assertEqual(&_pp_kind1., N);
      %assertEqual(&_pp_head1., DATA);
      %assertEqual(actual=&_pp_val1., expected=%str(work._in));

      %assertEqual(&_pp_kind2., N);
      %assertEqual(&_pp_head2., VALIDATE);
      %assertEqual(actual=&_pp_val2., expected=NO);

      %assertEqual(&_pp_kind3., P);
      %assertEqual(actual=&_pp_val3., expected=%str(x > 1));

      %assertEqual(&_pp_kind4., N);
      %assertEqual(&_pp_head4., OUT);
      %assertEqual(actual=&_pp_val4., expected=%str(work._out));
    %test_summary;

    %test_case(shared tokenizer supports comma and whitespace splitting);
      %global _pipr_util_debug;
      %let _pipr_util_debug=1;
      %_pipr_tokenize(
        expr=%str(starts_with('policy') company_numb, ends_with('code')),
        out_n=_pt_n,
        out_prefix=_pt_tok,
        split_on_comma=1,
        split_on_ws=1
      );
      %assertEqual(&_pt_n., 3);
      %assertEqual(actual=&_pt_tok1., expected=%str(starts_with('policy')));
      %assertEqual(actual=&_pt_tok2., expected=company_numb);
      %assertEqual(actual=&_pt_tok3., expected=%str(ends_with('code')));

      %_pipr_tokenize(
        expr=%str(cols=a b c, pred=is_missing(), args=blank_is_missing=0),
        out_n=_pt_n2,
        out_prefix=_pt_tok2,
        split_on_comma=1,
        split_on_ws=0
      );
      %assertEqual(&_pt_n2., 3);
      %assertEqual(actual=&_pt_tok21., expected=%str(cols=a b c));
      %assertEqual(actual=&_pt_tok22., expected=%str(pred=is_missing()));
      %assertEqual(actual=&_pt_tok23., expected=%str(args=blank_is_missing=0));

      %_pipr_tokenize(
        expr=%str(cols=a b c),
        out_n=_pt_n3,
        out_prefix=_pt_tok3,
        split_on_comma=1,
        split_on_ws=0
      );
      %assertEqual(&_pt_n3., 1);
      %assertEqual(actual=&_pt_tok31., expected=%str(cols=a b c));
      %let _pipr_util_debug=0;
    %test_summary;

    %test_case(assign helper writes to caller-scoped target names);
      %local _pt_local_out;
      %let _pt_local_out=;
      %_pipr_ucl_assign(out_text=_pt_local_out, value=%str(local scoped value));
      %assertEqual(actual=%superq(_pt_local_out), expected=%str(local scoped value));
    %test_summary;

    %test_case(assign strip helper trims before assignment);
      %local _pt_local_strip;
      %let _pt_local_strip=;
      %_pipr_ucl_assign_strip(out_text=_pt_local_strip, value=%str(  trimmed value  ));
      %assertEqual(actual=%superq(_pt_local_strip), expected=%str(trimmed value));
    %test_summary;

    %test_case(shared string helpers normalize quotes and lambda syntax);
      %let _pipr_util_debug=1;
      %_pipr_strip_matching_quotes(text=%str('policy_state'), out_text=_pu_uq1);
      %assertEqual(actual=%superq(_pu_uq1), expected=policy_state);

      %_pipr_strip_matching_quotes(text=%str("home_state"), out_text=_pu_uq2);
      %assertEqual(actual=%superq(_pu_uq2), expected=home_state);

      %_pipr_lambda_normalize(expr=%str(lambda(.is_num and .name='POLICY_ID')), out_expr=_pu_l1);
      %assertEqual(actual=%superq(_pu_l1), expected=%str(.is_num and .name='POLICY_ID'));

      %_pipr_lambda_normalize(expr=%str(~.is_char), out_expr=_pu_l2);
      %assertEqual(actual=%superq(_pu_l2), expected=%str(.is_char));

      %_pipr_lambda_strip_wrapper(expr=%str(lambda(.is_char and .x='A')), out_expr=_pu_lw);
      %assertEqual(actual=%superq(_pu_lw), expected=%str(.is_char and .x='A'));

      %_pipr_lambda_strip_tilde(expr=%str(~.is_num), out_expr=_pu_lt);
      %assertEqual(actual=%superq(_pu_lt), expected=%str(.is_num));
      %let _pipr_util_debug=0;
    %test_summary;

    %test_case(shared non-empty guard allows populated values);
      %_pipr_require_nonempty(value=%str(ok), msg=should not abort);
      %assertTrue(1, non-empty guard passed);
    %test_summary;

    %test_case(bracket csv helper rewrites bracket lists);
      %_pipr_normalize_list(
        text=%str(right_keep=[rpt_period_date, experian_bin], on=sb_policy_key)
      );
      %let _pul_norm=%superq(_pipr_norm_out);
      %assertEqual(
        actual=%superq(_pul_norm),
        expected=%str(right_keep=rpt_period_date experian_bin, on=sb_policy_key)
      );
    %test_summary;

    %test_case(bracket csv helper preserves non-bracket spaces);
      %_pipr_normalize_list(
        text=%str(right_keep=company_numb policy_sym policy_numb)
      );
      %let _pul_norm_space=%superq(_pipr_norm_out);
      %assertEqual(
        actual=%superq(_pul_norm_space),
        expected=%str(right_keep=company_numb policy_sym policy_numb)
      );
    %test_summary;

    %test_case(central normalizer collapses commas for name lists);
      %_pipr_normalize_list(text=%str([a, b], c), collapse_commas=1);
      %assertEqual(actual=%superq(_pipr_norm_out), expected=%str(a b c));
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
