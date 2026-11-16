#!/usr/bin/env python3
"""No-network negative tests for Task-FK disposable catalog classifier."""
import subprocess
import unittest
import uniops_prior_mowing_task_fk_catalog_held as catalog

DB="postgres://postgres:synthetic@127.0.0.1:5432/postgres"
DRIVER='''def run():
    try:
        return sql(_db,_statement)
    except Exception as _seed_failure:
        if _next == "physical_seed_called":
'''+catalog.ANCHOR+'''        raise
    _legacy.install(a.db_url,_prior_mowing_traced_sql)
    _legacy.require_preserved(a,b,c,d)
    history_receipt=hist.prove(a,b)
    print("UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=PASS")
    print("33340d412df23d4ee608d894a37dce638ea73b2b")
    print("a18904f46719457ae06ca301ed1c12323a5ca3c2")
    print("3847bebca7490bfc4bfbad7f629a6b26f64d7acd")
    print("ae5da30ca5953ad9bd7cb17ed09fd00ab4825dfc")
'''

class CatalogOnly(unittest.TestCase):
    def err(self,con="tasks_custom_shape_fkey"):
        return subprocess.CalledProcessError(1,["psql","private"],
                stderr='ERROR: insert violates foreign key constraint "'+con+'"\nDETAIL: SECRET NEVER EXPOSED')

    def test_one_catalog_read_and_fixed_family(self):
        calls=[]
        def sql(db,stmt):
            calls.append((db,stmt))
            return '{"columns":["generated_from_id"],"reference":"atlas.rhythm_state"}'
        self.assertEqual(catalog.classify_exception(self.err(),DB,sql),"task_generated_source")
        self.assertEqual(len(calls),1)
        self.assertIn("pg_catalog.pg_constraint",calls[0][1])
        self.assertIn("nt.nspname='atlas'",calls[0][1])
        self.assertIn("current_database()='postgres'",calls[0][1])
        self.assertNotIn("SECRET",calls[0][1])
        self.assertEqual(catalog.classify_exception(self.err(),"postgres://postgres:pw@host:5432/postgres",sql),"non_disposable")
        self.assertEqual(len(calls),1)

    def test_catalog_ref_families_and_fail_closed(self):
        self.assertEqual(catalog.classify_catalog('{"columns":["unknown"],"reference":"atlas.rhythm_state"}'),"task_ref_rhythm_state")
        self.assertEqual(catalog.classify_catalog('{"columns":["unknown"],"reference":"secret.hidden"}'),"catalog_unknown_column")
        for x in (None,"PRIVATE",'{}','{"columns":[],"reference":"atlas.tasks"}',
                  '{"columns":["secret;injection"],"reference":"atlas.tasks"}',
                  '{"columns":["a"],"reference":"atlas.tasks","other":"secret"}',
                  '{"columns":["a"],"reference":"x"}'):
            self.assertEqual(catalog.classify_catalog(x),"catalog_untrusted")
        self.assertEqual(catalog.classify_exception(AssertionError("SECRET"),DB,lambda *a:None),"non_psql_exception")
        self.assertEqual(catalog.classify_exception(self.err("work_table_id_fkey"),DB,lambda *a:None),"wrong_fk_family")
        self.assertEqual(catalog.classify_exception(self.err(),DB,lambda *a:(_ for _ in ()).throw(OSError("SECRET"))),"catalog_unavailable")

    def test_finite_log_receipt(self):
        k=catalog.RECEIPT
        self.assertEqual(catalog.extract('irrelevant'),"not_reported")
        self.assertEqual(catalog.extract(k+'task_generated_source\nSECRET'),"task_generated_source")
        self.assertEqual(catalog.extract(k+'secret_relation'),"untrusted_report")
        self.assertEqual(catalog.extract(k+'task_generated_source\n'+k+'task_zone'),"ambiguous_report")
        self.assertEqual(catalog.extract(["secret"]),"untrusted_report")

    def test_exact_one_extension_and_tamper_rejection(self):
        patched=catalog.inject(DRIVER.encode(),"a"*40).decode()
        self.assertEqual(patched.replace(catalog.ANCHOR+catalog.EXTRA.format(blob="a"*40),catalog.ANCHOR,1),DRIVER)
        self.assertEqual(patched.count(catalog.RECEIPT),1)
        self.assertEqual(patched.count("UNI_OPS_PRIOR_MOWING_TASK_FK_REFINEMENT="),1)
        self.assertEqual(patched.count("_legacy.install(a.db_url,_prior_mowing_traced_sql)"),1)
        self.assertEqual(patched.count("history_receipt=hist.prove("),1)
        self.assertEqual(patched.count("raise\n"),1)
        self.assertNotIn("print(_seed_failure)",patched)
        for altered in (DRIVER.replace(catalog.ANCHOR,""),
                        DRIVER.replace("_legacy.require_preserved(","_legacy.skip_preserved("),
                        DRIVER.replace(catalog.V6_BLOB,"0"*40),
                        DRIVER.replace(catalog.V5_BLOB,"0"*40),
                        DRIVER.replace(catalog.V4_BLOB,"0"*40),
                        DRIVER.replace(catalog.FIXTURE_BLOB,"0"*40),
                        patched):
            with self.subTest(size=len(altered)):
                with self.assertRaises(catalog.TaskCatalogRefusal):
                    catalog.inject(altered.encode(),"a"*40)

if __name__=="__main__":
    unittest.main(verbosity=2)
