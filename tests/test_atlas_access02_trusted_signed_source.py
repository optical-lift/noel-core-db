#!/usr/bin/env python3
"""Offline trusted controller contract. This is NOT signed acceptance."""
import re
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
W=(ROOT/".github/workflows/atlas-access02-owner-protected-signed-clone.yml").read_text()
H=(ROOT/"scripts/validate-production-schema-clone.sh").read_text()
P=(ROOT/"scripts/validate-atlas-access02-my-work-signed-http.py").read_text()
F=(ROOT/"validation/fixtures/access02_my_work_relevance_signed_clone_only.sql").read_text()
ACL=(ROOT/"scripts/atlas-access02-disposable-anon-parity-held.sql").read_text()

class TrustedAccess02(unittest.TestCase):
    def test_owner_issue_gated_exact_held_source(self):
        protected=W.split("  validate-owner-protected-signed:",1)[1]
        for required in (
          "github.event.issue.author_association == 'OWNER'",
          "github.actor == github.repository_owner",
          "environment: production",
          "Atlas ACCESS-02: protected signed My Work relevance approval",
          "13b3f2cc2364b4e9d3f4d161b3a4d3a9d5033530",
          "candidate_sha:",
          "Snapshot production roles and schema READ ONLY",
          "Checkout immutable held candidate",
          "Assemble ephemeral disposable clone inputs",
          "Genuine signed local My Work / relevance withdrawal clone",
          "ACCESS02_DISPOSABLE_SIGNED_RESULT=PASS",
        ):
            self.assertIn(required,protected,required)
        self.assertIn('print("ACCESS02_DISPOSABLE_PHASE="+val)',protected)
        self.assertIn('"UNKNOWN"',protected)
        self.assertIn('"signed_my_work"',protected)
        self.assertIn('print("ACCESS02_POSTCONDITION_REASON="+reason)',protected)
        self.assertIn('reason=found[0] if len(found)==1 else "unknown_or_not_applicable"',protected)
        self.assertIn('"wrapper_acl"',protected)
        self.assertIn('"native_source_contract"',protected)
        self.assertNotIn("print(message)",protected)
        self.assertNotIn("print(source)",protected)
        self.assertNotIn("print(raw)",protected)
        self.assertEqual(protected.count("NOEL_CORE_DATABASE_URL: "),1)
        self.assertLess(protected.index("Snapshot production roles and schema READ ONLY"),
                        protected.index("Checkout immutable held candidate"))
        self.assertLess(protected.index("Checkout immutable held candidate"),
                        protected.index("Assemble ephemeral disposable clone inputs"))
        for forbidden in (
          "supabase db push", "supabase migration up", "db reset --linked",
          "apply_migration", "SUPABASE_SERVICE_ROLE_KEY","gh pr merge"
        ):
            self.assertNotIn(forbidden,protected)

    def test_only_scratch_migration_executes_proof(self):
        exact="^[0-9]{14}_atlas_access02_my_work_relevance_signed_clone_only_v1[.]sql$"
        self.assertIn(exact,H)
        self.assertEqual(H.count("signed_access02_my_work_probe=true"),1)
        self.assertIn('if [ "$signed_access02_my_work_probe" = true ]; then',H)
        self.assertIn("validate-atlas-access02-my-work-signed-http.py",H)
        self.assertIn("signed-access02-my-work-summary.txt",H)
        self.assertIn("genuinely signed local ACCESS-02",H)
        # The exact ACCESS-02 probe MUST launch local GoTrue + PostgREST.
        # A DB-only startup silently fails when the signed test calls local_status().
        startup=H.split('startup_attempt=1',1)[1].split('phase="production custom-role restore"',1)[0]
        # Preserve the old ACCESS-02 real Auth+REST startup while adding
        # ACCESS-03A as a second individually gated signed clone path.
        joined=('       [ "$signed_access02_my_work_probe" = true ] ||\n'
                '       [ "$signed_access03_zone_retirement_probe" = true ]; then')
        self.assertEqual(startup.count(joined),2)
        starts=startup.split(joined)
        self.assertEqual(len(starts),3)
        self.assertTrue(starts[1].lstrip().startswith('# The source-governed signed care'))
        self.assertTrue(starts[2].lstrip().startswith('supabase start -x'))
        self.assertIn('supabase db start >"$startup_log" 2>&1',startup)

        self.assertIn("access02_my_work_relevance_signed_clone_only.sql",W)
        self.assertIn("atlas_universal_original_work_integrated_v1/fixture.sql",W)
        self.assertIn("timeout --signal=TERM --kill-after=25s 18m",W)
        self.assertNotIn("supabase db push",H)

    def test_exact_local_wrapper_acl_parity_only(self):
        self.assertIn('PGOPTIONS="-c access02.disposable_clone=true"',H)
        self.assertIn('scripts/atlas-access02-disposable-anon-parity-held.sql',H)
        self.assertIn('phase="ACCESS-02 disposable anonymous REST ACL parity"',H)
        self.assertEqual(ACL.count(
            "REVOKE EXECUTE ON FUNCTION public.connected_person_my_work_self_api_v1(integer,uuid) FROM anon;"),1)
        self.assertIn("REFUSE ACCESS02 ACL parity outside disposable clone",ACL)
        self.assertIn("access02.disposable_clone",ACL)
        self.assertIn("c47a7961a04f6b834b65a851253990da",ACL)
        self.assertIn("AND coalesce(relevance.has_relevance,false)",ACL)
        self.assertIn("has_function_privilege('authenticated',p.oid,'EXECUTE')",ACL)
        self.assertIn("has_function_privilege('anon',v_rest,'EXECUTE')",ACL)
        self.assertIn("aclexplode(p.proacl)",ACL)
        self.assertEqual(ACL.count("DO $access02_parity_"),2)
        self.assertEqual(ACL.count("COMMIT;"),1)
        self.assertNotRegex(ACL,re.compile(r"\\bGRANT\\s+EXECUTE\\b",re.I))
        self.assertNotIn("REVOKE EXECUTE ON FUNCTION atlas.",ACL)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY",ACL)

    def test_genuine_signed_fictional_cases_and_nonproduction_refusal(self):
        for required in (
          "127[.]0[.]0[.]1",
          "base.setup_auth(a.db_url)",
          "c1.sign_in(api,key,label)",
          "auth.sessions",
          "len({x[1].get(\"session_id\")",
          "connected_person_my_work_self_api_v1",
          "company_work_native_ledger_relevance",
          "attribution_state='withdrawn'",
          "attribution_state='active'",
          "offer_connected_person_company_work_owner_self_api_v1",
          "respond_connected_person_company_work_self_api_v1",
          "person_connection_receiver_uptake",
          "clone:access02-reattest-901",
          "must preserve original withdrawn evidence",
          "hasMore",
          "nextAllocationId",
          "Synthetic instructions for Work 901",
          "Synthetic instructions for Work 902",
          "seat_state='ended'",
          "no-seat",
          "anonymous REST request was not denied",
          "PASS ACCESS-02 signed ",
        ):
            self.assertIn(required,P,required)
        self.assertEqual(P.count("def main():"),1)
        self.assertNotIn("supabase.co",P)
        self.assertNotIn("zirqkouammpwxlqfbsvf",P)
        self.assertNotIn("service_role",P.lower())
        for required in ("e5200000-0000-4000-8000-000000000850",
                         "atlas.organization_memberships",
                         "'owner',true",
                         "access02_fixture_postconditions"):
            self.assertIn(required,F,required)
        for forbidden in ("auth.users","GRANT ","REVOKE ","CREATE TABLE","DROP TABLE","public."):
            self.assertNotIn(forbidden,F)
        self.assertNotIn("INSERT INTO atlas.work_allocations",F)
        self.assertIn("global ALLOC_A,ALLOC_B",P)
        # Mirror the exact disposable schema-clone fixture admission, not
        # just PostgreSQL grammar. Procedural DO and semicolons in strings
        # are rejected by the trusted fixture sanitizer.
        clean=re.sub(r"--[^\n]*"," ",F)
        clean=re.sub(r"\s+"," ",clean).strip()
        forbidden_sql=re.compile(
            r"\b(create|alter|drop|truncate|grant|revoke|comment|vacuum|"
            r"analyze|reindex|cluster|refresh|copy|do|call|execute|prepare|"
            r"deallocate|listen|notify|security)\b",re.I)
        self.assertIsNone(forbidden_sql.search(clean))
        statements=[v.strip() for v in clean.split(";") if v.strip()]
        self.assertEqual(len(statements),4)
        self.assertTrue(all(re.match(r"^(insert\s+into|update\s+|delete\s+from|select\s+)",v,re.I)
                            for v in statements))

if __name__=="__main__":
    unittest.main()
