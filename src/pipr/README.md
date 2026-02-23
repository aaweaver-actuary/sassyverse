# pipr

`pipr` is the tidyverse-style pipeline layer for sassyverse.

Main idea:

- chain dataset transforms with `|` delimiters
- keep each step explicit and testable
- reuse the same verbs standalone or inside `pipe()`

## Fast start

```sas
%pipe(
  data=work.input,
  out=work.output,
  steps=filter(x > 0) | mutate(y = x * 2) | select(x y),
  use_views=0
);
```

Equivalent positional style:

```sas
%pipe(
  work.input
  | filter(x > 0)
  | mutate(y = x * 2)
  | collect_into(work.output)
  , use_views=0
);
```

## `pipe()` signature

```sas
%pipe(
  steps=,
  data=,
  out=,
  validate=1,
  use_views=1,
  view_output=0,
  debug=0,
  cleanup=1
);
```

Behavior:

- `steps`: `|`-delimited chain, for example `filter(...) | select(...)`.
- `data`: optional if the first step token is a dataset name.
- `out`: optional if the last step is `collect_to(...)`/`collect_into(...)`.
- `validate=1`: run dataset/column validation where supported.
- `use_views=1`: use views for intermediate outputs on verbs that support views.
- `view_output=1`: allow final output to be a view.
- `debug=1`: print step-level planning/logging.
- `cleanup=1`: remove temporary working datasets.

Planner internals:

- Planner state/build logic is centralized in `src/pipr/plan.sas`.
- `%_pipe_plan_serialize(out_plan=...)` returns a text snapshot of the current plan.
- `%_pipe_plan_replay(plan=..., out=...)` replays a supported serialized plan via the data-step builder path.

Boolean-like values accepted:

- `1/0`, `YES/NO`, `TRUE/FALSE`, `Y/N`, `ON/OFF`

## Predicate Functions (`predicates.sas`)

`pipr` now includes a generalized function generator plus a core predicate surface.

Generator macros:

- `%gen_function(expr, args, name)` or named form `%gen_function(expr=..., args=..., name=...)`
- `%gen_predicate(expr, args, name)` convenience wrapper (`kind=PREDICATE`)
- `%predicate(...)` alias for `%gen_predicate(...)`
- `%list_functions()` to inspect registered functions

Positional example:

```sas
%gen_function(%str(((&x) > (&thr))), %str(x, thr=0), gt_thr);
```

Example ad hoc predicate:

```sas
%gen_predicate(
  name=near_zero,
  args=%str(x, tol=1e-6),
  expr=%str((abs(&x) <= (&tol))),
  overwrite=1
);

%filter(near_zero(balance), data=work.txn, out=work.txn_near_zero);
```

Built-in row-wise predicates include:

- missingness: `is_missing`, `is_not_missing`, `is_blank`, `is_na_like`
- equality/membership: `is_in`, `is_not_in`, `is_between`, `is_outside`, `is_equal`, `is_not_equal`
- numeric/data shape: `is_zero`, `is_positive`, `is_negative`, `is_nonpositive`, `is_nonnegative`, `is_integerish`, `is_multiple_of`, `is_finite`
- strings: `starts_with`, `ends_with`, `contains`, `matches`, `is_alpha`, `is_alnum`, `is_digit`, `is_upper`, `is_lower`, `is_like`
- dates: `is_before`, `is_after`, `is_on_or_before`, `is_on_or_after`, `is_between_dates`
- data-quality encodings: `is_numeric_string`, `is_date_string`, `is_in_format`

Column-wise predicate composition:

- `if_any(cols=..., pred=...)`
- `if_all(cols=..., pred=...)`

Examples:

```sas
%filter(if_any(cols=amt1 amt2 amt3, pred=is_zero()), data=work.fact, out=work.has_zero);
%filter(if_all(cols=id1 id2 id3, pred=is_not_missing()), data=work.fact, out=work.keys_complete);

/* lambda-style template across columns */
%filter(
  if_any(cols=code1 code2, pred=~prxmatch('/^X/', strip(.x)) > 0),
  data=work.fact,
  out=work.any_x_code
);
```

Note:

- In `filter(...)` and `mutate(...)`, registered predicates/functions are auto-expanded, so `is_zero(x)` and `if_any(...)` do not need a leading `%`.

## Selector quick guide (`select(...)`)

Supported selector tokens:

- `starts_with('prefix')`
- `ends_with('suffix')`
- `contains('substr')`
- `like('%pattern%')`
- `matches('regex')`
- `cols_where(predicate)`
- plain column names in the same expression

Examples:

```sas
%select(
  %str(starts_with('policy') company_numb ends_with('code') like('%state%')),
  data=work.policies,
  out=work.cols1
);

%select(
  %str(matches('state$') cols_where(~.is_char and prxmatch('/policy/i', .name) > 0)),
  data=work.policies,
  out=work.cols2
);
```

Notes:

- selector tokens may be separated by spaces or commas
- duplicates are removed in first-seen order
- `cols_where(...)` supports `~...` and `lambda(...)`

Lambda details:

- A lambda is a compact predicate applied per-column in `cols_where(...)`.
- `~...` is shorthand; `lambda(...)` is equivalent.
- The expression is evaluated against column metadata (`sashelp.vcolumn`), not dataset row values.
- This enables schema-driven selection that was not possible with only name-pattern selectors.

Example:

```sas
%select(
  %str(cols_where(~.is_char and .length <= 8 and prxmatch('/state/i', .name) > 0)),
  data=work.policies,
  out=work.char_state_cols
);
```

## Common tasks for new users

### 1. Filter, derive columns, and keep a few outputs

```sas
%pipe(
  work.policies
  | filter(premium > 1000)
  | mutate(premium_band = ifc(premium >= 2000, 'HIGH', 'STD'))
  | select(policy_id premium premium_band)
  | collect_into(work.policy_features)
  , use_views=0
);
```

`mutate(...)` ergonomics:

- Preferred: `mutate(new_col = expression)`
- Trailing `;` is optional for single assignments
- Multiple assignments can be comma-delimited: `mutate(a = x + 1, b = a * 2)`
- Whitespace is optional in assignments: `mutate(a=x+1,b=a*2)`
- Multi-statement blocks are still valid with `%str(...)`
- `with_column(...)` supports both legacy `with_column(name, expr, ...)` and mutate-style assignment form
- If assigning to columns named `data`, `out`, `validate`, or `as_view`, prefer `stmt=%str(...)` for clarity

### 2. Join lookup data

```sas
%pipe(
  work.policies
  | left_join(
      right=work.company_dim,
      on=company_numb,
      right_keep=company_name,
      method=AUTO
    )
  | collect_into(work.policy_enriched)
  , use_views=0
);
```

### 3. Aggregate by a group

```sas
%pipe(
  work.policies
  | summarise(premium, by=home_state, stats=sum=total_premium mean=avg_premium)
  | collect_into(work.premium_summary)
  , use_views=0
);
```

### 4. Rename and sort

```sas
%pipe(
  work.policies
  | rename(policy_id=id policy_type=lob)
  | arrange(id)
  | collect_into(work.policies_clean)
  , use_views=0
);
```

### 5. Debug a pipeline

```sas
%pipe(
  data=work.policies,
  out=work.policies_dbg,
  steps=filter(premium > 1000) | select(policy_id premium),
  debug=1,
  use_views=0
);
```

## Design notes

- Verbs are implemented in `_verbs/*.sas`.
- Selector system is in `_selectors/*.sas`.
- Shared plumbing:
  - `util.sas`: `_abort`, `_tmpds`, boolean/test helpers
  - `predicates.sas`: `%gen_function`, `%gen_predicate`, built-in predicates, `if_any/if_all` helpers
  - `validation.sas`: existence/type/key checks
  - `_verbs/utils.sas`: step parsing and macro dispatch
- `pipe()` internals are intentionally split into small helper macros for maintainability and testability.

## Picking load strategy

- For full project load, use `%sassyverse_init(..., include_pipr=1)`.
- For focused experimentation, include only:
  - `util.sas`
  - `predicates.sas` (if using `%gen_function`, `%gen_predicate`, or predicate helpers such as `if_any/if_all`)
  - `validation.sas`
  - selector files (if using selector syntax)
  - needed verb files
  - `pipr.sas`
