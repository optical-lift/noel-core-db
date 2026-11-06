// UNI-OPS-01 immutable-source compatibility guard, 2026-11-06.
// READ ONLY. Not a SQL compiler, signed runtime test, migration or release grant.
// Run with seven *local* immutable SQL files in this exact order:
// completion packet, native L2, P1 recognition, C1 care Actual, U2C original guard,
// U2E campaign source, U2E direct-route cutover.
// A PASS explicitly preserves the campaign/P1 incompatibility as a HOLD.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

const files = [
  ['completion','0e7c8581e6656b218bdc1ff2c13152201e3e03f5'],
  ['nativeL2','3178e11863f1c6de89e07724c3b209923fd825d3'],
  ['p1','476e85b1e6f46d7ac996dce9ea0e51b89c50f28c'],
  ['actual','967456ae34a305a59d663a73f90f9070ef74f1ba'],
  ['u2c','4413d84b042a357567a2334cddccc859650c41dc'],
  ['u2e','a558a8bd09e9e470ec82619193e3162b6818f0f7'],
  ['u2eCut','4fdc9cf56cefe6c70ec5af24ec43f7a5e8a72015']
];
if (process.argv.length !== files.length + 2) {
  throw Error('Supply seven local SQL paths in the order documented in this file');
}
const sql = {};
for (let i = 0; i < files.length; i++) {
  const [key, expected] = files[i];
  const bytes = readFileSync(process.argv[i + 2]);
  const sha = createHash('sha1').update('blob ' + bytes.length + '\0').update(bytes).digest('hex');
  if (sha !== expected) throw Error('STOP ' + key + ' source blob changed: ' + sha);
  sql[key] = bytes.toString('utf8');
  process.stdout.write('PIN ' + key + ' ' + sha + '\n');
}
const tests = [
 ['native completion only; no historical cancel',
  sql.completion.includes("p_transition_kind IS DISTINCT FROM 'complete'") &&
  !sql.completion.includes("IF p_transition_kind='cancel' THEN") &&
  !sql.completion.includes('historical_self_adoption_review_events_v1')],
 ['one private Done writer and current Person authority',
  (sql.completion.match(/CREATE OR REPLACE FUNCTION atlas\.apply_work_lifecycle_transition_internal_v1\(/g) || []).length === 1 &&
  sql.nativeL2.includes('Current native responsible Person required')],
 ['P1 requires preexisting specific assignment',
  sql.p1.includes('v_work.created_at>v_activity.created_at') &&
  sql.p1.includes('v_allocation.allocated_at>v_activity.created_at') &&
  sql.p1.includes('INSERT INTO atlas.assigned_care_activity_recognition_links_v1')],
 ['P1 calls source-qualified physical Actual',
  sql.p1.includes('atlas.record_continuing_care_actual_self_api_v1(') &&
  sql.p1.includes("'source_qualified_physical_actual'")],
 ['care source invokes same private lifecycle Done',
  sql.actual.includes('atlas.apply_work_lifecycle_transition_internal_v1(') &&
  sql.actual.includes("v_work.id,'complete',v_result.id,v_source_key")],
 ['P1 requires no-new-Work and no-Clock receipts',
  sql.p1.includes("v_receipt->>'noNewWorkCreated' IS DISTINCT FROM 'true'") &&
  sql.p1.includes("v_receipt->>'noClockAdmission' IS DISTINCT FROM 'true'")],
 ['care writer has no inline successor issuer',
  sql.actual.includes("'noNewWorkCreated',true") &&
  !sql.actual.includes('continuing_original_work_result_continuation_internal_v1(')],
 ['P1 rejects campaign-linked original pending P3',
  sql.p1.includes("v_work.metadata ? 'sourceStandingCampaignId'") &&
  sql.p1.includes('Campaign-linked Actual requires no-successor source cutover')],
 ['U2C stamps campaign original only behind accepted-offer guard',
  sql.u2c.includes("'sourceStandingCampaignId',p_action_id") &&
  sql.u2c.includes('atlas.require_accepted_prework_standing_original_v1(')],
 ['U2E has unbound, finite, single-original campaign',
  sql.u2e.includes('unbound') && sql.u2e.includes('original_limit') &&
  sql.u2e.includes('120')],
 ['U2E revokes earlier noncampaign public offer/finalizer',
  sql.u2eCut.includes('REVOKE ALL ON FUNCTION public.offer_next_governed_prework_candidate_self_api_v1') &&
  sql.u2eCut.includes('REVOKE ALL ON FUNCTION public.finalize_accepted_governed_prework_self_api_v1')],
 ['completion packet does not silently install P1',
  !sql.completion.includes('recognize_assigned_care_activity_self_api_v1')]
];
let failures = 0;
for (const [name, pass] of tests) {
  process.stdout.write((pass ? 'PASS ' : 'FAIL ') + name + '\n');
  if (!pass) failures++;
}
if (failures) throw Error('STOP source drift; current compatibility claim invalid');
process.stdout.write('STATIC-ONLY PASS: 7 immutable sources and 12 boundaries.\n');
process.stdout.write('INTEGRATION HELD: U2C campaign originals currently fail P1 until source-governed P3.\n');
process.stdout.write('NOT PROVED: PostgreSQL, GoTrue, concurrency, alternate writers, source ACL, or release.\n');
