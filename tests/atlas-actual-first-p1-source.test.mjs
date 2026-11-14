// UNI-OPS-01 Actual-first P1 SOURCE-ONLY guards. These are NOT PG/signed tests.
import './atlas-c1-source-custody-split.test.mjs';
import test from 'node:test';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const folder='../candidates/atlas_actual_first_p1_assigned_care_activity_v1/';
const sql=readFileSync(new URL(folder+'01_assigned_activity_recognition_held.sql',import.meta.url),'utf8');
const post=readFileSync(new URL(folder+'02_rollback_postconditions_held.sql',import.meta.url),'utf8');
const sh=readFileSync(new URL(folder+'03_local_rollback_source_check.sh',import.meta.url),'utf8');
const executable=sql.split('\n').filter(line=>!line.trimStart().startsWith('--')).join('\n');

test('activity evidence is pre-existing, worker-authored and unretracted',()=>{
  assert.match(sql,/v_activity.source<>'worker_manual_log'/);
  assert.match(sql,/v_activity.retracted_at IS NOT NULL/);
  assert.match(sql,/v_activity.actor_user_id IS DISTINCT FROM v_uid/);
});
test('signed current canonical Person is mandatory',()=>{
  assert.match(sql,/v_uid uuid:=auth.uid\(\)/);
  assert.match(sql,/v_person uuid:=atlas.current_person_id_v1\(\)/);
  assert.match(sql,/v_activity.actor_membership_id/);
});
test('only one known original and its live Subject link',()=>{
  assert.match(sql,/v_work.source_object_type<>'rhythm_state'/);
  assert.match(sql,/v_work.result_contract_key<>'continuing_care_actual_v1'/);
  assert.match(sql,/farm_id=v_activity.farm_id/);
  assert.match(sql,/l.relation_kind='acts_on'/);
});
test('exact assigned performer, not generic standing worker scope',()=>{
  assert.match(sql,/a.assignee_canonical_person_id=v_person/);
  assert.match(sql,/a.allocation_role='responsible'/);
});
test('original and assignment precede the report',()=>{
  assert.match(sql,/v_work.created_at>v_activity.created_at/);
  assert.match(sql,/v_allocation.allocated_at>v_activity.created_at/);
});
test('one piece of activity evidence cannot be reinterpreted against another Work',()=>{
  assert.match(sql,/activity_log_id uuid NOT NULL UNIQUE/);
  assert.match(sql,/execution_result_id uuid NOT NULL UNIQUE/);
  assert.match(sql,/WHERE activity_log_id=v_activity.id FOR UPDATE/);
  assert.match(sql,/23505/);
});
test('typed Actual is explicit, never silently extracted from free text',()=>{
  assert.match(sql,/v_kind text:=nullif/);
  assert.match(sql,/v_after text:=nullif/);
  assert.match(sql,/v_work.id,v_activity.id,v_kind,v_after/);
});
test('native care actual and accepted result are independently checked',()=>{
  assert.match(sql,/atlas.record_continuing_care_actual_self_api_v1/);
  assert.match(sql,/atlas.work_execution_results/);
  assert.match(sql,/a.acceptance_kind='source_qualified_physical_actual'/);
});
test('no retrospective original creation, Work creation or responsibility creation',()=>{
  assert.doesNotMatch(executable,/\bINSERT\s+INTO\s+atlas.work_items\b/i);
  assert.doesNotMatch(executable,/\bUPDATE\s+atlas.work_items\b/i);
  assert.doesNotMatch(executable,/\bINSERT\s+INTO\s+atlas.work_allocations\b/i);
  assert.match(sql,/'retrospectiveOriginalCreated',false/);
});
test('old standing campaign successor path is blocked',()=>{
  assert.match(sql,/v_work.metadata \? 'sourceStandingCampaignId'/);
  assert.match(sql,/requires no-successor source cutover/);
  assert.doesNotMatch(executable,/advance_owner_standing_campaign_after_actual_internal_v1\s*\(/);
});
test('receipt requires zero new Work and no Clock admission',()=>{
  assert.match(sql,/v_receipt->>'noNewWorkCreated' IS DISTINCT FROM 'true'/);
  assert.match(sql,/v_receipt->>'noClockAdmission' IS DISTINCT FROM 'true'/);
  assert.match(sql,/'nextCampaignAuthorized',false/);
});
test('no second Activity, Work or Actual store — only immutable private link',()=>{
  assert.match(sql,/CREATE TABLE atlas.assigned_care_activity_recognition_links_v1/);
  assert.match(sql,/ENABLE ROW LEVEL SECURITY/);
  assert.match(sql,/BEFORE UPDATE OR DELETE/);
});
test('RPC is signed authenticated only; private data grants revoked',()=>{
  assert.match(sql,/REVOKE ALL ON atlas.assigned_care_activity_recognition_links_v1/);
  assert.match(sql,/REVOKE ALL ON FUNCTION atlas.recognize_assigned_care_activity_self_api_v1/);
  assert.match(sql,/GRANT EXECUTE ON FUNCTION public.recognize_assigned_care_activity_self_api_v1/);
  assert.match(sql,/TO authenticated;/);
});
test('disposable PG postconditions and local ROLLBACK guard included',()=>{
  assert.match(post,/to_regprocedure/);
  assert.match(post,/has_function_privilege/);
  assert.match(post,/pg_trigger/);
  assert.match(sh,/P1_DISPOSABLE_CONFIRM/);
  assert.match(sh,/ROLLBACK;/);
  assert.doesNotMatch(sh,/COMMIT;/);
});

test('held clone preserves the live October 30 connection-direct root gate',()=>{
  const held=readFileSync(new URL('../candidates/atlas/20261028235811_atlas_care_single_done_signed_proof_v1.sql',import.meta.url),'utf8');
  const liveLedgerSource='7570082f04024397227545e685a4c071';
  const liveResponsibilityGuard='1043ad551860196f1a13df25de9f8478';
  assert.match(held,/<> '1043ad551860196f1a13df25de9f8478'/);
  assert.match(held,/<> '7570082f04024397227545e685a4c071'/);
  assert.equal((held.match(/Exact Ledger root required for connection-direct responsibility/g)||[]).length,1);
  assert.match(held,/if v_kind='ledger_connection_direct_assignment' then[\s\S]*?Connected direct assignment requires exact original Person and Ledger source' using errcode='23514';end if;\s*IF NOT EXISTS \(SELECT 1 FROM atlas\.capability_root_authority_context_self_v1\(\(v_basis->>'nativeLedgerId'\)::uuid\)\)[\s\S]*?Exact Ledger root required for connection-direct responsibility/);
  assert.equal(liveLedgerSource.length,32);
  assert.equal(liveResponsibilityGuard.length,32);
});


test('held signed care suite has the exact source-owned disclosure reader, no fake permission bridge',()=>{
  const held=readFileSync(new URL('../candidates/atlas/20261028235811_atlas_care_single_done_signed_proof_v1.sql',import.meta.url),'utf8');
  const postconditions=readFileSync(new URL('../validation/migrations/20261028235811_atlas_care_single_done_signed_proof_v1.sql',import.meta.url),'utf8');
  const marker='-- HELD SOURCE-ONLY candidate stacked on Noel #2362.';
  const beginning=held.lastIndexOf(marker);
  const ending=held.lastIndexOf('\n\nCOMMIT;');
  assert.ok(beginning>0 && ending>beginning,'source reader must precede the held COMMIT');
  const exactSource=held.slice(beginning,ending)+'\n';
  const gitBlobSha=createHash('sha1').update('blob '+Buffer.byteLength(exactSource)+'\0').update(exactSource).digest('hex');
  assert.equal(gitBlobSha,'f2ca1a5975c5f1e06a54709e6d90e08e1bb1d751','reader must retain exact approved held source blob');
  const checks=['auth.uid()','current_person_id_v1','current_active_ledger_seat_v1',
    'person_has_native_ledger_connection_v1','scope.accepted_at IS NOT NULL',
    "scope.coverage_mode='ledger_all_work'","'identity')","'condition')",
    'LIMIT (p_limit+1)','noUndisclosedCounts','noWorkCreated',
    'REVOKE ALL ON FUNCTION atlas.connected_person_disclosed_standing_rhythms_self_api_v1',
    'GRANT EXECUTE ON FUNCTION public.connected_person_disclosed_standing_rhythms_self_api_v1'];
  for(const needle of checks)assert.ok(exactSource.includes(needle),'missing '+needle);
  assert.doesNotMatch(exactSource,/^\s*(INSERT|UPDATE|DELETE|TRUNCATE)\s/mi);
  assert.match(postconditions,/DO \$disclosed_standing\$/);
  assert.match(postconditions,/Missing exact signed native disclosed care list/);
  assert.match(postconditions,/Standing care reader exposed through wrong authority/);
  assert.match(postconditions,/AND 'search_path=""'=ANY\(p\.proconfig\)/);
  assert.doesNotMatch(postconditions,/AND 'search_path='=ANY\(p\.proconfig\)/);
  assert.match(held,/\nCOMMIT;\s*$/);
});


test('full protected clone exercises exact P1 source and SQL-only denials',()=>{
  const held=readFileSync(new URL('../candidates/atlas/20261028235811_atlas_care_single_done_signed_proof_v1.sql',import.meta.url),'utf8');
  const p1=readFileSync(new URL('../candidates/atlas_actual_first_p1_assigned_care_activity_v1/01_assigned_activity_recognition_held.sql',import.meta.url),'utf8');
  const structural=readFileSync(new URL('../candidates/atlas_actual_first_p1_assigned_care_activity_v1/02_rollback_postconditions_held.sql',import.meta.url),'utf8');
  const denials=readFileSync(new URL('../candidates/atlas_actual_first_p1_assigned_care_activity_v1/04_sql_role_denials_held.sql',import.meta.url),'utf8');
  const post=readFileSync(new URL('../validation/migrations/20261028235811_atlas_care_single_done_signed_proof_v1.sql',import.meta.url),'utf8');
  assert.ok(held.includes(p1),'P1 source must stay verbatim');
  assert.equal(held.split('CREATE FUNCTION atlas.recognize_assigned_care_activity_self_api_v1').length,2);
  assert.ok(post.includes(structural.trimEnd()),'P1 structural checks must be executed');
  assert.ok(post.includes(denials.trimEnd()),'P1 signed-absent role denials must be executed');
  assert.match(post,/BEGIN;\s*-- UNI-OPS-01 P1 SQL-only negative behavioral checks/);
  assert.match(post,/\$p1_counts\$;\s*ROLLBACK;/);
  assert.match(post,/Standing care read must be constrained and stable/);
  assert.match(held,/\nCOMMIT;\s*$/);
});


test('optional P1 signed bearer proof does not replace the existing C1 signed matrix',()=>{
  const c1=readFileSync(new URL('../scripts/validate-atlas-care-single-done-signed-http.py',import.meta.url),'utf8');
  const p1=readFileSync(new URL('../scripts/validate-atlas-actual-first-p1-signed-http.py',import.meta.url),'utf8');
  assert.match(c1,/--p1-recognition-proof/);
  assert.match(c1,/if args\.p1_recognition_proof:/);
  assert.match(c1,/p1_module\.prove\(/);
  assert.ok(c1.indexOf('if args.p1_recognition_proof:')>c1.indexOf('work=made["workItemId"]'));
  assert.ok(c1.indexOf('if args.p1_recognition_proof:')<c1.indexOf('print("PASS governor source observation and one bounded original Work")'));
  assert.match(p1,/record_worker_activity_log_v1\(/);
  assert.match(p1,/signed_source\(db, worker, event\)/);
  assert.match(p1,/ThreadPoolExecutor\(max_workers=2\)/);
  assert.match(p1,/recognitionLinkId/);
  assert.match(p1,/retract_worker_activity_log_v1/);
  assert.match(p1,/active=false where user_id=/);
  assert.match(p1,/noClockAdmission/);
  assert.match(p1,/noNewWorkCreated/);
  assert.match(p1,/NOT PROVEN: production/);
  assert.match(p1,/allowed = \(409,\) if code == "23505"/);
  assert.match(p1,/and isinstance\(payload, dict\) and payload.get\("code"\)==code/);

  assert.doesNotMatch(p1,/https?:\/\//);
});


test('release eligibility records live-missing C1 prerequisite identities and clone-only fence',()=>{
  const review=readFileSync(new URL('../candidates/atlas_actual_first_p1_assigned_care_activity_v1/RELEASE_ELIGIBILITY_20261105.md',import.meta.url),'utf8');
  const liveProbe=readFileSync(new URL('../candidates/atlas_actual_first_p1_assigned_care_activity_v1/P1_RELEASE_READONLY_PREFLIGHT.sql',import.meta.url),'utf8');
  const combined=readFileSync(new URL('../candidates/atlas/20261028235811_atlas_care_single_done_signed_proof_v1.sql',import.meta.url),'utf8');
  assert.match(review,/Decision: BLOCKED for production release/);
  assert.match(review,/isolated P1 signed acceptance: PASSED/);
  assert.match(review,/source provenance and dependency split register/);
  for(const signature of (
    'atlas.record_continuing_care_actual_self_api_v1(uuid,uuid,text,text,integer,text,date)',
    'atlas.apply_work_lifecycle_transition_internal_v1(uuid,text,uuid,text)',
    'atlas.owner_establish_observed_continuing_care_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid)',
    'atlas.recognize_assigned_care_activity_self_api_v1(uuid,uuid,text,text)',
    'atlas.assigned_care_activity_recognition_links_v1'
  )){
    assert.ok(liveProbe.includes(signature),'missing dependency from read-only live preflight: '+signature);
  }
  const sqlOnly=liveProbe.split('\n').filter(line=>!line.trimStart().startsWith('--')).join('\n');
  assert.match(sqlOnly,/^\s*WITH required\(/);
  assert.match(sqlOnly,/SELECT kind,identity,purpose/);
  assert.doesNotMatch(sqlOnly,/\b(CREATE|ALTER|DROP|TRUNCATE|INSERT|UPDATE|DELETE|GRANT|REVOKE|COPY|CALL)\s+(TABLE|FUNCTION|SCHEMA|INTO|FROM|ON)\b/i);
  assert.match(combined,/^BEGIN;\n-- CLONE TEST ONLY:/);
  assert.match(combined,/Test-only care source requires an exact fictional C1 clone/);
  assert.match(combined,/\nCOMMIT;\s*$/);
  assert.match(review,/No P1 migration until this is reconciled/);
});


test('separate P1 Partial/Blocked overlay is an exact one-expression source delta',()=>{
  // This MUST NOT alter original P1 blob 476e85b1; the owner-signed clone
  // still executes the unmodified source and cannot be credited to the overlay.
  const parent=readFileSync(new URL('../candidates/atlas_actual_first_p1_assigned_care_activity_v1/01_assigned_activity_recognition_held.sql',import.meta.url),'utf8');
  const overlay=readFileSync(new URL('../candidates/atlas_actual_first_p1_assigned_care_activity_v1/18_nonterminal_actual_receipt_overlay_held.sql',import.meta.url),'utf8');
  const origSha=createHash('sha1').update('blob '+Buffer.byteLength(parent)+'\0').update(parent).digest('hex');
  assert.equal(origSha,'476e85b1e6f46d7ac996dce9ea0e51b89c50f28c',
    'original previously signed P1 source must remain exact');
  const start='CREATE FUNCTION atlas.recognize_assigned_care_activity_self_api_v1(';
  const overStart='CREATE OR REPLACE FUNCTION atlas.recognize_assigned_care_activity_self_api_v1(';
  const getBody=(value,needle)=>{
    const i=value.indexOf(needle);
    const j=value.indexOf('$recognize$;',i);
    assert.ok(i>=0 && j>i,'exact P1 private function not present');
    return value.slice(i,j+'$recognize$;'.length);
  };
  const baseline=getBody(parent,start);
  const candidate=getBody(overlay,overStart).replace(overStart,start);
  const oldReceipt=`    OR v_receipt->>'physicalActualContractVersion'
       IS DISTINCT FROM 'continuing_care_actual_v1'
`;
  const newReceipt=`    OR NOT (
      -- Completed care returns the universal lifecycle envelope plus
      -- physicalActualContractVersion. Partial/Blocked care returns the
      -- nonterminal native Actual contractVersion and keeps Work open.
      -- Both are source-qualified Result receipts; neither is a next issuer.
      v_receipt->>'physicalActualContractVersion'='continuing_care_actual_v1'
      OR (
        v_receipt->>'physicalActualContractVersion' IS NULL
        AND v_receipt->>'contractVersion'='continuing_care_actual_v1'
        AND v_receipt->>'workState'='open'
      )
    )
`;
  assert.ok(candidate.includes(newReceipt),'new exact nonterminal receipt branch missing');
  assert.equal(candidate.replace(newReceipt,oldReceipt),baseline,
    'overlay may alter only the Result receipt discriminator');
  assert.match(candidate,/v_work.metadata \? 'sourceStandingCampaignId'/);
  assert.match(candidate,/requires no-successor source cutover/);
  assert.match(candidate,/a.acceptance_kind='source_qualified_physical_actual'/);
  assert.match(candidate,/v_receipt->>'noNewWorkCreated' IS DISTINCT FROM 'true'/);
  assert.match(candidate,/v_receipt->>'noClockAdmission' IS DISTINCT FROM 'true'/);
  assert.match(overlay,/REVOKE ALL ON FUNCTION atlas.recognize_assigned_care_activity_self_api_v1/);
  assert.doesNotMatch(overlay,/CREATE\s+(?:OR REPLACE\s+)?TABLE\s+atlas/i);
  assert.doesNotMatch(overlay,/\bGRANT\s+EXECUTE\b/i);
  assert.doesNotMatch(overlay,/CREATE\s+(?:OR REPLACE\s+)?FUNCTION\s+public\./i);
});
