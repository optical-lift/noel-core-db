// Source-only resolver. Caller must supply authentic GitHub event/context from
// the existing canonical owner-gated workflow; a JSON fixture proves no authority.
import { verifyReviewedPackage, stageReviewedPackage, canonicalPackageJSON, packageDigest } from "./development-candidate-git-observation-v1.mjs";
const sha = x=>typeof x==="string"&&/^[0-9a-f]{40}$/.test(x);
const digest = x=>typeof x==="string"&&/^[0-9a-f]{64}$/.test(x);
const positive = x=>Number.isSafeInteger(x)&&x>0;
const fail = ()=>{throw Error("Exact owner clone request refused");};
export function resolveOwnerCloneRequest(event,context) {
  const i=event?.issue, r=event?.repository, sender=event?.sender;
  if(context?.event_name!=="issues"||context.ref!=="refs/heads/main"||
     context.repository!=="optical-lift/noel-core-db"||context.repository_id!==1346595523||
     context.owner!=="optical-lift"||context.owner_id!==290109753||
     context.actor!==context.owner||context.actor_id!==context.owner_id||
     context.triggering_actor!==context.owner||!sha(context.controller_sha)||
     context.workflow_ref!==context.repository+"/.github/workflows/production-schema-clone-validation.yml@refs/heads/main"||
     !["opened","edited","reopened"].includes(event?.action)||
     r?.full_name!==context.repository||r.id!==context.repository_id||r.owner?.login!==context.owner||r.owner.id!==context.owner_id||
     sender?.login!==context.owner||sender.id!==context.owner_id||
     i?.user?.login!==context.owner||i.user.id!==context.owner_id||i.author_association!=="OWNER"||
     i.state!=="open"||i.pull_request!==undefined||!positive(i.number)||!positive(i.id)||
     typeof i.body!=="string"||i.body.length>16384) fail();
  const fields=Object.create(null);
  const required=["diagnostic_scope","release_lane","production_target","candidate_sha","controller_sha","package_sha256"];
  const lines=i.body.trim().split(/\r?\n/);
  const manifestLine=lines.pop();
  if(!manifestLine.startsWith("manifest_json: ")) fail();
  const json=manifestLine.slice("manifest_json: ".length);
  let manifest;
  try {manifest=JSON.parse(json);} catch {fail();}
  if(!manifest||Array.isArray(manifest)||typeof manifest!=="object") fail();
  try {if(canonicalPackageJSON(manifest)!==json) fail();} catch {fail();}
  for(const line of lines) {
    const m=/^([a-z_][a-z_0-9]*): ([a-z0-9_]+)$/.exec(line);
    if(!m||!required.includes(m[1])||Object.hasOwn(fields,m[1])) fail();
    fields[m[1]]=m[2];
  }
  if(Object.keys(fields).length!==required.length||!required.every(k=>Object.hasOwn(fields,k))||
     !["atlas","titus","wnph","noel","shared"].includes(fields.release_lane)||
     !/^[a-z][a-z0-9_]{1,100}_clone_only_v1$/.test(fields.diagnostic_scope)||
     !fields.diagnostic_scope.startsWith(fields.release_lane+"_")||
     fields.production_target!=="zirqkouammpwxlqfbsvf"||!sha(fields.candidate_sha)||
     fields.controller_sha!==context.controller_sha||!digest(fields.package_sha256)||
     i.title!=="Production schema validation request: package "+fields.diagnostic_scope||
     manifest.intent!=="clone_only"||manifest.scope!==fields.diagnostic_scope||manifest.lane!==fields.release_lane||
     manifest.candidate_sha!==fields.candidate_sha||manifest.controller_sha!==fields.controller_sha||
     packageDigest(manifest)!==fields.package_sha256) fail();
  return Object.freeze({intent:"clone_only",lane:fields.release_lane,scope:fields.diagnostic_scope,
    candidate_sha:fields.candidate_sha,controller_sha:fields.controller_sha,package_sha256:fields.package_sha256,
    request_issue:i.number,request_id:i.id,owner_id:context.owner_id,manifest,
    status:"owner_event_binding_matched_only",release_authorized:false,execution_authorized:false});
}
// A matching event still cannot authorize runtime execution until the existing
// environment gate, independent source inspection and isolation gates pass.
export function assertRequestPackage(request,manifest,identity) {
  if(request?.status!=="owner_event_binding_matched_only"||request.intent!=="clone_only"||
     identity?.status!=="source_identity_matched_only"||identity.git_objects_verified!==true||identity.reviewed_binding_matched!==true||
     ![manifest,identity].every(x=>x?.intent===request.intent&&x.lane===request.lane&&x.scope===request.scope&&
       x.candidate_sha===request.candidate_sha&&x.controller_sha===request.controller_sha)||
     request.package_sha256!==identity.package_sha256) fail();
  return Object.freeze({...request,status:"owner_and_source_binding_matched_only"});
}

// Caller fetches this current issue independently from GitHub, not the event.
// A revoked or replaced request may not be replayed from an old workflow event.
export function assertCurrentOwnerIssue(event,currentIssue) {
  const i=event?.issue,c=currentIssue;
  if(!i||!c||c.state!=="open"||c.pull_request!==undefined||
     c.id!==i.id||c.number!==i.number||c.title!==i.title||c.body!==i.body||
     c.author_association!=="OWNER"||c.user?.id!==i.user?.id||c.user?.login!==i.user?.login) fail();
}

// The trusted entry point never accepts a caller-supplied identity receipt.
export function verifyOwnerClonePackage(event,context,currentIssue,repositories) {
  const request=resolveOwnerCloneRequest(event,context),manifest=request.manifest;
  assertCurrentOwnerIssue(event,currentIssue);
  const identity=verifyReviewedPackage(manifest,request,repositories);
  return assertRequestPackage(request,manifest,identity);
}

// Resolve real event provenance before observing or staging anything.
export function stageOwnerClonePackage(event,context,currentIssue,repositories,parent) {
  const request=resolveOwnerCloneRequest(event,context),manifest=request.manifest;
  assertCurrentOwnerIssue(event,currentIssue);
  // Digest and bytes are checked again by the independent Git reader.
  // No caller-supplied manifest or receipt is used.
  const stage=stageReviewedPackage(manifest,request,repositories,parent);
  return {...stage,request:assertRequestPackage(request,manifest,stage.identity)};
}
