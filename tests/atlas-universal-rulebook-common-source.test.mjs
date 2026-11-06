import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const root='candidates/atlas_universal_rulebook_common_source_v1/';
const candidate=readFileSync(root+'candidate.sql','utf8');
const post=readFileSync(root+'postconditions.sql','utf8');
const coverage=readFileSync(root+'read_only_coverage.sql','utf8');
const executable=(text)=>text.replace(/--[^\n]*/g,'');
const source=executable(candidate);
const readOnly=executable(coverage);

test('one source-owned private common function in one held transaction',()=>{
  assert.match(source,/^\s*BEGIN\s*;/i);
  assert.match(source,/\bCOMMIT\s*;\s*$/i);
  assert.equal((source.match(/\bCREATE\s+FUNCTION\b/gi)||[]).length,1);
  assert.match(source,/CREATE FUNCTION atlas\.universal_rulebook_common_source_preflight_internal_v1\s*\(/);
  assert.doesNotMatch(source,/\bCREATE\s+(TABLE|VIEW|TRIGGER|POLICY)\b/i);
});
test('not an arbitrary new grant, root, exposed transport, or Work writer',()=>{
  assert.doesNotMatch(source,/\bGRANT\b|\bINSERT\s+INTO\b|\bUPDATE\s+|\bDELETE\s+FROM\b/i);
  assert.doesNotMatch(source,/\bCREATE FUNCTION public\.|\bCREATE OR REPLACE FUNCTION public\./i);
  assert.match(source,/REVOKE ALL ON FUNCTION\s+atlas\.universal_rulebook_common_source_preflight_internal_v1/i);
  assert.match(source,/FROM PUBLIC,anon,authenticated,service_role/i);
});
test('requires the actual current signed principal, not actor metadata',()=>{
  assert.match(source,/foundry_current_signed_principal_v1\s*\(\s*\)/);
  assert.match(source,/company_work_native_ledger_owner_self_v1\s*\(/);
  assert.match(source,/current_principal_id_v1\s*\(\s*\)/);
  assert.doesNotMatch(source,/raw_user_meta_data|user_metadata|service_role\s+as|set_config.*role/i);
});
test('native organization owns one current primary governing Ledger',()=>{
  for(const expr of [
    "lp.organization_id=p_organization_id",
    "lp.ledger_id=p_ledger_id",
    "lp.status='active'",
    "lp.ended_at IS NULL",
    "lp.participation_kind='governing'",
    "lp.is_compatibility_primary=true"
  ]) assert.ok(source.includes(expr),expr);
});
test('requires an already active, source-linked exact Requirement',()=>{
  for(const expr of [
    "w.id=p_requirement_id",
    "w.organization_id=p_organization_id",
    "w.state='active'",
    "w.source_object_type='reality_entity'",
    "w.source_object_id IS NOT NULL",
    "nullif(btrim(v_requirement.metadata->>'needKey'),'')",
    "length(v_need_key) NOT BETWEEN 2 AND 120"
  ]) assert.ok(source.includes(expr),expr);
});
test('only canonical reality.entities is authoritative for common Subject identity',()=>{
  assert.match(source,/FROM reality\.entities e/);
  assert.match(source,/e\.id=v_requirement\.source_object_id/);
  assert.match(source,/e\.identity_state='canonical'/);
  assert.doesNotMatch(source,/FROM atlas\.identity_subjects|JOIN atlas\.identity_subjects/);
  assert.doesNotMatch(source,/FROM atlas\.identity_source_subject_assertions|JOIN atlas\.identity_source_subject_assertions/);
});
test('declared domain alone is explicitly not adapter provenance',()=>{
  assert.match(candidate,/declared domain is NOT evidence of its authority/i);
  assert.match(source,/v_domain := nullif\(btrim\(v_subject\.metadata->>'subjectDomain'\),''\)/);
  assert.match(source,/'domainAdapterAccepted',false/);
  assert.match(source,/'state','common_checks_only_not_admitted'/);
});
test('common gate contains no privileged farm, household, school or event exception',()=>{
  assert.doesNotMatch(source,/growing_objects|farms|crop|laundry|school|household|venue|mowing|sunflower|bed_assignment/i);
  assert.doesNotMatch(source,/entity_kind\s*=\s*'[^']+'/i);
  assert.match(source,/v_subject\.entity_kind/);
});
test('both actual current identity and condition permissions are mandatory',()=>{
  assert.equal((source.match(/atlas\.has_current_subject_disclosure_v1\s*\(/g)||[]).length,2);
  assert.match(source,/v_subject\.id,'identity'\),false\)/);
  assert.match(source,/v_subject\.id,'condition'\),false\)/);
  assert.match(source,/Current Subject disclosure unavailable/);
});
test('every common failure denies with 42501, not silent authority',()=>{
  const reasons=[
    'Exact native source required',
    'Current native root unavailable',
    'Current governing Ledger unavailable',
    'Canonical Requirement source unavailable',
    'Canonical Subject source unavailable',
    'Current Subject disclosure unavailable'
  ];
  for(const x of reasons)assert.ok(candidate.includes(x),x);
  assert.equal((source.match(/USING ERRCODE='42501'/g)||[]).length,6);
});
test('common source verification NEVER authorizes a policy or Work',()=>{
  for(const flag of [
    'domainAdapterAccepted','independentSourceReviewAccepted',
    'policyAdoptable','policyExecutable','workCreated','clockAdmitted',
    'successorWorkCreated'
  ])assert.ok(source.includes("'"+flag+"',false"),flag);
  assert.doesNotMatch(source,/apply_work_lifecycle|establish_.*work|offer_.*candidate|record_.*actual/i);
});
test('the common reader is stable, security-defined, private, and nonexecuting',()=>{
  assert.match(source,/LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''/);
  assert.match(post,/to_regprocedure\s*\(/);
  assert.match(post,/has_function_privilege\('anon',v_fn,'EXECUTE'\)/);
  assert.match(post,/has_function_privilege\('authenticated',v_fn,'EXECUTE'\)/);
  assert.match(post,/has_function_privilege\('service_role',v_fn,'EXECUTE'\)/);
  assert.match(post,/v_security_definer IS DISTINCT FROM true/);
});
test('coverage is an aggregate-only SELECT with source-family grouping',()=>{
  assert.match(readOnly,/^\s*WITH\s/i);
  assert.match(readOnly,/^WITH[\s\S]+SELECT jsonb_build_object\s*\(/i);
  assert.doesNotMatch(readOnly,/\bINSERT\b|\bUPDATE\b|\bDELETE\b|\bCREATE\b|\bDROP\b|\bALTER\b|\bGRANT\b|\bREVOKE\b|\bCOPY\b|\bEXECUTE\b|\bCALL\b/i);
  assert.match(readOnly,/w\.source_object_type/);
  assert.match(readOnly,/GROUP BY w\.source_object_type/);
  assert.match(readOnly,/identity_reconciliation_adjudications/);
  assert.match(readOnly,/foundry\.source_custody_review_cases_v1/);
});
test('no row details, contacts, source text or individual identities emitted by aggregate',()=>{
  assert.doesNotMatch(readOnly,/display_name|original_text|email|phone|metadata::text|auth\.users|source_refs|person_entity_id/i);
  assert.match(readOnly,/commonCanonicalCandidates/);
  assert.match(readOnly,/originalOperatingInputEvents/);
});
test('read-only coverage explicitly refuses domain/authorization inference',()=>{
  assert.match(coverage,/Never treat counts, claims, aliases, same-ID proximity or metadata as/i);
  assert.match(readOnly,/'domainAdapterAuthority',true/);
  assert.match(readOnly,/'policyAdoptionAuthority',true/);
  assert.match(readOnly,/'workIssuanceAuthority',true/);
});
