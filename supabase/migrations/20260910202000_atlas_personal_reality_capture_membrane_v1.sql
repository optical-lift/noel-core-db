-- Personal Reality Capture Membrane v1
-- Raw testimony is preserved once before subject, timing, action, capacity, or Claim interpretation.
-- Readiness, human decision, and destination routing are separate states.
-- Human confirmation requires a short-lived trusted-surface receipt; an authenticated session alone is not confirmation.
-- Downstream truth remains owned by its domain writer. Missing destinations fail closed and remain retryable.

create table if not exists atlas.personal_reality_captures (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  source_action_id text not null,
  testimony text not null,
  evidence_id uuid not null references atlas.evidence_records(id) on delete restrict,
  capture_state text not null default 'captured' check (capture_state in ('captured','interpreted','resolved')),
  source_surface text not null default 'tell_atlas',
  capture_context jsonb not null default '{}'::jsonb check (jsonb_typeof(capture_context)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  captured_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_user_id,source_action_id),
  check (btrim(source_action_id)<>''),
  check (btrim(testimony)<>''),
  check (btrim(source_surface)<>'')
);
comment on table atlas.personal_reality_captures is
  'Workflow envelope for spontaneous first-party testimony. Raw Evidence is deliberately subject-unresolved; interpretation happens later.';
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
  effect_kind text not null check (effect_kind in ('claim','capacity_block','capacity_adjustment','one_off_action','fact_only')),
  proposal jsonb not null check (jsonb_typeof(proposal)='object'),
  interpreter_kind text not null check (interpreter_kind in ('self_authenticated','ai','rule','import')),
  interpreter_ref text not null,
  confidence numeric(5,4) check (confidence is null or confidence between 0 and 1),
  explanation text,
  readiness_state text not null check (readiness_state in ('ready_for_confirmation','needs_clarification')),
  validation jsonb not null check (jsonb_typeof(validation)='object'),
  decision_state text not null default 'pending' check (decision_state in ('pending','confirmed','rejected','revoked')),
  route_state text not null default 'not_ready' check (route_state in ('not_ready','ready','applied','destination_unavailable','superseded')),
  decision_receipt_id uuid,
  supersedes_proposal_id uuid references atlas.personal_reality_effect_proposals(id) on delete restrict,
  confirmed_at timestamptz,
  rejected_at timestamptz,
  revoked_at timestamptz,
  applied_at timestamptz,
  destination_kind text,
  destination_id text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(capture_id,effect_key),
  check (btrim(effect_key)<>''),
  check (btrim(interpreter_ref)<>''),
  check (supersedes_proposal_id is null or supersedes_proposal_id<>id),
  check (
    (decision_state='pending' and route_state='not_ready' and decision_receipt_id is null)
    or (decision_state='rejected' and route_state='not_ready' and decision_receipt_id is not null)
    or (decision_state='confirmed' and route_state in ('ready','applied','destination_unavailable') and decision_receipt_id is not null)
    or (decision_state='revoked' and route_state in ('not_ready','superseded'))
  )
);
comment on table atlas.personal_reality_effect_proposals is
  'Immutable interpretation proposal with readiness, human decision, and downstream routing modeled separately.';
create index if not exists personal_reality_effect_proposals_capture_idx
  on atlas.personal_reality_effect_proposals(capture_id,decision_state,route_state,created_at,id);
create index if not exists personal_reality_effect_proposals_supersedes_idx
  on atlas.personal_reality_effect_proposals(supersedes_proposal_id) where supersedes_proposal_id is not null;
alter table atlas.personal_reality_effect_proposals enable row level security;
revoke all on atlas.personal_reality_effect_proposals from public,anon,authenticated;

create table if not exists atlas.personal_reality_human_decision_receipts (
  id uuid primary key default gen_random_uuid(),
  proposal_id uuid not null references atlas.personal_reality_effect_proposals(id) on delete cascade,
  capture_id uuid not null references atlas.personal_reality_captures(id) on delete cascade,
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  decision text not null check (decision in ('confirm','reject')),
  interaction_kind text not null default 'explicit_user_action' check (interaction_kind='explicit_user_action'),
  interaction_ref text not null,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null default (now()+interval '15 minutes'),
  consumed_at timestamptz,
  consumed_by_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  unique(owner_user_id,interaction_ref),
  check (btrim(interaction_ref)<>''),
  check (expires_at>issued_at),
  check ((consumed_at is null)=(consumed_by_user_id is null))
);
comment on table atlas.personal_reality_human_decision_receipts is
  'Short-lived capability proving a trusted Atlas surface observed an explicit user decision for one proposal.';
create index if not exists personal_reality_human_decision_receipts_proposal_idx
  on atlas.personal_reality_human_decision_receipts(proposal_id,issued_at desc,id);
alter table atlas.personal_reality_human_decision_receipts enable row level security;
revoke all on atlas.personal_reality_human_decision_receipts from public,anon,authenticated;

alter table atlas.personal_reality_effect_proposals
  add constraint personal_reality_effect_proposals_decision_receipt_fkey
  foreign key(decision_receipt_id) references atlas.personal_reality_human_decision_receipts(id) on delete restrict;

create table if not exists atlas.personal_reality_effect_events (
  id uuid primary key default gen_random_uuid(),
  proposal_id uuid not null references atlas.personal_reality_effect_proposals(id) on delete cascade,
  capture_id uuid not null references atlas.personal_reality_captures(id) on delete cascade,
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  authority_receipt_id uuid references atlas.personal_reality_human_decision_receipts(id) on delete set null,
  event_kind text not null check (event_kind in ('proposed','confirmed','rejected','applied','destination_unavailable','superseded')),
  state_axis text not null check (state_axis in ('proposal','decision','route')),
  from_state text,
  to_state text not null,
  detail jsonb not null default '{}'::jsonb check (jsonb_typeof(detail)='object'),
  occurred_at timestamptz not null default now()
);
create index if not exists personal_reality_effect_events_proposal_idx
  on atlas.personal_reality_effect_events(proposal_id,occurred_at,id);
alter table atlas.personal_reality_effect_events enable row level security;
revoke all on atlas.personal_reality_effect_events from public,anon,authenticated;

create or replace function atlas.personal_reality_effect_proposal_immutable_guard_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
begin
  if old.capture_id is distinct from new.capture_id
    or old.principal_id is distinct from new.principal_id
    or old.owner_user_id is distinct from new.owner_user_id
    or old.effect_key is distinct from new.effect_key
    or old.effect_kind is distinct from new.effect_kind
    or old.proposal is distinct from new.proposal
    or old.interpreter_kind is distinct from new.interpreter_kind
    or old.interpreter_ref is distinct from new.interpreter_ref
    or old.confidence is distinct from new.confidence
    or old.explanation is distinct from new.explanation
    or old.readiness_state is distinct from new.readiness_state
    or old.validation is distinct from new.validation
    or old.supersedes_proposal_id is distinct from new.supersedes_proposal_id
    or old.metadata is distinct from new.metadata then
    raise exception 'Personal reality proposal content is immutable; create a superseding proposal instead.' using errcode='23514';
  end if;
  return new;
end;$function$;
revoke all on function atlas.personal_reality_effect_proposal_immutable_guard_v1() from public,anon,authenticated;
drop trigger if exists personal_reality_effect_proposal_immutable_guard_v1 on atlas.personal_reality_effect_proposals;
create trigger personal_reality_effect_proposal_immutable_guard_v1
before update on atlas.personal_reality_effect_proposals
for each row execute function atlas.personal_reality_effect_proposal_immutable_guard_v1();

create or replace function atlas.personal_reality_timestamp_is_explicit_v1(p_value text)
returns boolean language sql immutable set search_path=pg_catalog as $function$
  select p_value is not null and btrim(p_value)<>'' and btrim(p_value) ~* '(Z|[+-][0-9]{2}:[0-9]{2})$';
$function$;
revoke all on function atlas.personal_reality_timestamp_is_explicit_v1(text) from public,anon,authenticated;

create or replace function atlas.personal_reality_effect_validation_v1(p_kind text,p_body jsonb)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas as $function$
declare
  issues jsonb:='[]'::jsonb; tp jsonb; tz text; rk text; a timestamptz; b timestamptz; n numeric;
  has_time boolean:=false; k text:=coalesce(p_kind,''); v text;
begin
  if p_body is null or jsonb_typeof(p_body)<>'object' then
    return jsonb_build_object('readyForConfirmation',false,'issues',jsonb_build_array('proposal_object_required'));
  end if;
  if k='claim' then
    if nullif(btrim(p_body#>>'{subject,domain}'),'') is null then issues:=issues||'"subject_domain_required"'::jsonb; end if;
    if nullif(btrim(p_body#>>'{subject,kind}'),'') is null then issues:=issues||'"subject_kind_required"'::jsonb; end if;
    if nullif(btrim(p_body#>>'{subject,id}'),'') is null then issues:=issues||'"subject_identity_required"'::jsonb; end if;
    if nullif(btrim(p_body#>>'{claim,claimType}'),'') is null then issues:=issues||'"claim_type_required"'::jsonb; end if;
    if nullif(btrim(p_body#>>'{claim,lifecycleState}'),'') is null then issues:=issues||'"claim_lifecycle_required"'::jsonb;
    elsif p_body#>>'{claim,lifecycleState}' not in ('reported','observed','accepted','rejected','unknown') then issues:=issues||'"claim_lifecycle_not_first_party"'::jsonb; end if;
    if not coalesce((p_body->'claim')?'value',false) then issues:=issues||'"claim_value_required"'::jsonb; end if;
    if nullif(p_body#>>'{claim,validFrom}','') is not null then
      has_time:=true; v:=p_body#>>'{claim,validFrom}';
      if not atlas.personal_reality_timestamp_is_explicit_v1(v) then issues:=issues||'"claim_valid_from_requires_explicit_offset"'::jsonb;
      else begin a:=v::timestamptz; exception when others then issues:=issues||'"claim_valid_from_invalid"'::jsonb; end; end if;
    end if;
    if nullif(p_body#>>'{claim,validUntil}','') is not null then
      has_time:=true; v:=p_body#>>'{claim,validUntil}';
      if not atlas.personal_reality_timestamp_is_explicit_v1(v) then issues:=issues||'"claim_valid_until_requires_explicit_offset"'::jsonb;
      else begin b:=v::timestamptz; exception when others then issues:=issues||'"claim_valid_until_invalid"'::jsonb; end; end if;
    end if;
    if a is not null and b is not null and b<a then issues:=issues||'"claim_valid_until_precedes_valid_from"'::jsonb; end if;
    if has_time then tp:=p_body->'timingProvenance'; end if;
  elsif k='one_off_action' then
    if nullif(btrim(p_body->>'title'),'') is null then issues:=issues||'"action_title_required"'::jsonb; end if;
    if p_body?'expectedMinutes' then
      if jsonb_typeof(p_body->'expectedMinutes')<>'number' then issues:=issues||'"expected_minutes_invalid"'::jsonb;
      else n:=(p_body->>'expectedMinutes')::numeric; if n<=0 or trunc(n)<>n then issues:=issues||'"expected_minutes_must_be_positive_integer"'::jsonb; end if; end if;
    end if;
    has_time:=nullif(p_body->>'becomesRelevantAt','') is not null or nullif(p_body->>'mustFinishBy','') is not null
      or nullif(p_body->>'preferredWindowStart','') is not null or nullif(p_body->>'preferredWindowEnd','') is not null;
    if (nullif(p_body->>'preferredWindowStart','') is null) <> (nullif(p_body->>'preferredWindowEnd','') is null) then issues:=issues||'"preferred_window_requires_both_boundaries"'::jsonb; end if;
    foreach v in array array[p_body->>'becomesRelevantAt',p_body->>'mustFinishBy',p_body->>'preferredWindowStart',p_body->>'preferredWindowEnd'] loop
      if nullif(btrim(v),'') is not null then
        if not atlas.personal_reality_timestamp_is_explicit_v1(v) then issues:=issues||'"action_time_requires_explicit_offset"'::jsonb;
        else begin perform v::timestamptz; exception when others then issues:=issues||'"action_time_invalid"'::jsonb; end; end if;
      end if;
    end loop;
    begin a:=nullif(p_body->>'becomesRelevantAt','')::timestamptz; exception when others then a:=null; end;
    begin b:=nullif(p_body->>'mustFinishBy','')::timestamptz; exception when others then b:=null; end;
    if a is not null and b is not null and b<a then issues:=issues||'"action_finish_precedes_relevance"'::jsonb; end if;
    if atlas.personal_reality_timestamp_is_explicit_v1(p_body->>'preferredWindowStart') and atlas.personal_reality_timestamp_is_explicit_v1(p_body->>'preferredWindowEnd') then
      begin a:=(p_body->>'preferredWindowStart')::timestamptz; b:=(p_body->>'preferredWindowEnd')::timestamptz;
        if b<=a then issues:=issues||'"preferred_window_must_be_positive"'::jsonb; end if; exception when others then null; end;
    end if;
    if has_time then tp:=p_body->'timingProvenance'; end if;
  elsif k='capacity_block' then
    if nullif(btrim(p_body->>'title'),'') is null then issues:=issues||'"capacity_title_required"'::jsonb; end if;
    if nullif(btrim(p_body->>'blockKind'),'') is null then issues:=issues||'"capacity_block_kind_required"'::jsonb;
    elsif p_body->>'blockKind' not in ('human_fixed','household','family','travel','appointment','recovery','other') then issues:=issues||'"capacity_block_kind_not_unavailability"'::jsonb; end if;
    if not atlas.personal_reality_timestamp_is_explicit_v1(p_body->>'startsAt') then issues:=issues||'"capacity_start_requires_explicit_offset"'::jsonb; end if;
    if not atlas.personal_reality_timestamp_is_explicit_v1(p_body->>'endsAt') then issues:=issues||'"capacity_end_requires_explicit_offset"'::jsonb; end if;
    if atlas.personal_reality_timestamp_is_explicit_v1(p_body->>'startsAt') and atlas.personal_reality_timestamp_is_explicit_v1(p_body->>'endsAt') then
      begin a:=(p_body->>'startsAt')::timestamptz; b:=(p_body->>'endsAt')::timestamptz; if b<=a then issues:=issues||'"capacity_interval_must_be_positive"'::jsonb; end if;
      exception when others then issues:=issues||'"capacity_interval_invalid"'::jsonb; end;
    end if;
    tp:=p_body->'timingProvenance';
  elsif k='capacity_adjustment' then
    if nullif(btrim(p_body->>'title'),'') is null then issues:=issues||'"capacity_adjustment_title_required"'::jsonb; end if;
    if not atlas.personal_reality_timestamp_is_explicit_v1(p_body->>'startsAt') then issues:=issues||'"capacity_adjustment_start_requires_explicit_offset"'::jsonb; end if;
    if not atlas.personal_reality_timestamp_is_explicit_v1(p_body->>'endsAt') then issues:=issues||'"capacity_adjustment_end_requires_explicit_offset"'::jsonb; end if;
    if not (p_body?'availabilityFraction') then issues:=issues||'"availability_fraction_required"'::jsonb; end if;
    if p_body?'availabilityFraction' then
      if jsonb_typeof(p_body->'availabilityFraction')<>'number' then issues:=issues||'"availability_fraction_invalid"'::jsonb;
      else n:=(p_body->>'availabilityFraction')::numeric; if n<=0 or n>=1 then issues:=issues||'"availability_fraction_must_be_between_zero_and_one"'::jsonb; end if; end if;
    end if;
    if p_body?'maximumPlannedMinutes' then issues:=issues||'"maximum_planned_minutes_not_allowed_for_capacity_adjustment"'::jsonb; end if;
    if p_body?'discretionaryCapacityMinutes' then issues:=issues||'"discretionary_capacity_minutes_not_allowed_for_capacity_adjustment"'::jsonb; end if;
    if atlas.personal_reality_timestamp_is_explicit_v1(p_body->>'startsAt') and atlas.personal_reality_timestamp_is_explicit_v1(p_body->>'endsAt') then
      begin a:=(p_body->>'startsAt')::timestamptz; b:=(p_body->>'endsAt')::timestamptz; if b<=a then issues:=issues||'"capacity_adjustment_interval_must_be_positive"'::jsonb; end if;
      exception when others then issues:=issues||'"capacity_adjustment_interval_invalid"'::jsonb; end;
    end if;
    tp:=p_body->'timingProvenance';
  elsif k<>'fact_only' then issues:=issues||'"unsupported_effect_kind"'::jsonb; end if;

  if tp is not null then
    if jsonb_typeof(tp)<>'object' then issues:=issues||'"timing_provenance_required"'::jsonb;
    else
      if nullif(btrim(tp->>'sourceText'),'') is null then issues:=issues||'"timing_source_text_required"'::jsonb; end if;
      tz:=nullif(btrim(tp->>'timezone'),'');
      if tz is null then issues:=issues||'"timing_timezone_required"'::jsonb;
      elsif not exists(select 1 from pg_catalog.pg_timezone_names where name=tz) then issues:=issues||'"timing_timezone_unknown"'::jsonb; end if;
      rk:=nullif(btrim(tp->>'resolutionKind'),'');
      if rk is null then issues:=issues||'"timing_resolution_kind_required"'::jsonb;
      elsif rk not in ('explicit_absolute','explicit_local','human_clarified','source_context') then issues:=issues||'"timing_resolution_kind_invalid"'::jsonb; end if;
    end if;
  elsif has_time or k in ('capacity_block','capacity_adjustment') then issues:=issues||'"timing_provenance_required"'::jsonb; end if;
  return jsonb_build_object('readyForConfirmation',jsonb_array_length(issues)=0,'issues',issues,
    'truthBoundary',jsonb_build_object('validationDoesNotConfirmTruth',true,'missingIdentityRequiresClarification',true,'relativeTimeIsNotSilentlyNormalized',true,'reducedCapacityIsDistinctFromCapacityBlock',true));
end;$function$;
revoke all on function atlas.personal_reality_effect_validation_v1(text,jsonb) from public,anon,authenticated;

create or replace function atlas.refresh_personal_reality_capture_state_v1(p_capture_id uuid)
returns text language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare s text;
begin
  if not exists(select 1 from atlas.personal_reality_effect_proposals p where p.capture_id=p_capture_id) then s:='captured';
  elsif exists(select 1 from atlas.personal_reality_effect_proposals p where p.capture_id=p_capture_id
    and (p.decision_state='pending' or (p.decision_state='confirmed' and p.route_state in ('ready','destination_unavailable')))) then s:='interpreted';
  else s:='resolved'; end if;
  update atlas.personal_reality_captures set capture_state=s,updated_at=now() where id=p_capture_id;
  return s;
end;$function$;
revoke all on function atlas.refresh_personal_reality_capture_state_v1(uuid) from public,anon,authenticated;

create or replace function atlas.capture_personal_reality_self_api_v1(p_input jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare
  u uuid:=auth.uid(); p atlas.principals%rowtype; key text; txt text; surface text; source_text text; source_at timestamptz; basis text;
  ctx jsonb; md jsonb; prov jsonb; emd jsonb; eid uuid; ev atlas.evidence_records%rowtype; cap atlas.personal_reality_captures%rowtype; old atlas.personal_reality_captures%rowtype; made boolean:=false;
begin
  if u is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then raise exception 'Personal reality capture input must be an object.' using errcode='22023'; end if;
  select * into p from atlas.principals x where x.user_id=u and x.status='active' limit 1;
  if p.id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;
  key:=nullif(btrim(p_input->>'sourceActionId'),''); txt:=nullif(btrim(p_input->>'testimony'),'');
  surface:=coalesce(nullif(btrim(p_input->>'sourceSurface'),''),'tell_atlas'); source_text:=nullif(btrim(p_input->>'sourceOccurredAt'),''); basis:=nullif(btrim(p_input->>'sourceTimeBasis'),'');
  ctx:=coalesce(case when jsonb_typeof(p_input->'captureContext')='object' then p_input->'captureContext' end,'{}'::jsonb);
  md:=coalesce(case when jsonb_typeof(p_input->'metadata')='object' then p_input->'metadata' end,'{}'::jsonb);
  if key is null or txt is null then raise exception 'sourceActionId and testimony are required.' using errcode='22023'; end if;
  if source_text is not null then
    if not atlas.personal_reality_timestamp_is_explicit_v1(source_text) or basis is null then raise exception 'sourceOccurredAt requires an explicit offset and sourceTimeBasis.' using errcode='22023'; end if;
    source_at:=source_text::timestamptz;
  elsif basis is not null then raise exception 'sourceTimeBasis requires sourceOccurredAt.' using errcode='22023'; end if;
  prov:=jsonb_strip_nulls(jsonb_build_object('sourceSurface',surface,'sourceActionId',key,'sourceTimeBasis',basis));
  emd:=md||jsonb_build_object('captureContract','personal_reality_capture_v1','captureContext',ctx,'subjectUnresolvedAtRawCapture',true);
  insert into atlas.evidence_records(scope_kind,scope_id,subject_domain,subject_kind,subject_id,evidence_kind,source_kind,source_key,actor_user_id,value,confidence,observed_at,effective_from,effective_until,provenance,metadata)
  values('person',u,'personal_reality','unresolved_testimony',key,'first_party_testimony','personal_reality_capture',key,u,to_jsonb(txt),1,source_at,null,null,prov,emd)
  on conflict(scope_kind,scope_id,source_kind,source_key) do nothing returning id into eid;
  if eid is null then
    select * into ev from atlas.evidence_records e where e.scope_kind='person' and e.scope_id=u and e.source_kind='personal_reality_capture' and e.source_key=key;
    if ev.id is null or ev.subject_domain is distinct from 'personal_reality' or ev.subject_kind is distinct from 'unresolved_testimony' or ev.subject_id is distinct from key
      or ev.evidence_kind is distinct from 'first_party_testimony' or ev.actor_user_id is distinct from u or ev.value is distinct from to_jsonb(txt)
      or ev.confidence is distinct from 1::numeric or ev.observed_at is distinct from source_at or ev.effective_from is not null or ev.effective_until is not null
      or ev.provenance is distinct from prov or ev.metadata is distinct from emd then raise exception 'sourceActionId retry does not match existing testimony evidence.' using errcode='23505'; end if;
    eid:=ev.id;
  end if;
  insert into atlas.personal_reality_captures(principal_id,owner_user_id,source_action_id,testimony,evidence_id,source_surface,capture_context,metadata)
  values(p.id,u,key,txt,eid,surface,ctx,md) on conflict(owner_user_id,source_action_id) do nothing returning * into cap;
  if cap.id is null then
    select * into old from atlas.personal_reality_captures c where c.owner_user_id=u and c.source_action_id=key;
    if old.id is null or old.principal_id is distinct from p.id or old.testimony is distinct from txt or old.evidence_id is distinct from eid
      or old.source_surface is distinct from surface or old.capture_context is distinct from ctx or old.metadata is distinct from md then
      raise exception 'sourceActionId retry does not match existing personal reality capture.' using errcode='23505'; end if;
    cap:=old;
  else made:=true; end if;
  return jsonb_build_object('ok',true,'created',made,'contractVersion','personal_reality_capture_v1','captureId',cap.id,'evidenceId',cap.evidence_id,'captureState',cap.capture_state,'testimony',cap.testimony,
    'truthBoundary',jsonb_build_object('testimonyPreservedOnce',true,'rawCaptureSubjectRemainsUnresolved',true,'captureIsNotClaim',true,'captureDoesNotCreateTask',true,'captureDoesNotCreateClockPlacement',true));
end;$function$;

create or replace function atlas.propose_personal_reality_effects_internal_v1(p_owner_user_id uuid,p_capture_id uuid,p_effects jsonb,p_interpreter_kind text,p_interpreter_ref text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare
  cap atlas.personal_reality_captures%rowtype; old atlas.personal_reality_effect_proposals%rowtype; superseded atlas.personal_reality_effect_proposals%rowtype; rowv atlas.personal_reality_effect_proposals%rowtype;
  x jsonb; ek text; kind text; body jsonb; conf numeric; expl text; md jsonb; validation jsonb; readiness text; sid uuid; items jsonb:='[]'::jsonb;
begin
  if p_owner_user_id is null or p_capture_id is null or p_effects is null or jsonb_typeof(p_effects)<>'array' then raise exception 'owner, captureId, and effects array are required.' using errcode='22023'; end if;
  if p_interpreter_kind not in ('self_authenticated','ai','rule','import') or nullif(btrim(p_interpreter_ref),'') is null then raise exception 'Valid interpreter provenance is required.' using errcode='22023'; end if;
  select * into cap from atlas.personal_reality_captures c where c.id=p_capture_id and c.owner_user_id=p_owner_user_id for update;
  if cap.id is null then raise exception 'Personal reality capture not found.' using errcode='P0002'; end if;
  for x in select value from jsonb_array_elements(p_effects) loop
    if jsonb_typeof(x)<>'object' then raise exception 'Each effect proposal must be an object.' using errcode='22023'; end if;
    ek:=nullif(btrim(x->>'effectKey'),''); kind:=nullif(btrim(x->>'effectKind'),''); body:=x->'proposal'; expl:=nullif(btrim(x->>'explanation'),'');
    conf:=case when x?'confidence' then (x->>'confidence')::numeric else null end; md:=coalesce(case when jsonb_typeof(x->'metadata')='object' then x->'metadata' end,'{}'::jsonb); sid:=nullif(x->>'supersedesProposalId','')::uuid;
    if ek is null or kind is null or jsonb_typeof(body)<>'object' then raise exception 'effectKey, effectKind, and proposal are required.' using errcode='22023'; end if;
    if kind not in ('claim','capacity_block','capacity_adjustment','one_off_action','fact_only') then raise exception 'Unsupported effectKind.' using errcode='22023'; end if;
    if conf is not null and (conf<0 or conf>1) then raise exception 'Effect confidence must be between 0 and 1.' using errcode='22023'; end if;
    if sid is not null then
      select * into superseded from atlas.personal_reality_effect_proposals p where p.id=sid and p.owner_user_id=p_owner_user_id and p.principal_id=cap.principal_id;
      if superseded.id is null then raise exception 'supersedesProposalId must identify this Principal own proposal.' using errcode='42501'; end if;
      if superseded.decision_state='revoked' or superseded.route_state='superseded' then raise exception 'Supersede the current proposal, not an obsolete proposal.' using errcode='23505'; end if;
    end if;
    validation:=atlas.personal_reality_effect_validation_v1(kind,body); readiness:=case when coalesce((validation->>'readyForConfirmation')::boolean,false) then 'ready_for_confirmation' else 'needs_clarification' end;
    select * into old from atlas.personal_reality_effect_proposals p where p.capture_id=cap.id and p.effect_key=ek;
    if old.id is not null then
      if old.effect_kind is distinct from kind or old.proposal is distinct from body or old.interpreter_kind is distinct from p_interpreter_kind
        or old.interpreter_ref is distinct from p_interpreter_ref or old.confidence is distinct from conf or old.explanation is distinct from expl
        or old.readiness_state is distinct from readiness or old.validation is distinct from validation or old.supersedes_proposal_id is distinct from sid or old.metadata is distinct from md then
        raise exception 'effectKey retry does not match existing effect proposal.' using errcode='23505'; end if;
      items:=items||jsonb_build_array(to_jsonb(old)); continue;
    end if;
    insert into atlas.personal_reality_effect_proposals(capture_id,principal_id,owner_user_id,effect_key,effect_kind,proposal,interpreter_kind,interpreter_ref,confidence,explanation,readiness_state,validation,supersedes_proposal_id,metadata)
    values(cap.id,cap.principal_id,p_owner_user_id,ek,kind,body,p_interpreter_kind,p_interpreter_ref,conf,expl,readiness,validation,sid,md)
    on conflict(capture_id,effect_key) do nothing returning * into rowv;
    if rowv.id is null then
      select * into old from atlas.personal_reality_effect_proposals p where p.capture_id=cap.id and p.effect_key=ek;
      if old.id is null or old.effect_kind is distinct from kind or old.proposal is distinct from body or old.interpreter_kind is distinct from p_interpreter_kind or old.interpreter_ref is distinct from p_interpreter_ref
        or old.confidence is distinct from conf or old.explanation is distinct from expl or old.readiness_state is distinct from readiness or old.validation is distinct from validation or old.supersedes_proposal_id is distinct from sid or old.metadata is distinct from md then
        raise exception 'effectKey retry does not match concurrently created effect proposal.' using errcode='23505'; end if;
      items:=items||jsonb_build_array(to_jsonb(old)); continue;
    end if;
    insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,event_kind,state_axis,from_state,to_state,detail)
    values(rowv.id,cap.id,cap.principal_id,case when p_interpreter_kind='self_authenticated' then p_owner_user_id else null end,'proposed','proposal',null,'proposed',jsonb_build_object('interpreterKind',p_interpreter_kind,'interpreterRef',p_interpreter_ref,'effectKind',kind,'readinessState',readiness));
    items:=items||jsonb_build_array(to_jsonb(rowv));
  end loop;
  perform atlas.refresh_personal_reality_capture_state_v1(cap.id);
  return jsonb_build_object('ok',true,'contractVersion','personal_reality_effect_proposal_v1','captureId',cap.id,'evidenceId',cap.evidence_id,'effects',items,
    'truthBoundary',jsonb_build_object('proposalIsNotTruth',true,'interpreterKindComesFromTrustedRouteNotPayload',true,'selfAuthenticatedDoesNotMeanHumanConfirmed',true,'needsClarificationCannotBeConfirmed',true));
end;$function$;
revoke all on function atlas.propose_personal_reality_effects_internal_v1(uuid,uuid,jsonb,text,text) from public,anon,authenticated,service_role;

create or replace function atlas.propose_personal_reality_effects_self_api_v1(p_capture_id uuid,p_effects jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare u uuid:=auth.uid(); x jsonb;
begin
  if u is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_effects is not null and jsonb_typeof(p_effects)='array' then
    for x in select value from jsonb_array_elements(p_effects) loop if x?'interpreterKind' or x?'interpreterRef' then raise exception 'Interpreter identity is assigned by the route.' using errcode='22023'; end if; end loop;
  end if;
  return atlas.propose_personal_reality_effects_internal_v1(u,p_capture_id,p_effects,'self_authenticated','self_api');
end;$function$;

create or replace function atlas.propose_personal_reality_effects_serv_v1(p_owner_user_id uuid,p_capture_id uuid,p_effects jsonb,p_interpreter_kind text,p_interpreter_ref text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
begin
  if p_interpreter_kind not in ('ai','rule','import') then raise exception 'Service interpreter kind must be ai, rule, or import.' using errcode='22023'; end if;
  return atlas.propose_personal_reality_effects_internal_v1(p_owner_user_id,p_capture_id,p_effects,p_interpreter_kind,p_interpreter_ref);
end;$function$;
revoke all on function atlas.propose_personal_reality_effects_serv_v1(uuid,uuid,jsonb,text,text) from public,anon,authenticated;
grant execute on function atlas.propose_personal_reality_effects_serv_v1(uuid,uuid,jsonb,text,text) to service_role;

create or replace function atlas.issue_personal_reality_human_decision_receipt_serv_v1(p_owner_user_id uuid,p_proposal_id uuid,p_decision text,p_interaction_ref text,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare q atlas.personal_reality_effect_proposals%rowtype; r atlas.personal_reality_human_decision_receipts%rowtype; old atlas.personal_reality_human_decision_receipts%rowtype;
  d text:=lower(nullif(btrim(p_decision),'')); ir text:=nullif(btrim(p_interaction_ref),''); md jsonb:=coalesce(case when jsonb_typeof(p_metadata)='object' then p_metadata end,'{}'::jsonb); made boolean:=false;
begin
  if p_owner_user_id is null or p_proposal_id is null or d is null or ir is null then raise exception 'ownerUserId, proposalId, decision, and interactionRef are required.' using errcode='22023'; end if;
  if d not in ('confirm','reject') then raise exception 'decision must be confirm or reject.' using errcode='22023'; end if;
  select * into q from atlas.personal_reality_effect_proposals p where p.id=p_proposal_id and p.owner_user_id=p_owner_user_id;
  if q.id is null then raise exception 'Effect proposal not found for owner.' using errcode='P0002'; end if;
  if q.decision_state<>'pending' then raise exception 'Decision receipt can only be issued for a pending proposal.' using errcode='22023'; end if;
  if d='confirm' and q.readiness_state<>'ready_for_confirmation' then raise exception 'Proposal needs clarification before confirmation.' using errcode='22023'; end if;
  insert into atlas.personal_reality_human_decision_receipts(proposal_id,capture_id,principal_id,owner_user_id,decision,interaction_ref,metadata)
  values(q.id,q.capture_id,q.principal_id,p_owner_user_id,d,ir,md) on conflict(owner_user_id,interaction_ref) do nothing returning * into r;
  if r.id is null then
    select * into old from atlas.personal_reality_human_decision_receipts x where x.owner_user_id=p_owner_user_id and x.interaction_ref=ir;
    if old.id is null or old.proposal_id is distinct from q.id or old.decision is distinct from d or old.metadata is distinct from md then raise exception 'interactionRef retry does not match existing receipt.' using errcode='23505'; end if; r:=old;
  else made:=true; end if;
  return jsonb_build_object('ok',true,'created',made,'contractVersion','personal_reality_human_decision_receipt_v1','receiptId',r.id,'proposalId',r.proposal_id,'decision',r.decision,'expiresAt',r.expires_at,
    'truthBoundary',jsonb_build_object('receiptProvesTrustedSurfaceObservedExplicitUserAction',true,'receiptDoesNotApplyEffect',true,'authenticatedSessionAloneIsNotHumanConfirmation',true));
end;$function$;
revoke all on function atlas.issue_personal_reality_human_decision_receipt_serv_v1(uuid,uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function atlas.issue_personal_reality_human_decision_receipt_serv_v1(uuid,uuid,text,text,jsonb) to service_role;

create or replace function atlas.confirm_personal_reality_effect_self_api_v1(p_proposal_id uuid,p_receipt_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare u uuid:=auth.uid(); q atlas.personal_reality_effect_proposals%rowtype; cap atlas.personal_reality_captures%rowtype; r atlas.personal_reality_human_decision_receipts%rowtype; td text; tr text; cs text;
begin
  if u is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into q from atlas.personal_reality_effect_proposals p where p.id=p_proposal_id and p.owner_user_id=u for update;
  if q.id is null then raise exception 'Effect proposal not found.' using errcode='P0002'; end if;
  select * into cap from atlas.personal_reality_captures c where c.id=q.capture_id and c.owner_user_id=u;
  select * into r from atlas.personal_reality_human_decision_receipts x where x.id=p_receipt_id and x.proposal_id=q.id and x.owner_user_id=u for update;
  if r.id is null then raise exception 'Human decision receipt not found for proposal.' using errcode='42501'; end if;
  td:=case when r.decision='confirm' then 'confirmed' else 'rejected' end; tr:=case when r.decision='confirm' then 'ready' else 'not_ready' end;
  if r.consumed_at is not null then
    if q.decision_receipt_id=r.id and q.decision_state=td then return jsonb_build_object('ok',true,'changed',false,'proposal',to_jsonb(q),'captureState',cap.capture_state); end if;
    raise exception 'Human decision receipt already consumed.' using errcode='23505';
  end if;
  if r.expires_at<=now() then raise exception 'Human decision receipt expired.' using errcode='22023'; end if;
  if q.decision_state<>'pending' then raise exception 'Proposal already decided; correct with a superseding proposal.' using errcode='23505'; end if;
  if r.decision='confirm' and q.readiness_state<>'ready_for_confirmation' then raise exception 'Proposal needs clarification before confirmation.' using errcode='22023'; end if;
  update atlas.personal_reality_human_decision_receipts set consumed_at=now(),consumed_by_user_id=u where id=r.id;
  update atlas.personal_reality_effect_proposals set decision_state=td,route_state=tr,decision_receipt_id=r.id,
    confirmed_at=case when r.decision='confirm' then now() else null end,rejected_at=case when r.decision='reject' then now() else null end,updated_at=now()
  where id=q.id returning * into q;
  insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,authority_receipt_id,event_kind,state_axis,from_state,to_state,detail)
  values(q.id,cap.id,cap.principal_id,u,r.id,case when r.decision='confirm' then 'confirmed' else 'rejected' end,'decision','pending',td,jsonb_build_object('interactionKind',r.interaction_kind,'interactionRef',r.interaction_ref));
  if r.decision='confirm' then
    insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,authority_receipt_id,event_kind,state_axis,from_state,to_state,detail)
    values(q.id,cap.id,cap.principal_id,u,r.id,'confirmed','route','not_ready','ready',jsonb_build_object('authorizedByReceipt',r.id));
  end if;
  cs:=atlas.refresh_personal_reality_capture_state_v1(cap.id);
  return jsonb_build_object('ok',true,'changed',true,'contractVersion','personal_reality_effect_confirmation_v1','proposal',to_jsonb(q),'evidenceId',cap.evidence_id,'captureState',cs,
    'truthBoundary',jsonb_build_object('humanAuthorityComesFromConsumedReceipt',true,'confirmationIsNotApplication',true,'correctionRequiresSupersedingProposal',true));
end;$function$;

create or replace function atlas.record_person_claim_from_capture_evidence_v1(p_input jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare
  u uuid:=auth.uid(); raw_id uuid:=nullif(p_input->>'sourceEvidenceId','')::uuid; pid uuid:=nullif(p_input->>'proposalId','')::uuid; rid uuid:=nullif(p_input->>'decisionReceiptId','')::uuid;
  supersedes uuid:=nullif(p_input->>'supersedesClaimId','')::uuid; s jsonb:=p_input->'subject'; c jsonb:=p_input->'claim'; sd text; sk text; sid text; ct text; ls text; ak text; conf numeric;
  vf timestamptz; vu timestamptz; md jsonb; eid uuid; cid uuid; old atlas.claim_records%rowtype; ec atlas.claim_records%rowtype; ee atlas.evidence_records%rowtype; v_source_key text; made boolean:=false;
begin
  if u is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if raw_id is null or pid is null or rid is null or jsonb_typeof(s)<>'object' or jsonb_typeof(c)<>'object' then raise exception 'sourceEvidenceId, proposalId, decisionReceiptId, subject, and claim are required.' using errcode='22023'; end if;
  if not exists(select 1 from atlas.evidence_records e where e.id=raw_id and e.scope_kind='person' and e.scope_id=u) then raise exception 'Source Evidence not owned by signed-in person.' using errcode='42501'; end if;
  if not exists(select 1 from atlas.personal_reality_human_decision_receipts r where r.id=rid and r.proposal_id=pid and r.owner_user_id=u and r.decision='confirm' and r.consumed_at is not null) then raise exception 'Consumed human confirmation receipt required.' using errcode='42501'; end if;
  sd:=nullif(btrim(s->>'domain'),''); sk:=nullif(btrim(s->>'kind'),''); sid:=nullif(btrim(s->>'id'),''); ct:=nullif(btrim(c->>'claimType'),''); ls:=nullif(btrim(c->>'lifecycleState'),'');
  if sd is null or sk is null or sid is null or ct is null or ls is null or not(c?'value') then raise exception 'Resolved subject and complete claim are required.' using errcode='22023'; end if;
  if ls not in ('reported','observed','accepted','rejected','unknown') then raise exception 'Unsupported human-confirmed claim lifecycle.' using errcode='22023'; end if;
  if c?'confidence' then conf:=(c->>'confidence')::numeric; if conf<0 or conf>1 then raise exception 'claim confidence must be 0..1.' using errcode='22023'; end if; end if;
  vf:=nullif(c->>'validFrom','')::timestamptz; vu:=nullif(c->>'validUntil','')::timestamptz; if vf is not null and vu is not null and vu<vf then raise exception 'validUntil precedes validFrom.' using errcode='22023'; end if;
  md:=coalesce(case when jsonb_typeof(c->'metadata')='object' then c->'metadata' end,'{}'::jsonb); v_source_key:='personal_reality_proposal:'||pid::text;
  if supersedes is not null then
    select * into old from atlas.claim_records x where x.id=supersedes and x.scope_kind='person' and x.scope_id=u and x.subject_domain=sd and x.subject_kind=sk and x.subject_id=sid;
    if old.id is null then raise exception 'supersedesClaimId must identify same-subject person claim.' using errcode='42501'; end if;
  end if;
  insert into atlas.evidence_records(scope_kind,scope_id,subject_domain,subject_kind,subject_id,evidence_kind,source_kind,source_key,actor_user_id,value,confidence,observed_at,effective_from,effective_until,provenance,metadata)
  values('person',u,sd,sk,sid,'human_confirmed_interpretation','personal_reality_claim_interpretation',v_source_key,u,c->'value',1,null,vf,vu,
    jsonb_build_object('sourceEvidenceId',raw_id,'proposalId',pid,'decisionReceiptId',rid),jsonb_build_object('rawTestimonyNotCopied',true))
  on conflict(scope_kind,scope_id,source_kind,source_key) do nothing returning id into eid;
  if eid is null then
    select * into ee from atlas.evidence_records e where e.scope_kind='person' and e.scope_id=u and e.source_kind='personal_reality_claim_interpretation' and e.source_key=v_source_key;
    if ee.id is null or ee.subject_domain is distinct from sd or ee.subject_kind is distinct from sk or ee.subject_id is distinct from sid or ee.value is distinct from c->'value' or ee.effective_from is distinct from vf or ee.effective_until is distinct from vu then raise exception 'proposal retry does not match interpretation Evidence.' using errcode='23505'; end if; eid:=ee.id;
  end if;
  ak:=case when supersedes is not null then 'person_correction' when ls='observed' then 'person_reported_observation' when ls='accepted' then 'person_acceptance' when ls='rejected' then 'person_rejection' else 'person_confirmed_interpretation' end;
  insert into atlas.claim_records(scope_kind,scope_id,subject_domain,subject_kind,subject_id,claim_type,lifecycle_state,authority_kind,source_kind,source_key,value,confidence,primary_evidence_id,supersedes_claim_id,valid_from,valid_until,metadata)
  values('person',u,sd,sk,sid,ct,ls,ak,'personal_reality_claim',v_source_key,c->'value',conf,eid,supersedes,vf,vu,md||jsonb_build_object('sourceEvidenceId',raw_id,'proposalId',pid,'decisionReceiptId',rid))
  on conflict(scope_kind,scope_id,source_kind,source_key) do nothing returning id into cid;
  if cid is null then
    select * into ec from atlas.claim_records x where x.scope_kind='person' and x.scope_id=u and x.source_kind='personal_reality_claim' and x.source_key=v_source_key;
    if ec.id is null or ec.subject_domain is distinct from sd or ec.subject_kind is distinct from sk or ec.subject_id is distinct from sid or ec.claim_type is distinct from ct or ec.value is distinct from c->'value' or ec.primary_evidence_id is distinct from eid or ec.supersedes_claim_id is distinct from supersedes then raise exception 'proposal retry does not match Claim.' using errcode='23505'; end if; cid:=ec.id;
  else made:=true; end if;
  insert into atlas.claim_evidence_links(claim_id,evidence_id,relation_kind,metadata) values(cid,eid,'supports',jsonb_build_object('primary',true)) on conflict(claim_id,evidence_id,relation_kind) do nothing;
  insert into atlas.claim_evidence_links(claim_id,evidence_id,relation_kind,metadata) values(cid,raw_id,'supports',jsonb_build_object('rawTestimony',true,'primary',false)) on conflict(claim_id,evidence_id,relation_kind) do nothing;
  if made and supersedes is not null then
    update atlas.claim_records set lifecycle_state='superseded',superseded_at=now() where id=supersedes and scope_kind='person' and scope_id=u and lifecycle_state<>'superseded';
    if not found then raise exception 'Claim being corrected already superseded.' using errcode='23505'; end if;
    insert into atlas.claim_evidence_links(claim_id,evidence_id,relation_kind,metadata) values(supersedes,raw_id,'corrects',jsonb_build_object('correctedByClaimId',cid)) on conflict(claim_id,evidence_id,relation_kind) do nothing;
  end if;
  return jsonb_build_object('ok',true,'created',made,'claimId',cid,'interpretationEvidenceId',eid,'sourceEvidenceId',raw_id);
end;$function$;
revoke all on function atlas.record_person_claim_from_capture_evidence_v1(jsonb) from public,anon,authenticated,service_role;

create or replace function atlas.personal_reality_destination_state_v1(p_kind text,p_id text)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas as $function$
declare s jsonb; r regclass; sn text; rn text;
begin
  if p_id is null then return null; end if;
  if p_kind='evidence_record' then select jsonb_build_object('exists',true,'evidenceId',e.id) into s from atlas.evidence_records e where e.id=p_id::uuid;
  elsif p_kind='claim_record' then select jsonb_build_object('exists',true,'claimId',c.id,'lifecycleState',c.lifecycle_state,'supersededAt',c.superseded_at) into s from atlas.claim_records c where c.id=p_id::uuid;
  elsif p_kind='principal_capacity_block' then select jsonb_build_object('exists',true,'capacityBlockId',b.id,'blocksCapacity',b.blocks_capacity,'startsAt',b.starts_at,'endsAt',b.ends_at) into s from atlas.principal_capacity_blocks b where b.id=p_id::uuid;
  elsif p_kind='principal_one_off_action' then
    r:=to_regclass('atlas.principal_one_off_actions'); if r is not null then select n.nspname,c.relname into sn,rn from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.oid=r;
      execute format('select jsonb_build_object(''exists'',true,''actionId'',id,''status'',status,''completedAt'',completed_at,''cancelledAt'',cancelled_at) from %I.%I where id=$1',sn,rn) into s using p_id::uuid; end if;
  elsif p_kind='principal_capacity_adjustment' then
    r:=to_regclass('atlas.principal_capacity_adjustments'); if r is not null then select n.nspname,c.relname into sn,rn from pg_class c join pg_namespace n on n.oid=r;
      execute format('select jsonb_build_object(''exists'',true,''adjustmentId'',id,''active'',active,''startsAt'',starts_at,''endsAt'',ends_at) from %I.%I where id=$1',sn,rn) into s using p_id::uuid; end if;
  end if;
  return coalesce(s,jsonb_build_object('exists',false));
exception when invalid_text_representation then return jsonb_build_object('exists',false,'invalidDestinationId',true);
end;$function$;
revoke all on function atlas.personal_reality_destination_state_v1(text,text) from public,anon,authenticated;

create or replace function atlas.apply_personal_reality_effect_self_api_v1(p_proposal_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare
  u uuid:=auth.uid(); q atlas.personal_reality_effect_proposals%rowtype; oldq atlas.personal_reality_effect_proposals%rowtype; cap atlas.personal_reality_captures%rowtype; body jsonb; result jsonb;
  dk text; did text; rb text; fn regprocedure; tfn regprocedure; fs text; fnm text; ts text; tnm text; source_key text; old_claim atlas.claim_records%rowtype;
  same_subject boolean:=false; old_reversed boolean:=false; old_dec text; old_route text; cs text;
begin
  if u is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into q from atlas.personal_reality_effect_proposals p where p.id=p_proposal_id and p.owner_user_id=u for update;
  if q.id is null then raise exception 'Effect proposal not found.' using errcode='P0002'; end if;
  select * into cap from atlas.personal_reality_captures c where c.id=q.capture_id and c.owner_user_id=u;
  if q.route_state='applied' then return jsonb_build_object('ok',true,'changed',false,'routeState','applied','destinationKind',q.destination_kind,'destinationId',q.destination_id,'destinationState',atlas.personal_reality_destination_state_v1(q.destination_kind,q.destination_id)); end if;
  if q.decision_state<>'confirmed' or q.decision_receipt_id is null then raise exception 'Human confirmation receipt required before application.' using errcode='42501'; end if;
  if q.readiness_state<>'ready_for_confirmation' or q.route_state not in ('ready','destination_unavailable') then raise exception 'Proposal is not ready for application.' using errcode='22023'; end if;
  rb:=q.route_state; body:=q.proposal; source_key:='personal_reality_proposal:'||q.id::text;
  if q.supersedes_proposal_id is not null then
    select * into oldq from atlas.personal_reality_effect_proposals p where p.id=q.supersedes_proposal_id and p.owner_user_id=u and p.principal_id=q.principal_id for update;
    if oldq.id is null or oldq.decision_state='revoked' or oldq.route_state='superseded' then raise exception 'Superseded proposal is unavailable or obsolete.' using errcode='23505'; end if;
    old_dec:=oldq.decision_state; old_route:=oldq.route_state;
  end if;
  if q.effect_kind='one_off_action' then fn:=to_regprocedure('atlas.capture_personal_one_off_action_self_api_v1(jsonb)');
  elsif q.effect_kind='capacity_block' then fn:=to_regprocedure('atlas.record_principal_capacity_block_self_api_v1(jsonb)');
  elsif q.effect_kind='capacity_adjustment' then fn:=to_regprocedure('atlas.record_principal_capacity_adjustment_self_api_v1(jsonb)'); end if;
  if q.effect_kind in ('one_off_action','capacity_block','capacity_adjustment') and fn is null then
    update atlas.personal_reality_effect_proposals set route_state='destination_unavailable',updated_at=now() where id=q.id returning * into q;
    if rb<>'destination_unavailable' then insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,authority_receipt_id,event_kind,state_axis,from_state,to_state,detail)
      values(q.id,cap.id,cap.principal_id,u,q.decision_receipt_id,'destination_unavailable','route',rb,'destination_unavailable',jsonb_build_object('effectKind',q.effect_kind)); end if;
    cs:=atlas.refresh_personal_reality_capture_state_v1(cap.id);
    return jsonb_build_object('ok',true,'changed',(rb<>'destination_unavailable'),'routeState','destination_unavailable','effectKind',q.effect_kind,'captureState',cs);
  end if;
  if q.effect_kind='fact_only' then dk:='evidence_record'; did:=cap.evidence_id::text; result:=jsonb_build_object('ok',true,'evidenceId',cap.evidence_id);
  elsif q.effect_kind='claim' then
    if oldq.id is not null and oldq.route_state='applied' and oldq.effect_kind='claim' then
      select * into old_claim from atlas.claim_records c where c.id=oldq.destination_id::uuid and c.scope_kind='person' and c.scope_id=u;
      if old_claim.id is null then raise exception 'Prior Claim destination missing.' using errcode='P0002'; end if;
      same_subject:=old_claim.subject_domain=body#>>'{subject,domain}' and old_claim.subject_kind=body#>>'{subject,kind}' and old_claim.subject_id=body#>>'{subject,id}';
    end if;
    result:=atlas.record_person_claim_from_capture_evidence_v1(jsonb_build_object('sourceEvidenceId',cap.evidence_id,'proposalId',q.id,'decisionReceiptId',q.decision_receipt_id,'subject',body->'subject','claim',body->'claim','supersedesClaimId',case when same_subject then old_claim.id else null end));
    dk:='claim_record'; did:=result->>'claimId'; if same_subject then old_reversed:=true; end if;
  else
    body:=(body-'sourceKey'-'sourceEvidenceId'-'sourceClaimId'-'testimony'-'floorClass'-'protectionLevel'-'interruptibility'-'reasonForFloor'-'consequence'-'blocksCapacity'-'maximumPlannedMinutes'-'discretionaryCapacityMinutes')
      ||jsonb_build_object('sourceKey',source_key,'sourceEvidenceId',cap.evidence_id,
        'metadata',coalesce(case when jsonb_typeof(body->'metadata')='object' then body->'metadata' end,'{}'::jsonb)||jsonb_build_object('personalRealityProposalId',q.id,'decisionReceiptId',q.decision_receipt_id,'timingProvenance',body->'timingProvenance'));
    if q.effect_kind='one_off_action' then body:=body||jsonb_build_object('testimony',cap.testimony); end if;
    select n.nspname,p.proname into fs,fnm from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.oid=fn::oid;
    execute format('select %I.%I($1)',fs,fnm) into result using body;
    if q.effect_kind='one_off_action' then dk:='principal_one_off_action'; did:=result#>>'{action,id}';
    elsif q.effect_kind='capacity_block' then dk:='principal_capacity_block'; did:=result#>>'{capacityBlock,id}';
    else dk:='principal_capacity_adjustment'; did:=result#>>'{capacityAdjustment,id}'; end if;
    if did is null then raise exception 'Destination did not return an id.' using errcode='55000'; end if;
  end if;
  if oldq.id is not null and oldq.route_state='applied' and not old_reversed then
    if oldq.effect_kind='claim' then
      select * into old_claim from atlas.claim_records c where c.id=oldq.destination_id::uuid and c.scope_kind='person' and c.scope_id=u;
      if old_claim.id is null then raise exception 'Prior Claim destination missing.' using errcode='P0002'; end if;
      update atlas.claim_records set lifecycle_state='superseded',superseded_at=now() where id=old_claim.id and lifecycle_state<>'superseded';
      if not found then raise exception 'Prior Claim already superseded.' using errcode='23505'; end if;
      insert into atlas.claim_evidence_links(claim_id,evidence_id,relation_kind,metadata) values(old_claim.id,cap.evidence_id,'corrects',jsonb_build_object('correctionProposalId',q.id)) on conflict(claim_id,evidence_id,relation_kind) do nothing; old_reversed:=true;
    elsif oldq.effect_kind='one_off_action' then tfn:=to_regprocedure('atlas.transition_personal_one_off_action_self_api_v1(uuid,text)');
    elsif oldq.effect_kind='capacity_block' then tfn:=to_regprocedure('atlas.transition_principal_capacity_block_self_api_v1(uuid,text,text)');
    elsif oldq.effect_kind='capacity_adjustment' then tfn:=to_regprocedure('atlas.transition_principal_capacity_adjustment_self_api_v1(uuid,text,text)'); end if;
    if oldq.effect_kind in ('one_off_action','capacity_block','capacity_adjustment') then
      if tfn is null then raise exception 'Correction transition writer unavailable.' using errcode='55000'; end if;
      select n.nspname,p.proname into ts,tnm from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.oid=tfn::oid;
      if oldq.effect_kind='one_off_action' then execute format('select %I.%I($1,$2)',ts,tnm) into result using oldq.destination_id::uuid,'cancel';
      else execute format('select %I.%I($1,$2,$3)',ts,tnm) into result using oldq.destination_id::uuid,'cancel','Superseded by corrected personal reality interpretation.'; end if; old_reversed:=true;
    end if;
  end if;
  update atlas.personal_reality_effect_proposals set route_state='applied',applied_at=coalesce(applied_at,now()),destination_kind=dk,destination_id=did,updated_at=now() where id=q.id returning * into q;
  insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,authority_receipt_id,event_kind,state_axis,from_state,to_state,detail)
  values(q.id,cap.id,cap.principal_id,u,q.decision_receipt_id,'applied','route',rb,'applied',jsonb_build_object('destinationKind',dk,'destinationId',did,'sourceEvidenceId',cap.evidence_id));
  if oldq.id is not null then
    update atlas.personal_reality_effect_proposals set decision_state='revoked',route_state=case when route_state='applied' then 'superseded' else 'not_ready' end,revoked_at=now(),updated_at=now() where id=oldq.id returning * into oldq;
    insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,authority_receipt_id,event_kind,state_axis,from_state,to_state,detail)
    values(oldq.id,oldq.capture_id,oldq.principal_id,u,q.decision_receipt_id,'superseded','decision',old_dec,'revoked',jsonb_build_object('supersededByProposalId',q.id,'oldDestinationReversed',old_reversed));
    if old_route is distinct from oldq.route_state then insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,authority_receipt_id,event_kind,state_axis,from_state,to_state,detail)
      values(oldq.id,oldq.capture_id,oldq.principal_id,u,q.decision_receipt_id,'superseded','route',old_route,oldq.route_state,jsonb_build_object('supersededByProposalId',q.id)); end if;
    perform atlas.refresh_personal_reality_capture_state_v1(oldq.capture_id);
  end if;
  cs:=atlas.refresh_personal_reality_capture_state_v1(cap.id);
  return jsonb_build_object('ok',true,'changed',true,'contractVersion','personal_reality_effect_application_v1','proposalId',q.id,'decisionState',q.decision_state,'routeState',q.route_state,
    'effectKind',q.effect_kind,'destinationKind',dk,'destinationId',did,'destinationState',atlas.personal_reality_destination_state_v1(dk,did),'evidenceId',cap.evidence_id,'captureState',cs,
    'truthBoundary',jsonb_build_object('applicationAuthorityComesFromHumanDecisionReceiptNotCaller',true,'destinationCallsAreLateBoundAndFailClosed',true,'sourceKeyUsesProposalUuid',true,'correctionIsTransactional',true));
end;$function$;

create or replace function atlas.personal_reality_capture_self_api_v1(p_capture_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $function$
declare u uuid:=auth.uid(); cap atlas.personal_reality_captures%rowtype; effects jsonb;
begin
  if u is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into cap from atlas.personal_reality_captures c where c.id=p_capture_id and c.owner_user_id=u;
  if cap.id is null then raise exception 'Personal reality capture not found.' using errcode='P0002'; end if;
  select coalesce(jsonb_agg(to_jsonb(p)||jsonb_build_object('destinationState',atlas.personal_reality_destination_state_v1(p.destination_kind,p.destination_id)) order by p.created_at,p.id),'[]'::jsonb)
    into effects from atlas.personal_reality_effect_proposals p where p.capture_id=cap.id and p.owner_user_id=u;
  return jsonb_build_object('ok',true,'contractVersion','personal_reality_capture_read_v1','capture',to_jsonb(cap),'effects',effects,
    'truthBoundary',jsonb_build_object('captureStateIsWorkflowStateNotLifeTruth',true,'readinessDecisionAndRouteStatesAreDistinct',true,'destinationStateIsProjectedSeparately',true));
end;$function$;

revoke all on function atlas.capture_personal_reality_self_api_v1(jsonb) from public,anon;
revoke all on function atlas.propose_personal_reality_effects_self_api_v1(uuid,jsonb) from public,anon;
revoke all on function atlas.confirm_personal_reality_effect_self_api_v1(uuid,uuid) from public,anon;
revoke all on function atlas.apply_personal_reality_effect_self_api_v1(uuid) from public,anon;
revoke all on function atlas.personal_reality_capture_self_api_v1(uuid) from public,anon;
grant execute on function atlas.capture_personal_reality_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function atlas.propose_personal_reality_effects_self_api_v1(uuid,jsonb) to authenticated,service_role;
grant execute on function atlas.confirm_personal_reality_effect_self_api_v1(uuid,uuid) to authenticated,service_role;
grant execute on function atlas.apply_personal_reality_effect_self_api_v1(uuid) to authenticated,service_role;
grant execute on function atlas.personal_reality_capture_self_api_v1(uuid) to authenticated,service_role;

create or replace function public.capture_personal_reality_self_api_v1(p_input jsonb) returns jsonb language sql security definer set search_path=pg_catalog as $function$ select atlas.capture_personal_reality_self_api_v1(p_input); $function$;
create or replace function public.propose_personal_reality_effects_self_api_v1(p_capture_id uuid,p_effects jsonb) returns jsonb language sql security definer set search_path=pg_catalog as $function$ select atlas.propose_personal_reality_effects_self_api_v1(p_capture_id,p_effects); $function$;
create or replace function public.confirm_personal_reality_effect_self_api_v1(p_proposal_id uuid,p_receipt_id uuid) returns jsonb language sql security definer set search_path=pg_catalog as $function$ select atlas.confirm_personal_reality_effect_self_api_v1(p_proposal_id,p_receipt_id); $function$;
create or replace function public.apply_personal_reality_effect_self_api_v1(p_proposal_id uuid) returns jsonb language sql security definer set search_path=pg_catalog as $function$ select atlas.apply_personal_reality_effect_self_api_v1(p_proposal_id); $function$;
create or replace function public.personal_reality_capture_self_api_v1(p_capture_id uuid) returns jsonb language sql stable security definer set search_path=pg_catalog as $function$ select atlas.personal_reality_capture_self_api_v1(p_capture_id); $function$;
revoke all on function public.capture_personal_reality_self_api_v1(jsonb) from public,anon;
revoke all on function public.propose_personal_reality_effects_self_api_v1(uuid,jsonb) from public,anon;
revoke all on function public.confirm_personal_reality_effect_self_api_v1(uuid,uuid) from public,anon;
revoke all on function public.apply_personal_reality_effect_self_api_v1(uuid) from public,anon;
revoke all on function public.personal_reality_capture_self_api_v1(uuid) from public,anon;
grant execute on function public.capture_personal_reality_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function public.propose_personal_reality_effects_self_api_v1(uuid,jsonb) to authenticated,service_role;
grant execute on function public.confirm_personal_reality_effect_self_api_v1(uuid,uuid) to authenticated,service_role;
grant execute on function public.apply_personal_reality_effect_self_api_v1(uuid) to authenticated,service_role;
grant execute on function public.personal_reality_capture_self_api_v1(uuid) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(signature,classification,confidence,review_status,authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,caller_count,policy_reference_count,evidence,registered_at) values
('atlas.capture_personal_reality_self_api_v1(p_input jsonb)','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Preserve spontaneous testimony once as unresolved-subject Evidence.','domainTruthOwner',false),now()),
('atlas.propose_personal_reality_effects_self_api_v1(p_capture_id uuid, p_effects jsonb)','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Create immutable self-authenticated interpretations; self-authentication is not human confirmation.','humanAuthority',false),now()),
('atlas.confirm_personal_reality_effect_self_api_v1(p_proposal_id uuid, p_receipt_id uuid)','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Consume a trusted-surface human decision receipt.','requiresHumanDecisionReceipt',true),now()),
('atlas.apply_personal_reality_effect_self_api_v1(p_proposal_id uuid)','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Route confirmed effects through late-bound governed destinations.','authorizationComesFromReceipt',true),now()),
('atlas.personal_reality_capture_self_api_v1(p_capture_id uuid)','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Read capture workflow with readiness, decision, route, and destination state distinct.'),now())
on conflict(signature) do update set classification=excluded.classification,confidence=excluded.confidence,review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,anonymous_execute_expected=excluded.anonymous_execute_expected,
  evidence=atlas.authenticated_rpc_registry.evidence||excluded.evidence,reviewed_at=now();