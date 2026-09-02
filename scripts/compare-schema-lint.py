#!/usr/bin/env python3
"""Compare Supabase schema-lint findings before and after a candidate migration."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")


def parse_lint(path: Path) -> list[dict[str, Any]]:
    raw = ANSI.sub("", path.read_text(encoding="utf-8", errors="replace"))
    decoder = json.JSONDecoder()
    parsed: Any | None = None

    for index, character in enumerate(raw):
        if character not in "[{":
            continue
        try:
            candidate, _ = decoder.raw_decode(raw[index:])
        except json.JSONDecodeError:
            continue
        if isinstance(candidate, list) and all(isinstance(item, dict) for item in candidate):
            parsed = candidate
            break

    if parsed is None and "No schema errors found" in raw:
        return []

    if parsed is None:
        excerpt = raw[-2000:].strip()
        raise ValueError(
            f"{path} did not contain a parseable Supabase lint result. "
            f"Command output ended with:\n{excerpt}"
        )

    findings: list[dict[str, Any]] = []
    for function_result in parsed:
        function_name = function_result.get("function", "<unknown function>")
        issues = function_result.get("issues", [])
        if not isinstance(issues, list):
            raise ValueError(f"Unexpected issues payload for {function_name!r} in {path}")
        for issue in issues:
            if not isinstance(issue, dict):
                raise ValueError(f"Unexpected issue payload for {function_name!r} in {path}")
            findings.append({"function": function_name, "issue": issue})

    return findings


def canonical(finding: dict[str, Any]) -> str:
    return json.dumps(finding, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def summarized(finding: dict[str, Any]) -> str:
    issue = finding["issue"]
    message = str(issue.get("message", "unknown lint error")).replace("\n", " ")
    sql_state = issue.get("sqlState")
    suffix = f" (`{sql_state}`)" if sql_state else ""
    return f"`{finding['function']}` — {message}{suffix}"


def write_json(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline_raw", type=Path)
    parser.add_argument("candidate_raw", type=Path)
    parser.add_argument("--artifacts-dir", required=True, type=Path)
    args = parser.parse_args()

    args.artifacts_dir.mkdir(parents=True, exist_ok=True)
    baseline = parse_lint(args.baseline_raw)
    candidate = parse_lint(args.candidate_raw)

    baseline_by_key = {canonical(item): item for item in baseline}
    candidate_by_key = {canonical(item): item for item in candidate}
    introduced = [candidate_by_key[key] for key in sorted(candidate_by_key.keys() - baseline_by_key.keys())]
    resolved = [baseline_by_key[key] for key in sorted(baseline_by_key.keys() - candidate_by_key.keys())]
    unchanged = len(baseline_by_key.keys() & candidate_by_key.keys())

    write_json(args.artifacts_dir / "schema-lint-baseline.json", baseline)
    write_json(args.artifacts_dir / "schema-lint-candidate.json", candidate)
    write_json(
        args.artifacts_dir / "schema-lint-delta.json",
        {
            "baseline_count": len(baseline),
            "candidate_count": len(candidate),
            "unchanged_count": unchanged,
            "introduced_count": len(introduced),
            "resolved_count": len(resolved),
            "introduced": introduced,
            "resolved": resolved,
        },
    )

    outcome = "FAILED" if introduced else "PASSED"
    lines = [
        "# Production schema clone validation",
        "",
        f"**{outcome}: candidate-introduced Atlas lint errors: {len(introduced)}.**",
        "",
        f"- Baseline production-clone errors: {len(baseline)}",
        f"- Candidate-clone errors: {len(candidate)}",
        f"- Unchanged pre-existing errors: {unchanged}",
        f"- Errors resolved by candidate: {len(resolved)}",
        "",
    ]

    if introduced:
        lines.extend(["## Introduced errors", ""])
        lines.extend(f"- {summarized(item)}" for item in introduced)
        lines.append("")
    if resolved:
        lines.extend(["## Resolved errors", ""])
        lines.extend(f"- {summarized(item)}" for item in resolved)
        lines.append("")
    if baseline and not introduced:
        lines.extend(
            [
                "The pre-existing Atlas lint findings remain visible in the attached baseline report, "
                "but this candidate added or worsened none of them.",
                "",
            ]
        )

    summary = "\n".join(lines)
    (args.artifacts_dir / "summary.md").write_text(summary, encoding="utf-8")
    print(summary)
    return 1 if introduced else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # Keep parser failures explicit in CI and artifacts.
        print(f"Schema lint comparison failed: {exc}", file=sys.stderr)
        raise
