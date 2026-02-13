# Log Insights (Recent)

Key errors observed and their root causes:

1) %SYSEVALF function has no expression
- Cause: assertEqual used %eval on string comparisons; fixed with numeric/char branching.

2) More positional parameters found than defined
- Cause: macros called with unquoted special characters (|, commas) or code blocks expanded too early.
- Fix: use %superq for args and %nrstr in foreach call sites.

3) FILENAME PIPE invalid option name
- Cause: quoted command strings inside filename pipe broke parsing.
- Fix: avoid nested quotes; let filename pipe quote the whole command.

4) export_csv_copy filename mismatch
- Cause: replacing '.' with '__' on work._exp yields work___exp.csv.
- Fix: tests should expect work___exp.csv.

5) %eval numeric conversion errors
- Cause: %if &macrovar when macrovar is empty or non-numeric.
- Fix: use %length(%superq(var)) and string comparisons, or parse into known set (1/YES/TRUE).

6) datalines inside macros
- Cause: data step CARDS errors when macros expand with datalines.
- Fix: build data with assignment statements instead.
