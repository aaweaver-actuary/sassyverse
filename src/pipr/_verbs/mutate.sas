%macro _mutate_emit_data(stmt, data=, out=, as_view=0);
  %if &as_view %then %do;
    data &out / view=&out;
      set &data;
      &stmt
    run;
  %end;
  %else %do;
    data &out;
      set &data;
      &stmt
    run;
  %end;
%mend;

%macro _mutate_parse_parmbuff(
  stmt_in=,
  data_in=,
  out_in=,
  validate_in=,
  as_view_in=,
  out_stmt=,
  out_data=,
  out_out=,
  out_validate=,
  out_as_view=
);
  %local _buf _n _i _seg _head _eq _val _stmt_acc;

  %let &out_stmt=%superq(stmt_in);
  %let &out_data=%superq(data_in);
  %let &out_out=%superq(out_in);
  %let &out_validate=%superq(validate_in);
  %let &out_as_view=%superq(as_view_in);

  %let _stmt_acc=;
  %let _buf=%superq(syspbuff);
  %if %length(%superq(_buf)) > 2 %then %do;
    %if not %sysmacexist(_pipr_split_parmbuff_segments) %then %_abort(mutate() requires pipr util helpers to be loaded.);
    %_pipr_split_parmbuff_segments(buf=%superq(_buf), out_n=_n, out_prefix=_mt_seg);

    %do _i=1 %to &_n;
      %let _seg=%sysfunc(strip(%superq(_mt_seg&_i)));
      %if %length(%superq(_seg)) > 0 %then %do;
        %let _head=%upcase(%sysfunc(strip(%scan(%superq(_seg), 1, =))));
        %if %sysfunc(indexw(DATA OUT VALIDATE AS_VIEW STMT, &_head)) > 0 %then %do;
          %let _eq=%index(%superq(_seg), %str(=));
          %if &_eq > 0 %then %let _val=%substr(%superq(_seg), %eval(&_eq+1));
          %else %let _val=;

          %if &_head=DATA %then %let &out_data=%sysfunc(strip(%superq(_val)));
          %else %if &_head=OUT %then %let &out_out=%sysfunc(strip(%superq(_val)));
          %else %if &_head=VALIDATE %then %let &out_validate=%sysfunc(strip(%superq(_val)));
          %else %if &_head=AS_VIEW %then %let &out_as_view=%sysfunc(strip(%superq(_val)));
          %else %if &_head=STMT %then %let _stmt_acc=%sysfunc(strip(%superq(_val)));
        %end;
        %else %do;
          /* Treat unknown segments as mutate expressions (supports mutate(a=x+1, b=a*2)). */
          %if %length(%superq(_stmt_acc))=0 %then %let _stmt_acc=%superq(_seg);
          %else %let _stmt_acc=%superq(_stmt_acc), %superq(_seg);
        %end;
      %end;
    %end;
  %end;

  %if %length(%superq(_stmt_acc))=0 %then %let _stmt_acc=%superq(stmt_in);
  %let &out_stmt=%superq(_stmt_acc);
%mend;

%macro _mutate_normalize_stmt(stmt, out_stmt);
  %local _raw _norm;
  %global &out_stmt;
  %let _raw=%sysfunc(strip(%unquote(%superq(stmt))));
  %if %length(%superq(_raw))=0 %then %_abort(mutate() requires a non-empty expression or statement block.);

  data _null_;
    length raw norm tok $32767 ch quote $1;
    raw = strip(symget('_raw'));

    if index(raw, ';') > 0 then norm = raw;
    else do;
      norm = '';
      tok = '';
      quote = '';
      depth = 0;

      do i = 1 to length(raw);
        ch = substr(raw, i, 1);

        if quote = '' then do;
          if ch = "'" or ch = '"' then quote = ch;
          else if ch = '(' then depth + 1;
          else if ch = ')' and depth > 0 then depth + (-1);
        end;
        else if ch = quote then quote = '';

        if quote = '' and depth = 0 and ch = ',' then do;
          if length(strip(tok)) then norm = catx(' ', norm, cats(strip(tok), ';'));
          tok = '';
        end;
        else tok = cats(tok, ch);
      end;

      if length(strip(tok)) then norm = catx(' ', norm, cats(strip(tok), ';'));
    end;

    norm = strip(norm);
    if length(norm) > 0 and substr(norm, length(norm), 1) ne ';' then norm = cats(norm, ';');
    call symputx('_norm', norm, 'L');
  run;

  %let &out_stmt=%superq(_norm);
%mend;

%macro _mutate_expand_functions(stmt=, out_stmt=);
  %local _stmt_in _stmt_out;
  %let _stmt_in=%superq(stmt);
  %if %length(%superq(_stmt_in))=0 %then %do;
    %let &out_stmt=;
    %return;
  %end;

  %if %sysmacexist(_pred_expand_expr) %then %do;
    %_pred_expand_expr(expr=%superq(_stmt_in), out_expr=_stmt_out);
    %let &out_stmt=%superq(_stmt_out);
  %end;
  %else %let &out_stmt=%superq(_stmt_in);
%mend;

%macro mutate(stmt, data=, out=, validate=1, as_view=0) / parmbuff;
  %local _as_view _stmt_norm _stmt_eval _stmt_work _data_work _out_work _validate_work _as_view_work;

  %_mutate_parse_parmbuff(
    stmt_in=%superq(stmt),
    data_in=%superq(data),
    out_in=%superq(out),
    validate_in=%superq(validate),
    as_view_in=%superq(as_view),
    out_stmt=_stmt_work,
    out_data=_data_work,
    out_out=_out_work,
    out_validate=_validate_work,
    out_as_view=_as_view_work
  );

  %let _as_view=%_pipr_bool(%superq(_as_view_work), default=0);
  %_assert_ds_exists(&_data_work);
  %_mutate_normalize_stmt(%superq(_stmt_work), _stmt_norm);
  %_mutate_expand_functions(stmt=%superq(_stmt_norm), out_stmt=_stmt_eval);

  %_mutate_emit_data(stmt=%superq(_stmt_eval), data=&_data_work, out=&_out_work, as_view=&_as_view);
  %if &syserr > 4 %then %_abort(mutate() failed (SYSERR=&syserr).);
%mend;

%macro with_column(col_name, col_expr, data=, out=, validate=1, as_view=0) / parmbuff;
  %local _stmt_work _stmt_final _data_work _out_work _validate_work _as_view_work;

  %_mutate_parse_parmbuff(
    stmt_in=,
    data_in=%superq(data),
    out_in=%superq(out),
    validate_in=%superq(validate),
    as_view_in=%superq(as_view),
    out_stmt=_stmt_work,
    out_data=_data_work,
    out_out=_out_work,
    out_validate=_validate_work,
    out_as_view=_as_view_work
  );

  /* Backward-compatible two-arg form: with_column(name, expr, ...). */
  %if %index(%superq(col_name), %str(=)) = 0 and %length(%superq(col_expr)) > 0 %then %do;
    %let _stmt_final=%superq(col_name) = %superq(col_expr);
  %end;
  %else %let _stmt_final=%superq(_stmt_work);

  %mutate(
    stmt=%superq(_stmt_final),
    data=%superq(_data_work),
    out=%superq(_out_work),
    validate=%superq(_validate_work),
    as_view=%superq(_as_view_work)
  );
%mend;

%macro test_mutate;
  %_pipr_require_assert;

  %test_suite(Testing mutate);
    %test_case(mutate adds column);
      data work._mut;
        x=2; output;
        x=4; output;
      run;

      %mutate(y = x * 2, data=work._mut, out=work._mut2);

      proc sql noprint;
        select sum(y) into :_sum_y trimmed from work._mut2;
      quit;

      %assertEqual(&_sum_y., 12);
    %test_summary;

    %test_case(%nrstr(mutate supports expressions with commas without explicit %str));
      %mutate(y = ifc(x > 2, 1, 0), data=work._mut, out=work._mut_ifc);
      proc sql noprint;
        select sum(y) into :_sum_y_ifc trimmed from work._mut_ifc;
      quit;
      %assertEqual(&_sum_y_ifc., 1);
    %test_summary;

    %test_case(mutate supports comma-delimited assignments);
      %mutate(a = x + 1, b = a * 2, data=work._mut, out=work._mut_multi);
      proc sql noprint;
        select sum(b) into :_sum_b_multi trimmed from work._mut_multi;
      quit;
      %assertEqual(&_sum_b_multi., 16);
    %test_summary;

    %test_case(mutate supports compact comma-delimited assignments);
      %mutate(a=x+1,b=a*2, data=work._mut, out=work._mut_multi_compact);
      proc sql noprint;
        select sum(b) into :_sum_b_multi_compact trimmed from work._mut_multi_compact;
      quit;
      %assertEqual(&_sum_b_multi_compact., 16);
    %test_summary;

    %test_case(mutate supports named stmt= with boolean flags and view output);
      %mutate(stmt=a=x+1, data=work._mut, out=work._mut_named_view, validate=NO, as_view=TRUE);
      %assertEqual(%sysfunc(exist(work._mut_named_view, view)), 1);
      proc sql noprint;
        select sum(a) into :_sum_a_named_view trimmed from work._mut_named_view;
      quit;
      %assertEqual(&_sum_a_named_view., 8);
    %test_summary;

    %if %sysmacexist(is_positive) and %sysmacexist(is_between) %then %do;
      %test_case(mutate expands registered predicates without percent prefix);
        %mutate(flag = is_positive(x), in_2_3 = is_between(x, 2, 3), data=work._mut, out=work._mut_pred);
        proc sql noprint;
          select sum(flag) into :_sum_flag_pred trimmed from work._mut_pred;
          select sum(in_2_3) into :_sum_in_2_3 trimmed from work._mut_pred;
        quit;
        %assertEqual(&_sum_flag_pred., 2);
        %assertEqual(&_sum_in_2_3., 1);
      %test_summary;
    %end;

    %test_case(mutate remains compatible with explicit statement blocks);
      %mutate(%str(y = x * 3;), data=work._mut, out=work._mut3x);
      proc sql noprint;
        select sum(y) into :_sum_y_3x trimmed from work._mut3x;
      quit;
      %assertEqual(&_sum_y_3x., 18);
    %test_summary;

    %test_case(with_column alias);
      %with_column(z, x + 1, data=work._mut, out=work._mut3);
      proc sql noprint;
        select min(z) into :_min_z trimmed from work._mut3;
      quit;
      %assertEqual(&_min_z., 3);

      %with_column(flag, ifc(x > 2, 1, 0), data=work._mut, out=work._mut4);
      proc sql noprint;
        select sum(flag) into :_sum_flag_wc trimmed from work._mut4;
      quit;
      %assertEqual(&_sum_flag_wc., 1);
    %test_summary;

    %test_case(with_column supports mutate-style assignment expressions);
      %with_column(a = x + 1, b = a * 2, data=work._mut, out=work._mut_wc_multi);
      proc sql noprint;
        select sum(b) into :_sum_b_wc_multi trimmed from work._mut_wc_multi;
      quit;
      %assertEqual(&_sum_b_wc_multi., 16);
    %test_summary;

    %if %sysmacexist(is_positive) %then %do;
      %test_case(with_column expands predicates without percent prefix);
        %with_column(flag = is_positive(x), data=work._mut, out=work._mut_wc_pred);
        proc sql noprint;
          select sum(flag) into :_sum_wc_pred trimmed from work._mut_wc_pred;
        quit;
        %assertEqual(&_sum_wc_pred., 2);
      %test_summary;
    %end;

    %test_case(mutate helper view);
      %_mutate_emit_data(stmt=%str(z = x + 2;), data=work._mut, out=work._mut_view, as_view=1);
      %assertTrue(%eval(%sysfunc(exist(work._mut_view, view))=1), view created);
      proc sql noprint;
        select max(z) into :_max_z trimmed from work._mut_view;
      quit;
      %assertEqual(&_max_z., 6);
    %test_summary;

    %test_case(mutate supports as_view and validate boolean flags);
      %mutate(y = x + 5, data=work._mut, out=work._mut_view2, validate=YES, as_view=TRUE);
      %assertEqual(%sysfunc(exist(work._mut_view2, view)), 1);
      proc sql noprint;
        select sum(y) into :_sum_y_view2 trimmed from work._mut_view2;
      quit;
      %assertEqual(&_sum_y_view2., 16);
    %test_summary;

    %test_case(with_column supports named argument style);
      %with_column(
        col_name=flag,
        col_expr=(x >= 4),
        data=work._mut,
        out=work._mut_named,
        validate=NO,
        as_view=0
      );
      proc sql noprint;
        select sum(flag) into :_sum_flag_named trimmed from work._mut_named;
      quit;
      %assertEqual(&_sum_flag_named., 1);
    %test_summary;

    %test_case(mutate normalize helper preserves semicolon blocks and splits comma lists);
      %_mutate_normalize_stmt(%str(a=x+1; b=a*2;), _mut_norm1);
      %assertEqual(%superq(_mut_norm1), %str(a=x+1; b=a*2;));

      %_mutate_normalize_stmt(%str(a=x+1,b=a*2), _mut_norm2);
      %assertEqual(%superq(_mut_norm2), %str(a=x+1; b=a*2;));
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist;
    delete _mut _mut2 _mut_ifc _mut_multi _mut_multi_compact _mut_pred _mut3x _mut3 _mut4 _mut_wc_multi _mut_wc_pred _mut_named;
    delete _mut_view _mut_view2 _mut_named_view / memtype=view;
  quit;
%mend test_mutate;

%_pipr_autorun_tests(test_mutate);
