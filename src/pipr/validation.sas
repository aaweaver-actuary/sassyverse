%macro _ds_split(ds, out_lib, out_mem);
  %local lib mem;
  %if %index(&ds, .) > 0 %then %do;
    %let lib=%upcase(%scan(&ds, 1, .));
    %let mem=%upcase(%scan(&ds, 2, .));
  %end;
  %else %do;
    %let lib=WORK;
    %let mem=%upcase(&ds);
  %end;

  %let &out_lib=&lib;
  %let &out_mem=&mem;
%mend;

%macro _assert_ds_exists(ds, error_msg=);
  %if not %sysfunc(exist(&ds)) %then %do;
    %_abort(Dataset does not exist: &ds. &error_msg);
  %end;
%mend;

%macro _assert_cols_exist(ds, cols, error_msg=);
  %local lib mem i n col missing _cnt;
  %_ds_split(&ds, lib, mem);

  %let n=%sysfunc(countw(&cols, %str( )));
  %if &n=0 %then %return;

  %let missing=;

  %do i=1 %to &n;
    %let col=%upcase(%scan(&cols, &i, %str( )));

    proc sql noprint;
      select count(*) 
        into :_cnt trimmed
      from sashelp.vcolumn
      where libname="&lib" 
        and memname="&mem" 
        and upcase(name)="&col";
    quit;

    %if &_cnt = 0 %then %let missing=&missing &col;
  %end;

  %if %length(%sysfunc(compbl(&missing))) %then %do;
    %_abort(Missing required columns in &ds: %sysfunc(compbl(&missing)). &error_msg);
  %end;
%mend;

%macro _get_col_attr(ds, col, out_type, out_len);
  %local lib mem;
  %_ds_split(&ds, lib, mem);

  proc sql noprint;
    select type, length into :&out_type trimmed, :&out_len trimmed
    from sashelp.vcolumn
    where libname="&lib" and memname="&mem" and upcase(name)=upcase("&col");
  quit;

  %if %length(&&&out_type)=0 %then %_abort(Could not read type/length for &ds..&col);
%mend;

%macro _assert_by_vars(ds, by_list);
  %local cleaned vars i n tok;
  %let cleaned=%sysfunc(prxchange(s/\bdescending\b//i, -1, &by_list));
  %let cleaned=%sysfunc(compbl(&cleaned));
  %let n=%sysfunc(countw(&cleaned, %str( )));

  %let vars=;
  %do i=1 %to &n;
    %let tok=%scan(&cleaned, &i, %str( ));
    %let vars=&vars &tok;
  %end;

  %if %length(&vars)=0 %then %_abort(arrange() requires a non-empty BY list.);
  %_assert_cols_exist(&ds, &vars);
%mend;

%macro _assert_key_compatible(left, right, keys, strict_char_len=0);
  %local i n k lt ll rt rl;
  %let n=%sysfunc(countw(&keys, %str( )));
  %if &n=0 %then %_abort(keys= is required for join validation);

  %do i=1 %to &n;
    %let k=%scan(&keys, &i, %str( ));
    %_assert_cols_exist(&left, &k);
    %_assert_cols_exist(&right, &k);

    %_get_col_attr(&left,  &k, lt, ll);
    %_get_col_attr(&right, &k, rt, rl);

    %if %upcase(&lt) ne %upcase(&rt) %then %do;
      %_abort(Join key type mismatch for &k: &left=&lt vs &right=&rt);
    %end;

    %if %upcase(&lt)=CHAR and (&ll ne &rl) %then %do;
      %if &strict_char_len %then %_abort(Join key length mismatch for &k: &left=&ll vs &right=&rl);
      %else %put WARNING: Join key length differs for &k: &left=&ll vs &right=&rl. Standardize if needed.;
    %end;
  %end;
%mend;

%macro _assert_unique_key(ds, keys);
  %local dup_rows;
  proc sql noprint;
    create table work._dupchk as
    select &keys, count(*) as _n
    from &ds
    group by &keys
    having calculated _n > 1;
    select count(*) into :dup_rows trimmed from work._dupchk;
  quit;

  %if &dup_rows > 0 %then %do;
    %_abort(Duplicate keys detected in &ds for (&keys). Hash join would be ambiguous.);
  %end;

  proc datasets lib=work nolist; delete _dupchk; quit;
%mend;

%macro test_pipr_validation;
  %sbmod(assert);

  %test_suite(Testing pipr validation);
    %test_case(assert_cols_exist and get_col_attr);
      data work._pv_left;
        length id 8 name $10;
        id=1; name='a'; output;
      run;

      %_assert_cols_exist(work._pv_left, id name);
      %_get_col_attr(work._pv_left, name, _type, _len);
      %assertEqual(&_type., CHAR);
      %assertEqual(&_len., 10);
    %test_summary;

    %test_case(assert_key_compatible and unique_key);
      data work._pv_right;
        length id 8 name $10;
        id=1; name='b'; output;
      run;

      %_assert_key_compatible(work._pv_left, work._pv_right, id);
      %_assert_unique_key(work._pv_right, id);
      %assertTrue(1, validation passes for compatible keys);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _pv_left _pv_right; quit;
%mend test_pipr_validation;

%test_pipr_validation;
