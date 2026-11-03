import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

const base=new URL("../candidates/atlas_personal_task_progress_original_v1/",import.meta.url);
const sql=readFileSync(new URL("candidate.sql",base),"utf8");
const post=readFileSync(new URL("postconditions.sql",base),"utf8");
const readme=readFileSync(new URL("README.md",base),"utf8");

test("one original personal task owns the progress event, no new Task or Company Work",()=>{
  assert.match(sql,/^-- Source-only Atlas original personal-task progress/);
  assert.match(sql,/BEGIN;[\s\S]*COMMIT;\s*$/);
  assert.match(sql,/task_id uuid NOT NULL REFERENCES atlas\.task_entries\(id\) ON DELETE CASCADE/);
  assert.match(sql,/CONSTRAINT personal_task_progress_owner_action_v1 UNIQUE\(owner_user_id,source_action_id\)/);
  assert.doesNotMatch(sql,/(INSERT INTO atlas\.task_entries|UPDATE atlas\.work_items|DROP TABLE|TRUNCATE)/);
  assert.match(sql,/'oneOriginalTaskId',true/);
  assert.match(sql,/'noInstitutionalWorkChanged',true/);
});
test("append and read are exact active owner, Principal and original Work-custody guarded",()=>{
  for(const part of [
    "require_active_task_principal_v1","owner_user_id=auth.uid()",
    "t.principal_id=v_principal FOR UPDATE",
    "v_task.status<>'open'","v_task.archived_at IS NOT NULL",
    "source_object_type='personal_dated_task'","source_object_id=v_task.id",
    "p_source_action_id","v_prior.note=v_text","ERRCODE='PT409'",
    "recorded_at DESC,id DESC",
  ])assert.ok(sql.includes(part),part);
});
test("immutable privately guarded progress and source-qualified public transport",()=>{
  assert.match(sql,/ENABLE ROW LEVEL SECURITY/);
  assert.match(sql,/BEFORE UPDATE ON atlas\.personal_task_progress_events_v1/);
  assert.match(sql,/REVOKE ALL ON atlas\.personal_task_progress_events_v1 FROM PUBLIC,anon,authenticated/);
  assert.match(sql,/CREATE FUNCTION public\.append_personal_task_progress_self_api_v1/);
  assert.match(sql,/CREATE FUNCTION public\.read_personal_task_progress_self_api_v1/);
  assert.match(sql,/SECURITY INVOKER SET search_path TO ''/);
  assert.equal((sql.match(/GRANT EXECUTE ON FUNCTION public\./g)||[]).length,2);
  assert.match(post,/confdeltype='c'/);
  assert.match(post,/prosecdef AND provolatile='s'/);
  assert.match(post,/has_function_privilege\('anon',pw,'EXECUTE'\)/);
  assert.match(post,/personal_task_progress_owner_action_v1/);
});
test("paginated history and idempotent retry do not claim Done or hide earlier entries",()=>{
  for(const fragment of [
    "p_limit NOT BETWEEN 1 AND 100",
    "p_before_recorded_at","p_before_id",
    "e.recorded_at,e.id","LIMIT p_limit+1",
    "'hasMore',v_more","'nextCursor'",
    "'idempotent',true","'idempotent',false",
    "'contractVersion','personal_task_progress_append_v1'",
    "'contractVersion','personal_task_progress_read_v1'",
  ])assert.ok(sql.includes(fragment),fragment);
  assert.doesNotMatch(sql,/SET status=|work_state='completed'/);
  assert.match(readme,/Cancel, Blocked and Unable status/);
  assert.match(readme,/genuine separate local GoTrue sessions/);
});
