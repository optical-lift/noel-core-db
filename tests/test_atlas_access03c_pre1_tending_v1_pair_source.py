#!/usr/bin/env python3
"""Fail-closed source contract for the exact ACCESS-03C-PRE1 function pair."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIR = ROOT / "candidates/atlas/atlas_access03c_pre1_tending_v1_pair_retirement_v1"
SQL = (DIR / "candidate.sql").read_text()
POST = (DIR / "postconditions.sql").read_text()
README = (DIR / "README.md").read_text()

class TendingV1PairRetirement(unittest.TestCase):
    def test_exact_two_function_drops_ordered_restrict(self):
        drops = re.findall(r"^DROP FUNCTION atlas\.([a-z0-9_]+\([^;]+\)) RESTRICT;$", SQL, re.M)
        self.assertEqual(drops, [
            "tending_task_context_v1(uuid,uuid,text)",
            "tending_card_json_v1(uuid,jsonb,boolean)",
        ])
        self.assertEqual(SQL.count("DROP FUNCTION "), 2)
        self.assertEqual(SQL.count("DROP VIEW "), 0)
        self.assertTrue(SQL.startswith("-- ACCESS-03C-PRE1 SOURCE ONLY"))
        self.assertIn("BEGIN;",SQL)
        self.assertTrue(SQL.rstrip().endswith("COMMIT;"))
        for forbidden in (
            "CASCADE;", "DROP TABLE ", "DROP SCHEMA ", "ALTER POLICY ",
            "ALTER TABLE ", "CREATE FUNCTION ", "REVOKE ", "GRANT ",
            "TRUNCATE ", "DELETE FROM ", "INSERT INTO ", "UPDATE atlas.",
            "DISABLE ROW LEVEL SECURITY",
        ):
            self.assertNotIn(forbidden, SQL)

    def test_fail_closed_schema_privileges_and_runtime_dependencies(self):
        for required in (
            "to_regprocedure('atlas.can_read_native_governed_farm_full_self_v1(uuid)')",
            "qual='atlas.can_read_native_governed_farm_full_self_v1(farm_id)'",
            "has_table_privilege('authenticated','atlas.zones','SELECT')",
            "26ca1f7a3d1a16f1fc5b1aed9f2fae42",
            "510f783e3162b1052b6081fb8fa3271b",
            "has_function_privilege('service_role'",
            "has_function_privilege('authenticated'",
            "has_function_privilege('anon'",
            "pg_catalog.pg_depend",
            "pg_catalog.pg_get_functiondef(p.oid)",
            "ACCESS03C-PRE1 unexpected runtime function-body consumer",
            "ACCESS03C-PRE1 unexpected catalog dependency",
        ):
            self.assertIn(required, SQL)

    def test_preserves_v2_and_canonical_source(self):
        for source in (SQL, POST):
            for name in (
                "tending_task_context_v2",
                "tending_card_json_v2",
                "tending_task_track_v1",
                "zone_registry_source_v1",
                "farm_care_zone_v1",
                "owner_effective_subject_disclosure_review_self_api_v1",
            ):
                self.assertIn(name, source)
            for fingerprint in (
                "48a972d24a0b168211fbde6d8e6eb5d0",
                "5621f5f54676f0310f54ea726cf7340e",
                "ac9f651584032997fb5106433190e245",
            ):
                self.assertIn(fingerprint, source)
        for name in ("tasks","zones","growing_objects","crop_cycles","care_state_history"):
            self.assertIn("atlas."+name,POST)
        self.assertIn("to_regprocedure('atlas.tending_task_context_v1(uuid,uuid,text)') IS NOT NULL",POST)
        self.assertIn("to_regprocedure('atlas.tending_card_json_v1(uuid,jsonb,boolean)') IS NOT NULL",POST)

    def test_external_snapshot_census_is_pinned_read_only_and_historical(self):
        scan=(DIR/"audit_farm_atlas_consumers.py").read_text()
        workflow=(ROOT/".github/workflows/atlas-access03c-pre1-tending-v1-source.yml").read_text()
        self.assertIn('TARGETS = ("tending_task_context_v1", "tending_card_json_v1")',scan)
        self.assertIn("tests/atlas-narrow-tending-helpers.test.mjs",scan)
        self.assertIn("source_inventory(repo)",scan)
        self.assertIn('require(not hits',scan)
        self.assertIn('rpc("tending_task_context_v2"',scan)
        self.assertIn('rpc("tending_bed_v1"',scan)
        self.assertIn('rpc("tending_board_v1"',scan)
        self.assertIn("NOT PROVEN:",scan)
        self.assertIn("repository: optical-lift/farm-atlas",workflow)
        self.assertIn("1090d872754c170c61760a03ad232182f0538476",workflow)
        self.assertIn("git ls-remote https://github.com/optical-lift/farm-atlas.git refs/heads/main",workflow)
        self.assertIn("audit_farm_atlas_consumers.py external/farm-atlas",workflow)
        self.assertNotIn("DROP FUNCTION",scan)
        self.assertNotIn("supabase execute",scan)

    def test_no_claim_of_exhaustive_external_audit_or_release(self):
        self.assertIn("HELD SOURCE CANDIDATE", README)
        self.assertIn("incomplete", README)
        self.assertIn("signed synthetic",README)
        self.assertIn("DATA",README.upper())
        self.assertIn("tending_task_context_v2",README)
        self.assertIn("farm-atlas",README)
        self.assertIn("not",README.lower())
        self.assertNotIn("DROP FUNCTION",POST)
        for forbidden in ("DROP TABLE ","DELETE FROM ","GRANT ","REVOKE "):
            self.assertNotIn(forbidden,POST)
if __name__ == "__main__":
    unittest.main()
