-- Personal Reality Capture Membrane v1
--
-- "Tell Atlas something" preserves spontaneous first-party testimony once, before interpretation.
-- Interpretation may propose multiple effects from that one testimony. A proposal is not truth.
-- Human confirmation is required before an effect may be routed, and routing is restricted to
-- explicit governed destinations. The membrane never becomes a universal domain writer.
--
-- This migration owns capture workflow identity and interpretation workflow state only.
-- Evidence Record owns preserved source evidence. Claim Record and downstream domain objects own
-- their own truths. World-kernel definitions and Reality Discovery may later consume evidence, but
-- this membrane never instantiates a kernel or answers a discovery question by resemblance.

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
  capture_state text not null default 'captured'
    check (capture_state in ('captured','interpreted','resolved')),
  source_surface text not null default 'tell_atlas',
  metadata jsonb not null default '{}'::jsonb,
  captured_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_user_id,source_action_id),
  check (btrim(source_action_id)<>''),
  check (btrim(testimony)<>''),
  check (btrim(subject_domain)<>''),
  check (btrim(subject_kind)<>''),
  check (btrim(subject_id)<>''),
  check (btrim(source_surface)<>'')
);

comment on table atlas.personal_reality_captures is
  'Workflow envelope for spontaneous first-party testimony. One capture points to one preserved Evidence Record and may support several separately governed effects.';

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
  effect_kind text not null
    check (effect_kind in ('claim','capacity_block','one_off_action','fact_only')),
  proposal jsonb not null,
  interpreter_kind text not null
    check (interpreter_kind in ('human','ai','rule','import')),
  interpreter_ref text,
  confidence numeric(5,4) check (confidence is null or (confidence>=0 and confidence<=1)),
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
  unique(capture_id,effect_key),
  check (btrim(effect_key)<>''),
  check (jsonb_typeof(proposal)='object'),
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
  event_kind text not null
    check (event_kind in ('proposed','confirmed','rejected','applied','destination_unavailable')),
  from_state text,
  to_state text not null,
  detail jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);

create index if not exists personal_reality_effect_events_proposal_idx
  on atlas.personal_reality_effect_events(proposal_id,occurred_at,id);

alter table atlas.personal_reality_effect_events enable row level security;
revoke all on atlas.personal_reality_effect_events from public,anon,authenticated;

create or replace function atlas.attach_person_claim_to_existing_evidence_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_evidence_id uuid;
  v_source_key text;
  v_subject jsonb;
  v_claim jsonb;
  v_subject_domain text;
  v_subject_kind text;
  v_subject_id text;
  v_claim_type text;
  v_lifecycle text;
  v_authority text;
  v_confidence numeric;
  v_valid_from timestamptz;
  v_valid_until timestamptz;
  v_metadata jsonb;
  v_claim_id uuid;
  v_existing atlas.claim_records%rowtype;
  v_created boolean:=false;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Claim attachment input must be an object.' using errcode='22023';
  end if;

  v_evidence_id:=nullif(p_input->>'evidenceId','')::uuid;
  v_source_key:=nullif(btrim(p_input->>'sourceKey'),'');
  v_subject:=p_input->'subject';
  v_claim:=p_input->'claim';
  if v_evidence_id is null or v_source_key is null
     or jsonb_typeof(v_subject)<>'object' or jsonb_typeof(v_claim)<>'object' then
    raise exception 'evidenceId, sourceKey, subject, and claim are required.' using errcode='22023';
  end if;

  if not exists(
    select 1 from atlas.evidence_records e
    where e.id=v_evidence_id and e.scope_kind='person' and e.scope_id=v_user_id
  ) then
    raise exception 'evidenceId must identify evidence owned by the signed-in person.' using errcode='42501';
  end if;

  v_subject_domain:=nullif(btrim(v_subject->>'domain'),'');
  v_subject_kind:=nullif(btrim(v_subject->>'kind'),'');
  v_subject_id:=nullif(btrim(v_subject->>'id'),'');
  v_claim_type:=nullif(btrim(v_claim->>'claimType'),'');
  v_lifecycle:=nullif(btrim(v_claim->>'lifecycleState'),'');
  if v_subject_domain is null or v_subject_kind is null or v_subject_id is null
     or v_claim_type is null or v_lifecycle is null or not (v_claim ? 'value') then
    raise exception 'subject domain/kind/id and claim claimType/lifecycleState/value are required.' using errcode='22023';
  end if;
  if v_lifecycle not in ('reported','observed','proposed','accepted','rejected','unknown') then
    raise exception 'First-party claim attachment cannot author inferred, superseded, or expired lifecycle state.' using errcode='22023';
  end if;

  if v_claim ? 'confidence' then
    v_confidence:=(v_claim->>'confidence')::numeric;
    if v_confidence<0 or v_confidence>1 then
      raise exception 'claim confidence must be between 0 and 1.' using errcode='22023';
    end if;
  end if;
  v_valid_from:=nullif(v_claim->>'validFrom','')::timestamptz;
  v_valid_until:=nullif(v_claim->>'validUntil','')::timestamptz;
  if v_valid_from is not null and v_valid_until is not null and v_valid_until<v_valid_from then
    raise exception 'claim validUntil cannot precede validFrom.' using errcode='22023';
  end if;
  v_metadata:=coalesce(case when jsonb_typeof(v_claim->'metadata')='object' then v_claim->'metadata' end,'{}'::jsonb);
  v_authority:=case v_lifecycle
    when 'observed' then 'person_reported_observation'
    when 'accepted' then 'person_acceptance'
    when 'rejected' then 'person_rejection'
    when 'proposed' then 'person_proposal'
    else 'person'
  end;

  insert into atlas.claim_records(
    scope_kind,scope_id,subject_domain,subject_kind,subject_id,
    claim_type,lifecycle_state,authority_kind,source_kind,source_key,value,confidence,
    primary_evidence_id,valid_from,valid_until,metadata
  ) values(
    'person',v_user_id,v_subject_domain,v_subject_kind,v_subject_id,
    v_claim_type,v_lifecycle,v_authority,'person_existing_evidence_claim',v_source_key,
    v_claim->'value',v_confidence,v_evidence_id,v_valid_from,v_valid_until,v_metadata
  )
  on conflict(scope_kind,scope_id,source_kind,source_key) do nothing
  returning id into v_claim_id;

  if v_claim_id is not null then
    v_created:=true;
  else
    select * into v_existing
    from atlas.claim_records c
    where c.scope_kind='person' and c.scope_id=v_user_id
      and c.source_kind='person_existing_evidence_claim' and c.source_key=v_source_key;

    if v_existing.id is null
      or v_existing.subject_domain is distinct from v_subject_domain
      or v_existing.subject_kind is distinct from v_subject_kind
      or v_existing.subject_id is distinct from v_subject_id
      or v_existing.claim_type is distinct from v_claim_type
      or v_existing.lifecycle_state is distinct from v_lifecycle
      or v_existing.authority_kind is distinct from v_authority
      or v_existing.value is distinct from v_claim->'value'
      or v_existing.confidence is distinct from v_confidence
      or v_existing.primary_evidence_id is distinct from v_evidence_id
      or v_existing.valid_from is distinct from v_valid_from
      or v_existing.valid_until is distinct from v_valid_until
      or v_existing.metadata is distinct from v_metadata then
      raise exception 'sourceKey retry does not match existing attached claim.' using errcode='23505';
    end if;
    v_claim_id:=v_existing.id;
  end if;

  insert into atlas.claim_evidence_links(claim_id,evidence_id,relation_kind,metadata)
  values(v_claim_id,v_evidence_id,'supports',jsonb_build_object('primary',true,'attachmentContract','person_existing_evidence_claim_v1'))
  on conflict do nothing;

  return jsonb_build_object(
    'ok',true,'created',v_created,'contractVersion','person_existing_evidence_claim_v1',
    'claimId',v_claim_id,'evidenceId',v_evidence_id,
    'truthBoundary',jsonb_build_object(
      'evidenceIsReusedNotCopied',true,'claimRemainsDistinctFromEvidence',true,
      'samePersonCustodyRequired',true,'doesNotCreateTask',true,
      'doesNotCreateClockPlacement',true,'doesNotDiagnose',true,'doesNotEstablishCausation',true
    )
  );
end;
$function$;

create or replace function atlas.capture_personal_reality_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal atlas.principals%rowtype;
  v_source_action_id text;
  v_testimony text;
  v_subject_domain text;
  v_subject_kind text;
  v_subject_id text;
  v_source_surface text;
  v_observed_at timestamptz;
  v_metadata jsonb;
  v_provenance jsonb;
  v_evidence_id uuid;
  v_existing_evidence atlas.evidence_records%rowtype;
  v_capture atlas.personal_reality_captures%rowtype;
  v_existing_capture atlas.personal_reality_captures%rowtype;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Personal reality capture input must be an object.' using errcode='22023';
  end if;

  select * into v_principal from atlas.principals p
  where p.user_id=v_user_id and p.status='active' limit 1;
  if v_principal.id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  v_source_action_id:=nullif(btrim(p_input->>'sourceActionId'),'');
  v_testimony:=nullif(btrim(p_input->>'testimony'),'');
  v_subject_domain:=coalesce(nullif(btrim(p_input#>>'{subject,domain}'),''),'person');
  v_subject_kind:=coalesce(nullif(btrim(p_input#>>'{subject,kind}'),''),'principal');
  v_subject_id:=coalesce(nullif(btrim(p_input#>>'{subject,id}'),''),v_principal.id::text);
  v_source_surface:=coalesce(nullif(btrim(p_input->>'sourceSurface'),''),'tell_atlas');
  v_observed_at:=nullif(p_input->>'observedAt','')::timestamptz;
  v_metadata:=coalesce(case when jsonb_typeof(p_input->'metadata')='object' then p_input->'metadata' end,'{}'::jsonb);
  v_provenance:=jsonb_build_object('sourceSurface',v_source_surface,'sourceActionId',v_source_action_id);

  if v_source_action_id is null or v_testimony is null then
    raise exception 'sourceActionId and testimony are required.' using errcode='22023';
  end if;

  select * into v_existing_capture from atlas.personal_reality_captures c
  where c.owner_user_id=v_user_id and c.source_action_id=v_source_action_id;
  if v_existing_capture.id is not null then
    select * into v_existing_evidence from atlas.evidence_records e where e.id=v_existing_capture.evidence_id;
    if v_existing_capture.principal_id is distinct from v_principal.id
      or v_existing_capture.testimony is distinct from v_testimony
      or v_existing_capture.subject_domain is distinct from v_subject_domain
      or v_existing_capture.subject_kind is distinct from v_subject_kind
      or v_existing_capture.subject_id is distinct from v_subject_id
      or v_existing_capture.source_surface is distinct from v_source_surface
      or v_existing_capture.metadata is distinct from v_metadata
      or v_existing_evidence.value is distinct from to_jsonb(v_testimony)
      or v_existing_evidence.observed_at is distinct from v_observed_at
      or v_existing_evidence.provenance is distinct from v_provenance
      or v_existing_evidence.metadata is distinct from (v_metadata||jsonb_build_object('captureContract','personal_reality_capture_v1')) then
      raise exception 'sourceActionId retry does not match existing personal reality capture.' using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,'created',false,'contractVersion','personal_reality_capture_v1',
      'captureId',v_existing_capture.id,'evidenceId',v_existing_capture.evidence_id,'captureState',v_existing_capture.capture_state,
      'truthBoundary',jsonb_build_object(
        'testimonyPreservedOnce',true,'captureIsNotClaim',true,'captureIsNotDomainTruth',true,
        'captureDoesNotCreateTask',true,'captureDoesNotCreateClockPlacement',true,
        'captureDoesNotInstantiateWorldKernel',true,'captureDoesNotAnswerDiscoveryQuestion',true
      )
    );
  end if;

  insert into atlas.evidence_records(
    scope_kind,scope_id,subject_domain,subject_kind,subject_id,evidence_kind,source_kind,source_key,
    actor_user_id,value,confidence,observed_at,effective_from,effective_until,provenance,metadata
  ) values(
    'person',v_user_id,v_subject_domain,v_subject_kind,v_subject_id,
    'first_party_testimony','personal_reality_capture',v_source_action_id,v_user_id,
    to_jsonb(v_testimony),1,v_observed_at,null,null,v_provenance,
    v_metadata||jsonb_build_object('captureContract','personal_reality_capture_v1')
  ) on conflict(scope_kind,scope_id,source_kind,source_key) do nothing
  returning id into v_evidence_id;

  if v_evidence_id is null then
    select * into v_existing_evidence from atlas.evidence_records e
    where e.scope_kind='person' and e.scope_id=v_user_id
      and e.source_kind='personal_reality_capture' and e.source_key=v_source_action_id;
    if v_existing_evidence.id is null
      or v_existing_evidence.subject_domain is distinct from v_subject_domain
      or v_existing_evidence.subject_kind is distinct from v_subject_kind
      or v_existing_evidence.subject_id is distinct from v_subject_id
      or v_existing_evidence.evidence_kind is distinct from 'first_party_testimony'
      or v_existing_evidence.actor_user_id is distinct from v_user_id
      or v_existing_evidence.value is distinct from to_jsonb(v_testimony)
      or v_existing_evidence.confidence is distinct from 1::numeric
      or v_existing_evidence.observed_at is distinct from v_observed_at
      or v_existing_evidence.effective_from is not null or v_existing_evidence.effective_until is not null
      or v_existing_evidence.provenance is distinct from v_provenance
      or v_existing_evidence.metadata is distinct from (v_metadata||jsonb_build_object('captureContract','personal_reality_capture_v1')) then
      raise exception 'sourceActionId retry does not match existing testimony evidence.' using errcode='23505';
    end if;
    v_evidence_id:=v_existing_evidence.id;
  end if;

  insert into atlas.personal_reality_captures(
    principal_id,owner_user_id,source_action_id,testimony,subject_domain,subject_kind,subject_id,evidence_id,source_surface,metadata
  ) values(
    v_principal.id,v_user_id,v_source_action_id,v_testimony,v_subject_domain,v_subject_kind,v_subject_id,v_evidence_id,v_source_surface,v_metadata
  ) returning * into v_capture;

  return jsonb_build_object(
    'ok',true,'created',true,'contractVersion','personal_reality_capture_v1',
    'captureId',v_capture.id,'evidenceId',v_evidence_id,'captureState',v_capture.capture_state,'testimony',v_capture.testimony,
    'truthBoundary',jsonb_build_object(
      'testimonyPreservedOnce',true,'captureIsNotClaim',true,'captureIsNotDomainTruth',true,
      'captureDoesNotCreateTask',true,'captureDoesNotCreateClockPlacement',true,
      'captureDoesNotInstantiateWorldKernel',true,'captureDoesNotAnswerDiscoveryQuestion',true,
      'interpretationMayProduceMultipleEffects',true,'effectProposalRequiresSeparateAuthoring',true
    )
  );
end;
$function$;

create or replace function atlas.propose_personal_reality_effects_self_api_v1(p_capture_id uuid,p_effects jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_capture atlas.personal_reality_captures%rowtype;
  v_effect jsonb;
  v_effect_key text;
  v_effect_kind text;
  v_interpreter_kind text;
  v_interpreter_ref text;
  v_confidence numeric;
  v_explanation text;
  v_proposal jsonb;
  v_row atlas.personal_reality_effect_proposals%rowtype;
  v_existing atlas.personal_reality_effect_proposals%rowtype;
  v_items jsonb:='[]'::jsonb;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_capture_id is null or p_effects is null or jsonb_typeof(p_effects)<>'array' then
    raise exception 'captureId and effects array are required.' using errcode='22023';
  end if;
  select * into v_capture from atlas.personal_reality_captures c
  where c.id=p_capture_id and c.owner_user_id=v_user_id for update;
  if v_capture.id is null then raise exception 'Personal reality capture not found.' using errcode='P0002'; end if;

  for v_effect in select value from jsonb_array_elements(p_effects)
  loop
    if jsonb_typeof(v_effect)<>'object' then raise exception 'Each effect proposal must be an object.' using errcode='22023'; end if;
    v_effect_key:=nullif(btrim(v_effect->>'effectKey'),'');
    v_effect_kind:=nullif(btrim(v_effect->>'effectKind'),'');
    v_proposal:=v_effect->'proposal';
    v_interpreter_kind:=coalesce(nullif(btrim(v_effect->>'interpreterKind'),''),'human');
    v_interpreter_ref:=nullif(btrim(v_effect->>'interpreterRef'),'');
    v_explanation:=nullif(btrim(v_effect->>'explanation'),'');
    v_confidence:=case when v_effect ? 'confidence' then (v_effect->>'confidence')::numeric else null end;
    if v_effect_key is null or v_effect_kind is null or jsonb_typeof(v_proposal)<>'object' then
      raise exception 'effectKey, effectKind, and proposal object are required.' using errcode='22023';
    end if;
    if v_effect_kind not in ('claim','capacity_block','one_off_action','fact_only') then raise exception 'Unsupported effectKind.' using errcode='22023'; end if;
    if v_interpreter_kind not in ('human','ai','rule','import') then raise exception 'Unsupported interpreterKind.' using errcode='22023'; end if;
    if v_confidence is not null and (v_confidence<0 or v_confidence>1) then raise exception 'Effect confidence must be between 0 and 1.' using errcode='22023'; end if;

    select * into v_existing from atlas.personal_reality_effect_proposals p
    where p.capture_id=v_capture.id and p.effect_key=v_effect_key;
    if v_existing.id is not null then
      if v_existing.effect_kind is distinct from v_effect_kind or v_existing.proposal is distinct from v_proposal
        or v_existing.interpreter_kind is distinct from v_interpreter_kind or v_existing.interpreter_ref is distinct from v_interpreter_ref
        or v_existing.confidence is distinct from v_confidence or v_existing.explanation is distinct from v_explanation then
        raise exception 'effectKey retry does not match existing effect proposal.' using errcode='23505';
      end if;
      v_items:=v_items||jsonb_build_array(to_jsonb(v_existing));
      continue;
    end if;

    insert into atlas.personal_reality_effect_proposals(
      capture_id,principal_id,owner_user_id,effect_key,effect_kind,proposal,interpreter_kind,interpreter_ref,confidence,explanation
    ) values(
      v_capture.id,v_capture.principal_id,v_user_id,v_effect_key,v_effect_kind,v_proposal,v_interpreter_kind,v_interpreter_ref,v_confidence,v_explanation
    ) returning * into v_row;
    insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,event_kind,from_state,to_state,detail)
    values(v_row.id,v_capture.id,v_capture.principal_id,v_user_id,'proposed',null,'proposed',jsonb_build_object('interpreterKind',v_interpreter_kind,'effectKind',v_effect_kind));
    v_items:=v_items||jsonb_build_array(to_jsonb(v_row));
  end loop;

  if jsonb_array_length(p_effects)>0 then
    update atlas.personal_reality_captures set capture_state=case when capture_state='captured' then 'interpreted' else capture_state end,updated_at=now()
    where id=v_capture.id;
  end if;
  return jsonb_build_object(
    'ok',true,'contractVersion','personal_reality_effect_proposal_v1','captureId',v_capture.id,'evidenceId',v_capture.evidence_id,'effects',v_items,
    'truthBoundary',jsonb_build_object(
      'proposalIsNotTruth',true,'aiMayProposeButNotApply',true,'ruleMayProposeButNotApply',true,
      'multipleEffectsMayShareOneEvidence',true,'proposalDoesNotInstantiateWorldKernel',true,
      'proposalDoesNotAnswerDiscoveryQuestion',true,'proposalDoesNotCreateClockPlacement',true
    )
  );
end;
$function$;

create or replace function atlas.confirm_personal_reality_effect_self_api_v1(p_proposal_id uuid,p_decision text)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_proposal atlas.personal_reality_effect_proposals%rowtype;
  v_capture atlas.personal_reality_captures%rowtype;
  v_decision text;
  v_from text;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_decision:=lower(btrim(coalesce(p_decision,'')));
  if v_decision not in ('confirm','reject') then raise exception 'decision must be confirm or reject.' using errcode='22023'; end if;
  select * into v_proposal from atlas.personal_reality_effect_proposals p
  where p.id=p_proposal_id and p.owner_user_id=v_user_id for update;
  if v_proposal.id is null then raise exception 'Effect proposal not found.' using errcode='P0002'; end if;
  select * into v_capture from atlas.personal_reality_captures c
  where c.id=v_proposal.capture_id and c.owner_user_id=v_user_id;
  if v_capture.id is null then raise exception 'Capture not found.' using errcode='P0002'; end if;

  if v_proposal.proposal_state in ('applied','destination_unavailable') then
    raise exception 'An applied or routed effect cannot be re-decided through confirmation.' using errcode='22023';
  end if;
  if v_proposal.proposal_state in ('confirmed','rejected') then
    if (v_decision='confirm' and v_proposal.proposal_state<>'confirmed') or (v_decision='reject' and v_proposal.proposal_state<>'rejected') then
      raise exception 'Effect proposal has already been decided differently.' using errcode='23505';
    end if;
    return jsonb_build_object('ok',true,'changed',false,'contractVersion','personal_reality_effect_confirmation_v1','proposal',to_jsonb(v_proposal),'evidenceId',v_capture.evidence_id);
  end if;

  v_from:=v_proposal.proposal_state;
  update atlas.personal_reality_effect_proposals
  set proposal_state=case when v_decision='confirm' then 'confirmed' else 'rejected' end,
      confirmed_at=case when v_decision='confirm' then now() else null end,
      rejected_at=case when v_decision='reject' then now() else null end,updated_at=now()
  where id=v_proposal.id returning * into v_proposal;
  insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,event_kind,from_state,to_state,detail)
  values(v_proposal.id,v_capture.id,v_capture.principal_id,v_user_id,case when v_decision='confirm' then 'confirmed' else 'rejected' end,v_from,v_proposal.proposal_state,jsonb_build_object('humanDecision',v_decision));
  return jsonb_build_object(
    'ok',true,'changed',true,'contractVersion','personal_reality_effect_confirmation_v1','proposal',to_jsonb(v_proposal),'evidenceId',v_capture.evidence_id,
    'truthBoundary',jsonb_build_object('confirmationIsNotApplication',true,'rejectionDoesNotDeleteTestimony',true,'sourceEvidenceRemainsPreserved',true)
  );
end;
$function$;

create or replace function atlas.apply_personal_reality_effect_self_api_v1(p_proposal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_proposal atlas.personal_reality_effect_proposals%rowtype;
  v_capture atlas.personal_reality_captures%rowtype;
  v_payload jsonb;
  v_result jsonb;
  v_destination_kind text;
  v_destination_id text;
  v_from text;
  v_function regprocedure;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_proposal from atlas.personal_reality_effect_proposals p
  where p.id=p_proposal_id and p.owner_user_id=v_user_id for update;
  if v_proposal.id is null then raise exception 'Effect proposal not found.' using errcode='P0002'; end if;
  select * into v_capture from atlas.personal_reality_captures c
  where c.id=v_proposal.capture_id and c.owner_user_id=v_user_id;
  if v_capture.id is null then raise exception 'Capture not found.' using errcode='P0002'; end if;

  if v_proposal.proposal_state='applied' then
    return jsonb_build_object('ok',true,'changed',false,'contractVersion','personal_reality_effect_application_v1','proposalId',v_proposal.id,'state','applied','destinationKind',v_proposal.destination_kind,'destinationId',v_proposal.destination_id,'evidenceId',v_capture.evidence_id);
  end if;
  if v_proposal.proposal_state='rejected' then raise exception 'Rejected effect proposal cannot be applied.' using errcode='22023'; end if;
  if v_proposal.proposal_state not in ('confirmed','destination_unavailable') then raise exception 'Human confirmation is required before applying a proposed effect.' using errcode='42501'; end if;

  v_from:=v_proposal.proposal_state;
  v_payload:=v_proposal.proposal;

  if v_proposal.effect_kind='fact_only' then
    v_destination_kind:='evidence_record';
    v_destination_id:=v_capture.evidence_id::text;
    v_result:=jsonb_build_object('ok',true,'effect','fact_only','evidenceId',v_capture.evidence_id,'message','Original testimony evidence remains the only authored fact evidence.');

  elsif v_proposal.effect_kind='claim' then
    if jsonb_typeof(v_payload->'subject')<>'object' or jsonb_typeof(v_payload->'claim')<>'object' then raise exception 'claim effect requires subject and claim objects.' using errcode='22023'; end if;
    v_result:=atlas.attach_person_claim_to_existing_evidence_api_v1(jsonb_build_object(
      'evidenceId',v_capture.evidence_id,'sourceKey',v_capture.source_action_id||':'||v_proposal.effect_key,
      'subject',v_payload->'subject','claim',v_payload->'claim'
    ));
    v_destination_kind:='claim_record';
    v_destination_id:=v_result->>'claimId';

  elsif v_proposal.effect_kind='one_off_action' then
    v_function:=to_regprocedure('atlas.capture_personal_one_off_action_self_api_v1(jsonb)');
    if v_function is null then
      update atlas.personal_reality_effect_proposals set proposal_state='destination_unavailable',updated_at=now(),destination_kind='principal_one_off_action',destination_id=null
      where id=v_proposal.id returning * into v_proposal;
      if v_from<>'destination_unavailable' then
        insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,event_kind,from_state,to_state,detail)
        values(v_proposal.id,v_capture.id,v_capture.principal_id,v_user_id,'destination_unavailable',v_from,'destination_unavailable',jsonb_build_object('requiredFunction','atlas.capture_personal_one_off_action_self_api_v1(jsonb)','sourceEvidenceId',v_capture.evidence_id));
      end if;
      return jsonb_build_object('ok',true,'changed',(v_from<>'destination_unavailable'),'contractVersion','personal_reality_effect_application_v1','proposalId',v_proposal.id,'state','destination_unavailable','effectKind','one_off_action','evidenceId',v_capture.evidence_id,'message','One-Off Action authority is not available in this schema. The confirmed effect remains preserved for later governed routing.');
    end if;
    if nullif(btrim(v_payload->>'title'),'') is null then raise exception 'one_off_action effect requires title.' using errcode='22023'; end if;
    v_payload:=(v_payload-'sourceKey'-'testimony'-'sourceEvidenceId'-'sourceClaimId')||jsonb_build_object(
      'sourceKey',v_capture.source_action_id||':'||v_proposal.effect_key,'testimony',v_capture.testimony,'sourceEvidenceId',v_capture.evidence_id
    );
    execute 'select atlas.capture_personal_one_off_action_self_api_v1($1)' into v_result using v_payload;
    v_destination_kind:='principal_one_off_action';
    v_destination_id:=v_result#>>'{action,id}';
    if v_destination_id is null then raise exception 'One-Off Action destination did not return an action id.' using errcode='55000'; end if;

  elsif v_proposal.effect_kind='capacity_block' then
    update atlas.personal_reality_effect_proposals set proposal_state='destination_unavailable',updated_at=now(),destination_kind='principal_capacity_block',destination_id=null
    where id=v_proposal.id returning * into v_proposal;
    if v_from<>'destination_unavailable' then
      insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,event_kind,from_state,to_state,detail)
      values(v_proposal.id,v_capture.id,v_capture.principal_id,v_user_id,'destination_unavailable',v_from,'destination_unavailable',jsonb_build_object('reason','No governed self-authoring Principal Capacity Block writer exists yet.','sourceEvidenceId',v_capture.evidence_id));
    end if;
    return jsonb_build_object('ok',true,'changed',(v_from<>'destination_unavailable'),'contractVersion','personal_reality_effect_application_v1','proposalId',v_proposal.id,'state','destination_unavailable','effectKind','capacity_block','evidenceId',v_capture.evidence_id,'message','Principal Capacity Block self-authoring is not yet governed. The confirmed effect remains preserved.');
  else
    raise exception 'Unsupported effect route.' using errcode='22023';
  end if;

  update atlas.personal_reality_effect_proposals
  set proposal_state='applied',applied_at=coalesce(applied_at,now()),updated_at=now(),destination_kind=v_destination_kind,destination_id=v_destination_id
  where id=v_proposal.id returning * into v_proposal;
  insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,event_kind,from_state,to_state,detail)
  values(v_proposal.id,v_capture.id,v_capture.principal_id,v_user_id,'applied',v_from,'applied',jsonb_build_object('destinationKind',v_destination_kind,'destinationId',v_destination_id,'sourceEvidenceId',v_capture.evidence_id));
  update atlas.personal_reality_captures c
  set capture_state=case when not exists(select 1 from atlas.personal_reality_effect_proposals p where p.capture_id=c.id and p.proposal_state in ('proposed','confirmed','destination_unavailable')) then 'resolved' else 'interpreted' end,updated_at=now()
  where c.id=v_capture.id;

  return jsonb_build_object(
    'ok',true,'changed',true,'contractVersion','personal_reality_effect_application_v1','proposalId',v_proposal.id,'state','applied','effectKind',v_proposal.effect_kind,
    'destinationKind',v_destination_kind,'destinationId',v_destination_id,'evidenceId',v_capture.evidence_id,'result',v_result,
    'truthBoundary',jsonb_build_object(
      'applicationUsesAllowlistedRoute',true,'sourceEvidenceRetained',true,'captureMembraneDoesNotOwnDestinationTruth',true,
      'applicationDoesNotCreateClockPlacementUnlessDestinationLawfullyDoesSo',true,'worldKernelApplicabilityNotInferred',true,'discoveryQuestionNotAnsweredByResemblance',true
    )
  );
end;
$function$;

create or replace function atlas.personal_reality_capture_self_api_v1(p_capture_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_capture atlas.personal_reality_captures%rowtype;
  v_effects jsonb;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_capture from atlas.personal_reality_captures c where c.id=p_capture_id and c.owner_user_id=v_user_id;
  if v_capture.id is null then raise exception 'Personal reality capture not found.' using errcode='P0002'; end if;
  select coalesce(jsonb_agg(to_jsonb(p) order by p.created_at,p.id),'[]'::jsonb) into v_effects
  from atlas.personal_reality_effect_proposals p where p.capture_id=v_capture.id and p.owner_user_id=v_user_id;
  return jsonb_build_object('ok',true,'contractVersion','personal_reality_capture_read_v1','capture',to_jsonb(v_capture),'effects',v_effects,
    'truthBoundary',jsonb_build_object('captureStateIsWorkflowStateNotLifeTruth',true,'proposalStateIsInterpretationWorkflowState',true,'destinationTruthLivesElsewhere',true));
end;
$function$;

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

create or replace function public.capture_personal_reality_self_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.capture_personal_reality_self_api_v1(p_input); $function$;
create or replace function public.propose_personal_reality_effects_self_api_v1(p_capture_id uuid,p_effects jsonb)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.propose_personal_reality_effects_self_api_v1(p_capture_id,p_effects); $function$;
create or replace function public.confirm_personal_reality_effect_self_api_v1(p_proposal_id uuid,p_decision text)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.confirm_personal_reality_effect_self_api_v1(p_proposal_id,p_decision); $function$;
create or replace function public.apply_personal_reality_effect_self_api_v1(p_proposal_id uuid)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.apply_personal_reality_effect_self_api_v1(p_proposal_id); $function$;
create or replace function public.personal_reality_capture_self_api_v1(p_capture_id uuid)
returns jsonb language sql stable security definer set search_path=pg_catalog
as $function$ select atlas.personal_reality_capture_self_api_v1(p_capture_id); $function$;

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

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
) values
('atlas.attach_person_claim_to_existing_evidence_api_v1(p_input jsonb)','internal_platform','verified','active',true,true,true,false,1,0,
 jsonb_build_object('purpose','Attach a person-scoped claim to existing evidence owned by that same signed-in person without duplicating evidence.','genericDomainWriter',false),now()),
('atlas.capture_personal_reality_self_api_v1(p_input jsonb)','app_endpoint','verified','active',true,true,true,false,1,0,
 jsonb_build_object('purpose','Preserve spontaneous first-party testimony exactly once as Evidence before interpretation or routing.','domainTruthOwner',false),now()),
('atlas.propose_personal_reality_effects_self_api_v1(p_capture_id uuid, p_effects jsonb)','app_endpoint','verified','active',true,true,true,false,1,0,
 jsonb_build_object('purpose','Attach zero or more interpretation proposals to one preserved testimony without establishing downstream truth.','aiMayApply',false),now()),
('atlas.confirm_personal_reality_effect_self_api_v1(p_proposal_id uuid, p_decision text)','app_endpoint','verified','active',true,true,true,false,1,0,
 jsonb_build_object('purpose','Record explicit human confirmation or rejection of one proposed effect; confirmation remains distinct from application.'),now()),
('atlas.apply_personal_reality_effect_self_api_v1(p_proposal_id uuid)','app_endpoint','verified','active',true,true,true,false,1,0,
 jsonb_build_object('purpose','Route a confirmed effect only through a narrow allowlist while retaining original testimony evidence; unavailable destinations remain preserved.','genericDomainWriter',false),now()),
('atlas.personal_reality_capture_self_api_v1(p_capture_id uuid)','app_endpoint','verified','active',true,true,true,false,1,0,
 jsonb_build_object('purpose','Read one spontaneous personal reality capture and its interpretation workflow without collapsing workflow state into domain truth.'),now())
on conflict(signature) do update set
  classification=excluded.classification,confidence=excluded.confidence,review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  evidence=atlas.authenticated_rpc_registry.evidence||excluded.evidence,
  reviewed_at=now();
