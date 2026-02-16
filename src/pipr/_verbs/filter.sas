%macro _filter_emit_data(where_expr, data=, out=, as_view=0);
  %if &as_view %then %do;
    data &out / view=&out;
      set &data;
      %if %length(%superq(where_expr)) %then %do;
        if (&where_expr);
      %end;
    run;
  %end;
  %else %do;
    data &out;
      set &data;
      %if %length(%superq(where_expr)) %then %do;
        if (&where_expr);
      %end;
    run;
  %end;
%mend;

%macro _filter_parse_parmbuff(
  where_in=,
  data_in=,
  out_in=,
  validate_in=,
  as_view_in=,
  out_where=,
  out_data=,
  out_out=,
  out_validate=,
  out_as_view=
);
  %local _buf _n _i _seg _head _eq _val _where_acc;

  %let &out_where=%superq(where_in);
  %let &out_data=%superq(data_in);
  %let &out_out=%superq(out_in);
  %let &out_validate=%superq(validate_in);
  %let &out_as_view=%superq(as_view_in);

  %let _where_acc=;
  %let _buf=%superq(syspbuff);
  %if %length(%superq(_buf)) > 2 %then %do;
    %if not %sysmacexist(_pipr_split_parmbuff_segments) %then
      %_abort(filter() requires pipr util helpers to be loaded.);
    %_pipr_split_parmbuff_segments(buf=%superq(_buf), out_n=_n, out_prefix=_flt_seg);

    %do _i=1 %to &_n;
      %let _seg=%sysfunc(strip(%superq(_flt_seg&_i)));
      %if %length(%superq(_seg))=0 %then %goto _flt_next;

      %let _head=%upcase(%sysfunc(strip(%scan(%superq(_seg), 1, =))));
      %if %sysfunc(indexw(DATA OUT VALIDATE AS_VIEW WHERE_EXPR MASK_EXPR EXPR, &_head)) > 0 %then %do;
        %let _eq=%index(%superq(_seg), %str(=));
        %if &_eq > 0 %then %let _val=%sysfunc(strip(%substr(%superq(_seg), %eval(&_eq+1))));
        %else %let _val=;

        %if &_head=DATA %then %let &out_data=%superq(_val);
        %else %if &_head=OUT %then %let &out_out=%superq(_val);
        %else %if &_head=VALIDATE %then %let &out_validate=%superq(_val);
        %else %if &_head=AS_VIEW %then %let &out_as_view=%superq(_val);
        %else %if &_head=WHERE_EXPR or &_head=MASK_EXPR or &_head=EXPR %then %let _where_acc=%superq(_val);
      %end;
      %else %do;
        %if %length(%superq(_where_acc))=0 %then %let _where_acc=%superq(_seg);
        %else %let _where_acc=%superq(_where_acc), %superq(_seg);
      %end;

      %_flt_next:
    %end;
  %end;

  %if %length(%superq(_where_acc))=0 %then %let _where_acc=%superq(where_in);
  %let &out_where=%superq(_where_acc);
%mend;

%macro _where_if_parse_parmbuff(
  where_in=,
  condition_in=,
  data_in=,
  out_in=,
  validate_in=,
  as_view_in=,
  out_where=,
  out_condition=,
  out_data=,
  out_out=,
  out_validate=,
  out_as_view=
);
  %local _buf _n _i _seg _head _eq _val _where_acc _pos;

  %let &out_where=%superq(where_in);
  %let &out_condition=%superq(condition_in);
  %let &out_data=%superq(data_in);
  %let &out_out=%superq(out_in);
  %let &out_validate=%superq(validate_in);
  %let &out_as_view=%superq(as_view_in);

  %let _where_acc=;
  %let _pos=0;
  %let _buf=%superq(syspbuff);
  %if %length(%superq(_buf)) > 2 %then %do;
    %if not %sysmacexist(_pipr_split_parmbuff_segments) %then
      %_abort(where_if() requires pipr util helpers to be loaded.);
    %_pipr_split_parmbuff_segments(buf=%superq(_buf), out_n=_n, out_prefix=_wif_seg);

    %do _i=1 %to &_n;
      %let _seg=%sysfunc(strip(%superq(_wif_seg&_i)));
      %if %length(%superq(_seg))=0 %then %goto _wif_next;

      %let _head=%upcase(%sysfunc(strip(%scan(%superq(_seg), 1, =))));
      %if %sysfunc(indexw(DATA OUT VALIDATE AS_VIEW WHERE_EXPR EXPR CONDITION, &_head)) > 0 %then %do;
        %let _eq=%index(%superq(_seg), %str(=));
        %if &_eq > 0 %then %let _val=%sysfunc(strip(%substr(%superq(_seg), %eval(&_eq+1))));
        %else %let _val=;

        %if &_head=DATA %then %let &out_data=%superq(_val);
        %else %if &_head=OUT %then %let &out_out=%superq(_val);
        %else %if &_head=VALIDATE %then %let &out_validate=%superq(_val);
        %else %if &_head=AS_VIEW %then %let &out_as_view=%superq(_val);
        %else %if &_head=CONDITION %then %let &out_condition=%superq(_val);
        %else %if &_head=WHERE_EXPR or &_head=EXPR %then %let _where_acc=%superq(_val);
      %end;
      %else %do;
        %let _pos=%eval(&_pos + 1);
        %if &_pos = 1 %then %let _where_acc=%superq(_seg);
        %else %if &_pos = 2 %then %let &out_condition=%superq(_seg);
        %else %if %length(%superq(_where_acc))=0 %then %let _where_acc=%superq(_seg);
        %else %let _where_acc=%superq(_where_acc), %superq(_seg);
      %end;

      %_wif_next:
    %end;
  %end;

  %if %length(%superq(_where_acc))=0 %then %let _where_acc=%superq(where_in);
  %let &out_where=%superq(_where_acc);
%mend;

%macro _filter_expand_where(where_expr=, out_where=);
  %local _in _out;
  %let _in=%superq(where_expr);
  %if %length(%superq(_in))=0 %then %do;
    %let &out_where=;
    %return;
  %end;

  %if %sysmacexist(_pred_expand_expr) %then %do;
    %_pred_expand_expr(expr=%superq(_in), out_expr=_out);
    %let &out_where=%superq(_out);
  %end;
  %else %let &out_where=%superq(_in);
%mend;

%macro filter(where_expr, data=, out=, validate=1, as_view=0) / parmbuff;
  %local _where_work _where_eval _data_work _out_work _validate_work _as_view_work _as_view;
  %_filter_parse_parmbuff(
    where_in=%superq(where_expr),
    data_in=%superq(data),
    out_in=%superq(out),
    validate_in=%superq(validate),
    as_view_in=%superq(as_view),
    out_where=_where_work,
    out_data=_data_work,
    out_out=_out_work,
    out_validate=_validate_work,
    out_as_view=_as_view_work
  );

  %let _as_view=%_pipr_bool(%superq(_as_view_work), default=0);
  %_assert_ds_exists(&_data_work);
  %_filter_expand_where(where_expr=%superq(_where_work), out_where=_where_eval);

  %_filter_emit_data(where_expr=%superq(_where_eval), data=&_data_work, out=&_out_work, as_view=&_as_view);
  %if &syserr > 4 %then %_abort(filter() failed (SYSERR=&syserr).);
%mend;

%macro where(where_expr, data=, out=, validate=1, as_view=0) / parmbuff;
  %unquote(%nrstr(%filter)&syspbuff);
%mend;

%macro where_not(where_expr, data=, out=, validate=1, as_view=0) / parmbuff;
  %local _where_work _data_work _out_work _validate_work _as_view_work;
  %_filter_parse_parmbuff(
    where_in=%superq(where_expr),
    data_in=%superq(data),
    out_in=%superq(out),
    validate_in=%superq(validate),
    as_view_in=%superq(as_view),
    out_where=_where_work,
    out_data=_data_work,
    out_out=_out_work,
    out_validate=_validate_work,
    out_as_view=_as_view_work
  );
  %if %length(%superq(_where_work))=0 %then %_abort(where_not() requires a non-empty where expression.);

  %filter(
    where_expr=not (%superq(_where_work)),
    data=%superq(_data_work),
    out=%superq(_out_work),
    validate=%superq(_validate_work),
    as_view=%superq(_as_view_work)
  );
%mend;

%macro mask(mask_expr, data=, out=, validate=1, as_view=0) / parmbuff;
  %local _where_work _data_work _out_work _validate_work _as_view_work;
  %_filter_parse_parmbuff(
    where_in=%superq(mask_expr),
    data_in=%superq(data),
    out_in=%superq(out),
    validate_in=%superq(validate),
    as_view_in=%superq(as_view),
    out_where=_where_work,
    out_data=_data_work,
    out_out=_out_work,
    out_validate=_validate_work,
    out_as_view=_as_view_work
  );
  %if %length(%superq(_where_work))=0 %then %_abort(mask() requires a non-empty mask expression.);

  %filter(
    where_expr=not (%superq(_where_work)),
    data=%superq(_data_work),
    out=%superq(_out_work),
    validate=%superq(_validate_work),
    as_view=%superq(_as_view_work)
  );
%mend;

%macro where_if(where_expr, condition, data=, out=, validate=1, as_view=0) / parmbuff;
  %local _where_work _cond_work _data_work _out_work _validate_work _as_view_work _condition;
  %_where_if_parse_parmbuff(
    where_in=%superq(where_expr),
    condition_in=%superq(condition),
    data_in=%superq(data),
    out_in=%superq(out),
    validate_in=%superq(validate),
    as_view_in=%superq(as_view),
    out_where=_where_work,
    out_condition=_cond_work,
    out_data=_data_work,
    out_out=_out_work,
    out_validate=_validate_work,
    out_as_view=_as_view_work
  );

  %let _condition=%_pipr_bool(%superq(_cond_work), default=0);
  %if &_condition %then %do;
    %filter(
      where_expr=%superq(_where_work),
      data=%superq(_data_work),
      out=%superq(_out_work),
      validate=%superq(_validate_work),
      as_view=%superq(_as_view_work)
    );
  %end;
  %else %do;
    %filter(
      where_expr=,
      data=%superq(_data_work),
      out=%superq(_out_work),
      validate=%superq(_validate_work),
      as_view=%superq(_as_view_work)
    );
  %end;
%mend;

%macro test_filter;
  %_pipr_require_assert;

  %test_suite(Testing filter);
    %test_case(filter and where_not);
      data work._flt;
        x=1; output;
        x=2; output;
        x=3; output;
      run;

      %filter(x > 1, data=work._flt, out=work._flt_gt1);
      %where_not(x > 1, data=work._flt, out=work._flt_le1);

      proc sql noprint;
        select count(*) into :_cnt_gt1 trimmed from work._flt_gt1;
        select count(*) into :_cnt_le1 trimmed from work._flt_le1;
      quit;

      %assertEqual(&_cnt_gt1., 2);
      %assertEqual(&_cnt_le1., 1);
    %test_summary;

    %test_case(where_if condition toggles filter);
      %where_if(x > 1, 0, data=work._flt, out=work._flt_all);
      proc sql noprint;
        select count(*) into :_cnt_all trimmed from work._flt_all;
      quit;
      %assertEqual(&_cnt_all., 3);
    %test_summary;

    %test_case(filter helper view);
      %_filter_emit_data(where_expr=x > 1, data=work._flt, out=work._flt_view, as_view=1);
      %assertTrue(%eval(%sysfunc(exist(work._flt_view, view))=1), view created);
      proc sql noprint;
        select count(*) into :_cnt_view trimmed from work._flt_view;
      quit;
      %assertEqual(&_cnt_view., 2);
    %test_summary;

    %if %sysmacexist(if_any) and %sysmacexist(if_all) %then %do;
      %test_case(filter supports if_any and if_all without percent prefix);
        data work._flt_any;
          a=1; b=0; c=.; output;
          a=2; b=3; c=4; output;
          a=.; b=.; c=.; output;
        run;

        %filter(if_any(cols=a b c, pred=is_zero()), data=work._flt_any, out=work._flt_any_out);
        %filter(if_all(cols=a b c, pred=is_not_missing()), data=work._flt_any, out=work._flt_all_out);

        proc sql noprint;
          select count(*) into :_cnt_any trimmed from work._flt_any_out;
          select count(*) into :_cnt_all_cols trimmed from work._flt_all_out;
        quit;

        %assertEqual(&_cnt_any., 1);
        %assertEqual(&_cnt_all_cols., 1);
      %test_summary;
    %end;

    %if %sysmacexist(is_positive) and %sysmacexist(is_between) %then %do;
      %test_case(filter expands registered predicates without percent prefix);
        %filter(is_positive(x), data=work._flt, out=work._flt_pos);
        %filter(is_between(x, 1, 2), data=work._flt, out=work._flt_between);

        proc sql noprint;
          select count(*) into :_cnt_pos trimmed from work._flt_pos;
          select count(*) into :_cnt_between trimmed from work._flt_between;
        quit;

        %assertEqual(&_cnt_pos., 2);
        %assertEqual(&_cnt_between., 2);
      %test_summary;
    %end;
  %test_summary;

  proc datasets lib=work nolist;
    delete _flt _flt_gt1 _flt_le1 _flt_all _flt_view _flt_any _flt_any_out _flt_all_out _flt_pos _flt_between;
  quit;
%mend test_filter;

%_pipr_autorun_tests(test_filter);
