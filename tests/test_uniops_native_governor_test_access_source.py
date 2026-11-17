#!/usr/bin/env python3
"""No-DB contract for source-owned fictional governor Personal Atlas access."""
import importlib.util
from pathlib import Path
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
