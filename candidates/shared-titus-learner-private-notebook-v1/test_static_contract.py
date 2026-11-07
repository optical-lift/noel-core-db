"""Source-only negative contract checks. Not PostgreSQL or signed GoTrue acceptance."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parent
SQL = (ROOT / "candidate.sql").read_text()

class LearnerPrivateNotebookSource(unittest.TestCase):
    def test_candidate_is_transactional_not_live_migration(self):
        self.assertIn("BEGIN;", SQL)
        self.assertEqual(SQL.strip().splitlines()[-1], "COMMIT;")
        self.assertNotIn("INSERT INTO atlas.teaching_enrollments", SQL)
        self.assertNotIn("INSERT INTO atlas.teaching_courses", SQL)
        self.assertNotIn("INSERT INTO titus.customer_course_drafts_v1", SQL)
        self.assertNotIn("INSERT INTO titus.classroom_events_v1", SQL)

    def test_requires_person_and_live_titus_session(self):
        for fragment in (
            "titus.current_authenticated_person_entity_id_v1()",
            "reality.auth_person_bindings", "entity.identity_state='canonical'",
            "credential.auth_user_id=v_auth", "credential.person_id=v_reality_person",
            "credential.credential_kind='supabase_auth_user'",
            "credential.status='active'", "credential.retired_at IS NULL",
            "auth.jwt()->>'client_id'", "NOT coalesce(u.is_anonymous,false)",
            "u.email_confirmed_at IS NOT NULL", "u.banned_until",
        ):
            self.assertIn(fragment, SQL, fragment)

    def test_exact_published_open_enrollment_source(self):
        for fragment in (
            "e.id=p_enrollment_id", "e.state='active'",
            "e.withdrawn_at IS NULL", "o.state='open'",
            "o.opened_at IS NOT NULL", "o.closed_at IS NULL",
            "o.retired_at IS NULL", "c.status='active'",
            "c.retired_at IS NULL", "v.published_at IS NOT NULL",
            "atlas.teaching_activation_active_v1",
            "o.course_version_id", "atlas.teaching_course_versions v",
        ):
            self.assertIn(fragment, SQL, fragment)

    def test_no_client_supplied_actor_or_role(self):
        self.assertRegex(SQL, r"CREATE FUNCTION public.titus_learner_private_note_create_self_api_v1\(\s*p_enrollment_id uuid,p_request_id uuid,p_body_text text\s*\)")
        self.assertRegex(SQL, r"CREATE FUNCTION public.titus_learner_private_notes_read_self_api_v1\(p_enrollment_id uuid\)")
        self.assertNotIn("p_person_id", SQL)
        self.assertNotIn("p_teacher_id", SQL)
        self.assertNotIn("p_role", SQL)

    def test_no_direct_table_access_and_explicit_rpc_acl(self):
        for fragment in (
            "ENABLE ROW LEVEL SECURITY", "FORCE ROW LEVEL SECURITY",
            "REVOKE ALL ON TABLE titus.learner_private_course_note_events_v1",
            "FROM PUBLIC,anon,authenticated,service_role",
            "GRANT EXECUTE ON FUNCTION public.titus_learner_private_note_create_self_api_v1",
            "GRANT EXECUTE ON FUNCTION public.titus_learner_private_notes_read_self_api_v1",
        ):
            self.assertIn(fragment, SQL, fragment)
        self.assertNotRegex(SQL, r"GRANT\s+(?:SELECT|INSERT|UPDATE)\s+ON\s+TABLE.*learner_private_course_note_events", "Do not expose note table")

    def test_writer_serializes_rechecks_and_preserves_idempotent_original(self):
        self.assertIn("FOR UPDATE;", SQL)
        self.assertGreater(SQL.count("FROM titus.learner_private_note_authority_self_v1(p_enrollment_id)"), 2)
        for fragment in (
            "CONSTRAINT learner_private_note_idempotency_v1 UNIQUE(enrollment_id,request_id)",
            "v_existing.body_text IS DISTINCT FROM pg_catalog.btrim(p_body_text)",
            "'replay',true", "'replay',false", "Private notebook note limit reached",
            "CREATE TRIGGER learner_private_notes_immutable_v1",
            "BEFORE UPDATE OR DELETE",
        ):
            self.assertIn(fragment, SQL, fragment)

    def test_read_returns_only_owner_originals_without_roster(self):
        self.assertIn("n.enrollment_id=p_enrollment_id AND n.learner_person_id=v_person",SQL)
        self.assertIn("n.course_version_id=v_version",SQL)
        self.assertIn("'notes',v_notes",SQL)
        self.assertNotIn("'students'",SQL)
        self.assertNotIn("'teachers'",SQL)
        self.assertNotIn("'sourceBodies'",SQL)

    def test_disclosure_and_current_titus_private_draft_not_shortcut(self):
        self.assertNotIn("titus.customer_current_auth_user_v1()",SQL)
        self.assertNotIn("titus.customer_course_units_v1",SQL)
        self.assertNotIn("INSERT INTO titus.classroom_",SQL)
        self.assertNotIn("public.titus_classroom_append_self_api_v1",SQL)

if __name__ == "__main__":
    unittest.main()
