// Native Person-only lifecycle SOURCE tests. Never substitute for signed clone.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {SOURCE_PATHS,NATIVE_SHA,deriveNativeOnlyL1,deriveNativeOnlyL2,
        assembleNativePersonOnly,assembleFromRepo}
  from '../candidates/atlas_native_person_completion_only_v1/assemble_native_person_only_clone_only.mjs';

const inputs=Object.fromEntries(Object.entries(SOURCE_PATHS)
  .map(([name,path])=>[name,readFileSync(path,'utf8')]));

test('precise current #2368 L1 provenance held without historical-event admission',()=>{
  assert.equal(deriveNativeOnlyL1(inputs.originalL1),inputs.l1);
  assert.match(inputs.l1,/FORCE ROW LEVEL SECURITY/);
  assert.match(inputs.l1,/work_lifecycle_event_append_only_v1/);
  assert.doesNotMatch(inputs.l1,/atlas[.]historical_self_adoption_review_events_v1/);
  assert.match(NATIVE_SHA.l1,/^[0-9a-f]{40}$/);
});

test('completion-only transition matches current native-Person version exactly minus reviewed cancellation',()=>{
  assert.equal(deriveNativeOnlyL2(inputs.originalL2),inputs.l2);
  assert.match(inputs.l2,/p_transition_kind IS DISTINCT FROM 'complete'/);
  assert.match(inputs.l2,/Historical self-adopted responsibility requires native reconciliation/);
  assert.match(inputs.l2,/Current native responsible Person required/);
  assert.match(inputs.l2,/Existing accepted source evidence required/);
  assert.match(inputs.l2,/source_qualified_physical_actual/);
  assert.match(inputs.l2,/personalPerformanceNotClaimed/);
  assert.match(inputs.l2,/work_lifecycle_one_transition_action_v1/);
  assert.match(inputs.l2,/REVOKE ALL ON FUNCTION atlas[.]apply_work_lifecycle_transition_internal_v1/);
  assert.doesNotMatch(inputs.l2,/historical_self_adoption_review_events_v1|work_state='cancelled'|p_transition_kind='cancel'/);
  assert.match(NATIVE_SHA.l2,/^[0-9a-f]{40}$/);
});

test('only one latest-Person completion authority, no hidden historical source, clone only',()=>{
  const {sql,sha256}=assembleFromRepo();
  assert.equal(sha256,assembleNativePersonOnly(inputs).sha256);
  assert.match(sha256,/^[0-9a-f]{64}$/);
  assert.ok(sql.startsWith('BEGIN;\n-- CLONE TEST ONLY: this candidate is NEVER production-releasable.'));
  assert.ok(sql.endsWith('\nCOMMIT;\n'));
  assert.equal((sql.match(/CREATE OR REPLACE FUNCTION atlas[.]apply_work_lifecycle_transition_internal_v1\(/g)||[]).length,1);
  assert.equal((sql.match(/CREATE TABLE atlas[.]work_lifecycle_events_v1 \(/g)||[]).length,1);
  assert.match(sql,/id='e5200000-0000-4000-8000-000000000b03'::uuid/);
  assert.doesNotMatch(sql,/historical_self_adoption_review_events_v1|governor_retire_historical_work_self_api_v1|historicalRetirementReviewId/);
  assert.match(sql,/Historical self-adopted responsibility requires native reconciliation/);
  assert.match(sql,/Current native responsible Person required/);
});

test('fail closed on any unreviewed exact-source drift',()=>{
  const changedL1={...inputs,l1:inputs.l1.replace('FROM PUBLIC,anon,authenticated,service_role;','FROM PUBLIC,anon,authenticated;')};
  assert.throws(()=>assembleNativePersonOnly(changedL1),/L1.*Git blob changed|l1 immutable Git blob changed/);
  const changedL2={...inputs,l2:inputs.l2.replace("IS DISTINCT FROM 'complete'","NOT IN ('complete','cancel')")};
  assert.throws(()=>assembleNativePersonOnly(changedL2),/l2 immutable Git blob changed/);
  const swappedCurrent={...inputs,originalL2:inputs.l2};
  assert.throws(()=>assembleNativePersonOnly(swappedCurrent),/originalL2 immutable Git blob changed/);
  const damagedBase={...inputs,base:inputs.base.replace('CLONE TEST ONLY','RELEASE ALLOWED')};
  assert.throws(()=>assembleNativePersonOnly(damagedBase),/base immutable Git blob changed/);
});
