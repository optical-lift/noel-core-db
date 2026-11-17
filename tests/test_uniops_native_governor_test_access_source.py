#!/usr/bin/env python3
"""No-DB contract for source-owned fictional governor Personal Atlas access."""
import importlib.util
from pathlib import Path
import os
from unittest import mock
import subprocess
import sys
import unittest

MODULE=Path(__file__).resolve().parent/"uniops_native_governor_test_access_local_held.py"
spec=importlib.util.spec_from_file_location("disposable_governor_access",MODULE)
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class NativeGovernorAccessSourceTests(unittest.TestCase):
    def test_refuses_production_or_noncanonical_local_host(self):
        self.assertTrue(module.local_only(
            "postgresql://postgres:postgres@127.0.0.1:54322/postgres"))
        for url in ("postgresql://db.example.com/postgres",
             "postgresql://postgres:password@localhost:54322/postgres",
             "postgresql://postgres:password@127.0.0.2:54322/postgres",
             "postgresql://postgres:password@127.0.0.1:54322/other",
             "https://127.0.0.1:54322/postgres",""):
            self.assertFalse(module.local_only(url),url)

    def test_uses_existing_privileged_grant_not_purchase_or_direct_dml(self):
        queries=module.source_queries()
        grant=queries["grant"]
        self.assertIn("public.grant_personal_atlas_access_v1(",grant)
        self.assertIn("disposableCloneOnly",grant)
        self.assertIn(module.C1_PRINCIPAL,grant)
        self.assertIn(module.GRANT_KIND,grant)
        self.assertIn("authority_kind='root_governing'",queries["actor"])
        self.assertIn("p.user_id=",queries["actor"])
        self.assertIn("p.person_id=",queries["actor"])
        self.assertIn(module.C1_LEDGER,queries["actor"])
        self.assertIn("NOT has_function_privilege('anon'",queries["acl"])
        self.assertIn("NOT has_function_privilege('authenticated'",queries["acl"])
        self.assertIn("has_function_privilege('postgres'",queries["acl"])
        self.assertIn("personal_atlas_access_grants",queries["before"])
        self.assertIn("personal_atlas_access_grants",queries["after"])
        self.assertIn(module.C1_WORKER,queries["negatives"])
        self.assertIn(module.C1_OUTSIDER,queries["negatives"])
        source=MODULE.read_text()
        for forbidden in ("INSERT INTO atlas.personal_atlas_purchases",
         "INSERT INTO atlas.personal_atlas_access_grants",
         "GRANT EXECUTE", "DROP TABLE", "ALTER TABLE", "service_role:"):
            self.assertNotIn(forbidden,source)
        self.assertEqual(source.count("SELECT public.grant_personal_atlas_access_v1"),1)

    def test_acl_failure_is_bounded_and_never_enters_grant(self):
        q=module.source_queries()
        for key in ("acl_exists","acl_anon","acl_authenticated","acl_postgres"):
            self.assertTrue(q[key].startswith("SELECT CASE WHEN "))
            self.assertIn(module.RPC,q[key])
        base={"acl_exists":"1","acl_anon":"0","acl_authenticated":"0",
              "acl_postgres":"1"}
        cases=(
            ({"acl_exists":"0"},"source_function_missing"),
            ({"acl_anon":"1"},"source_anon_exposed"),
            ({"acl_authenticated":"1"},"source_authenticated_exposed"),
            ({"acl_postgres":"0"},"source_postgres_denied"),
            ({"acl_anon":"1","acl_authenticated":"1"},"source_acl_multiple_mismatches"),
            ({}, "source_acl_inconsistent"),
            ({"acl_exists":"bad"},"source_acl_probe_refused"),
            ({"acl_postgres":""},"source_acl_probe_refused"),
        )
        for changes,expected in cases:
            vals={**base,**changes}
            used=[]
            def read(_db,query):
                used.append(query)
                return vals[next(k for k in base if q[k]==query)]
            with self.subTest(expected=expected):
                with mock.patch.object(module,"run_local",side_effect=read):
                    self.assertEqual(module.classify_acl_refusal("local-test",q),expected)
            self.assertNotIn(q["grant"],used)
        with mock.patch.object(module,"run_local",side_effect=RuntimeError("PRIVATE")):
            self.assertEqual(module.classify_acl_refusal("local-test",q),
                             "source_acl_probe_refused")

    def test_refused_acl_does_not_issue_grant(self):
        q=module.source_queries()
        vals={"actor":"1","acl":"0","acl_exists":"1","acl_anon":"1",
              "acl_authenticated":"0","acl_postgres":"1"}
        used=[]
        def read(_db,query):
            used.append(query)
            return vals[next(k for k in vals if q[k]==query)]
        env={"CI":"true","GITHUB_ACTIONS":"true",
             "GITHUB_REPOSITORY":"optical-lift/noel-core-db",
             "ATLAS_NATIVE_GOVERNOR_TEST_GRANT_ENABLED":"true"}
        with mock.patch.dict(os.environ,env,clear=True):
            with mock.patch.object(module,"run_local",side_effect=read):
                with self.assertRaisesRegex(RuntimeError,"Canonical privileged grant source unavailable"):
                    module.authorize("postgresql://postgres:dummy@127.0.0.1:54322/postgres")
                self.assertEqual(module.stage,"source_anon_exposed")
        self.assertNotIn(q["grant"],used)
        self.assertNotIn(q["before"],used)

    def test_acl_sql_exception_is_finite_and_never_enters_grant(self):
        q=module.source_queries()
        used=[]
        def read(_db,query):
            used.append(query)
            if query==q["actor"]:
                return "1"
            raise RuntimeError("PRIVATE")
        env={"CI":"true","GITHUB_ACTIONS":"true",
             "GITHUB_REPOSITORY":"optical-lift/noel-core-db",
             "ATLAS_NATIVE_GOVERNOR_TEST_GRANT_ENABLED":"true"}
        with mock.patch.dict(os.environ,env,clear=True):
            with mock.patch.object(module,"run_local",side_effect=read):
                with self.assertRaises(RuntimeError):
                    module.authorize("postgresql://postgres:dummy@127.0.0.1:54322/postgres")
                self.assertEqual(module.stage,"source_acl_probe_refused")
        self.assertNotIn(q["grant"],used)

    def test_unauthorized_caller_does_not_connect_or_write(self):
        script=subprocess.run([sys.executable,str(MODULE),"--db-url",
          "postgresql://postgres:password@remote.example:54322/postgres"],
          text=True,capture_output=True,timeout=15)
        self.assertNotEqual(script.returncode,0)
        self.assertEqual(script.stderr,"")
        self.assertIn("ATLAS_NATIVE_GOVERNOR_GRANT_STAGE=environment",script.stdout)
        self.assertNotIn("Traceback",script.stdout)

    def test_source_is_only_for_explicit_owner_approved_local_clone(self):
        source=MODULE.read_text()
        for item in ("ATLAS_NATIVE_GOVERNOR_TEST_GRANT_ENABLED",
          "GITHUB_ACTIONS","GITHUB_REPOSITORY","NOEL_CORE_DATABASE_URL",
          "SUPABASE_SERVICE_ROLE_KEY","ATLAS_NATIVE_GOVERNOR_AUTHORIZED_TEST_GRANT=PASS"):
            self.assertIn(item,source)


if __name__=="__main__":
    unittest.main()
