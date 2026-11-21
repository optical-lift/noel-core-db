import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {INPUTS,gitBlob,buildReleasePacket,verifyFromRepository,assertSourceSecurity}
  from '../candidates/atlas_native_person_completion_release_packet_v1/verify_release_packet.mjs';

const ROOT='candidates/atlas_native_person_completion_release_packet_v1';
const parts=INPUTS.map(x=>readFileSync(x.path,'utf8'));
const committed=readFileSync(resolve(ROOT,'candidate.sql'),'utf8');
const postconditions=readFileSync(resolve(ROOT,'postconditions.sql'),'utf8');

test('immutable source-linked candidate exactly equals seven owner files in fixed order',()=>{
  assert.equal(buildReleasePacket(parts),committed);
  assert.equal(verifyFromRepository().gitBlob,'2ee49072aee9e6d7ab9180c21ce8463f7e713994');
  assert.equal(Buffer.byteLength(committed,'utf8'),66571);
  assert.equal(parts.length,7);
  assert.ok(INPUTS.every((x,k)=>gitBlob(parts[k])===x.git));
});
test('native-Person-only core and original three writers, no new public entrypoint',()=>{
  assert.doesNotThrow(()=>assertSourceSecurity(committed));
  assert.match(committed,/work_lifecycle_event_append_only_v1/);
  assert.match(committed,/Historical self-adopted responsibility requires native reconciliation/);
  assert.match(committed,/Current native responsible Person required/);
  assert.match(committed,/p_transition_kind IS DISTINCT FROM 'complete'/);
  assert.match(committed,/personalPerformanceNotClaimed/);
  assert.match(committed,/'contractVersion','connected_person_company_work_result_v1'/);
  assert.match(committed,/'resultId',v_result.id/);
  assert.match(committed,/'resultKind','completed'/);
  assert.match(committed,/'oneLifecycleDone',v_universal_receipt/);
  assert.equal((committed.match(/apply_work_lifecycle_transition_internal_v1\(/g)||[]).length,6);
  assert.doesNotMatch(committed,/CREATE OR REPLACE FUNCTION public\./);
  assert.doesNotMatch(committed,/historical_self_adoption_review_events_v1|IF p_transition_kind='cancel' THEN/);
  assert.doesNotMatch(committed,/e5200000|CLONE TEST ONLY|recognize_assigned_care_activity_self_api_v1/);
});
test('must preserve old originals as historical observations before installing writers',()=>{
  const lock=committed.indexOf('LOCK TABLE atlas.work_items,atlas.work_allocations,');
  const seed=committed.indexOf('SELECT atlas.seed_work_lifecycle_shadow_baseline_internal_v1();');
  const trig=committed.indexOf('CREATE TRIGGER work_items_shadow_lifecycle_state_v1');
  const actor=committed.indexOf('CREATE OR REPLACE FUNCTION atlas.apply_work_lifecycle_transition_internal_v1(');
  const writer=committed.indexOf('CREATE OR REPLACE FUNCTION atlas.report_connected_person_company_work_internal_v1(');
  assert.ok(lock>0 && lock<seed && seed<trig && trig<actor && actor<writer);
  assert.match(parts[1],/Historical baseline is a privileged custody operation/);
  assert.equal((committed.match(/SELECT atlas.seed_work_lifecycle_shadow_baseline_internal_v1\(\);/g)||[]).length,1);
});
test('postconditions require actual ACL, RLS, no cancellation and current original writer delegation',()=>{
  assert.match(postconditions,/has_function_privilege\('service_role'/);
  assert.match(postconditions,/relforcerowsecurity/);
  assert.match(postconditions,/work_lifecycle_event_append_only_v1/);
  assert.match(postconditions,/Historical self-adopted Work is reference only/);
  assert.match(postconditions,/report_connected_person_company_work_internal_v1/);
  assert.match(postconditions,/mark_ledger_occurrence_shared_work_done_self_api_v1/);
  assert.match(postconditions,/historical_self_adoption_review_events_v1/);
  assert.match(postconditions,/baseline not complete/i);
});
test('fail closed if a single owner-source byte is changed or release includes synthetic history',()=>{
  const tampered=parts.slice();tampered[3]=tampered[3].replace("IS DISTINCT FROM 'complete'","NOT IN ('complete','cancel')");
  assert.throws(()=>buildReleasePacket(tampered),/immutable source blob/);
  assert.throws(()=>assertSourceSecurity(committed.replace('COMMIT;','SELECT 42; COMMIT;')),/custody mismatch/);
  assert.throws(()=>assertSourceSecurity(committed.replace("Current native responsible Person required","Legacy members allowed")),/custody mismatch/);
});
