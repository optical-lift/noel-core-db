import test from "node:test";
import assert from "node:assert/strict";
import { inspectCandidatePackage } from "../scripts/development-candidate-admission-v1.mjs";

// Historical pins transcribed from the existing protected workflow at the
// controller commit. These test observations are fictional input records,
// not live Git queries, authorization, or a repeated protected proof.
const controller = "2ceb6a6a4acbac2379b75060f8a137e31434d18e";
const helper = {role:"trusted_helper",origin:"controller",path:"scripts/validate-atlas-c1-signed-http.py",blob:"1b82e698705e473280f1fc55b0e762bce243effb"};
const asset = (role,origin,path,blob)=>({role,origin,path,blob});
const base = (lane,scope,candidate_sha,assets)=>({contract:"noel_candidate_package_v1",intent:"clone_only",lane,scope,profile:"local_signed_auth_rest_v1",candidate_sha,controller_sha:controller,assets});
const course = base("shared","shared_private_course_working_loop_clone_only_v1","0fd98326892e9ed4cf22c15e572882fe97d3e383",[
  asset("migration","candidate","candidates/shared-private-course-working-loop-validation-v1/combined_candidate.sql","33aa73e850a22eeecabcb456dc67523c7d351370"),
  asset("postconditions","controller","scripts/private-course-working-loop-postconditions.sql","43820e70118372c2974a747c4b86a149107e895d"),
  asset("signed_probe","controller","scripts/validate-private-course-working-loop-signed-http.py","5ee0d666be7bddacb91a4a362e1cb24823c4f5f8"),helper]);
const dir="candidates/atlas/atlas_task_initial_details_v1/";
const details=base("atlas","atlas_task_initial_details_clone_only_v1","563e24c5b9b42094d8f94a599c6d46de53e566d4",[
  asset("migration","candidate",dir+"candidate.sql","493836a06949401d067f444d2729366239292588"),
  asset("fixture","candidate",dir+"fixture.sql","01d36beb7116e7fd7c27c89e9d5dfb2c9d6a3f9f"),
  asset("postconditions","candidate",dir+"postconditions.sql","a6cd2160b7a14832c3390921d2e9aeced5d58f43"),
  asset("signed_probe","candidate",dir+"validate_signed_initial_details.py","1f60014949cd290a3e517a954fb5291634f711e4"),helper,
  asset("trusted_helper","controller","scripts/validate-atlas-work-prerequisite-signed-http.py","eb3bbfb45848a7fca90cc503e153f1451d8d7471")]);
const observations = m=>m.assets.map(({origin,path,blob})=>({origin,path,blob,commit:origin==="candidate"?m.candidate_sha:m.controller_sha,mode:"100644"}));
for(const m of [course,details]) test("historical package shape: "+m.scope,()=>{
  const r=inspectCandidatePackage(m,observations(m));
  assert.equal(r.assets_verified,m.assets.length);
  assert.equal(r.status,"source_identity_matched_only");
  for(const k of ["authorization_verified","signed_proof_executed","release_authorized"]) assert.equal(r[k],false);
});
const cases=[
 ["mutable candidate",m=>m.candidate_sha="main"],
 ["mutable controller",m=>m.controller_sha="main"],
 ["production intent",m=>m.intent="release"],
 ["scope/lane mismatch",m=>m.lane="atlas"],
 ["command injection",m=>m.command="python arbitrary.py"],
 ["unknown profile",m=>m.profile="arbitrary"],
 ["unknown asset field",m=>m.assets[0].command="run"],
 ["path traversal",m=>m.assets[0].path="candidates/../scripts/a.sql"],
 ["production migration path",m=>m.assets[0].path="supabase/migrations/a.sql"],
 ["candidate helper",m=>{m.assets[3].origin="candidate";m.assets[3].path="candidates/helper.py"}],
 ["duplicate asset",m=>m.assets.push(m.assets[0])],
 ["missing signed test",m=>m.assets=m.assets.filter(a=>a.role!=="signed_probe")],
 ["unexpected observation",(_,o)=>o.push(o[0])],
 ["substituted bytes",(_,o)=>o[0].blob="0".repeat(40)],
 ["wrong commit",(_,o)=>o[0].commit="0".repeat(40)],
 ["symlink",(_,o)=>o[0].mode="120000"],
 ["missing observation",(_,o)=>o.pop()],
 ["duplicate observation",(_,o)=>o[1]=o[0]]
];
for(const [name,change] of cases) test("refuses "+name,()=>{
  const m=structuredClone(course),o=observations(m);change(m,o);
  assert.throws(()=>inspectCandidatePackage(m,o));
});
