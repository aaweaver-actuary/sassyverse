# pipr verbs

This folder contains the individual verb implementations used by `pipe()`.

All verbs follow the same basic signature:

```sas
%verb_name(args, data=, out=, validate=1, as_view=0);
```

- `data` and `out` are the input and output datasets.
- `validate=1` runs safety checks (dataset existence, column existence, and key compatibility).
- `as_view=1` writes the output as a view for verbs that support it.

## Verbs

### arrange.sas

- `%arrange(by_list, data=, out=, validate=1, as_view=0)`
- `%sort(...)` is an alias.
- Uses PROC SORT, so it cannot create a view.

### filter.sas

- `%filter(where_expr, ...)` filters rows.
- Aliases: `%where`, `%where_not`, `%mask`, `%where_if`.
- Supports `as_view=1`.

### mutate.sas

- `%mutate(stmt, ...)` adds or updates columns using a statement block.
- Alias: `%with_column(col_name, col_expr, ...)`.
- Supports `as_view=1`.

### select.sas

- `%select(cols, ...)` keeps specific columns.
- Supports `as_view=1`.

### keep.sas / drop.sas

- `%keep(vars, ...)` keeps the given columns.
- `%drop(vars, ...)` drops the given columns.
- Both support `as_view=1`.

### rename.sas

- `%rename(rename_pairs, ...)` renames columns using `old=new` pairs.
- Example: `%rename(a=b c=d, data=..., out=...)`.

### join.sas

- `%left_join(right, on=, data=, out=, ...)` hash-based left join.
- Validation includes key compatibility and optional uniqueness checks.
- Supports `as_view=1`.

### summarise.sas

- Aggregation support via PROC SUMMARY.
- Alias: `%summarize(...)`.

## Pipeline integration

`_verbs/utils.sas` defines:
- The verb registry (which verbs support views and which are positional).
- Step expansion and argument injection for `pipe()`.
