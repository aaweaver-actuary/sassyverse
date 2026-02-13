# Test Matrix and Hotspots

This is a compact map of where tests live and where failures have clustered.

## Core macros

- assert.sas
  - Tests: macro assertions and FCMP assertions.
  - Hotspot: assertEqual/assertNotEqual must support character comparisons.

- strings.sas
  - Tests: many string helpers.
  - Hotspot: argument parsing for str__split/str__format; use %superq.

- lists.sas
  - Tests: len/nth/first/last/unique/sorted/transform/foreach.
  - Hotspot: foreach codeblock expansion and macro-safe sorted output.

- export.sas
  - Tests: _get_dataset_name, _get_filename, export_to_csv, export_csv_copy, export_with_temp_file.
  - Hotspot: file naming (work._exp -> work___exp.csv) and shell command quoting.

- dryrun.sas
  - Tests: resolves a macro call.
  - Hotspot: resolve() must be executed in data step.

- index.sas
  - Tests: index creation via proc datasets.
  - Hotspot: avoid datalines within macro tests.

## pipr

- validation.sas
  - Tests: _assert_cols_exist, _get_col_attr, _assert_key_compatible, _assert_unique_key.
  - Hotspot: ensure _ds_split exists.

- pipe() integration
  - Tests: filter/mutate/select pipeline.

- verbs
  - arrange/filter/mutate/select/keep/drop/rename/join/summarise have basic tests.

## Environment assumptions

- The shell macros assume Unix commands on Linux hosts.
- Export tests write to WORK; clean up files when possible.
- Some warnings (parameter catalogs, compression) are expected and not failures.
