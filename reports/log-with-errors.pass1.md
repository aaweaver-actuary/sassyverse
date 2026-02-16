# Pass 1 Error Catalog and Root-Cause Classification

- Log file: `log-with-errors.txt`
- Total lines: `23800`
- Runtime errors (`^ERROR:`): `1307`
- Runtime warnings (`^WARNING:`): `58`
- Unique runtime error signatures: `36`

## Include File Error Distribution

| Include file | Error count |
|---|---:|
| `/parm_share/small_business/modeling/sassyverse/src/pipr/predicates.sas` | 1305 |
| `/parm_share/small_business/modeling/sassyverse/src/pipr/pipr.sas` | 2 |

## Category Counts

| Category | Count |
|---|---:|
| `A` | 3 |
| `B` | 108 |
| `C` | 60 |
| `D` | 1134 |
| `E` | 2 |

## Invariant Validation

- All invariants passed.

## Runtime Error Signatures

| Count | First line | Category | Signature |
|---:|---:|---:|---|
| 1134 | 5872 | `D` | `ERROR: Maximum level of nesting of macro functions exceeded.` |
| 27 | 5690 | `B` | `ERROR: %EVAL function has no expression to evaluate, or %IF statement has no condition.` |
| 27 | 5600 | `B` | `ERROR: Attempt to %GLOBAL a name (_N) which exists in a local environment.` |
| 27 | 5691 | `B` | `ERROR: The %TO value of the %DO _I loop is invalid.` |
| 27 | 5692 | `B` | `ERROR: The macro _PRED_RESOLVE_GEN_ARGS will stop executing.` |
| 12 | 5893 | `C` | `ERROR: Expecting a variable name after %LET.` |
| 12 | 5895 | `C` | `ERROR: The macro _PRED_REGISTRY_ADD will stop executing.` |
| 2 | 17183 | `C` | `ERROR: Symbolic variable name _PIPR_FUNCTION_KIND_IS_BETWEEN_DA must be 32 or fewer characters long.` |
| 2 | 14253 | `C` | `ERROR: Symbolic variable name _PIPR_FUNCTION_KIND_IS_DATE_STRIN must be 32 or fewer characters long.` |
| 2 | 10332 | `C` | `ERROR: Symbolic variable name _PIPR_FUNCTION_KIND_IS_INTEGERISH must be 32 or fewer characters long.` |
| 2 | 10757 | `C` | `ERROR: Symbolic variable name _PIPR_FUNCTION_KIND_IS_MULTIPLE_O must be 32 or fewer characters long.` |
| 2 | 9911 | `C` | `ERROR: Symbolic variable name _PIPR_FUNCTION_KIND_IS_NONNEGATIV must be 32 or fewer characters long.` |
| 2 | 9496 | `C` | `ERROR: Symbolic variable name _PIPR_FUNCTION_KIND_IS_NONPOSITIV must be 32 or fewer characters long.` |
| 2 | 5888 | `C` | `ERROR: Symbolic variable name _PIPR_FUNCTION_KIND_IS_NOT_MISSIN must be 32 or fewer characters long.` |
| 2 | 13804 | `C` | `ERROR: Symbolic variable name _PIPR_FUNCTION_KIND_IS_NUMERIC_ST must be 32 or fewer characters long.` |
| 2 | 16687 | `C` | `ERROR: Symbolic variable name _PIPR_FUNCTION_KIND_IS_ON_OR_AFTE must be 32 or fewer characters long.` |
| 2 | 16225 | `C` | `ERROR: Symbolic variable name _PIPR_FUNCTION_KIND_IS_ON_OR_BEFO must be 32 or fewer characters long.` |
| 2 | 14855 | `C` | `ERROR: Symbolic variable name _PIPR_FUNCTION_MACRO_IS_IN_FORMAT must be 32 or fewer characters long.` |
| 2 | 7864 | `C` | `ERROR: Symbolic variable name _PIPR_FUNCTION_MACRO_IS_NOT_EQUAL must be 32 or fewer characters long.` |
| 1 | 22602 | `E` | `ERROR: Expected %DO not found.` |
| 1 | 17184 | `C` | `ERROR: Invalid symbolic variable name _PIPR_FUNCTION_KIND_IS_BETWEEN_DATES.` |
| 1 | 14254 | `C` | `ERROR: Invalid symbolic variable name _PIPR_FUNCTION_KIND_IS_DATE_STRING.` |
| 1 | 10333 | `C` | `ERROR: Invalid symbolic variable name _PIPR_FUNCTION_KIND_IS_INTEGERISH.` |
| 1 | 10758 | `C` | `ERROR: Invalid symbolic variable name _PIPR_FUNCTION_KIND_IS_MULTIPLE_OF.` |
| 1 | 9912 | `C` | `ERROR: Invalid symbolic variable name _PIPR_FUNCTION_KIND_IS_NONNEGATIVE.` |
| 1 | 9497 | `C` | `ERROR: Invalid symbolic variable name _PIPR_FUNCTION_KIND_IS_NONPOSITIVE.` |
| 1 | 5889 | `C` | `ERROR: Invalid symbolic variable name _PIPR_FUNCTION_KIND_IS_NOT_MISSING.` |
| 1 | 13805 | `C` | `ERROR: Invalid symbolic variable name _PIPR_FUNCTION_KIND_IS_NUMERIC_STRING.` |
| 1 | 16688 | `C` | `ERROR: Invalid symbolic variable name _PIPR_FUNCTION_KIND_IS_ON_OR_AFTER.` |
| 1 | 16226 | `C` | `ERROR: Invalid symbolic variable name _PIPR_FUNCTION_KIND_IS_ON_OR_BEFORE.` |
| 1 | 14856 | `C` | `ERROR: Invalid symbolic variable name _PIPR_FUNCTION_MACRO_IS_IN_FORMAT.` |
| 1 | 7865 | `C` | `ERROR: Invalid symbolic variable name _PIPR_FUNCTION_MACRO_IS_NOT_EQUAL.` |
| 1 | 22603 | `E` | `ERROR: Skipping to next %END statement.` |
| 1 | 14275 | `A` | `ERROR: The text expression &X &REGEX contains a recursive reference to the macro variable X. The macro variable will be assigned` |
| 1 | 16712 | `A` | `ERROR: The text expression &X &START &END INCLUSIVE &INCLUSIVE contains a recursive reference to the macro variable X. The` |
| 1 | 5477 | `A` | `ERROR: The text expression &X BLANK_IS_MISSING &BLANK_IS_MISSING contains a recursive reference to the macro variable X. The` |

## Warning Signatures

| Count | Signature |
|---:|---|
| 35 | `WARNING: Apparent symbolic reference X not resolved.` |
| 7 | `WARNING: Apparent symbolic reference TOL not resolved.` |
| 4 | `WARNING: Apparent symbolic reference DATE not resolved.` |
| 2 | `WARNING: Apparent symbolic reference K not resolved.` |
| 2 | `WARNING: Apparent symbolic reference SET not resolved.` |
| 2 | `WARNING: Apparent symbolic reference Y not resolved.` |
| 1 | `WARNING: Apparent symbolic reference BLANK_IS_MISSING not resolved.` |
| 1 | `WARNING: Apparent symbolic reference END not resolved.` |
| 1 | `WARNING: Apparent symbolic reference INCLUSIVE not resolved.` |
| 1 | `WARNING: Apparent symbolic reference INFORMAT not resolved.` |
| 1 | `WARNING: Apparent symbolic reference REGEX not resolved.` |
| 1 | `WARNING: Apparent symbolic reference START not resolved.` |
