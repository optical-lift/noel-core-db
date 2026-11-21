// SOURCE-CUSTODY ONLY; no live SQL, migration generation, release or credentials.
// Every body in candidate.sql must match the pinned owner SQL bytes exactly.
import {readFileSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';

const HERE=dirname(fileURLToPath(import.meta.url));
const NATIVE=resolve(HERE,'../atlas_native_person_completion_only_v1');
const ORIGINAL=resolve(HERE,'source_snapshot');
export const INPUTS=Object.freeze([
  {name:'01_current_native_person_lifecycle_source',path:resolve(NATIVE,'01_shadow_event_native_person_completion_only_held.sql'),git:'62e114eb2c2371450cca1a1ca851a9f2518b75f7'},
  {name:'02_baseline_and_shadow_observers',path:resolve(ORIGINAL,'02_baseline_and_shadow_observers.sql'),git:'0ca69e0a604f43cf3eee442cb1edeb4ae6c1672b'},
  {name:'03_shadow_projection_and_observers',path:resolve(ORIGINAL,'03_shadow_projection_and_observers.sql'),git:'4113d95c1d8ae3b1161ca5a43e344100b6120c1b'},
  {name:'04_current_native_person_single_done',path:resolve(NATIVE,'06_single_transition_native_person_completion_only_held.sql'),git:'3178e11863f1c6de89e07724c3b209923fd825d3'},
  {name:'05_existing_connected_person_result_writer_cutover',path:resolve(ORIGINAL,'10_connected_person_result_writer_single_done_receipt_compat_held.sql'),git:'8ef030b100e983f36fb7c59217a193876527a720'},
  {name:'06_disable_legacy_self_adopted_writer',path:resolve(ORIGINAL,'12_self_adopted_original_writer_single_done_cutover_candidate.sql'),git:'e6f6dd4367ad84b57ff0fb65915a9b8785e941b7'},
  {name:'07_existing_event_shared_writer_cutover',path:resolve(ORIGINAL,'14_event_shared_original_writer_single_done_cutover_candidate.sql'),git:'8f24ee85ffa841b8d1ab91da2289365d1713bec3'}
]);
const HEADER="BEGIN;\n-- HELD ATLAS NATIVE PERSON COMPLETION RELEASE SOURCE PACKET (UNVERSIONED).\n-- Source-only candidate; NOT an executable migration or production approval.\n-- Release target: existing Atlas original Work lifecycle only.\n-- Historical review/cancellation and standing farm-care/P1 bridge are excluded.\nSET LOCAL statement_timeout='75s';\n\n";
const BASELINE="-- Preserve old state as un-attributed historical observations, never fabricating Done.\n-- Lock original writers before one-time source baseline; then install observers.\nLOCK TABLE atlas.work_items,atlas.work_allocations,\n atlas.work_execution_results,atlas.work_result_acceptances,\n atlas.work_execution_plan_events IN SHARE ROW EXCLUSIVE MODE;\nSELECT atlas.seed_work_lifecycle_shadow_baseline_internal_v1();\n\n";
const TAIL="-- Public RPC signatures remain unchanged; no new client or role EXECUTE.\nCOMMIT;\n";
export const CANDIDATE_GIT_BLOB='2ee49072aee9e6d7ab9180c21ce8463f7e713994';
export function gitBlob(s){
  return createHash('sha1').update('blob '+Buffer.byteLength(s)+'\0').update(s).digest('hex');
}
export function assertSame(ok,why){if(!ok)throw Error('STOP held migration packet custody mismatch: '+why);}
export function buildReleasePacket(sourceTexts){
  assertSame(sourceTexts.length===INPUTS.length,'source count');
  let sql=HEADER;
  for(let k=0;k<INPUTS.length;k++){
    const p=INPUTS[k],s=sourceTexts[k];
    assertSame(typeof s==='string' && gitBlob(s)===p.git,p.name+' immutable source blob');
    sql+='-- EXACT HELD SOURCE: '+p.name+'; Git blob '+p.git+'\n'+s.trimEnd()+'\n\n';
    if(k===1)sql+=BASELINE;
  }
  return sql+TAIL;
}
export function assertSourceSecurity(sql){
  assertSame(sql.startsWith(HEADER)&&sql.endsWith(TAIL),'atomic transaction/header');
  assertSame(gitBlob(sql)===CANDIDATE_GIT_BLOB,'assembled candidate.sql exact blob');
  assertSame(sql.match(/CREATE TABLE atlas[.]work_lifecycle_events_v1 \(/g)?.length===1,'one immutable lifecycle stream');
  assertSame(sql.match(/CREATE OR REPLACE FUNCTION atlas[.]apply_work_lifecycle_transition_internal_v1\(/g)?.length===1,'one private Done authority');
  assertSame(sql.includes("p_transition_kind IS DISTINCT FROM 'complete'"),'only complete admitted');
  for(const need of [
    'Historical self-adopted responsibility requires native reconciliation',
    'Current native responsible Person required',
    'Existing accepted source evidence required',
    'source_qualified_physical_actual',
    'work_lifecycle_event_append_only_v1',
    'work_lifecycle_event_no_truncate_v1',
    'ENABLE ROW LEVEL SECURITY',
    'FORCE ROW LEVEL SECURITY',
    'REVOKE ALL ON FUNCTION atlas.apply_work_lifecycle_transition_internal_v1(',
    'SELECT atlas.seed_work_lifecycle_shadow_baseline_internal_v1();',
    'mark_ledger_occurrence_shared_work_done_self_api_v1',
    'report_connected_person_company_work_internal_v1',
    'report_self_responsible_company_work_self_api_v1',
    'Current native responsible Person required',
    "'contractVersion','connected_person_company_work_result_v1'",
    "'resultId',v_result.id",
    "'resultKind','completed'",
    "'oneLifecycleDone',v_universal_receipt",
    "'historicalRecordedCompletion',true",
    "'newTransitionApplied',false"
  ])assertSame(sql.includes(need),'missing '+need);
  for(const forbidden of [
    'CLONE TEST ONLY','e5200000','current_database()',
    'historical_self_adoption_review_events_v1',
    'governor_retire_historical_work_self_api_v1',
    "IF p_transition_kind='cancel' THEN",
    "SET work_state='cancelled'",
    'INSERT INTO auth.users','INSERT INTO atlas.rhythm_rules',
    'INSERT INTO atlas.weed_cards','recognize_assigned_care_activity_self_api_v1',
    'admit_standing_continuing_source_work_self_api_v1',
    'CREATE OR REPLACE FUNCTION public.',
    'GRANT EXECUTE ON FUNCTION public.',
    'supabase_migrations','schema_migrations','service_role_key',
    'pg_notify('
  ])assertSame(!sql.includes(forbidden),'forbidden '+forbidden);
  assertSame(sql.match(/CREATE OR REPLACE FUNCTION atlas[.](?:report_connected_person_company_work_internal_v1|mark_ledger_occurrence_shared_work_done_self_api_v1|report_self_responsible_company_work_self_api_v1)\(/g)?.length===3,'exact three preexisting writer cutovers');
  const seed=sql.indexOf('SELECT atlas.seed_work_lifecycle_shadow_baseline_internal_v1();');
  const observer=sql.indexOf('CREATE TRIGGER work_items_shadow_lifecycle_insert_v1');
  const transition=sql.indexOf('CREATE OR REPLACE FUNCTION atlas.apply_work_lifecycle_transition_internal_v1(');
  const writer=sql.indexOf('CREATE OR REPLACE FUNCTION atlas.report_connected_person_company_work_internal_v1(');
  assertSame(seed>0 && observer>seed && transition>observer && writer>transition,'baseline/observer/transition/writer ordering');
}
export function verifyFromRepository(){
  const parts=INPUTS.map(x=>readFileSync(x.path,'utf8'));
  const expected=buildReleasePacket(parts);
  const committed=readFileSync(resolve(HERE,'candidate.sql'),'utf8');
  assertSame(committed===expected,'candidate.sql differs from exact sources');
  assertSourceSecurity(committed);
  return {gitBlob:gitBlob(committed),sha256:createHash('sha256').update(committed).digest('hex'),bytes:Buffer.byteLength(committed)};
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  if(process.argv.slice(2).length!==1||process.argv[2]!=='--check')throw Error('Usage: node verify_release_packet.mjs --check');
  const result=verifyFromRepository();
  process.stdout.write('PASS held native-only release packet exact sources, privacy & historical exclusion '+JSON.stringify(result)+'\n');
}
