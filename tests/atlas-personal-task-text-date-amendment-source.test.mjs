import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
const base=new URL("../candidates/atlas_personal_task_text_date_amendment_v1/",import.meta.url);
const sql=readFileSync(new URL("candidate.sql",base),"utf8");
const post=readFileSync(new URL("postconditions.sql",base),"utf8");
const notes=readFileSync(new URL("README.md",base),"utf8");
test("source-only atomic personal task amendment without replacing Work",()=>{
 assert.match(sql,/^-- Source-only candidate/);
 assert.match(sql,/BEGIN;[\s\S]*COMMIT;/);
 assert.equal((sql.match(/CREATE FUNCTION atlas\./g)||[]).length,3);
 assert.equal((sql.match(/CREATE FUNCTION public\./g)||[]).length,2);
 assert.doesNotMatch(sql,/INSERT INTO atlas\.task_entries|UPDATE atlas\.work_items|DROP TABLE|TRUNCATE/);
});
test("serialized source owner, stale revision and transfer protection",()=>{
 for(const x of ["FOR UPDATE","require_active_task_principal_v1",
 "owner_user_id=auth.uid()","principal_id=v_principal",
 "amendment_revision<>p_expected_revision","v_old.status<>'open'",
 "v_old.archived_at IS NOT NULL","source_object_type='personal_dated_task'",
 "'noInstitutionalWorkChanged',true","'oneOriginalTaskId',true"])
 assert.ok(sql.includes(x),x);
});
test("grants, private event cleanup, and public invoker transport",()=>{
 assert.match(sql,/REFERENCES atlas\.task_entries\(id\) ON DELETE CASCADE/);
 assert.match(sql,/BEFORE UPDATE ON atlas\.personal_task_amendment_events_v1/);
 assert.match(sql,/ENABLE ROW LEVEL SECURITY/);
 assert.equal((sql.match(/FROM PUBLIC,anon,authenticated;/g)||[]).length,6);
 assert.equal((sql.match(/TO authenticated;/g)||[]).length,4);
 assert.match(sql,/LANGUAGE sql STABLE SECURITY INVOKER/);
 assert.match(sql,/LANGUAGE sql VOLATILE SECURITY INVOKER/);
 assert.match(post,/confdeltype='c'/);
});
test("protected source release is explicitly incomplete",()=>{
 assert.match(notes,/signed GoTrue\/PostgREST/);
 assert.match(notes,/separately authorized protected production release/);
 assert.match(notes,/permanent deletion after amendment/);
});
