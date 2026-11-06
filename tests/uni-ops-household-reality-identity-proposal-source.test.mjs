import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {resolve,dirname} from 'node:path';

const base=dirname(fileURLToPath(import.meta.url));
const sql=readFileSync(resolve(base,'../candidates/uni_ops_household_reality_identity_proposal_v1/candidate.sql'),'utf8');
const post=readFileSync(resolve(base,'../candidates/uni_ops_household_reality_identity_proposal_v1/postconditions.sql'),'utf8');

test('candidate is a held proposal, not a canonical registry or migration',()=>{
  assert.match(sql,/HELD CANDIDATE, NOT A MIGRATION/i);
  assert.match(sql,/CREATE TABLE atlas\.uni_ops_household_reality_identity_proposals_v1/);
  assert.match(sql,/REFERENCES reality\.entities\(id\) ON DELETE RESTRICT/);
  assert.doesNotMatch(sql,/\bCREATE TABLE reality\.entities\b/i);
  assert.doesNotMatch(sql,/\bINSERT INTO reality\.entities\b/i);
});
test('native Household cannot be impersonated by Company Ledger',()=>{
  assert.match(sql,/atlas\.foundry_current_signed_principal_v1\(\)/);
  assert.match(sql,/atlas\.current_principal_id_v1\(\)/);
  assert.match(sql,/atlas\.require_household_governor_self_v1\(p_household_id\)/);
  assert.match(sql,/JOIN atlas\.world_kernel_definitions d/);
  assert.doesNotMatch(sql,/company_work_native_ledger_owner_self_v1/);
});
test('proposal is not independent evidence or identity approval',()=>{
  assert.match(sql,/e\.identity_state='canonical'/);
  for(const flag of ['evidenceIndependentlyVerified','canonicalIdentityBindingApproved','nativeNeedMapped','foundryIndependentReviewApproved','domainAdmitted','policyAdoptable','policyExecutable','workCreated','clockAdmitted','successorWorkCreated']){
    assert.match(sql,new RegExp("'"+flag+"',false"));
  }
  assert.match(sql,/source_identity_proposal_only_not_adjudicated/);
});
test('exact original claim, immutable custody, replay conflict',()=>{
  assert.match(sql,/BEFORE UPDATE OR DELETE ON atlas\.uni_ops_household_reality_identity_proposals_v1/);
  assert.match(sql,/source_action_id uuid NOT NULL/);
  assert.match(sql,/UNIQUE\(household_id,source_action_id\)/);
  assert.match(sql,/ON CONFLICT \(household_id,source_action_id\) DO NOTHING/);
  assert.match(sql,/Identity proposal action replay conflict/);
  assert.match(sql,/claimed_evidence_sha256 ~ '\^\[0-9a-f\]\{64\}\$'/);
});
test('private ACL and read-only source boundary',()=>{
  assert.match(sql,/ENABLE ROW LEVEL SECURITY/);
  assert.match(sql,/REVOKE ALL ON TABLE/);
  assert.match(sql,/REVOKE ALL ON FUNCTION/);
  assert.doesNotMatch(sql,/\bGRANT\b/i);
  assert.doesNotMatch(sql,/\bINSERT INTO atlas\.work_items\b/i);
  assert.doesNotMatch(sql,/\bINSERT INTO atlas\.work_requirements\b/i);
  assert.doesNotMatch(sql,/\bINSERT INTO atlas\.household_need_occurrences_v1\b/i);
  assert.match(post,/has_function_privilege/);
  assert.match(post,/has_table_privilege/);
  assert.match(post,/relrowsecurity=true/);
});