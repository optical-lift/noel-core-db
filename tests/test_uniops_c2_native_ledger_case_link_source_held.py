#!/usr/bin/env python3
"""HELD UNI-OPS C2: no-network source-only exact Work relevance narrowing.

This test executes NO SQL, and does not authenticate, migrate, issue Work,
approve any role or run a protected production-schema clone. It verifies
an exact one-block candidate change against the installed source snapshot.
"""
from __future__ import annotations

import hashlib
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "docs/review/uniops_c2_native_ledger_requirement_work_scope_held"
BASE = SOURCE / "installed_baseline.sql"
CANDIDATE = SOURCE / "proposed_function_review_only.sql"
INSTALLED_SOURCE_MD5 = "ffcf0b1c8ab49b4d456037aa5f1147cf"

ANCHOR = """        where l.requirement_id=w.id and l.organization_id=r.organization_id
          and l.active
      ),'[]'::jsonb) as canonical_work"""

REPLACEMENT = """        where l.requirement_id=w.id and l.organization_id=r.organization_id
          and l.active
          and exists (
            select 1
            from atlas.company_work_native_ledger_relevance rel
            where rel.organization_id=i.organization_id
              and rel.work_item_id=i.id
              and rel.ledger_id=p_ledger_id
              and rel.attribution_state='active'
              and (
                rel.evidence_kind='owner_attested'
                or (
                  rel.evidence_kind='source_verified'
                  and exists (
                    select 1
                    from atlas.company_work_native_ledger_exact_source_v1(
                      rel.work_item_id,rel.ledger_id
                    ) proof
                    where proof.source_schema=rel.source_schema
                      and proof.source_table=rel.source_table
                      and proof.source_id=rel.source_id
                  )
                )
              )
          )
      ),'[]'::jsonb) as canonical_work"""


class HeldC2CaseSourceReview(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.before = BASE.read_text(encoding="utf-8")
        cls.after = CANDIDATE.read_text(encoding="utf-8")

    def test_snapshot_is_exact_read_only_pg_function_definition(self):
        self.assertEqual(hashlib.md5(self.before.encode("utf-8")).hexdigest(),
                         INSTALLED_SOURCE_MD5)
        self.assertEqual(self.before.count(ANCHOR), 1)
        self.assertEqual(self.before.count("CREATE OR REPLACE FUNCTION"), 1)
        self.assertIn("atlas.operating_requirements_owner_self_api_v1", self.before)
        self.assertIn("STABLE SECURITY DEFINER", self.before)
        self.assertIn("atlas.company_work_native_ledger_owner_self_v1", self.before)

    def test_proposal_is_exactly_one_scoped_change_not_an_authority_change(self):
        self.assertEqual(self.after, self.before.replace(ANCHOR, REPLACEMENT, 1))
        self.assertEqual(self.after.count("CREATE OR REPLACE FUNCTION"), 1)
        self.assertEqual(self.after.count("as canonical_work"), 1)
        self.assertEqual(self.after.count("atlas.company_work_native_ledger_relevance rel"), 1)
        self.assertEqual(self.after.count("atlas.company_work_native_ledger_exact_source_v1("),
                         self.before.count("atlas.company_work_native_ledger_exact_source_v1(")+1)
        # A complete-file equality after one replacement prevents changes to
        # owner authority, legacy source, return envelope, GRANT or DML writers.
        for text in ("GRANT ", "ALTER ROLE ", "CREATE TABLE ", "DROP TABLE ",
                     "INSERT INTO ", "UPDATE atlas.", "DELETE FROM atlas."):
            self.assertNotIn(text.upper(), self.after.upper())

    def test_exact_ledger_original_relevance_not_organization_only(self):
        scoped = REPLACEMENT.split("and exists (", 1)[1]
        for fragment in (
            "rel.organization_id=i.organization_id",
            "rel.work_item_id=i.id",
            "rel.ledger_id=p_ledger_id",
            "rel.attribution_state='active'",
            "rel.evidence_kind='owner_attested'",
            "rel.evidence_kind='source_verified'",
            "atlas.company_work_native_ledger_exact_source_v1(",
            "proof.source_schema=rel.source_schema",
            "proof.source_table=rel.source_table",
            "proof.source_id=rel.source_id",
        ):
            self.assertIn(fragment, scoped, fragment)
        self.assertIn("where l.requirement_id=w.id", REPLACEMENT)
        self.assertNotIn("rel.ledger_id=r.ledger_id OR", scoped)
        self.assertNotIn("rel.attribution_state <> 'withdrawn'", scoped)

    def test_outer_case_and_legacy_link_custody_unchanged(self):
        for fragment in (
            "v_owner:=atlas.company_work_native_ledger_owner_self_v1(",
            "where r.organization_id=p_organization_id and r.ledger_id=p_ledger_id",
            "select coalesce(jsonb_agg(to_jsonb(x)",
            "l.organization_id=w.organization_id and l.active",
            "n.ledger_id=p_ledger_id and n.attribution_state='active'",
            "'recurrenceRuleDoesNotMaterializeWorkHere',true",
            "'unlinkedLegacyRequirementsAreUnattributed',true",
        ):
            self.assertIn(fragment, self.after)

    def test_synthetic_relevance_classes_explain_denial_without_db_claims(self):
        # The following is a model of the SQL predicate, not a signed/runtime
        # database acceptance test. Real actors and MVCC need separate proof.
        def admitted(rows, org, work, ledger):
            return any(
                r["org"] == org
                and r["work"] == work
                and r["ledger"] == ledger
                and r["state"] == "active"
                and (r["kind"] == "owner_attested"
                     or (r["kind"] == "source_verified" and r["source_still_proves"]))
                for r in rows
            )
        relevant = [{"org": "Elm", "work": "W1", "ledger": "L1",
                     "state": "active", "kind": "owner_attested",
                     "source_still_proves": False}]
        other = [{"org": "Elm", "work": "W2", "ledger": "L2",
                  "state": "active", "kind": "owner_attested",
                  "source_still_proves": False}]
        verified = [{"org": "Elm", "work": "W3", "ledger": "L1",
                     "state": "active", "kind": "source_verified",
                     "source_still_proves": True}]
        self.assertTrue(admitted(relevant, "Elm", "W1", "L1"))
        self.assertFalse(admitted(other, "Elm", "W2", "L1"))
        self.assertTrue(admitted(verified, "Elm", "W3", "L1"))
        verified[0]["source_still_proves"] = False
        self.assertFalse(admitted(verified, "Elm", "W3", "L1"))
        relevant[0]["state"] = "withdrawn"
        self.assertFalse(admitted(relevant, "Elm", "W1", "L1"))
        self.assertFalse(admitted(other, "OtherOrg", "W2", "L2"))


if __name__ == "__main__":
    unittest.main()
