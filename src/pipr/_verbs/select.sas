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
  %_assert_ds_exists(&data);
  %if &validate %then %_assert_cols_exist(&data, &cols);

  %_select_emit_data(cols=&cols, data=&data, out=&out, as_view=&as_view);

  %if &syserr > 4 %then %_abort(select() failed (SYSERR=&syserr).);
%mend;

%macro test_select;
  %sbmod(assert);

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
  %test_summary;

  proc datasets lib=work nolist; delete _sel _sel_ac _sel_view; quit;
%mend test_select;

%test_select;