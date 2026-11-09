#!/usr/bin/env python3
"""No-network contract tests for a HELD, wholly fictional U4 mowing-rule fixture.

These check only the test rule's positive/negative qualification matrix and
fixture custody. They are NOT genuine signed Actual, Result, or Done acceptance;
the separately owner-gated current-schema disposable clone must prove that.
"""
import json
import re
import unittest
from pathlib import Path

FIXTURE = Path(__file__).with_name(
    "uniops-option-a-first-mowing-signed-fixture.sql"
)
RULE_ID = "e5200000-0000-4000-8000-000000000d03"
EXACT = [{
    "effect": "full",
    "sourceKind": "mowing_result",
    "sourceEvent": "mowed_full",
}]


def fixture_sql():
    return FIXTURE.read_text(encoding="utf-8")


def qualification_touches(sql):
    """Extract the one fixture-owned rule value, never an inferred default."""
    part = sql.split("INSERT INTO atlas.rhythm_rules(", 1)[1].split(
        "INSERT INTO atlas.rhythm_bindings(", 1
    )[0]
    assert "validity_interval_seconds,qualifying_touches,metadata)" in part
    matches = re.findall(r"'(\[[^\n']*\])'::jsonb", part)
    assert len(matches) == 1, "One explicit fictional rule array required"
    return json.loads(matches[0])


def qualifies(touches, effect, source_kind, source_event):
    """Mirror the *qualification predicate* only, not the full SQL writer."""
    return any(
        t.get("effect") == effect
        and t.get("sourceKind") == source_kind
        and (
            t.get("sourceEvent") == source_event
            or source_event in t.get("sourceEvents", [])
        )
        for t in touches
    )


class FictionalMowingQualification(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = fixture_sql()
        cls.touches = qualification_touches(cls.sql)

    def test_exact_only_qualified_touch(self):
        self.assertEqual(self.touches, EXACT)
        self.assertTrue(qualifies(
            self.touches, "full", "mowing_result", "mowed_full"
        ))

    def test_nonqualifying_events_and_effects_remain_denied(self):
        for effect, kind, event in (
            ("partial", "mowing_result", "mowed_full"),
            ("conditional", "mowing_result", "acceptable_no_cut"),
            ("full", "mowing_result", "acceptable_no_cut"),
            ("full", "mowing_result", "mowed_partial"),
            ("full", "object", "mowed_full"),
            ("blocked", "mowing_result", "too_wet"),
            ("full", "field_log", "mowed_full"),
        ):
            with self.subTest(effect=effect, kind=kind, event=event):
                self.assertFalse(
                    qualifies(self.touches, effect, kind, event)
                )

    def test_source_rule_fails_closed_if_qualification_missing(self):
        self.assertFalse(
            qualifies([], "full", "mowing_result", "mowed_full")
        )
        self.assertFalse(
            qualifies([{"effect": "full", "sourceKind": "mowing_result"}],
                      "full", "mowing_result", "mowed_full")
        )
        self.assertFalse(
            qualifies([{"effect": "full", "sourceEvent": "mowed_full"}],
                      "full", "mowing_result", "mowed_full")
        )

    def test_fixture_guards_exact_rule_but_does_not_approve_work(self):
        self.assertIn("SET uniops.disposable_signed = 'true'", self.sql)
        self.assertIn("current_database()<>'postgres'", self.sql)
        self.assertIn('"physicalConditionAsserted":false', self.sql)
        self.assertIn("IS DISTINCT FROM", self.sql)
        self.assertIn("WHERE r.id='" + RULE_ID + "'::uuid", self.sql)
        self.assertNotIn("CREATE TABLE", self.sql)
        for forbidden in (
            "INSERT INTO atlas.governed_farm_rulebook_scope_versions_v1(",
            "INSERT INTO atlas.governed_prework_candidate_offers_v1(",
            "INSERT INTO atlas.work_items(",
            "INSERT INTO atlas.work_execution_results(",
            "INSERT INTO atlas.work_result_acceptances(",
        ):
            self.assertNotIn(forbidden, self.sql)


if __name__ == "__main__":
    unittest.main()
