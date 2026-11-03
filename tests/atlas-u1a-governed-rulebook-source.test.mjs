// U1A fast static contract; NOT PostgreSQL compilation or signed-actor proof.
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
const p=new URL('../candidates/atlas_governed_rulebook_u1a_v1/candidate.sql', import.meta.url);
const s=readFileSync(p,'utf8');
test('two private append-only Rulebook tables, no competing Person/Need/Work store',()=>{
 for(const t of ['governed_rulebook_versions_v1','governed_rulebook_bindings_v1'])
  assert.match(s,new RegExp('CREATE TABLE atlas\\.'+t+' \\('));
 assert.equal((s.match(/CREATE TABLE /g)||[]).length,2);
 assert.match(s,/BEFORE UPDATE OR DELETE ON atlas\.governed_rulebook_versions_v1/);
 assert.match(s,/BEFORE UPDATE OR DELETE ON atlas\.governed_rulebook_bindings_v1/);
 for(const f of ['work_items','tasks','work_allocations','work_execution_plans','work_execution_results','work_requirements','care_observation_events'])
  assert.doesNotMatch(s,new RegExp('INSERT INTO atlas\\.'+f+'\\b','i'));
 assert.doesNotMatch(s,/ALTER TABLE atlas\.work_items\b|DROP TABLE |CREATE TABLE public\./i);
});
test('native current root, independent disclosure, and existing canonical Need/Subject',()=>{
 for(const q of [
  'foundry_current_signed_principal_v1','company_work_native_ledger_owner_self_v1',
  'current_principal_id_v1','is_compatibility_primary=true','participation_kind=\'governing\'',
  'work_requirements','state=\'active\'','source_object_type=\'reality_entity\'',
  'reality.entities','identity_state=\'canonical\'',
  'has_current_subject_disclosure_v1','\'identity\'','\'condition\''
 ])assert.ok(s.includes(q),q);
});
test('human-owned Foundry source and literal original verified before insertion',()=>{
 for(const q of ['workspace_authority_registry_v1','foundry.events',
 'owner_principal_id=v_root.actor_principal_id','revoked_at IS NULL',
 'suspended_at IS NULL','author_principal_id','source_kind',
 'original_text','strpos(','v_literal','source_basis'])
  assert.ok(s.includes(q),q);
 assert.match(s,/coalesce\(v_segment->>'kind',''\) NOT IN/);
});
test('immutable version / same-action replay / expected prior / retired terminal',()=>{
 for(const q of ['decision_action_id uuid NOT NULL UNIQUE',
 'pg_advisory_xact_lock','p_expected_previous_version_id',
 'v_replay.source_basis IS DISTINCT FROM v_basis',
 'v_prior.rule_status=\'retired\'','v_prior.rule_version+1',
 "p_decision IN ('paused','retired')"])
  assert.ok(s.includes(q),q);
});
test('standing visits do not require fake observation or physical classifier',()=>{
 assert.match(s,/standing_stewardship/);
 assert.match(s,/condition_triggered/);
 assert.match(s,/standingPurpose/);
 assert.match(s,/maxObservationAgeSeconds/);
 assert.doesNotMatch(s,/record_standing_care_observation_self_api_v1\(/);
});
test('signed transport only; revoke private tables, functions and anon',()=>{
 for(const q of ['ENABLE ROW LEVEL SECURITY',
 'REVOKE ALL ON atlas.governed_rulebook_versions_v1',
 'REVOKE ALL ON atlas.governed_rulebook_bindings_v1',
 'FROM PUBLIC,anon,authenticated,service_role',
 'GRANT EXECUTE ON FUNCTION public.adopt_governed_rulebook_version_self_api_v1',
 'GRANT EXECUTE ON FUNCTION public.read_governed_rulebook_current_self_api_v1'])
  assert.ok(s.includes(q),q);
 assert.match(s,/coalesce\(p_policy->>'eligibilityMode',''\) NOT IN/);
 assert.match(s,/coalesce\(p_decision,''\) NOT IN/);
});
test('Foundry source is selected as a complete row, never a composite column',()=>{
 assert.match(s,/SELECT e\.\* INTO v_source FROM foundry\.events e/);
 assert.doesNotMatch(s,/SELECT e INTO v_source FROM foundry\.events e/);
});
test('U1A cannot accept a client-invented property, class or release policy',()=>{
 assert.match(s,/jsonb_object_keys\(p_policy\)/);
 assert.match(s,/Unapproved policy field; requires new scoped rule version/);
 for(const field of ["'eligibilityMode'","'desiredOutcome'","'standingPurpose'",
                     "'triggerMode'","'strategyDisposition'",
                     "'maxObservationAgeSeconds'","'seasonKeys'","'priority'"]){
   assert.ok(s.includes(field),field);
 }
 assert.match(s,/policyExecutable',false/);
 assert.doesNotMatch(s,/INSERT INTO (?:atlas|ledger)\.(?:work_items|work_allocations|work_execution_plans)\b/i);
});
test('public receipts say this cannot execute Work or Clock',()=>{
 assert.match(s,/'workCreated',false/);
 assert.match(s,/'clockAdmitted',false/);
 assert.match(s,/'policyExecutable',false/);
 assert.match(s,/RETURN jsonb_build_object\('ok',true,'replayed',true/);
});

const runner = readFileSync(
  new URL('../candidates/atlas_governed_rulebook_u1a_v1/run_riversong_rollback.sh', import.meta.url),'utf8');
test('RiverSong U1A rollback refuses remote or stale native clone and never persists SQL',()=>{
 for(const gate of [
  'noel_schema_clone','-h "$SOCKET"','pg-isolated',
  'inet_server_addr() IS NULL',"current_setting('data_directory')",
  'atlas.work_requirements','foundry.workspace_authority_registry_v1',
  'to_regprocedure','ON_ERROR_STOP=1',"node --test",
  "'BEGIN;'","'ROLLBACK;'","SET LOCAL statement_timeout",
  '$before','$after'
 ])assert.ok(runner.includes(gate),gate);
 assert.doesNotMatch(runner,/NOEL_CORE_DATABASE_URL|SUPABASE_DB_URL|pg_restore --dbname/);
 assert.doesNotMatch(runner,/supabase db push|supabase migration up|--db-url/);
});
test('RiverSong U1A preflight must precede all SQL sent to psql',()=>{
 const preflight=runner.indexOf('for rel in atlas.organizations atlas.ledgers');
 const baseline=runner.indexOf('before="$(q "$fingerprint")"');
 const entry=runner.indexOf("printf '%s\\n' 'BEGIN;'");
 const rollback=runner.indexOf("printf '%s\\n' 'ROLLBACK;'");
 assert.ok(preflight>0 && baseline>preflight && entry>baseline && rollback>entry);
 assert.match(runner,/set -euo pipefail/);
 assert.match(runner,/HOLD: genuine signed positive\/negative actors and concurrency untested/);
});


test('U1A runner requires a clean reviewed branch before touching the database',()=>{
 for(const needle of [
   'git -C "$HERE" rev-parse --show-toplevel',
   'symbolic-ref --quiet --short HEAD',
   'candidate/atlas-u1a-governed-rulebook-adoption-20261103',
   'status --porcelain --untracked-files=all',
   'SOURCE_SHA="$(git -C "$CHECKOUT" rev-parse HEAD)"',
   'STOP: working tree is dirty or contains untracked files',
   'SOURCE_SHA=$SOURCE_SHA'
 ])assert.ok(runner.includes(needle),needle);
 const branchGuard=runner.indexOf('SOURCE_BRANCH="$(git -C "$CHECKOUT" symbolic-ref');
 const cleanGuard=runner.indexOf('status --porcelain --untracked-files=all');
 const firstPg=runner.indexOf('ident="$(q ');
 const txn=runner.indexOf("printf '%s\\n' 'BEGIN;'");
 assert.ok(branchGuard>0 && cleanGuard>branchGuard && firstPg>cleanGuard && txn>firstPg);
});

test('Foundry adoption requires a current approved independent review case for exact saved original',()=>{
 // The native review decision leaves workspace custody pending; it changes
 // foundry.source_custody_review_cases_v1.review_state to approved. A
 // provisional workspace by itself is never adopted as policy.
 for(const piece of [
   "foundry.source_custody_review_cases_v1",
   "c.review_state='approved'",
   "c.revoked_at IS NULL",
   "c.expires_at IS NULL OR c.expires_at>now()",
   "c.reviewed_at>=v_source.inserted_at",
   "p_entry_id=ANY(c.source_refs)",
   "'analyze'=ANY(c.permitted_human_actions)",
   "c.reviewer_principal_id IS DISTINCT FROM v_root.actor_principal_id",
   "sourceReviewCaseId",
   "sourceReviewRecordedAt"
 ])assert.ok(s.includes(piece),piece);
 assert.match(s,/IF v_review\.case_id IS NULL THEN/);
 assert.doesNotMatch(s,/w\.custody_review_state='reviewed'/);
});

