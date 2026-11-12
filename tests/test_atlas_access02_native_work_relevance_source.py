#!/usr/bin/env python3
"""ACCESS-02 candidate source-only checks. NOT a signed actor/privacy test."""
import re
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
DIR=ROOT/"candidates/atlas_connected_person_my_work_verified_relevance_v1"
CAND=(DIR/"candidate.sql").read_text()
POST=(DIR/"postconditions.sql").read_text()

class Access02SourceOnly(unittest.TestCase):
    def test_exact_live_source_pinned(self):
        self.assertEqual(CAND.count("d6003af17ab97d3ee21188f35454332c"),1)
        self.assertEqual(CAND.count(
            "CREATE OR REPLACE FUNCTION atlas.connected_person_my_work_self_api_v1("),1)
        self.assertIn("ACCESS-02 native Work reader source drift",CAND)
        self.assertIn("to_regprocedure('atlas.connected_person_my_work_self_api_v1(integer,uuid)')",POST)

    def test_new_guard_precedes_original_identity_and_paging(self):
        clause="AND coalesce(relevance.has_relevance,false)"
        self.assertEqual(CAND.count(clause),1)
        src=CAND.split("CREATE OR REPLACE FUNCTION",1)[1]
        anchors=[
            "AND w.work_state='open'",
            clause,
            "AND atlas.person_original_work_identity_disclosed_self_v1(",
            "AND (p_after_allocation_id IS NULL OR a.id>p_after_allocation_id)",
            "AND atlas.person_has_native_ledger_connection_v1(",
            "LIMIT p_limit+1",
        ]
        positions=[src.find(x) for x in anchors]
        self.assertTrue(all(x>=0 for x in positions),positions)
        self.assertEqual(positions,sorted(positions))
        self.assertIn("coalesce(relevance.has_relevance,false) has_relevance",src)
        self.assertIn("company_work_native_ledger_exact_source_v1(",src)
        self.assertIn("x.evidence_kind IN ('owner_attested','participant_attested')",src)

    def test_preserve_person_access_details_and_no_authority_widening(self):
        for fragment in [
            "IF auth.uid() IS NULL OR v_self IS NULL",
            "a.assignee_canonical_person_id=v_self",
            "AND a.state='active'",
            "AND a.assignee_membership_id IS NULL",
            "AND w.work_state='open'",
            "'title',r.title,'instructions',r.instructions",
            "'personId',v_self",
            "'workRelevanceVerified',r.has_relevance",
            "p_limit+1",
            "SET search_path TO ''",
            "STABLE SECURITY DEFINER",
        ]:
            self.assertIn(fragment,CAND,fragment)
        self.assertNotRegex(CAND,re.compile(
            r"\b(?:GRANT|REVOKE|ALTER TABLE|CREATE TABLE|DROP TABLE|INSERT INTO|"
            r"DELETE FROM|UPDATE\s+atlas\.)\b",re.I
        ))
        self.assertNotIn("CREATE OR REPLACE FUNCTION public.",CAND)

    def test_static_check_is_explicitly_not_signed_proof(self):
        self.assertIn("independent signed actors still required",POST)
        self.assertIn("authenticated",POST)
        self.assertIn("'c47a7961a04f6b834b65a851253990da'",POST)
        self.assertIn("has_function_privilege('anon',v_wrapper,'EXECUTE')",POST)
        self.assertIn("ACL differs from release baseline",POST)
        self.assertEqual(POST.count("DO $access02_postconditions$"),1)
        self.assertEqual(POST.count("$access02_postconditions$;"),1)

if __name__=="__main__":
    unittest.main()
