%macro _rename_parse_pairs(rename_pairs, out_old, out_map);
  %local i pair old_var new_var num_pairs old_list map;
  %global &out_old &out_map;

  %let old_list=;
  %let map=;
  %let num_pairs=%sysfunc(countw(%superq(rename_pairs), %str( ), q));
  %if &num_pairs = 0 %then %_abort(rename() requires rename_pairs=);

  %do i=1 %to &num_pairs.;
    %let pair=%scan(%superq(rename_pairs), &i., %str( ), q);
    %let old_var=%scan(%superq(pair), 1, =, q);
    %let new_var=%scan(%superq(pair), 2, =, q);

    %if %length(%superq(old_var))=0 or %length(%superq(new_var))=0 %then %do;
      %_abort(rename() requires pairs in old=new form. Bad token: %superq(pair).);
    %end;

    %let old_list=&old_list %superq(old_var);
    %let map=&map %superq(old_var)=%superq(new_var);
  %end;

  %let old_list=%sysfunc(compbl(&old_list));
  %let map=%sysfunc(compbl(&map));
  %let &out_old=&old_list;
  %let &out_map=&map;
%mend;

%macro _rename_emit_data(rename_map, data=, out=, as_view=0);
  data &out
    %if &as_view %then / view=&out;
  ;
    set &data(rename=(&rename_map));
  run;
%mend;

%macro rename(rename_pairs, data=, out=, validate=1, as_view=0);
  %_assert_ds_exists(&data);

  %_rename_parse_pairs(&rename_pairs., _rn_old, _rn_map);
  %if &validate %then %_assert_cols_exist(&data, &&_rn_old);

  %_rename_emit_data(rename_map=&&_rn_map, data=&data, out=&out, as_view=&as_view);

  %if &syserr > 4 %then %_abort(rename() failed (SYSERR=&syserr).);
%mend;

%macro test_rename;
  %sbmod(assert);

  %test_suite(Testing rename);
    %test_case(rename changes column names);
      data work._ren;
        length a b 8;
        a=1; b=2; output;
      run;

      %rename(rename_pairs=a=x, data=work._ren, out=work._ren2);

      proc sql noprint;
        select count(*) into :_cnt_x trimmed
        from sashelp.vcolumn
        where libname="WORK" and memname="_REN2" and upcase(name)="X";
      quit;

      %assertEqual(&_cnt_x., 1);
    %test_summary;

    %test_case(rename helper parse);
      %_rename_parse_pairs(%str(a=x b=y), _rp_old, _rp_map);
      %assertEqual(&_rp_old., a b);
      %assertEqual(&_rp_map., a=x b=y);
    %test_summary;

    %test_case(rename helper view);
      %_rename_emit_data(rename_map=a=x, data=work._ren, out=work._ren_view, as_view=1);
      %assertTrue(%eval(%sysfunc(exist(work._ren_view, view))=1), view created);
      proc sql noprint;
        select count(*) into :_cnt_view trimmed from work._ren_view;
      quit;
      %assertEqual(&_cnt_view., 1);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _ren _ren2 _ren_view; quit;
%mend test_rename;

%test_rename;