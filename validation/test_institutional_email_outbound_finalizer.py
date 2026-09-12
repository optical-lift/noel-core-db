import pathlib
import unittest

ROOT = pathlib.Path(__file__).parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "20260912114723_atlas_communication_outbound_transport_finalize_v1.sql"


class FinalizerMigrationTests(unittest.TestCase):
    def test_transport_only_finalizer_owns_canonical_construction(self):
        sql = MIGRATION.read_text()
        self.assertIn("finalize_communication_outbound_transport_service_v1", sql)
        self.assertIn("record_communication_outbound_result_service_v2", sql)
        self.assertIn("'schemaVersion','atlas_communication_event_v1'", sql)
        self.assertIn("'direction','outgoing'", sql)
        self.assertIn("'sourceAuthority','evidence_only'", sql)
        self.assertIn("'permittedStateEffect','append_source_attributed_evidence_only'", sql)
        self.assertIn("'governingStateChanged',false", sql)
        self.assertNotIn("prepare_institutional_email_send_self_api_v1", sql)

    def test_finalizer_preserves_existing_uncertainty_boundary(self):
        sql = MIGRATION.read_text()
        self.assertIn("Ambiguous post-DATA outcomes must not call this function", sql)
        self.assertNotIn("transport_uncertain' then", sql)
        self.assertNotIn("operation_state='authorized'", sql)

    def test_sql_wrapper_is_transactional_and_function_delimiters_balance(self):
        sql = MIGRATION.read_text().strip()
        self.assertTrue(sql.startswith("begin;"))
        self.assertTrue(sql.endswith("commit;"))
        self.assertEqual(2, sql.count("$function$"))


if __name__ == "__main__":
    unittest.main()
