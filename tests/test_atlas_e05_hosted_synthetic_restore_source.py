"""No production source is accessed by E05 synthetic restore source tests."""
from pathlib import Path
import importlib.util
import os
import tempfile
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/"scripts/atlas-e05-hosted-synthetic-restore.py"
spec=importlib.util.spec_from_file_location("e05_synthetic_restore",SOURCE)
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class E05HostedRestoreTests(unittest.TestCase):
    def test_reject_remote_or_named_legacy_database(self):
        for url in ("postgresql://postgres@prod.example.com:5432/postgres",
                    "postgresql://postgres@127.0.0.1:55432/postgres",
                    "postgresql://postgres@127.0.0.1:57000/noel_schema_clone",
                    "postgresql://postgres:secret@127.0.0.1:57000/postgres",
                    "postgresql://postgres@127.0.0.1:57000/postgres?sslmode=require"):
            with self.assertRaises(m.Refused,msg=url): m.local_url(url)
        self.assertEqual(m.local_url("postgresql://postgres@127.0.0.1:57000/postgres"),
                         "postgresql://postgres@127.0.0.1:57000/postgres")

    def test_requires_owned_job_folder(self):
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp)/"e05-supported-stack.example"
            p.mkdir()
            with patch.dict(os.environ,{"RUNNER_TEMP":temp}):
                self.assertEqual(m.job_root(p),p.resolve())
                with self.assertRaises(m.Refused):
                    m.job_root(Path(temp))
            with patch.dict(os.environ,{"RUNNER_TEMP":"/tmp/nowhere-nonexistent"}):
                with self.assertRaises((OSError,m.Refused)):
                    m.job_root(p)

    def test_no_symlink_or_overwrite_private_source_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            output=m.write_private(root,"roles-only.sql",m.ROLE_SQL)
            self.assertEqual(output.read_text(),m.ROLE_SQL)
            self.assertFalse(output.stat().st_mode & 0o077)
            with self.assertRaises(m.Refused):
                m.write_private(root,"roles-only.sql",m.ROLE_SQL)
            with self.assertRaises(m.Refused):
                m.write_private(root,"user-data.sql","SELECT 1;")

    def test_roles_first_schema_second_and_data_outside_snapshot(self):
        s=SOURCE.read_text()
        self.assertIn("psql(url, env, script=roles)",s)
        self.assertIn("psql(url, env, script=schema)",s)
        self.assertLess(s.index("psql(url, env, script=roles)"),
                        s.index("psql(url, env, script=schema)"))
        self.assertNotIn("INSERT INTO",m.SCHEMA_SQL)
        self.assertNotIn("auth.users",m.SCHEMA_SQL)
        self.assertIn("CREATE ROLE e05_restore_probe_role NOLOGIN",m.ROLE_SQL)
        self.assertIn("ALTER TABLE e05_restore_probe.items ENABLE ROW LEVEL SECURITY",m.SCHEMA_SQL)
        self.assertIn("USING (owner_id = auth.uid())",m.SCHEMA_SQL)
        self.assertIn("REVOKE EXECUTE ON FUNCTION",m.SCHEMA_SQL)

    def test_sql_transport_fails_closed_without_exact_local_credentials(self):
        u="postgresql://postgres@127.0.0.1:57000/postgres"
        with patch.object(m.subprocess,"run",side_effect=AssertionError("no SQL command permitted")):
            with self.assertRaises(m.Refused):
                m.psql(u,{"PGPASSWORD":"production"},sql="SELECT 1")
            with self.assertRaises(m.Refused):
                m.psql(u,{"PGPASSWORD":"postgres","NOEL_CORE_DATABASE_URL":"secret"},
                       sql="SELECT 1")

    def test_exact_anonymous_denial_and_two_rls_actor_matrix(self):
        s=SOURCE.read_text()
        self.assertIn("42501",s)
        self.assertIn("signed_role_count(OWNER)==\"1\"",s)
        self.assertIn("signed_role_count(OUTSIDER)==\"0\"",s)
        self.assertIn('SET LOCAL ROLE authenticated;',s)
        self.assertIn('SET LOCAL ROLE anon;',s)
        self.assertIn('input_sql = sql + "\\n"',s)
        self.assertIn("PRODUCTION_SCHEMA=NOT_READ; E05_SIGNED=NOT_RUN",s)

    def test_real_signed_synthetic_source_and_refusals(self):
        import base64
        import json
        import uuid
        good={"API_URL":"http://127.0.0.1:54321","ANON_KEY":"eyJ"+"a"*48}
        self.assertEqual(m.local_api_key(good,54321),good["ANON_KEY"])
        for wrong in ({"API_URL":"https://example.com","ANON_KEY":good["ANON_KEY"]},
                      {"API_URL":"http://127.0.0.1:54322","ANON_KEY":good["ANON_KEY"]},
                      {"API_URL":good["API_URL"],"SERVICE_ROLE_KEY":"secret"},
                      {"API_URL":good["API_URL"],"ANON_KEY":"short"}):
            with self.assertRaises(m.Refused):m.local_api_key(wrong,54321)
        u=str(uuid.uuid4()); sid=str(uuid.uuid4())
        def token(claims):
            body=base64.urlsafe_b64encode(json.dumps(claims).encode()).decode().rstrip("=")
            return "eyJhbGciOiJIUzI1NiJ9."+body+".fakesig"
        self.assertEqual(m.jwt_claims(token(
            {"sub":u,"session_id":sid,"role":"authenticated"})),(u,sid))
        for claims in ({"sub":u,"session_id":sid,"role":"anon"},
                       {"sub":u,"role":"authenticated"},
                       {"sub":"not-uuid","session_id":sid,"role":"authenticated"}):
            with self.assertRaises(m.Refused):m.jwt_claims(token(claims))
        source=SOURCE.read_text()
        self.assertIn('"/auth/v1/token?grant_type=password"',source)
        self.assertIn('"/rest/v1/rpc/e05_probe_owned_count"',source)
        self.assertIn("auth.sessions WHERE id IN",source)
        self.assertIn("SECURITY INVOKER",source)
        self.assertIn("public.e05_probe_owned_count() FROM PUBLIC, anon",source)
        self.assertIn("NOT has_function_privilege('anon'",source)
        self.assertIn("ANON_RPC=DENIED",source)
        self.assertNotIn("SECURITY DEFINER",source)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY",source)
        with patch.object(m.subprocess,"run",side_effect=AssertionError("No process")):
            with self.assertRaises(m.Refused):
                m.run_signed_synthetic_auth_probe(
                    "postgresql://postgres@production.example.com:5432/postgres",
                    {},Path("/tmp"),54321,Path("/tmp/project"))

    def test_restore_not_run_on_checkout_or_nonlocal_url(self):
        with patch.object(m.subprocess,"run",side_effect=AssertionError("should not execute")):
            with self.assertRaises(m.Refused):
                m.run_synthetic_restore("postgresql://postgres@host:5432/postgres",{},Path("/tmp"))

if __name__=="__main__":
    unittest.main()
