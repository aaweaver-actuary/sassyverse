%macro _left_join_call_missing(on=, right_keep=);
  %local i total_cols n_keys n_keep k idx;

  %let n_keys=%sysfunc(countw(%superq(on), %str( ), q));
  %if %length(%superq(right_keep)) %then %let n_keep=%sysfunc(countw(%superq(right_keep), %str( ), q));
  %else %let n_keep=0;

  %let total_cols = %eval(&n_keys + &n_keep);

  %do i=1 %to &total_cols;
    call missing(
      %if &i <= &n_keys %then %do;
        %let k=%scan(%superq(on), &i, %str( ), q);
        &k
      %end;
      %else %do;
        %let idx = %eval(&i - &n_keys);
        %let k=%scan(%superq(right_keep), &idx, %str( ), q);
        &k
      %end;
    );
  %end;
%mend;

%macro _left_join_hash(obj, right, on=, right_keep=);
  %local i n_keys n_keep k;

  %let n_keys=%sysfunc(countw(%superq(on), %str( ), q));
  %if %length(%superq(right_keep)) %then %let n_keep=%sysfunc(countw(%superq(right_keep), %str( ), q));
  %else %let n_keep=0;
  
  declare hash &obj.(dataset:"&right(keep=&on &right_keep)");

  %do i=1 %to &n_keys;
    %let k=%scan(%superq(on), &i, %str( ), q);
    &obj..defineKey("&k");
    &obj..defineData("&k");
  %end;

  %do i=1 %to &n_keep;
    %let k=%scan(%superq(right_keep), &i, %str( ), q);
    &obj..defineData("&k");
  %end;

  &obj..defineDone();
  %_left_join_call_missing(on=&on, right_keep=&right_keep);
%mend;

%macro _left_join_emit_data(obj, right, on=, data=, out=, right_keep=, as_view=0);
  %if &as_view %then %do;
    data &out / view=&out;
  %end;
  %else %do;
    data &out;
  %end;
      if _n_=1 then do;
        %_left_join_hash(&obj, &right, on=&on, right_keep=&right_keep);
      end;
      
      set &data;
      rc = &obj..find();
      if rc = 0 then output;
      drop rc;
    run;
%mend;

%macro left_join_with_hash(
    right,
    on=, 
    data=, 
    out=, 
    right_keep=,
    validate=1, 
    require_unique=1, 
    strict_char_len=0, 
    as_view=0,
    error_msg=left_join() failed due to invalid input parameters
);
  %_assert_ds_exists(&data);
  %_assert_ds_exists(&right);
  %if %length(&on)=0 %then %_abort(&error_msg.);

  %if &validate %then %do;
    %_assert_key_compatible(&data, &right, &on, strict_char_len=&strict_char_len);
    %if %length(&right_keep) %then %_assert_cols_exist(&right, &right_keep);
    %if &require_unique %then %_assert_unique_key(&right, &on);
  %end;

  %if &as_view %then %do;
    %_left_join_emit_data(obj=h, right=&right, on=&on, data=&data, out=&out, right_keep=&right_keep, as_view=1);
  %end;
  %else %do;
    %_left_join_emit_data(obj=h, right=&right, on=&on, data=&data, out=&out, right_keep=&right_keep, as_view=0);
  %end;

  %if &syserr > 4 %then %_abort(&error_msg.);
%mend;

%macro left_join(
    right,
    on=, 
    data=, 
    out=, 
    right_keep=,
    validate=1, 
    require_unique=1, 
    strict_char_len=0, 
    as_view=0,
    error_msg=left_join() failed due to invalid input parameters
);
  %left_join_with_hash(
      right=&right,
      on=&on,
      data=&data,
      out=&out,
      right_keep=&right_keep,
      validate=&validate,
      require_unique=&require_unique,
      strict_char_len=&strict_char_len,
      as_view=&as_view,
      error_msg=&error_msg
  );
%mend;

%macro test_left_join;
  %sbmod(assert);

  %test_suite(Testing left_join);
    %test_case(left_join brings right_keep columns);
      data work._lj_left;
        id=1; x=10; output;
        id=2; x=20; output;
      run;

      data work._lj_right;
        id=1; r1=100; r2=300; output;
        id=2; r1=200; r2=400; output;
      run;

      %left_join(
        right=work._lj_right,
        on=id,
        data=work._lj_left,
        out=work._lj_out,
        right_keep=r1
      );

      proc sql noprint;
        select sum(r1) into :_sum_r1 trimmed from work._lj_out;
        select count(*) into :_cnt_r2 trimmed
        from sashelp.vcolumn
        where libname="WORK" and memname="_LJ_OUT" and upcase(name)="R2";
      quit;

      %assertEqual(&_sum_r1., 300);
      %assertEqual(&_cnt_r2., 0);
    %test_summary;

    %test_case(left_join view helper);
      %_left_join_emit_data(obj=h, right=work._lj_right, on=id, data=work._lj_left, out=work._lj_view, right_keep=r1, as_view=1);
      %assertTrue(%eval(%sysfunc(exist(work._lj_view, view))=1), view created);
      proc sql noprint;
        select sum(r1) into :_sum_r1_view trimmed from work._lj_view;
      quit;
      %assertEqual(&_sum_r1_view., 300);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _lj_left _lj_right _lj_out _lj_view; quit;
%mend test_left_join;

%test_left_join;

