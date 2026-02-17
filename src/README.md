# Core modules (`src/`)

This folder contains the reusable utility layer that powers sassyverse and pipr.

You can either:

- load everything via `sassyverse_init(...)`, or
- include only the modules you need for focused scripts.

## Loading patterns

### Full project load (recommended)

```sas
%include "S:/small_business/modeling/sassyverse/sassyverse.sas";
%sassyverse_init(base_path=S:/small_business/modeling/sassyverse/src, include_pipr=1, include_tests=0);
```

### Targeted load for a single utility

```sas
%include "S:/small_business/modeling/sassyverse/src/sassymod.sas";
%let _sassyverse_base_path=S:/small_business/modeling/sassyverse/src;

%sbmod(strings);
%sbmod(lists);
```

### Targeted load with import-level predicate diagnostics

Use this when you want debug logs for one module only.

```sas
%include "S:/small_business/modeling/sassyverse/src/sassymod.sas";
%let _sassyverse_base_path=S:/small_business/modeling/sassyverse/src;

%sbmod(pipr/predicates, use_dbg=1);
```

Notes:

- `use_dbg=1` sets `log_level=DEBUG` during this `%sbmod(...)` call.
- At the end of the call, `%sbmod` restores `log_level=INFO`.
- This keeps debugging targeted so other module imports stay quiet.

## Module quick reference

### `assert.sas`

Purpose:

- lightweight test framework for macro-level and data-step assertions

Key macros:

- `assertTrue`, `assertFalse`, `assertEqual`, `assertNotEqual`
- `test_suite`, `test_case`, `test_summary`

Example:

```sas
%test_suite(Smoke checks);
  %test_case(Basic math);
    %assertEqual(2, 2);
    %assertTrue(%eval(5 > 1), 5 is greater than 1);
  %test_summary;
%test_summary;
```

### `strings.sas`

Purpose:

- string manipulation in macro code

Common tasks:

- split/parsing: `str__split`
- find/replace: `str__find`, `str__replace`
- formatting: `str__format`

Example:

```sas
%let name=policy_state;
%put %str__upper(&name);          /* POLICY_STATE */
%put %str__replace(&name, _, -);  /* policy-state */
```

### `lists.sas`

Purpose:

- list-like operations in macro language

Common tasks:

- counting and indexing: `len`, `nth`, `first`, `last`
- deduplication/sorting: `unique`, `sorted`
- iteration: `foreach`

Example:

```sas
%let cols=policy_id policy_state policy_id;
%let unique_cols=%unique(&cols);
%put &=unique_cols;  /* policy_id policy_state */
```

### `dates.sas`

Purpose:

- macro wrappers for date extraction and formatting

Example:

```sas
%let dt='16FEB2026'd;
%put Year=%year(&dt) Month=%month(&dt) Day=%day(&dt);
```

### `n_rows.sas`

Purpose:

- fast count of observations in a dataset

Example:

```sas
%let row_count=%n_rows(work.my_ds);
%put &=row_count;
```

### `round_to.sas`

Purpose:

- consistent numeric rounding helper

Example:

```sas
%let x=%roundto(3.14159, 2);
%put &=x;  /* 3.14 */
```

### `shell.sas`

Purpose:

- OS command wrappers with Windows compatibility handling

Common tasks:

- inspect folder contents: `shls`
- create/delete directories: `shmkdir`, `shrm_dir`

Example:

```sas
%let out_dir=%sysfunc(tranwrd(%sysfunc(pathname(work)), \, /));
%shls(dir=&out_dir, show_hidden=0);
```

### `export.sas`

Purpose:

- CSV export wrappers around `PROC EXPORT`

Common tasks:

- one-step export: `export_csv_copy`
- explicit output library path: `export_to_csv`

Example:

```sas
%let out_dir=%sysfunc(tranwrd(%sysfunc(pathname(work)), \, /));
%export_csv_copy(work.my_ds, out_folder=&out_dir);
```

Note:

- `export_csv_copy` lowercases dataset names and replaces `.` with `__` in filenames.
- Example: `work._exp` becomes `work___exp.csv`.

### `hash.sas`

Purpose:

- helper macros for hash object setup in data steps

Common tasks:

- define keys/data once, then `find()`/`add()` in data-step logic

Example:

```sas
/* Most users should prefer pipr left_join(...) unless custom hash logic is needed. */
```

### `index.sas`

Purpose:

- helpers for simple/composite index creation

Example:

```sas
%make_simple_index(ds=policies, col=policy_id, lib=work);
```

### `logging.sas`

Purpose:

- file + console logging helpers

Common tasks:

- quick console output: `console_log`
- leveled logs: `info`, `dbg`

Example:

```sas
%set_log_level(DEBUG);
%dbg(Starting policy feature build);
```

### `testthat.sas`

Purpose:

- additional test helpers (`nobs`, `tt_require_nonempty`, etc.)

## Common workflows for new users

### 1. Include one module for ad hoc utility use

```sas
%include "S:/small_business/modeling/sassyverse/src/strings.sas";
%put %str__lower(HELLO_WORLD);
```

### 2. Build a small reusable test around a macro

```sas
%test_suite(My macro tests);
  %test_case(Non-empty output);
    %assertNotEqual(%str__trim(  a  ), );
  %test_summary;
%test_summary;
```

### 3. Export a WORK table for debugging

```sas
%let debug_dir=%sysfunc(tranwrd(%sysfunc(pathname(work)), \, /));
%export_to_csv(work.intermediate_table, &debug_dir);
```

## Testing notes

- Many module files contain test blocks at file end.
- Deterministic full-suite run is available via `tests/run_tests.sas`.
- For CI-like runs, prefer the deterministic runner over ad hoc includes.
