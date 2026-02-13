# Agent Onboarding Notes (Sassyverse)

This repo is a SAS macro toolkit that emulates tidyverse-style workflows plus general utilities. Key goals: reliability, test coverage, portability.

## Entry points

- Root entry: sassyverse.sas
  - Use: %sassyverse_init(base_path=..., include_pipr=1, include_tests=0)
  - Expects base_path to point at src/.
- Deterministic test runner: tests/run_tests.sas
  - Use: %sassyverse_run_tests(base_path=..., include_pipr=1)
  - Sets __unit_tests=1 and loads in a fixed order.

## Test behavior

- Many modules auto-run tests at file end. This can be noisy in production.
- __unit_tests is used by some modules to guard tests, but guard logic must not evaluate an undefined macro var.
- Common failure mode: using %eval or %if on unquoted macro variables (causes numeric conversion errors).

## Known sensitive areas

- Macro argument parsing:
  - Use %superq for args that may include commas, pipes, or spaces.
  - For macros that accept code blocks (foreach), delay resolution with %nrstr and %unquote(%superq()).
- assertEqual/assertNotEqual:
  - Must handle both numeric and character comparisons safely.

## pipr

- Core pipeline macro: src/pipr/pipr.sas
- Helpers: src/pipr/validation.sas and src/pipr/_verbs/utils.sas
- Verbs live under src/pipr/_verbs/ and include summarise/summarize.
- validation.sas needs _ds_split to derive LIB/MEM; this was added.

## Shell and OS compatibility

- shell.sas wraps shell commands; on Windows, it uses cmd /c.
- Avoid quoted command strings inside filename pipe; prefer plain strings and rely on filename pipe quoting.
- shchmod is no-op on Windows.

## Export behavior

- export_csv_copy builds filenames by lowercasing dataset name and replacing dots with double underscores.
  - Example: work._exp -> work___exp.csv
- Tests must match this naming.

## Recent fixes from log-driven debugging

- lists.sas:
  - len default delimiters and safe handling for empty delimiters.
  - sorted reworked as a macro-level numeric sort to allow %let usage.
  - foreach uses %unquote(%superq(codeblock)).
- strings.sas:
  - str__split and str__format hardened with %superq and named args in tests.
- sassyverse_init:
  - include_pipr/include_tests must be parsed without numeric %eval errors.

## Style guidance

- Keep changes ASCII-only.
- Add tests that are deterministic and cleanup WORK datasets.
- Avoid datalines inside macros (causes CARDS errors).
- Prefer small, focused tests that isolate behavior.


# Agent Collaboration Instructions

This document captures the operating guidelines for how I (GitHub Copilot) work in this repo.
It is meant to be stable and reproducible for future sessions.

## Working Principles

- Be explicit, concise, and task-focused.
- Prefer deterministic behavior and reproducible outputs.
- Avoid unnecessary changes; keep diffs minimal and readable.
- Preserve existing behavior unless the user requests a change.

## Tooling and File Access

- Read relevant files before editing.
- Batch file reads when possible to reduce churn.
- Use `apply_patch` for single-file edits; avoid rewriting whole files unless required.
- Avoid destructive commands (e.g., reset/checkout) unless explicitly requested.

## SAS-Specific Guidance

- Use `%superq` for arguments that can include commas, pipes, or spaces.
- Avoid `%eval`/`%if` on unquoted macro vars that can be empty or non-numeric.
- For code-block macro arguments, delay resolution using `%nrstr` and `
	%unquote(%superq())` patterns.
- Avoid datalines inside macros.

## Testing Expectations

- Add deterministic tests that clean up WORK datasets.
- Keep tests focused and isolated per macro behavior.
- Prefer the repo test harness (`tests/run_tests.sas`) for new coverage.

## Communication and Reviews

- Lead with what changed and why.
- When asked for a review, prioritize defects, risks, and test gaps.
- Ask clarifying questions only when required to proceed.

## Constraints

- Keep content ASCII-only unless the file already uses Unicode and requires it.
- Do not remove or revert unrelated changes.

# IMPORTANT:

Given the magnitude of the task you are being asked to help with, **you are no longer bound by the previous 5-file checkin requirement**. You may edit as many files as needed to accomplish the task, but please keep diffs focused and readable. Always lead with a clear explanation of what changed and why.