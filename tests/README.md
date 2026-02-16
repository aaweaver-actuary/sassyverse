# tests

This folder contains the deterministic test entrypoint for sassyverse.

## Run the full suite

```sas
%include "S:/small_business/modeling/sassyverse/tests/run_tests.sas";
%sassyverse_run_tests(
  base_path=S:/small_business/modeling/sassyverse/src,
  include_pipr=1
);
```

What this does:

- sets `__unit_tests=1`
- loads the framework in a stable order
- triggers module-level `%_pipr_autorun_tests(...)` blocks

## Common workflows

### Core utilities only

```sas
%sassyverse_run_tests(
  base_path=S:/small_business/modeling/sassyverse/src,
  include_pipr=0
);
```

### Full framework (recommended for releases)

```sas
%sassyverse_run_tests(
  base_path=S:/small_business/modeling/sassyverse/src,
  include_pipr=1
);
```

## Interpreting failures

- `ERROR: [FAIL]` in logs indicates assertion failure.
- `ERROR: [ERROR]` usually indicates malformed test condition or macro runtime issue.
- `ERROR: ... _abort(...)` messages indicate explicit validation failure in framework code.

## Authoring guidance

- Keep tests deterministic.
- Create and delete temporary `WORK` datasets inside the same test macro.
- Prefer narrow, focused test cases over broad integration checks unless behavior truly spans modules.
