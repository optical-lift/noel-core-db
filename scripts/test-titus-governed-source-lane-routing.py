#!/usr/bin/env python3
"""No credentials, no database: exercise exact existing owner-issue parsers.

A Titus structural migration can use the same governed source generation and
production-schema clone as Atlas. This test does not create migration history,
authorize any release, invoke GitHub APIs or access the protected environment.
"""
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHA = "1" * 40
NAME = "titus_customer_workspace_first_course_v1"
VERSION = "20261104220000"


def request_python(path: str) -> str:
    value = (ROOT / path).read_text()
    match = re.search(r"python3 - <<'PY'\n(.*?)\n\s+PY\n", value, re.S)
    if not match:
        raise AssertionError(f"Cannot locate owner-request parser in {path}")
    lines = match.group(1).splitlines()
    meaningful = [x for x in lines if x.strip()]
    indent = min(len(x) - len(x.lstrip(" ")) for x in meaningful)
    return "\n".join(x[indent:] for x in lines)


def check_parser(path: str, title: str, body: str, expected: bool):
    with tempfile.TemporaryDirectory(prefix="noel-titus-parse-") as tmp:
        output = Path(tmp) / "output"
        env = dict(os.environ, ISSUE_TITLE=title, ISSUE_BODY=body,
                   GITHUB_OUTPUT=str(output))
        p = subprocess.run([sys.executable, "-c", request_python(path)],
                           env=env, capture_output=True, text=True)
        if expected and p.returncode != 0:
            raise AssertionError(f"{path} rejected valid Titus: {p.stderr}")
        if not expected and p.returncode == 0:
            raise AssertionError(f"{path} accepted invalid Titus request")
        return output.read_text() if output.exists() else ""


def main():
    generate = ".github/workflows/migration-source-generation.yml"
    validate = ".github/workflows/production-schema-clone-validation.yml"
    generated_body = "\n".join((
        "release_lane: titus",
        f"migration_name: {NAME}",
        f"candidate_sha: {SHA}",
        "candidate_path: candidates/titus-customer-workspace-first-course-v1/candidate.sql",
        "fixture_path: none",
        "validation_path: none",
    ))
    title = f"Migration generation request: Titus {NAME}"
    good = check_parser(generate, title, generated_body, True)
    assert "release_lane=titus" in good and f"migration_name={NAME}" in good
    check_parser(generate, "Migration generation request: Atlas " + NAME,
                 generated_body, False)
    check_parser(generate, title, generated_body.replace(
        "migration_name: " + NAME,
        "migration_name: atlas_customer_workspace_first_course_v1"
    ), False)

    validation_body = "\n".join((
        f"migration_version: {VERSION}",
        "release_lane: titus",
        "production_target: zirqkouammpwxlqfbsvf",
        f"candidate_sha: {SHA}",
    ))
    validation_title = f"Production schema validation request: Titus {VERSION}"
    good = check_parser(validate, validation_title, validation_body, True)
    assert "release_lane=titus" in good and f"migration_version={VERSION}" in good
    check_parser(validate, "Production schema validation request: Atlas " +
                 VERSION, validation_body, False)
    check_parser(validate, validation_title, validation_body.replace(
        "production_target: zirqkouammpwxlqfbsvf",
        "production_target: not-production"
    ), False)

    script = (ROOT / "scripts/validate-production-schema-clone.sh").read_text()
    assert '--release-lane <atlas|wnph|titus|noel|shared>' in script
    assert '"$lane" != "titus"' in script
    assert '"$lane" != "shared"' in script

    # The independently existing lane checker must not be bypassed.
    with tempfile.TemporaryDirectory(prefix="noel-titus-lane-") as tmp:
        target = Path(tmp) / (VERSION + "_" + NAME + ".sql")
        target.write_text((ROOT /
           "candidates/titus-customer-workspace-first-course-v1/candidate.sql").read_text())
        check = subprocess.run(
            ["bash", "scripts/check-migration-release-lane.sh",
             VERSION, "titus", str(target)],
            cwd=ROOT,capture_output=True,text=True)
        if check.returncode:
            raise AssertionError(check.stderr or check.stdout)
        deny = subprocess.run(
            ["bash", "scripts/check-migration-release-lane.sh",
             VERSION, "atlas", str(target)],
            cwd=ROOT,capture_output=True,text=True)
        assert deny.returncode != 0
    print("PASS: owner-only Titus migration generator/clone parser accepts exact "
          "Titus lane; wrong title/target/prefix rejected; existing lane membrane preserved.")


if __name__ == "__main__":
    main()
