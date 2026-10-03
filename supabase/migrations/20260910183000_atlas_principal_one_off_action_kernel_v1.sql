-- Principal One-Off Action is the durable identity for a finite action a Principal still needs to do.
-- It is not Company Work, not a legacy Task, not an Owner Obligation, not a Commitment Plan,
-- and not a Clock placement. Capture may preserve a useful action before Atlas knows enough to
-- estimate duration, protection, or scheduling consequence.
--
-- Attention is derived separately from the durable action. V1 admits an open action to current
-- attention only from temporal evidence already attached to the action or from a declared Principal
-- Capacity planning boundary. It does not assign a generic priority score or a default urgency horizon.
-- Attention is still not Clock admission: the one-off action kernel does not invent floor class,
-- protection, consequence, or placement authority.

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
  status text not null default 'open' check (status in ('open','completed','cancelled')),
  completed_at timestamptz,
  cancelled_at timestamptz,
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
  check ((status='cancelled') = (cancelled_at is not null))
);

comment on table atlas.principal_one_off_actions is
  'Principal-owned finite action identity. It preserves what remains to be done without itself creating Owner Obligation, Company Work, Commitment Plan, execution authority, Clock placement, or current attention.';

create index if not exists principal_one_off_actions_open_idx
  on atlas.principal_one_off_actions(principal_id,status,becomes_relevant_at,must_finish_by,created_at);

alter table atlas.principal_one_off_actions enable row level security;
revoke all on atlas.principal_one_off_actions from public,anon,authenticated;

create table if not exists atlas.principal_one_off_action_events (
  id uuid primary key default gen_random_uuid(),
  action_id uuid not null references atlas.principal_one_off_actions(id) on delete cascade,
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_kind text not null check (event_kind in ('captured','completed','cancelled','reopened')),
  from_status text,
  to_status text not null,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

comment on table atlas.principal_one_off_action_events is
  'Append-oriented lifecycle evidence for Principal one-off actions.';

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
  v_becomes_relevant_at timestamptz;
  v_must_finish_by timestamptz;
  v_preferred_window tstzrange;
  v_source_evidence_id uuid;
  v_source_claim_id uuid;
  v_existing atlas.principal_one_off_actions%rowtype;
  v_action atlas.principal_one_off_actions%rowtype;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'One-off action input must be an object.' using errcode='22023';
  end if;

  select * into v_principal
  from atlas.principals p
  where p.user_id=v_user_id and p.status='active'
  limit 1;
  if v_principal.id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  v_source_key:=nullif(btrim(p_input->>'sourceKey'),'');
  v_title:=nullif(btrim(p_input->>'title'),'');
  v_testimony:=coalesce(nullif(btrim(p_input->>'testimony'),''),v_title);
  v_domain:=coalesce(nullif(btrim(p_input->>'actionDomain'),''),'personal');
  v_becomes_relevant_at:=nullif(p_input->>'becomesRelevantAt','')::timestamptz;
  v_must_finish_by:=nullif(p_input->>'mustFinishBy','')::timestamptz;
  v_source_evidence_id:=nullif(p_input->>'sourceEvidenceId','')::uuid;
  v_source_claim_id:=nullif(p_input->>'sourceClaimId','')::uuid;

  if nullif(p_input->>'preferredWindowStart','') is not null
     or nullif(p_input->>'preferredWindowEnd','') is not null then
    if nullif(p_input->>'preferredWindowStart','') is null
       or nullif(p_input->>'preferredWindowEnd','') is null then
      raise exception 'Preferred window requires both start and end when supplied.' using errcode='22023';
    end if;
    v_preferred_window:=tstzrange(
      (p_input->>'preferredWindowStart')::timestamptz,
      (p_input->>'preferredWindowEnd')::timestamptz,
      '[)'
    );
    if isempty(v_preferred_window) then
      raise exception 'Preferred window must have positive duration.' using errcode='22023';
    end if;
  end if;

  if p_input ? 'expectedMinutes' and jsonb_typeof(p_input->'expectedMinutes')='number' then
    v_expected:=(p_input->>'expectedMinutes')::integer;
  end if;

  if v_source_key is null or v_title is null or v_testimony is null then
    raise exception 'sourceKey, title, and testimony are required.' using errcode='22023';
  end if;
  if v_expected is not null and v_expected<=0 then
    raise exception 'expectedMinutes must be positive when supplied.' using errcode='22023';
  end if;
  if v_must_finish_by is not null and v_becomes_relevant_at is not null
     and v_must_finish_by<v_becomes_relevant_at then
    raise exception 'mustFinishBy cannot precede becomesRelevantAt.' using errcode='22023';
  end if;

  if v_source_evidence_id is not null and not exists(
    select 1 from atlas.evidence_records e
    where e.id=v_source_evidence_id and e.scope_kind='person' and e.scope_id=v_user_id
  ) then
    raise exception 'sourceEvidenceId must identify evidence owned by the signed-in person.' using errcode='42501';
  end if;

  if v_source_claim_id is not null and not exists(
    select 1 from atlas.claim_records c
    where c.id=v_source_claim_id and c.scope_kind='person' and c.scope_id=v_user_id
  ) then
    raise exception 'sourceClaimId must identify a claim owned by the signed-in person.' using errcode='42501';
  end if;

  if v_source_evidence_id is not null and v_source_claim_id is not null and not exists(
    select 1 from atlas.claim_evidence_links l
    where l.claim_id=v_source_claim_id and l.evidence_id=v_source_evidence_id
  ) then
    raise exception 'sourceClaimId and sourceEvidenceId must already be related.' using errcode='22023';
  end if;

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
      or v_existing.becomes_relevant_at is distinct from v_becomes_relevant_at
      or v_existing.must_finish_by is distinct from v_must_finish_by
      or v_existing.preferred_window is distinct from v_preferred_window
      or v_existing.expected_minutes is distinct from v_expected
      or v_existing.external_action_kind is distinct from nullif(btrim(p_input->>'externalActionKind'),'')
      or v_existing.external_action_ref is distinct from nullif(btrim(p_input->>'externalActionRef'),'')
      or v_existing.source_evidence_id is distinct from v_source_evidence_id
      or v_existing.source_claim_id is distinct from v_source_claim_id then
      raise exception 'sourceKey retry does not match existing one-off action.' using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,
      'created',false,
      'contractVersion','personal_one_off_action_v1',
      'action',to_jsonb(v_existing),
      'truthBoundary',jsonb_build_object(
        'actionIsNotCurrentAttention',true,
        'actionIsNotClockPlacement',true,
        'actionIsNotOwnerObligation',true,
        'actionIsNotCompanyWork',true,
        'actionIsNotCommitmentPlan',true,
        'missingEstimateIsAllowed',true
      )
    );
  end if;

  insert into atlas.principal_one_off_actions(
    principal_id,owner_user_id,source_key,title,testimony,action_domain,
    subject_domain,subject_kind,subject_id,becomes_relevant_at,must_finish_by,preferred_window,
    expected_minutes,external_action_kind,external_action_ref,source_evidence_id,source_claim_id,metadata
  ) values(
    v_principal.id,v_user_id,v_source_key,v_title,v_testimony,v_domain,
    nullif(btrim(p_input->>'subjectDomain'),''),
    nullif(btrim(p_input->>'subjectKind'),''),
    nullif(btrim(p_input->>'subjectId'),''),
    v_becomes_relevant_at,v_must_finish_by,v_preferred_window,
    v_expected,
    nullif(btrim(p_input->>'externalActionKind'),''),
    nullif(btrim(p_input->>'externalActionRef'),''),
    v_source_evidence_id,v_source_claim_id,
    coalesce(case when jsonb_typeof(p_input->'metadata')='object' then p_input->'metadata' end,'{}'::jsonb)
      ||jsonb_build_object('authoringContract','personal_one_off_action_v1')
  ) returning * into v_action;

  insert into atlas.principal_one_off_action_events(
    action_id,principal_id,actor_user_id,event_kind,from_status,to_status,reason,metadata
  ) values(
    v_action.id,v_principal.id,v_user_id,'captured',null,'open',
    'Principal captured a finite action that remains to be done.',
    jsonb_build_object('sourceKey',v_source_key)
  );

  return jsonb_build_object(
    'ok',true,
    'created',true,
    'contractVersion','personal_one_off_action_v1',
    'action',to_jsonb(v_action),
    'truthBoundary',jsonb_build_object(
      'actionIsNotCurrentAttention',true,
      'actionIsNotClockPlacement',true,
      'actionIsNotOwnerObligation',true,
      'actionIsNotCompanyWork',true,
      'actionIsNotCommitmentPlan',true,
      'actionDoesNotRequireExpectedMinutes',true,
      'actionDoesNotRequireDeadline',true,
      'captureDoesNotInventCurrentRelevance',true,
      'sourceEvidenceRemainsDistinct',true,
      'sourceClaimRemainsDistinct',true,
      'sourceLinksRequireSamePersonCustody',true,
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
  select p.id into v_principal_id
  from atlas.principals p
  where p.user_id=v_user_id and p.status='active'
  limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  select coalesce(
    jsonb_agg(to_jsonb(a) order by a.must_finish_by nulls last,a.becomes_relevant_at nulls first,a.created_at,a.id),
    '[]'::jsonb
  ) into v_items
  from atlas.principal_one_off_actions a
  where a.owner_user_id=v_user_id
    and a.principal_id=v_principal_id
    and (coalesce(p_include_closed,false) or a.status='open');

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_one_off_actions_self_api_v1',
    'principalId',v_principal_id,
    'count',jsonb_array_length(v_items),
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'listIsNotAttentionAdmission',true,
      'listIsNotClockOrder',true,
      'openDoesNotMeanDueToday',true,
      'missingTimingRemainsUnknown',true
    )
  );
end;
$function$;

create or replace function atlas.personal_one_off_action_attention_self_api_v1(p_as_of timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_timezone text;
  v_local_day date;
  v_next_capacity_start timestamptz;
  v_needs_attention jsonb:='[]'::jsonb;
  v_future jsonb:='[]'::jsonb;
  v_remembered jsonb:='[]'::jsonb;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_as_of is null then raise exception 'Attention as-of time is required.' using errcode='22023'; end if;

  select p.id,coalesce(nullif(p.home_timezone,''),'America/Chicago')
  into v_principal_id,v_timezone
  from atlas.principals p
  where p.user_id=v_user_id and p.status='active'
  limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  v_local_day:=(p_as_of at time zone v_timezone)::date;

  -- Each capacity policy repeats by weekday. For every policy, the first matching weekday must occur
  -- within seven calendar days of max(today,effective_from); this finds the next declared planning start
  -- without assigning a generic urgency horizon.
  with candidate_starts as (
    select ((d.day::date::timestamp + cp.local_start) at time zone v_timezone) as starts_at
    from atlas.principal_capacity_policies cp
    cross join lateral generate_series(
      greatest(v_local_day,cp.effective_from)::timestamp,
      (greatest(v_local_day,cp.effective_from)+6)::timestamp,
      interval '1 day'
    ) as d(day)
    where cp.principal_id=v_principal_id
      and cp.active
      and (cp.effective_through is null or d.day::date<=cp.effective_through)
      and extract(dow from d.day)::smallint=any(cp.weekdays)
  )
  select min(c.starts_at)
  into v_next_capacity_start
  from candidate_starts c
  where c.starts_at>p_as_of;

  with base as (
    select
      a.*,
      case when a.preferred_window is null then null else lower(a.preferred_window) end as preferred_start,
      case when a.preferred_window is null then null else upper(a.preferred_window) end as preferred_end,
      case
        when a.expected_minutes is not null and a.must_finish_by is not null
        then a.must_finish_by-make_interval(mins=>a.expected_minutes)
        else null
      end as latest_start_at
    from atlas.principal_one_off_actions a
    where a.principal_id=v_principal_id
      and a.owner_user_id=v_user_id
      and a.status='open'
  ), classified as (
    select
      b.*,
      case
        when b.must_finish_by is not null and b.must_finish_by<=p_as_of then 'needs_attention'
        when b.preferred_end is not null and b.preferred_end<=p_as_of then 'needs_attention'
        when b.preferred_window is not null and b.preferred_window @> p_as_of then 'needs_attention'
        when b.latest_start_at is not null and b.latest_start_at<=p_as_of then 'needs_attention'
        when b.becomes_relevant_at is not null and b.becomes_relevant_at<=p_as_of then 'needs_attention'
        when b.must_finish_by is not null
          and v_next_capacity_start is not null
          and b.must_finish_by<=v_next_capacity_start then 'needs_attention'
        when exists(
          select 1 from (values
            (b.becomes_relevant_at),
            (b.preferred_start),
            (b.latest_start_at),
            (b.must_finish_by)
          ) as f(boundary)
          where f.boundary>p_as_of
        ) then 'future'
        else 'remembered'
      end as attention_state,
      case
        when b.must_finish_by is not null and b.must_finish_by<=p_as_of then 'finish_boundary_breached'
        when b.preferred_end is not null and b.preferred_end<=p_as_of then 'preferred_window_elapsed_unresolved'
        when b.preferred_window is not null and b.preferred_window @> p_as_of then 'preferred_window_open'
        when b.latest_start_at is not null and b.latest_start_at<=p_as_of then 'latest_start_reached'
        when b.becomes_relevant_at is not null and b.becomes_relevant_at<=p_as_of then 'relevance_reached'
        when b.must_finish_by is not null
          and v_next_capacity_start is not null
          and b.must_finish_by<=v_next_capacity_start then 'last_declared_planning_opportunity'
        when exists(
          select 1 from (values
            (b.becomes_relevant_at),
            (b.preferred_start),
            (b.latest_start_at),
            (b.must_finish_by)
          ) as f(boundary)
          where f.boundary>p_as_of
        ) then 'future_timing_boundary'
        else 'remembered_without_current_timing'
      end as attention_reason,
      case
        when b.must_finish_by is not null and b.must_finish_by<=p_as_of then 10
        when b.preferred_end is not null and b.preferred_end<=p_as_of then 20
        when b.preferred_window is not null and b.preferred_window @> p_as_of then 30
        when b.latest_start_at is not null and b.latest_start_at<=p_as_of then 40
        when b.becomes_relevant_at is not null and b.becomes_relevant_at<=p_as_of then 50
        when b.must_finish_by is not null
          and v_next_capacity_start is not null
          and b.must_finish_by<=v_next_capacity_start then 60
        when exists(
          select 1 from (values
            (b.becomes_relevant_at),
            (b.preferred_start),
            (b.latest_start_at),
            (b.must_finish_by)
          ) as f(boundary)
          where f.boundary>p_as_of
        ) then 70
        else 80
      end as attention_order,
      (
        select min(n.boundary)
        from (values
          (b.becomes_relevant_at),
          (b.preferred_start),
          (b.preferred_end),
          (b.latest_start_at),
          (b.must_finish_by),
          (case when b.must_finish_by is not null then v_next_capacity_start else null end)
        ) as n(boundary)
        where n.boundary>p_as_of
      ) as next_attention_boundary_at
    from base b
  ), rendered as (
    select
      c.*,
      jsonb_build_object(
        'id',c.id,
        'title',c.title,
        'testimony',c.testimony,
        'actionDomain',c.action_domain,
        'subject',jsonb_strip_nulls(jsonb_build_object(
          'domain',c.subject_domain,
          'kind',c.subject_kind,
          'id',c.subject_id
        )),
        'attentionState',c.attention_state,
        'attentionReason',c.attention_reason,
        'rightToAttentionNow',(c.attention_state='needs_attention'),
        'becomesRelevantAt',c.becomes_relevant_at,
        'mustFinishBy',c.must_finish_by,
        'preferredWindow',case when c.preferred_window is null then null else c.preferred_window::text end,
        'latestStartAt',c.latest_start_at,
        'nextAttentionBoundaryAt',c.next_attention_boundary_at,
        'nextDeclaredCapacityStart',v_next_capacity_start,
        'expectedMinutes',c.expected_minutes,
        'durationState',case when c.expected_minutes is null then 'duration_required_for_placement' else 'duration_known' end,
        'externalAction',jsonb_strip_nulls(jsonb_build_object(
          'kind',c.external_action_kind,
          'ref',c.external_action_ref
        )),
        'sourceEvidenceId',c.source_evidence_id,
        'sourceClaimId',c.source_claim_id,
        'clockAdmissionState','not_admitted',
        'clockAdmissionReason','Attention does not establish floor class, protection, consequence, or Clock warrant.',
        'createdAt',c.created_at
      ) as item_json
    from classified c
  )
  select
    coalesce(
      jsonb_agg(r.item_json order by r.attention_order,r.must_finish_by nulls last,r.created_at,r.id)
        filter(where r.attention_state='needs_attention'),
      '[]'::jsonb
    ),
    coalesce(
      jsonb_agg(r.item_json order by r.next_attention_boundary_at nulls last,r.created_at,r.id)
        filter(where r.attention_state='future'),
      '[]'::jsonb
    ),
    coalesce(
      jsonb_agg(r.item_json order by r.created_at,r.id)
        filter(where r.attention_state='remembered'),
      '[]'::jsonb
    )
  into v_needs_attention,v_future,v_remembered
  from rendered r;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_one_off_action_attention_v1',
    'principalId',v_principal_id,
    'asOf',p_as_of,
    'timezone',v_timezone,
    'nextDeclaredCapacityStart',v_next_capacity_start,
    'counts',jsonb_build_object(
      'needsAttention',jsonb_array_length(v_needs_attention),
      'future',jsonb_array_length(v_future),
      'remembered',jsonb_array_length(v_remembered)
    ),
    'needsAttention',v_needs_attention,
    'future',v_future,
    'remembered',v_remembered,
    'truthBoundary',jsonb_build_object(
      'attentionIsDerivedNotStored',true,
      'attentionIsNotPriorityScore',true,
      'attentionIsNotClockPlacement',true,
      'attentionIsNotClockFloor',true,
      'unknownDurationDoesNotHideRealTiming',true,
      'unknownDurationStillBlocksPlacementSizing',true,
      'noDefaultUrgencyHorizon',true,
      'deadlineDoesNotInventLeadTime',true,
      'lastOpportunityUsesDeclaredCapacityPolicyOnly',true,
      'missingCapacityPolicyDoesNotInventAvailability',true,
      'rememberedDoesNotMeanCompletedOrIgnored',true
    )
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
  select p.id into v_principal_id
  from atlas.principals p
  where p.user_id=v_user_id and p.status='active'
  limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  select * into v_action
  from atlas.principal_one_off_actions a
  where a.id=p_action_id
    and a.owner_user_id=v_user_id
    and a.principal_id=v_principal_id
  for update;
  if v_action.id is null then raise exception 'One-off action not found.' using errcode='P0002'; end if;

  v_from:=v_action.status;
  v_to:=case lower(btrim(coalesce(p_transition,'')))
    when 'complete' then 'completed'
    when 'cancel' then 'cancelled'
    when 'reopen' then 'open'
    else null
  end;
  if v_to is null then raise exception 'transition must be complete, cancel, or reopen.' using errcode='22023'; end if;

  if v_from=v_to then
    return jsonb_build_object(
      'ok',true,'changed',false,'contractVersion','personal_one_off_action_transition_v1','action',to_jsonb(v_action)
    );
  end if;
  if v_to='completed' and v_from<>'open' then
    raise exception 'Only an open action may be completed.' using errcode='22023';
  end if;
  if v_to='cancelled' and v_from<>'open' then
    raise exception 'Only an open action may be cancelled.' using errcode='22023';
  end if;
  if v_to='open' and v_from not in ('completed','cancelled') then
    raise exception 'Only a completed or cancelled action may be reopened.' using errcode='22023';
  end if;

  update atlas.principal_one_off_actions
  set status=v_to,
      completed_at=case when v_to='completed' then now() else null end,
      cancelled_at=case when v_to='cancelled' then now() else null end,
      updated_at=now()
  where id=v_action.id
  returning * into v_action;

  insert into atlas.principal_one_off_action_events(
    action_id,principal_id,actor_user_id,event_kind,from_status,to_status,reason
  ) values(
    v_action.id,v_principal_id,v_user_id,
    case when v_to='completed' then 'completed' when v_to='cancelled' then 'cancelled' else 'reopened' end,
    v_from,v_to,'Principal explicitly changed the one-off action lifecycle.'
  );

  return jsonb_build_object(
    'ok',true,
    'changed',true,
    'contractVersion','personal_one_off_action_transition_v1',
    'action',to_jsonb(v_action),
    'truthBoundary',jsonb_build_object(
      'completionRequiresExplicitTransition',true,
      'transitionDoesNotCreateAttentionWarrant',true,
      'transitionDoesNotCreateClockPlacement',true
    )
  );
end;
$function$;

revoke all on function atlas.capture_personal_one_off_action_self_api_v1(jsonb) from public,anon;
revoke all on function atlas.personal_one_off_actions_self_api_v1(boolean) from public,anon;
revoke all on function atlas.personal_one_off_action_attention_self_api_v1(timestamptz) from public,anon;
revoke all on function atlas.transition_personal_one_off_action_self_api_v1(uuid,text) from public,anon;
grant execute on function atlas.capture_personal_one_off_action_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function atlas.personal_one_off_actions_self_api_v1(boolean) to authenticated,service_role;
grant execute on function atlas.personal_one_off_action_attention_self_api_v1(timestamptz) to authenticated,service_role;
grant execute on function atlas.transition_personal_one_off_action_self_api_v1(uuid,text) to authenticated,service_role;

create or replace function public.capture_personal_one_off_action_self_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.capture_personal_one_off_action_self_api_v1(p_input); $function$;

create or replace function public.personal_one_off_actions_self_api_v1(p_include_closed boolean default false)
returns jsonb language sql stable security definer set search_path=pg_catalog
as $function$ select atlas.personal_one_off_actions_self_api_v1(p_include_closed); $function$;

create or replace function public.personal_one_off_action_attention_self_api_v1(p_as_of timestamptz default now())
returns jsonb language sql stable security definer set search_path=pg_catalog
as $function$ select atlas.personal_one_off_action_attention_self_api_v1(p_as_of); $function$;

create or replace function public.transition_personal_one_off_action_self_api_v1(p_action_id uuid,p_transition text)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.transition_personal_one_off_action_self_api_v1(p_action_id,p_transition); $function$;

revoke all on function public.capture_personal_one_off_action_self_api_v1(jsonb) from public,anon;
revoke all on function public.personal_one_off_actions_self_api_v1(boolean) from public,anon;
revoke all on function public.personal_one_off_action_attention_self_api_v1(timestamptz) from public,anon;
revoke all on function public.transition_personal_one_off_action_self_api_v1(uuid,text) from public,anon;
grant execute on function public.capture_personal_one_off_action_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function public.personal_one_off_actions_self_api_v1(boolean) to authenticated,service_role;
grant execute on function public.personal_one_off_action_attention_self_api_v1(timestamptz) to authenticated,service_role;
grant execute on function public.transition_personal_one_off_action_self_api_v1(uuid,text) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
)
values
  (
    'atlas.capture_personal_one_off_action_self_api_v1(p_input jsonb)',
    'app_endpoint','verified','active',true,true,true,false,1,0,
    jsonb_build_object(
      'purpose','Capture a finite Principal-owned personal action without promoting it to current attention, Owner Obligation, Company Work, or Clock placement.'
    ),now()
  ),
  (
    'atlas.personal_one_off_actions_self_api_v1(p_include_closed boolean)',
    'app_endpoint','verified','active',true,true,true,false,1,0,
    jsonb_build_object(
      'purpose','Read Principal-owned one-off actions; ordering is presentation convenience, not attention or Clock arbitration.'
    ),now()
  ),
  (
    'atlas.personal_one_off_action_attention_self_api_v1(p_as_of timestamp with time zone)',
    'app_endpoint','verified','active',true,true,true,false,1,0,
    jsonb_build_object(
      'purpose','Classify open one-off actions as current attention, future, or remembered from explicit timing and declared Principal Capacity boundaries without assigning priority or Clock floor.',
      'defaultUrgencyHorizon',false,
      'clockAdmission',false
    ),now()
  ),
  (
    'atlas.transition_personal_one_off_action_self_api_v1(p_action_id uuid, p_transition text)',
    'app_endpoint','verified','active',true,true,true,false,1,0,
    jsonb_build_object(
      'purpose','Explicitly complete, cancel, or reopen a Principal-owned one-off action with append-oriented event evidence.'
    ),now()
  )
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