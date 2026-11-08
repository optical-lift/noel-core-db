import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const prefix='candidates/atlas_uni_ops_universal_typed_household_evidence_v1/';
const raw=readFileSync(prefix+'candidate.sql','utf8');
const sql=raw.replace(/--[^\n]*/g,'');
const post=readFileSync(prefix+'postconditions.sql','utf8');

test('single private typed native evidence function and no second Work/Rulebook engine',()=>{
  assert.equal((sql.match(/\bCREATE FUNCTION\b/g)||[]).length,1);
  assert.match(sql,/CREATE FUNCTION atlas\.universal_rulebook_household_native_evidence_internal_v1\(/);
  assert.match(sql,/LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''/);
  assert.doesNotMatch(sql,/\bCREATE\s+(TABLE|VIEW|POLICY|TRIGGER)\b/);
  assert.doesNotMatch(sql,/\b(?:INSERT|UPDATE|DELETE|ALTER|DROP|GRANT)\s+/);
  assert.match(sql,/\bCOMMIT;\s*$/);
});
test('requires exact signed current principal rather than browser claims',()=>{
  assert.match(sql,/foundry_current_signed_principal_v1\(\)/);
  assert.match(sql,/current_principal_id_v1\(\)/);
  assert.match(sql,/v_principal_id IS DISTINCT FROM atlas\.current_principal_id_v1\(\)/);
  assert.doesNotMatch(sql,/user_metadata|raw_user_meta_data|service_role\W+as/i);
});
test('Household governor is NOT corporate Ledger root',()=>{
  assert.match(sql,/atlas\.require_household_governor_self_v1\(/);
  assert.doesNotMatch(sql,/company_work_native_ledger_owner_self_v1|ledger_organization_participations|is_compatibility_primary|p_organization_id|p_ledger_id/);
});
test('exact active native Subject and independent native Household jurisdiction',()=>{
  for(const phrase of [
    "i.id=p_kernel_instance_id","i.household_id=p_household_id",
    "i.state='active'","h.status='active'",
    "d.kernel_key=i.kernel_key","d.version=i.kernel_version",
    "d.scope_kind='household'","d.active=true",
    "i.kernel_version>0"
  ])assert.ok(sql.includes(phrase),phrase);
});
test('domain source is keyed to a native kernel, not a magic laundry value',()=>{
  assert.doesNotMatch(sql,/\b(?:laundry|mowing|flower|wash_started|venue)\b/i);
  assert.match(sql,/v_kernel\.kernel_key/);
  assert.match(sql,/nativeSubjectKind','household_kernel_instance'/);
});
test('current physical source must be an authentic matching observed event',()=>{
  for(const phrase of [
    "c.scope_kind='household'","c.scope_id=p_household_id",
    "c.subject_domain='household'",
    "c.subject_kind='household_kernel_instance'",
    "c.subject_id=v_kernel.id::text",
    "c.last_observation_id",
    "o.id=v_current_observation_id","o.inferred_from_clock=false",
    "o.observed_by_user_id IS NOT NULL","o.observed_at<=now()",
    "c.condition_state=o.condition_state"
  ])assert.ok(sql.includes(phrase),phrase);
});
test('no invented future Need: opened by a real source observation only',()=>{
  for(const phrase of [
    "n.household_id=p_household_id","n.instance_id=v_kernel.id",
    "n.state='open'","n.opened_by_observation_id=v_current_observation_id"
  ])assert.ok(sql.includes(phrase),phrase);
  assert.match(sql,/IF v_observation_verified THEN/);
  assert.doesNotMatch(sql,/ensure_requirement|ensure_household|household_rhythm_tick|create.*work/i);
});
test('successful native source is not canonical Reality or a Rulebook authorization',()=>{
  for(const key of [
    'canonicalRealityBindingVerified','commonRequirementVerified',
    'independentFoundryReviewVerified','domainAdmissionAuthorized',
    'policyAdoptable','policyExecutable','workCreated',
    'clockAdmitted','successorWorkCreated'
  ]) assert.ok(sql.includes("'"+key+"',false"),key);
  assert.match(sql,/'nativeSubjectVerified',true/);
  assert.match(sql,/'state','native_subject_only_not_canonical'/);
});
test('private source transport has NO authenticated or service-role grant',()=>{
  assert.match(sql,/REVOKE ALL ON FUNCTION\s+atlas\.universal_rulebook_household_native_evidence_internal_v1\(/);
  assert.match(sql,/FROM PUBLIC,anon,authenticated,service_role/);
  assert.doesNotMatch(sql,/\bCREATE\s+FUNCTION\s+public\./);
  assert.match(post,/has_function_privilege\('anon'/);
  assert.match(post,/has_function_privilege\('authenticated'/);
  assert.match(post,/has_function_privilege\('service_role'/);
});
test('source-only SQL does not create synthetic actors or operate a live migration',()=>{
  assert.doesNotMatch(sql,/\bauth\.users\b|\bauth\.sessions\b|\bINSERT INTO\b|\bsupabase_migrations\b/);
  assert.doesNotMatch(sql,/\bGRANT EXECUTE\b/);
  assert.doesNotMatch(sql,/gen_random_uuid\(\)/);
});
test('native Subject does not assume a same-ID Reality Entity or fake crosswalk',()=>{
  assert.doesNotMatch(sql,/JOIN reality\.entities|INSERT INTO reality\.entities|source_object_type\s*=\s*'reality_entity'/);
  assert.match(raw,/not a canonical/i);
});
test('both unobserved condition and unknown Need remain honest, not inferred',()=>{
  assert.match(sql,/v_observation_verified boolean := false/);
  assert.match(sql,/v_open_need_verified boolean := false/);
  assert.match(sql,/'currentObservationSourceVerified',v_observation_verified/);
  assert.match(sql,/'openNeedSourceVerified',v_open_need_verified/);
});
test('all invalid native sources fail by permission denial',()=>{
  for(const msg of [
    'Exact independent Household source required',
    'Current signed Household principal unavailable',
    'Native Household governor unavailable',
    'Exact active native Household Subject unavailable'
  ]) assert.ok(sql.includes(msg),msg);
  assert.equal((sql.match(/USING ERRCODE='42501'/g)||[]).length,4);
});
test('supporting structural check is disposable-only and no public function mirror',()=>{
  assert.match(post,/to_regprocedure\(/);
  assert.match(post,/p\.prosecdef/);
  assert.match(post,/p\.provolatile='s'/);
  assert.match(post,/public\.universal_rulebook_household_native_evidence_internal_v1/);
});
