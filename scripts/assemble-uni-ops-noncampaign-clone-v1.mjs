// UNI-OPS-01 2026-11-06 integrated NONRELEASABLE synthetic clone source.
// Byte-pinned from separately reviewed Noel held candidates. Does not contact
// GitHub, Supabase, REST, a person, or a production database.
// Usage: node scripts/assemble-uni-ops-noncampaign-clone-v1.mjs
//   <exact P1 signed composite.sql> <exact #2522 completion packet.sql>
//   <path to EXISTING expected held_combined.sql>
// Verifies and compares; NEVER writes a migration or a SQL file.
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const pinned={
  old:'a59bd0053b68629bf8a31b8eda2f5d072e2b890e',
  completion:'0e7c8581e6656b218bdc1ff2c13152201e3e03f5',
  combined:'fde5a93111e3ba46c217c2d3baf29619fd463b0f'
};
const gitBlob=s=>createHash('sha1').update(
  'blob '+Buffer.byteLength(s)+'\0').update(s).digest('hex');
const check=(truth,msg)=>{if(!truth)throw Error('STOP UNI-OPS clone custody: '+msg)};
check(process.argv.length===5,'exactly three local file paths required');
const old=readFileSync(process.argv[2],'utf8');
const next=readFileSync(process.argv[3],'utf8');
const actual=readFileSync(process.argv[4],'utf8');
check(gitBlob(old)===pinned.old,'P1 old source blob');
check(gitBlob(next)===pinned.completion,'native completion source blob');
const a='-- EXACT ONE LIFECYCLE SHADOW';
const b='-- EXACT CONTINUING WORK SOURCE';
const x=old.indexOf(a),y=old.indexOf(b);
check(x>=0&&y>x&&old.indexOf(a,x+1)===-1&&old.indexOf(b,y+1)===-1,
      'old lifecycle and C1 boundaries are not unique');
const begin='BEGIN;\n';
const end='-- Public RPC signatures remain unchanged; no new client or role EXECUTE.\nCOMMIT;\n';
check(next.startsWith(begin)&&next.endsWith(end)&&
      old.startsWith('BEGIN;\n-- CLONE TEST ONLY')&&
      old.endsWith('\nCOMMIT;\n'),'transaction and clone-only custody');
const source=next.slice(begin.length,next.length-end.length);
const composed=old.slice(0,x)+
'-- HELD COMBINED CLONE ONLY / 2026-11-06\n'+
'-- Source: exact #2522 native completion packet SHA-1 0e7c8581e6656b218bdc1ff2c13152201e3e03f5\n'+
'-- NOTE: earlier lifecycle block is replaced in this disposable test only.\n'+
'-- DO NOT GENERATE MIGRATION, DEPLOY OR EXECUTE OUTSIDE SYNTHETIC LOCAL CLONE.\n'+
source+'\n-- END locked native-completion source, start existing exact held care/P1 source\n'+
old.slice(y);
const count=pattern=>(composed.match(pattern)||[]).length;
check(count(/^BEGIN;$/gm)===1&&count(/^COMMIT;$/gm)===1,
     'one exact enclosing transaction');
check(count(/CREATE TABLE atlas\.work_lifecycle_events_v1 \(/g)===1&&
      count(/CREATE OR REPLACE FUNCTION atlas\.apply_work_lifecycle_transition_internal_v1\(/g)===1,
      'one lifecycle, one private Done');
check(count(/CREATE FUNCTION atlas\.recognize_assigned_care_activity_self_api_v1\(/g)===1&&
      count(/CREATE OR REPLACE FUNCTION atlas\.record_continuing_care_actual_self_api_v1\(/g)===2,
      'one P1 recognizer and final source-qualified C1 care replacement');
check(composed.includes("p_transition_kind IS DISTINCT FROM 'complete'")&&
      composed.includes('Current native responsible Person required')&&
      composed.includes('source_qualified_physical_actual')&&
      composed.includes('Campaign-linked Actual requires no-successor source cutover')&&
      composed.includes('CLONE TEST ONLY')&&
      composed.includes("current_database()<>'postgres'")&&
      !composed.includes("IF p_transition_kind='cancel' THEN")&&
      !composed.includes('historical_self_adoption_review_events_v1'),
      'no historical cancel, campaign bypass or missing clone guard');
check(composed===actual,'committed expected source does not exactly match');
check(gitBlob(composed)===pinned.combined,'expected combined Git blob changed');
process.stdout.write('PASS byte-exact synthetic-only composite '+JSON.stringify({
  gitBlob:pinned.combined,bytes:Buffer.byteLength(composed),
  original:pinned.old,nativeCompletion:pinned.completion,
  statements:'one transaction / one native lifecycle / one P1 care recognizer',
  scope:'noncampaign assigned original only',
  historicalCancellation:'HELD',campaignP1:'EXPECTED SOURCE DENIAL',
  production:'NOT AUTHORIZED'
})+'\n');
