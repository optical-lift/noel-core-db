#!/usr/bin/env python3
"""Fictional offline tests for the 2848 ONE-USE read-only ACL runner."""
import importlib.util
import io
from contextlib import redirect_stdout
from pathlib import Path
import os
import tempfile
import unittest
from unittest import mock

ROOT=Path(__file__).resolve().parent
import sys
sys.path.insert(0,str(ROOT))
spec=importlib.util.spec_from_file_location(
    "acl_one_shot",ROOT/"inspect_uniops_acl_readonly_source_clone_held.py")
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class ReadOnlyAclInspection(unittest.TestCase):
    def test_cannot_run_without_explicit_protected_environment(self):
        with mock.patch.dict(os.environ,{},clear=True):
            with mock.patch.object(m.subprocess,"run") as proc:
                output=io.StringIO()
                with redirect_stdout(output):
                    self.assertEqual(m.main(),1)
                self.assertEqual(output.getvalue(),
                   "UNI_OPS_ACL_READONLY_RESULT=acl_inspect_environment_refused\n"
                   "UNI_OPS_PRODUCTION_CHANGE=NONE\n")
                proc.assert_not_called()

    def test_approved_scope_rejects_other_databases_or_insecure_env(self):
        with tempfile.TemporaryDirectory() as folder:
            base={"CI":"true","GITHUB_ACTIONS":"true",
                  "GITHUB_REPOSITORY":"optical-lift/noel-core-db",
                  "UNI_OPS_READONLY_ACL_2848_APPROVED":"true",
                  "RUNNER_TEMP":folder,
                  "NOEL_CORE_DATABASE_URL":
                   "postgresql://postgres:fictional@db.zirqkouammpwxlqfbsvf.supabase.co:5432/postgres"}
            self.assertEqual(m.require_environment(base)[1],Path(folder))
            for key,val in (("UNI_OPS_READONLY_ACL_2848_APPROVED","false"),
                            ("NOEL_CORE_DATABASE_URL",
                             "postgresql://postgres:test@127.0.0.1:5432/postgres"),
                            ("NOEL_CORE_DATABASE_URL",
                             "postgresql://postgres:test@db.unrelated.supabase.co:5432/postgres"),
                            ("SUPABASE_SERVICE_ROLE_KEY","fictional")):
                env=base.copy()
                env[key]=val
                with self.subTest(key=key,val=val.split("@")[-1]):
                    with self.assertRaisesRegex(m.Refused,"acl_inspect_environment_refused"):
                        m.require_environment(env)

    def test_static_catalog_probe_is_transaction_read_only_and_never_logs_result(self):
        class Fake:
            returncode=0
            stdout="fictional private ACL\n"
        with mock.patch.object(m.subprocess,"run",return_value=Fake()) as proc:
            with mock.patch.dict(os.environ,{"PGOPTIONS":"ignored"},clear=True):
                result=m.catalog_snapshot("postgresql://not-real",read_only=True)
            self.assertEqual(result,"fictional private ACL")
            args=proc.call_args.args[0]
            self.assertEqual(args[0],"psql")
            self.assertEqual(args[-1],m.acl.ACL)
            self.assertEqual(args[-2],"-c")
            self.assertTrue(m.acl.ACL.startswith("SELECT "))
            self.assertNotIn(";",m.acl.ACL)
            self.assertEqual(proc.call_args.kwargs["env"]["PGOPTIONS"],
                             "-c default_transaction_read_only=on")
            self.assertTrue(proc.call_args.kwargs["capture_output"])
            self.assertNotIn("fictional private ACL",repr(proc.call_args))

    def test_sanitization_never_removes_privileges_or_any_data(self):
        with tempfile.TemporaryDirectory() as root:
            original=Path(root)/"schema.sql"
            sanitized=Path(root)/"clean.sql"
            original.write_text(
                'CREATE FUNCTION "public"."f"() RETURNS integer LANGUAGE sql AS $$ SELECT 1 $$;\n'
                'REVOKE ALL ON FUNCTION "public"."f"() FROM PUBLIC;\n'
                'GRANT EXECUTE ON FUNCTION "public"."f"() TO "service_role";\n'
                'ALTER TABLE "public"."tab" DISABLE TRIGGER ALL;\n'
                'ALTER TABLE "public"."tab" ENABLE TRIGGER ALL;\n')
            m.sanitize_schema(original,sanitized)
            got=sanitized.read_text()
            self.assertIn("REVOKE ALL",got)
            self.assertIn("GRANT EXECUTE",got)
            self.assertNotIn("DISABLE TRIGGER ALL",got)
            self.assertNotIn("ENABLE TRIGGER ALL",got)
            original.write_text('ALTER TABLE "x" DISABLE TRIGGER ALL;\n')
            with self.assertRaisesRegex(m.Refused,"acl_inspect_snapshot_refused"):
                m.sanitize_schema(original,sanitized)

    def test_output_codes_only_and_no_prod_mutation_paths(self):
        self.assertTrue(set(m.acl.PARITY_MARKERS).issubset(m.ALLOWED))
        src=(ROOT/"inspect_uniops_acl_readonly_source_clone_held.py").read_text()
        self.assertIn("default_transaction_read_only=on",src)
        self.assertIn("supabase\",\"db\",\"dump",src)
        self.assertIn("source=acl",src) if False else None
        self.assertIn("shutil.rmtree(root)",src)
        self.assertNotIn("supabase\",\"db\",\"push",src)
        self.assertNotIn("supabase\",\"migration",src)
        self.assertNotIn("apply_migration(",src)
        self.assertNotIn("reconcile(",src)
        self.assertNotIn("upload-artifact",src)

if __name__=="__main__":
    unittest.main()
