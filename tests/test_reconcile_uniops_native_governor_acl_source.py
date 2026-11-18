#!/usr/bin/env python3
"""Offline, source-only negative tests for one exact clone-function ACL repair."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock

ROOT=Path(__file__).resolve().parent
MOD=ROOT/"reconcile_uniops_native_governor_acl_local_held.py"
MIGRATION=ROOT.parent/"supabase/migrations/20260912203347_personal_atlas_access_grants_v1.sql"
spec=importlib.util.spec_from_file_location("clone_acl_reconcile",MOD)
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class CloneAclSource(unittest.TestCase):
    def test_canonical_source_is_byte_pinned_and_has_exact_acl(self):
        digest=m.source_fingerprint(MIGRATION)
        self.assertRegex(digest,r"^[0-9a-f]{32}$")
        sql=m.guarded_sql(digest)
        self.assertIn(m.REVOKE,sql)
        self.assertIn(m.GRANT,sql)
        self.assertEqual(sql.count("REVOKE ALL ON FUNCTION".lower()),1)
        self.assertIn("p.proacl IS NULL",sql)
        self.assertIn("p.proacl IS NOT NULL",sql)
        self.assertIn("pg_catalog.aclexplode(p.proacl)",sql)
        self.assertIn("'service_role'::regrole AND g.is_grantable",sql)
        self.assertIn("g.grantee NOT IN",sql)
        self.assertIn("md5(p.prosrc)='"+digest+"'",sql)
        self.assertIn("DO $clone_acl_guard$",sql)
        self.assertNotIn("ALTER DEFAULT PRIVILEGES",sql)
        self.assertNotIn("CREATE ROLE",sql)
        self.assertNotIn("INSERT INTO",sql)
        self.assertNotIn("supabase db push",sql)
        with self.assertRaises(ValueError):
            m.source_fingerprint(ROOT/"does_not_exist.sql")
        with self.assertRaises(ValueError):
            m.guarded_sql("untrusted")

    def test_exact_default_only_and_all_other_acl_shapes_refused(self):
        digest=m.source_fingerprint(MIGRATION)
        prefix="postgres|t|"+digest+"|"
        self.assertEqual(m.classify(prefix+"t|t|t|t|t|t",digest),
                         "default_public_execute")
        self.assertEqual(m.classify(prefix+"f|f|f|t|t|t",digest),"protected")
        self.assertEqual(m.classify(prefix+"f|f|f|t|t|f",digest),"refused",
                         "A separate EXECUTE grantee cannot qualify as protected")
        self.assertEqual(m.classify_refusal(prefix+"f|f|f|t|t|f",digest),
                         "clone_acl_nondefault_privileges")
        for bad in (prefix+"f|t|t|t|t|t",prefix+"t|f|t|t|t|t",
                    prefix+"t|t|f|t|t|t",prefix+"t|t|t|f|t|t",
                    prefix+"t|t|t|t|f|t","another|t|"+digest+"|t|t|t|t|t|t",
                    "postgres|f|"+digest+"|t|t|t|t|t|t",
                    prefix.replace(digest,"0"*32)+"t|t|t|t|t|t",
                    "","postgres|t|"+digest+"|t|t|t|t"):
            with self.subTest(bad=bad):
                self.assertEqual(m.classify(bad,digest),"refused")

    def test_safe_refusal_categories_without_acl_repair(self):
        digest=m.source_fingerprint(MIGRATION)
        prefix="postgres|t|"+digest+"|"
        expected={
            "":"clone_acl_function_missing",
            "invalid row":"clone_acl_probe_refused",
            "not-postgres|t|"+digest+"|t|t|t|t|t|t":"clone_acl_owner_mismatch",
            "postgres|f|"+digest+"|t|t|t|t|t|t":"clone_acl_security_mismatch",
            "postgres|t|"+"0"*32+"|t|t|t|t|t|t":"clone_acl_body_mismatch",
            prefix+"f|t|t|t|t|t":"clone_acl_nondefault_privileges",
            prefix+"t|f|t|t|t|t":"clone_acl_default_privileges",
        }
        for observed,stage in expected.items():
            with self.subTest(stage=stage):
                self.assertEqual(m.classify(observed,digest),"refused")
                self.assertEqual(m.classify_refusal(observed,digest),stage)
                self.assertIn(stage,m.REFUSAL_STAGES)
        self.assertEqual(m.classify_refusal(None,digest),"clone_acl_probe_refused")
        self.assertNotIn("clone_acl_precondition_refused",m.REFUSAL_STAGES)

    def test_nondefault_is_an_umbrella_not_proof_of_a_live_acl_defect(self):
        # These are wholly invented function-ACL shapes, not restored real
        # role values. A non-NULL proacl is normal for canonical REVOKE/GRANT.
        digest=m.source_fingerprint(MIGRATION)
        prefix="postgres|t|"+digest+"|"
        self.assertEqual(m.classify(prefix+"f|f|f|t|t|t",digest),"protected")
        self.assertEqual(m.classify(prefix+"t|t|t|t|t|t",digest),
                         "default_public_execute")
        # An unexpected effective role state, not merely a nondefault ACL,
        # triggers the historical first-refusal category.
        for flags in (
            "f|t|f|t|t|t",  # fictional anonymous exposure
            "f|f|t|t|t|t",  # fictional authenticated exposure
            "f|f|f|f|t|t",  # fictional postgres mismatch
            "f|f|f|t|f|t",  # fictional service-role mismatch
            "f|t|t|t|f|t",  # fictional simultaneous differences
            "f|f|f|t|t|f",  # unrelated EXECUTE grantee or grant option
        ):
            with self.subTest(shape=flags):
                snap=prefix+flags
                self.assertEqual(m.classify(snap,digest),"refused")
                self.assertEqual(m.classify_refusal(snap,digest),
                                 "clone_acl_nondefault_privileges")
                env={"CI":"true","GITHUB_ACTIONS":"true",
                    "GITHUB_REPOSITORY":"optical-lift/noel-core-db",
                    "ATLAS_NATIVE_NOTEBOOK_FICTIONAL_ONLY":"true",
                    "ATLAS_NATIVE_GOVERNOR_CLONE_ACL_RECONCILE_ENABLED":"true"}
                with mock.patch.dict("os.environ",env,clear=True):
                    with mock.patch.object(m,"psql",
                            side_effect=["postgres|postgres|f",snap]) as calls:
                        with self.assertRaisesRegex(
                                ValueError,"clone_acl_nondefault_privileges"):
                            m.reconcile(
                                "postgresql://postgres:test@127.0.0.1:54322/postgres",
                                MIGRATION)
                        self.assertEqual(calls.call_count,2,
                            "No transaction or ACL write after refusal")
        # Exactly which imaginary flag differs is deliberately NOT logged
        # by the current category, and the real protected run published none.

    def test_readonly_source_clone_acl_observations_classify_without_db_or_private_output(self):
        digest=m.source_fingerprint(MIGRATION)
        prefix="postgres|t|"+digest+"|"
        canonical=prefix+"f|f|f|t|t|t"
        default=prefix+"t|t|t|t|t|t"
        extra=prefix+"f|f|f|t|t|f"
        anonymous=prefix+"f|t|f|t|t|t"
        cases=(
            ((canonical,canonical),"acl_parity_canonical_observations_match"),
            ((default,default),"acl_parity_noncanonical_observations_match"),
            ((extra,extra),"acl_parity_noncanonical_observations_match"),
            ((canonical,extra),"acl_parity_clone_differs_from_canonical_source"),
            ((extra,canonical),"acl_parity_clone_canonical_source_not"),
            ((anonymous,extra),"acl_parity_noncanonical_observations_differ"),
            ((canonical,""),"acl_parity_source_unverified"),
            (("other|t|"+digest+"|f|f|f|t|t|t",canonical),
                "acl_parity_source_unverified"),
            ((canonical,prefix+"f|f|f|t|t|maybe"),
                "acl_parity_source_unverified"),
        )
        with mock.patch.object(m,"psql") as database:
            for (source,clone),expected in cases:
                with self.subTest(expected=expected):
                    got=m.compare_readonly_acl_observations(source,clone,digest)
                    self.assertEqual(got,expected)
                    self.assertIn(got,m.PARITY_MARKERS)
            self.assertEqual(
                m.compare_readonly_acl_observations(canonical,canonical,"wrong"),
                "acl_parity_source_unverified")
            database.assert_not_called()
        self.assertEqual(len(m.PARITY_MARKERS),6)
        for forbidden in ("anon","authenticated","service_role","postgres","public"):
            self.assertTrue(all(forbidden not in marker for marker in m.PARITY_MARKERS))

    def test_first_refusal_has_finite_stage_and_does_not_write(self):
        digest=m.source_fingerprint(MIGRATION)
        env={"CI":"true","GITHUB_ACTIONS":"true",
             "GITHUB_REPOSITORY":"optical-lift/noel-core-db",
             "ATLAS_NATIVE_NOTEBOOK_FICTIONAL_ONLY":"true",
             "ATLAS_NATIVE_GOVERNOR_CLONE_ACL_RECONCILE_ENABLED":"true"}
        url="postgresql://postgres:test@127.0.0.1:54322/postgres"
        for snapshot,stage in [
           ("", "clone_acl_function_missing"),
           ("postgres|t|"+digest+"|f|t|t|t|t|t","clone_acl_nondefault_privileges"),
           ("postgres|t|"+"0"*32+"|t|t|t|t|t|t","clone_acl_body_mismatch")
        ]:
            with self.subTest(stage=stage),mock.patch.dict("os.environ",env,clear=True):
                with mock.patch.object(m,"psql",side_effect=["postgres|postgres|f",snapshot]) as query:
                    with self.assertRaisesRegex(ValueError,stage):
                        m.reconcile(url,MIGRATION)
                    self.assertEqual(query.call_count,2)
        with mock.patch.dict("os.environ",env,clear=True):
            with mock.patch.object(m,"psql",side_effect=[ValueError("private SQL error")]) as query:
                with self.assertRaisesRegex(ValueError,"clone_acl_probe_refused"):
                    m.reconcile(url,MIGRATION)
                self.assertEqual(query.call_count,1)

    def test_local_url_and_environment_fail_closed_without_psql(self):
        self.assertTrue(m.local_only("postgresql://postgres:test@127.0.0.1:54322/postgres"))
        for url in ("postgres://host/prod",
                    "postgresql://postgres:test@127.0.0.2:54322/postgres",
                    "postgresql://postgres:test@localhost:54322/postgres",
                    "postgresql://postgres:test@127.0.0.1:54322/other"):
            self.assertFalse(m.local_only(url))
        with mock.patch.object(m,"psql") as query:
            with self.assertRaises(ValueError):
                m.reconcile("postgresql://postgres:test@127.0.0.1:54322/postgres",
                            MIGRATION)
            query.assert_not_called()
        process=subprocess.run([sys.executable,str(MOD),"--db-url",
              "postgresql://postgres:test@remote.example:54322/postgres",
              "--canonical-migration",str(MIGRATION)],
              capture_output=True,text=True,timeout=15)
        self.assertNotEqual(process.returncode,0)
        self.assertEqual(process.stderr,"")
        self.assertEqual(process.stdout,(
              "BLOCKED ATLAS_NATIVE_GOVERNOR_CLONE_ACL=NOT_VERIFIED\n"
              "ATLAS_NATIVE_GOVERNOR_GRANT_STAGE=clone_acl_environment_refused\n"))

    def test_exact_local_default_restores_only_after_source_guard(self):
        digest=m.source_fingerprint(MIGRATION)
        before="postgres|t|"+digest+"|t|t|t|t|t|t"
        after="postgres|t|"+digest+"|f|f|f|t|t|t"
        env={"CI":"true","GITHUB_ACTIONS":"true",
             "GITHUB_REPOSITORY":"optical-lift/noel-core-db",
             "ATLAS_NATIVE_NOTEBOOK_FICTIONAL_ONLY":"true",
             "ATLAS_NATIVE_GOVERNOR_CLONE_ACL_RECONCILE_ENABLED":"true"}
        url="postgresql://postgres:test@127.0.0.1:54322/postgres"
        with mock.patch.dict("os.environ",env,clear=True):
            with mock.patch.object(m,"psql",side_effect=[
                    "postgres|postgres|f",before,"",after]) as query:
                self.assertEqual(m.reconcile(url,MIGRATION),
                                 "EXACT_CANONICAL_FUNCTION_ACL_RESTORED")
                self.assertEqual(query.call_count,4)
                self.assertEqual(query.call_args_list[2].kwargs,{"transaction":True})
                sql=query.call_args_list[2].args[1]
                self.assertIn(m.REVOKE,sql)
                self.assertIn(m.GRANT,sql)
            with mock.patch.object(m,"psql",side_effect=[
                    "postgres|postgres|f",after]) as query:
                self.assertEqual(m.reconcile(url,MIGRATION),"ALREADY_PROTECTED")
                self.assertEqual(query.call_count,2)
            with mock.patch.object(m,"psql",side_effect=[
                    "postgres|postgres|f","postgres|t|"+digest+"|f|t|t|t|t|t"]) as query:
                with self.assertRaisesRegex(ValueError,"clone_acl_nondefault_privileges"):
                    m.reconcile(url,MIGRATION)
                self.assertEqual(query.call_count,2)
            with mock.patch.object(m,"psql",side_effect=[
                    "postgres|postgres|f",before,"",before]) as query:
                with self.assertRaisesRegex(ValueError,"postcondition"):
                    m.reconcile(url,MIGRATION)
                self.assertEqual(query.call_count,4)
            with mock.patch.dict("os.environ",{"NOEL_CORE_DATABASE_URL":"secret"},clear=False):
                with mock.patch.object(m,"psql") as query:
                    with self.assertRaisesRegex(ValueError,"clone_acl_environment_refused"):
                        m.reconcile(url,MIGRATION)
                    query.assert_not_called()

if __name__=="__main__":
    unittest.main()
