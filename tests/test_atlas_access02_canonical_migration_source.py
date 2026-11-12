#!/usr/bin/env python3
"""ACCESS-02 versioned migration structural source custody (source only).
Do not confuse these checks with the independently signed actor clone PASS.
"""
import re
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/"candidates/atlas_connected_person_my_work_verified_relevance_v1"
CAND=(BASE/"candidate.sql").read_text()
POST=(BASE/"postconditions.sql").read_text()
FILE=ROOT/"supabase/migrations/20261112003844_atlas_access02_my_work_verified_native_relevance_v1.sql"
MIG=FILE.read_text()
VERSION="20261112003844"

class Access02CanonicalSource(unittest.TestCase):
    def test_cli_minted_immutable_version(self):
        self.assertEqual(FILE.name,
            VERSION+"_atlas_access02_my_work_verified_native_relevance_v1.sql")
        self.assertEqual(len(list(FILE.parent.glob(VERSION+"_*.sql"))),1)
        self.assertTrue(MIG.strip().endswith("COMMIT;"))
        self.assertEqual(len(re.findall(r"(?m)^BEGIN;\s*$",MIG)),1)
        self.assertEqual(len(re.findall(r"(?m)^COMMIT;\s*$",MIG)),1)

    def test_installed_function_body_equals_independently_signed_candidate(self):
        fn="CREATE OR REPLACE FUNCTION atlas.connected_person_my_work_self_api_v1("
        self.assertEqual(MIG.count(fn),1)
        self.assertEqual(CAND.count(fn),1)
        self.assertIn(CAND[CAND.index(fn):].strip(),MIG)
        self.assertEqual(MIG.count("AND coalesce(relevance.has_relevance,false)"),2)
        self.assertIn("AND w.work_state='open'",MIG)
        self.assertIn("AND a.assignee_canonical_person_id=v_self",MIG)
        self.assertIn("atlas.person_has_native_ledger_connection_v1(",MIG)
        self.assertIn("atlas.person_original_work_identity_disclosed_self_v1(",MIG)
        self.assertIn("LIMIT p_limit+1",MIG)
        self.assertIn("'title',r.title,'instructions',r.instructions",MIG)
        self.assertIn("'workRelevanceVerified',r.has_relevance",MIG)

    def test_guard_and_postconditions_are_exact_source_bound(self):
        self.assertIn("d6003af17ab97d3ee21188f35454332c",MIG)
        self.assertEqual(MIG.count("d6003af17ab97d3ee21188f35454332c"),1)
        self.assertIn("ACCESS-02 native Work reader source drift",MIG)
        self.assertIn("c47a7961a04f6b834b65a851253990da",MIG)
        self.assertIn("ACCESS-02 REST Work wrapper execution ACL differs",MIG)
        self.assertIn(POST[POST.index("DO $access02_postconditions$"):].strip(),MIG)
        self.assertEqual(MIG.count("DO $access02_postconditions$"),1)
        self.assertEqual(MIG.count("$access02_postconditions$;"),1)

    def test_scope_only_one_existing_private_reader_without_grants(self):
        self.assertEqual(len(re.findall(r"(?mi)^CREATE OR REPLACE FUNCTION",MIG)),1)
        self.assertNotIn("CREATE OR REPLACE FUNCTION public.",MIG)
        self.assertNotRegex(MIG,re.compile(r"(?mi)^\s*(GRANT|REVOKE|INSERT|UPDATE|DELETE|DROP|CREATE TABLE|ALTER TABLE)\s"))
        self.assertIn("STABLE SECURITY DEFINER",MIG)
        self.assertIn("SET search_path TO ''",MIG)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY",MIG)
        self.assertNotIn("NOEL_CORE_DATABASE_URL",MIG)

if __name__=="__main__":
    unittest.main()
