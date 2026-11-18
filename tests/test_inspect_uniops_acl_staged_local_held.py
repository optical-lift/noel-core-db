#!/usr/bin/env python3
"""Offline refusal and read-only I/O tests for held localhost stage adapter."""
import os
import subprocess
import tempfile
import unittest
from unittest import mock

import inspect_uniops_acl_staged_local_held as m
import uniops_acl_stage_observations_held as stage

DIGEST="0123456789abcdef0123456789abcdef"
CANON="postgres|t|"+DIGEST+"|f|f|f|t|t|t"
MANAGED="postgres|t|"+DIGEST+"|f|t|t|t|t|f"
LOCAL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
REMOTE="postgresql://postgres:fake@db.example.com:5432/postgres"

class StageLocalTest(unittest.TestCase):
    def test_read_only_aggregation_allowed_no_mutations(self):
        class Good:
            returncode=0
            stdout="0|2|0\n"
        with mock.patch.object(m.subprocess,"run",return_value=Good()) as call:
            self.assertEqual(m.local_catalog(LOCAL,stage.DEFAULTS_SQL),"0|2|0")
            cmd=call.call_args.args[0]
            self.assertEqual(cmd[-2],"-c")
            self.assertEqual(cmd[-1],stage.DEFAULTS_SQL)
            self.assertEqual(call.call_args.kwargs["env"]["PGOPTIONS"],
                             "-c default_transaction_read_only=on")
            self.assertTrue(call.call_args.kwargs["capture_output"])
        for url,sql in ((REMOTE,stage.DEFAULTS_SQL),(LOCAL,"DELETE FROM atlas.table"),
                        (LOCAL,"SELECT 1;")):
            with mock.patch.object(m.subprocess,"run") as call:
                with self.assertRaisesRegex(m.StageRefused,"stage_local_catalog_refused"):
                    m.local_catalog(url,sql)
                call.assert_not_called()

    def test_local_query_failed_or_oversized_refuses_with_no_raw_data(self):
        class Fail:
            returncode=1
            stdout="secret SQL text\n"
        for result in (Fail(),type("Huge",(),{"returncode":0,"stdout":"x"*210})()):
            with mock.patch.object(m.subprocess,"run",return_value=result):
                with self.assertRaisesRegex(m.StageRefused,"stage_local_catalog_refused"):
                    m.local_catalog(LOCAL,m.acl.ACL)

    def test_restore_requires_private_file_and_local_address(self):
        with tempfile.TemporaryDirectory() as d:
            path=os.path.join(d,"roles.sql")
            with open(path,"w") as f:
                f.write("RESET ALL;\n")
            os.chmod(path,0o600)
            with mock.patch.object(m.prior,"run_silent",return_value=True) as run:
                m.restore_one_local(LOCAL,path)
                self.assertIn("-f",run.call_args.args[0])
                self.assertIn(path,run.call_args.args[0])
            os.chmod(path,0o644)
            with mock.patch.object(m.prior,"run_silent") as run:
                with self.assertRaisesRegex(m.StageRefused,"stage_local_file_refused"):
                    m.restore_one_local(LOCAL,path)
                run.assert_not_called()
            os.chmod(path,0o600)
            with self.assertRaisesRegex(m.StageRefused,"stage_local_restore_refused"):
                m.restore_one_local(REMOTE,path)
            with mock.patch.object(m.prior,"run_silent",return_value=False):
                with self.assertRaisesRegex(m.StageRefused,"stage_local_restore_refused"):
                    m.restore_one_local(LOCAL,path)

    def test_staged_local_adapter_reads_at_exact_three_restore_boundaries(self):
        state={"step":0}
        records=[]
        def restore(url,source):
            records.append("restore")
            state["step"]+=1
        def catalog(url,sql):
            records.append(("read",state["step"],sql))
            if sql==m.acl.ACL:
                return "" if state["step"]<2 else MANAGED
            if sql==stage.DEFAULTS_SQL:
                return "0|2|0"
            return "2|2|0|0|0"
        with mock.patch.object(m,"local_catalog",side_effect=catalog):
            with mock.patch.object(m,"restore_one_local",side_effect=restore):
                r=m.inspect_staged_local(LOCAL,"roles.sql","schema.sql",CANON,DIGEST)
        self.assertEqual(r.verdict,"stage_default_compatible_not_provenance")
        self.assertEqual(records.count("restore"),2)
        self.assertEqual(len([x for x in records if isinstance(x,tuple)]),7)
        self.assertEqual([x[1] for x in records if isinstance(x,tuple)],
                         [0,0,1,1,2,2,2])

    def test_early_function_or_wrong_source_does_not_restore(self):
        with mock.patch.object(m,"local_catalog",return_value=MANAGED):
            with mock.patch.object(m,"restore_one_local") as restore:
                with self.assertRaisesRegex(m.StageRefused,"preexisting_target"):
                    m.inspect_staged_local(LOCAL,"r","s",CANON,DIGEST)
                restore.assert_not_called()
        with mock.patch.object(m,"local_catalog") as catalog:
            with self.assertRaisesRegex(m.StageRefused,"stage_local_source_refused"):
                m.inspect_staged_local(LOCAL,"r","s",MANAGED,DIGEST)
            catalog.assert_not_called()
        with mock.patch.object(m,"local_catalog") as catalog:
            with self.assertRaisesRegex(m.StageRefused,"stage_local_identity_refused"):
                m.inspect_staged_local(REMOTE,"r","s",CANON,DIGEST)
            catalog.assert_not_called()

    def test_negative_acl_verdict_is_refusal_not_correction(self):
        step=[0]
        def restore(url,src):
            step[0]+=1
        def catalog(url,sql):
            if sql==m.acl.ACL:
                return MANAGED if step[0]==2 else ""
            if sql==stage.DEFAULTS_SQL:return "0|2|0"
            return "3|2|1|0|0"
        with mock.patch.object(m,"local_catalog",side_effect=catalog):
            with mock.patch.object(m,"restore_one_local",side_effect=restore):
                with self.assertRaisesRegex(m.StageRefused,"stage_extra_unknown_refused"):
                    m.inspect_staged_local(LOCAL,"r","s",CANON,DIGEST)


if __name__=="__main__":
    unittest.main()
