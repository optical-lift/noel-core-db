import test from "node:test";
import assert from "node:assert/strict";
import {execFileSync} from "node:child_process";
import {mkdtempSync,mkdirSync,writeFileSync,symlinkSync,rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join,dirname} from "node:path";
import {packageDigest,verifyReviewedPackage} from "../scripts/development-candidate-git-observation-v1.mjs";

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
