#!/usr/bin/env python3
"""No-network test of exact-source P3 test-runner instrumentation.

Parent U4 source is supplied from a separately pinned immutable checkout on
GitHub's public unprivileged PR job. These tests never invoke PostgreSQL or
GoTrue, and they do not furnish owner-signed acceptance.
"""
import importlib.util
import json
from pathlib import Path
import py_compile
import tempfile
import unittest
import sys

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("p3_hook",HERE/"23_signed_p3_snapshot_hook_held.py")
hook=importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)
hook.SNAPSHOT=HERE/"18_disposable_signed_result_snapshot.sql"
hook.COMPARATOR=HERE/"19_compare_signed_result_snapshots.mjs"

class HookTests(unittest.TestCase):
    def test_read_only_exact_parameters_and_deny_unsafe(self):
        source=hook._pinned(hook.SNAPSHOT,hook.SNAPSHOT_BLOB)
        work="e5200000-0000-4000-8000-000000000d07"
        q=hook.render_snapshot(source,hook.ORG,hook.STATE,work,"before")
        self.assertIn("'"+work+"'::uuid",q)
        self.assertIn("'before'::text",q)
        self.assertIn("'"+hook.STATE+"'::uuid",q)
        self.assertNotIn(":'",q)
        self.assertIn("SELECT jsonb_build_object(",q)
        for phase in ("created","finished","",None):
            with self.assertRaises(AssertionError):
                hook.render_snapshot(source,hook.ORG,hook.STATE,work,phase)
        for unsafe in ("z' OR 1=1 --","",None):
            with self.assertRaises(AssertionError):
                hook.render_snapshot(source,hook.ORG,hook.STATE,unsafe,"before")
        with self.assertRaises(AssertionError):
            hook.render_snapshot(source+"\nDELETE FROM atlas.work_items;",
                hook.ORG,hook.STATE,work,"before")
        with self.assertRaises(AssertionError):
            hook.render_snapshot(source.replace(":'phase'","'forged'"),
                hook.ORG,hook.STATE,work,"before")

    def test_snapshot_local_only_and_source_receipt(self):
        good="postgresql://postgres:fictional@127.0.0.1:54322/postgres"
        status={"called":0}
        def sql(_db,q):
            status["called"]+=1
            self.assertIn("SELECT jsonb_build_object(",q)
            return json.dumps({"phase":"before",
                "contract":"uni_ops_p3_signed_result_snapshot_v1"})
        got=hook.capture(good,sql,hook.ORG,hook.STATE,
            "e5200000-0000-4000-8000-000000000d07","before")
        self.assertEqual(got["phase"],"before")
        self.assertEqual(status["called"],1)
        for unsafe in ("https://db.example.com",
                       "postgresql://postgres:fictional@10.10.10.10:5432/postgres",
                       "postgresql://postgres:fictional@127.0.0.1:54322/production"):
            with self.assertRaises(AssertionError):
                hook.capture(unsafe,sql,hook.ORG,hook.STATE,
                    "e5200000-0000-4000-8000-000000000d07","before")
        self.assertEqual(status["called"],1)

    def test_exact_previous_U4_source_clone_can_be_instrumented(self):
        if len(sys.argv)!=2:
            self.skipTest("pinned original U4 proof file is supplied by CI")
        parent=Path(sys.argv[1])
        raw=parent.read_bytes()
        self.assertEqual(hook._git_blob(raw),hook.SIGNED_U4_PARENT_BLOB)
        with tempfile.TemporaryDirectory(prefix="uniops-p3-hook-source-") as d:
            trial=Path(d)/"uniops_u2_qualified_actual_followon_held.py"
            trial.write_bytes(raw)
            self.assertTrue(hook.patch_exact_disposable_u4(trial))
            after=trial.read_text()
            py_compile.compile(str(trial),doraise=True)
            self.assertEqual(after.count("_p3_before=_p3.capture"),1)
            self.assertEqual(after.count("_p3_after=_p3.capture"),1)
            self.assertEqual(after.count("_p3_replay=_p3.capture"),1)
            self.assertEqual(after.count("_p3.compare("),1)
            self.assertIn('status, response = call("worker")',after)
            self.assertIn("Campaign",after)
            with self.assertRaises(AssertionError):
                hook.patch_exact_disposable_u4(trial)
            tampered=Path(d)/"tampered.py"
            tampered.write_bytes(raw+b"\n#unapproved\n")
            with self.assertRaises(AssertionError):
                hook.patch_exact_disposable_u4(tampered)

if __name__=="__main__":
    # unittest sees a parent fixture path as argv, so let it remain available
    # to test code but prevent unittest CLI treating it as a test name.
    parent=sys.argv[1:]  # preserve through a module constant if supplied
    U4_PINNED_PARENT=parent[0] if parent else None
    # Unittest invoked via discover does not need argv; CI uses direct invocation.
    unittest.main(argv=[sys.argv[0]],verbosity=2)
