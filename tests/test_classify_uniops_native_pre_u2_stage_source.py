#!/usr/bin/env python3
"""No-DB red-team tests for private single-value native U2-stage classifier."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parent
MOD=ROOT/"classify_uniops_native_pre_u2_stage_held.py"
INSTALLER=ROOT/"install_uniops_native_notebook_validator_copy_held.py"
spec=importlib.util.spec_from_file_location("held_pre_u2_diag",MOD)
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class PreU2FailureStages(unittest.TestCase):
    def test_no_private_detail_when_no_stage_is_present(self):
        with tempfile.TemporaryDirectory() as t:
            self.assertEqual(m.diagnose(t),("not_recorded","not_applicable"))

    def test_all_authorized_pre_u2_markers_are_finite(self):
        with tempfile.TemporaryDirectory() as t:
            for gate in sorted(m.GATES):
                (Path(t)/m.MARKER).write_text("UNI_OPS_NATIVE_PRE_U2_STAGE="+gate+"\n")
                expected=(gate,"not_recorded") if gate=="grant_source_refused" else (gate,"not_applicable")
                self.assertEqual(m.diagnose(t),expected)

    def test_real_grant_source_stage_reports_only_source_authored_enum(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)
            (p/m.MARKER).write_text("UNI_OPS_NATIVE_PRE_U2_STAGE=grant_source_refused\n")
            for stage in sorted(m.GRANT_STAGES):
                (p/m.GRANT_LOG).write_text(
                    "BLOCKED ATLAS_NATIVE_GOVERNOR_TEST_GRANT=NOT_VERIFIED\n"
                    "ATLAS_NATIVE_GOVERNOR_GRANT_STAGE="+stage+"\n"
                    "PRIVATE ERROR: do not print a user ID, SQL statement or JWT\n")
                self.assertEqual(m.diagnose(t),("grant_source_refused",stage))
            (p/m.GRANT_LOG).write_text(
                "ATLAS_NATIVE_GOVERNOR_GRANT_STAGE=source_acl\n"
                "ATLAS_NATIVE_GOVERNOR_GRANT_STAGE=postcondition\n")
            self.assertEqual(m.diagnose(t),("grant_source_refused","unclassified"))
            for injected in ("source_anon_exposed PRIVATE", "unknown_acl",
                             "source_postgres_denied\r", "source_acl_probe_refusedX"):
                (p/m.GRANT_LOG).write_text(
                    "ATLAS_NATIVE_GOVERNOR_GRANT_STAGE="+injected+"\n")
                self.assertEqual(m.diagnose(t),("grant_source_refused","unclassified"))

    def test_acl_substages_tied_only_to_grant_refusal(self):
        expected={"source_function_missing","source_anon_exposed",
                  "source_authenticated_exposed","source_postgres_denied",
                  "source_acl_multiple_mismatches","source_acl_probe_refused",
                  "source_acl_inconsistent","clone_acl_precondition_refused"}
        self.assertTrue(expected.issubset(m.GRANT_STAGES))
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)
            (p/m.GRANT_LOG).write_text(
                "ATLAS_NATIVE_GOVERNOR_GRANT_STAGE=source_anon_exposed\n")
            (p/m.MARKER).write_text(
                "UNI_OPS_NATIVE_PRE_U2_STAGE=projection_install_refused\n")
            self.assertEqual(m.diagnose(t),("projection_install_refused","not_applicable"))

    def test_untrusted_text_and_symlinks_do_not_become_diagnostics(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)
            for raw in (
                "UNI_OPS_NATIVE_PRE_U2_STAGE=SOURCE SQL ERROR: secret\n",
                "UNI_OPS_NATIVE_PRE_U2_STAGE=grant_source_refused\nINJECTED\n",
                "UNI_OPS_NATIVE_PRE_U2_STAGE=grant_source_refused\r\n",
                "UNI_OPS_NATIVE_PRE_U2_STAGE=grant_source_refused\n"*300,
                "UNI_OPS_NATIVE_PRE_U2_STAGE=unknown_new_stage\n",
            ):
                (p/m.MARKER).write_text(raw)
                self.assertEqual(m.diagnose(t),("unclassified","not_applicable"))
            marker=p/m.MARKER
            marker.unlink()
            marker.symlink_to(p/"private")
            self.assertEqual(m.diagnose(t),("not_recorded","not_applicable"))

    def test_installer_runs_before_signed_u2_and_preserves_protected_scope(self):
        content=INSTALLER.read_text()
        self.assertEqual(content.count("native_pre_u2_stage projection_fingerprint_check"),1)
        self.assertEqual(content.count("native_pre_u2_stage projection_source_mismatch"),1)
        self.assertEqual(content.count("native_pre_u2_stage projection_install_refused"),1)
        self.assertEqual(content.count("native_pre_u2_stage grant_source_refused"),2)
        # One refusal belongs to clone ACL source parity; the second remains
        # the original canonical entitlement grant source refusal.
        self.assertLess(content.index("reconcile_uniops_native_governor_acl_local_held.py"),
                        content.index("uniops_native_governor_test_access_local_held.py\" \\"))
        self.assertEqual(content.count("native_pre_u2_stage signed_u2_ready"),1)
        self.assertIn("302be9714957f5bf76d665092c9609b1",content)
        self.assertIn("pg_get_functiondef(p.oid)",content)
        self.assertIn("uniops-native-pre-u2-stage.safe",content)
        self.assertIn('if ! psql "$database_url" -X -v ON_ERROR_STOP=1',content)
        self.assertIn("ATLAS_NATIVE_GOVERNOR_TEST_GRANT_ENABLED=true",content)
        self.assertIn("ATLAS_NATIVE_NOTEBOOK_FICTIONAL_ONLY:-",content)
        self.assertIn("No database access, network, credentials, SQL",MOD.read_text())
        self.assertNotIn("supabase db push",content)
        self.assertNotIn("apply_migration",content)
        self.assertNotIn("https://",content)

if __name__=="__main__":
    unittest.main()
