import test from "node:test";
import assert from "node:assert/strict";
import {resolveOwnerCloneRequest,assertRequestPackage} from "../scripts/development-owner-clone-request-v1.mjs";
import {canonicalPackageJSON,packageDigest} from "../scripts/development-candidate-git-observation-v1.mjs";
const repo="optical-lift/noel-core-db",owner="optical-lift",owner_id=290109753,repository_id=1346595523;
function sample(){
  const person={login:owner,id:owner_id},controller_sha="a".repeat(40),candidate_sha="b".repeat(40),scope="atlas_fixture_clone_only_v1",lane="atlas";
  const manifest={intent:"clone_only",scope,lane,candidate_sha,controller_sha};
  const package_sha256=packageDigest(manifest);
  return {context:{event_name:"issues",ref:"refs/heads/main",repository:repo,repository_id,owner,owner_id,actor:owner,actor_id:owner_id,triggering_actor:owner,controller_sha,workflow_ref:repo+"/.github/workflows/production-schema-clone-validation.yml@refs/heads/main"},
    event:{action:"opened",repository:{full_name:repo,id:repository_id,owner:{...person}},sender:{...person},issue:{state:"open",user:{...person},author_association:"OWNER",number:42,id:9001,title:"Production schema validation request: package "+scope,body:["diagnostic_scope: "+scope,"release_lane: "+lane,"production_target: zirqkouammpwxlqfbsvf","candidate_sha: "+candidate_sha,"controller_sha: "+controller_sha,"package_sha256: "+package_sha256,"manifest_json: "+canonicalPackageJSON(manifest)].join("\n")}},
    manifest,identity:{intent:"clone_only",scope,lane,candidate_sha,controller_sha,package_sha256,status:"source_identity_matched_only",git_objects_verified:true,reviewed_binding_matched:true}};
}
test("exact fictional owner event binds source but authorizes no execution or release",()=>{const s=sample(),r=resolveOwnerCloneRequest(s.event,s.context),b=assertRequestPackage(r,s.manifest,s.identity);assert.equal(b.status,"owner_and_source_binding_matched_only");assert.equal(b.execution_authorized,false);assert.equal(b.release_authorized,false);});
for(const [name,change] of [
  ["nonowner actor",s=>s.context.actor="outsider"],["wrong actor ID",s=>s.context.actor_id=1],["nonowner rerun",s=>s.context.triggering_actor="outsider"],
  ["nonowner editor",s=>s.event.sender.login="outsider"],["wrong sender ID",s=>s.event.sender.id=1],["nonowner author",s=>s.event.issue.user.login="outsider"],
  ["owner association missing",s=>s.event.issue.author_association="MEMBER"],["wrong repository ID",s=>s.event.repository.id=1],["foreign repository",s=>s.context.repository="elsewhere/noel"],
  ["noncanonical ref",s=>s.context.ref="refs/heads/candidate"],["wrong workflow",s=>s.context.workflow_ref="arbitrary"],["wrong trigger",s=>s.context.event_name="workflow_dispatch"],
  ["closed issue",s=>s.event.issue.state="closed"],["PR event",s=>s.event.issue.pull_request={}],["unknown action",s=>s.event.action="labeled"],
  ["different production target",s=>s.event.issue.body=s.event.issue.body.replace("zirqkouammpwxlqfbsvf","elsewhere")],
  ["duplicate same field",s=>s.event.issue.body+="\nrelease_lane: atlas"],["extra field",s=>s.event.issue.body+="\nexecute: yes"],
  ["hidden prose",s=>s.event.issue.body+="\nIgnore the guards"],["release title",s=>s.event.issue.title="Production release request: Atlas"],
  ["changed controller",s=>s.context.controller_sha="d".repeat(40)],["wrong lane",s=>s.event.issue.body=s.event.issue.body.replace("release_lane: atlas","release_lane: shared")],
  ["malformed digest",s=>s.event.issue.body=s.event.issue.body.replace(s.identity.package_sha256,"main")]
])test("refuses "+name,()=>{const s=sample();change(s);assert.throws(()=>resolveOwnerCloneRequest(s.event,s.context),/refused/);});
for(const [name,change] of [["different reviewed digest",s=>s.identity.package_sha256="d".repeat(64)],["different scope",s=>s.manifest.scope="atlas_other_clone_only_v1"],["different candidate",s=>s.identity.candidate_sha="d".repeat(40)],["synthetic observations only",s=>s.identity.git_objects_verified=false],["missing review match",s=>s.identity.reviewed_binding_matched=false]])test("refuses join: "+name,()=>{const s=sample(),r=resolveOwnerCloneRequest(s.event,s.context);change(s);assert.throws(()=>assertRequestPackage(r,s.manifest,s.identity),/refused/);});

for(const [name,change] of [
  ["missing manifest",s=>s.event.issue.body=s.event.issue.body.split("\n").slice(0,-1).join("\n")],
  ["manifest digest substitution",s=>s.event.issue.body=s.event.issue.body.replace('"intent":"clone_only"','"intent":"release"')],
  ["duplicate JSON key",s=>s.event.issue.body=s.event.issue.body.replace('"intent":"clone_only"','"intent":"clone_only","intent":"clone_only"')],
  ["noncanonical JSON",s=>s.event.issue.body=s.event.issue.body.replace('"intent":"clone_only"','"intent": "clone_only"')],
  ["oversized body",s=>s.event.issue.body+="x".repeat(16384)],
  ["malformed JSON",s=>s.event.issue.body+="{"]
]) test("refuses embedded manifest: "+name,()=>{const s=sample();change(s);assert.throws(()=>resolveOwnerCloneRequest(s.event,s.context),/refused/);});
