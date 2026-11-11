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
    assert "UNIQUE (use_authorization_id, work_item_id)" in src
    assert "UNIQUE (id, venue_ledger_id, bed_id)" in src
    assert "FOREIGN KEY (use_authorization_id, venue_ledger_id, bed_id)" in src
    assert "(id, venue_ledger_id, bed_id) ON DELETE RESTRICT" in src

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



class IndependentOriginalBedReferenceCloneTests(unittest.TestCase):
    """Static mirror contract before owner-only disposable signed clone run."""

    def test_exact_held_source_mirror_and_clone_only_wrapper(self) -> None:
        source_dir=ROOT / "candidates/atlas/ledger_work_existing_object_reference_v1"
        source=(source_dir/"HELD_source_candidate.sql").read_text(encoding="utf-8")
        wrapper=(source_dir/"clone_test_api_DISPOSABLE_ONLY.sql").read_text(
            encoding="utf-8")
        transport=(ROOT/"candidates/atlas/venue_bed_shared_use_v1/"
                   "clone_signed_transport_DISPOSABLE_ONLY.sql").read_text(
                       encoding="utf-8")
        marker="-- BEGIN CLONE-ONLY MIRROR: independent Ledger same-original-Bed reference v1"
        end="-- END CLONE-ONLY MIRROR: independent Ledger same-original-Bed reference v1"
        expected=(marker+"\n"+source.rstrip()+"\n\n"+wrapper.rstrip()+"\n"+end+"\n")
        self.assertTrue(transport.endswith(expected),
                        "Only exact independently held source + guarded clone transport is admissible")
        self.assertIn("CREATE TABLE atlas.ledger_work_existing_bed_references_v1",source)
        self.assertIn("ENABLE ROW LEVEL SECURITY",source)
        self.assertIn("REVOKE ALL ON TABLE atlas.ledger_work_existing_bed_references_v1",source)
        self.assertIn("REVOKE ALL ON FUNCTION",source)
        self.assertIn("person_has_native_ledger_connection_v1",source)
        self.assertIn("company_work_native_ledger_relevance",source)
        self.assertIn("principal_has_ledger_authority_v1",source)
        self.assertIn("ledger_occurrence_shared_work_actor_self_v1",source)
        self.assertNotIn("offer_venue_bed_shared_use_self_v1",source)
        self.assertNotIn("accept_venue_bed_shared_use_self_v1",source)
        self.assertNotRegex(source,re.compile(r"\bINSERT\s+INTO\s+atlas\."
                                             r"(?:growing_objects|work_items)\b",re.I))
        self.assertNotIn("GRANT EXECUTE",source)
        self.assertIn("current_database() <> 'postgres'",wrapper)
        self.assertIn("clone-upick-bed-3",wrapper)
        self.assertIn("SECURITY DEFINER",wrapper)
        self.assertNotRegex(wrapper,re.compile(
           r"\bGRANT\s+EXECUTE\s+ON\s+FUNCTION\s+atlas\.",re.I))

    def test_true_signed_proof_runs_before_old_offer(self) -> None:
        signed=(ROOT/"scripts/validate-atlas-venue-bed-signed-http.py").read_text(
            encoding="utf-8")
        self.assertIn("def prove_independent_bed_reference(",signed)
        invoke="venue=prove_independent_bed_reference(api,key,db,actors)"
        self.assertIn(invoke,signed)
        self.assertLess(signed.index(invoke),signed.index(
            'offer=accepted(api,key,owner,"offer",offer_args())'))
        self.assertIn("DELETE FROM auth.sessions",signed)
        self.assertIn("PASS genuine signed independent Venue original Work",signed)
        self.assertIn("No Flower offer may exist before independent Venue link proof",signed)

if __name__ == "__main__":
    unittest.main(verbosity=2)
