#!/usr/bin/env python3
"""Offline refusal and cleanup tests for held one-shot #2867 staging."""
import contextlib
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import inspect_uniops_acl_staged_source_clone_2867_held as target
import uniops_acl_stage_observations_held as stage

DIGEST="0123456789abcdef0123456789abcdef"
CANON="postgres|t|"+DIGEST+"|f|f|f|t|t|t"
BASE=dict(target.EXPECTED)
BASE["NOEL_CORE_DATABASE_URL"] = (
  "postgresql://postgres:fictional@db.zirqkouammpwxlqfbsvf.supabase.co:5432/postgres?sslmode=require"
)

class GuardTests(unittest.TestCase):
    def test_wrong_or_old_credentials_fail_before_any_access(self):
        with tempfile.TemporaryDirectory() as temp:
            base=dict(BASE,RUNNER_TEMP=temp)
            self.assertEqual(target.require_environment(base)[1],Path(temp))
            pooler=dict(base,NOEL_CORE_DATABASE_URL=(
                "postgresql://postgres.zirqkouammpwxlqfbsvf:fictional@"
                "aws-0-us-east-1.pooler.supabase.com:5432/postgres?sslmode=verify-full"))
            self.assertEqual(target.require_environment(pooler)[1],Path(temp))
            variants=[
                {"NOEL_CORE_DATABASE_URL":"postgresql://postgres:x@127.0.0.1:5432/postgres"},
                {"NOEL_CORE_DATABASE_URL":"postgresql://postgres:x@db.other.supabase.co:5432/postgres?sslmode=require"},
                # A project-suffixed username must NEVER make an arbitrary
                # hostname trustworthy: it could receive a real DB password.
                {"NOEL_CORE_DATABASE_URL":
                    "postgresql://postgres.zirqkouammpwxlqfbsvf:x@evil.example:5432/postgres?sslmode=require"},
                {"NOEL_CORE_DATABASE_URL":
                    "postgresql://postgres.zirqkouammpwxlqfbsvf:x@not-pooler.supabase.com:5432/postgres?sslmode=require"},
                {"NOEL_CORE_DATABASE_URL":
                    "postgresql://postgres:x@db.zirqkouammpwxlqfbsvf.supabase.co:6500/postgres?sslmode=require"},
                {"NOEL_CORE_DATABASE_URL":
                    "postgresql://postgres:x@db.zirqkouammpwxlqfbsvf.supabase.co:5432/other?sslmode=require"},
                {"NOEL_CORE_DATABASE_URL":
                    "postgresql://postgres:x@db.zirqkouammpwxlqfbsvf.supabase.co:5432/postgres?sslmode=disable"},
                {"NOEL_CORE_DATABASE_URL":
                    "postgresql://postgres:x@db.zirqkouammpwxlqfbsvf.supabase.co:5432/postgres?sslmode=disable"},
                {"NOEL_CORE_DATABASE_URL":
                    "postgresql://postgres:x@db.zirqkouammpwxlqfbsvf.supabase.co:5432/postgres?sslmode=require&host=evil.example"},
                {"NOEL_CORE_DATABASE_URL":
                    "postgresql://other:x@db.zirqkouammpwxlqfbsvf.supabase.co:5432/postgres?sslmode=require"},
                {"NOEL_CORE_DATABASE_URL":
                    "postgresql://postgres:x@db.zirqkouammpwxlqfbsvf.supabase.co:bad/postgres?sslmode=require"},
                {"NOEL_CORE_DATABASE_URL":""},
                {target.GATE:"false"},
                {"UNI_OPS_READONLY_ACL_2848_APPROVED":"true"},
                {"UNI_OPS_STAGED_READONLY_2859_APPROVED":"true"},
                {"UNI_OPS_STAGED_READONLY_2864_APPROVED":"true"},
                {"ATLAS_NATIVE_GOVERNOR_CLONE_ACL_RECONCILE_ENABLED":"true"},
                {"ATLAS_GOVERNOR_PG17_SYNTHETIC_ENABLED":"true"},
                {"SUPABASE_SERVICE_ROLE_KEY":"fictional"},
                {"GITHUB_REPOSITORY":"other/repo"},
                {"RUNNER_TEMP":"/does-not-exist"},
            ]
            for change in variants:
                with self.subTest(change=sorted(change)):
                    with self.assertRaises(target.Refused):
                        target.require_environment(dict(base,**change))

    def test_main_preserves_environment_refusal_without_any_database_action(self):
        with tempfile.TemporaryDirectory() as temp:
            cases=(
                ("postgresql://postgres:x@other.example:5432/postgres?sslmode=require",
                 "stage_inspect_target_refused"),
                ("postgresql://postgres:x@db.zirqkouammpwxlqfbsvf.supabase.co:5432/postgres?sslmode=disable",
                 "stage_inspect_tls_refused"),
                ("", "stage_inspect_missing_connection_refused"),
                ("postgresql://other:x@db.zirqkouammpwxlqfbsvf.supabase.co:5432/postgres?sslmode=require",
                 "stage_inspect_credentials_refused"),
            )
            for bad,reason in cases:
                with self.subTest(reason=reason):
                    env=dict(BASE,RUNNER_TEMP=temp,NOEL_CORE_DATABASE_URL=bad)
                    buffer=io.StringIO()
                    with mock.patch.dict(os.environ,env,clear=True):
                        with mock.patch.object(target,"source_fingerprint") as source:
                            with mock.patch.object(target.prior,"catalog_snapshot") as sql:
                                with contextlib.redirect_stdout(buffer):
                                    code=target.main()
                    self.assertEqual(code,1)
                    self.assertIn("UNI_OPS_2867_READONLY_STAGE="+reason,
                                  buffer.getvalue())
                    self.assertIn("UNI_OPS_PRODUCTION_CHANGE=NONE",buffer.getvalue())
                    self.assertNotIn("postgresql://",buffer.getvalue())
                    source.assert_not_called()
                    sql.assert_not_called()

    def test_normalizes_known_direct_and_session_urls_only(self):
        with tempfile.TemporaryDirectory() as temp:
            base=dict(BASE,RUNNER_TEMP=temp)
            for legacy,want in (
                ("postgresql://postgres:fictional@db.zirqkouammpwxlqfbsvf.supabase.co:5432/postgres",
                 "postgresql://postgres:fictional@db.zirqkouammpwxlqfbsvf.supabase.co:5432/postgres?sslmode=require"),
                ("postgresql://postgres:fictional@db.zirqkouammpwxlqfbsvf.supabase.co:6543/postgres",
                 "postgresql://postgres:fictional@db.zirqkouammpwxlqfbsvf.supabase.co:5432/postgres?sslmode=require"),
                ("postgresql://postgres.zirqkouammpwxlqfbsvf:fictional@aws-0-us-east-1.pooler.supabase.com:6543/postgres",
                 "postgresql://postgres.zirqkouammpwxlqfbsvf:fictional@aws-0-us-east-1.pooler.supabase.com:5432/postgres?sslmode=require"),
                ("postgresql://postgres.zirqkouammpwxlqfbsvf:fictional@aws-0-us-east-1.pooler.supabase.com:5432/postgres?sslmode=verify-full",
                 "postgresql://postgres.zirqkouammpwxlqfbsvf:fictional@aws-0-us-east-1.pooler.supabase.com:5432/postgres?sslmode=verify-full"),
            ):
                with self.subTest(legacy_endpoint=legacy.rsplit("@",1)[-1]):
                    actual,tmp=target.require_environment(dict(base,NOEL_CORE_DATABASE_URL=legacy))
                    self.assertEqual(actual,want)
                    self.assertEqual(tmp,Path(temp))
            for unsafe in (
                "postgresql://postgres:fictional@outside.example:6543/postgres",
                "postgresql://postgres.zirqkouammpwxlqfbsvf:fictional@wrong.pooler.attacker.example:6543/postgres",
                "postgresql://postgres:fictional@db.other.supabase.co:5432/postgres",
                "postgresql://postgres:fictional@db.zirqkouammpwxlqfbsvf.supabase.co:5432/postgres?sslmode=disable",
                "postgresql://postgres:fictional@db.zirqkouammpwxlqfbsvf.supabase.co:5432/postgres?sslmode=require&host=outside.example",
                "postgresql://other:fictional@db.zirqkouammpwxlqfbsvf.supabase.co:5432/postgres",
            ):
                with self.subTest(unsafe_endpoint=unsafe.rsplit("@",1)[-1]):
                    with self.assertRaises(target.Refused):
                        target.require_environment(dict(base,NOEL_CORE_DATABASE_URL=unsafe))

    def test_old_gate_flags_rejected_even_with_valid_url(self):
        with tempfile.TemporaryDirectory() as temp:
            base=dict(BASE,RUNNER_TEMP=temp)
            for old_gate in ("UNI_OPS_STAGED_READONLY_2859_APPROVED",
                             "UNI_OPS_STAGED_READONLY_2864_APPROVED"):
                with self.subTest(old_gate=old_gate):
                    with self.assertRaisesRegex(target.Refused,"stage_inspect_gate_refused"):
                        target.require_environment(dict(base,**{old_gate:"true"}))

    def test_main_preserves_source_refusal_without_connecting(self):
        with tempfile.TemporaryDirectory() as temp:
            env=dict(BASE,RUNNER_TEMP=temp)
            buffer=io.StringIO()
            with mock.patch.dict(os.environ,env,clear=True):
                with mock.patch.object(target,"source_fingerprint",
                    side_effect=target.Refused("stage_inspect_source_refused")):
                    with mock.patch.object(target.prior,"catalog_snapshot") as sql:
                        with contextlib.redirect_stdout(buffer):
                            rc=target.main()
            self.assertEqual(rc,1)
            self.assertIn(
                "UNI_OPS_2867_READONLY_STAGE=stage_inspect_source_refused",
                buffer.getvalue())
            sql.assert_not_called()

    def test_missing_or_insecure_private_files_fail(self):
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp)/"export.sql"
            with self.assertRaisesRegex(target.Refused,"stage_inspect_snapshot_refused"):
                target.private_file(p)
            p.write_text("RESET ALL;\n")
            p.chmod(0o644)
            with self.assertRaisesRegex(target.Refused,"stage_inspect_snapshot_refused"):
                target.private_file(p)
            p.chmod(0o600)
            target.private_file(p)
            link=Path(temp)/"link.sql"
            link.symlink_to(p)
            with self.assertRaisesRegex(target.Refused,"stage_inspect_snapshot_refused"):
                target.private_file(link)

    def test_source_snapshot_calls_pinned_readonly_catalog_only(self):
        with mock.patch.object(target.prior,"catalog_snapshot",return_value=CANON) as fn:
            self.assertEqual(target.source_snapshot("fictional"),CANON)
            fn.assert_called_once_with("fictional",read_only=True)
        with mock.patch.object(target.prior,"catalog_snapshot",side_effect=OSError("sensitive")):
            with self.assertRaisesRegex(target.Refused,"stage_inspect_live_probe_refused"):
                target.source_snapshot("fictional")

    def exercise(self, *, second_source=None, final_source=None, cleanup_fail=False, verdict="stage_default_compatible_not_provenance"):
        with tempfile.TemporaryDirectory() as tmp:
            env=dict(BASE,RUNNER_TEMP=tmp)
            calls=[]
            snapshots=iter([CANON,second_source or CANON,final_source or CANON])
            def fake_run(cmd,**kwargs):
                calls.append(tuple(cmd))
                if cmd[:3]==["supabase","db","dump"]:
                    p=Path(cmd[-1])
                    p.write_text("RESET ALL;\n")
                    p.chmod(0o600)
                    return True
                if cmd[:2]==["supabase","stop"]:
                    return not cleanup_fail
                return True
            def fake_start(path,port):
                (path/"supabase").mkdir(parents=True,exist_ok=True)
            d=stage.StageDecision(verdict,("anon_exec",),False,False)
            buffer=io.StringIO()
            with mock.patch.dict(os.environ,env,clear=True):
                with mock.patch.object(target,"source_fingerprint",return_value=DIGEST):
                    with mock.patch.object(target,"source_snapshot",side_effect=lambda live: next(snapshots)):
                        with mock.patch.object(target.prior,"run_silent",side_effect=fake_run):
                            with mock.patch.object(target.prior,"setup_local",side_effect=fake_start):
                                with mock.patch.object(target.prior,"isolated_port",return_value=54322):
                                    with mock.patch.object(target.prior,"sanitize_schema",
                                    side_effect=lambda src,dst: (dst.write_text("RESET ALL;\n"),dst.chmod(0o600))):
                                        with mock.patch.object(target.local,"inspect_staged_local",return_value=d) as local:
                                            with contextlib.redirect_stdout(buffer):
                                                result=target.main()
            self.assertEqual(list(Path(tmp).iterdir()),[])
            self.assertFalse(any("--data-only" in x for x in calls))
            for command in calls:
                if command[:3]==("supabase","db","dump"):
                    self.assertIn("--file",command)
                    self.assertNotIn("push",command)
            return result,buffer.getvalue(),calls,local.call_count

    def test_authorized_shape_offline_mock_never_touches_live_db(self):
        rc,out,calls,count=self.exercise()
        self.assertEqual(rc,0)
        self.assertIn("stage_default_compatible_not_provenance",out)
        self.assertIn("UNI_OPS_PRODUCTION_CHANGE=NONE",out)
        self.assertEqual(count,1)
        self.assertEqual(len([c for c in calls if c[:3]==("supabase","db","dump")]),2)
        self.assertNotIn("fictional@",out)

    def test_cleanup_failure_overrides_prior_success(self):
        rc,out,_,count=self.exercise(cleanup_fail=True)
        self.assertEqual(rc,1)
        self.assertIn("stage_inspect_cleanup_refused",out)
        self.assertNotIn("stage_default_compatible_not_provenance",out)
        self.assertEqual(count,1)

    def test_source_drift_refuses_without_local_inspection(self):
        rc,out,_,count=self.exercise(second_source=CANON.replace("|f|f|f|t|t|t","|f|t|t|t|t|f"))
        self.assertEqual(rc,1)
        self.assertIn("stage_inspect_source_drift_refused",out)
        self.assertEqual(count,0)

    def test_source_drift_during_local_restore_invalidates_result(self):
        drift=CANON.replace("|f|f|f|t|t|t","|f|t|t|t|t|f")
        rc,out,_,count=self.exercise(final_source=drift)
        self.assertEqual(rc,1)
        self.assertIn("stage_inspect_source_drift_refused",out)
        self.assertNotIn("stage_default_compatible_not_provenance",out)
        self.assertEqual(count,1)

    def test_bad_local_verdict_is_never_promoted(self):
        rc,out,_,count=self.exercise(verdict="stage_other_mismatch_refused")
        self.assertEqual(rc,1)
        self.assertIn("stage_other_mismatch_refused",out)
        self.assertEqual(count,1)

    def test_no_runtime_controller_or_mutation_in_inspector(self):
        s=(Path(__file__).parent/"inspect_uniops_acl_staged_source_clone_2867_held.py").read_text()
        self.assertIn('raise SystemExit(main())',s)
        self.assertNotIn("fictional_clone_only_rebalance(",s)
        self.assertNotIn("reconcile(",s)
        self.assertNotIn("supabase\",\"db\",\"push",s)
        self.assertNotIn("upload-artifact",s)
        self.assertIn("UNI_OPS_STAGED_READONLY_2867_APPROVED",s)
        self.assertNotIn("UNI_OPS_STAGED_READONLY_2852_APPROVED",s)


if __name__=="__main__":
    unittest.main()
