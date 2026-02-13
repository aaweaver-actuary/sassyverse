# Suggested Next Steps for Agents

1) Stabilize sassyverse_init flags
- Ensure include_pipr/include_tests parsing does not use numeric %eval and handles blanks.

2) Expand edge-case tests
- strings: delimiters with commas, empty args, str__format with multiple placeholders.
- lists: empty list behavior, transform with different delimiters, foreach with quoted code blocks.
- export: filenames with libref and dots, temp file cleanup.
- pipr: validate failure modes (nonexistent dataset, missing cols) via non-aborting test harness.

3) Add a non-aborting test harness
- Implement a test-only _abort shim to prevent abort cancel during negative-path tests.

4) Reduce log noise
- Consider a global QUIET flag to suppress auto-run tests or shell output during init.
