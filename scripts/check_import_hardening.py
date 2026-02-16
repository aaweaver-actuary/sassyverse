#!/usr/bin/env python3
"""Static guard checks for known pipr import-breaker regressions."""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass
class CheckResult:
    name: str
    ok: bool
    detail: str


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return ""


def check_no_pattern(text: str, pattern: str, name: str, detail: str) -> CheckResult:
    return CheckResult(name=name, ok=re.search(pattern, text, re.MULTILINE) is None, detail=detail)


def check_pattern(text: str, pattern: str, name: str, detail: str) -> CheckResult:
    return CheckResult(name=name, ok=re.search(pattern, text, re.MULTILINE) is not None, detail=detail)


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    util = read_text(repo / "src/pipr/util.sas")
    selectors_utils = read_text(repo / "src/pipr/_selectors/utils.sas")
    predicates = read_text(repo / "src/pipr/predicates.sas")
    pipr = read_text(repo / "src/pipr/pipr.sas")
    entry = read_text(repo / "sassyverse.sas")

    include_blocks = re.findall(
        r"%_sassyverse_include_list\(\s*root=%superq\(root\),\s*files=%str\((.*?)\),\s*out_failed=_sv_failed",
        entry,
        re.S,
    )
    missing_includes: list[str] = []
    for block in include_blocks:
        items = [x.strip() for x in block.split("|") if x.strip()]
        for item in items:
            path = repo / "src" / item
            if not path.exists():
                missing_includes.append(str(path))

    checks = [
        check_no_pattern(
            util,
            r"(?im)^\s*%global\s+&out_n\s*;",
            "util_splitter_no_global_out_n",
            "util splitter must not %GLOBAL out_n to avoid local/global collisions.",
        ),
        check_pattern(
            util,
            r"(?im)call\s+symputx\s*\(\s*symget\('out_n'\)\s*,\s*__seg_count\s*,\s*'F'\s*\)",
            "util_splitter_out_n_first_scope",
            "util splitter should write out_n with scope 'F'.",
        ),
        check_no_pattern(
            selectors_utils,
            r"(?im)^\s*%global\s+&out_n\s*;",
            "selector_tokenizer_no_global_out_n",
            "selector tokenizer must not %GLOBAL out_n to avoid local/global collisions.",
        ),
        check_pattern(
            selectors_utils,
            r"(?im)call\s+symputx\s*\(\s*symget\('out_n'\)\s*,\s*n\s*,\s*'F'\s*\)",
            "selector_tokenizer_out_n_first_scope",
            "selector tokenizer should write out_n with scope 'F'.",
        ),
        check_no_pattern(
            predicates,
            r"_pipr_function_kind_|_pipr_function_macro_",
            "predicates_no_dynamic_registry_var_names",
            "predicates should not use dynamic _pipr_function_kind_/macro variable names.",
        ),
        check_pattern(
            predicates,
            r"(?is)%macro\s+is_not_missing\s*\(",
            "predicates_explicit_is_not_missing",
            "is_not_missing should be an explicit macro definition.",
        ),
        check_pattern(
            predicates,
            r"(?is)%macro\s+is_in_format\s*\(",
            "predicates_explicit_is_in_format",
            "is_in_format should be an explicit macro definition.",
        ),
        check_pattern(
            predicates,
            r"(?is)%macro\s+is_between_dates\s*\(",
            "predicates_explicit_is_between_dates",
            "is_between_dates should be an explicit macro definition.",
        ),
        check_no_pattern(
            pipr,
            r"(?im)^\s*%global\s+__seg_count\s*;",
            "pipe_no_global_seg_count",
            "pipe parser should keep __seg_count local to avoid scope leakage.",
        ),
        check_pattern(
            pipr,
            r"(?is)%if\s*\(not\s*%sysmacexist\(filter\)\)\s*or\s*\(not\s*%sysmacexist\(mutate\)\)\s*or\s*\(not\s*%sysmacexist\(select\)\)\s*%then\s*%do\s*;\s*%include\s+'verbs\.sas'\s*;\s*%end\s*;",
            "pipe_include_guard_block_form",
            "pipr include guard should use explicit %DO/%END block form.",
        ),
        CheckResult(
            name="entrypoint_include_paths_exist",
            ok=len(missing_includes) == 0 and len(include_blocks) > 0,
            detail=(
                "all files referenced by sassyverse entrypoint include lists should exist under src/."
                if not missing_includes
                else "missing include files: " + ", ".join(missing_includes)
            ),
        ),
    ]

    failed = [c for c in checks if not c.ok]
    for c in checks:
        status = "PASS" if c.ok else "FAIL"
        print(f"[{status}] {c.name}: {c.detail}")

    if failed:
        print(f"\n{len(failed)} check(s) failed.")
        return 1

    print("\nAll import-hardening checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
