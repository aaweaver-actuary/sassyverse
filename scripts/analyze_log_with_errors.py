#!/usr/bin/env python3
"""Analyze SAS runtime errors in log-with-errors.txt.

This script implements the Pass 1 categorization plan:
- Count canonical runtime errors/warnings (lines starting with ERROR:/WARNING:)
- Exclude echoed source lines containing "ERROR:" text
- Build unique signature inventory (count + first occurrence)
- Attribute each runtime error to active include file and MLOGIC context
- Classify each runtime error into agreed categories A-E
- Validate category and total invariants
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Tuple


INCLUDE_RE = re.compile(r"^NOTE: %INCLUDE \(level 1\) file (?P<path>\S+) is file")
MLOGIC_RE = re.compile(r"^MLOGIC\((?P<context>[^)]*)\):")

TARGET_PREDICATES = "/parm_share/small_business/modeling/sassyverse/src/pipr/predicates.sas"
TARGET_PIPE = "/parm_share/small_business/modeling/sassyverse/src/pipr/pipr.sas"


@dataclass(frozen=True)
class RuntimeMessage:
    line_no: int
    include_file: str
    mlogic_context: str
    text: str


def normalize_ws(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip())


def parse_runtime_messages(lines: Iterable[str]) -> Tuple[List[RuntimeMessage], List[RuntimeMessage]]:
    include_file = ""
    mlogic_context = ""
    errors: List[RuntimeMessage] = []
    warnings: List[RuntimeMessage] = []

    for idx, raw in enumerate(lines, start=1):
        line = raw.rstrip("\n")

        include_match = INCLUDE_RE.match(line)
        if include_match:
            include_file = include_match.group("path")

        mlogic_match = MLOGIC_RE.match(line)
        if mlogic_match:
            mlogic_context = mlogic_match.group("context")

        stripped = line.lstrip()
        if stripped.startswith("ERROR:"):
            errors.append(
                RuntimeMessage(
                    line_no=idx,
                    include_file=include_file,
                    mlogic_context=mlogic_context,
                    text=normalize_ws(stripped),
                )
            )
        elif stripped.startswith("WARNING:"):
            warnings.append(
                RuntimeMessage(
                    line_no=idx,
                    include_file=include_file,
                    mlogic_context=mlogic_context,
                    text=normalize_ws(stripped),
                )
            )

    return errors, warnings


def classify_error(signature: str) -> str:
    if signature == "ERROR: Maximum level of nesting of macro functions exceeded.":
        return "D"

    if signature in {
        "ERROR: Attempt to %GLOBAL a name (_N) which exists in a local environment.",
        "ERROR: %EVAL function has no expression to evaluate, or %IF statement has no condition.",
        "ERROR: The %TO value of the %DO _I loop is invalid.",
        "ERROR: The macro _PRED_RESOLVE_GEN_ARGS will stop executing.",
    }:
        return "B"

    if signature in {
        "ERROR: Expected %DO not found.",
        "ERROR: Skipping to next %END statement.",
    }:
        return "E"

    if "recursive reference to the macro variable X" in signature:
        return "A"

    if (
        signature == "ERROR: The macro _PRED_REGISTRY_ADD will stop executing."
        or signature == "ERROR: Expecting a variable name after %LET."
        or signature.startswith("ERROR: Symbolic variable name _PIPR_FUNCTION_")
        or signature.startswith("ERROR: Invalid symbolic variable name _PIPR_FUNCTION_")
    ):
        return "C"

    return "UNCLASSIFIED"


def first_occurrence(signatures: Iterable[RuntimeMessage]) -> Dict[str, int]:
    first: Dict[str, int] = {}
    for msg in signatures:
        if msg.text not in first:
            first[msg.text] = msg.line_no
    return first


def summarize(messages: List[RuntimeMessage]) -> Dict[str, object]:
    signature_counts = Counter(msg.text for msg in messages)
    include_counts = Counter(msg.include_file for msg in messages)
    category_counts = Counter(classify_error(msg.text) for msg in messages)
    context_counts = Counter((msg.include_file, msg.mlogic_context, msg.text) for msg in messages)
    first = first_occurrence(messages)

    return {
        "signature_counts": dict(signature_counts),
        "include_counts": dict(include_counts),
        "category_counts": dict(category_counts),
        "context_counts": {
            " | ".join(k): v for k, v in context_counts.items()
        },
        "first_occurrence": first,
    }


def assert_invariants(
    errors: List[RuntimeMessage],
    warnings: List[RuntimeMessage],
    summary: Dict[str, object],
) -> List[str]:
    issues: List[str] = []
    category_counts: Dict[str, int] = summary["category_counts"]  # type: ignore[assignment]
    include_counts: Dict[str, int] = summary["include_counts"]  # type: ignore[assignment]
    signature_counts: Dict[str, int] = summary["signature_counts"]  # type: ignore[assignment]

    runtime_errors = len(errors)
    runtime_warnings = len(warnings)
    unique_signatures = len(signature_counts)

    expected = {
        "runtime_errors": 1307,
        "runtime_warnings": 58,
        "unique_signatures": 36,
        "predicates_errors": 1305,
        "pipr_errors": 2,
        "A": 3,
        "B": 108,
        "C": 60,
        "D": 1134,
        "E": 2,
    }

    if runtime_errors != expected["runtime_errors"]:
        issues.append(
            f"runtime_errors mismatch: expected {expected['runtime_errors']}, got {runtime_errors}"
        )
    if runtime_warnings != expected["runtime_warnings"]:
        issues.append(
            f"runtime_warnings mismatch: expected {expected['runtime_warnings']}, got {runtime_warnings}"
        )
    if unique_signatures != expected["unique_signatures"]:
        issues.append(
            f"unique_signatures mismatch: expected {expected['unique_signatures']}, got {unique_signatures}"
        )
    if include_counts.get(TARGET_PREDICATES, 0) != expected["predicates_errors"]:
        issues.append(
            "predicates include count mismatch: "
            f"expected {expected['predicates_errors']}, got {include_counts.get(TARGET_PREDICATES, 0)}"
        )
    if include_counts.get(TARGET_PIPE, 0) != expected["pipr_errors"]:
        issues.append(
            "pipr include count mismatch: "
            f"expected {expected['pipr_errors']}, got {include_counts.get(TARGET_PIPE, 0)}"
        )

    for cat in ("A", "B", "C", "D", "E"):
        if category_counts.get(cat, 0) != expected[cat]:
            issues.append(
                f"category {cat} mismatch: expected {expected[cat]}, got {category_counts.get(cat, 0)}"
            )

    categorized_total = sum(category_counts.get(cat, 0) for cat in ("A", "B", "C", "D", "E"))
    if categorized_total != runtime_errors:
        issues.append(
            f"categorized total mismatch: expected {runtime_errors}, got {categorized_total}"
        )

    if category_counts.get("UNCLASSIFIED", 0) != 0:
        issues.append(f"unclassified errors present: {category_counts.get('UNCLASSIFIED', 0)}")

    return issues


def build_markdown_report(
    log_path: Path,
    errors: List[RuntimeMessage],
    warnings: List[RuntimeMessage],
    summary: Dict[str, object],
    invariant_issues: List[str],
) -> str:
    signature_counts: Dict[str, int] = summary["signature_counts"]  # type: ignore[assignment]
    include_counts: Dict[str, int] = summary["include_counts"]  # type: ignore[assignment]
    category_counts: Dict[str, int] = summary["category_counts"]  # type: ignore[assignment]
    first: Dict[str, int] = summary["first_occurrence"]  # type: ignore[assignment]

    lines: List[str] = []
    lines.append("# Pass 1 Error Catalog and Root-Cause Classification")
    lines.append("")
    lines.append(f"- Log file: `{log_path}`")
    lines.append(f"- Total lines: `{sum(1 for _ in log_path.open('r', encoding='utf-8', errors='replace'))}`")
    lines.append(f"- Runtime errors (`^ERROR:`): `{len(errors)}`")
    lines.append(f"- Runtime warnings (`^WARNING:`): `{len(warnings)}`")
    lines.append(f"- Unique runtime error signatures: `{len(signature_counts)}`")
    lines.append("")

    lines.append("## Include File Error Distribution")
    lines.append("")
    lines.append("| Include file | Error count |")
    lines.append("|---|---:|")
    for include_file, count in sorted(include_counts.items(), key=lambda kv: (-kv[1], kv[0])):
        label = include_file if include_file else "(unknown)"
        lines.append(f"| `{label}` | {count} |")
    lines.append("")

    lines.append("## Category Counts")
    lines.append("")
    lines.append("| Category | Count |")
    lines.append("|---|---:|")
    for category in ("A", "B", "C", "D", "E", "UNCLASSIFIED"):
        if category in category_counts:
            lines.append(f"| `{category}` | {category_counts[category]} |")
    lines.append("")

    lines.append("## Invariant Validation")
    lines.append("")
    if not invariant_issues:
        lines.append("- All invariants passed.")
    else:
        for issue in invariant_issues:
            lines.append(f"- FAILED: {issue}")
    lines.append("")

    lines.append("## Runtime Error Signatures")
    lines.append("")
    lines.append("| Count | First line | Category | Signature |")
    lines.append("|---:|---:|---:|---|")
    for signature, count in sorted(signature_counts.items(), key=lambda kv: (-kv[1], kv[0])):
        category = classify_error(signature)
        lines.append(f"| {count} | {first[signature]} | `{category}` | `{signature}` |")
    lines.append("")

    lines.append("## Warning Signatures")
    lines.append("")
    warning_counts = Counter(msg.text for msg in warnings)
    lines.append("| Count | Signature |")
    lines.append("|---:|---|")
    for signature, count in sorted(warning_counts.items(), key=lambda kv: (-kv[1], kv[0])):
        lines.append(f"| {count} | `{signature}` |")
    lines.append("")

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--log",
        default="log-with-errors.txt",
        help="Path to SAS log file (default: log-with-errors.txt)",
    )
    parser.add_argument(
        "--out-md",
        default="reports/log-with-errors.pass1.md",
        help="Output Markdown report path",
    )
    parser.add_argument(
        "--out-json",
        default="reports/log-with-errors.pass1.json",
        help="Output JSON summary path",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit non-zero if any invariant fails",
    )
    args = parser.parse_args()

    log_path = Path(args.log)
    if not log_path.exists():
        raise SystemExit(f"log file not found: {log_path}")

    with log_path.open("r", encoding="utf-8", errors="replace") as f:
        errors, warnings = parse_runtime_messages(f)

    summary = summarize(errors)
    invariant_issues = assert_invariants(errors, warnings, summary)

    md = build_markdown_report(log_path, errors, warnings, summary, invariant_issues)

    out_md = Path(args.out_md)
    out_json = Path(args.out_json)
    out_md.parent.mkdir(parents=True, exist_ok=True)
    out_json.parent.mkdir(parents=True, exist_ok=True)

    out_md.write_text(md, encoding="utf-8")
    out_json.write_text(
        json.dumps(
            {
                "log_path": str(log_path),
                "runtime_error_count": len(errors),
                "runtime_warning_count": len(warnings),
                "summary": summary,
                "invariant_issues": invariant_issues,
            },
            indent=2,
            sort_keys=True,
        ),
        encoding="utf-8",
    )

    print(f"Wrote report: {out_md}")
    print(f"Wrote summary: {out_json}")
    if invariant_issues:
        print("Invariant issues:")
        for issue in invariant_issues:
            print(f"- {issue}")
        if args.strict:
            return 2
    else:
        print("All invariants passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
