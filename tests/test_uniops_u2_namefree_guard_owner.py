"""Regression-only checks; never needs credentials or private source SQL."""
import importlib.util
import unittest
from pathlib import Path

spec=importlib.util.spec_from_file_location(
    'guard',Path(__file__).with_name('uniops_u2_namefree_guard_owner.py'))
guard=importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class NamefreeGuardTests(unittest.TestCase):
    def test_no_raw_message_in_sql_or_result(self):
        private="Private named Person '123' permission guard"
        calls=[]
        def query(_db, statement):
            calls.append(statement)
            return 'atlas_source:0007'
        self.assertEqual(
            guard.classify_namefree_source('local',private,query),
            ('atlas_source','0007'))
        self.assertNotIn(private,calls[0])
        self.assertIn('pg_catalog.pg_proc',calls[0])
        self.assertIn('pg_catalog.quote_literal',calls[0])
        self.assertNotIn('UPDATE ',calls[0])
        self.assertNotIn('DELETE ',calls[0])

    def test_unknown_and_ambiguous_fail_closed(self):
        for response in ('unmapped:0000','ambiguous:0000'):
            self.assertEqual(
                guard.classify_namefree_source(
                    'local','Unknown guard',lambda d,q:response),
                tuple(response.split(':')))

    def test_untrusted_catalog_response_is_suppressed(self):
        for resp in ('atlas_source:0000','atlas_source:123456',
                     'private_source:0001','SECRET',
                     'atlas_source:0001\npassword',''):
            self.assertEqual(
                guard.classify_namefree_source(
                    'local','Known guard',lambda d,q:resp),
                ('catalog_error','0000'))

    def test_invalid_message_skips_query(self):
        def forbidden(db,q):
            raise AssertionError('Must not query')
        for message in ('',None,'x'*513,'new\nline'):
            self.assertEqual(
                guard.classify_namefree_source('local',message,forbidden),
                ('unmapped','0000'))

    def test_catalog_failure_fails_closed(self):
        def broken(db,q):
            raise ValueError('private SQL details')
        self.assertEqual(
            guard.classify_namefree_source('local','Known guard',broken),
            ('catalog_error','0000'))


if __name__=='__main__':
    unittest.main()
