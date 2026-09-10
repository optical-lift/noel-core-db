-- Personal Reality Capture Membrane v1
-- "Tell Atlas something" preserves spontaneous first-party testimony once, before interpretation.
-- Interpretation may propose several effects from that evidence. Proposal/confirmation are workflow
-- states, not downstream truth. Routing is allowlisted and never bypasses a missing domain authority.

create table if not exists atlas.personal_reality_captures (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  source_action_id text not null,
  testimony text not null,
  subject_domain text not null default 'person',
  subject_kind text not null default 'principal',
  subject_id text not null,
  evidence_id uuid not null references atlas.evidence_records(id) on delete restrict,
  capture_state text not null default 'captured' check (capture_state in ('captured','interpreted','resolved')),
  source_surface text not null default 'tell_atlas',
  metadata jsonb not null default '{}'::jsonb,
  captured_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_user_id,source_action_id),
  check (btrim(source_action_id)<>''), check (btrim(testimony)<>''),
  check (btrim(subject_domain)<>''), check (btrim(subject_kind)<>''), check (btrim(subject_id)<>''),
  check (btrim(source_surface)<>'')
);
comment on table atlas.personal_reality_captures is
  'Workflow envelope for spontaneous first-party testimony. One capture points to one Evidence Record and may support several separately governed effects.';
create index if not exists personal_reality_captures_principal_time_idx
  on atlas.personal_reality_captures(principal_id,captured_at desc,id);
alter table atlas.personal_reality_captures enable row level security;
revoke all on atlas.personal_reality_captures from public,anon,authenticated;

create table if not exists atlas.personal_reality_effect_proposals (
  id uuid primary key default gen_random_uuid(),
  capture_id uuid not null references atlas.personal_reality_captures(id) on delete cascade,
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  effect_key text not null,
  effect_kind text not null check (effect_kind in ('claim','capacity_block','one_off_action','fact_only')),
  proposal jsonb not null check (jsonb_typeof(proposal)='object'),
  interpreter_kind text not null check (interpreter_kind in ('human','ai','rule','import')),
  interpreter_ref text,
  confidence numeric(5,4) check (confidence is null or confidence between 0 and 1),
  explanation text,
  proposal_state text not null default 'proposed'
    check (proposal_state in ('proposed','confirmed','rejected','applied','destination_unavailable')),
  confirmed_at timestamptz,
  rejected_at timestamptz,
  applied_at timestamptz,
  destination_kind text,
  destination_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(capture_id,effect_key), check (btrim(effect_key)<>''),
  check (interpreter_ref is null or btrim(interpreter_ref)<>'')
);
comment on table atlas.personal_reality_effect_proposals is
  'Interpretation workflow only. AI, rules, imports, or humans may propose an effect; proposal state never substitutes for downstream domain truth.';
create index if not exists personal_reality_effect_proposals_capture_idx
  on atlas.personal_reality_effect_proposals(capture_id,proposal_state,created_at,id);
alter table atlas.personal_reality_effect_proposals enable row level security;
revoke all on atlas.personal_reality_effect_proposals from public,anon,authenticated;

create table if not exists atlas.personal_reality_effect_events (
  id uuid primary key default gen_random_uuid(),
  proposal_id uuid not null references atlas.personal_reality_effect_proposals(id) on delete cascade,
  capture_id uuid not null references atlas.personal_reality_captures(id) on delete cascade,
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_kind text not null check (event_kind in ('proposed','confirmed','rejected','applied','destination_unavailable')),
  from_state text, to_state text not null,
  detail jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);
create index if not exists personal_reality_effect_events_proposal_idx
  on atlas.personal_reality_effect_events(proposal_id,occurred_at,id);
alter table atlas.personal_reality_effect_events enable row level security;
revoke all on atlas.personal_reality_effect_events from public,anon,authenticated;

-- Narrow composition helper: reuse already-owned Evidence for another person-scoped Claim.
create or replace function atlas.attach_person_claim_to_existing_evidence_api_v1(p_input jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare
  u uuid:=auth.uid(); e uuid; sk text; s jsonb; c jsonb;
  sd text; stk text; sid text; ct text; ls text; ak text; conf numeric;
  vf timestamptz; vu timestamptz; md jsonb; cid uuid; old atlas.claim_records%rowtype; made boolean:=false;
begin
  if u is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then raise exception 'Claim attachment input must be an object.' using errcode='22023'; end if;
  e:=nullif(p_input->>'evidenceId','')::uuid; sk:=nullif(btrim(p_input->>'sourceKey'),'');
  s:=p_input->'subject'; c:=p_input->'claim';
  if e is null or sk is null or jsonb_typeof(s)<>'object' or jsonb_typeof(c)<>'object' then
    raise exception 'evidenceId, sourceKey, subject, and claim are required.' using errcode='22023';
  end if;
  if not exists(select 1 from atlas.evidence_records x where x.id=e and x.scope_kind='person' and x.scope_id=u) then
    raise exception 'evidenceId must identify evidence owned by the signed-in person.' using errcode='42501';
  end if;
  sd:=nullif(btrim(s->>'domain'),''); stk:=nullif(btrim(s->>'kind'),''); sid:=nullif(btrim(s->>'id'),'');
  ct:=nullif(btrim(c->>'claimType'),''); ls:=nullif(btrim(c->>'lifecycleState'),'');
  if sd is null or stk is null or sid is null or ct is null or ls is null or not(c?'value') then
    raise exception 'subject domain/kind/id and claim claimType/lifecycleState/value are required.' using errcode='22023';
  end if;
  if ls not in ('reported','observed','proposed','accepted','rejected','unknown') then
    raise exception 'Unsupported first-party claim lifecycle state.' using errcode='22023';
  end if;
  if c?'confidence' then conf:=(c->>'confidence')::numeric; if conf<0 or conf>1 then raise exception 'claim confidence must be between 0 and 1.' using errcode='22023'; end if; end if;
  vf:=nullif(c->>'validFrom','')::timestamptz; vu:=nullif(c->>'validUntil','')::timestamptz;
  if vf is not null and vu is not null and vu<vf then raise exception 'claim validUntil cannot precede validFrom.' using errcode='22023'; end if;
  md:=coalesce(case when jsonb_typeof(c->'metadata')='object' then c->'metadata' end,'{}'::jsonb);
  ak:=case ls when 'observed' then 'person_reported_observation' when 'accepted' then 'person_acceptance'
      when 'rejected' then 'person_rejection' when 'proposed' then 'person_proposal' else 'person' end;
  insert into atlas.claim_records(scope_kind,scope_id,subject_domain,subject_kind,subject_id,claim_type,lifecycle_state,
    authority_kind,source_kind,source_key,value,confidence,primary_evidence_id,valid_from,valid_until,metadata)
  values('person',u,sd,stk,sid,ct,ls,ak,'person_existing_evidence_claim',sk,c->'value',conf,e,vf,vu,md)
  on conflict(scope_kind,scope_id,source_kind,source_key) do nothing returning id into cid;
  if cid is not null then made:=true; else
    select * into old from atlas.claim_records x where x.scope_kind='person' and x.scope_id=u
      and x.source_kind='person_existing_evidence_claim' and x.source_key=sk;
    if old.id is null or old.subject_domain is distinct from sd or old.subject_kind is distinct from stk
      or old.subject_id is distinct from sid or old.claim_type is distinct from ct or old.lifecycle_state is distinct from ls
      or old.authority_kind is distinct from ak or old.value is distinct from c->'value' or old.confidence is distinct from conf
      or old.primary_evidence_id is distinct from e or old.valid_from is distinct from vf or old.valid_until is distinct from vu
      or old.metadata is distinct from md then
      raise exception 'sourceKey retry does not match existing attached claim.' using errcode='23505';
    end if; cid:=old.id;
  end if;
  insert into atlas.claim_evidence_links(claim_id,evidence_id,relation_kind,metadata)
  values(cid,e,'supports',jsonb_build_object('primary',true,'attachmentContract','person_existing_evidence_claim_v1'))
  on conflict(claim_id,evidence_id,relation_kind) do nothing;
  return jsonb_build_object('ok',true,'created',made,'contractVersion','person_existing_evidence_claim_v1',
    'claimId',cid,'evidenceId',e,'truthBoundary',jsonb_build_object('evidenceIsReusedNotCopied',true,
    'claimRemainsDistinctFromEvidence',true,'samePersonCustodyRequired',true,'doesNotCreateTask',true,
    'doesNotCreateClockPlacement',true,'doesNotDiagnose',true,'doesNotEstablishCausation',true));
end;$function$;

create or replace function atlas.capture_personal_reality_self_api_v1(p_input jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare
  u uuid:=auth.uid(); p atlas.principals%rowtype; key text; txt text; sd text; sk text; sid text; surface text;
  obs timestamptz; md jsonb; prov jsonb; eid uuid; ev atlas.evidence_records%rowtype;
  cap atlas.personal_reality_captures%rowtype; old atlas.personal_reality_captures%rowtype;
begin
  if u is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then raise exception 'Personal reality capture input must be an object.' using errcode='22023'; end if;
  select * into p from atlas.principals x where x.user_id=u and x.status='active' limit 1;
  if p.id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;
  key:=nullif(btrim(p_input->>'sourceActionId'),''); txt:=nullif(btrim(p_input->>'testimony'),'');
  sd:=coalesce(nullif(btrim(p_input#>>'{subject,domain}'),''),'person');
  sk:=coalesce(nullif(btrim(p_input#>>'{subject,kind}'),''),'principal');
  sid:=coalesce(nullif(btrim(p_input#>>'{subject,id}'),''),p.id::text);
  surface:=coalesce(nullif(btrim(p_input->>'sourceSurface'),''),'tell_atlas');
  obs:=nullif(p_input->>'observedAt','')::timestamptz;
  md:=coalesce(case when jsonb_typeof(p_input->'metadata')='object' then p_input->'metadata' end,'{}'::jsonb);
  prov:=jsonb_build_object('sourceSurface',surface,'sourceActionId',key);
  if key is null or txt is null then raise exception 'sourceActionId and testimony are required.' using errcode='22023'; end if;
  select * into old from atlas.personal_reality_captures x where x.owner_user_id=u and x.source_action_id=key;
  if old.id is not null then
    select * into ev from atlas.evidence_records x where x.id=old.evidence_id;
    if old.principal_id is distinct from p.id or old.testimony is distinct from txt or old.subject_domain is distinct from sd
      or old.subject_kind is distinct from sk or old.subject_id is distinct from sid or old.source_surface is distinct from surface
      or old.metadata is distinct from md or ev.value is distinct from to_jsonb(txt) or ev.observed_at is distinct from obs
      or ev.provenance is distinct from prov or ev.metadata is distinct from (md||jsonb_build_object('captureContract','personal_reality_capture_v1')) then
      raise exception 'sourceActionId retry does not match existing personal reality capture.' using errcode='23505';
    end if;
    return jsonb_build_object('ok',true,'created',false,'contractVersion','personal_reality_capture_v1','captureId',old.id,
      'evidenceId',old.evidence_id,'captureState',old.capture_state,'truthBoundary',jsonb_build_object('testimonyPreservedOnce',true,
      'captureIsNotClaim',true,'captureIsNotDomainTruth',true,'captureDoesNotCreateTask',true,'captureDoesNotCreateClockPlacement',true,
      'captureDoesNotInstantiateWorldKernel',true,'captureDoesNotAnswerDiscoveryQuestion',true));
  end if;
  insert into atlas.evidence_records(scope_kind,scope_id,subject_domain,subject_kind,subject_id,evidence_kind,source_kind,source_key,
    actor_user_id,value,confidence,observed_at,effective_from,effective_until,provenance,metadata)
  values('person',u,sd,sk,sid,'first_party_testimony','personal_reality_capture',key,u,to_jsonb(txt),1,obs,null,null,prov,
    md||jsonb_build_object('captureContract','personal_reality_capture_v1'))
  on conflict(scope_kind,scope_id,source_kind,source_key) do nothing returning id into eid;
  if eid is null then
    select * into ev from atlas.evidence_records x where x.scope_kind='person' and x.scope_id=u
      and x.source_kind='personal_reality_capture' and x.source_key=key;
    if ev.id is null or ev.subject_domain is distinct from sd or ev.subject_kind is distinct from sk or ev.subject_id is distinct from sid
      or ev.evidence_kind is distinct from 'first_party_testimony' or ev.actor_user_id is distinct from u or ev.value is distinct from to_jsonb(txt)
      or ev.confidence is distinct from 1::numeric or ev.observed_at is distinct from obs or ev.effective_from is not null
      or ev.effective_until is not null or ev.provenance is distinct from prov
      or ev.metadata is distinct from (md||jsonb_build_object('captureContract','personal_reality_capture_v1')) then
      raise exception 'sourceActionId retry does not match existing testimony evidence.' using errcode='23505';
    end if; eid:=ev.id;
  end if;
  insert into atlas.personal_reality_captures(principal_id,owner_user_id,source_action_id,testimony,subject_domain,subject_kind,subject_id,evidence_id,source_surface,metadata)
  values(p.id,u,key,txt,sd,sk,sid,eid,surface,md) returning * into cap;
  return jsonb_build_object('ok',true,'created',true,'contractVersion','personal_reality_capture_v1','captureId',cap.id,
    'evidenceId',eid,'captureState',cap.capture_state,'testimony',cap.testimony,'truthBoundary',jsonb_build_object('testimonyPreservedOnce',true,
    'captureIsNotClaim',true,'captureIsNotDomainTruth',true,'captureDoesNotCreateTask',true,'captureDoesNotCreateClockPlacement',true,
    'captureDoesNotInstantiateWorldKernel',true,'captureDoesNotAnswerDiscoveryQuestion',true,'interpretationMayProduceMultipleEffects',true));
end;$function$;

create or replace function atlas.propose_personal_reality_effects_self_api_v1(p_capture_id uuid,p_effects jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare
  u uuid:=auth.uid(); cap atlas.personal_reality_captures%rowtype; x jsonb; ek text; kind text; ik text; ir text;
  conf numeric; expl text; body jsonb; rowv atlas.personal_reality_effect_proposals%rowtype;
  old atlas.personal_reality_effect_proposals%rowtype; items jsonb:='[]'::jsonb;
begin
  if u is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_capture_id is null or p_effects is null or jsonb_typeof(p_effects)<>'array' then raise exception 'captureId and effects array are required.' using errcode='22023'; end if;
  select * into cap from atlas.personal_reality_captures c where c.id=p_capture_id and c.owner_user_id=u for update;
  if cap.id is null then raise exception 'Personal reality capture not found.' using errcode='P0002'; end if;
  for x in select value from jsonb_array_elements(p_effects) loop
    if jsonb_typeof(x)<>'object' then raise exception 'Each effect proposal must be an object.' using errcode='22023'; end if;
    ek:=nullif(btrim(x->>'effectKey'),''); kind:=nullif(btrim(x->>'effectKind'),''); body:=x->'proposal';
    ik:=coalesce(nullif(btrim(x->>'interpreterKind'),''),'human'); ir:=nullif(btrim(x->>'interpreterRef'),'');
    expl:=nullif(btrim(x->>'explanation'),''); conf:=case when x?'confidence' then (x->>'confidence')::numeric else null end;
    if ek is null or kind is null or jsonb_typeof(body)<>'object' then raise exception 'effectKey, effectKind, and proposal object are required.' using errcode='22023'; end if;
    if kind not in ('claim','capacity_block','one_off_action','fact_only') then raise exception 'Unsupported effectKind.' using errcode='22023'; end if;
    if ik not in ('human','ai','rule','import') then raise exception 'Unsupported interpreterKind.' using errcode='22023'; end if;
    if conf is not null and (conf<0 or conf>1) then raise exception 'Effect confidence must be between 0 and 1.' using errcode='22023'; end if;
    select * into old from atlas.personal_reality_effect_proposals q where q.capture_id=cap.id and q.effect_key=ek;
    if old.id is not null then
      if old.effect_kind is distinct from kind or old.proposal is distinct from body or old.interpreter_kind is distinct from ik
        or old.interpreter_ref is distinct from ir or old.confidence is distinct from conf or old.explanation is distinct from expl then
        raise exception 'effectKey retry does not match existing effect proposal.' using errcode='23505';
      end if; items:=items||jsonb_build_array(to_jsonb(old)); continue;
    end if;
    insert into atlas.personal_reality_effect_proposals(capture_id,principal_id,owner_user_id,effect_key,effect_kind,proposal,interpreter_kind,interpreter_ref,confidence,explanation)
    values(cap.id,cap.principal_id,u,ek,kind,body,ik,ir,conf,expl) returning * into rowv;
    insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,event_kind,from_state,to_state,detail)
    values(rowv.id,cap.id,cap.principal_id,u,'proposed',null,'proposed',jsonb_build_object('interpreterKind',ik,'effectKind',kind));
    items:=items||jsonb_build_array(to_jsonb(rowv));
  end loop;
  if jsonb_array_length(p_effects)>0 then update atlas.personal_reality_captures set capture_state=case when capture_state='captured' then 'interpreted' else capture_state end,updated_at=now() where id=cap.id; end if;
  return jsonb_build_object('ok',true,'contractVersion','personal_reality_effect_proposal_v1','captureId',cap.id,'evidenceId',cap.evidence_id,
    'effects',items,'truthBoundary',jsonb_build_object('proposalIsNotTruth',true,'aiMayProposeButNotApply',true,'ruleMayProposeButNotApply',true,
    'multipleEffectsMayShareOneEvidence',true,'proposalDoesNotInstantiateWorldKernel',true,'proposalDoesNotAnswerDiscoveryQuestion',true));
end;$function$;

create or replace function atlas.confirm_personal_reality_effect_self_api_v1(p_proposal_id uuid,p_decision text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare u uuid:=auth.uid(); q atlas.personal_reality_effect_proposals%rowtype; cap atlas.personal_reality_captures%rowtype; d text; before text;
begin
  if u is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  d:=lower(btrim(coalesce(p_decision,''))); if d not in ('confirm','reject') then raise exception 'decision must be confirm or reject.' using errcode='22023'; end if;
  select * into q from atlas.personal_reality_effect_proposals x where x.id=p_proposal_id and x.owner_user_id=u for update;
  if q.id is null then raise exception 'Effect proposal not found.' using errcode='P0002'; end if;
  select * into cap from atlas.personal_reality_captures c where c.id=q.capture_id and c.owner_user_id=u;
  if q.proposal_state in ('applied','destination_unavailable') then raise exception 'An applied or routed effect cannot be re-decided.' using errcode='22023'; end if;
  if q.proposal_state in ('confirmed','rejected') then
    if (d='confirm')<>(q.proposal_state='confirmed') then raise exception 'Effect proposal has already been decided differently.' using errcode='23505'; end if;
    return jsonb_build_object('ok',true,'changed',false,'contractVersion','personal_reality_effect_confirmation_v1','proposal',to_jsonb(q),'evidenceId',cap.evidence_id);
  end if;
  before:=q.proposal_state;
  update atlas.personal_reality_effect_proposals set proposal_state=case when d='confirm' then 'confirmed' else 'rejected' end,
    confirmed_at=case when d='confirm' then now() else null end,rejected_at=case when d='reject' then now() else null end,updated_at=now()
  where id=q.id returning * into q;
  insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,event_kind,from_state,to_state,detail)
  values(q.id,cap.id,cap.principal_id,u,case when d='confirm' then 'confirmed' else 'rejected' end,before,q.proposal_state,jsonb_build_object('humanDecision',d));
  return jsonb_build_object('ok',true,'changed',true,'contractVersion','personal_reality_effect_confirmation_v1','proposal',to_jsonb(q),'evidenceId',cap.evidence_id,
    'truthBoundary',jsonb_build_object('confirmationIsNotApplication',true,'rejectionDoesNotDeleteTestimony',true));
end;$function$;

create or replace function atlas.apply_personal_reality_effect_self_api_v1(p_proposal_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare
  u uuid:=auth.uid(); q atlas.personal_reality_effect_proposals%rowtype; cap atlas.personal_reality_captures%rowtype;
  body jsonb; result jsonb; dk text; did text; before text; fn regprocedure;
begin
  if u is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into q from atlas.personal_reality_effect_proposals x where x.id=p_proposal_id and x.owner_user_id=u for update;
  if q.id is null then raise exception 'Effect proposal not found.' using errcode='P0002'; end if;
  select * into cap from atlas.personal_reality_captures c where c.id=q.capture_id and c.owner_user_id=u;
  if cap.id is null then raise exception 'Capture not found.' using errcode='P0002'; end if;
  if q.proposal_state='applied' then return jsonb_build_object('ok',true,'changed',false,'contractVersion','personal_reality_effect_application_v1',
    'proposalId',q.id,'state','applied','destinationKind',q.destination_kind,'destinationId',q.destination_id,'evidenceId',cap.evidence_id); end if;
  if q.proposal_state='rejected' then raise exception 'Rejected effect proposal cannot be applied.' using errcode='22023'; end if;
  if q.proposal_state not in ('confirmed','destination_unavailable') then raise exception 'Human confirmation is required before application.' using errcode='42501'; end if;
  before:=q.proposal_state; body:=q.proposal;
  if q.effect_kind='fact_only' then
    dk:='evidence_record'; did:=cap.evidence_id::text; result:=jsonb_build_object('ok',true,'evidenceId',cap.evidence_id);
  elsif q.effect_kind='claim' then
    result:=atlas.attach_person_claim_to_existing_evidence_api_v1(jsonb_build_object('evidenceId',cap.evidence_id,
      'sourceKey',cap.source_action_id||':'||q.effect_key,'subject',body->'subject','claim',body->'claim'));
    dk:='claim_record'; did:=result->>'claimId';
  elsif q.effect_kind='one_off_action' then
    fn:=to_regprocedure('atlas.capture_personal_one_off_action_self_api_v1(jsonb)');
    if fn is null then
      update atlas.personal_reality_effect_proposals set proposal_state='destination_unavailable',destination_kind='principal_one_off_action',destination_id=null,updated_at=now() where id=q.id returning * into q;
      if before<>'destination_unavailable' then insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,event_kind,from_state,to_state,detail)
        values(q.id,cap.id,cap.principal_id,u,'destination_unavailable',before,'destination_unavailable',jsonb_build_object('requiredFunction','atlas.capture_personal_one_off_action_self_api_v1(jsonb)','sourceEvidenceId',cap.evidence_id)); end if;
      return jsonb_build_object('ok',true,'changed',(before<>'destination_unavailable'),'contractVersion','personal_reality_effect_application_v1','proposalId',q.id,
        'state','destination_unavailable','effectKind','one_off_action','evidenceId',cap.evidence_id);
    end if;
    if nullif(btrim(body->>'title'),'') is null then raise exception 'one_off_action effect requires title.' using errcode='22023'; end if;
    body:=(body-'sourceKey'-'testimony'-'sourceEvidenceId'-'sourceClaimId')||jsonb_build_object('sourceKey',cap.source_action_id||':'||q.effect_key,'testimony',cap.testimony,'sourceEvidenceId',cap.evidence_id);
    execute 'select atlas.capture_personal_one_off_action_self_api_v1($1)' into result using body;
    dk:='principal_one_off_action'; did:=result#>>'{action,id}';
    if did is null then raise exception 'One-Off Action destination did not return an action id.' using errcode='55000'; end if;
  elsif q.effect_kind='capacity_block' then
    update atlas.personal_reality_effect_proposals set proposal_state='destination_unavailable',destination_kind='principal_capacity_block',destination_id=null,updated_at=now() where id=q.id returning * into q;
    if before<>'destination_unavailable' then insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,event_kind,from_state,to_state,detail)
      values(q.id,cap.id,cap.principal_id,u,'destination_unavailable',before,'destination_unavailable',jsonb_build_object('reason','No governed self-authoring Principal Capacity Block writer exists yet.','sourceEvidenceId',cap.evidence_id)); end if;
    return jsonb_build_object('ok',true,'changed',(before<>'destination_unavailable'),'contractVersion','personal_reality_effect_application_v1','proposalId',q.id,
      'state','destination_unavailable','effectKind','capacity_block','evidenceId',cap.evidence_id);
  end if;
  update atlas.personal_reality_effect_proposals set proposal_state='applied',applied_at=coalesce(applied_at,now()),destination_kind=dk,destination_id=did,updated_at=now() where id=q.id returning * into q;
  insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,event_kind,from_state,to_state,detail)
  values(q.id,cap.id,cap.principal_id,u,'applied',before,'applied',jsonb_build_object('destinationKind',dk,'destinationId',did,'sourceEvidenceId',cap.evidence_id));
  update atlas.personal_reality_captures c set capture_state=case when not exists(select 1 from atlas.personal_reality_effect_proposals z where z.capture_id=c.id and z.proposal_state in ('proposed','confirmed','destination_unavailable')) then 'resolved' else 'interpreted' end,updated_at=now() where c.id=cap.id;
  return jsonb_build_object('ok',true,'changed',true,'contractVersion','personal_reality_effect_application_v1','proposalId',q.id,'state','applied',
    'effectKind',q.effect_kind,'destinationKind',dk,'destinationId',did,'evidenceId',cap.evidence_id,'result',result,
    'truthBoundary',jsonb_build_object('applicationUsesAllowlistedRoute',true,'sourceEvidenceRetained',true,'captureMembraneDoesNotOwnDestinationTruth',true,
    'worldKernelApplicabilityNotInferred',true,'discoveryQuestionNotAnsweredByResemblance',true));
end;$function$;

create or replace function atlas.personal_reality_capture_self_api_v1(p_capture_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $function$
declare u uuid:=auth.uid(); cap atlas.personal_reality_captures%rowtype; effects jsonb;
begin
  if u is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into cap from atlas.personal_reality_captures c where c.id=p_capture_id and c.owner_user_id=u;
  if cap.id is null then raise exception 'Personal reality capture not found.' using errcode='P0002'; end if;
  select coalesce(jsonb_agg(to_jsonb(p) order by p.created_at,p.id),'[]'::jsonb) into effects from atlas.personal_reality_effect_proposals p where p.capture_id=cap.id and p.owner_user_id=u;
  return jsonb_build_object('ok',true,'contractVersion','personal_reality_capture_read_v1','capture',to_jsonb(cap),'effects',effects,
    'truthBoundary',jsonb_build_object('captureStateIsWorkflowStateNotLifeTruth',true,'proposalStateIsInterpretationWorkflowState',true,'destinationTruthLivesElsewhere',true));
end;$function$;

revoke all on function atlas.attach_person_claim_to_existing_evidence_api_v1(jsonb) from public,anon;
revoke all on function atlas.capture_personal_reality_self_api_v1(jsonb) from public,anon;
revoke all on function atlas.propose_personal_reality_effects_self_api_v1(uuid,jsonb) from public,anon;
revoke all on function atlas.confirm_personal_reality_effect_self_api_v1(uuid,text) from public,anon;
revoke all on function atlas.apply_personal_reality_effect_self_api_v1(uuid) from public,anon;
revoke all on function atlas.personal_reality_capture_self_api_v1(uuid) from public,anon;
grant execute on function atlas.attach_person_claim_to_existing_evidence_api_v1(jsonb) to authenticated,service_role;
grant execute on function atlas.capture_personal_reality_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function atlas.propose_personal_reality_effects_self_api_v1(uuid,jsonb) to authenticated,service_role;
grant execute on function atlas.confirm_personal_reality_effect_self_api_v1(uuid,text) to authenticated,service_role;
grant execute on function atlas.apply_personal_reality_effect_self_api_v1(uuid) to authenticated,service_role;
grant execute on function atlas.personal_reality_capture_self_api_v1(uuid) to authenticated,service_role;

create or replace function public.capture_personal_reality_self_api_v1(p_input jsonb) returns jsonb language sql security definer set search_path=pg_catalog as $f$ select atlas.capture_personal_reality_self_api_v1(p_input); $f$;
create or replace function public.propose_personal_reality_effects_self_api_v1(p_capture_id uuid,p_effects jsonb) returns jsonb language sql security definer set search_path=pg_catalog as $f$ select atlas.propose_personal_reality_effects_self_api_v1(p_capture_id,p_effects); $f$;
create or replace function public.confirm_personal_reality_effect_self_api_v1(p_proposal_id uuid,p_decision text) returns jsonb language sql security definer set search_path=pg_catalog as $f$ select atlas.confirm_personal_reality_effect_self_api_v1(p_proposal_id,p_decision); $f$;
create or replace function public.apply_personal_reality_effect_self_api_v1(p_proposal_id uuid) returns jsonb language sql security definer set search_path=pg_catalog as $f$ select atlas.apply_personal_reality_effect_self_api_v1(p_proposal_id); $f$;
create or replace function public.personal_reality_capture_self_api_v1(p_capture_id uuid) returns jsonb language sql stable security definer set search_path=pg_catalog as $f$ select atlas.personal_reality_capture_self_api_v1(p_capture_id); $f$;

revoke all on function public.capture_personal_reality_self_api_v1(jsonb) from public,anon;
revoke all on function public.propose_personal_reality_effects_self_api_v1(uuid,jsonb) from public,anon;
revoke all on function public.confirm_personal_reality_effect_self_api_v1(uuid,text) from public,anon;
revoke all on function public.apply_personal_reality_effect_self_api_v1(uuid) from public,anon;
revoke all on function public.personal_reality_capture_self_api_v1(uuid) from public,anon;
grant execute on function public.capture_personal_reality_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function public.propose_personal_reality_effects_self_api_v1(uuid,jsonb) to authenticated,service_role;
grant execute on function public.confirm_personal_reality_effect_self_api_v1(uuid,text) to authenticated,service_role;
grant execute on function public.apply_personal_reality_effect_self_api_v1(uuid) to authenticated,service_role;
grant execute on function public.personal_reality_capture_self_api_v1(uuid) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at) values
('atlas.attach_person_claim_to_existing_evidence_api_v1(p_input jsonb)','policy_or_composition_helper','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Attach a person-scoped claim to existing evidence owned by the same signed-in person without duplicating evidence.','genericDomainWriter',false),now()),
('atlas.capture_personal_reality_self_api_v1(p_input jsonb)','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Preserve spontaneous first-party testimony exactly once as Evidence before interpretation or routing.','domainTruthOwner',false),now()),
('atlas.propose_personal_reality_effects_self_api_v1(p_capture_id uuid, p_effects jsonb)','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Attach zero or more interpretation proposals to one preserved testimony without establishing downstream truth.','aiMayApply',false),now()),
('atlas.confirm_personal_reality_effect_self_api_v1(p_proposal_id uuid, p_decision text)','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Record explicit human confirmation or rejection; confirmation is not application.'),now()),
('atlas.apply_personal_reality_effect_self_api_v1(p_proposal_id uuid)','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Route a confirmed effect through a narrow allowlist while retaining original testimony evidence; unavailable destinations remain preserved.','genericDomainWriter',false),now()),
('atlas.personal_reality_capture_self_api_v1(p_capture_id uuid)','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Read one spontaneous capture and its interpretation workflow without collapsing workflow state into domain truth.'),now())
on conflict(signature) do update set classification=excluded.classification,confidence=excluded.confidence,review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,anonymous_execute_expected=excluded.anonymous_execute_expected,
  evidence=atlas.authenticated_rpc_registry.evidence||excluded.evidence,reviewed_at=now();