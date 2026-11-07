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

 def test_held_clone_adapter_cannot_bypass_real_schema_or_owner(self):
  adapter=ROOT/"scripts/validate-titus-learner-private-notebook-clone-signed-http.py"
  proposed=ROOT/"scripts/validate-production-schema-clone.sh"
  validator=(CAND/"validate_signed_local_http.py").read_text()
  a=adapter.read_text()
  r=proposed.read_text()
  for source,required in (
   (a,("--require-canonical-clone","module.main()")),
   (r,("signed_titus_learner_private_probe=false",
       "signed_titus_learner_private_probe=true",
       "d1a00f02b8673e8b016ab8ef124a52dbe40c8101",
       "validate-titus-learner-private-notebook-clone-signed-http.py",
       "signed-titus-learner-notebook-summary.txt")),
   (validator,("def verify_canonical_clone_shape():",
       "atlas.organizations","atlas.organization_ledger_entries",
       "atlas.teaching_course_versions","atlas.teaching_course_offerings",
       "relrowsecurity AND relforcerowsecurity","--require-canonical-clone")),
  ):
   for token in required:self.assertIn(token,source,token)
  self.assertIn('if ARGS.require_canonical_clone:',validator)
  self.assertIn("verify_canonical_clone_shape()",validator)
  self.assertNotIn("environment: production",a)
  self.assertNotIn("NOEL_CORE_DATABASE_URL",a)
  self.assertNotIn("supabase db dump",a)
  self.assertNotIn("candidate/supabase/migrations",a)
  # The *main* workflow is still owner-only. Draft runner changes alone cannot
  # be used in the protected job, which checks out main and not this PR's script.
  self.assertIn("ref: main",PROTECTED.read_text())
 def test_real_local_adapter_refusal_has_zero_auth_and_note_writes(self):
  runner=(ROOT/"scripts/test-shared-titus-learner-signed-local.sh").read_text()
  for fragment in (
   'before_refusal="$(psql "$db_url"',
   'validate-titus-learner-private-notebook-clone-signed-http.py',
   "'Clone preflight refused:'",
   'after_refusal="$(psql "$db_url"',
   'SELECT count(*) FROM auth.users',
   'SELECT count(*) FROM titus.learner_private_course_note_events_v1',
   '! -e "$scratch/clone-refusal-summary.txt"',
   'PASS canonical-clone adapter refused reduced local schema',
  ):
   self.assertIn(fragment,runner,fragment)
  self.assertLess(runner.index('before_refusal='),runner.index('after_refusal='))
  self.assertLess(runner.index('after_refusal='),runner.index('synthetic_clone_shape_extension.sql'))
  self.assertLess(runner.index('synthetic_clone_shape_extension.sql'),
                  runner.index('python3 "$root/scripts/validate-titus-learner-private-notebook-clone-signed-http.py"'))
  extension=(CAND/"synthetic_clone_shape_extension.sql").read_text()
  self.assertIn("CREATE TABLE atlas.organizations",extension)
  self.assertIn("CREATE TABLE atlas.organization_ledger_entries",extension)
  self.assertIn("ALTER TABLE atlas.ledgers",extension)
  self.assertNotIn("auth.users",extension)
  probe=(CAND/"validate_signed_local_http.py").read_text()
  self.assertIn('if ARGS.require_canonical_clone:',probe)
  self.assertIn("INSERT INTO atlas.organizations",probe)
  self.assertIn('org_columns=",organization_id"',probe)

 def test_clone_runner_oauth_config_is_limited_to_held_titus_probe(self):
  source=(ROOT/"scripts/validate-production-schema-clone.sh").read_text()
  selector='if [ "$signed_titus_learner_private_probe" = true ]; then'
  self.assertIn(selector,source)
  self.assertIn('authorization_url_path = "/oauth/consent"',source)
  self.assertIn('section = "[auth.oauth_server]"',source)
  self.assertIn('assert source.count(section) == 1',source)
  self.assertLess(source.index('section = "[auth.oauth_server]"'),source.index("local_started=true"))
  self.assertIn('ref: main',PROTECTED.read_text())
  self.assertNotIn('authorization_url_path = "/oauth/consent"',PROTECTED.read_text())

 def test_clone_preflight_fails_closed_when_catalog_missing(self):
  import importlib.util
  from unittest.mock import patch
  probe=CAND/"validate_signed_local_http.py"
  spec=importlib.util.spec_from_file_location("held_titus_shape",probe)
  mod=importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  with patch.object(mod,"db",return_value="f"):
   with self.assertRaisesRegex(AssertionError,"Clone preflight refused"):
    mod.verify_canonical_clone_shape()

if __name__=="__main__":unittest.main()
