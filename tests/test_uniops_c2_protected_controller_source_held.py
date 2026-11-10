#!/usr/bin/env python3
"""Offline C2 trusted-controller/hook contract tests, no external connection."""
from __future__ import annotations

import importlib.util
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
HOOK = ROOT / "scripts/prepare-uniops-c2-protected-clone-hook-held.py"
VALIDATOR = ROOT / "scripts/validate-production-schema-clone.sh"
WORKFLOW = ROOT / ".github/workflows/held-uniops-c2-protected-source-controller.yml"


class HeldC2ControllerSource(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("held_c2_installer", HOOK)
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)
        cls.validator = VALIDATOR.read_text(encoding="utf-8")
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")

    def test_one_exact_clone_only_hook_and_bash_syntax(self):
        compiled = self.module.build_copy(self.validator)
        self.assertEqual(compiled.count('phase="held C2 exact native Ledger source proof signed matrix"'), 1)
        self.assertLess(compiled.index('python3 "$repo_root/scripts/validate-atlas-c1-signed-http.py"'),
                        compiled.index('phase="held C2 exact native Ledger'))
        self.assertIn("--expected-function-sql", compiled)
        # bash -n misses doubled-backslash continuation: '\\\\' at EOL
        # escapes the backslash and executes the next argument as a command.
        # Exercise every multi-line C2 command rather than trusting syntax.
        hook = self.module.HOOK
        commands = [line for line in hook.splitlines()
                    if line.startswith("PGOPTIONS=")
                    or line.startswith("  -f \"$C2_")
                    or line.startswith("  --db-url ")
                    or line.startswith("  --expected-function-sql ")
                    or line.startswith("  --output ")]
        self.assertEqual(len(commands), 8)
        self.assertTrue(all(line.endswith(chr(92)) and
                            not line.endswith(chr(92) * 2)
                            for line in commands))
        self.assertIn('  >"$artifacts_dir/held-c2-signed-private.log" 2>&1', hook)
        self.assertIn("PGOPTIONS='-c uni_ops.disposable_clone=true'", compiled)
        self.assertIn("ffcf0b1c8ab49b4d456037aa5f1147cf", compiled)
        self.assertIn("held-c2-six-original-fixture.log", compiled)
        self.assertIn("held-c2-signed-private-receipt.txt", compiled)
        self.assertEqual(compiled.count('phase="candidate domain schema lint"'), 1)
        with tempfile.TemporaryDirectory() as d:
            p = pathlib.Path(d) / "validator-copy.sh"
            p.write_text(compiled)
            subprocess.run(["bash", "-n", str(p)], check=True)
        with self.assertRaises(ValueError):
            self.module.build_copy(compiled)

    def test_generated_hook_runs_only_fake_local_shell_dispatch(self):
        """Exercise the generated shell with fake psql/Python; no database."""
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            signed = root / "signed"
            proposed = root / "proposed"
            for relative in ("tests/uniops_c2_case_work_disposable_fixture_held.sql",
                             "scripts/validate-atlas-c2-case-work-signed-http.py"):
                file = signed / relative
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text("offline-only\n")
            proposed_sql = proposed / (
                "docs/review/uniops_c2_native_ledger_requirement_work_scope_held/"
                "proposed_function_review_only.sql")
            proposed_sql.parent.mkdir(parents=True, exist_ok=True)
            proposed_sql.write_text("offline-only\n")
            artifacts = root / "artifacts"
            artifacts.mkdir()
            trace = root / "trace.txt"
            shell = root / "mock-hook.sh"
            mocked_commands = r'''#!/usr/bin/env bash
set -euo pipefail
psql() {
  printf 'psql:%s:%s\n' "${PGOPTIONS:-}" "$*" >> "$TRACE"
  if [[ "$*" == *'select md5(pg_get_functiondef('* ]]; then
    printf 'ffcf0b1c8ab49b4d456037aa5f1147cf\n'
  else
    test "${PGOPTIONS:-}" = '-c uni_ops.disposable_clone=true'
    [[ " $* " == *' -f '* ]]
  fi
}
python3() {
  printf 'python:%s:%s\n' "${PGOPTIONS:-}" "$*" >> "$TRACE"
  test "${PGOPTIONS:-}" = '-c uni_ops.disposable_clone=true'
  test "$1" = "$C2_TEST_ROOT/scripts/validate-atlas-c2-case-work-signed-http.py"
  shift
  local receipt=''
  while (( $# )); do
    case "$1" in
      --db-url) test "$2" = "$database_url"; shift 2 ;;
      --expected-function-sql) test "$2" = "$C2_SOURCE_ROOT/docs/review/uniops_c2_native_ledger_requirement_work_scope_held/proposed_function_review_only.sql"; shift 2 ;;
      --output) receipt="$2"; shift 2 ;;
      *) echo 'unexpected arg' >&2; return 92 ;;
    esac
  done
  test -n "$receipt"
  printf '%s\n' 'C2 HELD synthetic signed owner, source-verified OFFLINE MOCK PASS' > "$receipt"
}
'''
            shell.write_text(mocked_commands + self.module.HOOK, encoding="utf-8")
            env = {
                "PATH": __import__("os").environ["PATH"],
                "TRACE": str(trace),
                "C2_TEST_ROOT": str(signed),
                "C2_SOURCE_ROOT": str(proposed),
                "artifacts_dir": str(artifacts),
                "database_url": "postgresql://postgres:postgres@127.0.0.1:40001/postgres",
            }
            subprocess.run(["bash", str(shell)], cwd=root, env=env,
                           check=True, capture_output=True, text=True)
            commands = trace.read_text().splitlines()
            self.assertEqual(len(commands), 4)
            self.assertTrue(commands[0].startswith("psql::"))
            self.assertIn("select md5(pg_get_functiondef(", commands[0])
            self.assertIn(str(proposed_sql), commands[1])
            self.assertIn("uniops_c2_case_work_disposable_fixture_held.sql", commands[2])
            self.assertTrue(commands[3].startswith("python:-c uni_ops.disposable_clone=true:"))
            self.assertIn("--expected-function-sql", commands[3])
            self.assertTrue((artifacts / "held-c2-signed-private-receipt.txt").is_file())

    def test_drift_and_missing_anchor_refused(self):
        for variant in (self.validator.replace("signed_http_probe=true", "signed_http_probe=false"),
                        self.validator + "\n# unauthorized change\n",
                        self.validator.replace('phase="candidate domain schema lint"',
                                               'phase="different lint"')):
            with self.assertRaises(ValueError):
                self.module.build_copy(variant)

    def test_pinned_custody_contracts_execute_from_checkout_root(self):
        """Reproduce the actual shell block with fake local files, no credentials."""
        workflow = self.workflow
        beginning = "          (\n            cd canonical\n"
        closing = "          )\n"
        self.assertEqual(workflow.count(beginning), 1)
        segment = workflow.split(beginning, 1)[1].split(closing, 1)[0]
        commands = [line.strip() for line in segment.splitlines()
                    if line.strip().startswith("bash ")]
        self.assertEqual(commands, [
            "bash scripts/check-custody.sh",
            "bash scripts/check-production-release-contract.sh",
            "bash scripts/check-production-schema-validation-contract.sh",
        ])
        # Reproduce this exact bounded source block with stand-in scripts
        # whose relative lookup fails when cwd is the overall workspace.
        # This is a pure local regression, not a protected schema test.
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            canonical = root / "canonical"
            (canonical / "schemas").mkdir(parents=True)
            (canonical / "scripts").mkdir(parents=True)
            (canonical / "schemas/OWNERSHIP.md").write_text("synthetic\n")
            receipt = root / "executed.txt"
            for command in commands:
                file = canonical / command.split(" ", 1)[1]
                file.write_text(
                    r"""#!/usr/bin/env bash
set -euo pipefail
test -f schemas/OWNERSHIP.md
printf '%s\n' "${0##*/}" >> "$TRACE"
""",
                    encoding="utf-8",
                )
            block = beginning + segment + closing
            env = dict(__import__("os").environ, TRACE=str(receipt))
            subprocess.run(["bash", "-euo", "pipefail", "-c", block],
                           cwd=root, env=env, check=True,
                           capture_output=True, text=True)
            self.assertEqual(receipt.read_text().splitlines(),
                             [command.rsplit("/", 1)[-1] for command in commands])

    def test_workflow_has_separate_owner_only_protected_gate(self):
        y = self.workflow
        self.assertIn("pull_request:", y)
        self.assertIn("issues:", y)
        self.assertIn("types: [opened, edited, reopened]", y)
        self.assertIn("github.event.issue.author_association == 'OWNER'", y)
        self.assertIn("github.actor == github.repository_owner", y)
        self.assertIn("environment: production", y)
        self.assertIn("NOEL_CORE_DATABASE_URL:", y)
        self.assertIn("supabase db dump", y)
        self.assertIn("production-custom-roles.sql", y)
        self.assertIn("production-user-schema.sql", y)
        self.assertIn("validate-production-schema-clone.sh", y)
        self.assertIn("20261019201528", y)
        self.assertIn("prepare-uniops-c2-protected-clone-hook-held.py", y)
        self.assertIn("diagnostic_scope", y)
        self.assertIn("release_intent", y)
        self.assertIn("checkout@v4", y)
        self.assertIn("pulls/2668", y)
        self.assertIn("pulls/2669", y)
        self.assertNotIn("workflow_dispatch:", y)
        self.assertNotIn("supabase db push", y)
        self.assertNotIn("supabase migration up", y)
        self.assertNotIn("secrets.SUPABASE_SERVICE_ROLE_KEY", y)
        # PR-only job has no secrets, no environment, no DB, no privileged
        # action. Protected job can never run from PR event.
        before, protected = y.split("\n  protected-disposable-signed-c2:\n", 1)
        self.assertNotIn("secrets.", before)
        self.assertNotIn("environment:", before)
        self.assertIn("github.event_name == 'issues'", protected)
        self.assertIn("github.event.issue.title == 'UNI-OPS C2 exact Ledger Case Work signed disposable test request'", protected)
        self.assertIn("ref: 32d67670259e37fc1bd1485ede2a4db7fc4e5401", protected)
        self.assertIn("ref: 2545ed3cdafc811ce6ccb466b6aaa99ab9d5ec17", protected)
        self.assertIn("ref: 7e9b712c38d6a9ff2ef3922f735431bc5dfd5f04", protected)
        self.assertTrue(y.index("Validate exact owner diagnostic scope") <
                        y.index("Read-only protected schema and roles snapshot") <
                        y.index("Validate C2 only on disposable clone"))


if __name__ == "__main__":
    unittest.main()
