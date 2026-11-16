#!/usr/bin/env python3
"""No-network negative and semantic contract tests for Task FK structure audit."""
import subprocess
import unittest
import uniops_prior_mowing_task_fk_structure_held as m

DB='postgres://postgres:synthetic@127.0.0.1:5432/postgres'

def err(name='tasks_unreviewed_fkey'):
    return subprocess.CalledProcessError(1,['psql','PRIVATE'],
        stderr='ERROR: insert or update violates foreign key constraint "'+name+'"\nDETAIL: PRIVATE ROW NOT FOR LOGGING')

class ShapeContract(unittest.TestCase):
    def test_source_literal_and_fixed_query(self):
        self.assertEqual(len(m.FIXTURE_TASK_COLUMNS),15)
        self.assertEqual(len(set(m.FIXTURE_TASK_COLUMNS)),15)
        sql=m.catalog_sql('tasks_unreviewed_fkey')
        for token in ('pg_catalog.pg_constraint','pg_catalog.pg_attribute',
                      'pg_catalog.pg_trigger','current_database()=\'postgres\'',
                      'nt.nspname=\'atlas\'','tc.relname=\'tasks\'',
                      'cardinality(c.conkey)','(t.tgtype & 7)=7','(t.tgtype & 7)=5'):
            self.assertIn(token,sql)
        self.assertNotIn('PRIVATE',sql)
        self.assertNotIn('SELECT *',sql.upper())
        for invalid in ('tasks_unreviewed_fkey; DROP TABLE atlas.tasks',
                        'tasks_unreviewed', 'foreign_fkey'):
            with self.assertRaises(m.StructuralRefusal):
                m.catalog_sql(invalid)

    def test_single_unlisted_and_composite_mixed(self):
        r='{"arity":1,"fixtureListed":0,"defaultedOrGenerated":0,"beforeRowInsert":true,"afterRowInsert":true}'
        self.assertEqual(m.classify_catalog(r),
                         'single_none_listed_no_auto_column_before_present_after_present')
        r='{"arity":2,"fixtureListed":1,"defaultedOrGenerated":1,"beforeRowInsert":false,"afterRowInsert":true}'
        self.assertEqual(m.classify_catalog(r),
                         'composite_mixed_listed_auto_column_before_absent_after_present')
        r='{"arity":1,"fixtureListed":1,"defaultedOrGenerated":0,"beforeRowInsert":false,"afterRowInsert":false}'
        self.assertEqual(m.classify_catalog(r),
                         'single_all_listed_no_auto_column_before_absent_after_absent')

    def test_reject_untrusted_catalog_data(self):
        bad=[None,'null','{}','PRIVATE',
             '{"arity":true,"fixtureListed":0,"defaultedOrGenerated":0,"beforeRowInsert":true,"afterRowInsert":true}',
             '{"arity":1,"fixtureListed":2,"defaultedOrGenerated":0,"beforeRowInsert":true,"afterRowInsert":true}',
             '{"arity":1,"fixtureListed":0,"defaultedOrGenerated":2,"beforeRowInsert":true,"afterRowInsert":true}',
             '{"arity":1,"fixtureListed":0,"defaultedOrGenerated":0,"beforeRowInsert":1,"afterRowInsert":true}',
             '{"arity":1,"fixtureListed":0,"defaultedOrGenerated":0,"beforeRowInsert":true,"afterRowInsert":true,"SECRET":"EXPOSED"}',
             '{"arity":0,"fixtureListed":0,"defaultedOrGenerated":0,"beforeRowInsert":true,"afterRowInsert":true}',
             '{"arity":17,"fixtureListed":0,"defaultedOrGenerated":0,"beforeRowInsert":true,"afterRowInsert":true}']
        for s in bad:
            with self.subTest(s=str(s)[:40]):
                self.assertEqual(m.classify_catalog(s),'catalog_untrusted')

    def test_only_allowlisted_clones_may_query(self):
        calls=[]
        def sql(db,query):
            calls.append((db,query))
            return '{"arity":1,"fixtureListed":0,"defaultedOrGenerated":0,"beforeRowInsert":true,"afterRowInsert":true}'
        e=err()
        self.assertEqual(m.classify_exception(e,DB,sql,'catalog_unknown_column'),
                         'single_none_listed_no_auto_column_before_present_after_present')
        self.assertEqual(len(calls),1)
        for args,result in ((('postgres://postgres:pw@remote:5432/postgres','catalog_unknown_column'),'not_disposable'),
                            ((DB,'task_ref_task'),'prior_stage_mismatch')):
            self.assertEqual(m.classify_exception(e,args[0],sql,args[1]),result)
        self.assertEqual(m.classify_exception(err('other_name_fkey'),DB,sql,'catalog_unknown_column'),'invalid_constraint')
        self.assertEqual(m.classify_exception(ValueError('PRIVATE'),DB,sql,'catalog_unknown_column'),'invalid_constraint')
        self.assertEqual(len(calls),1)
        def fail_sql(*args):
            raise ValueError('PRIVATE detail')
        self.assertEqual(m.classify_exception(e,DB,fail_sql,'catalog_unknown_column'),'catalog_unavailable')

    def test_exact_finite_report(self):
        token='single_none_listed_no_auto_column_before_present_after_present'
        self.assertIn(token,m.FINITE_RESULTS)
        self.assertEqual(m.extract('irrelevant'), 'not_reported')
        self.assertEqual(m.extract(m.RECEIPT+token+'\nDETAIL: PRIVATE'),'single_none_listed_no_auto_column_before_present_after_present')
        self.assertEqual(m.extract(m.RECEIPT+'PRIVATE'), 'untrusted_report')
        self.assertEqual(m.extract(m.RECEIPT+token+'\n'+m.RECEIPT+token),'ambiguous_report')
        self.assertEqual(m.extract(['PRIVATE']),'untrusted_report')

if __name__=='__main__':
    unittest.main(verbosity=2)
