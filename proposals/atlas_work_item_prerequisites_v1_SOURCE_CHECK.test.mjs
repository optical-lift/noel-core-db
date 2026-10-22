import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
const root=new URL("./",import.meta.url);
const read=name=>readFileSync(new URL(name,root),"utf8");
const sql=read("atlas_work_item_prerequisites_v1_REVIEW_ONLY.sql");
const graph=read("atlas_work_item_prerequisites_v1_CLONE_GRAPH_TEST.sql");
const post=read("atlas_work_item_prerequisites_v1_CLONE_POSTCONDITIONS.sql");

test("Postgres function bodies have balanced complete dollar-quote delimiters",()=>{
  assert.doesNotMatch(sql,/\bas \$(?!\$)/i,"Found malformed AS $ single delimiter");
  assert.doesNotMatch(sql,/(?:^|\n)\s*\$;/,"Found malformed lone $; function closer");
  const opens=[...sql.matchAll(/\bas \$\$/gi)].length;
  const closes=[...sql.matchAll(/\$\$;/g)].length;
  assert.ok(opens>=10,"Source contract expected named schema functions and public wrappers");
  assert.equal(opens,closes,"Each function AS $$ must have one $$; closer");
  assert.equal([...sql.matchAll(/\$\$/g)].length,opens+closes);
});
test("one existing source graph and same governing Ledger, not a parallel truth store",()=>{
  assert.match(sql,/insert into atlas\.work_item_relations\(/);
  assert.doesNotMatch(sql,/create table(?: if not exists)? atlas\.work_item_relations/);
  assert.match(sql,/company_work_native_ledger_owner_self_v1/);
  assert.match(sql,/work_prerequisite_ledger_scope_v1/);
  assert.match(sql,/Both Work records need current relevance to this governing Ledger/);
  assert.match(sql,/relation_kind='depends_on'/);
});
test("all existing depends_on writers share cycle guard and organizational lock",()=>{
  assert.match(sql,/create trigger guard_work_item_depends_on_cycle_v1/);
  assert.match(sql,/before insert or update of organization_id,from_work_item_id,/);
  assert.match(sql,/pg_catalog\.pg_advisory_xact_lock/);
  assert.match(sql,/with recursive walk/);
  assert.match(sql,/new\.from_work_item_id=new\.to_work_item_id/);
  assert.match(graph,/C->A is a cycle/);
  assert.match(graph,/reactivation should not bypass cycle guard/);
  assert.match(graph,/completion_bundle_member/);
});
test("audit table is append-only, private, source-action-bound and rereadable",()=>{
  assert.match(sql,/create table if not exists atlas\.work_item_prerequisite_events_v1/);
  assert.match(sql,/unique\(actor_person_id,source_action_id\)/);
  assert.match(sql,/request_fingerprint<>v_fingerprint/);
  assert.match(sql,/create trigger guard_work_item_prerequisite_event_immutable_v1/);
  assert.match(sql,/before update or delete on atlas\.work_item_prerequisite_events_v1/);
  assert.match(sql,/atlas_work_prerequisite_event_self_api_v1/);
  assert.match(sql,/recordedEventId/);
  assert.match(graph,/REJECT: audit history UPDATE admitted/);
  assert.match(graph,/REJECT: audit history DELETE admitted/);
  assert.match(post,/guard_work_item_prerequisite_event_immutable_v1/);
});
test("only authenticated owner-wrapped RPCs; never expose private tables",()=>{
  assert.match(sql,/revoke all on atlas\.work_item_prerequisite_events_v1 from public,anon,authenticated/);
  for(const api of [
    "atlas_work_prerequisite_candidates_self_api_v1",
    "atlas_work_prerequisites_self_api_v1",
    "atlas_work_prerequisite_event_self_api_v1",
    "atlas_set_work_prerequisite_self_api_v1",
  ]){
    assert.ok(sql.includes("public."+api),"Missing public wrapper "+api);
    assert.match(sql,new RegExp("revoke all on function public\\."+api+"\\("));
    assert.match(sql,new RegExp("grant execute on function public\\."+api+"\\("));
  }
  assert.match(post,/has_function_privilege/);
  assert.match(post,/has_table_privilege/);
});
test("clone fixtures use generated data and irrevocably roll back",()=>{
  assert.match(graph,/^begin;/m);
  assert.match(graph,/^rollback;/m);
  assert.doesNotMatch(graph,/\bcommit\s*;/i);
  assert.match(graph,/gen_random_uuid\(\)/);
  assert.doesNotMatch(sql,/\binsert into atlas\.(?:work_items|organizations)\(/);
});
