import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
const s=readFileSync(new URL("./candidate.sql",import.meta.url),"utf8");
test("single transactional adapter over both existing writers, not a new source",()=>{
 assert.match(s,/BEGIN;/);assert.match(s,/COMMIT;/);
 assert.match(s,/atlas\.create_atlas_task_self_api_v1\(p_sentence,p_due_date/);
 assert.match(s,/atlas\.change_personal_task_assignment_self_api_v1\(v_id,0,/);
 assert.match(s,/personal_task_connection_peers_v1\(auth\.uid\(\)\)/);
 assert.match(s,/personal_task_ready_person_v1\(auth\.uid\(\)\)/);
 assert.match(s,/daily:connected:/);
 assert.doesNotMatch(s,/CREATE TABLE|INSERT INTO atlas\.task_entries|GRANT .* TO anon/i);
 assert.equal([...s.matchAll(/CREATE FUNCTION public\./g)].length,3);
});

test("self Ledger uses existing authoritative commands and never peer dispatch",()=>{
 assert.match(s,/capability_root_authority_context_self_v1\(p_ledger_id\)/);
 assert.match(s,/record_ledger_work_self_api_v2\(p_ledger_id,p_sentence,p_execution_date/);
 assert.match(s,/work_focus_owner_reassign_direct_self_api_v1\(v_org,p_ledger_id,v_id,NULL,/);
 assert.match(s,/connected_person_place_work_self_api_v1\(v_id,p_execution_date/);
 assert.match(s,/IF v_intake->>'createdNow'='true' THEN/);
 assert.doesNotMatch(s,/connected_ledger_direct_assign_self_api_v1|INSERT INTO atlas\.work_items/);
});
