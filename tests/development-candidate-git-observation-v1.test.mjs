import test from "node:test";
import assert from "node:assert/strict";
import {execFileSync} from "node:child_process";
import {mkdtempSync,mkdirSync,writeFileSync,symlinkSync,rmSync,readFileSync,readdirSync,statSync,realpathSync} from "node:fs";
import {tmpdir} from "node:os";
import {join,dirname} from "node:path";
import {canonicalPackageJSON,packageDigest,verifyReviewedPackage} from "../scripts/development-candidate-git-observation-v1.mjs";

import {verifyOwnerClonePackage,stageOwnerClonePackage} from "../scripts/development-owner-clone-request-v1.mjs";

function fixture(t) {
  const root=mkdtempSync(join(tmpdir(),"noel-package-test-"));
  t.after(()=>rmSync(root,{recursive:true,force:true}));
  const repositories={candidate:join(root,"candidate"),controller:join(root,"controller")};
  const git=(repo,...args)=>execFileSync("git",["-C",repo,...args],{stdio:["ignore","pipe","pipe"]}).toString().trim();
  for(const repo of Object.values(repositories)) {
    mkdirSync(repo);git(repo,"init","-q");git(repo,"config","user.email","fictional@example.invalid");git(repo,"config","user.name","Fictional test");
  }
  const assets=[
    ["migration","candidate","candidates/atlas/candidate.sql","SELECT 1;\n"],
    ["fixture","candidate","candidates/atlas/fixture.sql","SELECT 2;\n"],
    ["postconditions","controller","scripts/post.sql","SELECT 3;\n"],
    ["signed_probe","candidate","candidates/atlas/probe.py","raise RuntimeError('must never execute')\n"],
    ["trusted_helper","controller","scripts/helper.py","raise RuntimeError('must never execute')\n"]
  ].map(([role,origin,path,data])=>{
    const repo=repositories[origin],file=join(repo,path);mkdirSync(dirname(file),{recursive:true});writeFileSync(file,data);
    return {role,origin,path,blob:git(repo,"hash-object",path)};
  });
  const commit=repo=>{git(repo,"add","-A");git(repo,"commit","-qm","synthetic fixture");return git(repo,"rev-parse","HEAD");};
  const manifest={contract:"noel_candidate_package_v1",intent:"clone_only",lane:"atlas",scope:"atlas_fixture_clone_only_v1",
    profile:"local_signed_auth_rest_v1",candidate_sha:commit(repositories.candidate),controller_sha:commit(repositories.controller),assets};
  const bind=()=>({candidate_sha:manifest.candidate_sha,controller_sha:manifest.controller_sha,package_sha256:packageDigest(manifest)});
  const binding=bind();
  return {repositories,manifest,binding,bind,git,commit};
}
test("read exact committed objects, never execute probes or trust worktree",t=>{
  const {repositories,manifest,binding}=fixture(t);
  writeFileSync(join(repositories.candidate,manifest.assets[0].path),"dirty uncommitted content");
  const r=verifyReviewedPackage(manifest,binding,repositories);
  assert.equal(r.assets_verified,5);assert.equal(r.git_objects_verified,true);
  assert.equal(r.reviewed_binding_matched,true);assert.equal(r.authorization_verified,false);
  assert.equal(r.signed_proof_executed,false);assert.equal(r.release_authorized,false);
});
for(const [name,change,error] of [
  ["unreviewed package change",x=>x.manifest.scope="atlas_other_clone_only_v1",/binding mismatch/],
  ["controller selection change",x=>x.binding.controller_sha=x.manifest.candidate_sha,/binding mismatch/],
  ["missing independent binding",x=>x.binding=null,/binding mismatch/],
  ["substituted blob even with matching manifest digest",x=>{x.manifest.assets[0].blob="1".repeat(40);x.binding=x.bind();},/source mismatch/],
  ["missing path",x=>{x.manifest.assets[0].path="candidates/atlas/missing.sql";x.binding=x.bind();},/regular Git blob/],
  ["directory substituted for file",x=>{x.manifest.assets[0].path="candidates/atlas/dir.sql";const p=join(x.repositories.candidate,x.manifest.assets[0].path);mkdirSync(p);writeFileSync(join(p,"a"),"data");x.manifest.candidate_sha=x.commit(x.repositories.candidate);x.binding=x.bind();},/regular Git blob/],
  ["symlink in Git tree",x=>{const p=join(x.repositories.candidate,x.manifest.assets[0].path);rmSync(p);symlinkSync("fixture.sql",p);x.manifest.candidate_sha=x.commit(x.repositories.candidate);x.binding=x.bind();},/regular Git blob/],
  ["blob supplied as commit",x=>{x.manifest.candidate_sha=x.manifest.assets[0].blob;x.binding=x.bind();},/exact Git commit/],
  ["candidate-selected helper",x=>{x.manifest.assets[4].origin="candidate";x.manifest.assets[4].path="candidates/atlas/helper.py";x.binding=x.bind();},/helper must be trusted/],
  ["unrecognized command field",x=>{x.manifest.command="run arbitrary";x.binding=x.bind();},/manifest fields/],
  ["relative repository path",x=>x.repositories.candidate=".",/absolute repository/],
  ["empty committed blob",x=>{const a=x.manifest.assets[0];writeFileSync(join(x.repositories.candidate,a.path),"");a.blob=x.git(x.repositories.candidate,"hash-object",a.path);x.manifest.candidate_sha=x.commit(x.repositories.candidate);x.binding=x.bind();},/bounded size/]
]) test("refuses "+name,t=>{const x=fixture(t);change(x);assert.throws(()=>verifyReviewedPackage(x.manifest,x.binding,x.repositories),error);});

function ownerEvent(manifest,binding) {
  const repo="optical-lift/noel-core-db",owner="optical-lift",owner_id=290109753,repository_id=1346595523;
  const person={login:owner,id:owner_id};
  const context={event_name:"issues",ref:"refs/heads/main",repository:repo,repository_id,owner,owner_id,actor:owner,actor_id:owner_id,triggering_actor:owner,controller_sha:binding.controller_sha,workflow_ref:repo+"/.github/workflows/production-schema-clone-validation.yml@refs/heads/main"};
  const event={action:"opened",repository:{full_name:repo,id:repository_id,owner:{...person}},sender:{...person},issue:{state:"open",user:{...person},author_association:"OWNER",number:42,id:9001,title:"Production schema validation request: package "+manifest.scope,body:["diagnostic_scope: "+manifest.scope,"release_lane: "+manifest.lane,"production_target: zirqkouammpwxlqfbsvf","candidate_sha: "+binding.candidate_sha,"controller_sha: "+binding.controller_sha,"package_sha256: "+binding.package_sha256,"manifest_json: "+canonicalPackageJSON(manifest)].join("\n")}};
  return {context,event};
}
test("synthetic owner event through independent actual Git reader",t=>{
  const {manifest,binding,repositories}=fixture(t),{context,event}=ownerEvent(manifest,binding);
  const result=verifyOwnerClonePackage(event,context,repositories);
  assert.equal(result.status,"owner_and_source_binding_matched_only");
  assert.equal(result.execution_authorized,false);assert.equal(result.release_authorized,false);
});
test("reject manifest substitution despite valid original owner event",t=>{
  const {manifest,binding,repositories}=fixture(t),{context,event}=ownerEvent(manifest,binding);
  event.issue.body=event.issue.body.replace(manifest.assets[0].blob,"a".repeat(40));
  assert.throws(()=>verifyOwnerClonePackage(event,context,repositories),/owner clone request refused/);
});
test("reject event before touching Git when source repository is unavailable",t=>{
  const {manifest,binding}=fixture(t),{context,event}=ownerEvent(manifest,binding);
  event.sender.login="outsider";
  assert.throws(()=>verifyOwnerClonePackage(event,context,undefined),/owner clone request refused/);
});

function stagingParent(t) {
  const p=realpathSync(mkdtempSync(join(tmpdir(),"noel-stage-test-")));t.after(()=>rmSync(p,{recursive:true,force:true}));return p;
}
test("stage only immutable admitted bytes privately, never overwrite source or execute probes",t=>{
  const {manifest,binding,repositories}=fixture(t),{context,event}=ownerEvent(manifest,binding),parent=stagingParent(t);
  writeFileSync(join(repositories.candidate,manifest.assets[0].path),"uncommitted substitution");
  writeFileSync(join(repositories.candidate,"not-admitted.py"),"raise RuntimeError('never stage')");
  const result=stageOwnerClonePackage(event,context,repositories,parent);
  assert.equal(result.request.status,"owner_and_source_binding_matched_only");
  assert.equal(result.execution_authorized,false);assert.equal(result.release_authorized,false);
  assert.equal(result.files.length,5);assert.equal(statSync(result.root).mode&0o777,0o700);
  assert.equal(readFileSync(result.files[0].path,"utf8"),"SELECT 1;\n");
  for(const f of result.files) assert.equal(statSync(f.path).mode&0o777,0o600);
  assert.deepEqual(readdirSync(result.root).sort(),["candidate","controller"]);
  assert.deepEqual(readdirSync(join(result.root,"candidate","candidates","atlas")).sort(),["candidate.sql","fixture.sql","probe.py"]);
  assert.equal(readFileSync(join(repositories.candidate,manifest.assets[0].path),"utf8"),"uncommitted substitution");
  const next=stageOwnerClonePackage(event,context,repositories,parent);assert.notEqual(result.root,next.root);
});
test("no staging occurs for substituted bytes even with newly matched digest",t=>{
  const x=fixture(t),parent=stagingParent(t);x.manifest.assets[0].blob="1".repeat(40);
  const {context,event}=ownerEvent(x.manifest,x.bind());
  assert.throws(()=>stageOwnerClonePackage(event,context,x.repositories,parent),/source mismatch/);
  assert.deepEqual(readdirSync(parent),[]);
});
test("no staging occurs for valid digest but unapproved scope",t=>{
  const x=fixture(t),parent=stagingParent(t),{context,event}=ownerEvent(x.manifest,x.binding);
  event.issue.body=event.issue.body.replace('"scope":"atlas_fixture_clone_only_v1"','"scope":"atlas_other_clone_only_v1"');
  assert.throws(()=>stageOwnerClonePackage(event,context,x.repositories,parent),/refused/);
  assert.deepEqual(readdirSync(parent),[]);
});
test("refuses symbolic-link staging parent",t=>{
  const x=fixture(t),parent=stagingParent(t),{context,event}=ownerEvent(x.manifest,x.binding);
  const target=join(parent,"target"),link=join(parent,"link");mkdirSync(target);symlinkSync(target,link);
  assert.throws(()=>stageOwnerClonePackage(event,context,x.repositories,link),/real staging parent/);
  assert.deepEqual(readdirSync(target),[]);
});
