// Source-only resolver. Caller must supply authentic GitHub event/context from
// the existing canonical owner-gated workflow; a JSON fixture proves no authority.
import { verifyReviewedPackage } from "./development-candidate-git-observation-v1.mjs";
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
     typeof i.body!=="string"||i.body.length>2048) fail();
  const fields=Object.create(null);
  const required=["diagnostic_scope","release_lane","production_target","candidate_sha","controller_sha","package_sha256"];
  for(const line of i.body.trim().split(/\r?\n/)) {
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
     i.title!=="Production schema validation request: package "+fields.diagnostic_scope) fail();
  return Object.freeze({intent:"clone_only",lane:fields.release_lane,scope:fields.diagnostic_scope,
    candidate_sha:fields.candidate_sha,controller_sha:fields.controller_sha,package_sha256:fields.package_sha256,
    request_issue:i.number,request_id:i.id,owner_id:context.owner_id,
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

// The trusted entry point never accepts a caller-supplied identity receipt.
export function verifyOwnerClonePackage(event,context,manifest,repositories) {
  const request=resolveOwnerCloneRequest(event,context);
  const identity=verifyReviewedPackage(manifest,request,repositories);
  return assertRequestPackage(request,manifest,identity);
}
