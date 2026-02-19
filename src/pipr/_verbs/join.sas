/* MODULE DOC
File: src/pipr/_verbs/join.sas

1) Purpose in overall project
- Pipr verb implementations for table transformation steps (select/filter/mutate/join/etc.).

2) High-level approach
- Each verb macro normalizes inputs, validates required datasets/columns, and emits a DATA step/PROC implementation.

3) Code organization and why this scheme was chosen
- One file per verb keeps behavior isolated; shared helpers (validation/utils) prevent repeated parsing/dispatch logic.
- Code is organized as helper macros first, public API second, and tests/autorun guards last to reduce contributor onboarding time and import risk.

4) Detailed pseudocode algorithm
- Parse verb arguments (including parmbuff positional/named forms where supported).
- Validate source dataset and required columns when validate=1.
- Normalize expressions/selectors into executable SAS code.
- Emit DATA/PROC logic to produce output dataset or view.
- Return stable output target name so pipe executor can chain next step.
- Expose alias macros for ergonomic naming compatibility where needed.

5) Acknowledged implementation deficits
- Different verbs use different SAS backends (DATA step, PROC SQL, hash) which increases cognitive load.
- Advanced edge-case validation is still evolving for some argument combinations.
- Contributor docs are still text comments; there is no generated API reference yet.

6) Macros defined in this file
- _join_right_keep_key_overlap
- _join_assert_right_keep_not_keys
- _join_call_missing
- _join_hash_define
- _join_hash_emit
- _join_sql_on_clause
- _join_sql_select_right
- _join_sql_emit
- _ds_is_view
- _ds_nobs_vtable
- _ds_est_row_bytes
- _join_auto_pick_method
- _join_validate
- left_join_hash
- inner_join_hash
- left_join_sql
- inner_join_sql
- left_join
- inner_join
- test_join
- test_join_auto

7) Expected side effects from running/include
- Defines 21 macro(s) in the session macro catalog.
- May create/update GLOBAL macro variable(s): PIPR_JOIN_LAST_METHOD.
- Executes top-level macro call(s) on include: _pipr_autorun_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
- When invoked, macros in this module can create or overwrite WORK datasets/views as part of pipeline operations.
*/
/*==============================================================================
  join.sas - hash + sql join verbs for pipr

  Adds:
    - left_join()        : user-facing, default method=HASH
    - inner_join()       : user-facing, default method=HASH
    - left_join_hash()   : explicit hash left join
    - inner_join_hash()  : explicit hash inner join
    - left_join_sql()    : explicit SQL left join (PROC SQL)
    - inner_join_sql()   : explicit SQL inner join (PROC SQL)

  Intended join shape:
    - many-to-1 lookup joins (right is unique on keys) are the primary target.
    - many-to-many joins (right duplicates on keys) are allowed only if you
      disable require_unique=, but semantics may be surprising (hash uses an
      arbitrary match; SQL multiplies rows).

  NOTE: This file depends on:
    - %_abort
    - %_assert_ds_exists
    - %_assert_cols_exist
    - %_assert_key_compatible
    - %_assert_unique_key
==============================================================================*/

/*-------------------------
  Helpers: list handling
-------------------------*/

/* Abort if right_keep contains any join keys. Duplicate column names in output
   are a common source of brittle downstream failures. */
%macro _join_right_keep_key_overlap(on=, right_keep=, out_has_overlap=, out_key=);
  %local i n k has_overlap overlap_key;
  %if %length(%superq(out_has_overlap)) %then %do;
    %if not %symexist(&out_has_overlap) %then %global &out_has_overlap;
  %end;
  %if %length(%superq(out_key)) %then %do;
    %if not %symexist(&out_key) %then %global &out_key;
  %end;

  %let has_overlap=0;
  %let overlap_key=;
  %if %length(%superq(right_keep))=0 %then %do;
    %let &out_has_overlap=0;
    %let &out_key=;
    %return;
  %end;

  %let n=%sysfunc(countw(%superq(on), %str( ), q));
  %do i=1 %to &n;
    %let k=%scan(%superq(on), &i, %str( ), q);
    %if %sysfunc(indexw(%upcase(%superq(right_keep)), %upcase(&k))) > 0 %then %do;
      %let has_overlap=1;
      %let overlap_key=%superq(k);
      %goto overlap_done;
    %end;
  %end;

%overlap_done:
  %let &out_has_overlap=&has_overlap;
  %let &out_key=&overlap_key;
%mend;

%macro _join_assert_right_keep_not_keys(on=, right_keep=, error_msg=);
  %local _has_overlap _overlap_key;
  %_join_right_keep_key_overlap(
    on=&on,
    right_keep=&right_keep,
    out_has_overlap=_has_overlap,
    out_key=_overlap_key
  );
  %if &_has_overlap %then %do;
    %if %length(%superq(error_msg)) %then %_abort(&error_msg);
    %else %_abort(right_keep must not include join key &_overlap_key);
  %end;
%mend;

/* Per-row reset of right-side vars (prevents value bleed on non-matches) */
%macro _join_call_missing(varlist=);
  %local i n v;
  %let n=%sysfunc(countw(%superq(varlist), %str( ), q));
  %do i=1 %to &n;
    %let v=%scan(%superq(varlist), &i, %str( ), q);
    call missing(&v);
  %end;
%mend;


/*-------------------------
  Helpers: HASH join
-------------------------*/

%macro _join_hash_define(obj=h, right=, on=, right_keep=);
  %local i n_keys n_keep k;

  %let n_keys=%sysfunc(countw(%superq(on), %str( ), q));
  %let n_keep=%sysfunc(countw(%superq(right_keep), %str( ), q));

  declare hash &obj(dataset:"&right(keep=&on &right_keep)");

  /* composite keys */
  %do i=1 %to &n_keys;
    %let k=%scan(%superq(on), &i, %str( ), q);
    &obj..defineKey("&k");
  %end;

  /* return keys + requested columns */
  %do i=1 %to &n_keys;
    %let k=%scan(%superq(on), &i, %str( ), q);
    &obj..defineData("&k");
  %end;

  %do i=1 %to &n_keep;
    %let k=%scan(%superq(right_keep), &i, %str( ), q);
    &obj..defineData("&k");
  %end;

  &obj..defineDone();
%mend;

%macro _join_hash_emit(join_type=LEFT, obj=h, right=, on=, data=, out=, right_keep=, as_view=0);
  %local jt _as_view;
  %let jt=%upcase(&join_type);
  %let _as_view=%_pipr_bool(%superq(as_view), default=0);

  %if &_as_view %then %do;
    data &out / view=&out;
  %end;
  %else %do;
    data &out;
  %end;

    /* Compile-time PDV alignment */
    if 0 then set &right(keep=&on &right_keep);

    if _n_ = 1 then do;
      %_join_hash_define(obj=&obj, right=&right, on=&on, right_keep=&right_keep);
    end;

    do until(eof);
      set &data end=eof;

      /* reset right vars each row for correct LEFT join behavior */
      %if %length(%superq(right_keep)) %then %do;
        %_join_call_missing(varlist=&right_keep);
      %end;

      rc = &obj..find();

      %if &jt = LEFT %then %do;
        /* left join: always output */
        output;
      %end;
      %else %if &jt = INNER %then %do;
        /* inner join: only output matches */
        if rc = 0 then output;
      %end;
      %else %do;
        /* defensive */
        stop;
      %end;

    end;

    drop rc;
  run;
%mend;


/*-------------------------
  Helpers: SQL join
-------------------------*/

%macro _join_sql_on_clause(on=, l=l, r=r);
  %local i n k;
  %let n=%sysfunc(countw(%superq(on), %str( ), q));
  %do i=1 %to &n;
    %let k=%scan(%superq(on), &i, %str( ), q);
    %if &i > 1 %then %do; and %end;
    &l..&k = &r..&k
  %end;
%mend;

/* Emits ", r.col1, r.col2" or empty string if right_keep empty */
%macro _join_sql_select_right(right_keep=, r=r);
  %local i n k;
  %let n=%sysfunc(countw(%superq(right_keep), %str( ), q));
  %do i=1 %to &n;
    %let k=%scan(%superq(right_keep), &i, %str( ), q);
    , &r..&k
  %end;
%mend;

%macro _join_sql_emit(join_type=LEFT, right=, on=, data=, out=, right_keep=, as_view=0);
  %local jt create_kw _as_view;
  %let jt=%upcase(&join_type);
  %let _as_view=%_pipr_bool(%superq(as_view), default=0);

  %if &_as_view %then %let create_kw=create view;
  %else %let create_kw=create table;

  proc sql;
    &create_kw &out as
      select
        l.*
        %_join_sql_select_right(right_keep=&right_keep, r=r)
      from &data as l
      %if &jt = LEFT %then %do;
        left join &right as r
      %end;
      %else %if &jt = INNER %then %do;
        inner join &right as r
      %end;
      on %_join_sql_on_clause(on=&on, l=l, r=r)
    ;
  quit;

  %if &sqlrc > 4 %then %_abort(join_sql(&join_type) failed (SQLRC=&sqlrc).);
%mend;

/*-------------------------
  AUTO method selection helpers
-------------------------*/

/* Returns 1 if dataset is a VIEW, else 0 */
%macro _ds_is_view(ds);
  %local lib mem is_view;
  %let is_view=0;

  %_ds_split(&ds, lib, mem);

  proc sql noprint;
    select (upcase(memtype) = "VIEW")
      into :is_view trimmed
    from sashelp.vtable
    where libname="&lib" and memname="&mem";
  quit;

  %sysfunc(ifc(%length(&is_view)=0, 0, &is_view))
%mend;

/* Fast-ish NOBS from SASHELP.VTABLE. Returns blank if unknown (e.g., some views). */
%macro _ds_nobs_vtable(ds, outvar);
  %local lib mem;
  %_ds_split(&ds, lib, mem);

  proc sql noprint;
    select nobs into :&outvar trimmed
    from sashelp.vtable
    where libname="&lib" and memname="&mem";
  quit;
%mend;

/* Estimate bytes per row for the subset of columns used on the RIGHT.
   For hash join memory sizing, we only care about keys + right_keep. */
%macro _ds_est_row_bytes(ds, cols, outvar);
  %local lib mem;
  %_ds_split(&ds, lib, mem);

  /* Sum LENGTH from sashelp.vcolumn; conservative (ignores overhead). */
  proc sql noprint;
    select sum(length) into :&outvar trimmed
    from sashelp.vcolumn
    where libname="&lib"
      and memname="&mem"
      and upcase(name) in (
        %local i n c;
        %let n=%sysfunc(countw(%superq(cols), %str( ), q));
        %do i=1 %to &n;
          %let c=%upcase(%scan(%superq(cols), &i, %str( ), q));
          %if &i>1 %then %do; , %end;
          "&c"
        %end;
      );
  quit;

  %if %length(&&&outvar)=0 %then %let &outvar=;
%mend;

/* Picks HASH vs SQL for lookup-style joins.

   Heuristic intent:
     - Prefer HASH when right is a true table (not a view), unique on keys,
       and estimated hash footprint is small enough.
     - Prefer SQL when right is a view (hash rebuilt each execution),
       or when size estimates are unavailable, or footprint likely large.

   Outputs:
     - sets &out_method to HASH or SQL
     - sets global PIPR_JOIN_LAST_METHOD for testability (optional)

   Parameters:
     auto_max_obs:         max right NOBS to prefer HASH (default 5e6)
     auto_max_mem_mb:      max estimated hash memory in MB to prefer HASH (default 512)
     auto_overhead_factor: multiplier for hash overhead (default 2.5)
     auto_prefer_hash:     1 forces HASH when estimates unavailable (default 0)
*/
%macro _join_auto_pick_method(
  data=,
  right=,
  on=,
  right_keep=,
  require_unique=1,
  as_view=0,
  out_method=,
  auto_max_obs=5000000,
  auto_max_mem_mb=512,
  auto_overhead_factor=2.5,
  auto_prefer_hash=0
);
  %local is_view nobs row_bytes cols mem_est_bytes mem_cap_bytes _require_unique _auto_prefer_hash;
  %let _require_unique=%_pipr_bool(%superq(require_unique), default=1);
  %let _auto_prefer_hash=%_pipr_bool(%superq(auto_prefer_hash), default=0);

  %if %length(&out_method)=0 %then %_abort(_join_auto_pick_method requires out_method=);

  /* If the caller wants strict lookup semantics, uniqueness is already enforced in validation.
     If require_unique=0, AUTO should generally avoid HASH because semantics diverge:
       - HASH: first match wins
       - SQL: multiplies rows
     So default to SQL unless user explicitly asks for HASH. */
  %if &_require_unique = 0 %then %do;
    %let &out_method=SQL;
    %global PIPR_JOIN_LAST_METHOD;
    %let PIPR_JOIN_LAST_METHOD=SQL;
    %return;
  %end;

  %let is_view=%_ds_is_view(&right);

  /* If right is a view, hash will be rebuilt every time the stream executes (especially painful in view pipelines).
     Prefer SQL (and possibly create view) in that case. */
  %if &is_view %then %do;
    %let &out_method=SQL;
    %global PIPR_JOIN_LAST_METHOD;
    %let PIPR_JOIN_LAST_METHOD=SQL;
    %return;
  %end;

  /* Try to get right NOBS cheaply */
  %_ds_nobs_vtable(&right, nobs);

  /* If NOBS unknown and auto_prefer_hash=0, choose SQL conservatively. */
  %if %length(&nobs)=0 %then %do;
    %if &_auto_prefer_hash %then %do;
      %let &out_method=HASH;
    %end;
    %else %do;
      %let &out_method=SQL;
    %end;
    %global PIPR_JOIN_LAST_METHOD;
    %let PIPR_JOIN_LAST_METHOD=&&&out_method;
    %return;
  %end;

  /* Quick NOBS gate */
  %if %sysevalf(&nobs > &auto_max_obs) %then %do;
    %let &out_method=SQL;
    %global PIPR_JOIN_LAST_METHOD;
    %let PIPR_JOIN_LAST_METHOD=SQL;
    %return;
  %end;

  /* Estimate memory footprint: nobs * row_bytes * overhead_factor */
  %let cols=&on &right_keep;
  %_ds_est_row_bytes(&right, &cols, row_bytes);

  %if %length(&row_bytes)=0 %then %do;
    /* no estimate => conservative */
    %if &_auto_prefer_hash %then %let &out_method=HASH;
    %else %let &out_method=SQL;

    %global PIPR_JOIN_LAST_METHOD;
    %let PIPR_JOIN_LAST_METHOD=&&&out_method;
    %return;
  %end;

  %let mem_est_bytes=%sysevalf(&nobs * &row_bytes * &auto_overhead_factor);
  %let mem_cap_bytes=%sysevalf(&auto_max_mem_mb * 1024 * 1024);

  %if %sysevalf(&mem_est_bytes <= &mem_cap_bytes) %then %let &out_method=HASH;
  %else %let &out_method=SQL;

  %global PIPR_JOIN_LAST_METHOD;
  %let PIPR_JOIN_LAST_METHOD=&&&out_method;
%mend;

/*-------------------------
  Validation wrapper (shared)
-------------------------*/

%macro _join_validate(
  data=,
  right=,
  on=,
  right_keep=,
  validate=1,
  require_unique=1,
  strict_char_len=0,
  error_msg=
);
  %local _validate _require_unique;
  %let _validate=%_pipr_bool(%superq(validate), default=1);
  %let _require_unique=%_pipr_bool(%superq(require_unique), default=1);
  %_assert_ds_exists(&data);
  %_assert_ds_exists(&right);

  %if %length(%superq(on))=0 %then %do;
    %if %length(%superq(error_msg)) %then %_abort(&error_msg);
    %else %_abort(join requires on=);
  %end;

  %if &_validate %then %do;
    %_assert_key_compatible(&data, &right, &on, strict_char_len=&strict_char_len);
    %if %length(%superq(right_keep)) %then %_assert_cols_exist(&right, &right_keep);
  %end;

  %_join_assert_right_keep_not_keys(on=&on, right_keep=&right_keep);

  /* For HASH joins, uniqueness is strongly recommended; for SQL joins, this is optional
     but provided for consistency and to prevent accidental row multiplication. */
  %if &_require_unique %then %do;
    %_assert_unique_key(&right, &on);
  %end;
%mend;


/*==============================================================================
  Public verbs: HASH
==============================================================================*/

%macro left_join_hash(
  right,
  on=,
  data=,
  out=,
  right_keep=,
  validate=1,
  require_unique=1,
  strict_char_len=0,
  as_view=0,
  error_msg=left_join_hash() failed due to invalid input parameters
);
  %_join_validate(
    data=&data,
    right=&right,
    on=&on,
    right_keep=&right_keep,
    validate=&validate,
    require_unique=&require_unique,
    strict_char_len=&strict_char_len,
    error_msg=&error_msg
  );

  %_join_hash_emit(
    join_type=LEFT,
    obj=h,
    right=&right,
    on=&on,
    data=&data,
    out=&out,
    right_keep=&right_keep,
    as_view=&as_view
  );
%mend;

%macro inner_join_hash(
  right,
  on=,
  data=,
  out=,
  right_keep=,
  validate=1,
  require_unique=1,
  strict_char_len=0,
  as_view=0,
  error_msg=inner_join_hash() failed due to invalid input parameters
);
  %_join_validate(
    data=&data,
    right=&right,
    on=&on,
    right_keep=&right_keep,
    validate=&validate,
    require_unique=&require_unique,
    strict_char_len=&strict_char_len,
    error_msg=&error_msg
  );

  %_join_hash_emit(
    join_type=INNER,
    obj=h,
    right=&right,
    on=&on,
    data=&data,
    out=&out,
    right_keep=&right_keep,
    as_view=&as_view
  );
%mend;


/*==============================================================================
  Public verbs: SQL
==============================================================================*/

%macro left_join_sql(
  right,
  on=,
  data=,
  out=,
  right_keep=,
  validate=1,
  require_unique=0,
  strict_char_len=0,
  as_view=0,
  error_msg=left_join_sql() failed due to invalid input parameters
);
  %_join_validate(
    data=&data,
    right=&right,
    on=&on,
    right_keep=&right_keep,
    validate=&validate,
    require_unique=&require_unique,
    strict_char_len=&strict_char_len,
    error_msg=&error_msg
  );

  %_join_sql_emit(
    join_type=LEFT,
    right=&right,
    on=&on,
    data=&data,
    out=&out,
    right_keep=&right_keep,
    as_view=&as_view
  );
%mend;

%macro inner_join_sql(
  right,
  on=,
  data=,
  out=,
  right_keep=,
  validate=1,
  require_unique=0,
  strict_char_len=0,
  as_view=0,
  error_msg=inner_join_sql() failed due to invalid input parameters
);
  %_join_validate(
    data=&data,
    right=&right,
    on=&on,
    right_keep=&right_keep,
    validate=&validate,
    require_unique=&require_unique,
    strict_char_len=&strict_char_len,
    error_msg=&error_msg
  );

  %_join_sql_emit(
    join_type=INNER,
    right=&right,
    on=&on,
    data=&data,
    out=&out,
    right_keep=&right_keep,
    as_view=&as_view
  );
%mend;


/*==============================================================================
  User-facing verbs: left_join / inner_join (dispatcher)
==============================================================================*/

%macro left_join(
  right,
  on=,
  data=,
  out=,
  right_keep=,
  method=HASH,
  validate=1,
  require_unique=1,
  strict_char_len=0,
  as_view=0,
  /* AUTO tuning knobs (optional) */
  auto_max_obs=5000000,
  auto_max_mem_mb=512,
  auto_overhead_factor=2.5,
  auto_prefer_hash=0,
  error_msg=left_join() failed due to invalid input parameters
);
  %local m picked _require_unique _as_view;
  %let _require_unique=%_pipr_bool(%superq(require_unique), default=1);
  %let _as_view=%_pipr_bool(%superq(as_view), default=0);

  %let m=%upcase(&method);

  %if "%superq(m)" = "AUTO" %then %do;
    %let picked=;
    %_join_auto_pick_method(
      data=&data,
      right=&right,
      on=&on,
      right_keep=&right_keep,
      require_unique=&_require_unique,
      as_view=&_as_view,
      out_method=picked,
      auto_max_obs=&auto_max_obs,
      auto_max_mem_mb=&auto_max_mem_mb,
      auto_overhead_factor=&auto_overhead_factor,
      auto_prefer_hash=&auto_prefer_hash
    );
    %let m=%upcase(&picked);
  %end;

  %if "%superq(m)" = "HASH" %then %do;
    %left_join_hash(&right, on=&on, data=&data, out=&out, right_keep=&right_keep,
      validate=&validate, require_unique=&_require_unique, strict_char_len=&strict_char_len, as_view=&_as_view, error_msg=&error_msg);
  %end;
  %else %if "%superq(m)" = "SQL" %then %do;
    %left_join_sql(&right, on=&on, data=&data, out=&out, right_keep=&right_keep,
      validate=&validate, require_unique=&_require_unique, strict_char_len=&strict_char_len, as_view=&_as_view, error_msg=&error_msg);
  %end;
  %else %do;
    %_abort(left_join(): unknown method=&method (expected HASH, SQL, or AUTO));
  %end;
%mend;


%macro inner_join(
  right,
  on=,
  data=,
  out=,
  right_keep=,
  method=HASH,
  validate=1,
  require_unique=1,
  strict_char_len=0,
  as_view=0,
  /* AUTO tuning knobs (optional) */
  auto_max_obs=5000000,
  auto_max_mem_mb=512,
  auto_overhead_factor=2.5,
  auto_prefer_hash=0,
  error_msg=inner_join() failed due to invalid input parameters
);
  %local m picked _require_unique _as_view;
  %let _require_unique=%_pipr_bool(%superq(require_unique), default=1);
  %let _as_view=%_pipr_bool(%superq(as_view), default=0);

  %let m=%upcase(&method);

  %if "%superq(m)" = "AUTO" %then %do;
    %let picked=;
    %_join_auto_pick_method(
      data=&data,
      right=&right,
      on=&on,
      right_keep=&right_keep,
      require_unique=&_require_unique,
      as_view=&_as_view,
      out_method=picked,
      auto_max_obs=&auto_max_obs,
      auto_max_mem_mb=&auto_max_mem_mb,
      auto_overhead_factor=&auto_overhead_factor,
      auto_prefer_hash=&auto_prefer_hash
    );
    %let m=%upcase(&picked);
  %end;

  %if "%superq(m)" = "HASH" %then %do;
    %inner_join_hash(&right, on=&on, data=&data, out=&out, right_keep=&right_keep,
      validate=&validate, require_unique=&_require_unique, strict_char_len=&strict_char_len, as_view=&_as_view, error_msg=&error_msg);
  %end;
  %else %if "%superq(m)" = "SQL" %then %do;
    %inner_join_sql(&right, on=&on, data=&data, out=&out, right_keep=&right_keep,
      validate=&validate, require_unique=&_require_unique, strict_char_len=&strict_char_len, as_view=&_as_view, error_msg=&error_msg);
  %end;
  %else %do;
    %_abort(inner_join(): unknown method=&method (expected HASH, SQL, or AUTO));
  %end;
%mend;

/*==============================================================================
  Unit tests (style consistent with your repo: testthat-like macros)
==============================================================================*/

%macro test_join();
  %_pipr_require_assert;
  %test_suite(join);

  /*-----------------------
    Base fixtures
  -----------------------*/
  data work._j_left;
    input id x;
    datalines;
1 10
2 20
2 21
3 30
;
  run;

  data work._j_right;
    input id r1;
    datalines;
1 100
3 300
;
  run;

  /*-----------------------
    Hash LEFT: preserves rowcount + missing for non-matches
  -----------------------*/
  %test_case(left_join_hash preserves left rowcount and missing);
    %left_join_hash(work._j_right, on=id, data=work._j_left, out=work._j_lh, right_keep=r1, require_unique=1);

    proc sql noprint;
      select count(*) into :_n_lh trimmed from work._j_lh;
      select sum(missing(r1)) into :_miss_lh trimmed from work._j_lh where id=2;
      select sum(r1) into :_sum_lh trimmed from work._j_lh;
    quit;

    %assertEqual(&_n_lh., 4);
    %assertEqual(&_miss_lh., 2);
    /* sum should be 100 + 300 = 400; missing contributes 0 */
    %assertEqual(&_sum_lh., 400);
  %test_summary;

  /*-----------------------
    Hash INNER: drops non-matches
  -----------------------*/
  %test_case(inner_join_hash drops non-matches);
    %inner_join_hash(work._j_right, on=id, data=work._j_left, out=work._j_ih, right_keep=r1, require_unique=1);

    proc sql noprint;
      select count(*) into :_n_ih trimmed from work._j_ih;
      select sum(r1) into :_sum_ih trimmed from work._j_ih;
    quit;

    %assertEqual(&_n_ih., 2);
    %assertEqual(&_sum_ih., 400);
  %test_summary;

  /*-----------------------
    SQL LEFT: preserves rowcount + missing for non-matches
  -----------------------*/
  %test_case(left_join_sql preserves left rowcount and missing);
    %left_join_sql(work._j_right, on=id, data=work._j_left, out=work._j_ls, right_keep=r1);

    proc sql noprint;
      select count(*) into :_n_ls trimmed from work._j_ls;
      select sum(case when r1 is null then 1 else 0 end) into :_miss_ls trimmed from work._j_ls where id=2;
      select sum(r1) into :_sum_ls trimmed from work._j_ls;
    quit;

    %assertEqual(&_n_ls., 4);
    %assertEqual(&_miss_ls., 2);
    %assertEqual(&_sum_ls., 400);
  %test_summary;

  /*-----------------------
    SQL INNER: drops non-matches
  -----------------------*/
  %test_case(inner_join_sql drops non-matches);
    %inner_join_sql(work._j_right, on=id, data=work._j_left, out=work._j_is, right_keep=r1);

    proc sql noprint;
      select count(*) into :_n_is trimmed from work._j_is;
      select sum(r1) into :_sum_is trimmed from work._j_is;
    quit;

    %assertEqual(&_n_is., 2);
    %assertEqual(&_sum_is., 400);
  %test_summary;

  /*-----------------------
    Guard: right_keep cannot include key
  -----------------------*/
  %test_case(right_keep may not include join key);
    %_join_right_keep_key_overlap(
      on=id,
      right_keep=id r1,
      out_has_overlap=_j_has_overlap,
      out_key=_j_overlap_key
    );
    %assertEqual(&_j_has_overlap., 1);
    %assertEqual(&_j_overlap_key., id);
  %test_summary;

  %test_case(join SQL helper emitters build expected fragments);
    %let _j_on_single=%sysfunc(compbl(%_join_sql_on_clause(on=id, l=l, r=r)));
    %assertTrue(%eval(%index(%superq(_j_on_single), %str(l.id = r.id)) > 0), single-key ON clause emitted);

    %let _j_on_multi=%sysfunc(compbl(%_join_sql_on_clause(on=%str(id grp), l=l, r=r)));
    %assertTrue(%eval(%index(%superq(_j_on_multi), %str(l.id = r.id)) > 0), multi-key ON clause includes first key);
    %assertTrue(%eval(%index(%superq(_j_on_multi), %str(and l.grp = r.grp)) > 0), multi-key ON clause includes second key);

    %let _j_sel_right=%sysfunc(compbl(%_join_sql_select_right(right_keep=%str(r1 r2), r=r)));
    %assertTrue(%eval(%index(%superq(_j_sel_right), %str(r.r1)) > 0), right select includes first keep column);
    %assertTrue(%eval(%index(%superq(_j_sel_right), %str(r.r2)) > 0), right select includes second keep column);
  %test_summary;

  %test_case(dataset/view detector distinguishes memtypes);
    data work._j_view_src;
      id=1;
      output;
    run;
    data work._j_view / view=work._j_view;
      set work._j_view_src;
    run;

    %assertEqual(%_ds_is_view(work._j_view_src), 0);
    %assertEqual(%_ds_is_view(work._j_view), 1);
  %test_summary;

  %test_case(left_join wrapper with method=HASH matches rowcount);
    %left_join(
      work._j_right,
      on=id,
      data=work._j_left,
      out=work._j_lw_hash,
      right_keep=r1,
      method=HASH,
      validate=YES,
      require_unique=1,
      as_view=0
    );

    proc sql noprint;
      select count(*) into :_n_lw_hash trimmed from work._j_lw_hash;
    quit;
    %assertEqual(&_n_lw_hash., 4);
  %test_summary;

  %test_case(left_join wrapper accepts lowercase method values);
    %left_join(
      work._j_right,
      on=id,
      data=work._j_left,
      out=work._j_lw_hash_lc,
      right_keep=r1,
      method=hash,
      validate=YES,
      require_unique=1,
      as_view=0
    );

    proc sql noprint;
      select count(*) into :_n_lw_hash_lc trimmed from work._j_lw_hash_lc;
    quit;
    %assertEqual(&_n_lw_hash_lc., 4);
  %test_summary;

  %test_case(inner_join wrapper with method=SQL matches rows);
    %inner_join(
      work._j_right,
      on=id,
      data=work._j_left,
      out=work._j_iw_sql,
      right_keep=r1,
      method=SQL,
      validate=YES,
      require_unique=0,
      as_view=0
    );

    proc sql noprint;
      select count(*) into :_n_iw_sql trimmed from work._j_iw_sql;
      select sum(r1) into :_sum_iw_sql trimmed from work._j_iw_sql;
    quit;
    %assertEqual(&_n_iw_sql., 2);
    %assertEqual(&_sum_iw_sql., 400);
  %test_summary;

  %test_case(join SQL and HASH support as_view outputs);
    %left_join_sql(
      work._j_right,
      on=id,
      data=work._j_left,
      out=work._j_ls_view,
      right_keep=r1,
      as_view=TRUE
    );
    %assertEqual(%sysfunc(exist(work._j_ls_view, view)), 1);

    %left_join_hash(
      work._j_right,
      on=id,
      data=work._j_left,
      out=work._j_lh_view,
      right_keep=r1,
      require_unique=1,
      as_view=TRUE
    );
    %assertEqual(%sysfunc(exist(work._j_lh_view, view)), 1);

    proc sql noprint;
      select count(*) into :_n_ls_view trimmed from work._j_ls_view;
      select count(*) into :_n_lh_view trimmed from work._j_lh_view;
    quit;
    %assertEqual(&_n_ls_view., 4);
    %assertEqual(&_n_lh_view., 4);
  %test_summary;

  %test_case(inner_join wrapper supports as_view output);
    %inner_join(
      work._j_right,
      on=id,
      data=work._j_left,
      out=work._j_iw_view,
      right_keep=r1,
      method=sql,
      validate=YES,
      require_unique=0,
      as_view=TRUE
    );
    %assertEqual(%sysfunc(exist(work._j_iw_view, view)), 1);
    proc sql noprint;
      select count(*) into :_n_iw_view trimmed from work._j_iw_view;
    quit;
    %assertEqual(&_n_iw_view., 2);
  %test_summary;

  %test_summary; /* suite */

  proc datasets lib=work nolist;
    delete _j_left _j_right _j_lh _j_ih _j_ls _j_is _j_lw_hash _j_lw_hash_lc _j_iw_sql _j_view_src;
    delete _j_ls_view _j_lh_view _j_iw_view _j_view / memtype=view;
  quit;
%mend test_join;


%macro test_join_auto();
  %_pipr_require_assert;
  %test_suite(join_auto);

  data work._a_left;
    input id x;
    datalines;
1 10
2 20
;
  run;

  data work._a_right_small;
    input id r1;
    datalines;
1 100
;
  run;

  /* Force HASH by giving generous thresholds */
  %test_case(auto picks HASH for small right);
    %let PIPR_JOIN_LAST_METHOD=;
    %left_join(work._a_right_small, on=id, data=work._a_left, out=work._a_out1,
      right_keep=r1, method=AUTO, require_unique=1,
      auto_max_obs=1000000, auto_max_mem_mb=512, auto_overhead_factor=2.5, auto_prefer_hash=0);

    %assertEqual(&PIPR_JOIN_LAST_METHOD., HASH);
  %test_summary;

  /* Force SQL by setting obs threshold below right nobs */
  %test_case(auto picks SQL when obs threshold exceeded);
    %let PIPR_JOIN_LAST_METHOD=;
    %left_join(work._a_right_small, on=id, data=work._a_left, out=work._a_out2,
      right_keep=r1, method=AUTO, require_unique=1,
      auto_max_obs=0, auto_max_mem_mb=512, auto_overhead_factor=2.5, auto_prefer_hash=0);

    %assertEqual(&PIPR_JOIN_LAST_METHOD., SQL);
  %test_summary;

  /* Force SQL if require_unique=0 (semantic divergence guard) */
  %test_case(auto defaults to SQL when require_unique=0);
    %let PIPR_JOIN_LAST_METHOD=;
    %left_join(work._a_right_small, on=id, data=work._a_left, out=work._a_out3,
      right_keep=r1, method=AUTO, require_unique=0,
      auto_max_obs=1000000, auto_max_mem_mb=512, auto_overhead_factor=2.5, auto_prefer_hash=1);

    %assertEqual(&PIPR_JOIN_LAST_METHOD., SQL);
  %test_summary;

  %test_case(inner_join AUTO records chosen method);
    %let PIPR_JOIN_LAST_METHOD=;
    %inner_join(work._a_right_small, on=id, data=work._a_left, out=work._a_out4,
      right_keep=r1, method=AUTO, require_unique=1,
      auto_max_obs=1000000, auto_max_mem_mb=512, auto_overhead_factor=2.5, auto_prefer_hash=0);

    %assertEqual(&PIPR_JOIN_LAST_METHOD., HASH);
  %test_summary;

  proc datasets lib=work nolist;
    delete _a_left _a_right_small _a_out1 _a_out2 _a_out3 _a_out4;
  quit;

  %test_summary;
%mend;

%_pipr_autorun_tests(test_join);
%_pipr_autorun_tests(test_join_auto);
