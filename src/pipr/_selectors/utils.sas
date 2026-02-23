/* MODULE DOC
File: src/pipr/_selectors/utils.sas

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
- _sel_unquote
- _sel_require_nonempty
- _sel_query_cols
- _sel_query_cols_run
- _sel_regex_to_prx
- _sel_regex_to_prx_core
- _sel_cols_where_predicate
- _sel_cols_where_rewrite
- _sel_collect_by_predicate
- _sel_tokenize
- _sel_parse_call
- _sel_list_append_unique
- _sel_expand_token
- _sel_expand
- test_selector_utils

7) Expected side effects from running/include
- Defines 12 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: _pipr_autorun_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
*/
/* Shared selector utilities for select() expansion. */

%macro _sel_dbg_enabled;
  %if %symexist(_pipr_sel_debug) %then %do;
    %_pipr_bool(%superq(_pipr_sel_debug), default=0)
  %end;
  %else %if %symexist(log_level) and "%upcase(%superq(log_level))"="DEBUG" %then 1;
  %else 0;
%mend;

%macro _sel_dbg(msg=);
  %if %_sel_dbg_enabled %then %do;
    %if %sysmacexist(dbg) %then %dbg(msg=%str([PIPR.SEL] )%superq(msg));
    %else %put NOTE: [PIPR.SEL] %superq(msg);
  %end;
%mend;

%macro _sel_out_assign(out_var=, value=);
  %if %length(%superq(out_var)) %then %do;
    %_pipr_ucl_assign(out_text=%superq(out_var), value=%superq(value));
  %end;
%mend;

%macro _sel_unquote(text=, out_text=);
  %_sel_dbg(msg=_sel_unquote start out_text=%superq(out_text) text=%superq(text));
  %if not %sysmacexist(_pipr_strip_matching_quotes) %then %_abort(selectors utils require _pipr_strip_matching_quotes from util.sas.);
  %_pipr_strip_matching_quotes(text=%superq(text), out_text=&out_text);
  %_sel_dbg(msg=_sel_unquote done out_text=%superq(out_text));
%mend;

%macro _sel_require_nonempty(value=, msg=Selector argument must be non-empty.);
  %if not %sysmacexist(_pipr_require_nonempty) %then %_abort(selectors utils require _pipr_require_nonempty from util.sas.);
  %_pipr_require_nonempty(value=%superq(value), msg=%superq(msg));
%mend;

%macro _sel_query_cols(ds=, where=, out_cols=, empty_msg=select() selector matched no columns.);
  %local _lib _mem _where _empty;
  %_ds_split(&ds, _lib, _mem);
  %let _where=%superq(where);
  %let _empty=%superq(empty_msg);
  %_sel_require_nonempty(value=%superq(_where), msg=Internal selector error: where= clause cannot be empty.);

  %_sel_query_cols_run(lib=%superq(_lib), mem=%superq(_mem), where=%superq(_where), out_cols=%superq(out_cols));

  %if %length(%superq(&out_cols))=0 %then %_abort(%superq(_empty));
%mend;

%macro _sel_query_cols_run(lib=, mem=, where=, out_cols=);
  %_sel_dbg(msg=_sel_query_cols_run lib=%superq(lib) mem=%superq(mem) where=%superq(where));
  proc sql noprint;
    select name into :&out_cols separated by ' '
    from sashelp.vcolumn
    where libname="%superq(lib)"
      and memname="%superq(mem)"
      and %unquote(%superq(where))
    order by varnum;
  quit;
  %_sel_dbg(msg=_sel_query_cols_run out_cols=%superq(out_cols) value=%superq(&out_cols));
%mend;

%macro _sel_regex_to_prx(regex=, out_prx=, default_flags=i);
  %local _out;
  %_sel_regex_to_prx_core(regex=%superq(regex), default_flags=%superq(default_flags), out_prx=_out);
  %_sel_out_assign(out_var=%superq(out_prx), value=%superq(_out));
%mend;

%macro _sel_regex_to_prx_core(regex=, default_flags=i, out_prx=);
  %local _in _flags _out;
  %let _in=%superq(regex);
  %let _flags=%superq(default_flags);
  %_sel_dbg(msg=_sel_regex_to_prx_core start regex=%superq(_in) flags=%superq(_flags));

  data _null_;
    length raw body flags out $32767;
    raw = strip(symget('_in'));
    flags = strip(symget('_flags'));
    out = '';

    if length(raw) then do;
      if prxmatch('/^\/.*\/[A-Za-z]*$/', raw) then out = raw;
      else do;
        body = tranwrd(raw, '/', '\/');
        out = cats('/', body, '/', flags);
      end;
    end;

    call symputx('_out', out, 'L');
  run;

  %_sel_out_assign(out_var=%superq(out_prx), value=%superq(_out));
  %_sel_dbg(msg=_sel_regex_to_prx_core done out=%superq(_out));
%mend;

%macro _sel_cols_where_predicate(predicate=, out_predicate=);
  %local _raw _out;
  %if not %sysmacexist(_sel_lambda_normalize) %then %_abort(cols_where() requires selector lambda helpers to be loaded.);
  %_sel_lambda_normalize(expr=%superq(predicate), out_expr=_raw);
  %_sel_require_nonempty(value=%superq(_raw), msg=cols_where() requires a non-empty predicate expression.);

  %_sel_cols_where_rewrite(raw=%superq(_raw), out_raw=_out);
  %_sel_out_assign(out_var=%superq(out_predicate), value=%superq(_out));
%mend;

%macro _sel_cols_where_rewrite(raw=, out_raw=);
  %local _in _out;
  %let _in=%superq(raw);
  %_sel_dbg(msg=_sel_cols_where_rewrite start raw=%superq(_in));

  data _null_;
    length raw $32767;
    raw = strip(symget('_in'));

    raw = prxchange('s/\.(name|col|column)\b/name/i', -1, raw);
    raw = prxchange('s/\.type\b/type/i', -1, raw);
    raw = prxchange('s/\.length\b/length/i', -1, raw);
    raw = prxchange('s/\.label\b/label/i', -1, raw);
    raw = prxchange('s/\.format\b/format/i', -1, raw);
    raw = prxchange('s/\.informat\b/informat/i', -1, raw);
    raw = prxchange('s/\.varnum\b/varnum/i', -1, raw);
    raw = prxchange('s/\.x\b/name/i', -1, raw);
    raw = prxchange("s/\\.is_char\\b/(upcase(type)='CHAR')/i", -1, raw);
    raw = prxchange("s/\\.is_num\\b/(upcase(type)='NUM')/i", -1, raw);
    if length(raw) > 0 and substr(raw, length(raw), 1) = ';' then raw = substr(raw, 1, length(raw) - 1);

    call symputx('_out', strip(raw), 'L');
  run;

  %_sel_out_assign(out_var=%superq(out_raw), value=%superq(_out));
  %_sel_dbg(msg=_sel_cols_where_rewrite done out=%superq(_out));
%mend;

%macro _sel_collect_by_predicate(ds=, predicate=, out_cols=, empty_msg=select() selector matched no columns.);
  %local _lib _mem _pred _empty;
  %_ds_split(&ds, _lib, _mem);
  %let _pred=%superq(predicate);
  %let _empty=%superq(empty_msg);
  %_sel_require_nonempty(value=%superq(_pred), msg=Internal selector error: predicate cannot be empty.);

  data _null_;
    length _cols $32767;
    set sashelp.vcolumn(
      where=(libname="&_lib" and memname="&_mem")
    ) end=_eof;
    _sel_keep = 0;
    _sel_keep = (%unquote(%superq(_pred)));
    if _sel_keep then _cols = catx(' ', _cols, strip(name));
    if _eof then call symputx("&out_cols", strip(_cols), 'L');
  run;

  %if %length(%superq(&out_cols))=0 %then %_abort(%superq(_empty));
%mend;

%macro _sel_tokenize(expr=, out_n=, out_prefix=_sel_tok);
  %_sel_dbg(msg=_sel_tokenize start out_n=%superq(out_n) out_prefix=%superq(out_prefix) expr=%superq(expr));
  %if not %sysmacexist(_pipr_tokenize) %then %_abort(selectors utils require _pipr_tokenize from util.sas.);
  %_pipr_tokenize(
    expr=%superq(expr),
    out_n=%superq(out_n),
    out_prefix=%superq(out_prefix),
    split_on_comma=1,
    split_on_ws=1
  );
  %_sel_dbg(msg=_sel_tokenize done out_n=%superq(out_n) value=%superq(&out_n));
%mend;

%macro _sel_parse_call_init(out_is=, out_name=, out_arg=);
  %_sel_out_assign(out_var=%superq(out_is), value=0);
  %_sel_out_assign(out_var=%superq(out_name), value=);
  %_sel_out_assign(out_var=%superq(out_arg), value=);
%mend;

%macro _sel_parse_call_extract(token=);
  %global _sel_pce_name _sel_pce_arg _sel_pce_open _sel_pce_len _sel_pce_last _sel_pce_is_call;
  %local _tok _open _len _name _arg _last _is_call;
  %let _tok=%sysfunc(strip(%superq(token)));
  %let _open=%index(%superq(_tok), %str(%());
  %let _len=%length(%superq(_tok));
  %let _name=;
  %let _arg=;
  %let _last=;
  %let _is_call=0;

  %if &_len > 0 %then %let _last=%qsubstr(%superq(_tok), &_len, 1);

  %if &_open > 1 and &_len > &_open and %superq(_last) = %str(%)) %then %do;
    %let _name=%upcase(%qsubstr(%superq(_tok), 1, %eval(&_open - 1)));
    %let _arg=%qsubstr(%superq(_tok), %eval(&_open + 1), %eval(&_len - &_open - 1));
    %let _is_call=1;
  %end;

  %let _sel_pce_name=%superq(_name);
  %let _sel_pce_arg=%superq(_arg);
  %let _sel_pce_open=&_open;
  %let _sel_pce_len=&_len;
  %let _sel_pce_last=%superq(_last);
  %let _sel_pce_is_call=&_is_call;
%mend;

%macro _sel_parse_call(token=, out_is=, out_name=, out_arg=);
  %local _name _arg _open _len _last _is_call;
  %_sel_parse_call_init(out_is=%superq(out_is), out_name=%superq(out_name), out_arg=%superq(out_arg));
  %_sel_parse_call_extract(token=%superq(token));

  %let _name=%superq(_sel_pce_name);
  %let _arg=%superq(_sel_pce_arg);
  %let _open=&_sel_pce_open;
  %let _len=&_sel_pce_len;
  %let _last=%superq(_sel_pce_last);
  %let _is_call=&_sel_pce_is_call;

  %_sel_dbg(msg=_sel_parse_call token=%superq(token) open=&_open len=&_len last=%superq(_last) is_call=&_is_call name=%superq(_name) arg=%superq(_arg));

  %if &_is_call %then %do;
    %if %sysfunc(indexw(STARTS_WITH ENDS_WITH CONTAINS LIKE MATCHES COLS_WHERE, %superq(_name))) > 0 %then %do;
      %_sel_unquote(text=%superq(_arg), out_text=_arg_unq);
      %_sel_out_assign(out_var=%superq(out_is), value=1);
      %_sel_out_assign(out_var=%superq(out_name), value=%superq(_name));
      %_sel_out_assign(out_var=%superq(out_arg), value=%superq(_arg_unq));
    %end;
    %else %do;
      %_sel_out_assign(out_var=%superq(out_is), value=-1);
      %_sel_out_assign(out_var=%superq(out_name), value=%superq(_name));
      %_sel_out_assign(out_var=%superq(out_arg), value=%superq(_arg));
    %end;
  %end;

  %_sel_dbg(msg=_sel_parse_call out is=%superq(&out_is) name=%superq(&out_name) arg=%superq(&out_arg));
%mend;

%macro _sel_list_append_unique(base=, add=, out_list=);
  %local i n tok merged;
  %let merged=%sysfunc(compbl(%superq(base)));
  %let n=%sysfunc(countw(%superq(add), %str( ), q));

  %do i=1 %to &n;
    %let tok=%scan(%superq(add), &i, %str( ), q);
    %if %length(%superq(tok)) %then %do;
      %if %sysfunc(indexw(%upcase(%superq(merged)), %upcase(%superq(tok)), %str( ))) = 0 %then %do;
        %if %length(%superq(merged)) %then %let merged=&merged %superq(tok);
        %else %let merged=%superq(tok);
      %end;
    %end;
  %end;

  %_sel_out_assign(out_var=%superq(out_list), value=%sysfunc(compbl(%superq(merged))));
%mend;

%macro _sel_expand_token(ds=, token=, out_cols=);
  %local _is _name _arg _open;
  %_sel_out_assign(out_var=%superq(out_cols), value=);

  %_sel_parse_call(token=%superq(token), out_is=_is, out_name=_name, out_arg=_arg);
  %if &_is = 1 %then %do;
    %if %superq(_name)=STARTS_WITH %then %do;
      %if not %sysmacexist(_selector_starts_with) %then %_abort(starts_with() selector macro is not loaded.);
      %_selector_starts_with(ds=&ds, prefix=%superq(_arg), out_cols=&out_cols);
    %end;
    %else %if %superq(_name)=ENDS_WITH %then %do;
      %if not %sysmacexist(_selector_ends_with) %then %_abort(ends_with() selector macro is not loaded.);
      %_selector_ends_with(ds=&ds, suffix=%superq(_arg), out_cols=&out_cols);
    %end;
    %else %if %superq(_name)=CONTAINS %then %do;
      %if not %sysmacexist(_selector_contains) %then %_abort(contains() selector macro is not loaded.);
      %_selector_contains(ds=&ds, needle=%superq(_arg), out_cols=&out_cols);
    %end;
    %else %if %superq(_name)=LIKE %then %do;
      %if not %sysmacexist(_selector_like) %then %_abort(like() selector macro is not loaded.);
      %_selector_like(ds=&ds, pattern=%superq(_arg), out_cols=&out_cols);
    %end;
    %else %if %superq(_name)=MATCHES %then %do;
      %if not %sysmacexist(_selector_matches) %then %_abort(matches() selector macro is not loaded.);
      %_selector_matches(ds=&ds, regex=%superq(_arg), out_cols=&out_cols);
    %end;
    %else %if %superq(_name)=COLS_WHERE %then %do;
      %if not %sysmacexist(_selector_cols_where) %then %_abort(cols_where() selector macro is not loaded.);
      %_selector_cols_where(ds=&ds, predicate=%superq(_arg), out_cols=&out_cols);
    %end;
    %return;
  %end;

  %if &_is = -1 %then %_abort(Unsupported selector function in select(): %superq(token));

  %let _open=%index(%superq(token), %str(%());
  %if &_open > 0 %then %_abort(Malformed selector token in select(): %superq(token));

  %_sel_out_assign(out_var=%superq(out_cols), value=%sysfunc(strip(%superq(token))));
%mend;

%macro _sel_expand(ds=, expr=, out_cols=, validate=1);
  %local _n _i _tok _expanded _merged _validate;
  %let _validate=%_pipr_bool(%superq(validate), default=1);
  %let _merged=;

  %_sel_tokenize(expr=%superq(expr), out_n=_n, out_prefix=_sel_tok);
  %if &_n = 0 %then %_abort(select() requires at least one column or selector token.);

  %do _i=1 %to &_n;
    %let _tok=&&_sel_tok&_i;
    %_sel_expand_token(ds=&ds, token=%superq(_tok), out_cols=_expanded);
    %_sel_list_append_unique(base=%superq(_merged), add=%superq(_expanded), out_list=_merged);
  %end;

  %if %length(%superq(_merged))=0 %then %_abort(select() resolved to an empty column list.);
  %if &_validate %then %_assert_cols_exist(&ds, &_merged);

  %_sel_out_assign(out_var=%superq(out_cols), value=%superq(_merged));
%mend;

%macro test_selector_utils;
  %_pipr_require_assert;

  %test_suite(Testing selector utils);
    %test_case(unquote helper handles quoted and unquoted text);
      %_sel_unquote(text=%str('policy_state'), out_text=_stu_uq1);
      %assertEqual(%superq(_stu_uq1), policy_state);

      %_sel_unquote(text=%str("home_state"), out_text=_stu_uq2);
      %assertEqual(%superq(_stu_uq2), home_state);

      %_sel_unquote(text=company_numb, out_text=_stu_uq3);
      %assertEqual(%superq(_stu_uq3), company_numb);

      %_sel_require_nonempty(value=%str(ok), msg=should not abort);
      %assertTrue(1, selector non-empty wrapper accepts populated values);
    %test_summary;

    %test_case(tokenizer splits selector expression);
      %_sel_tokenize(
        expr=%str(starts_with('policy') company_numb ends_with('code') like('%state%')),
        out_n=_stu_n,
        out_prefix=_stu_tok
      );

      %assertEqual(&_stu_n., 4);
      %assertEqual(&_stu_tok1., starts_with('policy'));
      %assertEqual(&_stu_tok2., company_numb);
      %assertEqual(&_stu_tok3., ends_with('code'));
      %assertEqual(&_stu_tok4., like('%state%'));
    %test_summary;

    %test_case(tokenizer handles comma-delimited tokens);
      %_sel_tokenize(
        expr=%str(starts_with('policy'),company_numb,ends_with('code')),
        out_n=_stu_n,
        out_prefix=_stu_tok
      );

      %assertEqual(&_stu_n., 3);
      %assertEqual(&_stu_tok1., starts_with('policy'));
      %assertEqual(&_stu_tok2., company_numb);
      %assertEqual(&_stu_tok3., ends_with('code'));
    %test_summary;

    %test_case(tokenizer supports local out_n names in callers);
      %local _n;
      %_sel_tokenize(
        expr=%str(company_numb starts_with('policy')),
        out_n=_n,
        out_prefix=_stu_tok_local
      );
      %assertEqual(&_n., 2);
      %assertEqual(&_stu_tok_local1., company_numb);
      %assertEqual(&_stu_tok_local2., starts_with('policy'));
    %test_summary;

    %test_case(parse selector call and unquote);
      %_sel_parse_call(token=%str(starts_with('policy')), out_is=_stu_is, out_name=_stu_name, out_arg=_stu_arg);
      %assertEqual(&_stu_is., 1);
      %assertEqual(&_stu_name., STARTS_WITH);
      %assertEqual(&_stu_arg., policy);

      %_sel_parse_call(token=company_numb, out_is=_stu_is, out_name=_stu_name, out_arg=_stu_arg);
      %assertEqual(&_stu_is., 0);

      %_sel_parse_call(token=%str(matches('state$')), out_is=_stu_is, out_name=_stu_name, out_arg=_stu_arg);
      %assertEqual(&_stu_is., 1);
      %assertEqual(&_stu_name., MATCHES);
      %assertEqual(&_stu_arg., state$);

      %_sel_parse_call(
        token=%str(cols_where(lambda(.is_char and prxmatch('/state/i', .name) > 0))),
        out_is=_stu_is,
        out_name=_stu_name,
        out_arg=_stu_arg
      );
      %assertEqual(&_stu_is., 1);
      %assertEqual(&_stu_name., COLS_WHERE);

      %_sel_parse_call(token=%str(unknown_fn('x')), out_is=_stu_is, out_name=_stu_name, out_arg=_stu_arg);
      %assertEqual(&_stu_is., -1);
      %assertEqual(&_stu_name., UNKNOWN_FN);
      %assertEqual(&_stu_arg., 'x');
    %test_summary;

    %test_case(parse helper extraction detects call shape safely);
      %_sel_parse_call_extract(token=%str(starts_with('policy')));
      %assertEqual(&_sel_pce_is_call., 1);
      %assertEqual(&_sel_pce_name., STARTS_WITH);
      %assertEqual(&_sel_pce_arg., 'policy');
    %test_summary;

    %test_case(list append unique preserves order);
      %_sel_list_append_unique(base=%str(a b), add=%str(b c a d), out_list=_stu_list);
      %assertEqual(&_stu_list., a b c d);
    %test_summary;

    %test_case(regex and cols_where predicate helpers);
      %global _pipr_sel_debug;
      %let _pipr_sel_debug=1;
      %_sel_regex_to_prx(regex=state$, out_prx=_stu_prx);
      %assertEqual(%superq(_stu_prx), /state$/i);

      %_sel_regex_to_prx(regex=%str(/^state$/), out_prx=_stu_prx2);
      %assertEqual(%superq(_stu_prx2), %str(/^state$/));

      %_sel_cols_where_predicate(
        predicate=%str(lambda(.is_char and prxmatch('/state/i', .name) > 0)),
        out_predicate=_stu_pred
      );
      %assertEqual(
        %superq(_stu_pred),
        %str((upcase(type)='CHAR') and prxmatch('/state/i', name) > 0)
      );

      %_sel_cols_where_predicate(
        predicate=%str(~.is_num;),
        out_predicate=_stu_pred2
      );
      %assertEqual(%superq(_stu_pred2), %str((upcase(type)='NUM')));

      %_sel_regex_to_prx_core(regex=%str(^abc$), default_flags=i, out_prx=_stu_prx_core);
      %assertEqual(%superq(_stu_prx_core), %str(/^abc$/i));

      %_sel_cols_where_rewrite(
        raw=%str(.is_char and .name='HOME_STATE';),
        out_raw=_stu_pred_core
      );
      %assertEqual(%superq(_stu_pred_core), %str((upcase(type)='CHAR') and name='HOME_STATE'));
      %let _pipr_sel_debug=0;
    %test_summary;

    %test_case(shared metadata query helper resolves ordered list);
      data work._stu;
        length home_state $2 policy_state $2 state_code $8 company_numb 8;
        home_state='CA';
        policy_state='NV';
        state_code='S1';
        company_numb=1;
        output;
      run;

      %_sel_query_cols(
        ds=work._stu,
        where=%str(index(upcase(name), 'STATE') > 0),
        out_cols=_stu_qcols,
        empty_msg=No STATE columns.
      );
      %assertEqual(%upcase(&_stu_qcols.), HOME_STATE POLICY_STATE STATE_CODE);
    %test_summary;

    %test_case(predicate collector evaluates row-wise metadata predicate);
      %_sel_collect_by_predicate(
        ds=work._stu,
        predicate=%str(upcase(type)='CHAR' and index(upcase(name), 'STATE') > 0),
        out_cols=_stu_pred_cols,
        empty_msg=No char STATE columns.
      );
      %assertEqual(%upcase(&_stu_pred_cols.), HOME_STATE POLICY_STATE STATE_CODE);
    %test_summary;

    %test_case(expand helper honors validate=NO);
      %_sel_expand(
        ds=work._stu,
        expr=%str(home_state no_such_col),
        out_cols=_stu_expand_nv,
        validate=0
      );
      %assertEqual(%upcase(&_stu_expand_nv.), HOME_STATE NO_SUCH_COL);
    %test_summary;

    %test_case(expand helper deduplicates columns while preserving first-seen order);
      %_sel_expand(
        ds=work._stu,
        expr=%str(company_numb starts_with('policy') company_numb contains('state')),
        out_cols=_stu_expand_dedupe,
        validate=1
      );
      %assertEqual(%upcase(&_stu_expand_dedupe.), COMPANY_NUMB POLICY_STATE HOME_STATE STATE_CODE);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _stu; quit;
%mend test_selector_utils;

%_pipr_autorun_tests(test_selector_utils);
