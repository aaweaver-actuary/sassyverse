/* MODULE DOC
File: src/pipr/verbs.sas

1) Purpose in overall project
- Pipr verb implementations for table transformation steps (select/filter/mutate/join/etc.).

2) High-level approach
- Each verb macro normalizes inputs, validates required datasets/columns, and emits a DATA step/PROC implementation.

3) Code organization and why this scheme was chosen
- One file per verb keeps behavior isolated; shared helpers (validation/utils) prevent repeated parsing/dispatch logic.
- Code is organized as helper macros first, public API second, and tests/autorun guards last to reduce contributor onboarding time and import risk.

4) Detailed pseudocode algorithm
- Parse verb arguments (including parmbuff positional/named forms where supported).
- Validate source dataset and required columns when validate=1.
- Normalize expressions/selectors into executable SAS code.
- Emit DATA/PROC logic to produce output dataset or view.
- Return stable output target name so pipe executor can chain next step.
- Expose alias macros for ergonomic naming compatibility where needed.

5) Acknowledged implementation deficits
- Different verbs use different SAS backends (DATA step, PROC SQL, hash) which increases cognitive load.
- Advanced edge-case validation is still evolving for some argument combinations.
- Contributor docs are still text comments; there is no generated API reference yet.

6) Macros defined in this file
- (No %macro definitions in this file; file is include/run orchestration only.)

7) Expected side effects from running/include
- No top-level side effects beyond macro definition were detected.
*/
%if not %sysmacexist(_abort) %then %include 'util.sas';
%if not %sysmacexist(_assert_ds_exists) %then %include 'validation.sas';

%include 'predicates.sas';

%include '_selectors/lambda.sas';
%include '_selectors/utils.sas';
%include '_selectors/starts_with.sas';
%include '_selectors/ends_with.sas';
%include '_selectors/contains.sas';
%include '_selectors/matches.sas';
%include '_selectors/cols_where.sas';

%include '_verbs/arrange.sas';
%include '_verbs/drop.sas';
%include '_verbs/drop_duplicates.sas';
%include '_verbs/filter.sas';
%include '_verbs/join.sas';
%include '_verbs/keep.sas';
%include '_verbs/mutate.sas';
%include '_verbs/collect_to.sas';
%include '_verbs/rename.sas';
%include '_verbs/select.sas';
%include '_verbs/summarise.sas';
