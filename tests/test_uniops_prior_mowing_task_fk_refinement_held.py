#!/usr/bin/env python3
"""Offline finite Task FK classification and immutable v5 wrapper tests."""
import ast
import subprocess
import unittest
import uniops_prior_mowing_task_fk_refinement_held as task_fk

DRIVER='''def run():
    try:
        return sql(_db,_statement)
    except Exception as _seed_failure:
        if _next == "physical_seed_called":
'''+task_fk.ANCHOR+'''        raise
    _legacy.install(a.db_url,_prior_mowing_traced_sql)
    _legacy.require_preserved(a,b,c,d)
    history_receipt=hist.prove(a,b)
    print("UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=PASS")
    print("a18904f46719457ae06ca301ed1c12323a5ca3c2")
    print("3847bebca7490bfc4bfbad7f629a6b26f64d7acd")
    print("ae5da30ca5953ad9bd7cb17ed09fd00ab4825dfc")
'''

class TaskFkOffline(unittest.TestCase):
    def error(self,name):
        raw='psql:PRIVATE:120: ERROR: insert on SECRET violates foreign key constraint "'+name+'"\nDETAIL: SECRET ROW NEVER EXPOSED'
        return subprocess.CalledProcessError(1,["psql","REDACTED"],stderr=raw)

    def test_exact_and_family_only(self):
        for name,label in task_fk.EXACT.items():
            with self.subTest(name=name):
                self.assertEqual(task_fk.classify_exception(self.error(name)),label)
        for suffix,label in task_fk.FAMILIES:
            with self.subTest(suffix=suffix):
                got=task_fk.classify_exception(self.error("tasks_unknown"+suffix))
                self.assertEqual(got,label)
                self.assertIn(got,task_fk.FIXED)
                self.assertNotIn("SECRET",got)
        self.assertEqual(task_fk.classify_exception(self.error("tasks_unmapped_custom_fkey")),"task_unclassified")
        self.assertEqual(task_fk.classify_exception(self.error("work_items_parent_id_fkey")),"not_task_fk")
        self.assertEqual(task_fk.classify_exception(self.error("tasks_farm_id_fkey")),"task_unclassified")
        self.assertEqual(task_fk.classify_exception(self.error("tasks_very_secret_fkey")),"task_unclassified")
        self.assertEqual(task_fk.classify_exception(AssertionError("SECRET")),"non_psql_exception")
        self.assertEqual(task_fk.classify_exception(subprocess.CalledProcessError(1,["psql"],stderr="No error")),"error_without_constraint")
        self.assertEqual(task_fk.classify_exception(subprocess.CalledProcessError(1,["psql"],stderr=
            'ERROR: violates foreign key constraint "tasks_parent_task_id_fkey"\n'
            'ERROR: violates foreign key constraint "tasks_assigned_membership_id_fkey"')),"multiple_fk")

    def test_only_one_allowlisted_receipt(self):
        p="UNI_OPS_PRIOR_MOWING_TASK_FK_REFINEMENT="
        self.assertEqual(task_fk.extract("unrelated"),"not_reported")
        self.assertEqual(task_fk.extract(p+"task_parent\nSECRET ROW"),"task_parent")
        self.assertEqual(task_fk.extract(p+"tasks_secret_id_fkey"),"untrusted_report")
        self.assertEqual(task_fk.extract(p+"task_parent;SECRET"),"untrusted_report")
        self.assertEqual(task_fk.extract(p+"task_parent\n"+p+"task_zone"),"ambiguous_report")
        self.assertEqual(task_fk.extract(["SECRET"]),"untrusted_report")

    def test_one_source_safe_extension(self):
        patched=task_fk.inject(DRIVER.encode("utf8"),"a"*40).decode("utf8")
        ast.parse(patched)
        self.assertEqual(patched.replace(task_fk.ANCHOR+task_fk.EXTRA.format(blob="a"*40),task_fk.ANCHOR,1),DRIVER)
        self.assertEqual(patched.count("UNI_OPS_PRIOR_MOWING_TASK_FK_REFINEMENT="),1)
        self.assertEqual(patched.count("UNI_OPS_PRIOR_MOWING_FK_LOCUS="),1)
        self.assertEqual(patched.count("_legacy.install(a.db_url,_prior_mowing_traced_sql)"),1)
        self.assertEqual(patched.count("_legacy.require_preserved("),1)
        self.assertEqual(patched.count("history_receipt=hist.prove("),1)
        self.assertEqual(patched.count("raise\n"),1)
        self.assertNotIn("print(_seed_failure)",patched)
        self.assertIn('b"\\0"+_task_fk_bytes',patched)

    def test_refuse_source_tamper_and_double_overlay(self):
        b=DRIVER.encode()
        bad=[
            b.replace(task_fk.ANCHOR.encode(),b""),
            b.replace(task_fk.ANCHOR.encode(),task_fk.ANCHOR.encode()*2),
            b.replace(task_fk.V5_BLOB.encode(),b"0"*40),
            b.replace(task_fk.V4_BLOB.encode(),b"0"*40),
            b.replace(task_fk.FIXTURE_BLOB.encode(),b"0"*40),
            b.replace(b"history_receipt=hist.prove(",b"history_receipt=hist.lie("),
            task_fk.inject(b,"a"*40),
        ]
        for raw in bad:
            with self.subTest(size=len(raw)):
                with self.assertRaises(task_fk.TaskForeignKeyRefusal):
                    task_fk.inject(raw,"a"*40)
        for wrong in ("","x"*40,"not_sha"):
            with self.assertRaises(task_fk.TaskForeignKeyRefusal):
                task_fk.inject(b,wrong)

if __name__=="__main__":
    unittest.main(verbosity=2)
