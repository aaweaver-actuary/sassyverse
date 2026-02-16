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

Boolean-like values accepted:

- `1/0`, `YES/NO`, `TRUE/FALSE`, `Y/N`, `ON/OFF`

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
- Multi-statement blocks are still valid with `%str(...)`

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
  - `validation.sas`: existence/type/key checks
  - `_verbs/utils.sas`: step parsing and macro dispatch
- `pipe()` internals are intentionally split into small helper macros for maintainability and testability.

## Picking load strategy

- For full project load, use `%sassyverse_init(..., include_pipr=1)`.
- For focused experimentation, include only:
  - `util.sas`
  - `validation.sas`
  - selector files (if using selector syntax)
  - needed verb files
  - `pipr.sas`
