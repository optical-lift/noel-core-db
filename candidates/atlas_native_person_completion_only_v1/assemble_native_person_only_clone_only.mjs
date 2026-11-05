// HELD SOURCE-LAW SPLIT ONLY. Not a migration or production-release authority.
// Exact current #2368 L1/L2 is the parent: only historical source admission and
// the reviewed cancellation operation are excluded. Person-native completion,
// signed accepted Result, one event and the anti-legacy guard remain unchanged.
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {INPUTS,GIT_SHA,gitBlobSha} from '../atlas_actual_first_p1_assigned_care_activity_v1/assemble_current_l1_l2_clone_only.mjs';

const HERE=dirname(fileURLToPath(import.meta.url));
const TEST_NAME='L1_L2_NATIVE_PERSON_ONLY_CLONE_ONLY.sql';
const CLONE_GUARD='-- CLONE TEST ONLY: this candidate is NEVER production-releasable.';
const L1_START='CREATE TABLE atlas.work_lifecycle_events_v1 (';
const L1_FOOT='REVOKE ALL ON FUNCTION atlas.append_work_lifecycle_observation_internal_v1(';
const L2_START='ALTER TABLE atlas.work_lifecycle_events_v1\n DROP CONSTRAINT work_lifecycle_events_v1_event_kind_check;';
const L2_FOOT='REVOKE ALL ON FUNCTION atlas.apply_work_lifecycle_transition_internal_v1(';
const REVOKE_END='FROM PUBLIC,anon,authenticated,service_role;';
const L1_OLD="   'atlas.work_execution_plan_events',\n   'atlas.historical_self_adoption_review_events_v1'";
const L1_NEW="   'atlas.work_execution_plan_events'";
const L2_OLD="OR p_transition_kind NOT IN ('complete','cancel')";
const L2_NEW="OR p_transition_kind IS DISTINCT FROM 'complete'";
const HISTORY_START=' -- The only cancellation admitted in this draft';
const HISTORY_END=' v_shared_event:=';
const REPLACEMENT=` -- SOURCE-LAW RELEASE SCOPE 2026-11-05: completion ONLY.
 -- Governor-reviewed historical cancellation is not admitted in this cutover.
 -- Historical review/retirement remains on separately held #2368 source.
 -- Never restore self-adopted membership as current Done authority.
`;
export const NATIVE_SHA=Object.freeze({
  l1:'62e114eb2c2371450cca1a1ca851a9f2518b75f7',
  l2:'3178e11863f1c6de89e07724c3b209923fd825d3'
});
export const SOURCE_PATHS=Object.freeze({
  base:resolve(HERE,INPUTS.base),
  originalL1:resolve(HERE,INPUTS.shadow),
  originalL2:resolve(HERE,INPUTS.transition),
  l1:resolve(HERE,'01_shadow_event_native_person_completion_only_held.sql'),
  l2:resolve(HERE,'06_single_transition_native_person_completion_only_held.sql')
});
function fail(ok,why){if(!ok)throw new Error('STOP completion-only source drift: '+why);}
function once(s,needle,why){
  const at=s.indexOf(needle);
  fail(at>=0 && s.indexOf(needle,at+needle.length)<0,why+' is not unique');
  return at;
}
function block(s,start,footer,why){
  const a=once(s,start,why+' start'), b=once(s,footer,why+' footer');
  fail(b>a,why+' footer precedes start');
  const e=s.indexOf(REVOKE_END,b);
  fail(e>b,why+' missing final privilege revoke');
  return s.slice(a,e+REVOKE_END.length);
}
export function deriveNativeOnlyL1(current) {
  once(current,L1_OLD,'historical source allowlist');
  return current.replace(L1_OLD,L1_NEW);
}
export function deriveNativeOnlyL2(current) {
  once(current,L2_OLD,'current dual-kind admission');
  current=current.replace(L2_OLD,L2_NEW);
  const start=once(current,HISTORY_START,'historical branch beginning');
  const end=once(current,HISTORY_END,'native completion continuation');
  const removed=current.slice(start,end);
  fail(end>start && removed.length>7000 && removed.length<18000
      && removed.includes("IF p_transition_kind='cancel' THEN")
      && removed.includes("SET work_state='cancelled'"),
      'history branch changed or includes unrelated completion');
  return current.slice(0,start)+REPLACEMENT+current.slice(end);
}
export function assembleNativePersonOnly(inputs){
  for(const [k,pin] of Object.entries({
    base:GIT_SHA.base,originalL1:GIT_SHA.shadow,originalL2:GIT_SHA.transition,
    l1:NATIVE_SHA.l1,l2:NATIVE_SHA.l2
  })){
    fail(typeof inputs[k]==='string' && gitBlobSha(inputs[k])===pin,k+' immutable Git blob changed');
  }
  const {base,originalL1,originalL2,l1,l2}=inputs;
  fail(l1===deriveNativeOnlyL1(originalL1),'L1 is not the exact no-history derivative');
  fail(l2===deriveNativeOnlyL2(originalL2),'L2 is not exact native-only derivative');
  fail(base.startsWith('BEGIN;\n'+CLONE_GUARD),'fictional canary boundary lost');
  for(const x of ["id='e5200000-0000-4000-8000-000000000001'::uuid",
                  "id='e5200000-0000-4000-8000-000000000b03'::uuid",
                  "current_database()<>'postgres'"]) {
    fail(base.includes(x),'P1 fictional-clone canary changed: '+x);
  }
  const oldL1=block(base,L1_START,L1_FOOT,'original signed P1 L1');
  const oldL2=block(base,L2_START,L2_FOOT,'original signed P1 L2');
  const newL1=block(l1,L1_START,L1_FOOT,'native completion L1');
  const newL2=block(l2,L2_START,L2_FOOT,'native completion L2');
  fail(oldL2.includes("p_transition_kind IS DISTINCT FROM 'complete'"),
    'base P1 single-kind admission drift');
  fail(newL2.includes("p_transition_kind IS DISTINCT FROM 'complete'")
    && newL2.includes('Historical self-adopted responsibility requires native reconciliation')
    && newL2.includes('Current native responsible Person required'),
    'native-current-Person completion guard weakened');
  const marker='-- DERIVED HELD DIAGNOSTIC: current Person-native completion ONLY; no history retirement.\n'
   +'-- Retained #2368 historical cancellation is NOT approved for this release.\n';
  let assembled=base.replace(oldL1,newL1).replace(oldL2,newL2);
  assembled=assembled.replace(CLONE_GUARD,CLONE_GUARD+'\n'+marker.trimEnd());
  fail(assembled.startsWith('BEGIN;\n'+CLONE_GUARD)
    && assembled.endsWith('\nCOMMIT;\n'),
    'test-only transaction boundary changed');
  fail(!assembled.includes('atlas.historical_self_adoption_review_events_v1')
    && !assembled.includes("IF p_transition_kind='cancel' THEN")
    && !assembled.includes('governor_retire_historical_work_self_api_v1(')
    && !assembled.includes('governor_historical_retirement_preflight_self_api_v1(')
    && !assembled.includes("SET work_state='cancelled'")
    && !assembled.includes('CREATE TABLE atlas.historical_self_adoption_review_events_v1'),
    'historical source or cancellation leaked into the completion-only candidate');
  fail((assembled.match(/CREATE TABLE atlas.work_lifecycle_events_v1 \(/g)||[]).length===1
    && (assembled.match(/CREATE OR REPLACE FUNCTION atlas.apply_work_lifecycle_transition_internal_v1\(/g)||[]).length===1
    && assembled.includes('REVOKE ALL ON FUNCTION atlas.apply_work_lifecycle_transition_internal_v1('),
    'second writer, missing private lifecycle or missing EXECUTE deny');
  fail(assembled.includes(newL1) && assembled.includes(newL2),
    'native-only source substitution failed');
  return {sql:assembled,sha256:createHash('sha256').update(assembled).digest('hex')};
}
export function assembleFromRepo(){
  const inputs=Object.fromEntries(Object.entries(SOURCE_PATHS).map(([k,p])=>[k,readFileSync(p,'utf8')]));
  return assembleNativePersonOnly(inputs);
}
const main=process.argv[1] && resolve(process.argv[1])===fileURLToPath(import.meta.url);
if(main){
  const {sql,sha256}=assembleFromRepo();
  const args=process.argv.slice(2);
  if(args.length===1 && args[0]==='--check'){
    process.stdout.write('PASS held Person-only L1/L2 source identity, no historical-cancel code, sha256 '+sha256+'\n');
  } else if(args.length===2 && args[0]==='--output' && args[1]==='/tmp/'+TEST_NAME){
    writeFileSync(args[1],sql,{encoding:'utf8',mode:0o600,flag:'w'});
    process.stdout.write('CLONE-ONLY assembled '+TEST_NAME+' sha256 '+sha256+'\n');
  } else {
    throw new Error('Usage: node assemble_native_person_only_clone_only.mjs --check | --output /tmp/'+TEST_NAME);
  }
}
