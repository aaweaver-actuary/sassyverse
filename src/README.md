# Core modules (src)

This folder contains the core macro library plus the testing utilities. Most files are self-contained and can be `%include`d individually, but the recommended way is to use the project entrypoint in the repo root.

## Entry and loading

- `sassymod.sas` defines `sbmod`/`sassymod` for one-time module loading. It uses a hardcoded default `base_path` that should be overridden in your environment.
- `globals.sas` sets up a few global variables used by other modules.
- `testthat.sas` contains higher-level test helpers and auto-runs its own tests when included.

## Module index

### assert.sas

- Minimal unit test framework with counters and log formatting.
- Macros: `assertTrue`, `assertFalse`, `assertEqual`, `assertNotEqual`, plus `test_suite`, `test_case`, `test_summary`.
- Also defines FCMP subroutines for data-step assertions.

### dates.sas

- Date convenience macros: `year`, `month`, `day`, `mdy`, and `fmt_date`.

### dryrun.sas

- `dryrun(macro_name, args)` resolves a macro call without executing it, useful for debugging macro expansion.
- Writes the resolved call to the log and returns it to the caller.

### export.sas

- Export helpers for CSV output: `export_to_csv`, `export_csv_copy`, `export_with_temp_file`.
- Uses `shell.sas` for chmod and listing output directories.

### hash.sas

- Helpers for declaring and configuring data-step hash objects: `hash__dcl`, `hash__key`, `hash__data`, `hash__missing`, `hash__add`.
- `make_hash_obj` provides a higher-level wrapper for common patterns.

### index.sas

- Index helpers for PROC DATASETS.
- `make_simple_index`, `make_simple_indices`, `make_comp_index` plus convenience aliases.

### is_equal.sas

- `is_equal(a,b)` and `is_not_equal(a,b)` for macro-level comparisons.
- Numeric-aware comparison with a fallback to character comparison.

### lists.sas

- List helpers: `len`, `nth`, `first`, `last`, `unique`, `sorted`, `push`, `pop`, `concat`, `foreach`, `transform`.

### logging.sas

- Logging to files with timestamps: `logger`, `logtype`, `info`, `dbg`, `console_log`.
- `set_log_level` and `toggle_log_level` for controlling verbosity.

### n_rows.sas

- `n_rows(ds)` returns the count of observations in a data set.

### round_to.sas

- `roundto(x, n_digits)` macro and FCMP function for numeric rounding.

### shell.sas

- Convenience wrappers around OS shell commands: `shell`, `shmkdir`, `shpwd`, `shrm`, `shrm_dir`, `shchmod`, `shls`.
- Includes Windows-safe wrappers. `shchmod` is a no-op on Windows.

### strings.sas

- Macro string helpers: `str__index`, `str__replace`, `str__trim`, `str__upper`, `str__lower`, `str__len`, `str__split`, `str__slice`, `str__startswith`, `str__endswith`, `str__join2`, `str__reverse`, `str__find`, `str__format`.
- Includes FCMP function versions as well.

### testthat.sas

- Higher-level test helpers: `nobs`, `tt_nonempty_bool`, `tt_require_nonempty`, `tt_is_nonempty`.
- Contains a self-test suite that auto-runs when included.

## Tests

Many modules contain auto-run test suites at the bottom of the file. This is useful during development but can be noisy or undesirable in production loads.

For a full deterministic run, use the runner at [tests/run_tests.sas](tests/run_tests.sas).

## Usage

For full-suite load, see the entrypoint in the repo root. For targeted use, `%include` the specific module file you need.
