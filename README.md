# Sassyverse

Sassyverse is a SAS macro toolkit for:

- tidyverse-style dataset pipelines (`pipr`)
- small, practical utility macros (strings, lists, shell, export, hash helpers)
- lightweight unit testing

If you are new to the project, this README is the fastest onboarding path.

## Quick start

```sas
%include "S:/small_business/modeling/sassyverse/sassyverse.sas";

%sassyverse_init(
  base_path=S:/small_business/modeling/sassyverse/src,
  include_pipr=1,
  include_tests=0
);
```

Notes:

- `base_path` should point to the `src/` folder.
- Prefer forward slashes in paths for portability.
- Keep `include_tests=0` for production-style loads.

## First pipeline in 5 minutes

```sas
data work.policies;
  length policy_id 8 policy_type $12 company_numb 8 home_state $2 premium 8;
  policy_id=1001; policy_type='AUTO'; company_numb=44; home_state='CA'; premium=1200; output;
  policy_id=1002; policy_type='HOME'; company_numb=44; home_state='NV'; premium=1800; output;
run;

%pipe(
  work.policies
  | filter(premium >= 1500)
  | mutate(premium_band = 'HIGH')
  | select(policy_id policy_type premium premium_band)
  | collect_into(work.policy_high_premium)
  , use_views=0
);
```

## Common tasks for new users

### 1. Select columns quickly

```sas
%pipe(
  work.policies
  | select(
      starts_with('policy')
      company_numb
      matches('state$')
      cols_where(~.is_num)
    )
  | collect_into(work.policy_selected)
);
```

Useful selector helpers:

- `starts_with('prefix')`
- `ends_with('suffix')`
- `contains('substr')`
- `like('%pattern%')`
- `matches('regex')`
- `cols_where(predicate)` with `~...` or `lambda(...)`

Mutate style:

- Preferred: `mutate(new_column = expression)`
- You no longer need `%str(...)` for the common single-assignment case

### 2. Join lookup data

```sas
data work.company_dim;
  length company_numb 8 company_name $20;
  company_numb=44; company_name='Acme Insurance'; output;
run;

%pipe(
  work.policies
  | left_join(
      right=work.company_dim,
      on=company_numb,
      right_keep=company_name,
      method=AUTO
    )
  | collect_into(work.policy_enriched)
);
```

### 3. Aggregate results

```sas
%summarise(
  vars=premium,
  by=home_state,
  data=work.policies,
  out=work.premium_by_state,
  stats=sum=total_premium mean=avg_premium
);
```

### 4. Export a dataset to CSV

```sas
%let out_dir=%sysfunc(tranwrd(%sysfunc(pathname(work)), \, /));
%export_csv_copy(work.policies, out_folder=&out_dir);
```

### 5. Run the deterministic test suite

```sas
%include "S:/small_business/modeling/sassyverse/tests/run_tests.sas";
%sassyverse_run_tests(base_path=S:/small_business/modeling/sassyverse/src, include_pipr=1);
```

## Documentation map

- `src/README.md`: core utility modules and examples
- `src/pipr/README.md`: pipeline engine usage and workflow patterns
- `src/pipr/_verbs/README.md`: verb reference
- `src/pipr/_selectors/README.md`: selector and lambda reference
- `tests/README.md`: deterministic test runner usage

## Troubleshooting

- `ERROR: base_path= is required`: pass `base_path=` to `sassyverse_init`.
- `Dataset does not exist`: confirm `data=` input exists before running a verb.
- `Missing required columns`: set `validate=0` only when intentionally bypassing checks.
- `selector macro is not loaded`: load through `sassyverse_init(..., include_pipr=1)` or include selector files before `select.sas`.

## License

See `LICENSE`.
