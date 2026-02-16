# Pass 1 Error Catalog and Root-Cause Classification

- Log file: `log-with-errors.txt`
- Total lines: `110075`
- Runtime errors (`^ERROR:`): `62209`
- Runtime warnings (`^WARNING:`): `200`
- Unique runtime error signatures: `5`

## Include File Error Distribution

| Include file | Error count |
|---|---:|
| `/parm_share/small_business/modeling/sassyverse/src/pipr/predicates.sas` | 62205 |
| `/parm_share/small_business/modeling/sassyverse/src/pipr/pipr.sas` | 2 |
| `/parm_share/small_business/modeling/sassyverse/src/testthat.sas` | 2 |

## Category Counts

| Category | Count |
|---|---:|
| `D` | 62205 |
| `E` | 2 |
| `UNCLASSIFIED` | 2 |

## Invariant Validation

- FAILED: runtime_errors mismatch: expected 1307, got 62209
- FAILED: runtime_warnings mismatch: expected 58, got 200
- FAILED: unique_signatures mismatch: expected 36, got 5
- FAILED: predicates include count mismatch: expected 1305, got 62205
- FAILED: category A mismatch: expected 3, got 0
- FAILED: category B mismatch: expected 108, got 0
- FAILED: category C mismatch: expected 60, got 0
- FAILED: category D mismatch: expected 1134, got 62205
- FAILED: categorized total mismatch: expected 62209, got 62207
- FAILED: unclassified errors present: 2

## Runtime Error Signatures

| Count | First line | Category | Signature |
|---:|---:|---:|---|
| 62205 | 6407 | `D` | `ERROR: Maximum level of nesting of macro functions exceeded.` |
| 1 | 110073 | `UNCLASSIFIED` | `ERROR: Dataset or view does not exist: policy_keys Step 1 did not create expected output. Step token: select(sb_policy_key)` |
| 1 | 110075 | `UNCLASSIFIED` | `ERROR: Execution canceled by an %ABORT CANCEL statement.` |
| 1 | 106653 | `E` | `ERROR: Expected %DO not found.` |
| 1 | 106654 | `E` | `ERROR: Skipping to next %END statement.` |

## Warning Signatures

| Count | Signature |
|---:|---|
| 122 | `WARNING: Apparent symbolic reference X not resolved.` |
| 28 | `WARNING: Apparent symbolic reference TOL not resolved.` |
| 16 | `WARNING: Apparent symbolic reference DATE not resolved.` |
| 8 | `WARNING: Apparent symbolic reference K not resolved.` |
| 8 | `WARNING: Apparent symbolic reference SET not resolved.` |
| 8 | `WARNING: Apparent symbolic reference Y not resolved.` |
| 4 | `WARNING: Apparent symbolic reference INFORMAT not resolved.` |
| 3 | `WARNING: Apparent symbolic reference XIN not resolved.` |
| 3 | `WARNING: Apparent symbolic reference XNOTIN not resolved.` |
