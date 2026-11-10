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
STAGE_CLASSIFIER = ROOT / "scripts/uniops-c2-safe-disposable-stage-receipt.py"
C1_REASON_CLASSIFIER = ROOT / "scripts/uniops-c1-safe-postconditions-reason-held.py"
C1_CLONE_PARITY = ROOT / "scripts/uniops-c1-readonly-disposable-grants-held.py"
C1_CLONE_WRAPPER = ROOT / "scripts/prepare-uniops-c1-disposable-grant-observation-held.py"
C1_PINNED_POSTCONDITIONS = ROOT / "candidates/atlas-company-work-operating-register-v1/postconditions.sql"


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

    def test_safe_phase_classifier_matches_only_canonical_fixed_summary_lines(self):
        """A failed clone can expose only a hardcoded, public-safe phase enum."""
        spec = importlib.util.spec_from_file_location("c2_stage_classifier", STAGE_CLASSIFIER)
        classifier = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(classifier)
        self.assertEqual(
            classifier.categorize_summary(
                "**FAILED during disposable database startup.**\n"
                "Inspect the attached raw diagnostics for the exact command output.\n"),
            "disposable_startup")
        self.assertEqual(
            classifier.categorize_summary(
                "# Production schema clone validation\n"
                "Validation command exited during "
                "\x60held C2 exact native Ledger source proof signed matrix\x60.\n"),
            "c2_signed_local")
        self.assertEqual(
            classifier.categorize_summary(
                "Validation command exited during "
                "\x60signed local HTTP API authorization matrix\x60.\n"),
            "c1_signed_local")
        self.assertEqual(
            classifier.categorize_summary(
                "private_sql=Validation command exited during "
                "\x60held C2 exact native Ledger source proof signed matrix\x60.\n"),
            "unclassified")
        self.assertEqual(
            classifier.categorize_summary(
                "**FAILED during attacker private-schema path.**\n"),
            "unclassified")
        self.assertEqual(
            classifier.categorize_summary("a credential was refused\n"),
            "unclassified")
        self.assertEqual(
            classifier.categorize_summary(
                "Validation command exited during "
                "\x60held C2 exact native Ledger source proof signed matrix\x60.\n"
                "Validation command exited during \x60unrecognized stage\x60.\n"),
            "unclassified")

    def test_safe_phase_classifier_cli_never_prints_private_text(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            record = root / "summary.md"
            marker = "SENSITIVE_FAKE_SQL_TOKEN_DO_NOT_ECHO"
            record.write_text(
                "## synthetic summary\n"
                "Validation command exited during \x60production user-schema restore\x60.\n"
                + marker + "\n")
            result = subprocess.run(
                ["python3", str(STAGE_CLASSIFIER), str(record)],
                capture_output=True, text=True, check=True)
            self.assertEqual(result.stdout, "C2_DISPOSABLE_PHASE=clone_schema_restore\n")
            self.assertNotIn(marker, result.stdout + result.stderr)
            missing = subprocess.run(
                ["python3", str(STAGE_CLASSIFIER), str(root / "missing")],
                capture_output=True, text=True, check=True)
            self.assertEqual(missing.stdout, "C2_DISPOSABLE_PHASE=unclassified\n")
            oversize = root / "oversize.md"
            oversize.write_text(
                "Validation command exited during \x60production user-schema restore\x60.\n"
                + "X" * 66000)
            large = subprocess.run(
                ["python3", str(STAGE_CLASSIFIER), str(oversize)],
                capture_output=True, text=True, check=True)
            self.assertEqual(large.stdout, "C2_DISPOSABLE_PHASE=unclassified\n")
            sym = root / "symlink.md"
            sym.symlink_to(record)
            symlinked = subprocess.run(
                ["python3", str(STAGE_CLASSIFIER), str(sym)],
                capture_output=True, text=True, check=True)
            self.assertEqual(symlinked.stdout, "C2_DISPOSABLE_PHASE=unclassified\n")

    def test_c1_reason_classifier_exactly_matches_held_canonical_assertions(self):
        import re
        source = C1_PINNED_POSTCONDITIONS.read_text(encoding="utf-8")
        expressions = re.findall(r"raise exception '([^']+)'", source, flags=re.I)
        spec = importlib.util.spec_from_file_location("c1_reasons", C1_REASON_CLASSIFIER)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(len(expressions), 27)
        self.assertEqual(list(module.ASSERTION_CODES), expressions)
        for position, expression in enumerate(expressions, start=1):
            example = ("/tmp/PRIVATE_NAME_DO_NOT_REPORT.sql:340: "
                       "ERROR:  " + expression)
            self.assertEqual(module.classify_text("psql:" + example + "\n"),
                             f"assertion_{position:02d}")
        self.assertEqual(module.classify_text("ERROR:  permission denied for schema PRIVATE\n"),
                         "permission_denied")
        self.assertEqual(module.classify_text("ERROR:  function PRIVATE.do_thing() does not exist\n"),
                         "missing_function")
        self.assertEqual(module.classify_text(
            "CONTEXT: ERROR:  Revoked native seat still read C1 register\n"),
            "unclassified")
        self.assertEqual(module.classify_text(
            "ERROR:  completely unknown private SQL diagnostic here\n"),
            "unclassified")
        self.assertEqual(module.classify_text(
            "ERROR:  Revoked native seat still read C1 register\n"
            "ERROR:  Unsafe direct register table privileges\n"),
            "unclassified")

    def test_c1_reason_classifier_cli_private_log_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            record = root / "postconditions.log"
            secret = "FAKE_SECRET_SHOULD_NOT_LEAK_IN_ANY_OUTPUT"
            record.write_text(
                "psql:/tmp/PRIVATE_NAME_DO_NOT_REPORT.sql:44: "
                "ERROR:  Register RPC role grants incorrect\n"
                "STATEMENT: " + secret + "\n", encoding="utf-8")
            result = subprocess.run(
                ["python3", str(C1_REASON_CLASSIFIER), str(record)],
                capture_output=True, text=True, check=True)
            self.assertEqual(result.stdout, "C1_POSTCONDITIONS_REASON=assertion_06\n")
            self.assertNotIn(secret, result.stdout + result.stderr)
            large = root / "oversize.log"
            large.write_text(record.read_text() + "x" * 66000)
            oversized = subprocess.run(
                ["python3", str(C1_REASON_CLASSIFIER), str(large)],
                capture_output=True, text=True, check=True)
            self.assertEqual(oversized.stdout, "C1_POSTCONDITIONS_REASON=unclassified\n")
            alias = root / "symlink.log"
            alias.symlink_to(record)
            symlinked = subprocess.run(
                ["python3", str(C1_REASON_CLASSIFIER), str(alias)],
                capture_output=True, text=True, check=True)
            self.assertEqual(symlinked.stdout, "C1_POSTCONDITIONS_REASON=unclassified\n")
            missing = subprocess.run(
                ["python3", str(C1_REASON_CLASSIFIER), str(root / "absent.log")],
                capture_output=True, text=True, check=True)
            self.assertEqual(missing.stdout, "C1_POSTCONDITIONS_REASON=unclassified\n")

    def test_readonly_c1_clone_grant_parity_fixed_contract(self):
        spec = importlib.util.spec_from_file_location("held_c1_clone_acl", C1_CLONE_PARITY)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(len(module.FUNCTIONS), 6)
        self.assertEqual(module.EXPECTED, ("f", "t", "f"))
        self.assertEqual(module.LABELS, ("anon", "authenticated", "public"))
        self.assertTrue(module.local_clone_url(
            "postgresql://postgres:postgres@127.0.0.1:45789/postgres"))
        self.assertFalse(module.local_clone_url(
            "postgresql://postgres:postgres@remote.internal:45789/postgres"))
        self.assertFalse(module.local_clone_url(
            "postgresql://postgres:postgres@localhost:45789/postgres"))
        self.assertFalse(module.local_clone_url(
            "postgresql://postgres:postgres@127.0.0.1:543/postgres"))
        self.assertFalse(module.local_clone_url(
            "postgresql://postgres:postgres@127.0.0.1:45789/production"))
        rows = "".join(f"{i}|f|t|f\n" for i in range(1, 7))
        self.assertEqual(module.classify(rows), "pass")
        diff = rows.replace("1|f|t|f", "1|t|t|t")
        self.assertEqual(module.classify(diff),
                         "atlas_establish_anon,atlas_establish_public")
        diff2 = rows.replace("6|f|t|f", "6|f|f|f")
        self.assertEqual(module.classify(diff2),
                         "public_read_authenticated")
        self.assertEqual(module.classify(rows.replace("2|f|t|f", "2|f|2|f")),
                         "unclassified")
        self.assertEqual(module.classify(rows + "7|f|t|f\n"), "unclassified")
        self.assertEqual(module.classify("SENSITIVE_SQL_OUTPUT\n"), "unclassified")
        self.assertIn("SELECT r.idx", module.QUERY)
        for forbidden in ("ALTER ", "GRANT ", "REVOKE ", "DROP ",
                          "INSERT ", "UPDATE ", "DELETE "):
            self.assertNotIn(forbidden, module.QUERY.upper())
        for signature in (
            "atlas.establish_operating_requirement_owner_self_api_v1(",
            "atlas.revise_operating_requirement_owner_self_api_v1(",
            "atlas.operating_requirements_owner_self_api_v1(",
            "public.establish_operating_requirement_owner_self_api_v1(",
            "public.revise_operating_requirement_owner_self_api_v1(",
            "public.operating_requirements_owner_self_api_v1(",
        ):
            self.assertIn(signature, module.QUERY)

    def test_readonly_c1_clone_probe_executes_only_local_and_never_echoes_psql(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            stub = root / "psql"
            secret = "SENSITIVE_FAKE_SQL_DO_NOT_PRINT"
            stub.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' '1|f|t|f' '2|f|t|f' '3|f|t|f' "
                "'4|f|t|f' '5|f|t|f' '6|t|t|f'\n"
                "echo '" + secret + "' >&2\n",
                encoding="utf-8")
            stub.chmod(0o755)
            os = __import__("os")
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"])
            result = subprocess.run(
                ["python3", str(C1_CLONE_PARITY), "--db-url",
                 "postgresql://postgres:postgres@127.0.0.1:45789/postgres"],
                env=env, check=True, capture_output=True, text=True)
            self.assertEqual(result.stdout, "C1_CLONE_ACL=public_read_anon\n")
            self.assertNotIn(secret, result.stdout + result.stderr)
            invalid = subprocess.run(
                ["python3", str(C1_CLONE_PARITY), "--db-url",
                 "postgresql://postgres:postgres@prod.example:5432/postgres"],
                env=env, check=True, capture_output=True, text=True)
            self.assertEqual(invalid.stdout, "C1_CLONE_ACL=unclassified\n")
            self.assertNotIn(secret, invalid.stdout + invalid.stderr)

    def test_c1_clone_acl_wrapper_keeps_pinned_sql_and_never_writes_grants(self):
        spec = importlib.util.spec_from_file_location("c1_acl_wrapper", C1_CLONE_WRAPPER)
        wrapper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(wrapper)
        source = C1_PINNED_POSTCONDITIONS
        self.assertEqual(wrapper.git_blob(source.read_bytes()), wrapper.SOURCE_BLOB)
        with tempfile.TemporaryDirectory() as directory:
            d = pathlib.Path(directory)
            output = d / "postconditions-wrapper.sql"
            report = d / "clone-acl-private.txt"
            wrapper.make_wrapper(source, output, report)
            text = output.read_text(encoding="utf-8")
            self.assertEqual(text.count("\\i "), 1)
            self.assertIn("\\i " + str(source) + "\n", text)
            self.assertIn("\\o " + str(report) + "\n", text)
            self.assertIn("SELECT r.idx", text)
            self.assertLess(text.index("SELECT r.idx"), text.index("\\i " + str(source)))
            self.assertEqual(text.count("has_function_privilege("), 2)
            for forbidden in ("REVOKE ALL ", "GRANT EXECUTE ", "DROP FUNCTION ",
                              "ALTER FUNCTION ", "CREATE FUNCTION "):
                self.assertNotIn(forbidden, text.upper())
            with self.assertRaises(ValueError):
                wrapper.make_wrapper(source, output, report)
            rows = "".join(f"{i}|f|t|f\n" for i in range(1, 7))
            report.write_text(rows, encoding="utf-8")
            self.assertEqual(wrapper.summarize(report), "pass")
            report.write_text(rows.replace("4|f|t|f", "4|t|t|f"))
            self.assertEqual(wrapper.summarize(report),
                             "public_establish_anon")
            bad = d / "bad.sql"
            bad.write_text(source.read_text(encoding="utf-8") + "\n-- altered\n")
            with self.assertRaises(ValueError):
                wrapper.make_wrapper(bad, d / "new-wrapper.sql", d / "new-report.txt")
            symlink = d / "symlink.txt"
            symlink.symlink_to(report)
            self.assertEqual(wrapper.summarize(symlink), "unclassified")
            self.assertEqual(wrapper.summarize(d / "missing"), "unclassified")

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
        # The only privileged use of the allowlisted classifier is the
        # diagnostic failure branch; pin its immutable Git blob before the
        # protected snapshot and verify that no private summary is printed.
        self.assertIn(
            'test "$(git -C controller hash-object '
            'scripts/uniops-c2-safe-disposable-stage-receipt.py)" = '
            '9ebd246ff262b471ef35b0c60b86ef6e4dcd507f', y)
        safe_call = ('python3 "$GITHUB_WORKSPACE/controller/scripts/'
                     'uniops-c2-safe-disposable-stage-receipt.py"')
        self.assertEqual(y.count(safe_call), 1)
        self.assertIn(
            '"$RUNNER_TEMP/held-c2-private-diagnostics/summary.md"', y)
        self.assertIn("|| echo 'C2_DISPOSABLE_PHASE=unclassified'", y)
        self.assertLess(y.index('scripts/uniops-c2-safe-disposable-stage-receipt.py)" ='),
                        y.index('Read-only protected schema and roles snapshot'))
        self.assertLess(y.index('Read-only protected schema and roles snapshot'),
                        y.index(safe_call))
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
