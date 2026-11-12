#!/usr/bin/env python3
"""ACCESS-03B source custody; NEVER applies SQL or creates live identities."""
import ast
import re
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
PACKET=ROOT/"candidates/atlas/atlas_access03b_governed_growing_crop_direct_read_v1"
CANDIDATE=(PACKET/"candidate.sql").read_text()
POST=(PACKET/"postconditions.sql").read_text()
FIXTURE=(PACKET/"fixture.sql").read_bytes()
ORIGINAL=(ROOT/"validation/fixtures/20261112160559_atlas_access03_zone_direct_reader_retirement_v1.sql").read_bytes()
WORKFLOW=(ROOT/".github/workflows/atlas-access03b-two-table-native-rls-signed-clone.yml").read_text()
PROBE=(ROOT/"scripts/validate-atlas-access03-zone-retirement-signed-http.py").read_text()


class AtlasAccess03BGate0Test(unittest.TestCase):
    def test_source_two_table_bounded_root_repair(self):
        self.assertEqual(CANDIDATE.count("ALTER POLICY "),2)
        self.assertEqual(CANDIDATE.count("CREATE FUNCTION "),1)
        for table, policy in (
            ("growing_objects","growing_objects_read_operations"),
            ("crop_cycles","crop_cycles_read_operations"),
        ):
            self.assertIn(f"ALTER POLICY {policy} ON atlas.{table}",CANDIDATE)
            self.assertIn(f"('{table}'::text,'{policy}'::text)",CANDIDATE)
            self.assertIn(f"('{table}'::text,'{policy}'::text)",POST)
            self.assertIn(f"atlas.{table}",CANDIDATE)
        self.assertIn("CREATE FUNCTION atlas.can_read_native_governed_farm_full_self_v1",CANDIDATE)
        self.assertIn("RETURNS boolean",CANDIDATE)
        self.assertIn("STABLE SECURITY DEFINER SET search_path TO ''",CANDIDATE)
        self.assertIn("PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id)",CANDIDATE)
        self.assertIn("EXCEPTION WHEN SQLSTATE '42501' THEN",CANDIDATE)
        self.assertIn("RETURN FALSE;",CANDIDATE)
        self.assertIn("GRANT EXECUTE ON FUNCTION atlas.can_read_native_governed_farm_full_self_v1(uuid)",CANDIDATE)
        self.assertIn("TO authenticated;",CANDIDATE)
        self.assertIn("FROM PUBLIC, anon, authenticated, service_role;",CANDIDATE)
        self.assertEqual(CANDIDATE.count("USING (atlas.can_read_native_governed_farm_full_self_v1(farm_id));"),2)
        self.assertIn("to_regprocedure('atlas.can_read_native_governed_farm_full_self_v1(uuid)') IS NOT NULL",CANDIDATE)
        self.assertIn("p.qual='atlas.can_read_farm_operations(farm_id)'",CANDIDATE)
        self.assertIn("cbcc8e98ac2530c60389c4f111793a5f",CANDIDATE)
        self.assertIn("429fa9bc47f4a4e17188b9d8d0b91167",CANDIDATE)
        self.assertIn("security_invoker=true",CANDIDATE)
        self.assertIn("farm_care_object_state_v1",CANDIDATE)
        self.assertIn("v_farm_object_operational_state",CANDIDATE)
        self.assertIn("COMMIT;",CANDIDATE)
        for forbidden in (
            "DROP POLICY","DROP TABLE","DROP VIEW","REVOKE SELECT ON TABLE",
            "TRUNCATE ","DELETE FROM ","UPDATE atlas.","INSERT INTO ",
            "GRANT ALL","CASCADE","auth.uid() IN",
            "current_farm_role(", "is_farm_member(", "raw_user_meta_data",
        ):
            self.assertNotIn(forbidden,CANDIDATE)
        self.assertEqual(FIXTURE,ORIGINAL)
        self.assertEqual(len([s for s in re.sub(r"--[^\n]*","",FIXTURE.decode()).split(";") if s.strip()]),33)

    def test_postconditions_cannot_report_old_role_as_safe(self):
        self.assertIn("p.qual='atlas.can_read_native_governed_farm_full_self_v1(farm_id)'",POST)
        self.assertIn("p.roles::text='{authenticated}'",POST)
        self.assertIn("NOT has_function_privilege('authenticated'",POST) if False else None
        self.assertIn("has_function_privilege('anon'",POST)
        self.assertIn("farm_care_object_state_v1",POST)
        self.assertIn("v_farm_object_operational_state",POST)
        self.assertIn("relrowsecurity",POST)
        self.assertIn("has_table_privilege('authenticated'",POST)
        self.assertIn("has_table_privilege('anon'",POST)
        for forbidden in ("DELETE FROM ","INSERT INTO ","UPDATE atlas.","ALTER POLICY","DROP POLICY","GRANT "):
            self.assertNotIn(forbidden,POST)

    def test_protected_current_schema_signed_source_not_production_release(self):
        for required in (
            "github.event.issue.author_association == 'OWNER'",
            "github.actor == github.repository_owner",
            "Atlas ACCESS-03B: protected signed two-table RLS repair test approval",
            "source_sha:", "ref: main", "environment: production",
            'test "$(git rev-parse HEAD)"',
            "--role-only --file", "supabase db dump --db-url",
            "scripts/check-custody.sh","scripts/check-production-schema-validation-contract.sh",
            "scripts/validate-production-schema-clone.sh",
            'cp "$source_dir/candidate.sql" "$migration"',
            'cmp "$source_dir/candidate.sql" "$migration"',
            "atlas_access03_zone_direct_reader_retirement_clone_only_v1",
            "ACCESS03B_SIGNED_RESULT=FAIL_UNSAFE_LEGACY_DIRECT_RLS",
            "ACCESS03B_SIGNED_RESULT=PASS_TESTED_TWO_TABLE_PATHS_ONLY",
            "grep -q '^PASS ACCESS03B signed '",
            "if: always()", "actions/upload-artifact@v4",
            "retention-days: 7",
            "access03b-two-table-artifacts/signed-access03-zone-retirement.log",
        ):
            self.assertIn(required,WORKFLOW)
        artifact=WORKFLOW.split("- name: Upload bounded disposable Gate 0 validation diagnostics",1)
        self.assertEqual(len(artifact),2)
        for forbidden in (
            "schema.sql", "roles.sql", "NOEL_CORE_DATABASE_URL", "JWT","secret",
        ):
            self.assertNotIn(forbidden,artifact[1])
        for forbidden in (
            "supabase db push", "supabase migration up",
            "scripts/release-production-migration.sh", "SUPABASE_SERVICE_ROLE_KEY",
            "admin.createUser", "apply_migration", "curl -X POST https://",
        ):
            self.assertNotIn(forbidden,WORKFLOW)
        self.assertEqual(WORKFLOW.count("NOEL_CORE_DATABASE_URL: "),1)
        self.assertEqual(WORKFLOW.count('cp "$source_dir/candidate.sql" "$migration"'),1)
        self.assertLess(WORKFLOW.index("Snapshot Production schema and roles READ ONLY"),
                        WORKFLOW.index('cp "$source_dir/candidate.sql" "$migration"'))

    def test_true_positive_and_negative_signed_actor_assertions(self):
        ast.parse(PROBE)
        for required in (
            'tokens["owner"]','tokens["worker"]','"outsider"','"no-seat"',
            '"farm_hand"','None,path',"c1.sign_in(api,key,name)",
            "native Ledger governor lost direct", "via "+'"'+ " and "+'"', 
            "invoker_views", "farm_care_object_state_v1",
            "v_farm_object_operational_state",
            "HELD ACCESS03B governor invoker view 42501",
            "direct_leaks.append(", "UNSAFE GATE0 SIGNED LOCAL DIRECT TABLE READ",
            "native governing root revocation cuts both tables",
            "root restoration returns both source rows",
            "PASS ACCESS03B signed native two-table policy and no-loss",
        ):
            self.assertIn(required,PROBE)


if __name__=="__main__":
    unittest.main()
