#!/usr/bin/env python3
"""Static/refusal checks for the E05 NONFARM fixture preparer.

These do NOT prove a signed test, a local schema-clone, source RLS or browser.
"""
import importlib.util
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
FILE = ROOT / "scripts/prepare-atlas-e05-nonfarm-clone-fixture.py"
spec = importlib.util.spec_from_file_location("e05_nonfarm_preparer", FILE)
e05 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(e05)


class E05FixtureSourceTest(unittest.TestCase):
    def test_valid_and_denied_database_urls(self):
        valid = "postgresql://fixture:local@127.0.0.1:55433/atlas_e05_12345678"
        self.assertEqual(e05.db_name(valid), "atlas_e05_12345678")
        for invalid in (
            "postgresql://fixture:local@127.0.0.1:55433/postgres",
            "postgresql://fixture:local@127.0.0.1:55433/noel_schema_clone",
            "postgresql://fixture:local@localhost:55433/atlas_e05_12345678",
            "postgresql://fixture:local@example.com:55433/atlas_e05_12345678",
            "postgresql://fixture:local@127.0.0.1:55433/atlas_e05_12345678?sslmode=require",
            "postgresql://fixture:local@127.0.0.1:55433/atlas_e05_12345678/other",
            "https://127.0.0.1:55433/atlas_e05_12345678",
        ):
            with self.subTest(invalid=invalid), self.assertRaises(e05.Refused):
                e05.db_name(invalid)

    def test_manifest_is_exact_atlas_runner_contract(self):
        f = e05.manifest()
        self.assertEqual(set(f), {
            "contractVersion", "organizationId", "ledgerId", "foreignLedgerId",
            "workItemId", "workerPersonId", "workerSeatId", "actorIds", "title"
        })
        self.assertEqual(f["contractVersion"], "atlas_e05_nonfarm_clone_fixture_v1")
        self.assertEqual(set(f["actorIds"]), {"governor", "recipient", "outsider"})
        self.assertEqual(len(set(f["actorIds"].values())), 3)
        self.assertTrue(f["title"].startswith("E05 SYNTHETIC "))
        self.assertNotEqual(f["ledgerId"], f["foreignLedgerId"])

    def test_test_only_sql_contains_one_nonfarm_original(self):
        sql = e05.FIXTURE.read_text(encoding="utf-8").lower()
        self.assertEqual(sql.count("insert into atlas.work_items"), 1)
        self.assertEqual(sql.count("insert into atlas.company_work_native_ledger_relevance"), 1)
        self.assertNotIn("insert into atlas.farms", sql)
        self.assertNotIn("insert into ledger.actions", sql)
        self.assertNotIn("grant ", sql)
        self.assertNotIn("create policy", sql)
        self.assertIn("ordinary_company_work_worker_attestation_v1", sql)
        self.assertIn("e05 synthetic nonprofit archive review", sql)
        self.assertIn("where organization_id='e5200000-0000-4000-8000-000000000801'::uuid", sql)

    def test_never_allow_real_email_or_shared_password(self):
        values = {
            "ATLAS_E05_GOVERNOR_EMAIL": "e05-governor-one@example.invalid",
            "ATLAS_E05_RECIPIENT_EMAIL": "e05-recipient-two@example.invalid",
            "ATLAS_E05_OUTSIDER_EMAIL": "e05-outsider-three@example.invalid",
            "ATLAS_E05_GOVERNOR_PASSWORD": "governor-local-1234",
            "ATLAS_E05_RECIPIENT_PASSWORD": "recipient-local-5678",
            "ATLAS_E05_OUTSIDER_PASSWORD": "outsider-local-4321",
        }
        with patch.dict("os.environ", values, clear=True):
            self.assertEqual(len(e05.credentials()), 3)
            sql = e05.auth_sql(e05.credentials())
            self.assertEqual(sql.count("UPDATE auth.users"), 3)
            self.assertEqual(sql.count("INSERT INTO auth.identities"), 3)
            self.assertIn("extensions.crypt", sql)
            self.assertNotIn("service_role", sql)
        with patch.dict("os.environ", {
            **values, "ATLAS_E05_GOVERNOR_EMAIL": "someone@gmail.com"
        }, clear=True):
            with self.assertRaises(e05.Refused):
                e05.credentials()
        with patch.dict("os.environ", {
            **values, "ATLAS_E05_GOVERNOR_PASSWORD": "recipient-local-5678"
        }, clear=True):
            with self.assertRaises(e05.Refused):
                e05.credentials()

    def test_guard_requires_fresh_pgdata_and_empty_tables(self):
        with tempfile.TemporaryDirectory() as root:
            temp = Path(root)
            pgdata = temp / "e05-pgdata"
            pgdata.mkdir()
            good = ("atlas_e05_12345678|127.0.0.1|" + str(pgdata))
            with patch.object(e05, "psql", side_effect=[good, "0|0|0|0|0"]):
                self.assertEqual(
                    e05.guard(
                        "postgresql://test:local@127.0.0.1:55433/atlas_e05_12345678",
                        temp), "atlas_e05_12345678")
            with patch.object(e05, "psql", side_effect=[good, "0|0|1|0|0"]):
                with self.assertRaises(e05.Refused):
                    e05.guard(
                        "postgresql://test:local@127.0.0.1:55433/atlas_e05_12345678",
                        temp)
            with patch.object(e05, "psql", return_value="atlas_e05_12345678|127.0.0.1|/tmp"):
                with self.assertRaises(e05.Refused):
                    e05.guard(
                        "postgresql://test:local@127.0.0.1:55433/atlas_e05_12345678",
                        temp)

    def test_database_guard_uses_exact_normalized_loopback(self):
        import inspect
        source = inspect.getsource(e05.guard)
        self.assertIn("host(inet_server_addr())", source)
        self.assertIn('fields[1] == "127.0.0.1"', source)

    def test_job_temp_cannot_be_a_symlink(self):
        with tempfile.TemporaryDirectory() as root:
            real = Path(root) / "real-runner-temp"
            real.mkdir()
            link = Path(root) / "symlink-to-runner-temp"
            link.symlink_to(real, target_is_directory=True)
            with patch.dict(os.environ, {"RUNNER_TEMP": str(link)}):
                with self.assertRaises(e05.Refused):
                    e05.job_temp()

    def test_manifest_is_private_from_creation_and_does_not_store_credentials(self):
        with tempfile.TemporaryDirectory() as root:
            temp = Path(root)
            data = temp / "postgres-owned-temp"
            data.mkdir()
            report = temp / "e05-fixture.json"
            db = "postgresql://fixture:local@127.0.0.1:55433/atlas_e05_12345678"
            variables = {
                "RUNNER_TEMP": str(temp),
                "ATLAS_E05_GOVERNOR_EMAIL": "e05-governor-one@example.invalid",
                "ATLAS_E05_RECIPIENT_EMAIL": "e05-recipient-two@example.invalid",
                "ATLAS_E05_OUTSIDER_EMAIL": "e05-outsider-three@example.invalid",
                "ATLAS_E05_GOVERNOR_PASSWORD": "governor-local-1234",
                "ATLAS_E05_RECIPIENT_PASSWORD": "recipient-local-5678",
                "ATLAS_E05_OUTSIDER_PASSWORD": "outsider-local-4321",
            }
            mock_sql = [
                "atlas_e05_12345678|127.0.0.1|" + str(data),
                "0|0|0|0|0",
                "",
                "0|1|1",
            ]
            with patch.dict(os.environ, variables), \
                 patch("sys.argv", ["e05", "--db-url", db, "--output", str(report)]), \
                 patch.object(e05, "psql", side_effect=mock_sql) as called:
                e05.main()
            self.assertEqual(stat.S_IMODE(report.stat().st_mode), 0o600)
            self.assertEqual(json.loads(report.read_text()), e05.manifest())
            self.assertEqual(len(called.call_args_list), 4)
            transaction = called.call_args_list[2].args[1]
            self.assertTrue(transaction.startswith("BEGIN;"))
            self.assertTrue(transaction.rstrip().endswith("COMMIT;"))
            self.assertNotIn("real-person@", report.read_text())
            self.assertNotIn("local-1234", report.read_text())
            self.assertNotIn("local-5678", report.read_text())
            with patch.dict(os.environ, variables), \
                 patch("sys.argv", ["e05", "--db-url", db, "--output", str(report)]), \
                 patch.object(e05, "psql", side_effect=AssertionError("Unnecessary SQL")):
                with self.assertRaises(e05.Refused):
                    e05.main()



if __name__ == "__main__":
    unittest.main()
