"""Source-only safety assertions for held Titus U1 LOCAL GoTrue test."""
import importlib.util
import pathlib
import unittest

ROOT=pathlib.Path(__file__).resolve().parents[1]
SCRIPT=ROOT/"scripts/test-titus-u1-gotrue-local-only.sh"
DRIVER=ROOT/"scripts/validate-titus-u1-gotrue-local-signed.py"
FIXTURE=ROOT/"candidates/shared-teaching-course-clean-cutover-v1/titus_u1_local_gotrue_fixture.sql"
WORKFLOW=ROOT/".github/workflows/titus-u1-gotrue-local-signed.yml"


class TestSignedLocalSafety(unittest.TestCase):
    def test_shell_never_targets_hosted_project(self):
        s=SCRIPT.read_text()
        for required in (
            "SUPABASE_DB_URL","NOEL_CORE_DATABASE_URL",
            "DATABASE_URL","SUPABASE_ACCESS_TOKEN",
            "127.0.0.1:54322","supabase init --force",
            "supabase start","supabase stop --no-backup",
            "titus_u1_local_gotrue_fixture.sql",
            "titus_account_context_candidate.sql",
            "titus_institution_account_admission_issuer_candidate.sql",
            "titus_institution_account_self_service_candidate.sql",
            "2.116.0",
        ):
            self.assertIn(required,s)
        for forbidden in (
            "supabase link", "supabase db push", "supabase db dump",
            "--linked", "--remote", "--project-ref",
            "https://zirqkouammpwxlqfbsvf",
        ):
            self.assertNotIn(forbidden,s)

    def test_driver_requires_real_gotrue_tokens_and_local_db(self):
        source=DRIVER.read_text()
        for required in (
            "auth/v1/signup", "auth/v1/token?grant_type=password",
            "auth.sessions","reality.auth_person_bindings",
            "role", "session_id", "not a",  # see intentionally no token forge
        ):
            if required=="not a":continue
            self.assertIn(required,source)
        self.assertNotIn("SET LOCAL ROLE authenticated",source)
        self.assertNotIn("SET request.jwt.claims",source)
        self.assertNotIn("supabase.co",source)
        spec=importlib.util.spec_from_file_location("titus_u1_signed",DRIVER)
        mod=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        self.assertTrue(mod.local_db(
            "postgresql://postgres:postgres@127.0.0.1:54322/postgres"))
        self.assertFalse(mod.local_db(
            "postgresql://postgres:postgres@127.0.0.1:54323/postgres"))
        self.assertFalse(mod.local_db(
            "postgresql://postgres:postgres@example.org:54322/postgres"))
        self.assertTrue(mod.local_api("http://127.0.0.1:54321"))
        self.assertFalse(mod.local_api("https://example.com"))
        self.assertFalse(mod.local_api("http://127.0.0.1:54322"))

    def test_local_fixture_contains_no_fake_auth_sessions(self):
        source=FIXTURE.read_text()
        self.assertNotIn("INSERT INTO auth.users",source)
        self.assertNotIn("INSERT INTO auth.sessions",source)
        self.assertNotIn("CREATE ROLE authenticated",source)
        self.assertNotIn("SUPABASE_SERVICE_ROLE",source)
        self.assertIn("CREATE SCHEMA titus",source)
        self.assertIn("auth.sessions",source)
        self.assertIn("reality.resolve_responsibility_relation_v1",source)
        self.assertIn("TITUS U1 SIGNED LOCAL TEST FIXTURE ONLY",source)

    def test_root_guard_is_in_relinquish_not_nomination(self):
        source=(ROOT/"candidates/shared-teaching-course-clean-cutover-v1"
            /"shared_titus_institution_root_establishment_candidate.sql").read_text()
        nominate=source.split(
            "CREATE FUNCTION public.shared_titus_institution_root_nominate_self_api_v1",1)[1].split(
            "CREATE FUNCTION public.shared_titus_institution_root_accept_self_api_v1",1)[0]
        relinquish=source.split(
            "CREATE FUNCTION public.shared_titus_institution_root_relinquish_self_api_v1",1)[1]
        self.assertNotIn(
            "revoke/transfer active manager before root relinquishment",nominate)
        self.assertIn(
            "revoke/transfer active manager before root relinquishment",relinquish)
        self.assertIn("atlas.company_work_native_ledger_owner_self_v1",source)
        self.assertNotIn("atlas.is_organization_owner(",source)
        self.assertIn("titus.current_exact_root_for_ledger_v1",source)
        self.assertIn("titus.institution_account_root_origins_v1",source)
        self.assertIn("GRANT EXECUTE ON FUNCTION public.shared_titus_institution_root_bootstrap_self_api_v1",source)

    def test_organization_reality_identity_must_have_unique_source_original(self):
        sql=(ROOT/"candidates/shared-teaching-course-clean-cutover-v1"
             /"shared_titus_institution_root_establishment_candidate.sql").read_text()
        fixture=FIXTURE.read_text()
        signed=DRIVER.read_text()
        helper=sql.split("CREATE FUNCTION titus.require_canonical_institution_organization_v1(",1)[1].split(
            "CREATE FUNCTION titus.current_exact_root_for_ledger_v1(",1)[0]
        for contract in ("compatibility.legacy_bindings",
                         "lb.legacy_schema='atlas'",
                         "lb.legacy_table='organizations'",
                         "lb.disposition='maps_to'",
                         "v_mapping_count IS DISTINCT FROM 1",
                         "v_mapped_entity IS DISTINCT FROM v_entity"):
            self.assertIn(contract,helper)
        self.assertIn("INSERT INTO compatibility.legacy_bindings",fixture)
        for guard in (
            "explicit Atlas Organization mapping to wrong Reality institution denies",
            "two competing Atlas-to-Reality organization originals deny",
            "missing organization Reality mapping denies rather than guessing",
        ):
            self.assertIn(guard,signed)

    def test_live_structure_audit_can_only_read_aggregate_source(self):
        import re
        source=(ROOT/"scripts/audit-titus-u1-live-structure-readonly.sql").read_text()
        statements="\n".join(line for line in source.splitlines()\n                            if not line.lstrip().startswith("--")).strip()
        self.assertTrue(statements.lower().startswith("with\n"))
        self.assertEqual(statements.count(";"),1)
        for forbidden in (
            "INSERT ", "UPDATE ", "DELETE ", "DROP ", "ALTER ",
            "CREATE ", "TRUNCATE ", "GRANT ", "REVOKE ",
            "COPY ", "PERFORM ", "EXECUTE ", "DO $",
        ):
            self.assertNotIn(forbidden,statements.upper())
        self.assertIn("exact_unique_compatible",source)
        self.assertIn("missing_explicit_mapping",source)
        self.assertIn("ambiguous_explicit_mapping",source)
        self.assertIn("course_specific_person_live",source)
        self.assertIn("'releaseApproved',false",source)
        self.assertIn("'protectedProductionSchemaCloneVerified',false",source)
        self.assertNotIn("organization_name",source)
        self.assertNotIn("email",source.lower())

    def test_signed_person_candidate_checks_live_gotrue_session_and_existing_identity(self):
        candidate=(ROOT/"candidates/shared-teaching-course-clean-cutover-v1"
                   /"shared_titus_current_person_signed_candidate.sql").read_text()
        self.assertNotIn(
            "CREATE FUNCTION atlas.current_person_for_private_course_v1()",
            FIXTURE.read_text())
        for required in (
            "CREATE FUNCTION atlas.current_person_for_private_course_v1()",
            "auth.sessions", "auth.users", "s.id=v_session",
            "s.user_id=v_auth", "s.not_after", "u.deleted_at",
            "u.banned_until", "reality.auth_person_bindings",
            "b.binding_state='active'", "b.retired_at IS NULL",
            "e.entity_kind='person'", "e.identity_state='canonical'",
            "v_count IS DISTINCT FROM 1", "atlas.current_person_id_v1()",
            "v_current IS DISTINCT FROM v_person",
            "REVOKE ALL ON FUNCTION atlas.current_person_for_private_course_v1()",
        ):
            self.assertIn(required,candidate)
        self.assertIn("shared_titus_current_person_signed_candidate.sql",
                      SCRIPT.read_text())
        candidate_sql="\n".join(line for line in candidate.splitlines()\n                                if not line.lstrip().startswith("--"))\n        self.assertNotIn("user_metadata",candidate_sql)
        self.assertNotIn("service_role",candidate)

    def test_workflow_not_production_protected_trigger(self):
        s=WORKFLOW.read_text()
        self.assertIn("permissions:\n  contents: read",s)
        self.assertNotIn("environment: production",s)
        self.assertNotIn("NOEL_CORE_DATABASE_URL: ${{ secrets.",s)
        self.assertNotIn("workflow_dispatch:",s)
        self.assertNotIn("supabase db push",s)
        self.assertIn("titus-u1-gotrue-local-only.sh",s)


if __name__=="__main__":
    unittest.main()
