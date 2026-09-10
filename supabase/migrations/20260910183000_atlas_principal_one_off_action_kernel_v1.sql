-- Principal One-Off Action is the durable identity for a finite action a Principal still needs to do.
-- It is not Company Work, not a legacy Task, not an Owner Obligation, not a Commitment Plan,
-- and not a Clock placement. Capture may preserve a useful action before Atlas knows enough to
-- estimate duration, protection, or scheduling consequence.

create table if not exists atlas.principal_one_off_actions (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  source_key text not null,
  title text not null,
  testimony text not null,
  action_domain text not null default 'personal',
  subject_domain text,
  subject_kind text,
  subject_id text,
  becomes_relevant_at timestamptz,
  must_finish_by timestamptz,
  preferred_window tstzrange,
  expected_minutes integer check (expected_minutes is null or expected_minutes > 0),
  external_action_kind text,
  external_action_ref text,
  source_evidence_id uuid references atlas.evidence_records(id) on delete set null,
  source_claim_id uuid references atlas.claim_records(id) on delete set null,
  status text not null default 'open' check (status in ('open','completed','cancelled','superseded')),
  completed_at timestamptz,
  cancelled_at timestamptz,
  superseded_by_action_id uuid references atlas.principal_one_off_actions(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_user_id,source_key),
  check (btrim(source_key)<>''),
  check (btrim(title)<>''),
  check (btrim(testimony)<>''),
  check (btrim(action_domain)<>''),
  check (must_finish_by is null or becomes_relevant_at is null or must_finish_by >= becomes_relevant_at),
  check (preferred_window is null or not isempty(preferred_window)),
  check ((status='completed') = (completed_at is not null)),
  check ((status='cancelled') = (cancelled_at is not null)),
  check ((status='superseded') = (superseded_by_action_id is not null)),
  check (superseded_by_action_id is null or superseded_by_action_id<>id)
);

create index if not exists principal_one_off_actions_open_idx
  on atlas.principal_one_off_actions(principal_id,status,becomes_relevant_at,must_finish_by,created_at);

alter table atlas.principal_one_off_actions enable row level security;
revoke all on atlas.principal_one_off_actions from public,anon,authenticated;

create table if not exists atlas.principal_one_off_action_events (
  id uuid primary key default gen_random_uuid(),
  action_id uuid not null references atlas.principal_one_off_actions(id) on delete cascade,
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_kind text not null check (event_kind in ('captured','completed','cancelled','superseded','reopened')),
  from_status text,
  to_status text not null,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists principal_one_off_action_events_action_idx
  on atlas.principal_one_off_action_events(action_id,created_at,id);

alter table atlas.principal_one_off_action_events enable row level security;
revoke all on atlas.principal_one_off_action_events from public,anon,authenticated;

create or replace function atlas.capture_personal_one_off_action_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal atlas.principals%rowtype;
  v_source_key text;
  v_title text;
  v_testimony text;
  v_domain text;
  v_expected integer;
  v_existing atlas.principal_one_off_actions%rowtype;
  v_action atlas.principal_one_off_actions%rowtype;
  v_created boolean:=false;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then raise exception 'One-off action input must be an object.' using errcode='22023'; end if;

  select * into v_principal
  from atlas.principals p
  where p.user_id=v_user_id and p.status='active'
  limit 1;
  if v_principal.id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  v_source_key:=nullif(btrim(p_input->>'sourceKey'),'');
  v_title:=nullif(btrim(p_input->>'title'),'');
  v_testimony:=coalesce(nullif(btrim(p_input->>'testimony'),''),v_title);
  v_domain:=coalesce(nullif(btrim(p_input->>'actionDomain'),''),'personal');
  if p_input ? 'expectedMinutes' and jsonb_typeof(p_input->'expectedMinutes')='number' then
    v_expected:=(p_input->>'expectedMinutes')::integer;
  end if;

  if v_source_key is null or v_title is null or v_testimony is null then
    raise exception 'sourceKey, title, and testimony are required.' using errcode='22023';
  end if;
  if v_expected is not null and v_expected<=0 then raise exception 'expectedMinutes must be positive when supplied.' using errcode='22023'; end if;

  select * into v_existing
  from atlas.principal_one_off_actions a
  where a.owner_user_id=v_user_id and a.source_key=v_source_key;

  if v_existing.id is not null then
    if v_existing.title is distinct from v_title
      or v_existing.testimony is distinct from v_testimony
      or v_existing.action_domain is distinct from v_domain
      or v_existing.subject_domain is distinct from nullif(btrim(p_input->>'subjectDomain'),'')
      or v_existing.subject_kind is distinct from nullif(btrim(p_input->>'subjectKind'),'')
      or v_existing.subject_id is distinct from nullif(btrim(p_input->>'subjectId'),'')
      or v_existing.becomes_relevant_at is distinct from nullif(p_input->>'becomesRelevantAt','')::timestamptz
      or v_existing.must_finish_by is distinct from nullif(p_input->>'mustFinishBy','')::timestamptz
      or v_existing.expected_minutes is distinct from v_expected
      or v_existing.external_action_kind is distinct from nullif(btrim(p_input->>'externalActionKind'),'')
      or v_existing.external_action_ref is distinct from nullif(btrim(p_input->>'externalActionRef'),'')
      or v_existing.source_evidence_id is distinct from nullif(p_input->>'sourceEvidenceId','')::uuid
      or v_existing.source_claim_id is distinct from nullif(p_input->>'sourceClaimId','')::uuid then
      raise exception 'sourceKey retry does not match existing one-off action.' using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,'created',false,'contractVersion','personal_one_off_action_v1','action',to_jsonb(v_existing),
      'truthBoundary',jsonb_build_object('actionIsNotClockPlacement',true,'actionIsNotOwnerObligation',true,'actionIsNotCompanyWork',true,'actionIsNotCommitmentPlan',true,'missingEstimateIsAllowed',true)
    );
  end if;

  insert into atlas.principal_one_off_actions(
    principal_id,owner_user_id,source_key,title,testimony,action_domain,
    subject_domain,subject_kind,subject_id,becomes_relevant_at,must_finish_by,preferred_window,
    expected_minutes,external_action_kind,external_action_ref,source_evidence_id,source_claim_id,metadata
  ) values(
    v_principal.id,v_user_id,v_source_key,v_title,v_testimony,v_domain,
    nullif(btrim(p_input->>'subjectDomain'),''),nullif(btrim(p_input->>'subjectKind'),''),nullif(btrim(p_input->>'subjectId'),''),
    nullif(p_input->>'becomesRelevantAt','')::timestamptz,
    nullif(p_input->>'mustFinishBy','')::timestamptz,
    case when nullif(p_input->>'preferredWindowStart','') is null or nullif(p_input->>'preferredWindowEnd','') is null then null
         else tstzrange((p_input->>'preferredWindowStart')::timestamptz,(p_input->>'preferredWindowEnd')::timestamptz,'[)') end,
    v_expected,nullif(btrim(p_input->>'externalActionKind'),''),nullif(btrim(p_input->>'externalActionRef'),''),
    nullif(p_input->>'sourceEvidenceId','')::uuid,nullif(p_input->>'sourceClaimId','')::uuid,
    coalesce(case when jsonb_typeof(p_input->'metadata')='object' then p_input->'metadata' end,'{}'::jsonb)
      ||jsonb_build_object('authoringContract','personal_one_off_action_v1')
  ) returning * into v_action;
  v_created:=true;

  insert into atlas.principal_one_off_action_events(action_id,principal_id,actor_user_id,event_kind,from_status,to_status,reason,metadata)
  values(v_action.id,v_principal.id,v_user_id,'captured',null,'open','Principal captured a finite action that remains to be done.',jsonb_build_object('sourceKey',v_source_key));

  return jsonb_build_object(
    'ok',true,'created',v_created,'contractVersion','personal_one_off_action_v1','action',to_jsonb(v_action),
    'truthBoundary',jsonb_build_object(
      'actionIsNotClockPlacement',true,
      'actionIsNotOwnerObligation',true,
      'actionIsNotCompanyWork',true,
      'actionIsNotCommitmentPlan',true,
      'actionDoesNotRequireExpectedMinutes',true,
      'actionDoesNotRequireDeadline',true,
      'sourceEvidenceRemainsDistinct',true,
      'sourceClaimRemainsDistinct',true,
      'externalActionReferenceDoesNotGrantExternalAuthority',true
    )
  );
end;
$function$;

create or replace function atlas.personal_one_off_actions_self_api_v1(p_include_closed boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_items jsonb;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select p.id into v_principal_id from atlas.principals p where p.user_id=v_user_id and p.status='active' limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  select coalesce(jsonb_agg(to_jsonb(a) order by a.must_finish_by nulls last,a.becomes_relevant_at nulls first,a.created_at,a.id),'[]'::jsonb)
  into v_items
  from atlas.principal_one_off_actions a
  where a.owner_user_id=v_user_id and a.principal_id=v_principal_id
    and (coalesce(p_include_closed,false) or a.status='open');

  return jsonb_build_object(
    'ok',true,'contractVersion','personal_one_off_actions_self_api_v1','principalId',v_principal_id,
    'count',jsonb_array_length(v_items),'items',v_items,
    'truthBoundary',jsonb_build_object('listIsNotClockOrder',true,'openDoesNotMeanDueToday',true,'missingTimingRemainsUnknown',true)
  );
end;
$function$;

create or replace function atlas.transition_personal_one_off_action_self_api_v1(p_action_id uuid,p_transition text)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_action atlas.principal_one_off_actions%rowtype;
  v_from text;
  v_to text;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select p.id into v_principal_id from atlas.principals p where p.user_id=v_user_id and p.status='active' limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  select * into v_action from atlas.principal_one_off_actions a
  where a.id=p_action_id and a.owner_user_id=v_user_id and a.principal_id=v_principal_id
  for update;
  if v_action.id is null then raise exception 'One-off action not found.' using errcode='P0002'; end if;

  v_from:=v_action.status;
  v_to:=case lower(btrim(coalesce(p_transition,'')))
    when 'complete' then 'completed'
    when 'cancel' then 'cancelled'
    when 'reopen' then 'open'
    else null end;
  if v_to is null then raise exception 'transition must be complete, cancel, or reopen.' using errcode='22023'; end if;
  if v_from=v_to then
    return jsonb_build_object('ok',true,'changed',false,'contractVersion','personal_one_off_action_transition_v1','action',to_jsonb(v_action));
  end if;
  if v_from='superseded' then raise exception 'Superseded action cannot be transitioned.' using errcode='22023'; end if;
  if v_to='completed' and v_from<>'open' then raise exception 'Only an open action may be completed.' using errcode='22023'; end if;
  if v_to='cancelled' and v_from<>'open' then raise exception 'Only an open action may be cancelled.' using errcode='22023'; end if;
  if v_to='open' and v_from not in ('completed','cancelled') then raise exception 'Only a completed or cancelled action may be reopened.' using errcode='22023'; end if;

  update atlas.principal_one_off_actions
  set status=v_to,
      completed_at=case when v_to='completed' then now() else null end,
      cancelled_at=case when v_to='cancelled' then now() else null end,
      updated_at=now()
  where id=v_action.id
  returning * into v_action;

  insert into atlas.principal_one_off_action_events(action_id,principal_id,actor_user_id,event_kind,from_status,to_status,reason)
  values(v_action.id,v_principal_id,v_user_id,
    case when v_to='completed' then 'completed' when v_to='cancelled' then 'cancelled' else 'reopened' end,
    v_from,v_to,'Principal explicitly changed the one-off action lifecycle.');

  return jsonb_build_object(
    'ok',true,'changed',true,'contractVersion','personal_one_off_action_transition_v1','action',to_jsonb(v_action),
    'truthBoundary',jsonb_build_object('completionRequiresExplicitTransition',true,'transitionDoesNotCreateClockPlacement',true)
  );
end;
$function$;

revoke all on function atlas.capture_personal_one_off_action_self_api_v1(jsonb) from public,anon;
revoke all on function atlas.personal_one_off_actions_self_api_v1(boolean) from public,anon;
revoke all on function atlas.transition_personal_one_off_action_self_api_v1(uuid,text) from public,anon;
grant execute on function atlas.capture_personal_one_off_action_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function atlas.personal_one_off_actions_self_api_v1(boolean) to authenticated,service_role;
grant execute on function atlas.transition_personal_one_off_action_self_api_v1(uuid,text) to authenticated,service_role;

create or replace function public.capture_personal_one_off_action_self_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.capture_personal_one_off_action_self_api_v1(p_input); $function$;

create or replace function public.personal_one_off_actions_self_api_v1(p_include_closed boolean default false)
returns jsonb language sql stable security definer set search_path=pg_catalog
as $function$ select atlas.personal_one_off_actions_self_api_v1(p_include_closed); $function$;

create or replace function public.transition_personal_one_off_action_self_api_v1(p_action_id uuid,p_transition text)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.transition_personal_one_off_action_self_api_v1(p_action_id,p_transition); $function$;

revoke all on function public.capture_personal_one_off_action_self_api_v1(jsonb) from public,anon;
revoke all on function public.personal_one_off_actions_self_api_v1(boolean) from public,anon;
revoke all on function public.transition_personal_one_off_action_self_api_v1(uuid,text) from public,anon;
grant execute on function public.capture_personal_one_off_action_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function public.personal_one_off_actions_self_api_v1(boolean) to authenticated,service_role;
grant execute on function public.transition_personal_one_off_action_self_api_v1(uuid,text) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
)
values
  ('atlas.capture_personal_one_off_action_self_api_v1(p_input jsonb)','app_endpoint','verified','active',true,true,true,false,1,0,
    jsonb_build_object('purpose','Capture a finite Principal-owned personal action without promoting it to Owner Obligation, Company Work, or Clock placement.'),now()),
  ('atlas.personal_one_off_actions_self_api_v1(p_include_closed boolean)','app_endpoint','verified','active',true,true,true,false,1,0,
    jsonb_build_object('purpose','Read Principal-owned one-off actions; ordering is presentation convenience, not Clock arbitration.'),now()),
  ('atlas.transition_personal_one_off_action_self_api_v1(p_action_id uuid, p_transition text)','app_endpoint','verified','active',true,true,true,false,1,0,
    jsonb_build_object('purpose','Explicitly complete, cancel, or reopen a Principal-owned one-off action with append-only event evidence.'),now())
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  evidence=atlas.authenticated_rpc_registry.evidence||excluded.evidence,
  reviewed_at=now();