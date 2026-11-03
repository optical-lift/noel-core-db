// U1A fast static contract; NOT PostgreSQL compilation or signed-actor proof.
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
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



test('source-review withdrawal remains visible in root-only historical readback',()=>{
 assert.match(s,/v_source_review_current boolean := false/);
 assert.match(s,/JOIN foundry\.source_custody_review_cases_v1 c|FROM foundry\.source_custody_review_cases_v1 c/);
 assert.match(s,/c\.review_state='approved'/);
 assert.match(s,/c\.revoked_at IS NULL/);
 assert.match(s,/c\.expires_at IS NULL OR c\.expires_at>now\(\)/);
 assert.match(s,/'sourceReviewCurrent',v_source_review_current/);
 assert.match(s,/'sourceReviewCurrent',false/);
 assert.match(s,/'policyExecutable',false/);
});
test('signed rule adoption serializes with native Foundry review/revocation',()=>{
 const sourceLock=s.indexOf('hashtextextended(p_workspace_id,0)');
 const evidence=s.indexOf('SELECT e.* INTO v_source FROM foundry.events e');
 const approval=s.indexOf('SELECT c.* INTO v_review FROM foundry.source_custody_review_cases_v1 c');
 const writer=s.indexOf('INSERT INTO atlas.governed_rulebook_versions_v1 (');
 assert.ok(sourceLock>0 && evidence>sourceLock && approval>evidence && writer>approval);
 assert.match(s,/c\.reviewed_at>=v_source\.inserted_at/);
 assert.match(s,/p_entry_id=ANY\(c\.source_refs\)/);
 assert.match(s,/'sourceReviewCaseId',v_review\.case_id/);
});


test('review adoption receipt keeps one timezone-invariant source-review timestamp',()=>{
 assert.match(s,/v_review\.reviewed_at AT TIME ZONE 'UTC'/);
 assert.match(s,/YYYY-MM-DD"T"HH24:MI:SS\.US"Z"/);
 assert.match(s,/'sourceReviewCaseId',v_review\.case_id/);
 assert.match(s,/'sourceReviewRecordedAt',to_char\(/);
});


const u1aFixture = readFileSync(
 new URL('../candidates/atlas_governed_rulebook_u1a_v1/signed_u1a_fictional_fixture_v1.sql',import.meta.url),'utf8');
const u1aSigned = readFileSync(
 new URL('../candidates/atlas_governed_rulebook_u1a_v1/validate_signed_u1a_local_clone_v1.py',import.meta.url),'utf8');
test('U1A exact-Subject approval is limited to currently sourced original growing objects',()=>{
 for(const x of [
  "s.entity_kind='growing_object'",
  "s.metadata->>'subjectDomain'='spatial'",
  "FROM atlas.growing_objects go",
  "JOIN atlas.farms f ON f.id=go.farm_id",
  "go.id=s.id AND f.organization_id=p_organization_id"
 ])assert.ok(s.includes(x),x);
});
test('U1A signed fixture is isolated and never seeds a Rulebook approval',()=>{
 for(const x of [
  "current_database()<>'postgres'",
  "inet_server_addr() IS DISTINCT FROM inet '127.0.0.1'",
  "current_setting('port') <> '54322'",
  "e5200000-0000-4000-8000-000000000b03",
  "source_object_type", "reality_entity",
  "fictional_bed3_restorative_maintenance",
  "EXISTS (SELECT 1 FROM atlas.governed_rulebook_versions_v1)",
  "Fictional Bed 3",
 ])assert.ok(u1aFixture.includes(x),x);
 assert.doesNotMatch(u1aFixture,/INSERT INTO atlas\.governed_rulebook_versions_v1|INSERT INTO atlas\.governed_rulebook_bindings_v1/i);
 assert.doesNotMatch(u1aFixture,/INSERT INTO auth\.users|INSERT INTO auth\.sessions|INSERT INTO ledger\.seats/i);
});
test('U1A signed proof uses independent real GoTrue auth and exact native approvals',()=>{
 for(const x of [
  "validate-atlas-work-prerequisite-signed-http.py",
  "c1.sign_in(api, key, name)",
  "auth.sessions",
  "request_foundry_source_custody_review_self_api_v1",
  "decide_foundry_source_custody_review_self_api_v1",
  "capture_foundry_reality_input_self_api_v1",
  "governor_set_subject_disclosure_self_api_v1",
  "adopt_governed_rulebook_version_self_api_v1",
  "read_governed_rulebook_current_self_api_v1",
  "revoke_foundry_source_custody_review_self_api_v1",
  "sourceReviewCurrent",
  "policyExecutable",
  "work_before", "need_before"
 ])assert.ok(u1aSigned.includes(x),x);
 assert.match(u1aSigned,/127\[.\]0\[.\]0\[.\]1:54322\/postgres/);
 assert.doesNotMatch(u1aSigned,/jwt\.encode|jwt\.sign|service_role.*Bearer|NOEL_CORE_DATABASE_URL|SUPABASE_DB_URL/i);
});


test('Python 3 syntax of U1A signed clone utilities',()=>{
 const files=[
   new URL('../candidates/atlas_governed_rulebook_u1a_v1/validate_signed_u1a_local_clone_v1.py',import.meta.url),
   new URL('../candidates/atlas_governed_rulebook_u1a_v1/run_signed_u1a_on_fresh_clone_v1.py',import.meta.url)
 ];
 // ast.parse parses source without importing Supabase or running the script.
 const result=spawnSync('python3',[
  '-c',
  'import ast,sys; [ast.parse(open(p,encoding="utf-8").read(),filename=p) for p in sys.argv[1:]]',
  ...files.map(x=>x.pathname)
 ],{encoding:'utf8',timeout:10000});
 assert.equal(result.status,0,result.stderr||result.error?.message||'Python parser unavailable');
});
test('U1A guarded signed controller cannot target existing RiverSong clone or production',()=>{
 const runner=readFileSync(
  new URL('../candidates/atlas_governed_rulebook_u1a_v1/run_signed_u1a_on_fresh_clone_v1.py',import.meta.url),'utf8');
 for(const v of [
  'confirm-fresh-disposable',
  'postgres(?:ql)?://[^@]+@127[.]0[.]0[.]1:54322/postgres',
  'FRESH_SYNTHETIC',
  'status","--porcelain"',
  'validate_signed_u1a_local_clone_v1.py',
  'signed_u1a_fictional_fixture_v1.sql',
  'DESTROY disposable Auth/REST/Postgres clone now'
 ])assert.ok(runner.includes(v),v);
 assert.doesNotMatch(runner,/NOEL_CORE_DATABASE_URL|supabase db push|--db-url.*noel_schema_clone|remote Supabase SQL/i);
});
