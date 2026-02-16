%macro _select_emit_data(cols, data=, out=, as_view=0);
  %if &as_view %then %do;
    data &out / view=&out;
      set &data(keep=&cols);
    run;
  %end;
  %else %do;
    data &out;
      set &data(keep=&cols);
    run;
  %end;
%mend;

%macro select(cols, data=, out=, validate=1, as_view=0);
  %local _validate _as_view _resolved_cols;
  %let _validate=%_pipr_bool(%superq(validate), default=1);
  %let _as_view=%_pipr_bool(%superq(as_view), default=0);
  %_assert_ds_exists(&data);
  %if %sysmacexist(_sel_expand) %then %do;
    %_sel_expand(ds=&data, expr=%superq(cols), out_cols=_resolved_cols, validate=&_validate);
  %end;
  %else %do;
    %let _resolved_cols=%superq(cols);
    %if %index(%superq(_resolved_cols), %str(%()) > 0 %then %do;
      %_abort(select() selector expressions require pipr/_selectors to be loaded.);
    %end;
    %if &_validate %then %_assert_cols_exist(&data, &_resolved_cols);
  %end;

  %_select_emit_data(cols=&_resolved_cols, data=&data, out=&out, as_view=&_as_view);

  %if &syserr > 4 %then %_abort(select() failed (SYSERR=&syserr).);
%mend;

%macro test_select;
  %_pipr_require_assert;

  %test_suite(Testing select);
    %test_case(select keeps columns);
      data work._sel;
        length a b c 8;
        a=1; b=2; c=3; output;
      run;

      %select(a c, data=work._sel, out=work._sel_ac);

      proc sql noprint;
        select count(*) into :_cnt_cols trimmed
        from sashelp.vcolumn
        where libname="WORK" and memname="_SEL_AC" and upcase(name) in ("A","C");
      quit;

      %assertEqual(&_cnt_cols., 2);
    %test_summary;

    %test_case(select helper view);
      %_select_emit_data(cols=a c, data=work._sel, out=work._sel_view, as_view=1);
      %assertTrue(%eval(%sysfunc(exist(work._sel_view, view))=1), view created);

      proc sql noprint;
        select count(*) into :_cnt_view trimmed from work._sel_view;
      quit;

      %assertEqual(&_cnt_view., 1);
    %test_summary;

    %test_case(select supports as_view at verb level and validate boolean flags);
      %select(a c, data=work._sel, out=work._sel_v2, validate=YES, as_view=TRUE);
      %assertEqual(%sysfunc(exist(work._sel_v2, view)), 1);
      proc sql noprint;
        select count(*) into :_cnt_view2 trimmed from work._sel_v2;
      quit;
      %assertEqual(&_cnt_view2., 1);
    %test_summary;

    %test_case(select validate=NO with comma-delimited plain columns);
      %select(%str(a, c), data=work._sel, out=work._sel_ac_nv, validate=NO, as_view=0);
      proc sql noprint;
        select upcase(name) into :_sel_nv_cols separated by ' '
        from sashelp.vcolumn
        where libname="WORK" and memname="_SEL_AC_NV"
        order by varnum;
      quit;
      %assertEqual(&_sel_nv_cols., A C);
    %test_summary;

    %test_case(select removes duplicate columns while preserving first-seen order);
      %select(%str(c a c b), data=work._sel, out=work._sel_dedupe, validate=YES, as_view=0);
      proc sql noprint;
        select upcase(name) into :_sel_dedupe_cols separated by ' '
        from sashelp.vcolumn
        where libname="WORK" and memname="_SEL_DEDUPE"
        order by varnum;
      quit;
      %assertEqual(&_sel_dedupe_cols., C A B);
    %test_summary;

    %test_case(select supports selector helpers);
      data work._selx;
        length policy_number 8 policy_type $12 company_numb 8 home_code $6 group_code $6 home_state $2 policy_state $2 misc 8;
        policy_number=1001;
        policy_type='ACTIVE';
        company_numb=44;
        home_code='H01';
        group_code='G01';
        home_state='CA';
        policy_state='NV';
        misc=9;
        output;
      run;

      %select(
        %str(starts_with('policy') company_numb ends_with('code') like('%state%')),
        data=work._selx,
        out=work._selx_out
      );

      proc sql noprint;
        select upcase(name) into :_sel_cols_list separated by ' '
        from sashelp.vcolumn
        where libname="WORK" and memname="_SELX_OUT"
        order by varnum;
      quit;

      %assertEqual(
        &_sel_cols_list.,
        POLICY_NUMBER POLICY_TYPE POLICY_STATE COMPANY_NUMB HOME_CODE GROUP_CODE HOME_STATE
      );

      %select(
        %str(starts_with('policy'), company_numb, ends_with('code')),
        data=work._selx,
        out=work._selx_commas
      );
      proc sql noprint;
        select upcase(name) into :_sel_commas_list separated by ' '
        from sashelp.vcolumn
        where libname="WORK" and memname="_SELX_COMMAS"
        order by varnum;
      quit;

      %assertEqual(
        &_sel_commas_list.,
        POLICY_NUMBER POLICY_TYPE POLICY_STATE COMPANY_NUMB HOME_CODE GROUP_CODE
      );

      %select(%str(contains('state')), data=work._selx, out=work._selx_state);
      proc sql noprint;
        select upcase(name) into :_sel_contains_list separated by ' '
        from sashelp.vcolumn
        where libname="WORK" and memname="_SELX_STATE"
        order by varnum;
      quit;

      %assertEqual(&_sel_contains_list., HOME_STATE POLICY_STATE);

      %select(%str(matches('state$')), data=work._selx, out=work._selx_matches);
      proc sql noprint;
        select upcase(name) into :_sel_matches_list separated by ' '
        from sashelp.vcolumn
        where libname="WORK" and memname="_SELX_MATCHES"
        order by varnum;
      quit;
      %assertEqual(&_sel_matches_list., HOME_STATE POLICY_STATE);

      %select(
        %str(cols_where(lambda(.is_char and prxmatch('/state/i', .name) > 0))),
        data=work._selx,
        out=work._selx_where
      );
      proc sql noprint;
        select upcase(name) into :_sel_where_list separated by ' '
        from sashelp.vcolumn
        where libname="WORK" and memname="_SELX_WHERE"
        order by varnum;
      quit;
      %assertEqual(&_sel_where_list., HOME_STATE POLICY_STATE);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist;
    delete _sel _sel_ac _sel_ac_nv _sel_dedupe _selx _selx_out _selx_commas _selx_state _selx_matches _selx_where;
    delete _sel_view _sel_v2 / memtype=view;
  quit;
%mend test_select;

%_pipr_autorun_tests(test_select);
