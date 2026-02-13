# pipr

`pipr` provides tidyverse-style data pipelines for SAS. The main entry is the `pipe()` macro, which lets you chain verbs with a `|` delimiter.

## Quick start

```sas
%include "S:/small_business/modeling/sassyverse/src/pipr/pipr.sas";
%include "S:/small_business/modeling/sassyverse/src/pipr/_verbs/filter.sas";
%include "S:/small_business/modeling/sassyverse/src/pipr/_verbs/mutate.sas";
%include "S:/small_business/modeling/sassyverse/src/pipr/_verbs/select.sas";

%pipe(
  data=work.input,
  out=work.output,
  steps=filter(x > 0) | mutate(%str(y = x * 2;)) | select(x y)
);
```

## pipe() macro

```sas
%pipe(
  data=,
  out=,
  steps=,
  validate=1,
  use_views=1,
  view_output=0,
  debug=0,
  cleanup=1
);
```

- `steps` is a `|`-delimited list of verbs: `filter(...) | mutate(...) | select(...)`.
- `validate=1` enables checks like dataset existence and column presence.
- `use_views=1` allows intermediate steps to be written as views when the verb supports it.
- `view_output=1` makes the final output a view if the final verb supports it.
- `cleanup=1` removes temporary datasets created during the pipeline.

## Supporting files

- `validation.sas` contains safety checks used by verbs and `pipe()`.
- `util.sas` provides `_abort` and `_tmpds` helpers.
- `_verbs/utils.sas` defines the verb registry and the step expansion logic.

## Verbs

Verbs live in the `_verbs` folder. Include them individually or use the project entrypoint to load all of them.

Currently implemented verbs include:
- `arrange`, `sort`
- `filter`, `where`, `where_not`, `mask`, `where_if`
- `mutate`, `with_column`
- `select`, `keep`, `drop`
- `rename`
- `left_join` (hash-based)
- `summarise`, `summarize`

## Notes

- Some verbs are positional (for example `filter` and `mutate`). The pipeline will auto-quote the first argument for those verbs.
- `left_join` uses hash joins and can enforce unique keys via `require_unique=1`.
