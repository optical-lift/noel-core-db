// UNI-OPS-01 P1 — held C1/Done source-custody split integrity (source only).
// These tests never re-fetch the referenced unmerged PR source files,
// inspect production or prove the upstream source unchanged after review.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,existsSync} from 'node:fs';
import {createHash} from 'node:crypto';

const root='../candidates/atlas_actual_first_p1_assigned_care_activity_v1/';
const manifest=JSON.parse(readFileSync(new URL(root+'C1_SOURCE_PROVENANCE_AND_DEPENDENCY_SPLIT_v1.json',import.meta.url),'utf8'));
const doc=readFileSync(new URL(root+'C1_SOURCE_PROVENANCE_AND_DEPENDENCY_SPLIT_v1.md',import.meta.url),'utf8');
const audit=readFileSync(new URL(root+'RELEASE_ELIGIBILITY_20261105.md',import.meta.url),'utf8');
const p1=readFileSync(new URL(root+'01_assigned_activity_recognition_held.sql',import.meta.url),'utf8');
const combined=readFileSync(new URL('../candidates/atlas/20261028235811_atlas_care_single_done_signed_proof_v1.sql',import.meta.url),'utf8');
const preflight=readFileSync(new URL(root+'P1_RELEASE_READONLY_PREFLIGHT.sql',import.meta.url),'utf8');
const byId=new Map(manifest.files.map(x=>[x.id,x]));
const sha40=/^[a-f0-9]{40}$/;

test('source custody split is explicitly release-blocked and does not install clone-only SQL',()=>{
  assert.equal(manifest.contract,'C1_SOURCE_PROVENANCE_AND_DEPENDENCY_SPLIT_v1');
  assert.equal(manifest.releaseEligibility,'BLOCKED');
  assert.equal(manifest.owner,'Noel');
  assert.equal(manifest.evidence.combinedCandidate.canBeReleased,false);
  assert.match(combined,/^BEGIN;\n-- CLONE TEST ONLY:/);
  assert.match(combined,/Refuse absent synthetic C1 canary/);
  assert.equal(manifest.evidence.combinedCandidate.sourceOnly,true);
  assert.equal(existsSync(new URL('../supabase/migrations/20261028235811_atlas_care_single_done_signed_proof_v1.sql',import.meta.url)),false);
  assert.match(doc,/production release remains BLOCKED/);
  assert.match(audit,/Decision: BLOCKED for production release/);
});

test('exact live and held source Git blob provenance is pinned and references close',()=>{
  assert.equal(manifest.files.length,26);
  assert.equal(byId.size,manifest.files.length,'duplicate source-custody ID');
  assert.ok(sha40.test(manifest.evidence.canonicalMainProofRef));
  for(const row of manifest.files){
    assert.match(row.id,/^[a-z0-9_]+$/);
    assert.ok(sha40.test(row.originCommit),'unfrozen source origin '+row.id);
    assert.ok(sha40.test(row.gitBlobSha1),'unfrozen Git source blob '+row.id);
    assert.ok(row.path.startsWith('candidates/')||row.path.startsWith('supabase/migrations/'));
    for(const dep of row.requires){
      assert.ok(byId.has(dep),row.id+' requires missing source '+dep);
    }
  }
  for(const stage of manifest.stageOrder){
    for(const id of stage.requires) assert.ok(byId.has(id),'stage requires unproven source '+id);
  }
  const native=byId.get('live_oct30_root');
  assert.equal(native.path,'supabase/migrations/20261030230921_atlas_ledger_reciprocal_root_work_intake_v1.sql');
  assert.equal(native.gitBlobSha1,'6d3ac9312a44849e1402e41631da0d32922bc454');
  assert.equal(byId.get('live_manual_activity').gitBlobSha1,'548cea7eb76686975aee89cb79f377a5dd74d5db');
});

test('signed P1 composite blob identity is locally reproducible and P1 fragment is byte-exact',()=>{
  const blob='blob '+Buffer.byteLength(combined,'utf8')+'\0';
  const actual=createHash('sha1').update(blob).update(combined).digest('hex');
  assert.equal(actual,manifest.evidence.combinedCandidate.gitBlobSha1);
  assert.ok(combined.includes(p1.trim()),'held P1 SQL is not in the signed composite');
  assert.equal(byId.get('p1_activity_recognition').exactVerbatimInP1CombinedClone,true);
  assert.equal(byId.get('p1_activity_recognition').gitBlobSha1,
    createHash('sha1').update('blob '+Buffer.byteLength(p1,'utf8')+'\0').update(p1).digest('hex'));
});

test('source version drifts block substitution of latest Done and original standing guard',()=>{
  assert.equal(byId.get('lifecycle_shadow_events').exactVerbatimInP1CombinedClone,false);
  assert.equal(byId.get('lifecycle_baseline').exactVerbatimInP1CombinedClone,true);
  assert.equal(byId.get('lifecycle_projection').exactVerbatimInP1CombinedClone,true);
  assert.equal(byId.get('single_done_transition').exactVerbatimInP1CombinedClone,false);
  assert.equal(byId.get('native_standing_guard_replacement').exactVerbatimInP1CombinedClone,false);
  assert.match(doc,/historical cancellation/);
  assert.match(doc,/NOT byte-verbatim/);
  assert.ok(manifest.criticalProvenanceDifferences.length>=5);
  assert.equal(manifest.liveFingerprintObservations.guard_work_allocation_responsibility_establishment_v2,
    '1043ad551860196f1a13df25de9f8478');
  assert.equal(manifest.liveFingerprintObservations.oct30RootCapabilityGuardPresent,true);
  assert.equal(manifest.liveFingerprintObservations.ensure_rhythm_task_v1,
    'b1c08de87ddb8033a26793005d74149a');
});

test('the final care Result writer, not older direct writer, is selected',()=>{
  assert.equal(byId.get('care_base_writer_superseded').exactVerbatimInP1CombinedClone,true);
  assert.equal(byId.get('care_single_done_writer').exactVerbatimInP1CombinedClone,true);
  assert.ok(byId.get('care_single_done_writer').requires.includes('single_done_transition'));
  assert.ok(byId.get('care_signed_adapter').requires.includes('care_single_done_writer'));
  assert.ok(manifest.excludedFromProduction.some(s=>s.includes('02_farm_care_actual_adapter.sql')));
  assert.ok(manifest.stageOrder.some(stage=>stage.stage==='L2'));
  assert.ok(manifest.stageOrder.some(stage=>stage.stage==='C1'));
  assert.ok(manifest.stageOrder.some(stage=>stage.stage==='C2'));
});

test('latest historical cancellation dependency is not misrepresented as signed P1 acceptance',()=>{
  const history=byId.get('historical_review_source');
  assert.equal(history.originPr,2368);
  assert.equal(history.exactVerbatimInP1CombinedClone,false);
  assert.equal(byId.get('historical_cancel_bridge').exactVerbatimInP1CombinedClone,false);
  assert.equal(manifest.liveFingerprintObservations.historical_self_adoption_review_events_v1,'ABSENT');
  assert.match(doc,/not part of the passing P1 composite|Not included in P1 signed composite/i);
  assert.match(manifest.nextSingleOutcome,/reconcile PR #2368 current 01\/06/);
});

test('catalog preflight remains read-only and no release action is smuggled into source checks',()=>{
  const statement=preflight.split('\n').filter(s=>!s.trimStart().startsWith('--')).join('\n');
  assert.match(statement,/\bWITH required\(/);
  assert.match(statement,/\bSELECT kind,identity,purpose/);
  assert.doesNotMatch(statement,/\b(CREATE|ALTER|DROP|TRUNCATE|INSERT|UPDATE|DELETE|GRANT|REVOKE|COPY|CALL)\s+(TABLE|FUNCTION|SCHEMA|INTO|FROM|ON)\b/i);
  assert.match(doc,/never.*production migration|not a new migration/i);
  assert.match(doc,/no release request/i);
});
