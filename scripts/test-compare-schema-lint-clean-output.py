#!/usr/bin/env python3
"""No DB or secrets: prove clean CLI-v2 lint is not confused with failed lint."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().with_name("compare-schema-lint.py")
CLEAN_V2 = "\n".join((
    "Connecting to local database...",
    "Linting schema: titus",
    "A new version of Supabase CLI is available: v3.0.0 (currently installed v2.116.0)",
    "We recommend updating regularly for new features and bug fixes: https://supabase.com/docs/guides/cli/getting-started#updating-the-supabase-cli",
    "",
))


def run_case(base_raw, base_exit, candidate_raw, candidate_exit):
    with tempfile.TemporaryDirectory(prefix="noel-titus-clean-lint-") as temp:
        root = Path(temp)
        for name, raw, status in (
            ("baseline", base_raw, base_exit),
            ("candidate", candidate_raw, candidate_exit),
        ):
            (root / f"schema-lint-{name}.raw.log").write_text(raw)
            if status is not None:
                (root / f"schema-lint-{name}.exit-code.txt").write_text(str(status) + "\n")
        out = root / "artifacts"
        result = subprocess.run(
            [sys.executable, str(SCRIPT),
             str(root / "schema-lint-baseline.raw.log"),
             str(root / "schema-lint-candidate.raw.log"),
             "--artifacts-dir", str(out)],
            text=True, capture_output=True,
        )
        delta = json.loads((out / "schema-lint-delta.json").read_text()) if (
            out / "schema-lint-delta.json").exists() else None
        return result, delta


def check():
    clean, delta = run_case(CLEAN_V2, 0, CLEAN_V2, 0)
    assert clean.returncode == 0, clean.stderr
    assert delta is not None and delta["introduced_count"] == 0
    assert delta["baseline_count"] == delta["candidate_count"] == 0
    print("PASS: exact clean Supabase CLI v2.116.0 output with exit 0")

    prior, delta = run_case("No schema errors found\n", 0,
                            "No schema errors found\n", 0)
    assert prior.returncode == 0 and delta["introduced_count"] == 0, prior.stderr
    print("PASS: previous clean-output wording preserved with exit 0")

    for raw, code in (
        (CLEAN_V2, 1),
        (CLEAN_V2, None),
        ("Linting schema: titus\nunexpected failure detail\n", 0),
        ("some tool failed\n", 0),
        ("", 0),
    ):
        result, delta = run_case(raw, code, CLEAN_V2, 0)
        assert result.returncode != 0, f"Unexpected success for exit {code}: {raw!r}"
        assert delta is None
    print("PASS: nonzero/missing exit, extra errors and empty/unrecognized output still block")

    old = '[{"function":"audit_fn","issues":[]}]\n'
    new = '[{"function":"audit_fn","issues":[{"message":"new unsafe function","sqlState":"42P01"}]}]\n'
    regress, delta = run_case(old, 0, new, 1)
    assert regress.returncode != 0 and delta["introduced_count"] == 1
    print("PASS: introduced structured lint error still blocks a candidate")


if __name__ == "__main__":
    check()
