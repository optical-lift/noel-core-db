#!/usr/bin/env node
// UNI-OPS-01 held test-only comparator. NOT an Actual writer, migration,
// source authorization, database substitute, or signed-session test.
// Run only on before/after JSON captured from the independent disposable
// PG17/GoTrue test using 18_disposable_signed_result_snapshot.sql.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

function readSnapshot(path,phase){
  const raw=readFileSync(path,'utf8').trim();
  // psql -qAt emits exactly one JSON line. Refuse extra output or ambiguity.
  assert.ok(raw.startsWith('{') && raw.endsWith('}') && !raw.includes('\n'),
    'snapshot must be exactly one JSON object (no psql banners/other rows)');
  const s=JSON.parse(raw);
  assert.equal(s.contract,'uni_ops_p3_signed_result_snapshot_v1');
  assert.equal(s.phase,phase);
  assert.equal(s.validExactOriginal,true,'source-owned original not verified');
  assert.equal(s.validRhythmState,true,'same canonical Rhythm Need not verified');
  assert.equal(s.campaignTableAbsent,true,
    'U2E campaign table present: independent row census required');
  assert.equal(s.campaignOfferTableAbsent,true,
    'U2E campaign-offer table present: independent row census required');
  return s;
}
function eq(a,b,key,message=key){
  assert.deepEqual(b[key],a[key],message);
}
function delta(a,b,key,increment){
  assert.equal(b[key],a[key]+increment,
    `${key}: expected exactly ${increment} new physical/source row(s)`);
}
const [beforeFile,afterFile,kind,replayFile]=process.argv.slice(2);
assert.ok(beforeFile&&afterFile&&['completed','partial','blocked'].includes(kind),
  'Usage: node 19_compare_signed_result_snapshots.mjs BEFORE.json AFTER.json completed|partial|blocked [REPLAY.json]');
const before=readSnapshot(beforeFile,'before');
const after=readSnapshot(afterFile,'after');
assert.equal(before.originalWorkState,'open');
assert.equal(before.sourceWorkTotal,1,'test fixture must have exactly one source original');
const fixed=[
  'workTotal','sourceWorkTotal','legacyTaskTotal','plannedOccurrenceTotal',
  'governedOfferTotal','workAllocationTotal','workPlanTotal','principalObligationTotal'
];
for(const key of fixed)eq(before,after,key,'unexpected successor or issuer side effect: '+key);

for(const key of ['workResultTotal','originalResultTotal','originalAcceptanceTotal',
  'physicalCareResultTotal','physicalCareObservationTotal']){
  delta(before,after,key,1);
}
assert.ok(typeof after.observedPhysicalCondition==='string' &&
  after.observedPhysicalCondition.length>0,'physical condition must be recorded');
if(kind==='completed'){
  assert.equal(after.originalWorkState,'completed');
  assert.equal(after.rhythmState,'resting');
  delta(before,after,'satisfactionTotal',1);
  assert.ok(after.qualifyingSatisfactionId &&
    after.qualifyingSatisfactionId!==before.qualifyingSatisfactionId,
    'completed care requires a new true satisfaction');
  assert.ok(after.nextEligibleAt,
    'completed care must preserve the next independently eligible window');
}else if(kind==='partial'){
  assert.equal(after.originalWorkState,'open');
  assert.equal(after.rhythmState,'recovering');
  delta(before,after,'satisfactionTotal',0);
}else{
  assert.equal(after.originalWorkState,'open');
  eq(before,after,'rhythmState',
    'blocked is an Actual, not a fabricated Rhythm satisfaction/Need repair');
  delta(before,after,'satisfactionTotal',0);
}

if(replayFile){
  const replay=readSnapshot(replayFile,'replay');
  for(const key of [...fixed,'workResultTotal','originalResultTotal',
    'originalAcceptanceTotal','physicalCareResultTotal','physicalCareObservationTotal',
    'satisfactionTotal','originalWorkState','rhythmState',
    'qualifyingSatisfactionId','nextEligibleAt','observedPhysicalCondition']){
    eq(after,replay,key,'exact action replay created or revised source state: '+key);
  }
}
console.log('UNI_OPS_P3_SIGNED_RESULT_SNAPSHOT_COUNTS=PASS; independently signed actor, receipt and PostgreSQL proof required');
