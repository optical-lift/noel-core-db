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
  'current_principal_id_v1','is_compatibility_primary=true','participation_kind=\\'governing\\'',
  'work_requirements','state=\\'active\\'','source_object_type=\\'reality_entity\\'',
  'reality.entities','identity_state=\\'canonical\\'',
  'has_current_subject_disclosure_v1','\\'identity\\'','\\'condition\\''
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
 'v_prior.rule_status=\\'retired\\'','v_prior.rule_version+1',
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
test('public receipts say this cannot execute Work or Clock',()=>{
 assert.match(s,/'workCreated',false/);
 assert.match(s,/'clockAdmitted',false/);
 assert.match(s,/'policyExecutable',false/);
 assert.match(s,/RETURN jsonb_build_object\('ok',true,'replayed',true/);
});
