/* Predicate and function helpers for row-wise expressions in filter()/data steps. */

%if not %sysmacexist(_abort) %then %do;
  %macro _abort(msg);
    %put ERROR: &msg;
    %abort cancel;
  %mend;
%end;

%if not %sysmacexist(_pipr_require_assert) %then %do;
  %macro _pipr_require_assert;
    %if not %sysmacexist(assertTrue) %then %sbmod(assert);
  %mend;
%end;

%if not %sysmacexist(_pipr_autorun_tests) %then %do;
  %macro _pipr_autorun_tests(test_macro);
  %mend;
%end;

%macro _pred_require_nonempty(value=, msg=Predicate argument must be non-empty.);
  %if %length(%superq(value))=0 %then %_abort(%superq(msg));
%mend;

%macro _pred_bool(value, default=0);
  %if %sysmacexist(_pipr_bool) %then %_pipr_bool(%superq(value), default=&default);
  %else %do;
    %local _raw _up;
    %let _raw=%superq(value);
    %if %length(%superq(_raw))=0 %then &default;
    %else %do;
      %let _up=%upcase(%superq(_raw));
      %if %sysfunc(indexw(1 Y YES TRUE T ON, &_up)) > 0 %then 1;
      %else %if %sysfunc(indexw(0 N NO FALSE F OFF, &_up)) > 0 %then 0;
      %else &default;
    %end;
  %end;
%mend;

%macro _pred_split_parmbuff(buf=, out_n=, out_prefix=_pred_seg);
  %if not %sysmacexist(_pipr_split_parmbuff_segments) %then %_abort(predicates.sas requires pipr util helpers to be loaded.);
  %_pipr_split_parmbuff_segments(buf=%superq(buf), out_n=&out_n, out_prefix=&out_prefix);
%mend;

%macro _pred_strip_quotes(text=, out_text=);
  %local _in _out;
  %let _in=%superq(text);
  data _null_;
    length raw $32767 q $1;
    raw = strip(symget('_in'));
    if length(raw) >= 2 then do;
      q = substr(raw, 1, 1);
      if (q = "'" or q = '"') and substr(raw, length(raw), 1) = q then
        raw = substr(raw, 2, length(raw) - 2);
    end;
    call symputx('_out', raw, 'L');
  run;
  %let &out_text=%superq(_out);
%mend;

%macro _pred_trim_expr(text=, out_text=);
  %local _in _out;
  %let _in=%superq(text);
  data _null_;
    length raw $32767;
    raw = strip(symget('_in'));
    if length(raw) > 0 and substr(raw, length(raw), 1) = ';' then raw = substr(raw, 1, length(raw) - 1);
    call symputx('_out', strip(raw), 'L');
  run;
  %let &out_text=%superq(_out);
%mend;

%macro _pred_escape_regex(text=, out_text=);
  %local _in _out;
  %let _in=%superq(text);
  data _null_;
    length raw esc $32767 ch $1;
    raw = symget('_in');
    esc = '';
    do i = 1 to length(raw);
      ch = substr(raw, i, 1);
      if indexc('\.^$|?*+()[]{}', ch) > 0 then esc = cats(esc, '\', ch);
      else esc = cats(esc, ch);
    end;
    call symputx('_out', esc, 'L');
  run;
  %let &out_text=%superq(_out);
%mend;

%macro _pred_regex_to_prx(regex=, ignore_case=1, out_prx=);
  %local _raw _ic _out;
  %let _raw=%superq(regex);
  %_pred_strip_quotes(text=%superq(_raw), out_text=_raw);
  %let _ic=%_pred_bool(%superq(ignore_case), default=1);

  data _null_;
    length raw body flags out $32767;
    raw = strip(symget('_raw'));
    out = '';

    if length(raw) then do;
      if prxmatch('/^\/.+\/[A-Za-z]*$/', raw) then do;
        slash = 0;
        do i = length(raw) to 2 by -1;
          if substr(raw, i, 1) = '/' then do;
            slash = i;
            leave;
          end;
        end;

        if slash > 1 then do;
          body = substr(raw, 2, slash - 2);
          flags = substr(raw, slash + 1);
          if symget('_ic') = '1' and index(lowcase(flags), 'i') = 0 then flags = cats(flags, 'i');
          out = cats('/', body, '/', flags);
        end;
      end;
      else do;
        body = tranwrd(raw, '/', '\/');
        flags = ifc(symget('_ic') = '1', 'i', '');
        out = cats('/', body, '/', flags);
      end;
    end;

    call symputx('_out', out, 'L');
  run;

  %let &out_prx=%superq(_out);
%mend;

%macro _pred_sql_like_to_prx(pattern=, ignore_case=1, out_prx=);
  %local _raw _ic _out;
  %let _raw=%superq(pattern);
  %_pred_strip_quotes(text=%superq(_raw), out_text=_raw);
  %let _ic=%_pred_bool(%superq(ignore_case), default=1);

  data _null_;
    length raw body out flags ch $32767;
    raw = symget('_raw');
    body = '';
    do i = 1 to length(raw);
      ch = substr(raw, i, 1);
      if ch = '%' then body = cats(body, '.*');
      else if ch = '_' then body = cats(body, '.');
      else do;
        if indexc('\.^$|?*+()[]{}', ch) > 0 then body = cats(body, '\', ch);
        else body = cats(body, ch);
      end;
    end;

    flags = ifc(symget('_ic') = '1', 'i', '');
    out = cats('/^', body, '$/', flags);
    call symputx('_out', out, 'L');
  run;

  %let &out_prx=%superq(_out);
%mend;

%macro _pred_registry_reset;
  %global _pipr_fn_count _pipr_functions _pipr_function_kinds _pipr_function_macros;
  %let _pipr_fn_count=0;
  %let _pipr_functions=;
  %let _pipr_function_kinds=;
  %let _pipr_function_macros=;
%mend;

%macro _pred_registry_add(name=, kind=GENERIC, macro_name=);
  %local _u _m _kind _n _i _found _name_var _kind_var _macro_var _fn;
  %local _new_functions _new_kinds _new_macros _k _mac;
  %global _pipr_fn_count _pipr_functions _pipr_function_kinds _pipr_function_macros;

  %let _u=%upcase(%sysfunc(strip(%superq(name))));
  %let _m=%sysfunc(strip(%superq(macro_name)));
  %let _kind=%upcase(%sysfunc(strip(%superq(kind))));
  %if %length(%superq(_u))=0 %then %return;
  %if %length(%superq(_m))=0 %then %let _m=%superq(name);

  %if not %sysfunc(symexist(_pipr_fn_count)) %then %let _pipr_fn_count=0;
  %let _n=%superq(_pipr_fn_count);
  %if %length(%superq(_n))=0 %then %let _n=0;

  %let _found=0;
  %do _i=1 %to &_n;
    %let _name_var=_pipr_fn_name&_i;
    %if %sysfunc(symexist(&_name_var)) %then %let _fn=%upcase(%superq(&_name_var));
    %else %let _fn=;

    %if %superq(_fn)=%superq(_u) %then %do;
      %let _found=1;
      %let _kind_var=_pipr_fn_kind&_i;
      %let _macro_var=_pipr_fn_macro&_i;
      %global &_kind_var &_macro_var;
      %let &_kind_var=%superq(_kind);
      %let &_macro_var=%superq(_m);
      %goto _pred_registry_add_rebuild;
    %end;
  %end;

  %let _n=%eval(&_n + 1);
  %let _pipr_fn_count=&_n;
  %let _name_var=_pipr_fn_name&_n;
  %let _kind_var=_pipr_fn_kind&_n;
  %let _macro_var=_pipr_fn_macro&_n;
  %global &_name_var &_kind_var &_macro_var;
  %let &_name_var=%superq(_u);
  %let &_kind_var=%superq(_kind);
  %let &_macro_var=%superq(_m);

  %_pred_registry_add_rebuild:
  %let _new_functions=;
  %let _new_kinds=;
  %let _new_macros=;
  %do _i=1 %to &_pipr_fn_count;
    %let _name_var=_pipr_fn_name&_i;
    %let _kind_var=_pipr_fn_kind&_i;
    %let _macro_var=_pipr_fn_macro&_i;
    %let _fn=%superq(&_name_var);
    %let _k=%superq(&_kind_var);
    %let _mac=%superq(&_macro_var);

    %if %length(%superq(_new_functions)) %then %let _new_functions=%superq(_new_functions) %superq(_fn);
    %else %let _new_functions=%superq(_fn);

    %if %length(%superq(_new_kinds)) %then %let _new_kinds=%superq(_new_kinds) %superq(_k);
    %else %let _new_kinds=%superq(_k);

    %if %length(%superq(_new_macros)) %then %let _new_macros=%superq(_new_macros) %superq(_mac);
    %else %let _new_macros=%superq(_mac);
  %end;

  %let _pipr_functions=%superq(_new_functions);
  %let _pipr_function_kinds=%superq(_new_kinds);
  %let _pipr_function_macros=%superq(_new_macros);
%mend;

%macro _pred_macro_for(name=, out_macro=);
  %local _u _m _n _i _fn _name_var _macro_var;
  %let _u=%upcase(%superq(name));
  %let _m=;

  %if %sysfunc(symexist(_pipr_fn_count)) %then %let _n=%superq(_pipr_fn_count);
  %else %let _n=0;
  %if %length(%superq(_n))=0 %then %let _n=0;

  %do _i=1 %to &_n;
    %let _name_var=_pipr_fn_name&_i;
    %let _macro_var=_pipr_fn_macro&_i;
    %if %sysfunc(symexist(&_name_var)) %then %let _fn=%superq(&_name_var);
    %else %let _fn=;
    %if %upcase(%superq(_fn))=%superq(_u) %then %do;
      %if %sysfunc(symexist(&_macro_var)) %then %let _m=%superq(&_macro_var);
      %else %let _m=;
      %goto _pred_macro_for_done;
    %end;
  %end;

  %_pred_macro_for_done:
  %if %length(%superq(_m))=0 %then %let _m=%superq(name);
  %let &out_macro=%superq(_m);
%mend;

%macro _pred_eval_registered_call(name=, args=, out_expr=);
  %local _macro _expr;
  %let _expr=;
  %_pred_macro_for(name=%superq(name), out_macro=_macro);
  %if %length(%superq(_macro))=0 %then %_abort(Unknown registered function/predicate: %superq(name));
  %if not %sysmacexist(&_macro) %then
    %_abort(Registered function/predicate %superq(name) maps to missing macro %superq(_macro).);

  %if %length(%superq(args)) %then %let _expr=%unquote(%nrstr(%)&_macro(%superq(args)));
  %else %let _expr=%unquote(%nrstr(%)&_macro());

  %_pred_trim_expr(text=%superq(_expr), out_text=_expr);
  %let &out_expr=%superq(_expr);
%mend;

%macro _pred_find_call(expr=, out_found=, out_prefix=, out_name=, out_args=, out_suffix=);
  %local _expr _registry;
  %let _expr=%superq(expr);
  %if %sysfunc(symexist(_pipr_functions)) %then %let _registry=%upcase(%superq(_pipr_functions));
  %else %let _registry=;

  %let &out_found=0;
  %let &out_prefix=%superq(_expr);
  %let &out_name=;
  %let &out_args=;
  %let &out_suffix=;

  %if %length(%superq(_registry))=0 %then %return;

  data _null_;
    length expr registry prefix name args suffix token up $32767;
    length ch c2 prev quote inner_quote $1;

    expr = symget('_expr');
    registry = symget('_registry');
    found = 0;
    prefix = '';
    name = '';
    args = '';
    suffix = '';
    quote = '';

    i = 1;
    do while(i <= length(expr));
      ch = substr(expr, i, 1);

      if quote = '' then do;
        if ch = "'" or ch = '"' then do;
          quote = ch;
          i + 1;
          continue;
        end;

        if prxmatch('/[A-Za-z_]/', ch) then do;
          start = i;
          j = i + 1;
          do while(j <= length(expr));
            c2 = substr(expr, j, 1);
            if prxmatch('/[A-Za-z0-9_]/', c2) then j + 1;
            else leave;
          end;

          token = substr(expr, start, j - start);
          up = upcase(strip(token));
          prev = ' ';
          if start > 1 then prev = substr(expr, start - 1, 1);

          k = j;
          do while(k <= length(expr) and substr(expr, k, 1) in (' ', '09'x, '0A'x, '0D'x));
            k + 1;
          end;

          if indexw(registry, strip(up), ' ') > 0
             and (start = 1 or not prxmatch('/[A-Za-z0-9_\.%&]/', prev))
             and k <= length(expr)
             and substr(expr, k, 1) = '(' then do;
            depth = 0;
            inner_quote = '';
            close = 0;
            p = k;
            do while(p <= length(expr));
              c2 = substr(expr, p, 1);

              if inner_quote = '' then do;
                if c2 = "'" or c2 = '"' then inner_quote = c2;
                else if c2 = '(' then depth + 1;
                else if c2 = ')' then do;
                  depth + (-1);
                  if depth = 0 then do;
                    close = p;
                    leave;
                  end;
                end;
              end;
              else if c2 = inner_quote then inner_quote = '';

              p + 1;
            end;

            if close > k then do;
              found = 1;
              if start > 1 then prefix = substr(expr, 1, start - 1);
              else prefix = '';
              name = token;
              args = substr(expr, k + 1, close - k - 1);
              if close < length(expr) then suffix = substr(expr, close + 1);
              else suffix = '';
              leave;
            end;
          end;

          i = j;
          continue;
        end;
      end;
      else if ch = quote then quote = '';

      i + 1;
    end;

    call symputx("&out_found", found, 'L');
    call symputx("&out_prefix", prefix, 'L');
    call symputx("&out_name", strip(name), 'L');
    call symputx("&out_args", args, 'L');
    call symputx("&out_suffix", suffix, 'L');
  run;
%mend;

%macro _pred_expand_expr(expr=, out_expr=, max_iter=200);
  %local _work _iter _found _prefix _name _args _suffix _expanded;
  %let _work=%superq(expr);
  %if %length(%superq(_work))=0 %then %do;
    %let &out_expr=;
    %return;
  %end;

  %do _iter=1 %to &max_iter;
    %_pred_find_call(
      expr=%superq(_work),
      out_found=_found,
      out_prefix=_prefix,
      out_name=_name,
      out_args=_args,
      out_suffix=_suffix
    );

    %if %superq(_found)=0 %then %goto _pred_expand_done;

    %_pred_eval_registered_call(
      name=%superq(_name),
      args=%superq(_args),
      out_expr=_expanded
    );

    %let _work=%superq(_prefix)%superq(_expanded)%superq(_suffix);
  %end;

  %_abort(Predicate expansion exceeded max_iter=&max_iter while expanding registered predicates.);

  %_pred_expand_done:
  %let &out_expr=%superq(_work);
%mend;

%macro list_functions(kind=, out_list=);
  %local _kind _n _i _fn _k _out _name_var _kind_var;
  %let _kind=%upcase(%superq(kind));
  %let _out=;
  %if %sysfunc(symexist(_pipr_fn_count)) %then %let _n=%superq(_pipr_fn_count);
  %else %let _n=0;
  %if %length(%superq(_n))=0 %then %let _n=0;

  %do _i=1 %to &_n;
    %let _name_var=_pipr_fn_name&_i;
    %let _kind_var=_pipr_fn_kind&_i;
    %if %sysfunc(symexist(&_name_var)) %then %let _fn=%superq(&_name_var);
    %else %let _fn=;
    %if %sysfunc(symexist(&_kind_var)) %then %let _k=%superq(&_kind_var);
    %else %let _k=;
    %if %length(%superq(_kind))=0 or %superq(_kind)=%superq(_k) %then %do;
      %if %length(%superq(_out)) %then %let _out=&_out &_fn;
      %else %let _out=&_fn;
    %end;
  %end;

  %if %length(%superq(out_list)) %then %let &out_list=%superq(_out);
  %else %put NOTE: Registered functions: %superq(_out);
%mend;

%macro _pred_resolve_gen_args(
  expr_in=,
  args_in=,
  name_in=,
  overwrite_in=0,
  kind_in=GENERIC,
  out_expr=,
  out_args=,
  out_name=,
  out_overwrite=,
  out_kind=
);
  %local _buf _n _i _seg _head _eq _val _pos;

  %let &out_expr=%superq(expr_in);
  %let &out_args=%superq(args_in);
  %let &out_name=%superq(name_in);
  %let &out_overwrite=%superq(overwrite_in);
  %let &out_kind=%superq(kind_in);

  %let _buf=%superq(syspbuff);
  %if %length(%superq(_buf)) > 2 %then %do;
    %_pred_split_parmbuff(buf=%superq(_buf), out_n=_n, out_prefix=_pg_seg);
    %let _pos=0;

    %do _i=1 %to &_n;
      %let _seg=%sysfunc(strip(%superq(_pg_seg&_i)));
      %if %length(%superq(_seg))=0 %then %goto _next_seg;

      %let _head=%upcase(%sysfunc(strip(%scan(%superq(_seg), 1, =))));
      %if %sysfunc(indexw(EXPR EXPRESSION BODY ARGS NAME OVERWRITE KIND, &_head)) > 0 %then %do;
        %let _eq=%index(%superq(_seg), %str(=));
        %if &_eq > 0 %then %let _val=%sysfunc(strip(%substr(%superq(_seg), %eval(&_eq+1))));
        %else %let _val=;

        %if &_head=EXPR or &_head=EXPRESSION or &_head=BODY %then %let &out_expr=%superq(_val);
        %else %if &_head=ARGS %then %let &out_args=%superq(_val);
        %else %if &_head=NAME %then %let &out_name=%superq(_val);
        %else %if &_head=OVERWRITE %then %let &out_overwrite=%superq(_val);
        %else %if &_head=KIND %then %let &out_kind=%superq(_val);
      %end;
      %else %do;
        %let _pos=%eval(&_pos + 1);
        %if &_pos = 1 %then %let &out_expr=%superq(_seg);
        %else %if &_pos = 2 %then %let &out_args=%superq(_seg);
        %else %if &_pos = 3 %then %let &out_name=%superq(_seg);
        %else %if &_pos = 4 %then %let &out_overwrite=%superq(_seg);
        %else %if &_pos = 5 %then %let &out_kind=%superq(_seg);
      %end;
      %_next_seg:
    %end;
  %end;
%mend;

%macro _pred_compile_macro(name=, args=, body=, overwrite=0, kind=GENERIC);
  %local _name _args _body _overwrite _fileref;
  %let _name=%sysfunc(strip(%superq(name)));
  %let _args=%superq(args);
  %let _body=%superq(body);
  %let _overwrite=%_pred_bool(%superq(overwrite), default=0);

  %_pred_require_nonempty(value=%superq(_name), msg=gen_function() requires name=.);
  %_pred_require_nonempty(value=%superq(_body), msg=gen_function() requires expression/body text.);
  %if %sysfunc(nvalid(%superq(_name), V7))=0 %then %_abort(gen_function() requires a valid SAS macro name. Got: %superq(_name));

  %if %sysmacexist(&_name) and (&_overwrite = 0) %then
    %_abort(gen_function() will not overwrite existing macro &_name. Use overwrite=1 if intended.);

  %let _fileref=_predsrc;
  filename &_fileref temp;
  data _null_;
    file &_fileref lrecl=32767;
    length name args body $32767;
    name = symget('_name');
    args = symget('_args');
    body = symget('_body');
    put '%macro ' name '(' args ');';
    put body;
    put '%mend ' name ';';
  run;

  %include &_fileref;
  filename &_fileref clear;

  %if not %sysmacexist(&_name) %then %_abort(gen_function() failed to compile macro &_name..);
  %_pred_registry_add(name=&_name, kind=&kind);
%mend;

%macro gen_function(expr=, args=, name=, overwrite=0, kind=GENERIC) / parmbuff;
  %local _expr _args _name _overwrite _kind;
  %_pred_resolve_gen_args(
    expr_in=%superq(expr),
    args_in=%superq(args),
    name_in=%superq(name),
    overwrite_in=%superq(overwrite),
    kind_in=%superq(kind),
    out_expr=_expr,
    out_args=_args,
    out_name=_name,
    out_overwrite=_overwrite,
    out_kind=_kind
  );
  %_pred_compile_macro(
    name=%superq(_name),
    args=%superq(_args),
    body=%superq(_expr),
    overwrite=%superq(_overwrite),
    kind=%superq(_kind)
  );
%mend;

%macro gen_predicate(expr=, args=x, name=, overwrite=0) / parmbuff;
  %local _expr _args _name _overwrite _kind;
  %_pred_resolve_gen_args(
    expr_in=%superq(expr),
    args_in=%superq(args),
    name_in=%superq(name),
    overwrite_in=%superq(overwrite),
    kind_in=PREDICATE,
    out_expr=_expr,
    out_args=_args,
    out_name=_name,
    out_overwrite=_overwrite,
    out_kind=_kind
  );
  %_pred_compile_macro(
    name=%superq(_name),
    args=%superq(_args),
    body=%superq(_expr),
    overwrite=%superq(_overwrite),
    kind=%superq(_kind)
  );
%mend;

%macro predicate(expr=, args=x, name=, overwrite=0) / parmbuff;
  %unquote(%nrstr(%gen_predicate)&syspbuff);
%mend;

%macro _pred_lambda_normalize(expr=, out_expr=);
  %local _in _out;
  %let _in=%superq(expr);
  data _null_;
    length raw $32767;
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

%macro _pred_bind_lambda(lambda=, col=, out_expr=);
  %local _lam _out;
  %_pred_lambda_normalize(expr=%superq(lambda), out_expr=_lam);
  %_pred_require_nonempty(value=%superq(_lam), msg=Lambda predicate cannot be empty.);
  data _null_;
    length raw col out rx $32767;
    raw = symget('_lam');
    col = strip(symget('col'));
    rx = cats('s/\\.(x|col|value)\\b/', col, '/i');
    out = prxchange(rx, -1, raw);
    call symputx('_out', strip(out), 'L');
  run;
  %let &out_expr=%superq(_out);
%mend;

%macro _pred_parse_pred_spec(spec=, out_kind=, out_name=, out_args=, out_lambda=);
  %local _raw _kind _name _args _lambda;
  %let _raw=%sysfunc(strip(%superq(spec)));

  data _null_;
    length raw kind name args lambda $32767;
    raw = strip(symget('_raw'));
    kind = '';
    name = '';
    args = '';
    lambda = '';

    if length(raw) > 0 then do;
      if substr(raw, 1, 1) = '~' or prxmatch('/^lambda\s*\(.*\)$/i', raw) then do;
        kind = 'LAMBDA';
        lambda = raw;
      end;
      else if prxmatch('/^[A-Za-z_][A-Za-z0-9_]*\s*\(.*\)$/', raw) then do;
        kind = 'CALL';
        openp = index(raw, '(');
        name = strip(substr(raw, 1, openp - 1));
        args = substr(raw, openp + 1, length(raw) - openp - 1);
      end;
      else do;
        kind = 'NAME';
        name = strip(raw);
      end;
    end;

    call symputx('_kind', kind, 'L');
    call symputx('_name', name, 'L');
    call symputx('_args', args, 'L');
    call symputx('_lambda', lambda, 'L');
  run;

  %let &out_kind=%superq(_kind);
  %let &out_name=%superq(_name);
  %let &out_args=%superq(_args);
  %let &out_lambda=%superq(_lambda);
%mend;

%macro _pred_eval_for_col(col=, pred=, args=, out_expr=);
  %local _kind _name _name_macro _spec_args _lam _all_args _expr;
  %_pred_parse_pred_spec(
    spec=%superq(pred),
    out_kind=_kind,
    out_name=_name,
    out_args=_spec_args,
    out_lambda=_lam
  );

  %if %superq(_kind)=LAMBDA %then %do;
    %_pred_bind_lambda(lambda=%superq(_lam), col=%superq(col), out_expr=_expr);
  %end;
  %else %do;
    %if %length(%superq(_name))=0 %then %_abort(if_any/if_all predicate is empty.);
    %if %sysfunc(nvalid(%superq(_name), V7))=0 %then %_abort(if_any/if_all requires predicate macro names to be valid identifiers. Got: %superq(_name));
    %_pred_macro_for(name=%superq(_name), out_macro=_name_macro);
    %if not %sysmacexist(&_name_macro) %then
      %_abort(if_any/if_all predicate macro is not loaded: %superq(_name));

    %let _all_args=%superq(_spec_args);
    %if %length(%superq(args)) %then %do;
      %if %length(%superq(_all_args)) %then %let _all_args=%superq(_all_args), %superq(args);
      %else %let _all_args=%superq(args);
    %end;

    %if %length(%superq(_all_args)) %then %let _expr=%unquote(%nrstr(%)&_name_macro(&col, %superq(_all_args)));
    %else %let _expr=%unquote(%nrstr(%)&_name_macro(&col));
  %end;

  %_pred_trim_expr(text=%superq(_expr), out_text=_expr);
  %let &out_expr=%superq(_expr);
%mend;

%macro _pred_parse_if_args(cols_in=, pred_in=, args_in=, out_cols=, out_pred=, out_args=);
  %local _buf _n _i _seg _head _eq _val _pos;
  %let &out_cols=%superq(cols_in);
  %let &out_pred=%superq(pred_in);
  %let &out_args=%superq(args_in);

  %let _buf=%superq(syspbuff);
  %if %length(%superq(_buf)) > 2 %then %do;
    %_pred_split_parmbuff(buf=%superq(_buf), out_n=_n, out_prefix=_pf_seg);
    %let _pos=0;

    %do _i=1 %to &_n;
      %let _seg=%sysfunc(strip(%superq(_pf_seg&_i)));
      %if %length(%superq(_seg))=0 %then %goto _next_if_seg;

      %let _head=%upcase(%sysfunc(strip(%scan(%superq(_seg), 1, =))));
      %if %sysfunc(indexw(COLS PRED PREDICATE ARGS, &_head)) > 0 %then %do;
        %let _eq=%index(%superq(_seg), %str(=));
        %if &_eq > 0 %then %let _val=%sysfunc(strip(%substr(%superq(_seg), %eval(&_eq+1))));
        %else %let _val=;

        %if &_head=COLS %then %let &out_cols=%superq(_val);
        %else %if &_head=PRED or &_head=PREDICATE %then %let &out_pred=%superq(_val);
        %else %if &_head=ARGS %then %let &out_args=%superq(_val);
      %end;
      %else %do;
        %let _pos=%eval(&_pos + 1);
        %if &_pos = 1 %then %let &out_cols=%superq(_seg);
        %else %if &_pos = 2 %then %let &out_pred=%superq(_seg);
        %else %if &_pos = 3 %then %let &out_args=%superq(_seg);
      %end;
      %_next_if_seg:
    %end;
  %end;
%mend;

%macro _pred_reduce(cols=, pred=, args=, joiner=OR, out_expr=);
  %local _cols _pred _args _join _n _i _col _col_expr _acc;
  %let _cols=%sysfunc(compbl(%sysfunc(tranwrd(%superq(cols), %str(,), %str( )))));
  %let _pred=%superq(pred);
  %let _args=%superq(args);
  %let _join=%upcase(%superq(joiner));

  %_pred_require_nonempty(value=%superq(_cols), msg=if_any/if_all requires cols=.);
  %_pred_require_nonempty(value=%superq(_pred), msg=if_any/if_all requires pred=.);

  %let _n=%sysfunc(countw(%superq(_cols), %str( ), q));
  %if &_n = 0 %then %_abort(if_any/if_all requires at least one column in cols=.);

  %let _acc=;
  %do _i=1 %to &_n;
    %let _col=%scan(%superq(_cols), &_i, %str( ), q);
    %_pred_eval_for_col(col=%superq(_col), pred=%superq(_pred), args=%superq(_args), out_expr=_col_expr);
    %if %length(%superq(_acc))=0 %then %let _acc=(%superq(_col_expr));
    %else %if &_join = AND %then %let _acc=%superq(_acc) and (%superq(_col_expr));
    %else %let _acc=%superq(_acc) or (%superq(_col_expr));
  %end;

  %let &out_expr=(%superq(_acc));
%mend;

/* Reset built-in registry state on load for deterministic imports. */
%_pred_registry_reset;

%macro if_any(cols=, pred=, args=) / parmbuff;
  %local _cols_work _pred_work _args_work _expr;
  %_pred_parse_if_args(
    cols_in=%superq(cols),
    pred_in=%superq(pred),
    args_in=%superq(args),
    out_cols=_cols_work,
    out_pred=_pred_work,
    out_args=_args_work
  );
  %_pred_reduce(cols=%superq(_cols_work), pred=%superq(_pred_work), args=%superq(_args_work), joiner=OR, out_expr=_expr);
  %superq(_expr)
%mend;
%_pred_registry_add(name=if_any, kind=PREDICATE);

%macro if_all(cols=, pred=, args=) / parmbuff;
  %local _cols_work _pred_work _args_work _expr;
  %_pred_parse_if_args(
    cols_in=%superq(cols),
    pred_in=%superq(pred),
    args_in=%superq(args),
    out_cols=_cols_work,
    out_pred=_pred_work,
    out_args=_args_work
  );
  %_pred_reduce(cols=%superq(_cols_work), pred=%superq(_pred_work), args=%superq(_args_work), joiner=AND, out_expr=_expr);
  %superq(_expr)
%mend;
%_pred_registry_add(name=if_all, kind=PREDICATE);

/* Core predicates */
%macro is_missing(x, blank_is_missing=1);
  %local _blank;
  %let _blank=%_pred_bool(%superq(blank_is_missing), default=1);
  %if &_blank %then ((missing(&x)) or (vtype(&x)='C' and lengthn(strip(&x))=0));
  %else (missing(&x));
%mend;
%_pred_registry_add(name=is_missing, kind=PREDICATE);

%macro is_na_like(x, values=, blank_is_missing=1);
  %if %length(%superq(values)) %then ((%is_missing(&x, blank_is_missing=&blank_is_missing)) or (&x in (&values)));
  %else (%is_missing(&x, blank_is_missing=&blank_is_missing));
%mend;
%_pred_registry_add(name=is_na_like, kind=PREDICATE);

%macro is_between(x, lo, hi, inclusive=both);
  %local _inc;
  %let _inc=%upcase(%sysfunc(strip(%superq(inclusive))));
  %if &_inc=LEFT %then ((&x) >= (&lo) and (&x) < (&hi));
  %else %if &_inc=RIGHT %then ((&x) > (&lo) and (&x) <= (&hi));
  %else %if &_inc=NONE %then ((&x) > (&lo) and (&x) < (&hi));
  %else ((&x) >= (&lo) and (&x) <= (&hi));
%mend;
%_pred_registry_add(name=is_between, kind=PREDICATE);

%macro is_outside(x, lo, hi, inclusive=both);
  (not (%is_between(&x, &lo, &hi, inclusive=&inclusive)))
%mend;
%_pred_registry_add(name=is_outside, kind=PREDICATE);

%macro starts_with(x, prefix, ignore_case=1);
  %local _prefix _esc _rx _prx;
  %let _prefix=%superq(prefix);
  %_pred_strip_quotes(text=%superq(_prefix), out_text=_prefix);
  %_pred_escape_regex(text=%superq(_prefix), out_text=_esc);
  %let _rx=^%superq(_esc);
  %_pred_regex_to_prx(regex=%superq(_rx), ignore_case=&ignore_case, out_prx=_prx);
  (prxmatch("%superq(_prx)", strip(&x)) > 0)
%mend;
%_pred_registry_add(name=starts_with, kind=PREDICATE);

%macro ends_with(x, suffix, ignore_case=1);
  %local _suffix _esc _rx _prx;
  %let _suffix=%superq(suffix);
  %_pred_strip_quotes(text=%superq(_suffix), out_text=_suffix);
  %_pred_escape_regex(text=%superq(_suffix), out_text=_esc);
  %let _rx=%superq(_esc)$;
  %_pred_regex_to_prx(regex=%superq(_rx), ignore_case=&ignore_case, out_prx=_prx);
  (prxmatch("%superq(_prx)", strip(&x)) > 0)
%mend;
%_pred_registry_add(name=ends_with, kind=PREDICATE);

%macro contains(x, pattern, ignore_case=1, regex=1);
  %local _regex _ic;
  %let _regex=%_pred_bool(%superq(regex), default=1);
  %let _ic=%_pred_bool(%superq(ignore_case), default=1);
  %if &_regex %then %do;
    %matches(&x, %superq(pattern), ignore_case=&_ic)
  %end;
  %else %do;
    %if &_ic %then (index(upcase(strip(&x)), upcase(strip(&pattern))) > 0);
    %else (index(strip(&x), strip(&pattern)) > 0);
  %end;
%mend;
%_pred_registry_add(name=contains, kind=PREDICATE);

%macro matches(x, regex, ignore_case=1);
  %local _prx;
  %_pred_regex_to_prx(regex=%superq(regex), ignore_case=&ignore_case, out_prx=_prx);
  (prxmatch("%superq(_prx)", strip(&x)) > 0)
%mend;
%_pred_registry_add(name=matches, kind=PREDICATE);

%macro is_like(x, pattern, ignore_case=1);
  %local _prx;
  %_pred_sql_like_to_prx(pattern=%superq(pattern), ignore_case=&ignore_case, out_prx=_prx);
  (prxmatch("%superq(_prx)", strip(&x)) > 0)
%mend;
%_pred_registry_add(name=is_like, kind=PREDICATE);

%macro is_not_missing(x, blank_is_missing=1);
  (not (%is_missing(&x, blank_is_missing=&blank_is_missing)))
%mend;
%_pred_registry_add(name=is_not_missing, kind=PREDICATE);

%gen_predicate(name=is_blank, args=x, expr=%nrstr((vtype(&x)='C' and lengthn(strip(&x))=0)), overwrite=1);
%gen_predicate(name=is_in, args=%nrstr(x, set), expr=%nrstr((&x in (&set))), overwrite=1);
%gen_predicate(name=is_not_in, args=%nrstr(x, set), expr=%nrstr((&x not in (&set))), overwrite=1);
%gen_predicate(name=is_equal, args=%nrstr(x, y), expr=%nrstr(((&x) = (&y))), overwrite=1);
%gen_predicate(name=is_not_equal, args=%nrstr(x, y), expr=%nrstr(((&x) ne (&y))), overwrite=1);

%gen_predicate(name=is_zero, args=%nrstr(x, tol=0), expr=%nrstr((abs(&x) <= (&tol))), overwrite=1);
%gen_predicate(name=is_positive, args=%nrstr(x, tol=0), expr=%nrstr(((&x) > (&tol))), overwrite=1);
%gen_predicate(name=is_negative, args=%nrstr(x, tol=0), expr=%nrstr(((&x) < -(&tol))), overwrite=1);
%gen_predicate(name=is_nonpositive, args=%nrstr(x, tol=0), expr=%nrstr(((&x) <= (&tol))), overwrite=1);
%gen_predicate(name=is_nonnegative, args=%nrstr(x, tol=0), expr=%nrstr(((&x) >= -(&tol))), overwrite=1);
%gen_predicate(name=is_integerish, args=%nrstr(x, tol=1e-12), expr=%nrstr((abs((&x) - round(&x, 1)) <= (&tol))), overwrite=1);
%gen_predicate(name=is_multiple_of, args=%nrstr(x, k, tol=0), expr=%nrstr(((abs(&k) > 0) and (abs(mod(&x, &k)) <= (&tol)))), overwrite=1);
%gen_predicate(name=is_finite, args=x, expr=%nrstr((not missing(&x))), overwrite=1);

%gen_predicate(name=is_alpha, args=x, expr=%nrstr((prxmatch('/^[A-Za-z]+$/', strip(&x)) > 0)), overwrite=1);
%gen_predicate(name=is_alnum, args=x, expr=%nrstr((prxmatch('/^[A-Za-z0-9]+$/', strip(&x)) > 0)), overwrite=1);
%gen_predicate(name=is_digit, args=x, expr=%nrstr((prxmatch('/^[0-9]+$/', strip(&x)) > 0)), overwrite=1);
%gen_predicate(name=is_upper, args=x, expr=%nrstr((prxmatch('/[A-Za-z]/', strip(&x)) > 0 and strip(&x)=upcase(strip(&x)))), overwrite=1);
%gen_predicate(name=is_lower, args=x, expr=%nrstr((prxmatch('/[A-Za-z]/', strip(&x)) > 0 and strip(&x)=lowcase(strip(&x)))), overwrite=1);
%gen_predicate(name=is_numeric_string, args=x, expr=%nrstr((vtype(&x)='C' and not missing(inputn(strip(&x), ?? best32.)))), overwrite=1);
%gen_predicate(name=is_date_string, args=%nrstr(x, informat=anydtdte.), expr=%nrstr((vtype(&x)='C' and not missing(inputn(strip(&x), ?? &informat)))), overwrite=1);
%macro is_in_format(x, regex);
  (%matches(&x, &regex))
%mend;
%_pred_registry_add(name=is_in_format, kind=PREDICATE);

%gen_predicate(name=is_before, args=%nrstr(x, date), expr=%nrstr(((&x) < (&date))), overwrite=1);
%gen_predicate(name=is_after, args=%nrstr(x, date), expr=%nrstr(((&x) > (&date))), overwrite=1);
%gen_predicate(name=is_on_or_before, args=%nrstr(x, date), expr=%nrstr(((&x) <= (&date))), overwrite=1);
%gen_predicate(name=is_on_or_after, args=%nrstr(x, date), expr=%nrstr(((&x) >= (&date))), overwrite=1);
%macro is_between_dates(x, start, end, inclusive=both);
  %is_between(&x, &start, &end, inclusive=&inclusive)
%mend;
%_pred_registry_add(name=is_between_dates, kind=PREDICATE);

%macro test_pipr_predicates;
  %_pipr_require_assert;

  %test_suite(Testing pipr predicates);
    %test_case(core parser helpers normalize quoted text and regex forms);
      %_pred_strip_quotes(text=%str('abc'), out_text=_pp_strip1);
      %assertEqual(%superq(_pp_strip1), abc);

      %_pred_strip_quotes(text=%str("xyz"), out_text=_pp_strip2);
      %assertEqual(%superq(_pp_strip2), xyz);

      %_pred_trim_expr(text=%str(a=1;), out_text=_pp_trim1);
      %assertEqual(%superq(_pp_trim1), a=1);

      %_pred_escape_regex(text=%str(a+b?c), out_text=_pp_esc1);
      %assertEqual(%superq(_pp_esc1), %str(a\+b\?c));

      %_pred_regex_to_prx(regex=%str(state$), ignore_case=0, out_prx=_pp_rx1);
      %assertEqual(%superq(_pp_rx1), %str(/state$/));

      %_pred_regex_to_prx(regex=%str(/^state$/), ignore_case=1, out_prx=_pp_rx2);
      %assertEqual(%superq(_pp_rx2), %str(/^state$/i));

      %_pred_sql_like_to_prx(pattern=%nrstr(A_%C), ignore_case=0, out_prx=_pp_like_rx);
      %assertEqual(%superq(_pp_like_rx), %str(/^A..*C$/));
    %test_summary;

    %test_case(gen_function creates ad hoc function macros);
      %gen_function(%nrstr(((&x) > (&thr))), %nrstr(x, thr=0), gt_thr, overwrite=1, kind=PREDICATE);
      %assertTrue(%eval(%sysmacexist(gt_thr)=1), gt_thr macro was generated);

      data work._pp_gen;
        x=0; output;
        x=3; output;
      run;
      data work._pp_gen_out;
        set work._pp_gen;
        if %gt_thr(x, thr=1);
      run;

      proc sql noprint;
        select count(*) into :_pp_gen_n trimmed from work._pp_gen_out;
      quit;
      %assertEqual(&_pp_gen_n., 1);
    %test_summary;

    %test_case(gen_function positional arguments and predicate spec parser);
      %gen_function(%nrstr(((&x) = (&y))), %nrstr(x, y), eq_val, 1, GENERIC);
      %assertTrue(%eval(%sysmacexist(eq_val)=1), eq_val generated via positional parameters);

      %_pred_parse_pred_spec(spec=%str(is_zero(tol=0.01)), out_kind=_pp_pk, out_name=_pp_pn, out_args=_pp_pa, out_lambda=_pp_pl);
      %assertEqual(%upcase(&_pp_pk.), CALL);
      %assertEqual(%upcase(&_pp_pn.), IS_ZERO);
      %assertEqual(%superq(_pp_pa), %str(tol=0.01));

      %_pred_parse_pred_spec(spec=%str(~.x=0), out_kind=_pp_pk2, out_name=_pp_pn2, out_args=_pp_pa2, out_lambda=_pp_pl2);
      %assertEqual(%upcase(&_pp_pk2.), LAMBDA);
      %assertEqual(%superq(_pp_pl2), %str(~.x=0));

      %_pred_parse_pred_spec(spec=%str(is_missing), out_kind=_pp_pk3, out_name=_pp_pn3, out_args=_pp_pa3, out_lambda=_pp_pl3);
      %assertEqual(%upcase(&_pp_pk3.), NAME);
      %assertEqual(%upcase(&_pp_pn3.), IS_MISSING);
    %test_summary;

    %test_case(gen_predicate and numeric predicates);
      %gen_predicate(%nrstr((abs(&x) <= (&tol))), %nrstr(x, tol=0.01), near_zero, overwrite=1);
      %assertTrue(%eval(%sysmacexist(near_zero)=1), near_zero macro was generated);

      %predicate(%nrstr(((&x) >= (&lo) and (&x) <= (&hi))), %nrstr(x, lo=0, hi=1), between_0_1, overwrite=1);
      %assertTrue(%eval(%sysmacexist(between_0_1)=1), predicate alias generated macro);

      data work._pp_num;
        x=0.0; y=2; output;
        x=0.005; y=4; output;
        x=1.2; y=5; output;
      run;
      data work._pp_num_out;
        set work._pp_num;
        if %near_zero(x);
      run;
      proc sql noprint;
        select count(*) into :_pp_num_n trimmed from work._pp_num_out;
        select count(*) into :_pp_between_n trimmed from work._pp_num where %between_0_1(x);
      quit;
      %assertEqual(&_pp_num_n., 2);
      %assertEqual(&_pp_between_n., 2);

      data work._pp_mult;
        set work._pp_num;
        if %is_multiple_of(y, 2);
      run;
      proc sql noprint;
        select count(*) into :_pp_mult_n trimmed from work._pp_mult;
      quit;
      %assertEqual(&_pp_mult_n., 2);
    %test_summary;

    %test_case(list_functions reports registered names by kind);
      %gen_function(name=id_fn, args=x, expr=%nrstr((&x)), overwrite=1);
      %list_functions(kind=PREDICATE, out_list=_pp_pred_list);
      %assertTrue(%eval(%sysfunc(indexw(%upcase(&_pp_pred_list.), IS_MISSING)) > 0), predicate registry includes IS_MISSING);
      %assertTrue(%eval(%sysfunc(indexw(%upcase(&_pp_pred_list.), IF_ANY)) > 0), predicate registry includes IF_ANY);

      %list_functions(kind=GENERIC, out_list=_pp_generic_list);
      %assertTrue(%eval(%sysfunc(indexw(%upcase(&_pp_generic_list.), ID_FN)) > 0), generic registry includes ad hoc generated function);
    %test_summary;

    %test_case(registry add updates existing entries without duplication);
      %let _pp_reg_before=&_pipr_fn_count;
      %_pred_registry_add(name=is_missing, kind=PREDICATE, macro_name=is_missing);
      %let _pp_reg_after=&_pipr_fn_count;

      %assertEqual(&_pp_reg_after., &_pp_reg_before.);
      %assertTrue(%eval(%sysfunc(indexw(%upcase(&_pipr_functions.), IS_MISSING)) > 0), registry still includes IS_MISSING);
    %test_summary;

    %test_case(registry resolves long predicate names without overflow variables);
      %_pred_macro_for(name=is_not_missing, out_macro=_pp_m_not_missing);
      %_pred_macro_for(name=is_between_dates, out_macro=_pp_m_between_dates);
      %_pred_macro_for(name=is_on_or_before, out_macro=_pp_m_on_or_before);

      %assertEqual(%upcase(&_pp_m_not_missing.), IS_NOT_MISSING);
      %assertEqual(%upcase(&_pp_m_between_dates.), IS_BETWEEN_DATES);
      %assertEqual(%upcase(&_pp_m_on_or_before.), IS_ON_OR_BEFORE);
    %test_summary;

    %test_case(missingness and equality predicates);
      data work._pp_misc;
        length c $8;
        x=.; c=' '; output;
        x=2; c='ABC'; output;
      run;

      data work._pp_missing;
        set work._pp_misc;
        if %is_missing(c);
      run;
      proc sql noprint;
        select count(*) into :_pp_missing_n trimmed from work._pp_missing;
      quit;
      %assertEqual(&_pp_missing_n., 1);

      data work._pp_eq;
        set work._pp_misc;
        if %is_equal(c, 'ABC');
      run;
      proc sql noprint;
        select count(*) into :_pp_eq_n trimmed from work._pp_eq;
      quit;
      %assertEqual(&_pp_eq_n., 1);

      data work._pp_na_like;
        set work._pp_misc;
        if %is_na_like(c, values='ABC');
      run;
      proc sql noprint;
        select count(*) into :_pp_na_like_n trimmed from work._pp_na_like;
      quit;
      %assertEqual(&_pp_na_like_n., 2);

      data work._pp_not_missing;
        set work._pp_misc;
        if %is_not_missing(c);
      run;
      proc sql noprint;
        select count(*) into :_pp_not_missing_n trimmed from work._pp_not_missing;
      quit;
      %assertEqual(&_pp_not_missing_n., 1);
    %test_summary;

    %test_case(string predicates);
      data work._pp_str;
        length s $16;
        s='Policy_A'; output;
        s='home_code'; output;
        s='X123'; output;
      run;

      data work._pp_sw;
        set work._pp_str;
        if %starts_with(s, 'policy', ignore_case=1);
      run;
      proc sql noprint;
        select count(*) into :_pp_sw_n trimmed from work._pp_sw;
      quit;
      %assertEqual(&_pp_sw_n., 1);

      data work._pp_like;
        set work._pp_str;
        if %is_like(s, 'home%');
      run;
      proc sql noprint;
        select count(*) into :_pp_like_n trimmed from work._pp_like;
      quit;
      %assertEqual(&_pp_like_n., 1);

      data work._pp_match;
        set work._pp_str;
        if %matches(s, %str(/^x[0-9]+$/), ignore_case=1);
      run;
      proc sql noprint;
        select count(*) into :_pp_match_n trimmed from work._pp_match;
      quit;
      %assertEqual(&_pp_match_n., 1);

      data work._pp_contains_plain;
        set work._pp_str;
        if %contains(s, 'POLICY', ignore_case=0, regex=0);
      run;
      proc sql noprint;
        select count(*) into :_pp_contains_plain_n trimmed from work._pp_contains_plain;
      quit;
      %assertEqual(&_pp_contains_plain_n., 0);

      data work._pp_contains_rx;
        set work._pp_str;
        if %contains(s, %str(^policy), ignore_case=1, regex=1);
      run;
      proc sql noprint;
        select count(*) into :_pp_contains_rx_n trimmed from work._pp_contains_rx;
      quit;
      %assertEqual(&_pp_contains_rx_n., 1);
    %test_summary;

    %test_case(interval and membership predicates);
      data work._pp_rng;
        x=0; output;
        x=1; output;
        x=2; output;
        x=3; output;
      run;

      data work._pp_rng_left;
        set work._pp_rng;
        if %is_between(x, 1, 3, inclusive=LEFT);
      run;
      data work._pp_rng_right;
        set work._pp_rng;
        if %is_between(x, 1, 3, inclusive=RIGHT);
      run;
      data work._pp_rng_none;
        set work._pp_rng;
        if %is_between(x, 1, 3, inclusive=NONE);
      run;
      data work._pp_rng_out;
        set work._pp_rng;
        if %is_outside(x, 1, 2);
      run;
      data work._pp_in;
        set work._pp_rng;
        if %is_in(x, 1, 3);
      run;
      data work._pp_not_in;
        set work._pp_rng;
        if %is_not_in(x, 1, 3);
      run;

      proc sql noprint;
        select count(*) into :_pp_rng_left_n trimmed from work._pp_rng_left;
        select count(*) into :_pp_rng_right_n trimmed from work._pp_rng_right;
        select count(*) into :_pp_rng_none_n trimmed from work._pp_rng_none;
        select count(*) into :_pp_rng_out_n trimmed from work._pp_rng_out;
        select count(*) into :_pp_in_n trimmed from work._pp_in;
        select count(*) into :_pp_not_in_n trimmed from work._pp_not_in;
      quit;

      %assertEqual(&_pp_rng_left_n., 2);
      %assertEqual(&_pp_rng_right_n., 2);
      %assertEqual(&_pp_rng_none_n., 1);
      %assertEqual(&_pp_rng_out_n., 2);
      %assertEqual(&_pp_in_n., 2);
      %assertEqual(&_pp_not_in_n., 2);
    %test_summary;

    %test_case(date predicates);
      data work._pp_date;
        d='01JAN2024'd; output;
        d='03JAN2024'd; output;
      run;

      data work._pp_date_out;
        set work._pp_date;
        if %is_on_or_before(d, '02JAN2024'd);
      run;
      proc sql noprint;
        select count(*) into :_pp_date_n trimmed from work._pp_date_out;
      quit;
      %assertEqual(&_pp_date_n., 1);
    %test_summary;

    %test_case(data-quality string predicates);
      data work._pp_qual;
        length raw_num raw_date raw_fmt $16;
        raw_num='123.45'; raw_date='2024-02-01'; raw_fmt='AB-12'; output;
        raw_num='abc'; raw_date='bad'; raw_fmt='ZZ'; output;
      run;

      data work._pp_numstr;
        set work._pp_qual;
        if %is_numeric_string(raw_num);
      run;
      proc sql noprint;
        select count(*) into :_pp_numstr_n trimmed from work._pp_numstr;
      quit;
      %assertEqual(&_pp_numstr_n., 1);

      data work._pp_datestr;
        set work._pp_qual;
        if %is_date_string(raw_date);
      run;
      proc sql noprint;
        select count(*) into :_pp_datestr_n trimmed from work._pp_datestr;
      quit;
      %assertEqual(&_pp_datestr_n., 1);

      data work._pp_fmt;
        set work._pp_qual;
        if %is_in_format(raw_fmt, %str(/^[A-Z]{2}-[0-9]{2}$/));
      run;
      proc sql noprint;
        select count(*) into :_pp_fmt_n trimmed from work._pp_fmt;
      quit;
      %assertEqual(&_pp_fmt_n., 1);
    %test_summary;

    %test_case(if_any and if_all apply predicates across columns);
      data work._pp_any;
        a=1; b=0; c=.; output;
        a=2; b=3; c=4; output;
        a=.; b=.; c=.; output;
      run;

      data work._pp_any_out;
        set work._pp_any;
        if %if_any(cols=a b c, pred=is_zero());
      run;
      proc sql noprint;
        select count(*) into :_pp_any_n trimmed from work._pp_any_out;
      quit;
      %assertEqual(&_pp_any_n., 1);

      data work._pp_all_out;
        set work._pp_any;
        if %if_all(cols=a b c, pred=is_not_missing());
      run;
      proc sql noprint;
        select count(*) into :_pp_all_n trimmed from work._pp_all_out;
      quit;
      %assertEqual(&_pp_all_n., 1);

      data work._pp_any_tol;
        set work._pp_any;
        if %if_any(a b c, is_zero(), tol=0.01);
      run;
      proc sql noprint;
        select count(*) into :_pp_any_tol_n trimmed from work._pp_any_tol;
      quit;
      %assertEqual(&_pp_any_tol_n., 1);

      data work._pp_all_positional;
        set work._pp_any;
        if %if_all(a b c, is_not_missing());
      run;
      proc sql noprint;
        select count(*) into :_pp_all_positional_n trimmed from work._pp_all_positional;
      quit;
      %assertEqual(&_pp_all_positional_n., 1);

      data work._pp_any_callspec;
        set work._pp_any;
        if %if_any(cols=a b c, pred=is_between(0, 1));
      run;
      proc sql noprint;
        select count(*) into :_pp_any_callspec_n trimmed from work._pp_any_callspec;
      quit;
      %assertEqual(&_pp_any_callspec_n., 1);
    %test_summary;

    %test_case(expander resolves bare predicate calls without percent prefix);
      data work._pp_expand;
        a=1; b=0; c=.; output;
        a=2; b=3; c=4; output;
        a=.; b=.; c=.; output;
      run;

      %_pred_expand_expr(expr=%str(is_zero(b) or is_missing(c)), out_expr=_pp_exp_expr);
      data work._pp_expand_out1;
        set work._pp_expand;
        if %superq(_pp_exp_expr);
      run;
      proc sql noprint;
        select count(*) into :_pp_exp_n1 trimmed from work._pp_expand_out1;
      quit;
      %assertEqual(&_pp_exp_n1., 2);

      %_pred_expand_expr(expr=%str(if_any(cols=a b c, pred=is_zero())), out_expr=_pp_exp_any_expr);
      data work._pp_expand_out2;
        set work._pp_expand;
        if %superq(_pp_exp_any_expr);
      run;
      proc sql noprint;
        select count(*) into :_pp_exp_n2 trimmed from work._pp_expand_out2;
      quit;
      %assertEqual(&_pp_exp_n2., 1);
    %test_summary;

    %test_case(if_any supports lambda predicate templates);
      data work._pp_lambda;
        length c1 c2 $8;
        c1='X1'; c2='A1'; output;
        c1='A1'; c2='X2'; output;
        c1='A1'; c2='B1'; output;
      run;

      data work._pp_lambda_out;
        set work._pp_lambda;
        if %if_any(cols=c1 c2, pred=~prxmatch('/^X/', strip(.x)) > 0);
      run;

      proc sql noprint;
        select count(*) into :_pp_lambda_n trimmed from work._pp_lambda_out;
      quit;
      %assertEqual(&_pp_lambda_n., 2);

      data work._pp_lambda_out2;
        set work._pp_lambda;
        if %if_all(cols=c1 c2, pred=lambda(prxmatch('/^[A-Z][0-9]$/', strip(.x)) > 0));
      run;
      proc sql noprint;
        select count(*) into :_pp_lambda_n2 trimmed from work._pp_lambda_out2;
      quit;
      %assertEqual(&_pp_lambda_n2., 3);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist;
    delete _pp_gen _pp_gen_out _pp_num _pp_num_out _pp_mult _pp_misc _pp_missing _pp_eq _pp_na_like _pp_not_missing _pp_str _pp_sw _pp_like _pp_match _pp_contains_plain _pp_contains_rx _pp_rng _pp_rng_left _pp_rng_right _pp_rng_none _pp_rng_out _pp_in _pp_not_in _pp_date _pp_date_out _pp_qual _pp_numstr _pp_datestr _pp_fmt _pp_any _pp_any_out _pp_all_out _pp_any_tol _pp_all_positional _pp_any_callspec _pp_expand _pp_expand_out1 _pp_expand_out2 _pp_lambda _pp_lambda_out _pp_lambda_out2;
  quit;
%mend test_pipr_predicates;

%_pipr_autorun_tests(test_pipr_predicates);
