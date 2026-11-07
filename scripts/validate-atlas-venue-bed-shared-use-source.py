#!/usr/bin/env python3
"""HELD Venue Bed shared-use SOURCE guard; not a runtime authorization proof.

This intentionally does not run held DDL against the real database. Protected
full-schema disposable clone + independent signed GoTrue/PostgREST actors
remain mandatory before release. Python stdlib only.
"""
from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
CANDIDATE = ROOT / "candidates/atlas/venue_bed_shared_use_v1/HELD_source_candidate.sql"

SOURCE_TABLES = (
    "atlas.work_items",
    "atlas.growing_objects",
    "atlas.farm_crop_ledger_custody_v1",
    "atlas.work_item_context_links",
    "atlas.company_work_native_ledger_relevance",
    "atlas.principal_ledger_authorities",
    "atlas.ledger_organization_participations",
)
SOURCE_FUNCTIONS = (
    "venue_bed_shared_use_source_current_v1",
    "offer_venue_bed_shared_use_self_v1",
    "accept_venue_bed_shared_use_self_v1",
    "establish_venue_work_bed_reference_self_v1",
    "withdraw_venue_bed_shared_use_self_v1",
)


def no_comments(text: str) -> str:
    return "\n".join(
        line.split("--", 1)[0] for line in text.splitlines()
    )


def assert_source_only(sql: str) -> None:
    src = no_comments(sql)
    normalized = re.sub(r"\s+", " ", src).strip()

    for table in ("venue_bed_shared_use_authorizations_v1", "venue_bed_work_references_v1"):
        assert re.search(rf"\bCREATE TABLE atlas\.{table}\b", src), table
        assert re.search(rf"\bALTER TABLE atlas\.{table} ENABLE ROW LEVEL SECURITY\b", src), table
        assert re.search(
            rf"\bREVOKE ALL ON TABLE atlas\.{table} FROM PUBLIC, anon, authenticated\b", src
        ), table

    assert len(re.findall(r"\bCREATE FUNCTION atlas\.", src)) == 5
    for fn in SOURCE_FUNCTIONS:
        assert f"CREATE FUNCTION atlas.{fn}(" in src, fn
        assert re.search(
            rf"\bREVOKE ALL ON FUNCTION atlas\.{fn}\(",
            src,
        ), fn

    assert len(re.findall(r"\bSECURITY DEFINER SET search_path TO ''", src)) == 5
    assert not re.search(r"\bCREATE OR REPLACE\b", src)
    assert not re.search(r"\bCREATE FUNCTION public\.", src, flags=re.I)
    assert not re.search(r"\bGRANT\b", src, flags=re.I)
    assert not re.search(
        r"\b(DROP|TRUNCATE)\b|\bALTER (?:TABLE|FUNCTION)\s+(?!atlas\.venue_bed_)",
        src,
        flags=re.I,
    ), "preexisting schema must be protected"
    for source_table in SOURCE_TABLES:
        assert not re.search(
            rf"\b(?:INSERT INTO|UPDATE|DELETE FROM)\s+{re.escape(source_table)}\b",
            src, flags=re.I,
        ), source_table

    # Exact Original Flower custody is the authority for Bed admission;
    # an Org name, Venue Work ID, or physical Zone tag is not sufficient.
    required = (
        "JOIN atlas.farm_crop_ledger_custody_v1 custody",
        "custody.ledger_id=p_flower_ledger_id",
        "custody.custody_state='active'",
        "AND bed.object_type='bed'",
        "atlas.principal_has_ledger_authority_v1(",
        "atlas.current_active_ledger_seat_v1(",
        "atlas.reality_access_self_api_v1()",
        "atlas.company_work_native_ledger_relevance relevance",
        "relevance.attribution_state='active'",
        "participation.status='active'",
        "v_work.work_state<>'open'",
        "reviewedWorkStableKey",
        "reviewedBedStableKey",
        "p_human_review->>'humanConfirmed'",
        "use_state='active'",
        "use_state='withdrawn'",
        "withdrawn_by_principal_id",
        "SOURCE",
    )
    # Literal required lines from executable source rather than comment.
    for phrase in required[:-1]:
        assert phrase in src, f"Missing required source guard: {phrase}"
    assert len(re.findall(r"reality_access_self_api_v1\(\)", src)) >= 4
    assert "confersAccess" not in src, "no new content grant by relationship"
    assert "CREATE TRIGGER" not in src
    assert src.startswith("\n") or "BEGIN;" in src
    assert "COMMIT;" in normalized

    # A Work association is explicit and references one already-existing Work:
    assert "work_item_id uuid NOT NULL REFERENCES atlas.work_items(id) ON DELETE RESTRICT" in src
    assert "bed_id uuid NOT NULL REFERENCES atlas.growing_objects(id) ON DELETE RESTRICT" in src
    assert "venue_ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT" in src
    assert "UNIQUE (venue_ledger_id, work_item_id, bed_id)" in src

class SourceGuardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = CANDIDATE.read_text(encoding="utf-8")

    def test_held_candidate(self) -> None:
        assert_source_only(self.source)

    def test_rejects_original_farm_mutation(self) -> None:
        with self.assertRaises(AssertionError):
            assert_source_only(self.source.replace("COMMIT;", "UPDATE atlas.growing_objects SET label='bad'; COMMIT;"))

    def test_rejects_public_wildcard_grant(self) -> None:
        with self.assertRaises(AssertionError):
            assert_source_only(self.source.replace("COMMIT;", "GRANT ALL ON TABLE atlas.growing_objects TO authenticated; COMMIT;"))

    def test_rejects_removed_signed_session(self) -> None:
        with self.assertRaises(AssertionError):
            assert_source_only(self.source.replace("atlas.reality_access_self_api_v1()", "to_jsonb('ready'::text)"))

    def test_rejects_rewritten_flower_guard(self) -> None:
        with self.assertRaises(AssertionError):
            assert_source_only(self.source.replace("COMMIT;", "CREATE OR REPLACE FUNCTION atlas.guard_work_growing_object_context_v1() RETURNS trigger; COMMIT;"))

if __name__ == "__main__":
    unittest.main(verbosity=2)
