-- Principal Capacity authority v1
--
-- Canonical truth owners:
--   * atlas.principal_capacity_blocks: explicit intervals of complete unavailability.
--   * atlas.principal_capacity_adjustments: explicit intervals of reduced availability.
--
-- This migration deliberately distinguishes zero capacity from reduced capacity.
-- Capacity Blocks may not be used for protected strategy or other merely important work.
-- Capacity Adjustments do not create Clock candidates or task/priority authority.

create table if not exists atlas.principal_capacity_adjustments (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  title text not null,
  adjustment_kind text not null check (adjustment_kind in ('reduced_capacity','recovery','caregiving','travel','appointment','other')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  availability_fraction numeric(5,4) not null check (availability_fraction > 0 and availability_fraction < 1),
  active boolean not null default true,
  source_type text,
  source_id text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);
comment on table atlas.principal_capacity_adjustments is
  'Explicit temporary reductions in Principal availability. These rows reduce capacity budget only; they are not Clock candidates and do not own priority.';

create unique index if not exists principal_capacity_adjustments_self_source_uq
  on atlas.principal_capacity_adjustments(principal_id,source_type,source_id)
  where source_type='principal_self_capacity_adjustment_v1' and source_id is not null;
create index if not exists principal_capacity_adjustments_principal_time_idx
  on atlas.principal_capacity_adjustments(principal_id,starts_at,ends_at)
  where active;

alter table atlas.principal_capacity_adjustments enable row level security;
revoke all on atlas.principal_capacity_adjustments from public,anon,authenticated;

create table if not exists atlas.principal_capacity_adjustment_events (
  id uuid primary key default gen_random_uuid(),
  capacity_adjustment_id uuid not null references atlas.principal_capacity_adjustments(id) on delete cascade,
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_kind text not null check (event_kind in ('recorded','cancelled','reopened')),
  from_active boolean,
  to_active boolean not null,
  reason text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  occurred_at timestamptz not null default now()
);
create index if not exists principal_capacity_adjustment_events_adjustment_idx
  on atlas.principal_capacity_adjustment_events(capacity_adjustment_id,occurred_at,id);
alter table atlas.principal_capacity_adjustment_events enable row level security;
revoke all on atlas.principal_capacity_adjustment_events from public,anon,authenticated;

create or replace function atlas.principal_authoritative_timezone_v1(p_principal_id uuid)
returns text
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  p atlas.principals%rowtype;
  h atlas.households%rowtype;
  tz text;
begin
  select * into p from atlas.principals where id=p_principal_id;
  if p.id is null then raise exception 'Principal not found.' using errcode='P0002'; end if;
  if auth.uid() is not null and p.user_id<>auth.uid() then
    raise exception 'Principal timezone may only be read by that Principal.' using errcode='42501';
  end if;

  if p.active_household_id is not null then
    select * into h from atlas.households where id=p.active_household_id and principal_id=p.id and status='active';
    if h.id is not null then tz:=nullif(btrim(h.timezone),''); end if;
  end if;
  if tz is null then tz:=nullif(btrim(p.home_timezone),''); end if;
  if tz is null or not exists(select 1 from pg_catalog.pg_timezone_names where name=tz) then
    raise exception 'Authoritative Principal timezone is required.' using errcode='22023';
  end if;
  return tz;
end;
$function$;
revoke all on function atlas.principal_authoritative_timezone_v1(uuid) from public,anon,authenticated;

create or replace function atlas.principal_capacity_day_state_v1(p_principal_id uuid,p_day date)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_principal atlas.principals%rowtype;
  v_policy atlas.principal_capacity_policies%rowtype;
  v_timezone text;
  v_start timestamptz;
  v_end timestamptz;
  v_elapsed integer:=0;
  v_blocked integer:=0;
  v_available integer:=0;
  v_adjusted_loss integer:=0;
  v_adjusted_available integer:=0;
  v_discretionary integer:=0;
  v_maximum integer:=0;
begin
  if p_day is null then raise exception 'A Principal capacity date is required.' using errcode='22023'; end if;
  select * into v_principal from atlas.principals where id=p_principal_id;
  if v_principal.id is null then raise exception 'Principal not found.' using errcode='P0002'; end if;
  if auth.uid() is not null and v_principal.user_id<>auth.uid() then
    raise exception 'Principal capacity may only be read by that Principal.' using errcode='42501';
  end if;
  v_timezone:=atlas.principal_authoritative_timezone_v1(p_principal_id);

  select * into v_policy
  from atlas.principal_capacity_policies p
  where p.principal_id=p_principal_id and p.active
    and p.effective_from<=p_day
    and (p.effective_through is null or p.effective_through>=p_day)
    and extract(dow from p_day)::smallint=any(p.weekdays)
  order by p.effective_from desc,p.created_at desc
  limit 1;

  if v_policy.id is null then
    return jsonb_build_object(
      'contractVersion','principal_capacity_day_state_v2',
      'principalId',p_principal_id,'serviceDate',p_day,
      'state','anchor_required','capacityKnown',false,
      'timezone',v_timezone,
      'reason','No effective Principal Capacity policy defines this day.'
    );
  end if;

  v_start:=(p_day::timestamp+v_policy.local_start) at time zone v_timezone;
  v_end:=(p_day::timestamp+v_policy.local_end) at time zone v_timezone;
  v_elapsed:=greatest(0,round(extract(epoch from (v_end-v_start))/60.0)::integer);

  with spans as (
    select tstzrange(greatest(b.starts_at,v_start),least(b.ends_at,v_end),'[)') as span
    from atlas.principal_capacity_blocks_v1 b
    where b.principal_id=p_principal_id
      and b.ends_at>v_start and b.starts_at<v_end
  ), merged as (
    select range_agg(span) as spans from spans where not isempty(span)
  )
  select coalesce(sum(round(extract(epoch from (upper(r)-lower(r)))/60.0)::integer),0)
  into v_blocked
  from merged m
  cross join lateral unnest(m.spans) r;

  v_available:=greatest(v_elapsed-v_blocked,0);

  -- For each instant, only the strictest active availability fraction applies.
  -- This prevents overlapping causes from being multiplicatively double-counted.
  with bounds as (
    select v_start as t union select v_end
    union
    select greatest(a.starts_at,v_start)
    from atlas.principal_capacity_adjustments a
    where a.principal_id=p_principal_id and a.active and a.ends_at>v_start and a.starts_at<v_end
    union
    select least(a.ends_at,v_end)
    from atlas.principal_capacity_adjustments a
    where a.principal_id=p_principal_id and a.active and a.ends_at>v_start and a.starts_at<v_end
    union
    select greatest(b.starts_at,v_start)
    from atlas.principal_capacity_blocks_v1 b
    where b.principal_id=p_principal_id and b.ends_at>v_start and b.starts_at<v_end
    union
    select least(b.ends_at,v_end)
    from atlas.principal_capacity_blocks_v1 b
    where b.principal_id=p_principal_id and b.ends_at>v_start and b.starts_at<v_end
  ), segments as (
    select t as s,lead(t) over(order by t) as e from bounds
  ), rated as (
    select s,e,
      case when exists(
        select 1 from atlas.principal_capacity_blocks_v1 b
        where b.principal_id=p_principal_id and b.starts_at<e and b.ends_at>s
      ) then 0::numeric
      else coalesce((
        select min(a.availability_fraction)
        from atlas.principal_capacity_adjustments a
        where a.principal_id=p_principal_id and a.active and a.starts_at<e and a.ends_at>s
      ),1::numeric) end as fraction
    from segments where e is not null and e>s
  )
  select greatest(0,round(sum(extract(epoch from (e-s))/60.0*fraction))::integer)
  into v_adjusted_available
  from rated;

  v_adjusted_available:=coalesce(v_adjusted_available,v_available);
  v_adjusted_loss:=greatest(v_available-v_adjusted_available,0);
  v_discretionary:=least(v_policy.default_discretionary_minutes,v_adjusted_available);
  v_maximum:=least(v_policy.maximum_planned_minutes,v_adjusted_available);

  return jsonb_build_object(
    'contractVersion','principal_capacity_day_state_v2',
    'principalId',p_principal_id,'serviceDate',p_day,
    'state','resolved','capacityKnown',true,'timezone',v_timezone,
    'policyId',v_policy.id,'startsAt',v_start,'endsAt',v_end,
    'elapsedMinutes',v_elapsed,'blockedMinutes',v_blocked,
    'availableElapsedMinutesBeforeAdjustments',v_available,
    'reducedCapacityEquivalentMinutes',v_adjusted_loss,
    'availableElapsedMinutes',v_adjusted_available,
    'discretionaryCapacityMinutes',v_discretionary,
    'maximumPlannedMinutes',v_maximum,
    'truthBoundary',jsonb_build_object(
      'zeroAvailabilityLivesInCapacityBlocks',true,
      'partialAvailabilityLivesInCapacityAdjustments',true,
      'overlappingAdjustmentsUseStrictestFractionNotMultiplication',true,
      'adjustmentsDoNotCreateClockCandidates',true
    )
  );
end;
$function$;

create unique index if not exists principal_capacity_blocks_self_source_uq
  on atlas.principal_capacity_blocks(principal_id,source_type,source_id)
  where source_type='principal_self_capacity_v1' and source_id is not null;

create table if not exists atlas.principal_capacity_block_events (
  id uuid primary key default gen_random_uuid(),
  capacity_block_id uuid not null references atlas.principal_capacity_blocks(id) on delete cascade,
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_kind text not null check (event_kind in ('recorded','cancelled','reopened')),
  from_blocks_capacity boolean,
  to_blocks_capacity boolean not null,
  reason text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  occurred_at timestamptz not null default now()
);
create index if not exists principal_capacity_block_events_block_time_idx
  on atlas.principal_capacity_block_events(capacity_block_id,occurred_at,id);
alter table atlas.principal_capacity_block_events enable row level security;
revoke all on atlas.principal_capacity_block_events from public,anon,authenticated;

create or replace function atlas.record_principal_capacity_block_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_principal atlas.principals%rowtype;
  v_source_key text;
  v_title text;
  v_block_kind text;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
  v_context text;
  v_source_evidence_id uuid;
  v_metadata jsonb;
  v_expected_metadata jsonb;
  v_row atlas.principal_capacity_blocks%rowtype;
  v_existing atlas.principal_capacity_blocks%rowtype;
  v_timezone text;
  v_created boolean:=false;
begin
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then raise exception 'Principal capacity input must be an object.' using errcode='22023'; end if;
  select * into v_principal from atlas.principals p where p.user_id=v_user_id and p.status='active' limit 1;
  if v_principal.id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  v_source_key:=nullif(btrim(p_input->>'sourceKey'),'');
  v_title:=nullif(btrim(p_input->>'title'),'');
  v_block_kind:=nullif(btrim(p_input->>'blockKind'),'');
  v_starts_at:=nullif(btrim(p_input->>'startsAt'),'')::timestamptz;
  v_ends_at:=nullif(btrim(p_input->>'endsAt'),'')::timestamptz;
  v_context:=nullif(btrim(p_input->>'context'),'');
  v_source_evidence_id:=nullif(btrim(p_input->>'sourceEvidenceId'),'')::uuid;
  v_metadata:=coalesce(case when jsonb_typeof(p_input->'metadata')='object' then p_input->'metadata' end,'{}'::jsonb);

  if v_source_key is null or v_title is null or v_block_kind is null or v_starts_at is null or v_ends_at is null then raise exception 'sourceKey, title, blockKind, startsAt, and endsAt are required.' using errcode='22023'; end if;
  if v_ends_at<=v_starts_at then raise exception 'endsAt must be later than startsAt.' using errcode='22023'; end if;
  if v_block_kind not in ('human_fixed','household','family','travel','appointment','recovery','other') then raise exception 'Unsupported Principal capacity block kind.' using errcode='22023'; end if;
  if v_source_evidence_id is not null and not exists(select 1 from atlas.evidence_records e where e.id=v_source_evidence_id and e.scope_kind='person' and e.scope_id=v_user_id) then raise exception 'sourceEvidenceId must identify evidence owned by the signed-in person.' using errcode='42501'; end if;
  v_timezone:=atlas.principal_authoritative_timezone_v1(v_principal.id);

  v_expected_metadata:=v_metadata
    ||case when v_source_evidence_id is null then '{}'::jsonb else jsonb_build_object('sourceEvidenceId',v_source_evidence_id) end
    ||case when v_context is null then '{}'::jsonb else jsonb_build_object('userContext',v_context) end
    ||jsonb_build_object('authoringContract','principal_capacity_self_writer_v1','authoritativeTimezone',v_timezone,
      'truthBoundary',jsonb_build_object('intervalExplicitlyConfirmed',true,'completeUnavailabilityExplicitlyConfirmed',true,'diagnosisNotInferred',true,'causeNotInferred',true,'contextIsNotConsequence',true,'priorityScoreNotCreated',true,'taskNotCreated',true,'clockPlacementNotCreatedByWriter',true,'unavailableMinutesAreNotDiscretionaryCapacity',true,'protectedStrategyIsNotCapacityBlock',true));

  select * into v_existing from atlas.principal_capacity_blocks b where b.principal_id=v_principal.id and b.source_type='principal_self_capacity_v1' and b.source_id=v_source_key;
  if v_existing.id is not null then
    if v_existing.title is distinct from v_title or v_existing.block_kind is distinct from v_block_kind or v_existing.starts_at is distinct from v_starts_at or v_existing.ends_at is distinct from v_ends_at
      or v_existing.blocks_capacity is distinct from true or v_existing.floor_class is distinct from 1 or v_existing.protection_level is distinct from 'critical' or v_existing.interruptibility is distinct from 'should_not_interrupt'
      or v_existing.reason_for_floor is distinct from 'User-confirmed fixed interval in which Principal capacity is unavailable.' or v_existing.consequence is not null or v_existing.metadata is distinct from v_expected_metadata then
      raise exception 'sourceKey retry does not match existing Principal capacity block.' using errcode='23505';
    end if;
    v_row:=v_existing;
  else
    insert into atlas.principal_capacity_blocks(principal_id,title,block_kind,starts_at,ends_at,blocks_capacity,floor_class,protection_level,interruptibility,reason_for_floor,source_type,source_id,consequence,metadata)
    values(v_principal.id,v_title,v_block_kind,v_starts_at,v_ends_at,true,1,'critical','should_not_interrupt','User-confirmed fixed interval in which Principal capacity is unavailable.','principal_self_capacity_v1',v_source_key,null,v_expected_metadata)
    returning * into v_row;
    v_created:=true;
    insert into atlas.principal_capacity_block_events(capacity_block_id,principal_id,actor_user_id,event_kind,from_blocks_capacity,to_blocks_capacity,reason,metadata)
    values(v_row.id,v_principal.id,v_user_id,'recorded',null,true,null,jsonb_strip_nulls(jsonb_build_object('sourceKey',v_source_key,'userContext',v_context,'authoringContract','principal_capacity_self_writer_v1')));
  end if;

  return jsonb_build_object('ok',true,'created',v_created,'contractVersion','principal_capacity_self_writer_v1',
    'capacityBlock',jsonb_build_object('id',v_row.id,'title',v_row.title,'blockKind',v_row.block_kind,'startsAt',v_row.starts_at,'endsAt',v_row.ends_at,'blocksCapacity',v_row.blocks_capacity,'context',nullif(v_row.metadata->>'userContext',''),'sourceKey',v_row.source_id,'sourceEvidenceId',nullif(v_row.metadata->>'sourceEvidenceId','')),
    'capacityStateOnStartDate',atlas.principal_capacity_day_state_v1(v_principal.id,(v_starts_at at time zone v_timezone)::date),
    'truthBoundary',jsonb_build_object('writerOwnsOnlyExplicitCompleteTemporaryUnavailability',true,'protectedStrategyRejected',true,'fixedTimeTreatmentIsStructuralNotPriorityScoring',true,'doesNotCreateTask',true,'doesNotCreateOwnerObligation',true,'writerDoesNotPlaceClockWork',true,'doesNotInferCause',true));
end;
$function$;

create or replace function atlas.transition_principal_capacity_block_self_api_v1(p_capacity_block_id uuid,p_transition text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare
  v_user_id uuid:=auth.uid(); v_principal_id uuid; v_row atlas.principal_capacity_blocks%rowtype; v_transition text:=lower(nullif(btrim(p_transition),'')); v_reason text:=nullif(btrim(coalesce(p_reason,'')),''); v_target boolean; v_event text;
begin
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_principal_id:=atlas.current_principal_id_v1(); if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;
  if p_capacity_block_id is null or v_transition is null then raise exception 'capacityBlockId and transition are required.' using errcode='22023'; end if;
  if v_transition not in ('cancel','reopen') then raise exception 'transition must be cancel or reopen.' using errcode='22023'; end if;
  select * into v_row from atlas.principal_capacity_blocks b where b.id=p_capacity_block_id and b.principal_id=v_principal_id and b.source_type='principal_self_capacity_v1' for update;
  if v_row.id is null then raise exception 'Principal-authored capacity block not found.' using errcode='P0002'; end if;
  v_target:=v_transition='reopen'; v_event:=case when v_target then 'reopened' else 'cancelled' end;
  if v_row.blocks_capacity is distinct from v_target then
    insert into atlas.principal_capacity_block_events(capacity_block_id,principal_id,actor_user_id,event_kind,from_blocks_capacity,to_blocks_capacity,reason,metadata)
    values(v_row.id,v_principal_id,v_user_id,v_event,v_row.blocks_capacity,v_target,v_reason,jsonb_build_object('transitionContract','principal_capacity_self_transition_v1'));
    update atlas.principal_capacity_blocks set blocks_capacity=v_target,updated_at=now() where id=v_row.id returning * into v_row;
  end if;
  return jsonb_build_object('ok',true,'contractVersion','principal_capacity_self_transition_v1','capacityBlock',jsonb_build_object('id',v_row.id,'title',v_row.title,'startsAt',v_row.starts_at,'endsAt',v_row.ends_at,'blocksCapacity',v_row.blocks_capacity,'sourceKey',v_row.source_id),'transition',v_transition,
    'truthBoundary',jsonb_build_object('cancelDoesNotDeleteHistory',true,'transitionHistoryLivesInEvents',true,'reopenRestoresOnlyCapacityBlockingState',true,'transitionDoesNotRewriteOriginalContext',true,'transitionDoesNotCreateTask',true,'transitionDoesNotCreateClockPlacement',true));
end;
$function$;

create or replace function atlas.principal_capacity_blocks_self_api_v1(p_start_at timestamptz default null,p_end_at timestamptz default null,p_include_inactive boolean default false)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_user_id uuid:=auth.uid(); v_principal_id uuid; v_items jsonb;
begin
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_principal_id:=atlas.current_principal_id_v1(); if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;
  if p_start_at is not null and p_end_at is not null and p_end_at<=p_start_at then raise exception 'endAt must be later than startAt.' using errcode='22023'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'title',b.title,'blockKind',b.block_kind,'startsAt',b.starts_at,'endsAt',b.ends_at,'blocksCapacity',b.blocks_capacity,'context',nullif(b.metadata->>'userContext',''),'sourceKey',b.source_id,'sourceEvidenceId',nullif(b.metadata->>'sourceEvidenceId',''),'createdAt',b.created_at,'updatedAt',b.updated_at) order by b.starts_at,b.created_at,b.id),'[]'::jsonb)
  into v_items from atlas.principal_capacity_blocks b where b.principal_id=v_principal_id and b.source_type='principal_self_capacity_v1' and (p_include_inactive or b.blocks_capacity) and (p_start_at is null or b.ends_at>p_start_at) and (p_end_at is null or b.starts_at<p_end_at);
  return jsonb_build_object('ok',true,'contractVersion','principal_capacity_blocks_self_v1','principalId',v_principal_id,'count',jsonb_array_length(v_items),'items',v_items,'truthBoundary',jsonb_build_object('listIsCapacityTruthNotPriorityOrder',true,'contextIsNotConsequence',true,'inactiveRowsRemainHistoricalEvidence',true));
end;
$function$;

create or replace function atlas.record_principal_capacity_adjustment_self_api_v1(p_input jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare
  u uuid:=auth.uid(); p atlas.principals%rowtype; key text; title text; kind text; starts timestamptz; ends timestamptz; frac numeric; context text; evidence_id uuid; md jsonb; expected jsonb; rowv atlas.principal_capacity_adjustments%rowtype; old atlas.principal_capacity_adjustments%rowtype; tz text; made boolean:=false;
begin
  if u is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then raise exception 'Principal capacity adjustment input must be an object.' using errcode='22023'; end if;
  select * into p from atlas.principals x where x.user_id=u and x.status='active' limit 1; if p.id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;
  key:=nullif(btrim(p_input->>'sourceKey'),''); title:=nullif(btrim(p_input->>'title'),''); kind:=coalesce(nullif(btrim(p_input->>'adjustmentKind'),''),'reduced_capacity');
  starts:=nullif(btrim(p_input->>'startsAt'),'')::timestamptz; ends:=nullif(btrim(p_input->>'endsAt'),'')::timestamptz; context:=nullif(btrim(p_input->>'context'),''); evidence_id:=nullif(btrim(p_input->>'sourceEvidenceId'),'')::uuid;
  md:=coalesce(case when jsonb_typeof(p_input->'metadata')='object' then p_input->'metadata' end,'{}'::jsonb);
  if key is null or title is null or starts is null or ends is null or not(p_input?'availabilityFraction') then raise exception 'sourceKey, title, startsAt, endsAt, and availabilityFraction are required.' using errcode='22023'; end if;
  if jsonb_typeof(p_input->'availabilityFraction')<>'number' then raise exception 'availabilityFraction must be numeric.' using errcode='22023'; end if;
  frac:=(p_input->>'availabilityFraction')::numeric;
  if ends<=starts then raise exception 'endsAt must be later than startsAt.' using errcode='22023'; end if;
  if frac<=0 or frac>=1 then raise exception 'availabilityFraction must be greater than 0 and less than 1; use a Capacity Block for zero availability and no adjustment for full availability.' using errcode='22023'; end if;
  if kind not in ('reduced_capacity','recovery','caregiving','travel','appointment','other') then raise exception 'Unsupported capacity adjustment kind.' using errcode='22023'; end if;
  if evidence_id is not null and not exists(select 1 from atlas.evidence_records e where e.id=evidence_id and e.scope_kind='person' and e.scope_id=u) then raise exception 'sourceEvidenceId must identify evidence owned by the signed-in person.' using errcode='42501'; end if;
  tz:=atlas.principal_authoritative_timezone_v1(p.id);
  expected:=md||case when evidence_id is null then '{}'::jsonb else jsonb_build_object('sourceEvidenceId',evidence_id) end||case when context is null then '{}'::jsonb else jsonb_build_object('userContext',context) end||jsonb_build_object('authoringContract','principal_capacity_adjustment_self_writer_v1','authoritativeTimezone',tz,
    'truthBoundary',jsonb_build_object('partialAvailabilityExplicitlyConfirmed',true,'zeroAvailabilityRejected',true,'fullAvailabilityRejected',true,'diagnosisNotInferred',true,'causeNotInferred',true,'taskNotCreated',true,'clockCandidateNotCreated',true,'priorityScoreNotCreated',true));
  select * into old from atlas.principal_capacity_adjustments a where a.principal_id=p.id and a.source_type='principal_self_capacity_adjustment_v1' and a.source_id=key;
  if old.id is not null then
    if old.title is distinct from title or old.adjustment_kind is distinct from kind or old.starts_at is distinct from starts or old.ends_at is distinct from ends or old.availability_fraction is distinct from frac or old.metadata is distinct from expected then raise exception 'sourceKey retry does not match existing Principal capacity adjustment.' using errcode='23505'; end if;
    rowv:=old;
  else
    insert into atlas.principal_capacity_adjustments(principal_id,title,adjustment_kind,starts_at,ends_at,availability_fraction,active,source_type,source_id,metadata)
    values(p.id,title,kind,starts,ends,frac,true,'principal_self_capacity_adjustment_v1',key,expected) returning * into rowv; made:=true;
    insert into atlas.principal_capacity_adjustment_events(capacity_adjustment_id,principal_id,actor_user_id,event_kind,from_active,to_active,reason,metadata)
    values(rowv.id,p.id,u,'recorded',null,true,null,jsonb_build_object('sourceKey',key,'authoringContract','principal_capacity_adjustment_self_writer_v1'));
  end if;
  return jsonb_build_object('ok',true,'created',made,'contractVersion','principal_capacity_adjustment_self_writer_v1','capacityAdjustment',jsonb_build_object('id',rowv.id,'title',rowv.title,'adjustmentKind',rowv.adjustment_kind,'startsAt',rowv.starts_at,'endsAt',rowv.ends_at,'availabilityFraction',rowv.availability_fraction,'active',rowv.active,'context',nullif(rowv.metadata->>'userContext',''),'sourceKey',rowv.source_id,'sourceEvidenceId',nullif(rowv.metadata->>'sourceEvidenceId','')),'capacityStateOnStartDate',atlas.principal_capacity_day_state_v1(p.id,(starts at time zone tz)::date),
    'truthBoundary',jsonb_build_object('adjustmentChangesCapacityBudgetNotClock',true,'zeroAvailabilityBelongsInCapacityBlock',true,'doesNotCreateTask',true,'doesNotCreateOwnerObligation',true,'doesNotInferCause',true));
end;
$function$;

create or replace function atlas.transition_principal_capacity_adjustment_self_api_v1(p_capacity_adjustment_id uuid,p_transition text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare u uuid:=auth.uid(); pid uuid; rowv atlas.principal_capacity_adjustments%rowtype; tr text:=lower(nullif(btrim(p_transition),'')); reason text:=nullif(btrim(coalesce(p_reason,'')),''); target boolean; ev text;
begin
  if u is null then raise exception 'Sign in required.' using errcode='42501'; end if; pid:=atlas.current_principal_id_v1(); if pid is null then raise exception 'Active Principal required.' using errcode='42501'; end if;
  if p_capacity_adjustment_id is null or tr is null then raise exception 'capacityAdjustmentId and transition are required.' using errcode='22023'; end if; if tr not in ('cancel','reopen') then raise exception 'transition must be cancel or reopen.' using errcode='22023'; end if;
  select * into rowv from atlas.principal_capacity_adjustments a where a.id=p_capacity_adjustment_id and a.principal_id=pid and a.source_type='principal_self_capacity_adjustment_v1' for update; if rowv.id is null then raise exception 'Principal-authored capacity adjustment not found.' using errcode='P0002'; end if;
  target:=tr='reopen'; ev:=case when target then 'reopened' else 'cancelled' end;
  if rowv.active is distinct from target then
    insert into atlas.principal_capacity_adjustment_events(capacity_adjustment_id,principal_id,actor_user_id,event_kind,from_active,to_active,reason,metadata) values(rowv.id,pid,u,ev,rowv.active,target,reason,jsonb_build_object('transitionContract','principal_capacity_adjustment_self_transition_v1'));
    update atlas.principal_capacity_adjustments set active=target,updated_at=now() where id=rowv.id returning * into rowv;
  end if;
  return jsonb_build_object('ok',true,'contractVersion','principal_capacity_adjustment_self_transition_v1','capacityAdjustment',jsonb_build_object('id',rowv.id,'title',rowv.title,'startsAt',rowv.starts_at,'endsAt',rowv.ends_at,'availabilityFraction',rowv.availability_fraction,'active',rowv.active,'sourceKey',rowv.source_id),'transition',tr,
    'truthBoundary',jsonb_build_object('cancelDoesNotDeleteHistory',true,'reopenRestoresOnlyAdjustmentState',true,'transitionDoesNotCreateClockPlacement',true));
end;
$function$;

create or replace function atlas.principal_capacity_adjustments_self_api_v1(p_start_at timestamptz default null,p_end_at timestamptz default null,p_include_inactive boolean default false)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $function$
declare u uuid:=auth.uid(); pid uuid; items jsonb;
begin
  if u is null then raise exception 'Sign in required.' using errcode='42501'; end if; pid:=atlas.current_principal_id_v1(); if pid is null then raise exception 'Active Principal required.' using errcode='42501'; end if;
  if p_start_at is not null and p_end_at is not null and p_end_at<=p_start_at then raise exception 'endAt must be later than startAt.' using errcode='22023'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'title',a.title,'adjustmentKind',a.adjustment_kind,'startsAt',a.starts_at,'endsAt',a.ends_at,'availabilityFraction',a.availability_fraction,'active',a.active,'context',nullif(a.metadata->>'userContext',''),'sourceKey',a.source_id,'sourceEvidenceId',nullif(a.metadata->>'sourceEvidenceId',''),'createdAt',a.created_at,'updatedAt',a.updated_at) order by a.starts_at,a.created_at,a.id),'[]'::jsonb) into items
  from atlas.principal_capacity_adjustments a where a.principal_id=pid and a.source_type='principal_self_capacity_adjustment_v1' and (p_include_inactive or a.active) and (p_start_at is null or a.ends_at>p_start_at) and (p_end_at is null or a.starts_at<p_end_at);
  return jsonb_build_object('ok',true,'contractVersion','principal_capacity_adjustments_self_v1','principalId',pid,'count',jsonb_array_length(items),'items',items,
    'truthBoundary',jsonb_build_object('adjustmentsAreCapacityBudgetTruthNotPriorityOrder',true,'inactiveRowsRemainHistorical',true,'adjustmentsAreNotClockCandidates',true));
end;
$function$;

revoke all on function atlas.record_principal_capacity_block_self_api_v1(jsonb) from public,anon;
revoke all on function atlas.transition_principal_capacity_block_self_api_v1(uuid,text,text) from public,anon;
revoke all on function atlas.principal_capacity_blocks_self_api_v1(timestamptz,timestamptz,boolean) from public,anon;
revoke all on function atlas.record_principal_capacity_adjustment_self_api_v1(jsonb) from public,anon;
revoke all on function atlas.transition_principal_capacity_adjustment_self_api_v1(uuid,text,text) from public,anon;
revoke all on function atlas.principal_capacity_adjustments_self_api_v1(timestamptz,timestamptz,boolean) from public,anon;
grant execute on function atlas.record_principal_capacity_block_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function atlas.transition_principal_capacity_block_self_api_v1(uuid,text,text) to authenticated,service_role;
grant execute on function atlas.principal_capacity_blocks_self_api_v1(timestamptz,timestamptz,boolean) to authenticated,service_role;
grant execute on function atlas.record_principal_capacity_adjustment_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function atlas.transition_principal_capacity_adjustment_self_api_v1(uuid,text,text) to authenticated,service_role;
grant execute on function atlas.principal_capacity_adjustments_self_api_v1(timestamptz,timestamptz,boolean) to authenticated,service_role;

create or replace function public.record_principal_capacity_block_self_api_v1(p_input jsonb) returns jsonb language sql security definer set search_path=pg_catalog as $function$ select atlas.record_principal_capacity_block_self_api_v1(p_input); $function$;
create or replace function public.transition_principal_capacity_block_self_api_v1(p_capacity_block_id uuid,p_transition text,p_reason text default null) returns jsonb language sql security definer set search_path=pg_catalog as $function$ select atlas.transition_principal_capacity_block_self_api_v1(p_capacity_block_id,p_transition,p_reason); $function$;
create or replace function public.principal_capacity_blocks_self_api_v1(p_start_at timestamptz default null,p_end_at timestamptz default null,p_include_inactive boolean default false) returns jsonb language sql stable security definer set search_path=pg_catalog as $function$ select atlas.principal_capacity_blocks_self_api_v1(p_start_at,p_end_at,p_include_inactive); $function$;
create or replace function public.record_principal_capacity_adjustment_self_api_v1(p_input jsonb) returns jsonb language sql security definer set search_path=pg_catalog as $function$ select atlas.record_principal_capacity_adjustment_self_api_v1(p_input); $function$;
create or replace function public.transition_principal_capacity_adjustment_self_api_v1(p_capacity_adjustment_id uuid,p_transition text,p_reason text default null) returns jsonb language sql security definer set search_path=pg_catalog as $function$ select atlas.transition_principal_capacity_adjustment_self_api_v1(p_capacity_adjustment_id,p_transition,p_reason); $function$;
create or replace function public.principal_capacity_adjustments_self_api_v1(p_start_at timestamptz default null,p_end_at timestamptz default null,p_include_inactive boolean default false) returns jsonb language sql stable security definer set search_path=pg_catalog as $function$ select atlas.principal_capacity_adjustments_self_api_v1(p_start_at,p_end_at,p_include_inactive); $function$;
revoke all on function public.record_principal_capacity_block_self_api_v1(jsonb) from public,anon;
revoke all on function public.transition_principal_capacity_block_self_api_v1(uuid,text,text) from public,anon;
revoke all on function public.principal_capacity_blocks_self_api_v1(timestamptz,timestamptz,boolean) from public,anon;
revoke all on function public.record_principal_capacity_adjustment_self_api_v1(jsonb) from public,anon;
revoke all on function public.transition_principal_capacity_adjustment_self_api_v1(uuid,text,text) from public,anon;
revoke all on function public.principal_capacity_adjustments_self_api_v1(timestamptz,timestamptz,boolean) from public,anon;
grant execute on function public.record_principal_capacity_block_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function public.transition_principal_capacity_block_self_api_v1(uuid,text,text) to authenticated,service_role;
grant execute on function public.principal_capacity_blocks_self_api_v1(timestamptz,timestamptz,boolean) to authenticated,service_role;
grant execute on function public.record_principal_capacity_adjustment_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function public.transition_principal_capacity_adjustment_self_api_v1(uuid,text,text) to authenticated,service_role;
grant execute on function public.principal_capacity_adjustments_self_api_v1(timestamptz,timestamptz,boolean) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(signature,classification,confidence,review_status,authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,caller_count,policy_reference_count,evidence,registered_at)
values
('atlas.record_principal_capacity_block_self_api_v1(p_input jsonb)','owner_admin_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Record explicit complete temporary unavailability.','canonicalOwner','atlas.principal_capacity_blocks','boundary','Protected strategy and partial availability are rejected by this writer.'),now()),
('atlas.transition_principal_capacity_block_self_api_v1(p_capacity_block_id uuid, p_transition text, p_reason text)','owner_admin_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Cancel/reopen the Principal own self-authored capacity block.'),now()),
('atlas.principal_capacity_blocks_self_api_v1(p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_include_inactive boolean)','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Read self-authored complete-unavailability intervals.'),now()),
('atlas.record_principal_capacity_adjustment_self_api_v1(p_input jsonb)','owner_admin_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Record explicit temporary partial availability.','canonicalOwner','atlas.principal_capacity_adjustments','boundary','Changes capacity budget only; no Clock candidate or task is created.'),now()),
('atlas.transition_principal_capacity_adjustment_self_api_v1(p_capacity_adjustment_id uuid, p_transition text, p_reason text)','owner_admin_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Cancel/reopen the Principal own self-authored capacity adjustment.'),now()),
('atlas.principal_capacity_adjustments_self_api_v1(p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_include_inactive boolean)','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Read self-authored reduced-capacity intervals.'),now())
on conflict(signature) do update set classification=excluded.classification,confidence=excluded.confidence,review_status=excluded.review_status,authenticated_execute_expected=excluded.authenticated_execute_expected,security_definer_expected=excluded.security_definer_expected,service_execute_expected=excluded.service_execute_expected,anonymous_execute_expected=excluded.anonymous_execute_expected,evidence=atlas.authenticated_rpc_registry.evidence||excluded.evidence,reviewed_at=now();