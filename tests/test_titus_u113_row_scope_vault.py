"""U1.13 source-only scope lock and fictional private vault readiness."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/titus-u113-check-historical-row-scope.py"
VAULT = ROOT / "scripts/titus-u113-preflight-private-vault.py"
DATA = ROOT / "candidates/shared-teaching-course-clean-cutover-v1"


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


scope = module(SCRIPT, "titus_u113_scope")
vault = module(VAULT, "titus_u113_vault")


def fixture():
    a = json.loads((DATA / "U1_13_HISTORICAL_ROW_SCOPE_REVIEW_HELD.json").read_text())
    b = json.loads((DATA / "U1_13_HISTORICAL_FK_PAIRS_METADATA_ONLY.json").read_text())
    return a, b


class TestU113HistoricalScopeAndVault(unittest.TestCase):
    def test_exact_catalog_closure_and_no_capture_auth(self):
        a, b = fixture()
        result = scope.check(a, b)
        self.assertEqual((result["fkEdges"], result["dependentRelations"],
                          result["externalReferences"], result["externalParentRelations"]),
                         (168, 39, 38, 13))
        self.assertEqual(result["exactLegacyCustomerSourceRelations"], 6)
        for guard in ("customerDataAccess", "rowSelectionApproved",
                      "backupCreated", "restoredRealData", "deletionAuthorized"):
            self.assertFalse(result[guard])
        self.assertTrue(result["reviewedAtCatalogStructureOnly"])

    def test_new_unknown_dependency_rejected(self):
        a, b = fixture()
        b["foreignKeyPairs"].append(
            {"child": "titus.new_unreviewed_customer_dependency",
             "parent": "titus.customer_course_drafts_v1"}
        )
        with self.assertRaises(ValueError):
            scope.check(a, b)

    def test_removed_dependency_or_independent_parent_rejected(self):
        a, b = fixture()
        b["foreignKeyPairs"] = [x for x in b["foreignKeyPairs"]
                                if x["parent"] != "draft.song_objects"]
        with self.assertRaises(ValueError):
            scope.check(a, b)
        a, b = fixture()
        a["externalParentDispositions"].pop("auth.users")
        with self.assertRaises(ValueError):
            scope.check(a, b)

    def test_changed_source_selection_and_permission_fail_closed(self):
        a, b = fixture()
        trials = (
            ("dataCaptureAuthorized", True),
            ("deletionAuthorized", True),
            ("persistentVaultConfigured", True),
            ("customerRowsRead", True),
        )
        for key, change in trials:
            modified = copy.deepcopy(a)
            modified[key] = change
            with self.subTest(key=key), self.assertRaises(ValueError):
                scope.check(modified, b)
        altered = copy.deepcopy(a)
        altered["descendantDispositions"]["titus.programs"]["rowSelector"] = "all"
        with self.assertRaises(ValueError):
            scope.check(altered, b)
        a["protectedCustomerTableScope"].pop()
        with self.assertRaises(ValueError):
            scope.check(a, b)

    def test_private_vault_fictional_canary_and_certificate(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            d = root / "vault"
            d.mkdir(mode=0o700)
            key = root / "private-test-key.pem"
            cert = root / "public-test-cert.pem"
            subprocess.run([
                "openssl", "req", "-x509", "-newkey", "rsa:2048",
                "-nodes", "-keyout", str(key), "-out", str(cert),
                "-days", "9", "-subj", "/CN=fictional-u113-vault-test",
            ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            result = vault.check_vault(str(d), str(cert), fictional_test=True)
            self.assertTrue(result["fictionalCanaryRemoved"])
            self.assertFalse(result["ownerDataBackupCreated"])
            self.assertEqual(list(d.iterdir()), [])
            d.chmod(0o755)
            with self.assertRaises(ValueError):
                vault.check_vault(str(d), str(cert), fictional_test=True)
            d.chmod(0o700)
            with self.assertRaises(ValueError):
                vault.check_vault(str(d), str(root / "missing.pem"),
                                  fictional_test=True)
            # Even a private temp folder must not be classified durable.
            with self.assertRaises(ValueError):
                vault.check_vault(str(d), str(cert), fictional_test=False)

    def test_no_database_dml_secret_or_data_client_in_source(self):
        source = SCRIPT.read_text() + VAULT.read_text()
        for prohibited in (
            "NOEL_CORE_DATABASE_URL", "SUPABASE_DB_URL",
            "SUPABASE_SERVICE_ROLE_KEY", "pg_dump", "pg_restore",
            "execute_sql(", "apply_migration(", "DELETE FROM",
            "DROP TABLE", "supabase db push",
        ):
            self.assertNotIn(prohibited, source)


if __name__ == "__main__":
    unittest.main()
