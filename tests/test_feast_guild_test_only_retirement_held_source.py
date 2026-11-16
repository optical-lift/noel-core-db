"""Source-only custody checks: no hosted database, credentials or real identifiers."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1] / "candidates/atlas/feast_guild_test_only_retirement_held_v1"
SOURCE = ROOT / "retire_held.sql"
FIXTURE = ROOT / "pg17/fixture.sql"
RUNNER = ROOT / "pg17/run_synthetic.sh"

class FeastGuildTestOnlyRetirementSource(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")
        cls.sql = "\n".join(l for l in cls.source.splitlines() if not l.strip().startswith("--")).lower()
        cls.fixture = FIXTURE.read_text(encoding="utf-8").lower()
        cls.runner = RUNNER.read_text(encoding="utf-8")

    def test_exact_four_deletions_only(self):
        targets = re.findall(r"\bdelete\s+from\s+([a-z_]+\.[a-z_]+)", self.sql)
        self.assertEqual(targets, [
            "atlas.principal_ledger_authorities",
            "atlas.ledger_organization_participations",
            "atlas.ledgers", "atlas.organizations"
        ])

    def test_source_fails_closed_on_identity_and_cardinality(self):
        for s in [
            "onboarding_state='new'", "canonicalinstitution",
            "canonicalendeavor", "2026-09-14",
            "participation_kind='governing'", "authority_kind='root_governing'",
            "select id into strict", "for update",
            "native ledger/onboarding source exists",
            "pg_constraint", "information_schema.columns",
            "organization_ledger_subjects", "row_count",
        ]:
            with self.subTest(needle=s):
                self.assertIn(s, self.sql)

    def test_no_side_effects_beyond_exact_deletions(self):
        for denied in [" cascade", "drop table", "truncate", "alter table",
                       "create table", "grant ", "revoke ", "security definer",
                       "insert into", "update atlas.", "auth.users",
                       "atlas.work_items", "atlas.tasks"]:
            with self.subTest(denied=denied):
                self.assertNotIn(denied, self.sql)
        self.assertTrue(self.source.lstrip().startswith("-- HELD SOURCE CANDIDATE ONLY"))

    def test_synthetic_tests_positive_and_negative(self):
        self.assertIn("create table atlas.farms", self.fixture)
        self.assertIn("create table atlas.nonfk_seat_probe", self.fixture)
        for case in [
            "positive", "foreign_key_block", "unguarded_uuid_block",
            "source_identity_mismatch", "native_ledger_block",
            "native_case_block", "other_organization_join", "text_reference",
        ]:
            with self.subTest(case=case):
                self.assertIn("run_case "+case, self.runner)
        self.assertNotIn("supabase.co", self.runner)
        self.assertNotIn("SUPABASE_", self.runner)

if __name__ == "__main__":
    unittest.main()
