/* Shared selector utilities for select() expansion. */

%macro _sel_unquote(text=, out_text=);
  %local _sel_uq_in _sel_uq_out;
  %let _sel_uq_in=%superq(text);

  data _null_;
    length raw $32767 q $1;
    raw = strip(symget('_sel_uq_in'));
    if length(raw) >= 2 then do;
      q = substr(raw, 1, 1);
      if (q = "'" or q = '"') and substr(raw, length(raw), 1) = q then
        raw = substr(raw, 2, length(raw) - 2);
    end;
    call symputx('_sel_uq_out', raw, 'L');
  run;

  %let &out_text=%superq(_sel_uq_out);
%mend;

%macro _sel_require_nonempty(value=, msg=Selector argument must be non-empty.);
  %if %length(%superq(value))=0 %then %_abort(%superq(msg));
%mend;

%macro _sel_query_cols(ds=, where=, out_cols=, empty_msg=select() selector matched no columns.);
  %local _lib _mem _where _empty;
  %_ds_split(&ds, _lib, _mem);
  %let _where=%superq(where);
  %let _empty=%superq(empty_msg);
  %_sel_require_nonempty(value=%superq(_where), msg=Internal selector error: where= clause cannot be empty.);

  proc sql noprint;
    select name into :&out_cols separated by ' '
    from sashelp.vcolumn
    where libname="&_lib"
      and memname="&_mem"
      and %superq(_where)
    order by varnum;
  quit;

  %if %length(%superq(&out_cols))=0 %then %_abort(%superq(_empty));
%mend;

%macro _sel_regex_to_prx(regex=, out_prx=, default_flags=i);
  %local _in _flags _out;
  %let _in=%superq(regex);
  %let _flags=%superq(default_flags);

  data _null_;
    length raw body flags out $32767;
    raw = strip(symget('_in'));
    flags = strip(symget('_flags'));
    out = '';

    if length(raw) then do;
      if prxmatch('/^\/.+\/[A-Za-z]*$/', raw) then out = raw;
      else do;
        body = tranwrd(raw, '/', '\/');
        out = cats('/', body, '/', flags);
      end;
    end;

    call symputx('_out', out, 'L');
  run;

  %let &out_prx=%superq(_out);
%mend;

%macro _sel_cols_where_predicate(predicate=, out_predicate=);
  %local _raw _out;
  %if not %sysmacexist(_sel_lambda_normalize) %then %_abort(cols_where() requires selector lambda helpers to be loaded.);
  %_sel_lambda_normalize(expr=%superq(predicate), out_expr=_raw);
  %_sel_require_nonempty(value=%superq(_raw), msg=cols_where() requires a non-empty predicate expression.);

  data _null_;
    length raw $32767;
    raw = strip(symget('_raw'));

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

  %let &out_predicate=%superq(_out);
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
    _sel_keep = (%superq(_pred));
    if _sel_keep then _cols = catx(' ', _cols, strip(name));
    if _eof then call symputx("&out_cols", strip(_cols), 'L');
  run;

  %if %length(%superq(&out_cols))=0 %then %_abort(%superq(_empty));
%mend;

%macro _sel_tokenize(expr=, out_n=, out_prefix=_sel_tok);
  data _null_;
    length expr tok $32767 ch quote $1;
    expr = symget('expr');
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

      if quote = '' and depth = 0 and (ch = ',' or ch in (' ', '09'x, '0A'x, '0D'x)) then do;
        if length(strip(tok)) then do;
          n + 1;
          /* Token names are dynamic; publish globally so parent callers can always read them. */
          call symputx(cats(symget('out_prefix'), n), strip(tok), 'G');
          tok = '';
        end;
      end;
      else tok = cats(tok, ch);
    end;

    if length(strip(tok)) then do;
      n + 1;
      call symputx(cats(symget('out_prefix'), n), strip(tok), 'G');
    end;

    call symputx(symget('out_n'), n, 'F');
  run;
%mend;

%macro _sel_parse_call(token=, out_is=, out_name=, out_arg=);
  %local _tok _open _len _name _arg;
  %let _tok=%sysfunc(strip(%superq(token)));

  %let &out_is=0;
  %let &out_name=;
  %let &out_arg=;

  %let _open=%index(%superq(_tok), %str(%());
  %let _len=%length(%superq(_tok));

  %if &_open > 1 and &_len > &_open %then %do;
    %if %qsubstr(%superq(_tok), &_len, 1) = %str()) %then %do;
      %let _name=%upcase(%qsubstr(%superq(_tok), 1, %eval(&_open - 1)));
      %let _arg=%qsubstr(%superq(_tok), %eval(&_open + 1), %eval(&_len - &_open - 1));

      %if %sysfunc(indexw(STARTS_WITH ENDS_WITH CONTAINS LIKE MATCHES COLS_WHERE, %superq(_name))) > 0 %then %do;
        %_sel_unquote(text=%superq(_arg), out_text=_arg_unq);
        %let &out_is=1;
        %let &out_name=%superq(_name);
        %let &out_arg=%superq(_arg_unq);
      %end;
      %else %do;
        %let &out_is=-1;
        %let &out_name=%superq(_name);
        %let &out_arg=%superq(_arg);
      %end;
    %end;
  %end;
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

  %let &out_list=%sysfunc(compbl(%superq(merged)));
%mend;

%macro _sel_expand_token(ds=, token=, out_cols=);
  %local _is _name _arg _open;
  %let &out_cols=;

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

  %let &out_cols=%sysfunc(strip(%superq(token)));
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

  %let &out_cols=%superq(_merged);
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

    %test_case(list append unique preserves order);
      %_sel_list_append_unique(base=%str(a b), add=%str(b c a d), out_list=_stu_list);
      %assertEqual(&_stu_list., a b c d);
    %test_summary;

    %test_case(regex and cols_where predicate helpers);
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
