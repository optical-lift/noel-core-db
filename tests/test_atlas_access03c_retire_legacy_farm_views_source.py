#!/usr/bin/env python3
"""ACCESS-03C: audit one exact four-view legacy interface retirement; source only."""
import re
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
DIR=ROOT/"candidates/atlas/atlas_access03c_retire_legacy_farm_operational_views_v1"
SQL=(DIR/"candidate.sql").read_text()
POST=(DIR/"postconditions.sql").read_text()
EXPECTED=(
 "farm_care_object_projection_v1",
 "tending_task_track_v1",
 "farm_care_object_state_v1",
 "v_farm_object_operational_state",
)

class UniversalAtlasLegacyViewRetirement(unittest.TestCase):
    def test_exact_dependency_order_and_restrict_only(self):
        drops=re.findall(r"^DROP VIEW atlas\.([a-z0-9_]+) RESTRICT;$",SQL,re.M)
        self.assertEqual(drops,list(EXPECTED),"DROP only exact four reviewed legacy views in safe dependency order")
        self.assertEqual(SQL.count("DROP VIEW "),4)
        self.assertEqual(SQL.count("ALTER POLICY "),0)
        self.assertEqual(SQL.count("CREATE FUNCTION "),0)
        self.assertTrue(SQL.startswith("-- ACCESS-03C SOURCE ONLY"))
        self.assertIn("BEGIN;",SQL)
        self.assertTrue(SQL.rstrip().endswith("COMMIT;"))
        for forbidden in (
            "DROP TABLE ", "TRUNCATE ", "DELETE FROM ",
            "UPDATE atlas.", "INSERT INTO ", "CASCADE;", "GRANT SELECT",
            "REVOKE SELECT", "DISABLE ROW LEVEL SECURITY",
            "DROP FUNCTION", "DROP SCHEMA",
        ):
            self.assertNotIn(forbidden,SQL)

    def test_prerequisite_only_after_03b_canonical_governance(self):
        self.assertIn("to_regprocedure('atlas.can_read_native_governed_farm_full_self_v1(uuid)') IS NULL",SQL)
        self.assertIn("qual='atlas.can_read_native_governed_farm_full_self_v1(farm_id)'",SQL)
        self.assertIn("has_table_privilege('authenticated','atlas.zones','SELECT')",SQL)
        self.assertIn("ACCESS03C requires released governed 03B",SQL)
        self.assertIn("ACCESS03C unexpected downstream view dependency",SQL)
        self.assertIn("ACCESS03C unreviewed view family dependents",SQL)
        for name in EXPECTED:
            self.assertIn(name,SQL)
            self.assertIn(f"to_regclass('atlas.{name}') IS NOT NULL",POST)
        for source_hash in (
            "d541cb041506c3fdd3594cf8f47a8e8d",
            "1134b7267249ac92a60176f4da23f6a3",
            "518463fd12aeb5f3465998833808606b",
            "5cd80e07b501999dc4f64fd4601e4300",
        ):
            self.assertIn(source_hash,SQL)

    def test_preserve_universal_and_original_source(self):
        for name in (
            "connected_person_farm_current_inventory_self_api_v1",
            "governor_farm_current_inventory_options_self_api_v1",
            "zone_registry_source_v1",
            "object_crop_bed_map_v1",
            "farm_care_zone_v1",
        ):
            self.assertIn(name,SQL)
            self.assertIn(name,POST)
        for name in ("atlas.zones","atlas.growing_objects","atlas.crop_cycles"):
            self.assertIn(name,POST)
        self.assertIn("atlas.farm_memberships",POST)
        self.assertIn("ACCESS03C retained canonical tables / RLS missing",POST)
        for forbidden in ("DELETE FROM ", "TRUNCATE ", "DROP VIEW ", "ALTER TABLE ", "UPDATE atlas."):
            self.assertNotIn(forbidden,POST)

if __name__=="__main__":
    unittest.main()
