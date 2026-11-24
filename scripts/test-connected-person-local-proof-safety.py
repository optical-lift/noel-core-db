#!/usr/bin/env python3
"""Pure unit tests: local-only safety for held Noel #2263 proof runner.

No Docker, remote Supabase, actual psql connection, or signed credentials.
These test only that the wrapper refuses dangerous inputs and install order.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location(
    "connected_person_local_proof",ROOT/"run-connected-person-local-proof.py")
proof=importlib.util.module_from_spec(spec)
spec.loader.exec_module(proof)

GOOD="DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres\nAPI_URL=http://127.0.0.1:54321\nANON_KEY=local-synthetic-only"
REMOTE="DB_URL=postgresql://postgres:password@db.example.com:5432/postgres\nAPI_URL=https://example.supabase.co"
LOCAL_REMOTE_API="DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres\nAPI_URL=https://project.supabase.co"

class LocalProofSafety(unittest.TestCase):
    def test_refuse_remote_db(self):
        with tempfile.TemporaryDirectory() as tmp:
            stack=Path(tmp)
            (stack/"supabase").mkdir()
            (stack/"supabase/config.toml").write_text("")
            with patch.object(proof,"run",return_value=REMOTE):
                with self.assertRaisesRegex(RuntimeError,"REFUSING|Refusing"):
                    proof.local_status(stack)

    def test_refuse_remote_http(self):
        with tempfile.TemporaryDirectory() as tmp:
            stack=Path(tmp)
            (stack/"supabase").mkdir()
            (stack/"supabase/config.toml").write_text("")
            with patch.object(proof,"run",return_value=LOCAL_REMOTE_API):
                with self.assertRaisesRegex(RuntimeError,"Refusing"):
                    proof.local_status(stack)

    def test_allow_local_status_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            stack=Path(tmp)
            (stack/"supabase").mkdir()
            (stack/"supabase/config.toml").write_text("")
            with patch.object(proof,"run",return_value=GOOD):
                db,api=proof.local_status(stack)
            self.assertIn("@127.0.0.1:54322/postgres",db)
            self.assertEqual(api,"http://127.0.0.1:54321")

    def test_refuse_unexpected_user_identity_even_on_localhost(self):
        def fake_query(_db,statement):
            if "WHERE id NOT IN" in statement and "auth.users" in statement:
                return "1"
            return "0"
        with patch.object(proof,"sql",side_effect=fake_query):
            with self.assertRaisesRegex(RuntimeError,"non-fixture records"):
                proof.allowed_local_data("postgresql://postgres:p@127.0.0.1:54322/postgres")

    def test_no_installer_before_identity_gate(self):
        source=(ROOT/"run-connected-person-local-proof.py").read_text()
        self.assertLess(source.index("allowed_local_data(db_url)"),
                        source.index("file_sql(db_url, FIXTURE)"))
        self.assertLess(source.index('if not args.execute:'),
                        source.index("file_sql(db_url, FIXTURE)"))
        self.assertFalse("supabase db push" in source)
        self.assertFalse("supabase link" in source)

    def test_source_order_is_field_authority_first(self):
        self.assertEqual(proof.INSTALL_ORDER[0],
                         "connected_person_work_field_decisions_hold.sql")
        self.assertLess(proof.INSTALL_ORDER.index("candidate.sql"),
                        proof.INSTALL_ORDER.index(
                            "connected_person_my_work_existing_reader_cutover_hold.sql"))
        self.assertTrue(proof.SIGNER.name.endswith("signed-http.py"))
        self.assertTrue(all((proof.BASE/n).is_file()
                            for n in proof.INSTALL_ORDER+proof.POSTCONDITIONS))
        self.assertTrue(proof.FIXTURE.is_file())

if __name__=="__main__":
    unittest.main()
