#!/usr/bin/env python3
"""No database/credentials: test exact owner-only Titus issue dispatch parser.

Do not create a production release issue in this test. Actual protected
workflow approval, custody checks and encrypted production URL remain separate.
"""
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REQUEST = ROOT / ".github/workflows/production-db-release-request.yml"
RELEASE = ROOT / ".github/workflows/production-db-release.yml"
VERSION = "20261104222535"
PROJECT = "zirqkouammpwxlqfbsvf"


def extract():
    src = REQUEST.read_text()
    match = re.search(r"python3 - <<'PY'\n(.*?)\n\s+PY\n", src, re.S)
    assert match, "owner request inline Python parser missing"
    lines = match.group(1).splitlines()
    indent = min(len(line) - len(line.lstrip(" ")) for line in lines if line.strip())
    return "\n".join(line[indent:] for line in lines)


def invoke(title, fields, valid):
    with tempfile.TemporaryDirectory(prefix="titus-release-request-") as td:
        output = Path(td) / "response"
        env = dict(os.environ, ISSUE_TITLE=title, ISSUE_BODY=fields,
                   GITHUB_OUTPUT=str(output))
        p = subprocess.run([sys.executable, "-c", extract()],
                           capture_output=True, text=True, env=env)
        if valid:
            assert p.returncode == 0, p.stderr
            value = output.read_text()
            assert f"release_lane=titus\n" in value
            assert f"migration_version={VERSION}\n" in value
            assert f"production_target={PROJECT}\n" in value
        else:
            assert p.returncode != 0, f"accepted invalid request: {title!r}"
            assert not output.exists(), "invalid request returned dispatch inputs"


def main():
    src = REQUEST.read_text()
    release = RELEASE.read_text()
    assert "github.event.issue.author_association == 'OWNER'" in src
    assert "github.event.issue.state == 'open'" in src
    assert "source_branch != 'main'" in src
    assert "gh workflow run production-db-release.yml" in src
    for field in ("--ref main", "-f release_lane=", "-f migration_version=", "-f confirm_project_ref="):
        assert field in src
    assert "environment: production" in release
    assert "github.ref == 'refs/heads/main'" in release
    assert "- titus" in release
    assert "bash scripts/check-titus-formation-custody.sh" in release
    assert "scripts/release-production-migration.sh" in release
    assert "cancel-in-progress: false" in release
    assert "if lane not in {'atlas', 'wnph', 'titus', 'shared'}:" in src
    assert "noel" not in src.split("if lane not in", 1)[1].split(":", 1)[0]

    fields = "\n".join([
        f"migration_version: {VERSION}",
        "release_lane: titus",
        f"production_target: {PROJECT}",
        "source_branch: main",
    ])
    invoke(f"Production release request: Titus {VERSION}", fields, True)
    invoke(f"Production release request: Atlas {VERSION}", fields, False)
    invoke(f"Production release request: Titus {VERSION}", fields.replace(
        "release_lane: titus", "release_lane: atlas"), False)
    invoke(f"Production release request: Titus {VERSION}", fields.replace(
        "source_branch: main", "source_branch: work"), False)
    invoke(f"Production release request: Titus {VERSION}", fields.replace(
        f"production_target: {PROJECT}", "production_target: other"), False)
    invoke(f"Production release request: Titus {VERSION}", fields.replace(
        "migration_version: " + VERSION, "migration_version: 123"), False)
    invoke(f"Production release request: Titus {VERSION}", fields + "\nrelease_lane: atlas", False)
    print("PASS: exact owner-only Titus release issue parser, wrong lane/name/"
          "target/branch/version and conflicting duplicates rejected; protected "
          "workflow selection unchanged. No release issue was created.")


if __name__ == "__main__":
    main()
