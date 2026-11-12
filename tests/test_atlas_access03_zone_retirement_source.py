#!/usr/bin/env python3
"""ACCESS-03A SOURCE-ONLY contract. Not signed acceptance."""
import re
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/"candidates/atlas/atlas_access03_retire_legacy_zone_direct_read_v1"
C=(BASE/"candidate.sql").read_text()
P=(BASE/"postconditions.sql").read_text()
F=(BASE/"fixture.sql").read_text()
class Access03Source(unittest.TestCase):
    def test_candidate_scope(self):
        self.assertEqual(C.count("DROP POLICY"),1)
        self.assertEqual(C.count("REVOKE SELECT ON TABLE"),2)
        self.assertIn("DROP POLICY zones_read_operations ON atlas.zones;",C)
        for table in ("atlas.zones","atlas.v_crop_cycle_registry"):
            self.assertIn(f"REVOKE SELECT ON TABLE {table} FROM authenticated;",C)
            self.assertIn(f"has_table_privilege('authenticated','{table}','SELECT')",P)
        for token in ("access03_preflight","security_invoker=true",
                      "connected_person_farm_current_inventory_self_api_v1",
                      "zone_registry_source_v1"):
            self.assertIn(token,C)
        statements=re.sub(r"--[^\n]*"," ",C).upper()
        for forbidden in ("DROP TABLE","DROP VIEW","CASCADE","TRUNCATE","DELETE FROM",
                          "INSERT INTO","UPDATE ATLAS.","GRANT ","DROP FUNCTION"):
            self.assertNotIn(forbidden,statements)
    def test_no_historical_row_mutation(self):
        self.assertIn("role='manager'",F)
        self.assertIn("INSERT INTO atlas.zones",F)
        self.assertIn("INSERT INTO atlas.crop_cycles",F)
        self.assertNotIn("supabase.co",F)
        self.assertNotIn("zirqkouammpwxlqfbsvf",F)
        clean=re.sub(r"--[^\n]*"," ",F)
        disallowed=re.compile(r"\b(create|alter|drop|truncate|grant|revoke|comment|vacuum|analyze|reindex|cluster|refresh|copy|do|call|execute|prepare|deallocate|listen|notify|security)\b",re.I)
        self.assertIsNone(disallowed.search(clean))
        statements=[s.strip() for s in clean.split(";") if s.strip()]
        self.assertEqual(len(statements),33)
        self.assertTrue(all(re.match(r"^(select|update|insert\s+into)\b",s,re.I) for s in statements))
    def test_fixture_reuses_c1_prerequisite_exactly(self):
        original=(ROOT/"validation/fixtures/20261026215011_atlas_universal_original_work_integrated_v1.sql").read_text()
        prefix=original.split("-- Original Event signed regression fixture")[0].rstrip()+"\n\n"
        self.assertIn("Original blob SHA e877d93323ddc67d8778be8bea1dfa34319cc85c",F)
        self.assertIn(prefix,F)
        self.assertIn("e5200000-0000-4000-8000-000000000b06",F)
    def test_sql_parses(self):
        try:
            from pglast import parse_sql
        except ImportError:
            self.skipTest("Pinned SQL parser installed by protected workflow")
        self.assertEqual(len(parse_sql(C)),6)
        self.assertEqual(len(parse_sql(P)),1)
        self.assertEqual(len(parse_sql(F)),33)
if __name__=="__main__":
    unittest.main()
