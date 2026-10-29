import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
const base=new URL("../candidates/atlas_work_self_assignment_native_v1/",import.meta.url);
const candidate=readFileSync(new URL("candidate.sql",base),"utf8");
const fixture=readFileSync(new URL("fixture.sql",base),"utf8");
const checks=readFileSync(new URL("postconditions.sql",base),"utf8");
const signed=readFileSync(new URL("../scripts/validate-atlas-work-self-assignment-signed-http.py",import.meta.url),"utf8");
test("exactly two complete PL/pgSQL CREATE statements under source snapshot guards",()=>{
  assert.equal((candidate.match(/CREATE OR REPLACE FUNCTION atlas\./g)||[]).length,2);
  assert.equal((candidate.match(/\$function\$;/g)||[]).length,2);
  assert.equal((candidate.match(/AS \$function\$/g)||[]).length,2);
  assert.match(candidate,/BEGIN;[\s\S]*DO \$source_guard\$/);
  assert.match(candidate,/\$source_guard\$;[\s\S]*COMMIT;/);
  assert.match(candidate,/98d5daf1edf7a62da1e161d5cfa9e61f/);
  assert.match(candidate,/22317b744f4c82fcf58562d3fb1934df/);
  assert.doesNotMatch(candidate,/e\.id<>v_self|v_owner=p_target_person_id/);
});
test("native Person and Work authority remains source-enforced",()=>{
  for(const fragment of [
    "atlas.current_active_ledger_seat_v1","atlas.company_work_native_ledger_owner_self_v1",
    "atlas.person_has_native_ledger_connection_v1","work_decomposition_groups",
    "company_work_native_ledger_relevance","Another live responsibility or decision exists",
    "work_execution_plans","sourceActionId"
  ])assert.ok(candidate.includes(fragment),fragment);
  assert.doesNotMatch(candidate,/\bGRANT\b|\bDROP\b|\bTRUNCATE\b/i);
  assert.match(checks,/prosecdef/);
});
test("disposable fixture and genuine signed test are present and bound locally",()=>{
 assert.match(fixture,/INSERT INTO atlas\.work_decomposition_groups/i);
 assert.match(fixture,/INSERT INTO atlas\.work_decomposition_members/i);
 assert.match(fixture,/INSERT INTO atlas\.company_work_native_ledger_relevance/i);
 assert.match(signed,/c1\.sign_in\(/);
 assert.match(signed,/c1\.local_status\(/);
 assert.match(signed,/127\[\.\]0\[\.\]0\[\.\]1/);
 assert.match(signed,/delete from auth\.sessions/);
 assert.match(signed,/status!=404/);
 assert.match(signed,/idempotent/);
});

test("clone runner admits signed self-assignment only for the exact governed migration",()=>{
 const runner=readFileSync(new URL("../scripts/validate-production-schema-clone.sh",import.meta.url),"utf8");
 assert.match(runner,/signed_work_self_assignment_probe=false/);
 assert.match(runner,/atlas_work_self_assignment_native_v1\[/);
 assert.match(runner,/signed_work_self_assignment_probe=true/);
 assert.match(runner,/validate-atlas-work-self-assignment-signed-http\.py/);
 assert.match(runner,/signed-work-self-assignment-summary\.txt/);
 assert.match(runner,/\[ "\$signed_work_self_assignment_probe" = true \]/);
});
