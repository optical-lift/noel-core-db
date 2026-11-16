#!/usr/bin/env python3
"""Offline no-network source/tamper checks for bounded prior-mowing FK locus."""
import ast
import subprocess
import unittest

import uniops_prior_mowing_foreign_key_locus_held as loc

# The signed source integration itself is checked independently by the
# protected source-only composer. Use its *real* exact v4 anchor in the test.
DRIVER='''def main():
    try:
        return sql(_db,_statement)
    except Exception as _seed_failure:
        if _next == "physical_seed_called":
'''+loc.SOURCE_V4_ANCHOR+'''        raise
    _legacy.install(a.db_url,_prior_mowing_traced_sql)
    _legacy.require_preserved(a,b,c,d)
    history_receipt=hist.prove(a,b)
    print("UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=PASS")
    print("3847bebca7490bfc4bfbad7f629a6b26f64d7acd")
    print("ae5da30ca5953ad9bd7cb17ed09fd00ab4825dfc")
'''

class ForeignKeyLocusSourceOnly(unittest.TestCase):
    def error(self,detail):
        return subprocess.CalledProcessError(1,["psql","REDACTED"],stderr=
            "psql:PRIVATE:32: ERROR: insert or update on table SECRET violates foreign key constraint \""+detail+"\"\n"
            "DETAIL: Key (id)=(SECRET_PERSON) is not present in table \"SECRET\".")

    def test_known_constraints_and_safe_family_fallback(self):
        for key,label in loc.LABELS.items():
            with self.subTest(key=key):
                got=loc.classify_exception(self.error(key))
                self.assertEqual(got,label)
                self.assertIn(got,loc.FIXED)
                self.assertNotIn("SECRET",got)
        for prefix,label in loc.FAMILIES.items():
            with self.subTest(prefix=prefix):
                self.assertEqual(loc.classify_exception(self.error(prefix+"unlisted_thing_fkey")),label)
        self.assertEqual(loc.classify_exception(self.error("outside_scope_unlisted_fkey")),"unknown_fk")
        self.assertEqual(loc.classify_exception(subprocess.CalledProcessError(1,["psql"],stderr="NO ERRORS")),"error_without_constraint")
        self.assertEqual(loc.classify_exception(AssertionError("PRIVATE")),"non_psql_exception")
        self.assertEqual(loc.classify_exception(subprocess.CalledProcessError(1,["psql"],stderr=
            "ERROR: violates foreign key constraint \"tasks_farm_id_fkey\"\n"
            "ERROR: violates foreign key constraint \"tasks_release_policy_id_fkey\"")),"multiple_fk")

    def test_bounded_report_reader_never_echoes_private_tokens(self):
        key="UNI_OPS_PRIOR_MOWING_FK_LOCUS="
        self.assertEqual(loc.extract_locus("unrelated"),"not_reported")
        self.assertEqual(loc.extract_locus(key+"task_policy\nSECRET"),"task_policy")
        self.assertEqual(loc.extract_locus(key+"SECRET_PERSON"),"untrusted_report")
        self.assertEqual(loc.extract_locus(key+"task_policy;SECRET"),"untrusted_report")
        self.assertEqual(loc.extract_locus(key+"task_policy\n"+key+"task_farm"),"ambiguous_report")
        self.assertEqual(loc.extract_locus(1),"untrusted_report")

    def test_one_exact_extension_of_existing_signed_error_wrapper(self):
        before=DRIVER.encode("utf8")
        after=loc.inject(before,"a"*40).decode("utf8")
        ast.parse(after)
        self.assertEqual(after.replace(loc.SOURCE_V4_ANCHOR+
            loc.EXTRA.format(blob="a"*40),loc.SOURCE_V4_ANCHOR,1),before.decode())
        self.assertEqual(after.count("UNI_OPS_PRIOR_MOWING_SEED_SQL_ERROR_CLASS="),1)
        self.assertEqual(after.count("UNI_OPS_PRIOR_MOWING_FK_LOCUS="),1)
        self.assertEqual(after.count("history_receipt=hist.prove("),1)
        self.assertEqual(after.count("_legacy.require_preserved("),1)
        self.assertEqual(after.count("_legacy.install(a.db_url,_prior_mowing_traced_sql)"),1)
        self.assertEqual(after.count("raise\n"),1)
        self.assertNotIn("print(_seed_failure)",after)
        self.assertNotIn("print(_fk_bytes)",after)
        self.assertIn('b"\\0"+_fk_bytes',after)

    def test_refuses_tamper_or_double_insertion(self):
        base=DRIVER.encode()
        cases=(
            base.replace(loc.SOURCE_V4_ANCHOR.encode(),b""),
            base.replace(loc.SOURCE_V4_ANCHOR.encode(),loc.SOURCE_V4_ANCHOR.encode()*2),
            base.replace(loc.SOURCE_V4_HELPER_BLOB.encode(),b"0"*40),
            base.replace(loc.SOURCE_V3_FIXTURE_BLOB.encode(),b"0"*40),
            base.replace(b"history_receipt=hist.prove(",b"history_receipt=hist.disallowed("),
            loc.inject(base,"a"*40)
        )
        for item in cases:
            with self.subTest(size=len(item)):
                with self.assertRaises(loc.ForeignKeyLocusRefusal):
                    loc.inject(item,"a"*40)
        for wrong in ("", "notasha", "g"*40):
            with self.assertRaises(loc.ForeignKeyLocusRefusal):
                loc.inject(base,wrong)

if __name__=="__main__":
    unittest.main(verbosity=2)
