#!/usr/bin/env node
// HELD TEST ONLY: assemble first-mowing P3 6A overlays onto an independently
// verified U2->U4 disposable 18-stage signed source. NO DB, no network,
// no roles, no release migration, no feature merge, no production access.
// Caller MUST independently source-review U2/U4/P3 and enforce an owner-gated
// disposable PG17/GoTrue clone before executing the output.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,realpathSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {basename,dirname,isAbsolute,resolve,sep} from 'node:path';
import {tmpdir} from 'node:os';
const sourceDir=new URL('./',import.meta.url);
const files=[
  ['01_result_only_rhythm_evaluator_held.sql','155bb1c154903becdbb489c6bddb895aa9a6b597'],
  ['02_accepted_first_original_readiness_held.sql','847f523c2bc2872623aa30252489965f87d0c1c0'],
  ['03_governed_rulebook_legacy_clock_cutover_held.sql','0070ee438b3e786815cc5a514a3fea453bf8117c'],
  ['04_canonical_original_acceptance_guard_held.sql','af9a70d8e29273707b6eb20d1b4c8a153ffa9d60'],
  ['06_deferred_governed_original_finalization_held.sql','a1bbc4f05b61f3de7694a738976bca3d838bbc32'],
  ['11_governed_rhythm_clock_signal_specific_hold_held.sql','95b93e896ceaae90d9bfe59eefda695dad204e72'],
  ['12_direct_rhythm_base_writers_governed_hold_held.sql','3b602219316e132dcc7e5562724308b3c093148f'],
  ['20_mowing_6a_core_postconditions_held.sql','210c42f97ceebc8dde2b493e898d23747cce7787']
];
const sha256=b=>createHash('sha256').update(b).digest('hex');
const gitBlob=b=>createHash('sha1')
  .update(Buffer.from('blob '+b.length+'\0')).update(b).digest('hex');
function insistTemp(path){
  assert.ok(isAbsolute(path),'disposable scratch path must be absolute');
  const parent=realpathSync(dirname(path));
  const allow=[tmpdir(),process.env.RUNNER_TEMP].filter(Boolean).map(x=>resolve(x));
  assert.ok(allow.some(a=>parent===a||parent.startsWith(a+sep)),
    'scratch must stay beneath operating-system or runner temporary directory');
}
const [input,expectedDigest,output]=process.argv.slice(2);
assert.ok(input && expectedDigest && output &&
  /^[0-9a-f]{64}$/.test(expectedDigest),
  'Usage: node 22_compose_mowing_6a_scratch_held.mjs ABSOLUTE_U4_DISPOSABLE_ONLY.sql INPUT_SHA256 ABSOLUTE_20261107211000_atlas_uni_ops_p3_6a_TEST_ONLY.sql');
insistTemp(input);insistTemp(output);
assert.match(basename(input),/DISPOSABLE_ONLY[.]sql$/);
assert.equal(basename(output),'20261107211000_atlas_uni_ops_p3_6a_TEST_ONLY.sql',
  'exact disposable Atlas validation version and TEST_ONLY filename required');
assert.notEqual(resolve(input),resolve(output));
const baseline=readFileSync(input);
assert.equal(sha256(baseline),expectedDigest,'immutable verified U4 scratch digest changed');
const raw=baseline.toString('utf8');
assert.equal((raw.match(/-- BEGIN PINNED STAGE /g)||[]).length,18);
assert.equal((raw.match(/-- END PINNED STAGE /g)||[]).length,18);
assert.ok(raw.includes('-- BEGIN U4 DISPOSABLE PUBLIC TRANSPORT SOURCE BLOB:3e09b66e54c15e100110c2b50f43dc9c7593e51a'),
 'trusted U4 exact signed Actual transport not present');
assert.ok(!raw.includes('uni_ops_legacy_rhythm_under_governed_rulebook_held_v1'),
  'P3 source already present: double installation or unreviewed composition');
assert.ok(!raw.includes('-- BEGIN PINNED P3 6A HELD STAGE '),
  'P3 stage already present');
const stageBytes=files.map(([name,pin])=>{
  const b=readFileSync(new URL(name,sourceDir));
  assert.equal(gitBlob(b),pin,'P3 reviewed file changed: '+name);
  return {name,pin,body:b.toString('utf8')};
});
assert.equal(new Set(stageBytes.map(s=>s.name)).size,8);
const preflight=`
-- BEFORE P3 file 01: stop if this U2/U4 clone's evaluator is NOT the
-- exact frozen source from the November 6 read-only Production audit.
-- Do not silently overwrite altered R02/U4 current evaluator source.
DO $p3_fingerprint$
BEGIN
 IF pg_catalog.to_regprocedure(
    'atlas.evaluate_rhythm_binding_v1(uuid,timestamptz,text)') IS NULL
    OR pg_catalog.md5(pg_catalog.pg_get_functiondef(
      'atlas.evaluate_rhythm_binding_v1(uuid,timestamptz,text)'::regprocedure
    )) IS DISTINCT FROM '774ad5c6728a615ada5bf4ea823c5498'
 THEN RAISE EXCEPTION 'P3 evaluator source fingerprint drift; stop'; END IF;
END
$p3_fingerprint$;
`;
const chunks=[raw,preflight,...stageBytes.map(s=>
  '\n-- BEGIN PINNED P3 6A HELD STAGE '+s.name+' '+s.pin+'\n'+
  s.body+'\n-- END PINNED P3 6A HELD STAGE '+s.name+'\n')];
const combined=chunks.join('\n');
assert.equal((combined.match(/-- BEGIN PINNED STAGE /g)||[]).length,18);
assert.equal((combined.match(/-- BEGIN PINNED P3 6A HELD STAGE /g)||[]).length,8);
writeFileSync(output,combined,{flag:'wx',mode:0o600});
console.log('P3_6A_DISPOSABLE_SCRATCH_CREATED='+basename(output));
console.log('P3_6A_SOURCE_STAGE_COUNT=8');
console.log('P3_6A_SCRATCH_SHA256='+sha256(Buffer.from(combined)));
console.log('SIGNED_POST_RESULT_6A=NOT_RUN');
console.log('PRODUCTION_MUTATION=NONE');
