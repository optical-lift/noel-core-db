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
