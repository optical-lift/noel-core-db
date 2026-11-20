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
 assert.equal([...s.matchAll(/CREATE FUNCTION public\./g)].length,2);
});
