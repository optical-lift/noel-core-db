import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
const source=readFileSync(new URL("../candidates/atlas_universal_continuing_original_work_v1/19_connected_person_disclosed_standing_rhythms_v1.sql",import.meta.url),"utf8");
test("standing rhythm list needs signed exact Ledger, native scope, and two disclosures",()=>{
 for(const key of [
   "auth.uid()","current_person_id_v1","current_active_ledger_seat_v1",
   "person_has_native_ledger_connection_v1",
   "continuing_work_source_governance_events_v1",
   "ORDER BY e.recorded_at DESC,e.id DESC LIMIT 1",
   "accepted_by_person_id=v_person","worker_membership_id IS NULL",
   "scope.coverage_mode='ledger_all_work'",
   "policy.authorization_method='standing_source_observed'",
   "policy.worker_visibility='eligible_disclosed'",
   "'identity')","'condition')","s.state <> 'paused'"
 ])assert.ok(source.includes(key),"missing "+key);
});
test("expectation reader neither makes Work nor invents date or unseen counts",()=>{
 assert.doesNotMatch(source,/^\s*(INSERT|UPDATE|DELETE|TRUNCATE)\s/mi);
 for(const key of ["LIMIT (p_limit+1)","noUndisclosedCounts","noWorkCreated",
   "notAnExecutionPlan","notAnAutomaticOverdueBacklog"])
   assert.ok(source.includes(key),"missing "+key);
});
test("public seam is auth-only and internal function is not exposed",()=>{
 assert.match(source,/REVOKE ALL ON FUNCTION atlas.connected_person_disclosed_standing_rhythms_self_api_v1/);
 assert.match(source,/REVOKE ALL ON FUNCTION public.connected_person_disclosed_standing_rhythms_self_api_v1/);
 assert.match(source,/GRANT EXECUTE ON FUNCTION public.connected_person_disclosed_standing_rhythms_self_api_v1/);
 assert.match(source,/TO authenticated;/);
});
