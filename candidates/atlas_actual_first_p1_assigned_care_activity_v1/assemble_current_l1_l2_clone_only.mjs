// HELD DIAGNOSTIC ONLY. This is NOT a migration, release permission or
// source-of-truth fork of Noel #2368. Source snapshots retain exact Git blobs.
// The assembly preserves the existing synthetic C1 clone-only canary.
import {readFileSync, writeFileSync} from 'node:fs';
import {basename, dirname, resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';

export const INPUTS=Object.freeze({
  base:'../../candidates/atlas/20261028235811_atlas_care_single_done_signed_proof_v1.sql',
  shadow:'./l1_l2_current_source_snapshot/01_shadow_event_source.sql',
  transition:'./l1_l2_current_source_snapshot/06_single_transition_authority_private.sql',
  history:'./l1_l2_current_source_snapshot/16_historical_self_adoption_review_candidate.sql'
});
export const GIT_SHA=Object.freeze({
  base:'a59bd0053b68629bf8a31b8eda2f5d072e2b890e',
  shadow:'1190b2d188846e48252da33be70ea35e9cd56efc',
  transition:'a6947ae7d5c5d31a75740c2cd2672e9832a7fee8',
  history:'2bccffbaee2de725f511ca5a67145ae72f7980c3'
});
const L1_START='CREATE TABLE atlas.work_lifecycle_events_v1 (';
const L1_FOOT='REVOKE ALL ON FUNCTION atlas.append_work_lifecycle_observation_internal_v1(';
const L2_START='ALTER TABLE atlas.work_lifecycle_events_v1\n DROP CONSTRAINT work_lifecycle_events_v1_event_kind_check;';
const L2_FOOT='REVOKE ALL ON FUNCTION atlas.apply_work_lifecycle_transition_internal_v1(';
const REVOKE_END='FROM PUBLIC,anon,authenticated,service_role;';
const L2_COMMENT='-- GATE 2 PREVIEW ONLY. Not an independent Done API.';
const CLONE_GUARD='-- CLONE TEST ONLY: this candidate is NEVER production-releasable.';
const OUTPUT_NAME='L1_L2_CURRENT_HISTORY_CLONE_ONLY.sql';
export function gitBlobSha(content) {
  const bytes=Buffer.byteLength(content,'utf8');
  return createHash('sha1').update('blob '+bytes+'\0').update(content).digest('hex');
}
function assertSource(ok,label){if(!ok)throw new Error('STOP clone source mismatch: '+label);}
function exactlyOnce(s,token,label){
  const at=s.indexOf(token);
  assertSource(at>=0 && s.indexOf(token,at+token.length)<0,label+' not exactly once');
  return at;
}
function sqlBlock(content,start,footer,label){
  const a=exactlyOnce(content,start,label+' start');
  const foot=exactlyOnce(content,footer,label+' footer');
  assertSource(foot>a,label+' footer precedes body');
  const end=content.indexOf(REVOKE_END,foot);
  assertSource(end>=foot,label+' revoke missing');
  return content.slice(a,end+REVOKE_END.length);
}
export function assembleHeldCurrentLifecycle({base,shadow,transition,history}){
  const inputs={base,shadow,transition,history};
  for(const [name,src] of Object.entries(inputs)){
    assertSource(typeof src==='string' && gitBlobSha(src)===GIT_SHA[name],
      name+' exact Git blob changed');
  }
  assertSource(base.startsWith('BEGIN;\n'+CLONE_GUARD),'original fictional canary removed');
  assertSource(base.includes("id='e5200000-0000-4000-8000-000000000001'::uuid")
    && base.includes("id='e5200000-0000-4000-8000-000000000b03'::uuid")
    && base.includes("current_database()<>'postgres'"),'fictional clone-only canary changed');
  const oldL1=sqlBlock(base,L1_START,L1_FOOT,'signed L1');
  const newL1=sqlBlock(shadow,L1_START,L1_FOOT,'current L1');
  const oldL2=sqlBlock(base,L2_START,L2_FOOT,'signed L2');
  const newL2=sqlBlock(transition,L2_START,L2_FOOT,'current L2');
  assertSource(!oldL1.includes('atlas.historical_self_adoption_review_events_v1')
    && newL1.includes('atlas.historical_self_adoption_review_events_v1'),
    'historical event provenance not version-distinct');
  assertSource(oldL2.includes("p_transition_kind IS DISTINCT FROM 'complete'")
    && newL2.includes("p_transition_kind NOT IN ('complete','cancel')")
    && newL2.includes('Historical self-adopted responsibility requires native reconciliation'),
    'current signed Done is not correctly distinct from older acceptance');
  assertSource(history.includes('CREATE TABLE atlas.historical_self_adoption_review_events_v1(')
    && history.includes('FORCE ROW LEVEL SECURITY')
    && history.includes('CREATE TRIGGER reject_historical_review_mutation_v1'),
    'current historical source immutable/RLS table missing');
  exactlyOnce(base,L2_COMMENT,'L2 insertion point');
  const insertion=[
    '-- SOURCE SNAPSHOT ONLY: latest held #2368 immutable historical review source;',
    '-- it is not a new consent/Work permission or approved historical-cancel release.',
    history.trimEnd(),
    '',
    '-- NEXT: unchanged #2368 current L2 complete/cancel authority, held.',
    ''
  ].join('\n');
  const marker='-- DERIVED DIAGNOSTIC: full current #2368 L1/L2+historical review; NOT releasable.\n'
    +'-- The existing P1 signed proof is for the prior lifecycle bytes only.\n';
  let assembled=base.replace(oldL1,newL1).replace(oldL2,newL2)
      .replace(L2_COMMENT,insertion+L2_COMMENT);
  assembled=assembled.replace(CLONE_GUARD,CLONE_GUARD+'\n'+marker.trimEnd());
  assertSource(assembled!==base && assembled.startsWith('BEGIN;\n'+CLONE_GUARD),
    'derived clone guard lost');
  assertSource(assembled.includes(newL1) && assembled.includes(newL2)
    && assembled.includes(history.trimEnd()),'current source payload incomplete');
  assertSource(assembled.indexOf('CREATE TABLE atlas.historical_self_adoption_review_events_v1(')
    >assembled.indexOf('CREATE TABLE atlas.work_lifecycle_events_v1 (')
    && assembled.indexOf('CREATE TABLE atlas.historical_self_adoption_review_events_v1(')
    <assembled.indexOf('CREATE OR REPLACE FUNCTION atlas.apply_work_lifecycle_transition_internal_v1('),
    'history must be instantiated before Done transition');
  assertSource(assembled.endsWith('\nCOMMIT;\n'),'clone transaction boundary changed');
  assertSource(assembled.match(/CREATE TABLE atlas.work_lifecycle_events_v1 \(/g)?.length===1
    && assembled.match(/CREATE TABLE atlas.historical_self_adoption_review_events_v1\(/g)?.length===1
    && assembled.match(/CREATE OR REPLACE FUNCTION atlas.apply_work_lifecycle_transition_internal_v1\(/g)?.length===1,
    'duplicate lifecycle source authority');
  return {sql:assembled,sha256:createHash('sha256').update(assembled).digest('hex'),
    provenance:{...GIT_SHA},outputName:OUTPUT_NAME};
}
export function assembleFromRepo(){
  const inputs=Object.fromEntries(Object.entries(INPUTS).map(([key,path])=>
    [key,readFileSync(new URL(path,import.meta.url),'utf8')]));
  return assembleHeldCurrentLifecycle(inputs);
}
if(process.argv[1] && resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  const args=process.argv.slice(2);
  if(args.length===0||args[0]==='--check'){
    assertSource(args.length<=1,'unexpected arguments');
    const result=assembleFromRepo();
    process.stdout.write('PASS held clone composition only; latest #2368 L1/L2/history '
      +result.sha256+'; SQL is NOT signed-tested or production eligible\n');
  }else if(args[0]==='--output' && args.length===2){
    const target=resolve(args[1]);
    assertSource(basename(target)===OUTPUT_NAME && dirname(target)===tmpdir(),
      'output must be an exact nonmigration file in local temporary directory');
    const result=assembleFromRepo();
    writeFileSync(target,result.sql,{flag:'wx',mode:0o600});
    process.stdout.write('Wrote disposable test-only candidate to '+target
      +' SHA256 '+result.sha256+'; DO NOT apply to production\n');
  }else{
    throw new Error('Usage: node assemble_current_l1_l2_clone_only.mjs [--check | --output '
      +tmpdir()+'/'+OUTPUT_NAME+']');
  }
}
