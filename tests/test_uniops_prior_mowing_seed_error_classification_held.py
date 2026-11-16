#!/usr/bin/env python3
"""Offline tamper and redaction tests for the prior-mowing seed error class."""
import ast
import subprocess
import unittest

import uniops_prior_mowing_seed_error_classification_held as classifier

DRIVER = '''#!/usr/bin/env python3
def main():
    def _prior_mowing_traced_sql(_db,_statement):
        _next="physical_seed_called"
        return sql(_db,_statement)
    _legacy.install(a.db_url,_prior_mowing_traced_sql)
    _legacy.require_preserved(before,after,c,d)
    history_receipt=hist.prove(a,b)
    print("UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=PASS")
    print("ae5da30ca5953ad9bd7cb17ed09fd00ab4825dfc")
'''

class SeedFailureCategories(unittest.TestCase):
    def err(self,raw):
        return subprocess.CalledProcessError(1,["psql","REDACTED"],output="",stderr=raw)

    def test_fixed_categories_never_echo_raw_psql_text(self):
        cases=(
            ("psql:<hidden>: ERROR: Prior-mowing fixture requires clean prepolicy disposable source","preflight_guard"),
            ("psql: ERROR: Prior-mowing fixture did not establish exact linked carriers","postcondition_guard"),
            ("psql: ERROR: Active tasks require a planned occurrence, release policy, and release timestamp.","task_release_gate"),
            ("psql: ERROR: Task release gate does not belong to the task farm.","task_release_farm_guard"),
            ("psql: ERROR: insert or update on table \"SECRET\" violates foreign key constraint \"SECRET\"","foreign_key"),
            ("psql: ERROR: null value in column \"SECRET\" of relation \"SECRET\" violates not-null constraint","not_null"),
            ("psql: ERROR: new row for relation \"SECRET\" violates check constraint \"SECRET\"","check_constraint"),
            ("psql: ERROR: duplicate key value violates unique constraint \"SECRET\"","uniqueness"),
            ("psql: ERROR: new row violates row-level security policy for table SECRET","rls"),
            ("psql: ERROR: permission denied for table SECRET","privilege"),
            ("psql: ERROR: relation \"SECRET\" does not exist","missing_relation"),
            ("psql: ERROR: column \"SECRET\" does not exist","missing_column"),
            ("psql: ERROR: function SECRET() does not exist","missing_function"),
            ("psql: ERROR: invalid input syntax for type uuid: \"SECRET\"","invalid_value"),
            ("psql: ERROR: syntax error at or near SECRET","syntax"),
            ("psql: ERROR: PRIVATE_UNCLASSIFIED_FAILURE_A9Z8","other_sql_error"),
            ("NOTICE: no error","psql_without_error_line")
        )
        for raw,want in cases:
            with self.subTest(want=want):
                got=classifier.classify_exception(self.err(raw))
                self.assertEqual(got,want)
                self.assertIn(got,classifier.CATEGORIES)
                self.assertNotIn("SECRET",got)
                self.assertNotIn("PRIVATE",got)
        self.assertEqual(classifier.classify_exception(AssertionError("private secret")),"non_psql_exception")

    def test_report_accepts_one_fixed_token_and_rejects_data_or_duplicates(self):
        prefix="UNI_OPS_PRIOR_MOWING_SEED_SQL_ERROR_CLASS="
        self.assertEqual(classifier.extract_category("unrelated private raw log"),"not_reported")
        self.assertEqual(classifier.extract_category(prefix+"preflight_guard\nPRIVATE"),"preflight_guard")
        self.assertEqual(classifier.extract_category(prefix+"check_constraint;sql=secret"),"untrusted_report")
        self.assertEqual(classifier.extract_category(prefix+"preflight_guard\n"+prefix+"foreign_key"),"ambiguous_report")
        self.assertEqual(classifier.extract_category({"log":"secret"}),"untrusted_report")

    def test_source_patch_is_only_one_exact_wrapper_and_compiles(self):
        out=classifier.inject(DRIVER.encode("utf8"),"a"*40).decode("utf8")
        ast.parse(out)
        self.assertIn("UNI_OPS_PRIOR_MOWING_SEED_SQL_ERROR_CLASS=",out)
        self.assertEqual(out.count("UNI_OPS_PRIOR_MOWING_SEED_SQL_ERROR_CLASS="),1)
        self.assertEqual(out.count("history_receipt=hist.prove("),1)
        self.assertEqual(out.count("_legacy.require_preserved("),1)
        self.assertEqual(out.count("_legacy.install(a.db_url,_prior_mowing_traced_sql)"),1)
        self.assertIn('raise\n',out)
        self.assertNotIn("stderr",out)
        self.assertNotIn("print(_seed_failure)",out)
        self.assertEqual(out.count("return sql(_db,_statement)"),1)
        self.assertEqual(out.count("import hashlib as _sc_hashlib"),1)
        self.assertIn('b"\\0"+_sc_raw',out)
        self.assertEqual(out.count("a"*40),1)

    def test_missing_duplicate_reused_or_unpinned_source_fail_closed(self):
        original=DRIVER.encode("utf8")
        cases=(original.replace(classifier.ANCHOR.encode("utf8"),b""),
               original.replace(classifier.ANCHOR.encode("utf8"),classifier.ANCHOR.encode("utf8")*2),
               original.replace(b"history_receipt=hist.prove(",b"history_receipt=hist.other("),
               original.replace(b"ae5da30ca5953ad9bd7cb17ed09fd00ab4825dfc",b"ffff"*10),
               classifier.inject(original,"a"*40))
        for data in cases:
            with self.subTest(size=len(data)):
                with self.assertRaises(classifier.SeedErrorCategoryRefusal):
                    classifier.inject(data,"a"*40)
        for incorrect in ("","not_a_sha","z"*40):
            with self.assertRaises(classifier.SeedErrorCategoryRefusal):
                classifier.inject(original,incorrect)

if __name__=="__main__":
    unittest.main(verbosity=2)
