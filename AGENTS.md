# Agent Onboarding Notes (Sassyverse)

This repo is a SAS macro toolkit that emulates tidyverse-style workflows plus general utilities. Key goals: reliability, test coverage, portability.

## First 60 Seconds (Do This Before Any Edit)

1. Identify the current branch immediately.
2. Classify the requested work type before changing code:
  - Feature -> `feature/*`
  - Bug fix -> `bugfix/*`
  - Refactor -> `refactor/*`
  - Docs-only -> `docs/*`
3. If current branch type does not match the work type, STOP and switch/create the correct branch from latest `main`.
4. If on `main`, do not implement any change directly; create/switch to the correct branch type first.

- This branch check is mandatory and must be one of the first actions in every task.
- Do not proceed to file edits, staging, or commits until branch/work-type alignment is confirmed.

## Entry points

- Root entry: sassyverse.sas
  - Use: %sassyverse_init(base_path=..., include_pipr=1, include_tests=0)
  - Expects base_path to point at src/.
- Deterministic test runner: tests/run_tests.sas
  - Use: %sassyverse_run_tests(base_path=..., include_pipr=1)
  - Sets __unit_tests=1 and loads in a fixed order.

## pipr

- Core pipeline macro: src/pipr/pipr.sas
- Helpers: src/pipr/validation.sas, src/pipr/_verbs/utils.sas, src/pipr/predicates.sas
- Verbs live under src/pipr/_verbs/

### UML for pipr:

```mermaid

```

## Shell and OS compatibility

- shell.sas wraps shell commands; on Windows, it uses cmd /c.

## Export behavior

- export_csv_copy builds filenames by lowercasing dataset name and replacing dots with double underscores.
  - Example: work._exp -> work___exp.csv
- Tests must match this naming.

## Style guidance

- All public macros must:
  1. Be documented with a header comment block that documents the macro's purpose, parameters, return value, side effects, and MUST include an example of usage.
  2. Include a test case in the test suite that demonstrates the documented example and validates the expected behavior.
  3. Follow SOLID principles where applicable, especially Single Responsibility and Open/Closed.
    - Each macro should have a single, well-defined purpose.
    - Public macros should be designed to be orchestrators that call smaller, focused helper macros as needed.
    - Avoid monolithic macros that try to do too much; instead, break complex logic into smaller, reusable components.
  4. Use consistent naming conventions that reflect their purpose and behavior.
    - Macro names should be descriptive and follow a consistent pattern (e.g., verb_noun for actions).
    - Helper macros can have a prefix or suffix to indicate their internal use (e.g., _helper, _utils).
  
## Tooling and File Access

- Read relevant files before editing.
- Batch file reads when possible to reduce churn.
- Use `apply_patch` for single-file edits; avoid rewriting whole files unless required.
- Avoid destructive commands (e.g., reset/checkout) unless explicitly requested.

## SAS-Specific Guidance

- Datalines inside macros are NOT ACCEPTABLE.
- Note that there is significant centralization of logic. Before creating a new macro, check if existing macros can be composed to achieve the desired behavior.
- When adding new functionality, consider whether it can be implemented as a helper macro that can be called by existing public macros, rather than creating a new public macro. This promotes code reuse and keeps the public API surface smaller and more maintainable.

### Centrally-Defined Logic

- Bootstrapping and include-order orchestration is centralized in `sassyverse.sas` via `sassyverse_init`, `_sassyverse_include`, and `_sassyverse_include_list`.
  - This is the single deterministic load graph for core modules plus optional `pipr` and `testthat` loading.
  - `tests/run_tests.sas` depends on this to ensure reproducible test import order.

- Module import idempotency is centralized in `src/sassymod.sas` (`sbmod`/`sassymod`).
  - Import markers (`_imported__*`) prevent duplicate includes.
  - Safe key generation and optional temporary debug-level toggling are encapsulated here.

- Core pipr utility primitives are centralized in `src/pipr/util.sas`.
  - Session-wide primitives: `_abort`, `_pipr_bool`, `_pipr_require_nonempty`, `_pipr_in_unit_tests`, `_pipr_autorun_tests`, `_pipr_require_assert`.
  - Parsing/tokenization primitives shared by pipeline, selectors, and verbs: `_pipr_split_parmbuff_segments`, `_pipr_tokenize`.
  - String/list normalization primitives shared across modules: `_pipr_strip_matching_quotes`, `_pipr_unbracket_csv_lists`, `_pipr_normalize_list`, `_pipr_ucl_assign`.

- Dataset/column validation is centralized in `src/pipr/validation.sas`.
  - Shared assertions: `_assert_ds_exists`, `_assert_cols_exist`, `_cols_missing`, `_assert_key_compatible`, `_assert_unique_key`.
  - Most verbs call these rather than implementing local metadata checks.

- Pipeline step dispatch is centralized in `src/pipr/_verbs/utils.sas` and consumed by `src/pipr/pipr.sas`.
  - `_apply_step` + `_step_parse` + `_step_call_positional/_step_call_named` forms the shared execution bridge.
  - View support policy (`_verb_supports_view`) is centralized and used by pipe planning.

- Selector expansion is centralized in `src/pipr/_selectors/utils.sas`.
  - Token parsing (`_sel_tokenize`, `_sel_parse_call`) and selector dispatch (`_sel_expand_token`) are shared.
  - Leaf selectors (`starts_with`, `ends_with`, `contains`, `matches`, `cols_where`) remain thin.

- Predicate/function registration and expansion is centralized in `src/pipr/predicates.sas`.
  - Registry lifecycle (`_pred_registry_reset`, `_pred_registry_add`) and expression expansion (`_pred_expand_expr`) are single-source.
  - Verbs like `filter` and `mutate` call into this shared expansion rather than duplicating predicate resolution logic.

- Verb include orchestration is centralized in `src/pipr/verbs.sas`, while execution orchestration lives in `src/pipr/pipr.sas`.
  - `verbs.sas` is the compatibility include surface for selectors + verbs.
  - `pipr.sas` owns pipeline planning, temp naming, collect-step extraction, and cleanup behavior.

### Candidate logic for further centralization

1. Consolidate repeated `parmbuff` named/positional argument parsing patterns from:
  - `src/pipr/_verbs/filter.sas` (`_filter_parse_parmbuff`, `_where_if_parse_parmbuff`)
  - `src/pipr/_verbs/mutate.sas` (`_mutate_parse_parmbuff`)
  - `src/pipr/pipr.sas` (`_pipe_parse_parmbuff`)
  into one reusable parser helper in `src/pipr/util.sas`.

2. Centralize DATA step emission with optional view output.
  - Current duplication: `_filter_emit_data`, `_mutate_emit_data`, and similar verb-local DATA step wrappers.
  - Candidate: shared helper that accepts `set` source and injected statement block/where expression.

3. Centralize common verb preflight and postflight checks.
  - Shared pattern appears across verbs: parse booleans -> `_assert_ds_exists` -> optional `_assert_cols_exist` -> run step -> `syserr` guard.
  - Candidate helpers: `_verb_preflight(...)` and `_verb_assert_success(verb_name=...)` in `src/pipr/_verbs/utils.sas`.

4. Consolidate local debug-gating patterns into one common utility layer.
  - Similar patterns exist in `src/pipr/util.sas` (`_pipr_util_dbg*`), `src/pipr/_selectors/utils.sas` (`_sel_dbg*`), and `src/pipr/predicates.sas` (`_pred_log`, `_pred_trace_*`).
  - Candidate: one shared logger facade with component tag support.

5. Unify bootstrapping/dependency guards for pipr modules.
  - Repeated checks like `if not %sysmacexist(...) then ...` are spread across `pipr.sas`, `predicates.sas`, selectors, and verbs.
  - Candidate: a centralized dependency-check helper that reports missing prerequisites uniformly.

6. Normalize boolean conversion across core and pipr.
  - Current duplication: `_pipr_bool` (`src/pipr/util.sas`) and `_sbmod_bool` (`src/sassymod.sas`) implement near-identical logic.
  - Candidate: reuse one canonical boolean parser everywhere.

7. Extract a shared expression-expansion adapter for predicate-enabled verbs.
  - Current duplication: `_filter_expand_where` and `_mutate_expand_functions` both perform optional `_pred_expand_expr` calls.
  - Candidate: a single helper in `src/pipr/predicates.sas` or `src/pipr/util.sas`.

8. Centralize selector function registry/dispatch map.
  - `_sel_expand_token` currently uses hard-coded `if/else` dispatch for each selector macro.
  - Candidate: registry-based selector dispatch (like predicate registry style) to reduce branching and ease new selector onboarding.

9. Centralize test bootstrap boilerplate for module-level unit tests.
  - Repeated pattern in many modules: `%if not %sysmacexist(assertTrue) %then %sbmod(assert);` and similar guarded test wrappers.
  - Candidate: one shared test bootstrap macro used by both core and pipr module tests.

## Formalized Working Plan (Current)

This section captures the practical workflow and architecture expectations that have been repeatedly validated during recent pipr hardening work.

### 1) Runtime-first debugging workflow

- Always reproduce with the deterministic loader/test path first:
  - `%sassyverse_init(base_path=..., include_pipr=1, include_tests=0)` for load-only checks.
  - `%sassyverse_run_tests(base_path=..., include_pipr=1)` or targeted module tests for deterministic execution order.
- Triage in this order:
  1. Compile/import errors (for example, unmatched `%if/%else`, dummy macro compiled).
  2. Macro resolution errors (for example, apparent invocation not resolved).
  3. Behavioral assertion failures.
- When collecting logs, prioritize the first failing block and immediately adjacent debug lines instead of full-log review.

### 2) Logging and debug contract

- Use a single debug entrypoint: `%dbg(...)`.
- `%dbg`/`%info` should carry diagnostics, but avoid high-volume routine noise in stable paths.
- Prefer failure-only debug statements for hot helpers (tokenizers/parsers).
- Put debug statements next to decision points and outputs that determine control flow.
- Do not include unescaped semicolons in inline `%if ... %then %dbg(...)` messages; this can terminate the statement early and break `%else` pairing.

### 3) Purity rule for value-returning macros

- Macros that return values inline (used inside `%let`, `%if`, or expression contexts) must be side-effect free.
- Do not call `%dbg`, `%info`, DATA steps, or other output-emitting macros from return-value helpers.
- If diagnostics are needed, log at the caller/orchestrator level, not inside value-return helpers.

### 4) Parser and tokenizer organization

- `src/pipr/util.sas` owns reusable parsing/tokenization primitives.
- Module wrappers (for example in predicates) should be thin adapters that:
  - normalize inputs,
  - call shared util helpers,
  - map outputs to module-specific variable names.
- Keep fallback behavior explicit and local when needed for compatibility, but prefer central primitives as the source of truth.

### 5) Test and regression expectations for parser changes

- Any parser/tokenizer fix must include or update a deterministic test case that covers:
  - nested parentheses,
  - quoted commas,
  - named/value argument segments,
  - and caller-scoped output variable assignment.
- When a failure involves unresolved symbols, include at least one test assertion that checks both count and token contents.

### 6) Safe change protocol during active debugging

- Keep patches minimal and directly tied to the current failing signal.
- Resolve compile-time syntax issues before iterating on behavioral fixes.
- After each fix, re-run targeted tests first, then broader suites if needed.
- Keep branch work linear and visible with focused `[BUGFIX]`/`[DEBUG]` commits.

## Testing Expectations

- All new features must include test cases that demonstrate the expected behavior and edge cases.
- Use the test suite in assert.sas for low-level assertions and the higher-level test functions in testthat.sas as appropriate.

## Constraints

- Keep content ASCII-only unless the file already uses Unicode and requires it.
- Do not remove or revert unrelated changes.

## What to do when...

### Branch Safety (Critical)

- Feature, bugfix, refactor, and docs implementation are NEVER allowed on `main`.
- If your current branch is `main`, you MUST stop implementation work and create/switch to the correct branch type (`feature/*`, `bugfix/*`, `refactor/*`, or `docs/*`) before making any code changes.
- Direct commits to `main` are prohibited for all feature, bugfix, refactor, and docs work; all such changes must flow through a PR.
- Treat any attempt to implement on `main` as a hard safety violation to be corrected immediately.

### Branch Scope and Course-Correction (Critical)

- A `feature/*` branch is single-purpose and must only contain commits for that specific feature.
- If unrelated work is discovered while building a feature (for example: bugfix, refactor, docs cleanup), do NOT continue mixing that work into the feature branch.
- Use branch names by intent:
  - `feature/<feature-name>` for feature implementation only.
  - `bugfix/<bug-name>` for defect fixes only.
  - `refactor/<topic>` for structural/code-quality changes only.
  - `docs/<topic>` for documentation-only changes.

#### Required interruption protocol

When feature work uncovers a separate fix that must happen first:

1. Stop feature implementation immediately.
2. Create a new branch from latest `main` for that fix (`bugfix/*`, `refactor/*`, or `docs/*` as appropriate).
3. Implement and test the fix in that branch only.
4. Merge that fix branch back to `main` through PR.
5. Return to the original `feature/*` branch.
6. Sync latest `main` into the feature branch (merge or rebase per repo policy).
7. Resume feature work.

- Never continue feature commits on top of an unmerged fix branch.
- Never leave required prerequisite fixes stranded only in a feature branch.

### 1. You encounter changes in the working tree that you did not make:
  1. Review the changes to understand what they are and why they might be there.
  2. If the changes are unrelated to your current task, your task is to immediately dispatch a subagent to perform a peer review of the code. This review should focus on identifying the source of the changes, assessing their relevance, and determining if they were intentional or accidental. 
    - If they appear to be accidental, you should revert the changes to maintain a clean working state.
    - If they appear to be intentional and pass a preliminary review, you should proceed to the next step.
  3. Once you are satisfied that the changes are intentional and relevant, you should incorporate them into your working state. This may involve merging the changes into your current branch or rebasing your work on top of the new changes, depending on the workflow you are following.

### 2. You begin work on a new feature
  1. Immediately identify the current branch you are working on and ensure that it is up to date with the latest changes from the main branch. If it is not, you MUST first merge or rebase the latest changes from the main branch into your current branch before proceeding with your work.
  2. Once you have confirmed that your branch is up to date, you should create a new branch for your feature work. Use the naming convention `feature/your-feature-name` for the new branch. This helps to keep the repository organized and makes it clear what the purpose of the branch is.

### 3. You are ready to commit your changes
  1. Before committing, review your changes to ensure that they are complete, well-documented, and properly tested. Make sure that your commit message follows the guidelines outlined in the Communication and Reviews section above.
  2. Ensure you have the following:
    - All public macros you created or modified are documented with a header comment block that includes an example of usage.
    - All new features have corresponding test cases that demonstrate the expected behavior and edge cases.
  3. Once you are satisfied with your changes and commit message (see above for guidelines), you can proceed to commit your changes. Use the appropriate tags in your commit message to indicate the nature of the changes you made (e.g., [FEAT], [BUGFIX], [REFACTOR], etc.). This helps maintain a clear history of changes and makes it easier for others to understand the purpose of each commit when reviewing the project history.

### 4. You begin reviewing a module you did not personally write, and there is no accompanying documentation or comments:
  1. If there is no provided documentation or comments, you should first attempt to understand the code by reading through it carefully and trying to infer its purpose and functionality based on the code itself. Look for any patterns, naming conventions, or structural elements that might provide clues about what the code is doing.
  2. You MUST next attempt a first pass documentation of the module. This involves writing a header comment block that describes the purpose of the module, its parameters, return value, and any side effects it may have. This documentation should be based on your understanding of the code and should aim to provide clarity for future readers.
  3. Document all public macros within the module, ensuring that each macro has a clear and descriptive header comment block that follows the guidelines outlined in the Style Guidance section above. This documentation should include an example of usage for each public macro to demonstrate how it is intended to be used.

## Communication and Reviews

- Lead with what changed and why.
- When asked for a review, prioritize defects, risks, and test gaps. 
- Ask clarifying questions only when required to proceed.
- This is a large project. You are expected to make significant changes. Focus on quality, not quantity. A well-scoped change that is well-tested and well-documented is more valuable than a large change that is rushed or incomplete.
- Given the magnitude of the task, you are no longer bound by the previous 5-file checkin requirement. You may edit as many files as needed to accomplish the task, but please keep diffs focused and readable. Always lead with a clear explanation of what changed and why.
- When reviewing code, focus on the following key areas:
  1. Correctness: Does the code do what it is supposed to do? Are there any logical errors or bugs?
  2. Readability: Is the code easy to understand? Are variable and function names descriptive? Is the code organized in a way that makes it easy to follow?
  3. Maintainability: Is the code structured in a way that makes it easy to modify and extend in the future? Are there any areas of technical debt that should be addressed?
  4. Test Coverage: Are there sufficient tests for the new features or changes? Do the tests cover edge cases and potential failure points?
- If you encounter unintended edits to the code, it is your job to first review them, then commit them if needed. 

# IMPORTANT

## Your work will only be considered complete when all of the following criteria are met:

1. Your original task has been implemented correctly and thoroughly on a feature branch.
2. A PR has been opened against the main branch with a clear description of the changes and their purpose.
3. You do not have any unintended edits in your working tree. If you do, you have either committed them or reverted them.
4. All public macros you created, modified, or merely encountered are documented with a header comment block that includes an example of usage.
5. All new features have corresponding test cases that demonstrate the expected behavior and edge cases.

## NEVER MAKE ANY CHANGES TO THE MAIN BRANCH. ALL WORK MUST BE DONE ON A FEATURE BRANCH AND MERGED VIA PR.

## HARD STOP RULE: IF YOU ARE ON `main`, DO NOT IMPLEMENT FEATURES. SWITCH TO A `feature/*` BRANCH FIRST.