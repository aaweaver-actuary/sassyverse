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

