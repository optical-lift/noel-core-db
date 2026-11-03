// R01 held-source regression tests; no database, live state or credentials.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const folder=new URL('../candidates/atlas_universal_continuing_original_work_v1/',import.meta.url);
const read=(file)=>readFileSync(fileURLToPath(new URL(file,folder)),'utf8');
const guard=read('16_native_standing_source_authority_extension_v1.sql');
const actual=read('10_care_actual_single_done_cutover_candidate.sql');
const writer=read('19_owner_standing_visit_source_writer.sql');
const selector=read('21_owner_standing_successor_authority.sql');
const advance=read('22_owner_standing_campaign_auto_advance.sql');
const bundle=read('r01_reality_offering_release_candidate.sql');
const post=read('r01_reality_offering_postconditions.sql');
const runner=read('manual_r01_reality_offering_rollback.sh');

test('the current native Ledger root check remains in the extended guard',()=>{
  assert.match(guard,/1043ad551860196f1a13df25de9f8478/);
  assert.match(guard,/capability_root_authority_context_self_v1/);
  assert.match(guard,/Exact Ledger root required for connection-direct responsibility/);
});
test('existing fresh observed-source native admission is not overwritten',()=>{
  assert.match(guard,/standing_continuing_source_admission_v1/);
  assert.match(guard,/continuing_work_source_governance_events_v1/);
  assert.match(guard,/Native Ledger standing agreement/);
});
test('an accepted physical Actual is the only new worker successor authority',()=>{
  assert.match(guard,/standing_care_auto_continuation_v1/);
  assert.match(guard,/standing_care_auto_successor_authorized_v1/);
  assert.match(guard,/owner_preapproved_standing_care_actual_successor_v1/);
  assert.match(selector,/work_result_acceptances/);
  assert.match(selector,/rhythm_satisfactions/);
});
test('the physical Result uses one immutable Work Done, not another terminal writer',()=>{
  assert.match(actual,/apply_work_lifecycle_transition_internal_v1/);
  assert.match(actual,/historicalRecordedCompletion/);
  assert.equal((actual.match(/advance_owner_standing_campaign_after_actual_internal_v1/g)||[]).length,2);
  assert.match(actual,/source_continuation_needs_review/);
  assert.match(actual,/campaignContinuation/);
});
test('initial owner mandate, next subject, and continuation stay bounded',()=>{
  assert.match(writer,/company_work_native_ledger_owner_self_v1/);
  assert.match(writer,/has_current_subject_disclosure_v1/);
  assert.match(selector,/has_current_subject_disclosure_v1/);
  assert.match(selector,/sourceStandingCampaignId/);
  assert.match(advance,/existing_open_campaign_work/);
  assert.match(advance,/sourceStandingCampaignEndsOn/);
  assert.match(advance,/work_result_acceptances/);
});
test('the assembled candidate is an unapplied and explicit hold',()=>{
  assert.ok(bundle.startsWith('BEGIN;\n'));
  assert.ok(bundle.trimEnd().endsWith('COMMIT;'));
  assert.match(bundle,/held universal one-Done lifecycle/);
  for(const file of [
    '16_native_standing_source_authority_extension_v1.sql',
    '19_owner_standing_visit_source_writer.sql',
    '21_owner_standing_successor_authority.sql',
    '22_owner_standing_campaign_auto_advance.sql',
    '10_care_actual_single_done_cutover_candidate.sql'
  ])assert.ok(bundle.includes(read(file)),file+' source not assembled intact');
  assert.match(post,/has_function_privilege\('authenticated'/);
});
test('the only available smoke path refuses a remote database',()=>{
  assert.match(runner,/127\.0\.0\.1:54322/);
  assert.doesNotMatch(runner,/supabase\.co/);
  assert.match(runner,/ROLLBACK;/);
});
