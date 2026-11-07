"""Fail closed: scratch staging is not the owner-approved production clone."""
from pathlib import Path
import subprocess,unittest

ROOT=Path(__file__).resolve().parents[2]
CAND=ROOT/"candidates/shared-titus-learner-private-notebook-v1"
STAGE=ROOT/"scripts/stage-held-titus-learner-clone-source.sh"
PROTECTED=ROOT/".github/workflows/production-schema-clone-validation.yml"
LOCAL=ROOT/".github/workflows/shared-titus-learner-private-signed-local.yml"

class ClonePreflight(unittest.TestCase):
 def test_candidate_blob_and_no_releasable_copy(self):
  sha=subprocess.run(["git","hash-object",str(CAND/"candidate.sql")],
   cwd=ROOT,text=True,capture_output=True,check=True).stdout.strip()
  self.assertEqual(sha,"d1a00f02b8673e8b016ab8ef124a52dbe40c8101")
  self.assertFalse(any("learner_private_notebook" in f.name for
   f in (ROOT/"supabase/migrations").glob("*.sql")))
 def test_scratch_stage_never_connects_or_publishes(self):
  s=STAGE.read_text()
  for term in ("supabase init --force","supabase migration new shared_titus_learner_private_notebook_clone_only_v1",
   'git -C "$repo" hash-object "$source"', 'cmp -s "$source"',
   "trap cleanup EXIT INT TERM","unset DATABASE_URL NOEL_CORE_DATABASE_URL"):
   self.assertIn(term,s,term)
  for bad in ("supabase db push","supabase db dump","supabase link",
   "supabase start","environment: production","gh issue create"):
   self.assertNotIn(bad,s,bad)
 def test_canonical_cloning_remains_owner_gated(self):
  w=PROTECTED.read_text()
  for key in ("github.event.issue.author_association == 'OWNER'",
   "startsWith(github.event.issue.title, 'Production schema validation request:')",
   "environment: production","production-user-schema.sql",
   "production-custom-roles.sql","find candidate/supabase/migrations"):
   self.assertIn(key,w,key)
  self.assertNotIn("shared-titus-learner-private-notebook-v1/candidate.sql",w)
 def test_source_shaped_fixture_still_not_a_canonical_clone(self):
  fx=(CAND/"signed_local_fixture.sql").read_text()
  probe=(CAND/"validate_signed_local_http.py").read_text()
  review=(CAND/"PRODUCTION_SHAPE_REVIEW.md").read_text()
  for name in ("course_key","version_no","created_by_principal_id",
   "enrolled_by_principal_id","published_by_principal_id",
   "atlas.capability_subject_valid_v1","atlas.capability_subject_governed_v1",
   "atlas.capability_active_for_subject_v1",
   "atlas.teaching_activation_active_v1","atlas.principal_ledger_authorities"):
   self.assertIn(name,fx,name)
  self.assertNotIn("atlas.synthetic_capability",fx)
  for table in ("atlas.ledgers","atlas.principals","atlas.capability_activations",
   "atlas.teaching_course_versions","atlas.teaching_enrollments"):
   self.assertIn(table,review)
  for name in ("atlas.capability_definitions","enrolled_by_principal_id",
   "created_by_principal_id","published_by_principal_id",
   "source-governed Teaching","Retired source Ledger"):
   self.assertIn(name,probe,name)
  self.assertIn("BLOCKED",review)
  w=LOCAL.read_text()
  self.assertIn("bash scripts/stage-held-titus-learner-clone-source.sh",w)
  self.assertNotIn("environment: production",w)

if __name__=="__main__":unittest.main()
