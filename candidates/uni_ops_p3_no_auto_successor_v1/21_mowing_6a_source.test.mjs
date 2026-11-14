// HELD test-only contract: executable no-network P3 core 6A source checks.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,rmSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
const base=new URL('./',import.meta.url);
const read=name=>readFileSync(new URL(name,base),'utf8');
const core=read('20_mowing_6a_core_postconditions_held.sql');
const snap=read('18_disposable_signed_result_snapshot.sql');
const comparator=new URL('19_compare_signed_result_snapshots.mjs',base);
const clean=s=>s.split('\n').filter(l=>!l.trimStart().startsWith('--')).join('\n');
function runCompare(before,after,kind,replay){
  const root=mkdtempSync(join(tmpdir(),'uniops-p3-source-'));
  try{
    const files=['before','after','replay'].map(k=>join(root,k+'.json'));
    writeFileSync(files[0],JSON.stringify(before));
    writeFileSync(files[1],JSON.stringify(after));
    if(replay)writeFileSync(files[2],JSON.stringify(replay));
    return spawnSync(process.execPath,[comparator.pathname,files[0],files[1],kind,...(replay?[files[2]]:[])],
      {encoding:'utf8',timeout:12000});
  }finally{rmSync(root,{recursive:true,force:true});}
}
function before(){
  return {
    contract:'uni_ops_p3_signed_result_snapshot_v1',phase:'before',
    validExactOriginal:true,validRhythmState:true,
    originalWorkState:'open',rhythmState:'due',
    qualifyingSatisfactionId:null,nextEligibleAt:null,observedPhysicalCondition:'overgrown',
    workTotal:1,sourceWorkTotal:1,legacyTaskTotal:0,plannedOccurrenceTotal:0,
    governedOfferTotal:1,workAllocationTotal:1,workPlanTotal:1,
    principalObligationTotal:0,
    workResultTotal:0,originalResultTotal:0,originalAcceptanceTotal:0,
    physicalCareResultTotal:0,physicalCareObservationTotal:0,satisfactionTotal:0,
    legacyReleasedTaskIds:[],eligibleOrReleasedOccurrenceIds:[],releasedOccurrenceIds:[],
    campaignTableAbsent:true,campaignOfferTableAbsent:true
  };
}
function after(b,kind){
  const a={...b,phase:'after',observedPhysicalCondition:
    kind==='completed'?'resting':kind==='partial'?'partial':'too_wet'};
  for(const field of ['workResultTotal','originalResultTotal','originalAcceptanceTotal',
    'physicalCareResultTotal','physicalCareObservationTotal'])a[field]++;
  if(kind==='completed'){
    a.originalWorkState='completed';a.rhythmState='resting';
    a.satisfactionTotal++;a.qualifyingSatisfactionId='fictional-source-satisfaction';
    a.nextEligibleAt='2026-11-21T00:00:00+00:00';
  }else if(kind==='partial'){a.rhythmState='recovering';}
  return a;
}
test('source-only evaluator delta remains unchanged; no PostgreSQL is touched',()=>{
  const r=spawnSync(process.execPath,[new URL('verify_source_delta.mjs',base).pathname],
    {encoding:'utf8',timeout:12000});
  assert.equal(r.status,0,'pinned P3 source delta failed: '+(r.stderr||'').slice(0,800));
  assert.match(r.stdout,/one-expression delta verified/);
});
test('mowing 6A postconditions require original policy, accepted-first and old Task cutover',()=>{
  for(const required of [
    'qualified_evaluation_no_successor',
    'activation_prerequisite_completed',
    'uni_ops_accepted_first_original_source_receipt_held_v1',
    'require_accepted_prework_standing_original_v1',
    'guard_uni_ops_governed_care_original_acceptance_v1',
    'require_uni_ops_original_finalize_on_commit_v1',
    'z_uni_ops_governed_original_finalization_v1',
    't.tgdeferrable AND t.tginitdeferred',
    'governed_rhythm_clock_signal_held',
    'noAutomaticNextTask',
    'ensure_rhythm_task_v1_base',
    'ensure_rhythm_task_without_physical_gate_v1',
    "has_function_privilege('service_role'",
  ])assert.ok(core.includes(required),'missing 6A source gate '+required);
  for(const unneeded of [
    'uni_ops_p3_owner_attention_decision_events_v1',
    'uni_ops_governed_case_decision_events_v1',
    'uni_ops_p3_owner_pending_decisions_self_held_v1'
  ])assert.ok(!clean(core).includes(unneeded),
    'universal mowing cannot require farm-specific owner-decision store');
  assert.doesNotMatch(clean(core),/\b(?:INSERT\s+INTO|UPDATE\s+atlas\.|DELETE\s+FROM|CREATE\s+TABLE|DROP\s+TABLE)\b/i);
});
test('signed snapshot reads original, physical Result, existing releases and holds campaign uncertainty',()=>{
  for(const f of ['validExactOriginal','validRhythmState','observedPhysicalCondition',
    'originalAcceptanceTotal','physicalCareResultTotal','physicalCareObservationTotal',
    'legacyReleasedTaskIds','eligibleOrReleasedOccurrenceIds','releasedOccurrenceIds',
    'workTotal','workPlanTotal','principalObligationTotal',
    'campaignTableAbsent','campaignOfferTableAbsent']){
    assert.ok(snap.includes("'"+f+"'"),'missing snapshot witness: '+f);
  }
  const sql=clean(snap).split('\n').filter(l=>!l.trim().startsWith('\\')).join('\n');
  assert.doesNotMatch(sql,/\b(?:INSERT\s+INTO|UPDATE\s+atlas\.|DELETE\s+FROM|CREATE\s+TABLE|DROP\s+TABLE)\b/i);
  assert.match(sql,/SELECT jsonb_build_object/);
});
for(const kind of ['completed','partial','blocked']){
  test('modeled '+kind+' qualified Result passes independent no-successor comparator',()=>{
    const b=before(),a=after(b,kind);
    const rp={...a,phase:'replay'};
    const result=runCompare(b,a,kind,rp);
    assert.equal(result.status,0,(result.stderr||'').slice(0,1400));
    assert.match(result.stdout,/UNI_OPS_P3_SIGNED_RESULT_SNAPSHOT_COUNTS=PASS/);
  });
}
test('new original or legacy released/eligible carrier fails despite genuine Result',()=>{
  const b=before(),a=after(b,'completed');
  const bad=[
    {...a,workTotal:a.workTotal+1},
    {...a,legacyReleasedTaskIds:['fictional-task']},
    {...a,eligibleOrReleasedOccurrenceIds:['fictional-occurrence']},
    {...a,releasedOccurrenceIds:['fictional-occurrence']},
    {...a,governedOfferTotal:a.governedOfferTotal+1},
    {...a,workPlanTotal:a.workPlanTotal+1},
    {...a,principalObligationTotal:a.principalObligationTotal+1},
  ];
  for(const changed of bad){
    const r=runCompare(b,changed,'completed');
    assert.notEqual(r.status,0,'unauthorized successor escaped: '+JSON.stringify(changed));
  }
});
test('falsified Result, campaign uncertainty, or non-idempotent replay fail closed',()=>{
  const b=before(),a=after(b,'completed');
  const denied=[
    {...a,originalAcceptanceTotal:0},
    {...a,physicalCareObservationTotal:0},
    {...a,campaignTableAbsent:false},
    {...a,campaignOfferTableAbsent:false},
    {...a,validExactOriginal:false},
    {...a,originalWorkState:'open'},
    {...a,qualifyingSatisfactionId:null},
  ];
  for(const changed of denied)assert.notEqual(runCompare(b,changed,'completed').status,0);
  assert.notEqual(runCompare(b,a,'completed',{...a,phase:'replay',workResultTotal:2}).status,0);
});
test('nonterminal Full/Blocked cannot pretend to close original Work',()=>{
  const b=before();
  assert.notEqual(runCompare(b,{...after(b,'partial'),originalWorkState:'completed'},'partial').status,0);
  assert.notEqual(runCompare(b,{...after(b,'blocked'),satisfactionTotal:1},'blocked').status,0);
});


test('disposable 18-stage U4 scratch gains exactly eight source-pinned P3 stages',()=>{
  const root=mkdtempSync(join(tmpdir(),'uniops-p3-assembly-'));
  try {
    const oldSql=join(root,'UNI_OPS_U4_DISPOSABLE_ONLY.sql');
    const out=join(root,'UNI_OPS_P3_6A_SYNTHETIC_TEST_ONLY.sql');
    const stage=Array.from({length:18},(_,i)=>
      '-- BEGIN PINNED STAGE fictional_'+(i+1)+'\\n-- END PINNED STAGE fictional_'+(i+1)+'\\n').join('');
    const input=stage+'-- BEGIN U4 DISPOSABLE PUBLIC TRANSPORT SOURCE BLOB:3e09b66e54c15e100110c2b50f43dc9c7593e51a\\n';
    writeFileSync(oldSql,input);
    const digest=createHash('sha256').update(input).digest('hex');
    const assembler=new URL('22_compose_mowing_6a_scratch_held.mjs',base);
    const cmd=(sha,target)=>spawnSync(process.execPath,[assembler.pathname,oldSql,sha,target],
      {encoding:'utf8',timeout:12000});
    const first=cmd(digest,out);
    assert.equal(first.status,0,(first.stderr||'').slice(0,1200));
    assert.match(first.stdout,/P3_6A_SOURCE_STAGE_COUNT=8/);
    const combined=readFileSync(out,'utf8');
    assert.equal((combined.match(/-- BEGIN PINNED STAGE /g)||[]).length,18);
    assert.equal((combined.match(/-- BEGIN PINNED P3 6A HELD STAGE /g)||[]).length,8);
    assert.match(combined,/P3 evaluator source fingerprint drift; stop/);
    assert.match(combined,/CORE_MOWING_P3_STRUCTURE=PASS/);
    assert.notEqual(cmd(digest,out).status,0,'existing output must never be overwritten');
    assert.notEqual(cmd('0'.repeat(64),
      join(root,'UNI_OPS_P3_6A_FORGED_TEST_ONLY.sql')).status,0,
      'forged U4 input hash must be denied');
    const missing=join(root,'UNI_OPS_BAD_DISPOSABLE_ONLY.sql');
    writeFileSync(missing,stage);
    const missingDigest=createHash('sha256').update(stage).digest('hex');
    const rejected=spawnSync(process.execPath,[assembler.pathname,missing,missingDigest,
      join(root,'UNI_OPS_P3_6A_MISSING_TEST_ONLY.sql')],{encoding:'utf8',timeout:12000});
    assert.notEqual(rejected.status,0,'U4 signed transport provenance must be present');
  }finally{rmSync(root,{recursive:true,force:true});}
});
