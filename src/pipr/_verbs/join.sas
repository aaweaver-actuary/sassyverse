%macro hash_for_left_join(obj, right, on=, right_keep=);
  %local i n k;
  %let n=%sysfunc(countw(&on,%str( )));
  
  /* Declare hash object for left join */
  declare hash &obj.(dataset:"&right(keep=&on &right_keep)");

  /* Define key columns for left join */
  %do i=1 %to &n;
    %let k=%scan(&on,&i,%str( ));
    &obj..defineKey("&k");
  %end;

  /* Define data columns for left join */
  %do i=1 %to &n;
    %let k=%scan(&on,&i,%str( ));
    &obj..defineData("&k");
  %end;

  /* Define additional columns to keep from the right dataset */
  %if %length(&right_keep) %then %do;
    %let n=%sysfunc(countw(&right_keep,%str( )));
    %do i=1 %to &n;
      %let k=%scan(&right_keep,&i,%str( ));
      &obj..defineData("&k");
    %end;
  %end;

  &obj..defineDone();

  /* Call missing to suppress warnings for uninitialized variables */
  %let total_cols = %eval(&n + %sysfunc(countw(&right_keep, %str( ))));
    %do i=1 %to &total_cols;
        call missing(
            %if &i <= &n %then %do;
                %let k=%scan(&on,&i,%str( ));
                &k
            %end;
            %else %do;
                %let idx = %eval(&i - &n);
                %let k=%scan(&right_keep,&idx,%str( ));
                &k
            %end;
        );
    %end;
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
    data &out / view=&out;
  %end;
  %else %do;
    data &out;
  %end;
        if _n_=1 then do;
            %hash_for_left_join(h, &right, on=&on, right_keep=&right_keep);
        end;
        
        set &data;
        rc = h.find();
        if rc = 0 then output;
        drop rc;
    run;

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
        input id x;
        datalines;
1 10
2 20
;
      run;

      data work._lj_right;
        input id r1 r2;
        datalines;
1 100 300
2 200 400
;
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
  %test_summary;

  proc datasets lib=work nolist; delete _lj_left _lj_right _lj_out; quit;
%mend test_left_join;

%test_left_join;

