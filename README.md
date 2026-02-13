# Sassyverse

A SAS macro toolkit that brings tidyverse-style data manipulation, lightweight testing helpers, and productivity utilities into a single, reusable codebase.

## Quick start

1. Include the entrypoint.
2. Call the initializer with the path to the src folder.

```sas
%include "S:/small_business/modeling/sassyverse/sassyverse.sas";

%sassyverse_init(
  base_path=S:/small_business/modeling/sassyverse/src,
  include_pipr=1,
  include_tests=0
);
```

Notes:
- Use forward slashes in paths for portability in SAS.
- Several modules currently run their unit tests on include. If you want a quiet load, set `include_tests=0` and consider removing auto-run tests in module files.

## What you get

- Core utilities in src (strings, lists, date helpers, logging, shell helpers, export, hash utilities, equality checks, rounding, and index helpers).
- A small testing framework: `assert.sas` and `testthat.sas`.
- `pipr`: a tidyverse-style pipeline macro with verbs like `filter`, `mutate`, `select`, `arrange`, and `left_join`.

## Project layout

- src/        Core macros and function definitions
- src/pipr/   Pipeline engine and validation helpers
- src/pipr/_verbs/   Verb implementations for `pipe()`
- sassyverse.sas     Single entrypoint to load everything

## Testing

- `assert.sas` provides `assertTrue`, `assertFalse`, `assertEqual`, and `assertNotEqual`.
- `testthat.sas` provides test-suite and test-case wrappers and convenience checks like `tt_require_nonempty`.
- Many modules auto-run tests at the end of the file. This can be convenient during development but noisy in production.

### Test runner

Use the deterministic test runner to execute the full suite:

```sas
%include "S:/small_business/modeling/sassyverse/tests/run_tests.sas";
%sassyverse_run_tests(base_path=S:/small_business/modeling/sassyverse/src);
```

This sets `__unit_tests=1` and loads the suite in a consistent order.

## Dependencies and assumptions

- Some modules reference external paths like `/sas/data/project/EG/aweaver/macros` and expect a writable WORK library.
- `assert.sas` references `sbfuncs` and `sb_funcs` function libraries; ensure these libraries are assigned in your environment.
- `shell.sas` includes Windows-safe wrappers for common operations. `shchmod` is a no-op on Windows.

## Known gaps and follow-ups

- `src/pipr/verbs.sas` includes all verbs, but you can also include specific verb files if you want a smaller footprint.
- Several modules hardcode default directories. Consider centralizing configuration in one place for portability.

## Contributing

- Keep macros small and focused.
- Add tests using `assert.sas` and `testthat.sas` for new behavior.
- Prefer `pipe()` verbs for data set transforms to keep pipelines consistent.

## License

See LICENSE.
