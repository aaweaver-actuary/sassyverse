/* Split a dataset reference into library and member components */
%macro _ds_split(ds, out_lib, out_mem);
  %local _lib _mem;
  %if %index(&ds, .) > 0 %then %do;
    %let _lib=%upcase(%scan(&ds, 1, .));
    %let _mem=%upcase(%scan(&ds, 2, .));
  %end;
  %else %do;
    %let _lib=WORK;
    %let _mem=%upcase(&ds);
  %end;

  %let &out_lib=&_lib;
  %let &out_mem=&_mem;
%mend;

/* Check if a column exists in a dataset. If so, sets the output macro variable to 1, otherwise 0. */
%macro _col_exists(ds, col, out_exists);
  %local lib mem _cnt;
  %global &out_exists;
  %_ds_split(&ds, lib, mem);

  proc sql noprint;
    select count(*)
      into :_cnt trimmed
    from sashelp.vcolumn
    where libname="&lib"
      and memname="&mem"
      and upcase(name)=upcase("&col");
  quit;

  %let &out_exists=%sysfunc(ifc(&_cnt > 0, 1, 0));
%mend;

%macro _cols_missing(ds, cols, out_missing);
  %local i n col missing;
  %global &out_missing;

  %let n=%sysfunc(countw(&cols, %str( )));
  %if &n=0 %then %do;
    %let &out_missing=;
    %return;
  %end;

  %let missing=;
  %do i=1 %to &n;
    %let col=%upcase(%scan(&cols, &i, %str( )));
    %_col_exists(&ds, &col, _exists);
    %if &_exists = 0 %then %let missing=&missing &col;
  %end;

  %let &out_missing=%sysfunc(compbl(%superq(missing)));
%mend;

%macro _assert_ds_exists(ds, error_msg=);
  %local _ds_exists _view_exists;
  %let _ds_exists=%sysfunc(exist(%superq(ds)));
  %let _view_exists=%sysfunc(exist(%superq(ds), view));
  %if (&_ds_exists = 0) and (&_view_exists = 0) %then %do;
    %_abort(Dataset or view does not exist: &ds. &error_msg);
  %end;
%mend;

%macro _assert_cols_exist(ds, cols, error_msg=);
  %_cols_missing(&ds, &cols, missing);
  %if %length(%superq(missing)) %then %do;
    %_abort(Missing required columns in &ds: %superq(missing). &error_msg);
  %end;
%mend;

%macro _get_col_attr(ds, col, out_type, out_len);
  %local lib mem;
  %_ds_split(&ds, lib, mem);

  %global &out_type &out_len;

  proc sql noprint;
    select type, length into :&out_type trimmed, :&out_len trimmed
    from sashelp.vcolumn
    where libname="&lib" and memname="&mem" and upcase(name)=upcase("&col");
  quit;

  %if %length(&&&out_type)=0 %then %_abort(Could not read type/length for &ds..&col);
%mend;

%macro _assert_by_vars(ds, by_list);
  %local cleaned vars;
  %_clean_by_list(&by_list, cleaned);
  %_by_vars_from_list(&cleaned, vars);

  %if %length(%superq(vars))=0 %then %_abort(arrange() requires a non-empty BY list.);
  %_assert_cols_exist(&ds, &vars);
%mend;

%macro _clean_by_list(by_list, out_clean);
  %global &out_clean;
  %let &out_clean=%sysfunc(prxchange(s/\bdescending\b//i, -1, &by_list));
  %let &out_clean=%sysfunc(compbl(%superq(&out_clean)));
%mend;

%macro _by_vars_from_list(cleaned, out_vars);
  %local n i tok vars;
  %global &out_vars;
  %let n=%sysfunc(countw(%superq(cleaned), %str( )));

  %let vars=;
  %do i=1 %to &n;
    %let tok=%scan(%superq(cleaned), &i, %str( ));
    %let vars=&vars &tok;
  %end;

  %let &out_vars=%sysfunc(compbl(%superq(vars)));
%mend;

%macro _assert_key_compatible(left, right, keys, strict_char_len=0);
  %local i n k;
  %let n=%sysfunc(countw(&keys, %str( )));
  %if &n=0 %then %_abort(keys= is required for join validation);

  %do i=1 %to &n;
    %let k=%scan(&keys, &i, %str( ));
    %_assert_cols_exist(&left, &k);
    %_assert_cols_exist(&right, &k);

    %_key_attr_mismatch(&left, &right, &k, lt, ll, rt, rl, type_mismatch, len_mismatch);

    %if &type_mismatch %then %do;
      %_abort(Join key type mismatch for &k: &left=&lt vs &right=&rt);
    %end;

    %if &len_mismatch %then %do;
      %if &strict_char_len %then %_abort(Join key length mismatch for &k: &left=&ll vs &right=&rl);
      %else %put WARNING: Join key length differs for &k: &left=&ll vs &right=&rl. Standardize if needed.;
    %end;
  %end;
%mend;

%macro _key_attr_mismatch(left, right, key, out_lt, out_ll, out_rt, out_rl, out_type_mismatch, out_len_mismatch);
  %global &out_lt &out_ll &out_rt &out_rl &out_type_mismatch &out_len_mismatch;

  %_get_col_attr(&left,  &key, &out_lt, &out_ll);
  %_get_col_attr(&right, &key, &out_rt, &out_rl);

  %if %upcase(&&&out_lt) ne %upcase(&&&out_rt) %then %let &out_type_mismatch=1;
  %else %let &out_type_mismatch=0;

  %if %upcase(&&&out_lt)=CHAR and (&&&out_ll ne &&&out_rl) %then %let &out_len_mismatch=1;
  %else %let &out_len_mismatch=0;
%mend;

%macro _pipr_tmpds(prefix=_p);
  %if %sysmacexist(_tmpds) %then %_tmpds(prefix=&prefix);
  %else %sysfunc(cats(work., &prefix., %sysfunc(putn(%sysfunc(datetime()), hex16.))));
%mend;

%macro _assert_unique_key(ds, keys);
  %local dup_rows _dupchk;
  %let _dupchk=%_pipr_tmpds(prefix=_dupchk_);
  proc sql noprint;
    create table &_dupchk as
    select &keys, count(*) as _n
    from &ds
    group by &keys
    having calculated _n > 1;
    select count(*) into :dup_rows trimmed from &_dupchk;
  quit;

  %if &dup_rows > 0 %then %do;
    %_abort(Duplicate keys detected in &ds for (&keys). Hash join would be ambiguous.);
  %end;

  proc datasets lib=work nolist; delete %scan(&_dupchk, 2, .); quit;
%mend;

%macro test_pipr_validation;
  %_pipr_require_assert;
  %global _exists _missing;
  %global _cleaned _vars _lt _ll _rt _rl _type_mis _len_mis;

  %test_suite(Testing pipr validation);
    %test_case(assert_cols_exist and get_col_attr);
      data work._pv_left;
        length id 8 name $10;
        id=1; name='a'; output;
      run;

      %global _type _len;
      %_assert_cols_exist(work._pv_left, id name);
      %_get_col_attr(work._pv_left, name, _type, _len);
      %assertEqual(%upcase(&_type.), CHAR);
      %assertEqual(&_len., 10);
    %test_summary;

    %test_case(column helpers);
      %_col_exists(work._pv_left, id, _exists);
      %assertEqual(&_exists., 1);
      %_col_exists(work._pv_left, no_such_col, _exists);
      %assertEqual(&_exists., 0);

      %_cols_missing(work._pv_left, id name no_such_col, _missing);
      %assertEqual(&_missing., NO_SUCH_COL);
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

    %test_case(assert_ds_exists accepts views as pipeline inputs);
      data work._pv_src;
        x=1; output;
      run;
      data work._pv_view / view=work._pv_view;
        set work._pv_src;
      run;

      %_assert_ds_exists(work._pv_src);
      %_assert_ds_exists(work._pv_view);
      %assertEqual(%sysfunc(exist(work._pv_view, view)), 1);
    %test_summary;

    %test_case(assert_unique_key does not clobber user work._dupchk);
      data work._dupchk;
        marker=42;
        output;
      run;

      %_assert_unique_key(work._pv_right, id);

      proc sql noprint;
        select count(*) into :_dupchk_exists trimmed
        from sashelp.vtable
        where libname="WORK" and memname="_DUPCHK";
        select sum(marker) into :_dupchk_marker trimmed from work._dupchk;
      quit;

      %assertEqual(&_dupchk_exists., 1);
      %assertEqual(&_dupchk_marker., 42);
    %test_summary;

    %test_case(by-list and key helpers);
      %_clean_by_list(%str(descending id name), _cleaned);
      %_by_vars_from_list(&_cleaned, _vars);
      %assertEqual(&_vars., id name);

      data work._pv_left2;
        length id $4;
        id='a'; output;
      run;
      data work._pv_right2;
        length id $8;
        id='b'; output;
      run;

      %_key_attr_mismatch(work._pv_left2, work._pv_right2, id, _lt, _ll, _rt, _rl, _type_mis, _len_mis);
      %assertEqual(&_type_mis., 0);
      %assertEqual(&_len_mis., 1);
    %test_summary;

    %test_case(ds split and by-vars assertion helpers);
      %_ds_split(work._pv_left, _pv_lib1, _pv_mem1);
      %assertEqual(&_pv_lib1., WORK);
      %assertEqual(&_pv_mem1., _PV_LEFT);

      %_ds_split(_pv_left, _pv_lib2, _pv_mem2);
      %assertEqual(&_pv_lib2., WORK);
      %assertEqual(&_pv_mem2., _PV_LEFT);

      %_assert_by_vars(work._pv_left, %str(descending id));
      %assertTrue(1, by vars assertion accepts descending syntax);
    %test_summary;

    %test_case(tmpds helper returns a WORK dataset name);
      %let _pv_tmp=%_pipr_tmpds(prefix=_pv_);
      %assertTrue(%eval(%index(%upcase(&_pv_tmp.), WORK._PV_) = 1), tmpds helper returns WORK-prefixed name);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist;
    delete _pv_left _pv_right _pv_left2 _pv_right2 _dupchk _pv_src;
    delete _pv_view / memtype=view;
  quit;
%mend test_pipr_validation;

%_pipr_autorun_tests(test_pipr_validation);
