// Offline trusted-controller primitive. Never checks out or executes a candidate.
// Repositories and reviewed binding MUST come from the trusted caller, not the package.
// The existing owner/event gate must authenticate the request independently.
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { isAbsolute, join, dirname } from "node:path";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, realpathSync, statSync } from "node:fs";
import { inspectCandidatePackage } from "./development-candidate-admission-v1.mjs";

const hash = (algorithm,bytes) => createHash(algorithm).update(bytes).digest("hex");
const sha = x => typeof x === "string" && /^[0-9a-f]{40}$/.test(x);
const canonical = x => Array.isArray(x) ? x.map(canonical) : x !== null && typeof x === "object" ?
  Object.fromEntries(Object.keys(x).sort().map(k=>[k,canonical(x[k])])) : x;
export const canonicalPackageJSON = manifest => JSON.stringify(canonical(manifest));
export const packageDigest = manifest => hash("sha256",canonicalPackageJSON(manifest));
const MAX_BLOB = 4*1024*1024;

function git(repo,args) {
  if (typeof repo !== "string" || !isAbsolute(repo)) throw Error("trusted absolute repository path required");
  return execFileSync("git",["--no-replace-objects","-C",repo,...args],{
    env:{PATH:process.env.PATH, GIT_CONFIG_NOSYSTEM:"1",GIT_CONFIG_GLOBAL:"/dev/null",
      GIT_LITERAL_PATHSPECS:"1",GIT_NO_LAZY_FETCH:"1",GIT_TERMINAL_PROMPT:"0",GIT_OPTIONAL_LOCKS:"0"},
    timeout:10000,maxBuffer:MAX_BLOB+1024,stdio:["ignore","pipe","pipe"]});
}
function observe(repo,commit,asset) {
  if (!sha(commit) || git(repo,["cat-file","-t",commit]).toString().trim()!=="commit") throw Error("exact Git commit required");
  const entry=git(repo,["ls-tree","-z","--full-tree",commit,"--",asset.path]).toString("utf8");
  const m=/^(100644|100755) blob ([0-9a-f]{40})\t([^\0]+)\0$/.exec(entry);
  if (!m || m[3]!==asset.path) throw Error("exact regular Git blob required");
  const size=Number(git(repo,["cat-file","-s",m[2]]).toString().trim());
  if (!Number.isSafeInteger(size) || size<=0 || size>MAX_BLOB) throw Error("blob outside bounded size");
  const bytes=git(repo,["cat-file","blob",m[2]]);
  const calculated=hash("sha1",Buffer.concat([Buffer.from("blob "+bytes.length+"\0"),bytes]));
  if (bytes.length!==size || calculated!==m[2]) throw Error("Git blob bytes mismatch");
  return {observation:{origin:asset.origin,commit,path:asset.path,blob:calculated,mode:m[1]},bytes};
}
function readReviewedPackage(manifest,binding,repositories) {
  // Structural preflight only: synthetic observations are deliberately discarded.
  if (!Array.isArray(manifest?.assets) || manifest.assets.length>16) throw Error("invalid package assets");
  inspectCandidatePackage(manifest,manifest.assets.map(a=>({origin:a.origin,path:a.path,blob:a.blob,
    commit:a.origin==="candidate"?manifest.candidate_sha:manifest.controller_sha,mode:"100644"})));
  if (!binding || !sha(binding.controller_sha) || !sha(binding.candidate_sha) ||
      binding.controller_sha!==manifest.controller_sha || binding.candidate_sha!==manifest.candidate_sha ||
      typeof binding.package_sha256!=="string" || !/^[0-9a-f]{64}$/.test(binding.package_sha256) ||
      binding.package_sha256!==packageDigest(manifest)) throw Error("independent reviewed binding mismatch");
  const observed=manifest.assets.map(a=>observe(repositories[a.origin],
    a.origin==="candidate"?binding.candidate_sha:binding.controller_sha,a));
  const identity={...inspectCandidatePackage(manifest,observed.map(o=>o.observation)),package_sha256:binding.package_sha256,
    reviewed_binding_matched:true,git_objects_verified:true};
  return {identity,observed};
}

export function verifyReviewedPackage(manifest,binding,repositories) {
  return readReviewedPackage(manifest,binding,repositories).identity;
}

// Private staging only: no execution, registration, or promotion of these bytes.
// The parent is selected by the trusted carrier; never by the request or package.
export function stageReviewedPackage(manifest,binding,repositories,parent) {
  const {identity,observed}=readReviewedPackage(manifest,binding,repositories);
  if(typeof parent!=="string"||!isAbsolute(parent)||realpathSync(parent)!==parent||!statSync(parent).isDirectory())
    throw Error("trusted real staging parent required");
  const root=mkdtempSync(join(parent,"noel-clone-package-"));
  try {
    const files=observed.map(({observation,bytes},index)=>{
      const path=join(root,observation.origin,observation.path);
      mkdirSync(dirname(path),{recursive:true,mode:0o700});
      writeFileSync(path,bytes,{flag:"wx",mode:0o600});
      return {role:manifest.assets[index].role,origin:observation.origin,path,blob:observation.blob};
    });
    return {identity,root,files,execution_authorized:false,release_authorized:false};
  } catch(error) {
    rmSync(root,{recursive:true,force:true});throw error;
  }
}
