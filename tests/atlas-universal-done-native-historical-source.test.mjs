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
