"""U1.9 HELD source-only checks. Never connects to production or Supabase."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
ASSEMBLER = ROOT / "scripts/prepare-titus-u1-protected-clone-source.py"
SOURCE = ROOT / "candidates/shared-teaching-course-clean-cutover-v1"
POST = SOURCE / "U1_9_PROTECTED_SCHEMA_SHAPE_POSTCONDITIONS_TEST_ONLY.sql"


class TestHeldU1ProtectedBundle(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.head = subprocess.check_output(
            ("git", "-C", str(ROOT), "rev-parse", "HEAD"), text=True).strip()

    def run_assembly(self, tmp, *, sha=None, env=None, scope=None, output=None):
        outfile = output or (
            Path(tmp) / "20261118095959_shared_titus_u1_full_schema_TEST_ONLY.sql")
        manifest = Path(tmp) / "manifest.json"
        e = {k: v for k, v in os.environ.items() if k not in (
            "NOEL_CORE_DATABASE_URL", "SUPABASE_DB_URL", "DATABASE_URL",
            "SUPABASE_ACCESS_TOKEN", "SUPABASE_SECRET_KEY",
            "SUPABASE_SERVICE_ROLE_KEY",
        )}
        if env:
            e.update(env)
        return subprocess.run([
            sys.executable, str(ASSEMBLER),
            "--source-root", str(ROOT),
            "--expected-sha", sha or self.head,
            "--test-scope", scope or "titus_u1_protected_source_shape_test_only_v1",
            "--output", str(outfile),
            "--manifest", str(manifest),
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=e), outfile, manifest

    def test_assembled_exact_source_no_release_migration(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc, outfile, manifest = self.run_assembly(tmp)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertTrue(outfile.is_file())
            self.assertTrue(manifest.is_file())
            package = outfile.read_text()
            report = json.loads(manifest.read_text())
            self.assertEqual(report["sourceSha"], self.head)
            self.assertFalse(report["productionAccess"])
            self.assertFalse(report["releaseAuthorized"])
            self.assertFalse(report["actualSignedProtectedSchemaTested"])
            self.assertEqual(len(report["sourceSegments"]), 6)
            self.assertEqual(
                hashlib.sha256(package.encode()).hexdigest(),
                report["scratchSqlSha256"])
            self.assertIn("TEST ONLY; NOT A RELEASABLE MIGRATION", package)
            self.assertEqual(package.count("-- SOURCE SEGMENT START"), 6)
            self.assertEqual(package.count("-- SOURCE SEGMENT END"), 6)
            self.assertEqual(package.count("SET app.shared_course_clone"), 1)
            for segment in report["sourceSegments"]:
                exact = ROOT / segment["source"]
                self.assertEqual(
                    hashlib.sha256(exact.read_bytes()).hexdigest(),
                    segment["sha256"])
                self.assertIn(exact.read_text().rstrip(), package)
            self.assertNotIn("supabase db push", package.lower())

    def test_deny_wrong_commit_scope_or_existing_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            for kwargs in (
                {"sha": "0" * 40},
                {"scope": "production_release"},
                {"env": {"NOEL_CORE_DATABASE_URL": "postgresql://example.invalid/db"}},
            ):
                proc, _, _ = self.run_assembly(tmp, **kwargs)
                self.assertNotEqual(proc.returncode, 0, kwargs)
            one, outfile, _ = self.run_assembly(tmp)
            self.assertEqual(one.returncode, 0, one.stderr)
            two, _, _ = self.run_assembly(tmp)
            self.assertNotEqual(two.returncode, 0)

    def test_deny_repo_output_or_migration_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = ROOT / "20261118095959_shared_titus_u1_full_schema_TEST_ONLY.sql"
            proc, _, _ = self.run_assembly(tmp, output=path)
            self.assertNotEqual(proc.returncode, 0)

    def test_postconditions_only_scratch_acl_and_no_loss_shape(self):
        sql = POST.read_text()
        for statement in (
            "TEST ONLY", "app.shared_course_clone",
            "titus.institution_account_manager_governance_v1",
            "titus.institution_account_admissions_v1",
            "titus.institution_account_root_origins_v1",
            "c.relrowsecurity", "has_table_privilege",
            "has_function_privilege",
            "titus.customer_workspaces_v1",
            "titus.customer_course_drafts_v1",
            "titus.customer_workspace_entitlements_v1",
            "NOT signed behavior or release",
        ):
            self.assertIn(statement, sql)
        import re
        upper = "\n".join(line for line in sql.splitlines()
                          if not line.lstrip().startswith("--")).upper()
        for forbidden in (
            "INSERT INTO", "UPDATE ", "DELETE FROM", "CREATE TABLE",
            "ALTER TABLE", "GRANT ", "REVOKE ", "COPY ",
        ):
            # Only SQL statement heads are forbidden; error messages may
            # correctly describe a missing GRANT or forbidden UPDATE.
            self.assertIsNone(
                re.search(r"(?m)^\\s*" + re.escape(forbidden), upper),
                forbidden)


if __name__ == "__main__":
    unittest.main()
