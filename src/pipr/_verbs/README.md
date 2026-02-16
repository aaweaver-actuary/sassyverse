# pipr verbs

This folder contains the individual verb implementations used by `pipe()`.

All verbs follow the same basic signature:

```sas
%verb_name(args, data=, out=, validate=1, as_view=0);
```

- `data` and `out` are the input and output datasets.
- `validate=1` runs safety checks (dataset existence, column existence, and key compatibility).
- `as_view=1` writes the output as a view for verbs that support it.
- Boolean flags accept `1/0`, `YES/NO`, `TRUE/FALSE`, and `ON/OFF`.

## New-user cheat sheet

Typical pipeline:

```sas
%pipe(
  work.input
  | filter(x > 0)
  | mutate(y = x * 2)
  | select(x y)
  | collect_into(work.output)
  , use_views=0
);
```

## Verbs

### arrange.sas

- `%arrange(by_list, data=, out=, validate=1, as_view=0)`
- `%sort(...)` is an alias.
- Uses PROC SORT, so it cannot create a view.

Example:

```sas
%arrange(descending premium policy_id, data=work.policies, out=work.policies_sorted);
```

### filter.sas

- `%filter(where_expr, ...)` filters rows.
- Aliases: `%where`, `%where_not`, `%mask`, `%where_if`.
- Supports `as_view=1`.

Examples:

```sas
%filter(premium > 1000, data=work.policies, out=work.high_premium);
%where_not(home_state='CA', data=work.policies, out=work.non_ca);
%where_if(premium > 1000, YES, data=work.policies, out=work.conditional_filter);
```

### mutate.sas

- `%mutate(stmt, ...)` adds or updates columns using a statement block.
- Alias: `%with_column(col_name, col_expr, ...)`.
- Supports `as_view=1`.
- For the common case, use assignment form directly: `mutate(new_col = expression)`.
- `mutate` auto-appends a trailing `;` when missing.
- Comma-delimited assignments are supported: `mutate(a = x + 1, b = a * 2)`.
- Compact form is also valid: `mutate(a=x+1,b=a*2)`.
- `with_column` also supports mutate-style assignments: `with_column(a = x + 1, b = a * 2, ...)`.
- `with_column(...)` is pipeline-friendly: `| with_column(a = x + 1, b = a * 2)`.
- For assignments to columns named `data/out/validate/as_view`, prefer `stmt=%str(...)` to avoid keyword ambiguity.

Examples:

```sas
%mutate(loss_ratio = losses / premium, data=work.policies, out=work.with_ratio);
%mutate(a = x + 1, b = a * 2, data=work.policies, out=work.with_two_cols);
%with_column(premium_k, premium / 1000, data=work.policies, out=work.with_k);
%with_column(a = x + 1, b = a * 2, data=work.policies, out=work.with_two_cols_wc);

/* multi-statement blocks are still supported */
%mutate(%str(a = x + 1; b = a * 2;), data=work.policies, out=work.multi_stmt);
```

### select.sas

- `%select(cols, ...)` keeps specific columns.
- Supports selector functions inside `cols`:
  - `starts_with('prefix')`
  - `ends_with('suffix')`
  - `contains('substr')`
  - `like('%pattern%')`
  - `matches('regex')`
  - `cols_where(~.is_char and prxmatch('/state/i', .name) > 0)`
- `cols` tokens can be space-separated or comma-separated, and duplicates are removed in first-seen order.
- Lambda predicates can be written as `~...` or with `%lambda(...)` for readability.
- Supports `as_view=1`.

Lambda notes:

- Lambda predicates are evaluated against column metadata (name/type/length/etc.), not dataset rows.
- This allows rule-based schema selection such as "all short character columns ending in `_state`".

Examples:

```sas
%select(policy_id premium, data=work.policies, out=work.base_cols);
%select(%str(starts_with('policy') matches('state$')), data=work.policies, out=work.smart_cols);
```

### keep.sas / drop.sas

- `%keep(vars, ...)` keeps the given columns.
- `%drop(vars, ...)` drops the given columns.
- Both support `as_view=1`.

Examples:

```sas
%keep(policy_id premium, data=work.policies, out=work.keep_cols);
%drop(debug_flag temp_col, data=work.policies, out=work.drop_cols);
```

### rename.sas

- `%rename(rename_pairs, ...)` renames columns using `old=new` pairs.
- Example: `%rename(a=b c=d, data=..., out=...)`.

### join.sas

- `%left_join(right, on=, data=, out=, ...)` hash-based left join.
- Validation includes key compatibility and optional uniqueness checks.
- Supports `as_view=1`.

Examples:

```sas
%left_join(
  right=work.company_dim,
  on=company_numb,
  data=work.policies,
  out=work.policies_enriched,
  right_keep=company_name,
  method=AUTO
);
```

### collect_to.sas

- `%collect_to(out_name, ...)` writes the current pipeline output to a target dataset.
- Alias: `%collect_into(...)`.

Example:

```sas
%collect_into(work.final_ds, data=work.tmp_ds);
```

### summarise.sas

- Aggregation support via PROC SUMMARY.
- Alias: `%summarize(...)`.

Example:

```sas
%summarise(
  vars=premium,
  by=home_state,
  data=work.policies,
  out=work.premium_summary,
  stats=sum=total_premium mean=avg_premium
);
```

## Pipeline integration

`_verbs/utils.sas` defines:
- The verb registry (which verbs support views and which are positional).
- Step expansion and argument injection for `pipe()`.

## Testing convention

- Use `%_pipr_require_assert;` at the start of test macros.
- Use `%_pipr_autorun_tests(test_macro_name);` at file end for deterministic auto-run behavior when `__unit_tests=1`.

## Common patterns

### Write transforms as views during development

```sas
%pipe(
  data=work.input,
  out=work.output_view,
  steps=filter(x > 0) | select(x y),
  use_views=1,
  view_output=1
);
```

### Disable validation for trusted, hot paths

```sas
%pipe(
  data=work.input,
  out=work.fast_path,
  steps=select(x y) | mutate(z = x + y),
  validate=0,
  use_views=0
);
```
