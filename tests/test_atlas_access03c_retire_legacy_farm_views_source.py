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

    def test_runtime_function_body_dependencies_fail_closed(self):
        # pg_depend does not reliably capture PL/pgSQL SQL body relation use.
        for content, message in (
            (SQL, "ACCESS03C function-body consumers of obsolete views remain"),
            (POST, "ACCESS03C residual runtime function-body dependency"),
        ):
            self.assertIn("pg_catalog.pg_proc", content)
            self.assertIn("pg_catalog.pg_get_functiondef(p.oid)", content)
            self.assertIn("p.prokind='f'", content)
            self.assertIn("n.nspname='atlas'", content)
            self.assertIn(message, content)
            for view in EXPECTED:
                self.assertIn(view, content)

    def test_exact_runtime_consumer_inventory_is_read_only_and_dispositioned(self):
        census=(DIR/"consumer_census.sql").read_text()
        disposition=(DIR/"CONSUMER_DISPOSITION.md").read_text()
        self.assertTrue(census.startswith("-- ACCESS-03C consumer census: READ ONLY"))
        self.assertIn("to_regprocedure(e.signature)",census)
        self.assertIn("pg_get_functiondef(q.oid)",census)
        self.assertIn("textual_references_not_proven_calls",census)
        self.assertIn("six with",disposition)
        self.assertIn("tending_task_context_v1",disposition)
        self.assertIn("tending_card_json_v1",disposition)
        self.assertIn("farm_care_zone_v1",disposition)
        expected={
            "atlas.farm_care_object_card_v1(uuid)": "912250a84abe2680e98890862316f1c3",
            "atlas.farm_care_summary_v1(uuid,integer)": "48a41b97be1f51ce7aa7a12422777bf6",
            "atlas.farm_care_zone_card_v1(uuid)": "36fe032b49403d4978385f24fb6b5822",
            "atlas.farm_care_zone_v1(uuid,text,integer)": "d83dd57420af32defe491a3d1ece7b1b",
            "atlas.tending_bed_v1(uuid,text,text)": "c9311300e2b5fb0bef2e0db5f87bca2d",
            "atlas.tending_board_v1(uuid,text,date)": "2ad9b2467a2102e86ada62eb0cc5ae39",
            "atlas.tending_card_json_v1(uuid,jsonb,boolean)": "510f783e3162b1052b6081fb8fa3271b",
            "atlas.tending_card_json_v2(uuid,uuid,jsonb,boolean)": "5621f5f54676f0310f54ea726cf7340e",
            "atlas.tending_task_context_v1(uuid,uuid,text)": "26ca1f7a3d1a16f1fc5b1aed9f2fae42",
            "atlas.tending_task_context_v2(uuid,uuid,text,text)": "48a972d24a0b168211fbde6d8e6eb5d0",
        }
        self.assertEqual(census.count("'atlas."),len(expected))
        for signature,source_hash in expected.items():
            self.assertIn("'"+signature+"'",census)
            self.assertIn(source_hash,census)
            self.assertIn(signature.split(".")[1].split("(")[0],disposition)
        # This file may be executed against a real schema for READ-ONLY audit;
        # never allow DDL, DML or permission changes into that tool.
        for forbidden in (
            "DROP VIEW ", "DROP FUNCTION ", "ALTER ", "CREATE ", "GRANT ",
            "REVOKE ", "DELETE FROM ", "UPDATE ", "INSERT INTO ", "TRUNCATE ",
        ):
            self.assertNotIn(forbidden,census.upper())

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
