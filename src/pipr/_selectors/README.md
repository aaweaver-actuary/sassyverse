# pipr selectors

This folder contains column-selector helpers used by `%select(...)`.

## Why selectors exist

Selectors let users write readable column intent instead of long explicit lists.

Example:

```sas
%select(
  %str(starts_with('policy') company_numb matches('state$') cols_where(~.is_char)),
  data=work.policies,
  out=work.selected
);
```

## Selector entry points (low-level)

- `%_selector_starts_with(ds=, prefix=, out_cols=)`
- `%_selector_ends_with(ds=, suffix=, out_cols=)`
- `%_selector_contains(ds=, needle=, out_cols=)`
- `%_selector_like(ds=, pattern=, out_cols=)`
- `%_selector_matches(ds=, regex=, out_cols=)`
- `%_selector_cols_where(ds=, predicate=, out_cols=)`

Each selector returns a space-delimited list of matching column names in `&out_cols`, preserving dataset column order (`varnum`).

`matches(...)` accepts:

- A raw regex body (for example `state$`, compiled as `/state$/i`)
- A full PRX literal (for example `/^policy_/i`)

## `cols_where(...)` predicate model

`cols_where(...)` evaluates a boolean expression against each row in `sashelp.vcolumn` for the input dataset.

Supported placeholders:

- `.name` / `.col` / `.column`
- `.type`, `.length`, `.label`, `.format`, `.informat`, `.varnum`
- `.is_char`, `.is_num`
- `.x` (alias for `.name`)

Examples:

```sas
/* all character columns */
cols_where(~.is_char)

/* numeric columns with name ending in _id */
cols_where(~.is_num and prxmatch('/_id$/i', .name) > 0)

/* same predicate using explicit lambda wrapper */
cols_where(lambda(.is_char and index(upcase(.name), 'STATE') > 0))
```

## Shared helpers (building blocks)

`utils.sas` provides the shared selector infrastructure:

- `%_sel_tokenize(...)` splits `select(...)` expressions into tokens while respecting quotes and parentheses.
- `%_sel_parse_call(...)` parses selector function calls and arguments.
- `%_sel_expand(...)` expands mixed expressions (raw columns + selectors) into one de-duplicated column list.
- `%_sel_query_cols(...)` runs centralized metadata queries against `sashelp.vcolumn`.
- `%_sel_collect_by_predicate(...)` evaluates metadata predicates row-wise against `sashelp.vcolumn`.
- `%_sel_list_append_unique(...)` merges lists while preserving first-seen order.

`lambda.sas` provides lambda syntax helpers:

- `%lambda(...)` produces a lambda expression prefixed with `~`.
- `%_sel_lambda_normalize(...)` accepts `~...` or `lambda(...)` and normalizes to the inner expression.

## Common selector tasks

### Keep all policy fields plus a few specific columns

```sas
%select(
  %str(starts_with('policy') company_numb home_state),
  data=work.policies,
  out=work.policy_core
);
```

### Keep only state-related character columns

```sas
%select(
  %str(cols_where(~.is_char and prxmatch('/state/i', .name) > 0)),
  data=work.policies,
  out=work.state_cols
);
```

### Combine regex and metadata filtering

```sas
%select(
  %str(matches('code$') cols_where(~.is_num)),
  data=work.policies,
  out=work.codes_and_nums
);
```

## Design notes

- Implementation is macro-based (not FCMP) because `%select(...)` needs compile-time expansion into a `keep=` list.
- Selector behavior is validated through unit tests in each selector file plus integration tests in:
  - `src/pipr/_verbs/select.sas`
  - `src/pipr/pipr.sas`
