#!/usr/bin/env python3
"""Review-only negative source contract: one orphan queue backfill FUNCTION DROP."""
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/"candidates/atlas/atlas_legacy_queue_orphan_backfill_retirement_v1"
SQL=(BASE/"candidate.sql").read_text()
POST=(BASE/"postconditions.sql").read_text()
DOC=(BASE/"README.md").read_text()

def uncommented(text):
    return re.sub(r"(?m)^\s*--[^\n]*\n?", "", text)

class HeldBackfillSourceContract(unittest.TestCase):
    def test_only_one_exact_restrict_drop(self):
        s=uncommented(SQL)
        matches=re.findall(r"\bDROP\s+(?:FUNCTION|TABLE|VIEW|TRIGGER|SCHEMA)\s+[^;]+;",s,re.I)
        self.assertEqual(
            [re.sub(r"\s+"," ",m).strip() for m in matches],
            ["DROP FUNCTION atlas.backfill_active_task_release_gates_v1() RESTRICT;"]
        )
        self.assertNotRegex(s,r"(?i)\bCASCADE\b")

    def test_fail_closed_source_identity_and_all_known_consumer_classes(self):
        for token in (
            "623f52a2ff3ae732cdc62e459be8bfca",
            "md5(pg_catalog.pg_get_functiondef(p.oid))",
            "to_regprocedure('atlas.backfill_active_task_release_gates_v1()')",
            "pg_catalog.pg_depend",
            "pg_catalog.pg_trigger",
            "pg_catalog.pg_proc",
            "pg_catalog.pg_namespace",
            "p.prokind IN ('f','p')",
            "has_function_privilege('anon'",
            "has_function_privilege('authenticated'",
            "has_function_privilege('service_role'",
            "to_regclass('cron.job') IS NULL",
            "SELECT 1 FROM cron.job",
            "RAISE EXCEPTION",
            "BEGIN;",
            "COMMIT;",
        ):
            with self.subTest(token=token):
                self.assertIn(token,SQL)

    def test_no_data_mutation_or_permission_migration(self):
        s=uncommented(SQL+" \n"+POST)
        self.assertNotRegex(s,r"(?i)\b(?:INSERT\s+INTO|UPDATE\s+\w+|DELETE\s+FROM|TRUNCATE|DROP\s+TABLE|ALTER\s+TABLE|GRANT|REVOKE|CREATE\s+POLICY|ALTER\s+POLICY)\b")
        self.assertEqual(len(re.findall(r"\bDROP\s+FUNCTION\b",s,re.I)),1)
        self.assertNotIn("service_role SET ROLE",s)

    def test_legacy_queue_and_canonical_work_both_remain(self):
        for sql in (SQL,POST):
            self.assertIn("to_regclass('atlas.task_release_queue_items')",sql)
            self.assertIn("to_regclass('atlas.work_items')",sql)
        self.assertIn("to_regprocedure('atlas.backfill_active_task_release_gates_v1()') IS NOT NULL",POST)

    def test_source_notes_explicit_hold_and_no_false_launch_claim(self):
        for token in ("NOT compiled or signed tested","NO production deletion authorized",
                      "33 old queue-function-body mentions","97 queue row states",
                      "November 4 decision 6A", "external/admin"):
            self.assertIn(token,DOC)

if __name__=="__main__":
    unittest.main(verbosity=2)
