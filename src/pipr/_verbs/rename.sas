%macro rename(rename_pairs, data=, out=, validate=1, as_view=0);
  %_assert_ds_exists(&data);
  
  /* Parse rename pairs into old and new variable lists */
  %let old_vars=;
  %let new_vars=;
  %let num_pairs=%sysfunc(countw(&rename_pairs., %str( )));
  
  %do i=1 %to &num_pairs.;
    %let pair=%scan(&rename_pairs., &i., %str( ));
    %let old_var=%scan(&pair., 1, =);
    %let new_var=%scan(&pair., 2, =);
    
    %if &validate %then %do;
      %_assert_cols_exist(&data, &old_var.);
    %end;
    
    %let old_vars=&old_vars. &old_var.;
    %let new_vars=&new_vars. &new_var.;
  %end;

  /* Create rename statement */
  data &out
    %if &as_view %then / view=&out;
  ;
    set &data(rename=(%sysfunc(compbl(&old_vars.))=%sysfunc(compbl(&new_vars.))));
  run;

  %if &syserr > 4 %then %_abort(rename() failed (SYSERR=&syserr).);
%mend;