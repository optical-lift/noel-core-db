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
        self.assertIn("66666666-6666-4666-8666-666666666666",fixture)
        self.assertIn("Atlas-only governing pair without native Ledger cannot bootstrap",signed)
        self.assertIn("adding Reality mapping alone cannot repair missing native Ledger",signed)
        for guard in (
            "explicit Atlas Organization mapping to wrong Reality institution denies",
            "two competing Atlas-to-Reality organization originals deny",
            "missing organization Reality mapping denies rather than guessing",
        ):
            self.assertIn(guard,signed)

    def test_live_structure_audit_can_only_read_aggregate_source(self):
        import re
        source=(ROOT/"scripts/audit-titus-u1-live-structure-readonly.sql").read_text()
        statements="\n".join(line for line in source.splitlines()
                            if not line.lstrip().startswith("--")).strip()
        self.assertTrue(statements.lower().startswith("with\n"))
        self.assertEqual(statements.count(";"),1)
        for forbidden in (
            "INSERT ", "UPDATE ", "DELETE ", "DROP ", "ALTER ",
            "CREATE ", "TRUNCATE ", "GRANT ", "REVOKE ",
            "COPY ", "PERFORM ", "EXECUTE ", "DO $",
        ):
            self.assertNotIn(forbidden,statements.upper())
        self.assertIn("exact_unique_compatible",source)
        self.assertIn("native_ledger_missing",source)
        self.assertIn("both_native_ledger_and_mapping_missing",source)
        self.assertIn("native_ledger_without_mapping",source)
        self.assertIn("mapping_without_native_ledger",source)
        self.assertIn("governing_atlas_ledger_inactive",source)
        self.assertIn("missing_explicit_mapping",source)
        self.assertIn("ambiguous_explicit_mapping",source)
        self.assertIn("course_specific_person_live",source)
        self.assertIn("'releaseApproved',false",source)
        self.assertIn("'protectedProductionSchemaCloneVerified',false",source)
        self.assertNotIn("organization_name",source)
        self.assertNotIn("email",source.lower())

    def test_catalog_preflight_is_only_a_structural_read(self):
        source=(ROOT/"scripts/audit-titus-u1-authority-catalog-readonly.sql").read_text()
        lines=[line for line in source.splitlines()
               if line.strip() and not line.lstrip().startswith("--")]
        self.assertTrue(lines[0].lstrip().upper()=="WITH")
        statements=" ".join(lines)
        self.assertEqual(statements.count(";"),1)
        for unsafe in (
            "INSERT INTO", "UPDATE ", "DELETE FROM", "CREATE ",
            "DROP ", "TRUNCATE ", "GRANT ", "REVOKE ", "COPY ",
            "SET ROLE ", "CALL ", "DO $", "ALTER ",
        ):
            self.assertNotIn(unsafe,statements.upper())
        for required in (
            "atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)",
            "reality.resolve_responsibility_relation_v1",
            "reality.guard_responsibility_relation_v1",
            "('atlas','ledger_organization_participations'",
            "('reality','auth_person_bindings'",
            "compatibility",
            "anonResponsibilityDirectSelect",
            "requiredColumnsPresent",
            "structuralPreflightPass",
            "'productionSchemaCloneTested',false",
            "'ownerApprovedRelease',false",
        ):
            self.assertIn(required,source)
        self.assertNotIn("WHERE organization_id=",source)
        self.assertNotIn("auth.users.email",source)

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
        candidate_sql="\n".join(line for line in candidate.splitlines()
                                if not line.lstrip().startswith("--"))
        self.assertNotIn("user_metadata",candidate_sql)
        self.assertNotIn("service_role",candidate)

    def test_two_independent_atlas_ledger_authorities_are_tested(self):
        fixture=FIXTURE.read_text()
        signed=DRIVER.read_text()
        owner=fixture.split(
            "CREATE FUNCTION atlas.company_work_native_ledger_owner_self_v1(",1)[1].split(
            "CREATE FUNCTION public.titus_u1_fixture_native_owner_probe_v1(",1)[0]
        for required in (
            "lop.participation_kind IN ('governing','operating')",
            "v_primary_count<>1",
            "a.ledger_id=p_ledger_id",
            "a.ledger_id=v_primary",
            "a.principal_id=v_principal",
            "seat.person_entity_id=v_person",
            "seat.seat_state='active'",
            "THEN RAISE EXCEPTION",
        ):
            self.assertIn(required,owner)
        self.assertIn("CREATE FUNCTION public.titus_u1_fixture_native_owner_probe_v1",fixture)
        self.assertIn("GRANT EXECUTE ON FUNCTION public.titus_u1_fixture_native_owner_probe_v1",fixture)
        self.assertNotIn("CREATE FUNCTION public.titus_u1_fixture_native_owner_probe_v1",
                         (ROOT/"candidates/shared-teaching-course-clean-cutover-v1"
                          /"shared_titus_institution_root_establishment_candidate.sql").read_text())
        for proof in (
            "native operating Ledger without its own root authority denies",
            "two distinct root-governed Ledgers admit one signed governing Principal",
            "native root without separate current primary governing root denies",
            "two root authorities do not replace a current native Ledger Seat",
            "Titus institutional root cannot bootstrap on merely operating Ledger",
        ):
            self.assertIn(proof,signed)


    def test_root_and_manager_commands_lock_ledger_before_root_responsibility(self):
        manager=(ROOT/"candidates/shared-teaching-course-clean-cutover-v1"
                 /"shared_titus_institution_manager_governance_candidate.sql").read_text()
        roots=(ROOT/"candidates/shared-teaching-course-clean-cutover-v1"
               /"shared_titus_institution_root_establishment_candidate.sql").read_text()
        def command_chunk(source,fn):
            section=source.split("CREATE FUNCTION public."+fn+"(",1)[1]
            return section.split("END $",1)[0]
        names=(
            (manager,"shared_titus_institution_manager_command_self_api_v1"),
            (roots,"shared_titus_institution_root_nominate_self_api_v1"),
            (roots,"shared_titus_institution_root_cancel_self_api_v1"),
            (roots,"shared_titus_institution_root_relinquish_self_api_v1"),
        )
        for source,name in names:
            section=command_chunk(source,name)
            ledger=section.find("PERFORM 1 FROM ledger.ledgers")
            root=section.find(
                "titus.require_institution_root_manager_governor_self_v1(")
            self.assertGreaterEqual(ledger,0,name+" missing Ledger lock")
            self.assertGreater(root,ledger,name+" locks root before Ledger")
            self.assertIn("FOR UPDATE",section[ledger:root],name)
        signed=DRIVER.read_text()
        self.assertIn("with ThreadPoolExecutor(max_workers=2)",signed)
        self.assertIn("concurrent_barrier=Barrier(2)",signed)
        self.assertIn("sorted(statuses)==[200,403]",signed)
        self.assertIn('rejected[1].get("code")=="42501"',signed)
        self.assertIn("(active_root,active_manager) in ((1,1),(0,0))",signed)

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
