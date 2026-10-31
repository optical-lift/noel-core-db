import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
const folder=new URL("../candidates/atlas_universal_work_lifecycle_v1/",import.meta.url);
const read=(name)=>readFileSync(new URL(name,folder),"utf8");
const transition=read("06_single_transition_authority_private.sql");
const retired=read("12_self_adopted_original_writer_single_done_cutover_candidate.sql");
const tests=[read("09_self_adoption_person_rollback.sql"),read("13_self_adopted_original_writer_rollback.sql")];
const runner=read("manual_rollback_smoke.sh");
test("universal Done uses native Person and disclosure, never legacy membership as permission",()=>{
 assert.doesNotMatch(transition,/organization_memberships|employee_seats/i);
 for(const term of ["establishment_basis_kind='self_adoption'","Historical self-adopted responsibility requires native reconciliation","assignee_canonical_person_id IS DISTINCT FROM v_actor","person_original_work_identity_disclosed_self_v1","company_work_native_ledger_owner_self_v1"])
  assert.ok(transition.includes(term),"missing "+term);
});
test("retired self-adoption writer creates no result, acceptance, Work or new Done",()=>{
 assert.match(retired,/CREATE OR REPLACE FUNCTION atlas\.report_self_responsible_company_work_self_api_v1/);
 assert.match(retired,/auth\.uid\(\)/);
 assert.match(retired,/current_person_id_v1\(\)/);
 assert.match(retired,/Historical self-adopted Work is reference only; current governor reconciliation required/);
 assert.doesNotMatch(retired,/organization_memberships|assignee_membership_id|institutional_person_records/i);
 assert.doesNotMatch(retired,/\b(INSERT INTO|UPDATE|DELETE FROM|TRUNCATE)\b/i);
 assert.doesNotMatch(retired,/apply_work_lifecycle_transition_internal_v1/);
});
test("historical Result denial is asserted with record counts, not a reopened Work",()=>{
 for(const src of tests){
  for(const key of ["v_before_events","v_before_results","v_before_acceptances","SQLSTATE '42501'"])
    assert.ok(src.includes(key),"missing "+key);
  assert.doesNotMatch(src,/UPDATE atlas\.work_items SET work_state='open'/i);
  assert.doesNotMatch(src,/INSERT INTO atlas\.work_items/i);
 }
 assert.doesNotMatch(runner,/SAVEPOINT gate2_self_original_fixture/);
 for(const name of ["09_self_adoption_person_rollback.sql","13_self_adopted_original_writer_rollback.sql"])
   assert.ok(runner.includes(name),"missing "+name);
});


const historical=read("16_historical_self_adoption_review_candidate.sql");
const historicalReadback=read("17_historical_self_adoption_review_readback_candidate.sql");
const historicalTransport=read("19_historical_self_adoption_public_transport_candidate.sql");
const historicalPostconditions=read("18_historical_self_adoption_review_postconditions.sql");
test("historical decisions use native Ledger governor or exact signed worker, never legacy authority",()=>{
 for(const name of [
 "governor_link_historical_self_adoption_self_api_v1",
 "report_historical_self_adoption_pending_self_api_v1",
 "governor_review_historical_self_adoption_self_api_v1",
 "historical_self_adoption_review_events_v1",
 "company_work_native_ledger_owner_self_v1",
 "person_has_native_ledger_connection_v1",
 "current_active_ledger_seat_v1",
 "person_original_work_identity_disclosed_self_v1",
 "reality_access_self_api_v1",
 "legacyAuthorityGranted",
 "newWorkCreated",
 "noAcceptedActualFabricated",
 "Historical performance requires actual evidence"
 ])assert.ok(historical.includes(name),"missing "+name);
 assert.doesNotMatch(historical,/atlas\.organization_memberships|atlas\.farm_memberships|employee_seats/i);
 assert.doesNotMatch(historical,/\b(UPDATE|DELETE FROM|TRUNCATE)\s+atlas\.work_(items|execution_results|allocations|result_acceptances)/i);
 assert.match(historical,/ENABLE ROW LEVEL SECURITY/);
 assert.match(historical,/FORCE ROW LEVEL SECURITY/);
 assert.match(historical,/REVOKE ALL ON atlas\.historical_self_adoption_review_events_v1/);
 assert.match(historical,/Historical review is immutable/);
 assert.match(historical,/state','pending','acceptedDone',false/);
 assert.match(historical,/currentAssignmentCreated',false/);
 assert.match(historical,/event_kind='governor_reviewed'/);
});

test("governor historical readback is bounded and retains source privacy",()=>{
 assert.match(historicalReadback,/governor_historical_self_adoption_history_self_api_v1/);
 assert.match(historicalReadback,/company_work_native_ledger_owner_self_v1/);
 assert.match(historicalReadback,/company_work_native_ledger_relevance/);
 assert.match(historicalReadback,/LIMIT 51/);
 assert.match(historicalReadback,/FILTER\(WHERE seq<=50\)/);
 assert.match(historicalReadback,/hasMore/);
 assert.match(historicalReadback,/REVOKE ALL ON FUNCTION/);
 assert.doesNotMatch(historicalReadback,/organization_memberships|employee_seats/);
});

test("public history transport is exact signed-only while raw table is absent",()=>{
 for(const rpc of [
  "governor_link_historical_self_adoption_self_api_v1",
  "report_historical_self_adoption_pending_self_api_v1",
  "governor_review_historical_self_adoption_self_api_v1",
  "governor_historical_self_adoption_history_self_api_v1"
 ]) {
  assert.match(historicalTransport,new RegExp("public\\."+rpc));
  assert.match(historicalTransport,new RegExp("atlas\\."+rpc));
  assert.ok(historicalPostconditions.includes("'public."+rpc));
 }
 assert.match(historicalTransport,/REVOKE ALL ON FUNCTION/);
 assert.match(historicalTransport,/TO authenticated/);
 assert.doesNotMatch(historicalTransport,/GRANT\s+(SELECT|INSERT|UPDATE|DELETE)\s+ON\s+atlas\./);
 assert.match(historicalPostconditions,/has_table_privilege\('authenticated'/);
 assert.match(historicalPostconditions,/has_function_privilege\('anon'/);
 assert.match(historicalPostconditions,/Historical review immutability not enforced/);
});

test("contradictory historical outcomes and post-review worker evidence are forbidden",()=>{
 assert.match(historical,/Accepted historical performance cannot be reclassified as obsolete/);
 assert.match(historical,/Historical performance requires actual evidence/);
 assert.match(historical,/Historical review already finalized; new evidence needs a governed reopen/);
 assert.match(historical,/Historical decision already reviewed; correction requires adjudication/);
 assert.match(historical,/Conflicting historical (link|evidence|review) replay/);
});

const lifecycleSource=read("01_shadow_event_source.sql");
const nativeRetire=read("20_native_historical_retirement_candidate.sql");
const retireTransport=read("21_native_historical_retirement_preflight_transport_candidate.sql");
const retireChecks=read("22_native_historical_retirement_rollback_postconditions.sql");
const retireRunner=read("manual_historical_retirement_rollback.sh");

test("historical retirement shares the private terminal authority without claiming Done",()=>{
 for(const source of [lifecycleSource,nativeRetire,transition]) {
   assert.match(source,/historical_self_adoption_review_events_v1/);
 }
 for(const word of [
  "p_transition_kind='cancel'","outcome='obsolete_cancelled'",
  "company_work_native_ledger_owner_self_v1",
  "company_work_retirement_dependency_snapshot_v1",
  "source_row_id","work_transition_applied",
  "work_state='cancelled'","originalResultId',null",
  "acceptedEvidenceId',null"
 ])assert.ok(transition.includes(word),"missing cancel gate "+word);
 assert.match(transition,/v_work\.work_state<>'open'/);
 assert.match(transition,/activeAdapterIds/);
 assert.match(transition,/activeTimeContractIds/);
 assert.match(transition,/state='released'/);
 assert.match(transition,/plan_state='withdrawn'/);
 assert.doesNotMatch(transition,/organization_memberships|farm_memberships|employee_seats/i);
 assert.doesNotMatch(nativeRetire,/\b(INSERT INTO|UPDATE)\s+atlas\.work_(items|execution_results|result_acceptances)/i);
 assert.doesNotMatch(nativeRetire,/organization_memberships|farm_memberships/i);
 assert.match(nativeRetire,/apply_work_lifecycle_transition_internal_v1/);
});
test("governor preflight token and transport cannot become a second Done writer",()=>{
 for(const word of [
  "company_work_native_ledger_owner_self_v1",
  "company_work_retirement_dependency_snapshot_v1",
  "impactToken","blockingDependencyCount","retirable",
  "public.governor_retire_historical_work_self_api_v1",
  "public.governor_historical_retirement_preflight_self_api_v1",
  "TO authenticated"
 ]) assert.ok(retireTransport.includes(word),"missing transport "+word);
 assert.match(nativeRetire,/p_impact_token/);
 assert.match(nativeRetire,/md5\(v_impact::text\)/);
 assert.match(nativeRetire,/FOR UPDATE/);
 assert.match(nativeRetire,/p_action_id::text/);
 assert.match(retireChecks,/has_function_privilege\('anon'/);
 assert.match(retireChecks,/has_function_privilege\('authenticated'/);
 for(const f of [
  "16_historical_self_adoption_review_candidate.sql",
  "19_historical_self_adoption_public_transport_candidate.sql",
  "20_native_historical_retirement_candidate.sql",
  "21_native_historical_retirement_preflight_transport_candidate.sql",
  "22_native_historical_retirement_rollback_postconditions.sql"
 ]) assert.ok(retireRunner.includes(f),"missing rollback assembly "+f);
 assert.match(retireRunner,/ROLLBACK;/);
 assert.doesNotMatch(retireRunner,/supabase db reset|supabase db push|apply_migration/i);
});
