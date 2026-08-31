BEGIN;

-- Atlas Commitment Ledger kernel v1.
--
-- Trust boundary:
--   reality and obligations may change continuously;
--   a plan Atlas has committed to a human must remain reconstructible forever.
--
-- This migration is deliberately domain-neutral. Farm Worker Day is only a
-- shadow adapter proving the kernel; it is not an authority embedded in the
-- kernel and this migration does not change any current worker-facing feed.

create table atlas.commitment_plans (
  id uuid primary key default gen_random_uuid(),
  plan_key text not null check (btrim(plan_key) <> ''),
  plan_kind text not null check (btrim(plan_kind) <> ''),
  custody_kind text not null check (custody_kind in ('organization','principal')),
  organization_id uuid references atlas.organizations(id) on delete restrict,
  principal_id uuid references atlas.principals(id) on delete restrict,
  recipient_kind text not null check (btrim(recipient_kind) <> ''),
  recipient_id uuid not null,
  effective_start timestamptz,
  effective_end timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (
    (custody_kind='organization' and organization_id is not null and principal_id is null)
    or
    (custody_kind='principal' and principal_id is not null and organization_id is null)
  ),
  check (effective_end is null or effective_start is null or effective_end >= effective_start)
);

create unique index commitment_plans_organization_key_uq
  on atlas.commitment_plans (organization_id, plan_key)
  where custody_kind='organization';
create unique index commitment_plans_principal_key_uq
  on atlas.commitment_plans (principal_id, plan_key)
  where custody_kind='principal';
create index commitment_plans_recipient_idx
  on atlas.commitment_plans (recipient_kind, recipient_id, plan_kind, created_at desc);

create table atlas.commitment_plan_generations (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references atlas.commitment_plans(id) on delete restrict,
  generation_number integer not null check (generation_number > 0),
  supersedes_generation_id uuid references atlas.commitment_plan_generations(id) on delete restrict,
  generation_reason text not null check (btrim(generation_reason) <> ''),
  source_kind text not null check (btrim(source_kind) <> ''),
  source_id uuid,
  planner_contract text,
  content_digest text not null check (content_digest ~ '^[0-9a-f]{64}$'),
  committed_at timestamptz not null default now(),
  actor_user_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (plan_id, generation_number),
  check (
    (generation_number=1 and supersedes_generation_id is null)
    or
    (generation_number>1 and supersedes_generation_id is not null)
  )
);

create index commitment_plan_generations_current_idx
  on atlas.commitment_plan_generations (plan_id, generation_number desc);

create table atlas.commitment_items (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references atlas.commitment_plans(id) on delete restrict,
  generation_id uuid not null references atlas.commitment_plan_generations(id) on delete restrict,
  stable_item_key text not null check (btrim(stable_item_key) <> ''),
  source_kind text not null check (btrim(source_kind) <> ''),
  source_id uuid,
  execution_kind text,
  execution_id uuid,
  title_snapshot text not null check (btrim(title_snapshot) <> ''),
  sequence_number integer not null check (sequence_number > 0),
  window_key text,
  expected_active_minutes integer check (expected_active_minutes is null or expected_active_minutes >= 0),
  physical_load text,
  admission_reason text not null check (btrim(admission_reason) <> ''),
  execution_warrant jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (generation_id, stable_item_key),
  unique (generation_id, sequence_number)
);

create index commitment_items_plan_generation_idx
  on atlas.commitment_items (plan_id, generation_id, sequence_number);
create index commitment_items_execution_idx
  on atlas.commitment_items (execution_kind, execution_id)
  where execution_id is not null;

create table atlas.commitment_events (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references atlas.commitment_plans(id) on delete restrict,
  generation_id uuid references atlas.commitment_plan_generations(id) on delete restrict,
  item_id uuid references atlas.commitment_items(id) on delete restrict,
  event_kind text not null check (event_kind in (
    'plan_committed',
    'plan_superseded',
    'item_admitted',
    'item_carried_forward',
    'item_withdrawn',
    'item_interrupted',
    'item_resumed',
    'item_completed',
    'plan_closed'
  )),
  reason text not null check (btrim(reason) <> ''),
  source_kind text not null check (btrim(source_kind) <> ''),
  source_id uuid,
  actor_user_id uuid,
  evidence jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index commitment_events_plan_idx
  on atlas.commitment_events (plan_id, occurred_at, id);
create index commitment_events_item_idx
  on atlas.commitment_events (item_id, occurred_at, id)
  where item_id is not null;

create or replace function atlas.reject_commitment_history_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
begin
  raise exception 'Atlas commitment history is append-only.' using errcode='55000';
end;
$function$;

create trigger commitment_plans_immutable
before update or delete on atlas.commitment_plans
for each row execute function atlas.reject_commitment_history_mutation_v1();

create trigger commitment_plan_generations_immutable
before update or delete on atlas.commitment_plan_generations
for each row execute function atlas.reject_commitment_history_mutation_v1();

create trigger commitment_items_immutable
before update or delete on atlas.commitment_items
for each row execute function atlas.reject_commitment_history_mutation_v1();

create trigger commitment_events_immutable
before update or delete on atlas.commitment_events
for each row execute function atlas.reject_commitment_history_mutation_v1();

create or replace function atlas.commitment_plan_current_generation_v1(p_plan_id uuid)
returns jsonb
language sql
stable security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
  select case when g.id is null then null else jsonb_build_object(
    'contractVersion','commitment_plan_current_generation_v1',
    'planId',g.plan_id,
    'generationId',g.id,
    'generationNumber',g.generation_number,
    'contentDigest',g.content_digest,
    'generationReason',g.generation_reason,
    'sourceKind',g.source_kind,
    'sourceId',g.source_id,
    'plannerContract',g.planner_contract,
    'committedAt',g.committed_at,
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'itemId',i.id,
        'stableItemKey',i.stable_item_key,
        'sourceKind',i.source_kind,
        'sourceId',i.source_id,
        'executionKind',i.execution_kind,
        'executionId',i.execution_id,
        'title',i.title_snapshot,
        'sequenceNumber',i.sequence_number,
        'windowKey',i.window_key,
        'expectedActiveMinutes',i.expected_active_minutes,
        'physicalLoad',i.physical_load,
        'admissionReason',i.admission_reason,
        'executionWarrant',i.execution_warrant,
        'metadata',i.metadata
      ) order by i.sequence_number)
      from atlas.commitment_items i
      where i.generation_id=g.id
    ),'[]'::jsonb)
  ) end
  from atlas.commitment_plan_generations g
  where g.plan_id=p_plan_id
  order by g.generation_number desc
  limit 1;
$function$;

create or replace function atlas.commit_plan_generation_v1(
  p_plan_key text,
  p_plan_kind text,
  p_custody_kind text,
  p_organization_id uuid,
  p_principal_id uuid,
  p_recipient_kind text,
  p_recipient_id uuid,
  p_effective_start timestamptz,
  p_effective_end timestamptz,
  p_items jsonb,
  p_generation_reason text,
  p_source_kind text,
  p_source_id uuid default null,
  p_planner_contract text default null,
  p_actor_user_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','extensions'
as $function$
declare
  v_plan atlas.commitment_plans%rowtype;
  v_previous atlas.commitment_plan_generations%rowtype;
  v_generation_id uuid;
  v_generation_number integer;
  v_digest text;
  v_item jsonb;
  v_item_id uuid;
  v_sequence integer:=0;
  v_seen_keys text[]:=array[]::text[];
  v_stable_key text;
  v_previous_item_id uuid;
  v_event_time timestamptz:=now();
begin
  if nullif(btrim(p_plan_key),'') is null
     or nullif(btrim(p_plan_kind),'') is null
     or nullif(btrim(p_recipient_kind),'') is null
     or p_recipient_id is null
     or nullif(btrim(p_generation_reason),'') is null
     or nullif(btrim(p_source_kind),'') is null then
    raise exception 'Commitment plan identity, recipient, reason, and source are required.' using errcode='22023';
  end if;
  if p_custody_kind not in ('organization','principal') then
    raise exception 'Unsupported commitment custody kind.' using errcode='22023';
  end if;
  if (p_custody_kind='organization' and (p_organization_id is null or p_principal_id is not null))
     or (p_custody_kind='principal' and (p_principal_id is null or p_organization_id is not null)) then
    raise exception 'Commitment custody reference does not match custody kind.' using errcode='22023';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then
    raise exception 'A committed plan generation requires at least one item.' using errcode='22023';
  end if;

  -- Serialize plans by stable custody + plan key even before the identity row exists.
  perform pg_advisory_xact_lock(hashtextextended(
    p_custody_kind||':'||coalesce(p_organization_id::text,p_principal_id::text)||':'||btrim(p_plan_key),0
  ));

  if p_custody_kind='organization' then
    select * into v_plan
    from atlas.commitment_plans p
    where p.organization_id=p_organization_id and p.plan_key=btrim(p_plan_key)
    limit 1;
  else
    select * into v_plan
    from atlas.commitment_plans p
    where p.principal_id=p_principal_id and p.plan_key=btrim(p_plan_key)
    limit 1;
  end if;

  if v_plan.id is null then
    insert into atlas.commitment_plans(
      plan_key,plan_kind,custody_kind,organization_id,principal_id,
      recipient_kind,recipient_id,effective_start,effective_end,metadata
    ) values (
      btrim(p_plan_key),btrim(p_plan_kind),p_custody_kind,p_organization_id,p_principal_id,
      btrim(p_recipient_kind),p_recipient_id,p_effective_start,p_effective_end,coalesce(p_metadata,'{}'::jsonb)
    ) returning * into v_plan;
  else
    if v_plan.plan_kind is distinct from btrim(p_plan_kind)
       or v_plan.custody_kind is distinct from p_custody_kind
       or v_plan.organization_id is distinct from p_organization_id
       or v_plan.principal_id is distinct from p_principal_id
       or v_plan.recipient_kind is distinct from btrim(p_recipient_kind)
       or v_plan.recipient_id is distinct from p_recipient_id
       or v_plan.effective_start is distinct from p_effective_start
       or v_plan.effective_end is distinct from p_effective_end then
      raise exception 'Existing commitment plan identity cannot be mutated; mint a new plan key.' using errcode='55000';
    end if;
  end if;

  -- JSONB text canonicalizes object key order; array order intentionally remains
  -- part of the commitment because ordering is part of what Atlas promised.
  v_digest:=encode(extensions.digest(p_items::text,'sha256'),'hex');

  select * into v_previous
  from atlas.commitment_plan_generations g
  where g.plan_id=v_plan.id
  order by g.generation_number desc
  limit 1
  for update;

  if v_previous.id is not null and v_previous.content_digest=v_digest then
    return jsonb_build_object(
      'contractVersion','commit_plan_generation_v1',
      'state','unchanged',
      'planId',v_plan.id,
      'generationId',v_previous.id,
      'generationNumber',v_previous.generation_number,
      'contentDigest',v_previous.content_digest,
      'trustBoundary',jsonb_build_object(
        'samePlanDoesNotMintGeneration',true,
        'priorGenerationsImmutable',true,
        'planChangeRequiresExplicitReason',true
      )
    );
  end if;

  v_generation_number:=coalesce(v_previous.generation_number,0)+1;
  insert into atlas.commitment_plan_generations(
    plan_id,generation_number,supersedes_generation_id,generation_reason,
    source_kind,source_id,planner_contract,content_digest,committed_at,
    actor_user_id,metadata
  ) values (
    v_plan.id,v_generation_number,v_previous.id,btrim(p_generation_reason),
    btrim(p_source_kind),p_source_id,nullif(btrim(p_planner_contract),''),v_digest,
    v_event_time,p_actor_user_id,coalesce(p_metadata,'{}'::jsonb)
  ) returning id into v_generation_id;

  if v_previous.id is not null then
    insert into atlas.commitment_events(
      plan_id,generation_id,event_kind,reason,source_kind,source_id,actor_user_id,evidence,metadata,occurred_at
    ) values (
      v_plan.id,v_generation_id,'plan_superseded',btrim(p_generation_reason),btrim(p_source_kind),
      p_source_id,p_actor_user_id,
      jsonb_build_object('supersededGenerationId',v_previous.id,'supersededGenerationNumber',v_previous.generation_number),
      '{}'::jsonb,v_event_time
    );
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_sequence:=v_sequence+1;
    v_stable_key:=nullif(btrim(v_item->>'stableItemKey'),'');
    if v_stable_key is null or nullif(btrim(v_item->>'sourceKind'),'') is null or nullif(btrim(v_item->>'title'),'') is null then
      raise exception 'Every commitment item requires stableItemKey, sourceKind, and title.' using errcode='22023';
    end if;
    if v_stable_key=any(v_seen_keys) then
      raise exception 'Duplicate commitment stable item key: %',v_stable_key using errcode='23505';
    end if;
    v_seen_keys:=array_append(v_seen_keys,v_stable_key);

    insert into atlas.commitment_items(
      plan_id,generation_id,stable_item_key,source_kind,source_id,
      execution_kind,execution_id,title_snapshot,sequence_number,window_key,
      expected_active_minutes,physical_load,admission_reason,execution_warrant,metadata
    ) values (
      v_plan.id,v_generation_id,v_stable_key,btrim(v_item->>'sourceKind'),
      nullif(v_item->>'sourceId','')::uuid,
      nullif(btrim(v_item->>'executionKind'),''),nullif(v_item->>'executionId','')::uuid,
      btrim(v_item->>'title'),v_sequence,nullif(btrim(v_item->>'windowKey'),''),
      case when coalesce(v_item->>'expectedActiveMinutes','') ~ '^\d+$' then (v_item->>'expectedActiveMinutes')::integer else null end,
      nullif(btrim(v_item->>'physicalLoad'),''),
      coalesce(nullif(btrim(v_item->>'admissionReason'),''),'planner_admitted'),
      coalesce(v_item->'executionWarrant','{}'::jsonb),coalesce(v_item->'metadata','{}'::jsonb)
    ) returning id into v_item_id;

    v_previous_item_id:=null;
    if v_previous.id is not null then
      select i.id into v_previous_item_id
      from atlas.commitment_items i
      where i.generation_id=v_previous.id and i.stable_item_key=v_stable_key;
    end if;

    insert into atlas.commitment_events(
      plan_id,generation_id,item_id,event_kind,reason,source_kind,source_id,actor_user_id,evidence,metadata,occurred_at
    ) values (
      v_plan.id,v_generation_id,v_item_id,
      case when v_previous_item_id is null then 'item_admitted' else 'item_carried_forward' end,
      btrim(p_generation_reason),btrim(p_source_kind),p_source_id,p_actor_user_id,
      case when v_previous_item_id is null then '{}'::jsonb else jsonb_build_object('previousItemId',v_previous_item_id) end,
      '{}'::jsonb,v_event_time
    );
  end loop;

  if v_previous.id is not null then
    insert into atlas.commitment_events(
      plan_id,generation_id,item_id,event_kind,reason,source_kind,source_id,actor_user_id,evidence,metadata,occurred_at
    )
    select
      v_plan.id,v_generation_id,i.id,'item_withdrawn',btrim(p_generation_reason),btrim(p_source_kind),
      p_source_id,p_actor_user_id,
      jsonb_build_object('withdrawnFromGenerationId',v_previous.id,'newGenerationId',v_generation_id),
      '{}'::jsonb,v_event_time
    from atlas.commitment_items i
    where i.generation_id=v_previous.id
      and not (i.stable_item_key=any(v_seen_keys));
  end if;

  insert into atlas.commitment_events(
    plan_id,generation_id,event_kind,reason,source_kind,source_id,actor_user_id,evidence,metadata,occurred_at
  ) values (
    v_plan.id,v_generation_id,'plan_committed',btrim(p_generation_reason),btrim(p_source_kind),p_source_id,p_actor_user_id,
    jsonb_build_object(
      'generationNumber',v_generation_number,
      'contentDigest',v_digest,
      'itemCount',jsonb_array_length(p_items)
    ),coalesce(p_metadata,'{}'::jsonb),v_event_time
  );

  return jsonb_build_object(
    'contractVersion','commit_plan_generation_v1',
    'state','committed',
    'planId',v_plan.id,
    'generationId',v_generation_id,
    'generationNumber',v_generation_number,
    'supersedesGenerationId',v_previous.id,
    'contentDigest',v_digest,
    'itemCount',jsonb_array_length(p_items),
    'trustBoundary',jsonb_build_object(
      'priorGenerationsImmutable',true,
      'samePlanDoesNotMintGeneration',true,
      'planChangeRequiresExplicitReason',true,
      'humanCommitmentIsNotLivePlannerOutput',true
    )
  );
end;
$function$;

create or replace function atlas.record_commitment_event_v1(
  p_plan_id uuid,
  p_generation_id uuid,
  p_item_id uuid,
  p_event_kind text,
  p_reason text,
  p_source_kind text,
  p_source_id uuid default null,
  p_actor_user_id uuid default null,
  p_evidence jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_event_id uuid;
begin
  if p_event_kind not in ('item_interrupted','item_resumed','item_completed','plan_closed') then
    raise exception 'This event API only records post-commitment lifecycle evidence.' using errcode='22023';
  end if;
  if nullif(btrim(p_reason),'') is null or nullif(btrim(p_source_kind),'') is null then
    raise exception 'Commitment transition reason and source are required.' using errcode='22023';
  end if;
  if p_event_kind in ('item_interrupted','item_resumed','item_completed') and p_item_id is null then
    raise exception 'Item transition requires a commitment item.' using errcode='22023';
  end if;
  if p_generation_id is not null and not exists(
    select 1 from atlas.commitment_plan_generations g where g.id=p_generation_id and g.plan_id=p_plan_id
  ) then
    raise exception 'Commitment generation does not belong to plan.' using errcode='23503';
  end if;
  if p_item_id is not null and not exists(
    select 1 from atlas.commitment_items i where i.id=p_item_id and i.plan_id=p_plan_id
      and (p_generation_id is null or i.generation_id=p_generation_id)
  ) then
    raise exception 'Commitment item does not belong to plan/generation.' using errcode='23503';
  end if;

  insert into atlas.commitment_events(
    plan_id,generation_id,item_id,event_kind,reason,source_kind,source_id,
    actor_user_id,evidence,metadata
  ) values (
    p_plan_id,p_generation_id,p_item_id,p_event_kind,btrim(p_reason),btrim(p_source_kind),p_source_id,
    p_actor_user_id,coalesce(p_evidence,'{}'::jsonb),coalesce(p_metadata,'{}'::jsonb)
  ) returning id into v_event_id;

  return jsonb_build_object(
    'contractVersion','record_commitment_event_v1',
    'state','recorded','eventId',v_event_id,'eventKind',p_event_kind,
    'planId',p_plan_id,'generationId',p_generation_id,'itemId',p_item_id
  );
end;
$function$;

-- Farm Worker Day is the first adapter proof, not a kernel special case.
-- This function only captures the current validated projection into the neutral
-- ledger when explicitly invoked by service authority. It changes no task,
-- placement, selector, notification, or worker-facing API.
create or replace function atlas.capture_worker_day_commitment_shadow_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date,
  p_reason text,
  p_actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_org_id uuid;
  v_items jsonb;
  v_start timestamptz;
  v_end timestamptz;
begin
  if p_day is null or nullif(btrim(p_reason),'') is null then
    raise exception 'Worker Day shadow capture requires day and explicit reason.' using errcode='22023';
  end if;

  select fm.organization_id into v_org_id
  from atlas.farm_memberships fm
  where fm.id=p_membership_id and fm.farm_id=p_farm_id and fm.active=true;
  if v_org_id is null then
    raise exception 'Active membership on farm is required.' using errcode='42501';
  end if;

  v_start:=(p_day::text||' 00:00:00 America/Chicago')::timestamptz;
  v_end:=((p_day+1)::text||' 00:00:00 America/Chicago')::timestamptz;

  select coalesce(jsonb_agg(jsonb_build_object(
    'stableItemKey','task:'||t.id::text,
    'sourceKind','task',
    'sourceId',t.id,
    'executionKind','task',
    'executionId',t.id,
    'title',t.title,
    'windowKey',resolved.placement->>'dayWindow',
    'expectedActiveMinutes',capacity.expected_active_minutes,
    'physicalLoad',capacity.physical_load,
    'admissionReason',projection.presentation_reason,
    'executionWarrant',jsonb_build_object(
      'executionReadiness',atlas.task_execution_readiness_v1(t.id),
      'operationFit',atlas.task_operation_fit_warrant_v1(t.id),
      'projectionContract','worker_day_work_projection_v1'
    ),
    'metadata',jsonb_build_object(
      'selectionRank',projection.selection_rank,
      'workLane',projection.work_lane,
      'commitmentKind',projection.commitment_kind,
      'visibilityReason',projection.visibility_reason,
      'presentationReason',projection.presentation_reason
    )
  ) order by projection.selection_rank,t.id),'[]'::jsonb)
  into v_items
  from atlas.worker_day_work_projection_v1(p_farm_id,p_membership_id,p_day) projection
  join atlas.tasks t on t.id=projection.task_id
  cross join lateral atlas.task_capacity_plan_v1(t,p_day) capacity
  cross join lateral (
    select atlas.worker_task_effective_placement_v1(p_farm_id,p_membership_id,t.id,p_day) as placement
  ) resolved;

  if jsonb_array_length(v_items)=0 then
    raise exception 'Worker Day projection has no presentable items to commit.' using errcode='22023';
  end if;

  return atlas.commit_plan_generation_v1(
    'worker_day:'||p_farm_id::text||':'||p_membership_id::text||':'||p_day::text,
    'worker_day',
    'organization',
    v_org_id,
    null,
    'farm_membership',
    p_membership_id,
    v_start,
    v_end,
    v_items,
    p_reason,
    'worker_day_shadow_adapter',
    null,
    'worker_day_work_projection_v1',
    p_actor_user_id,
    jsonb_build_object(
      'farmId',p_farm_id,
      'serviceDate',p_day,
      'shadowOnly',true,
      'doesNotDrivePresentation',true
    )
  );
end;
$function$;

alter table atlas.commitment_plans enable row level security;
alter table atlas.commitment_plan_generations enable row level security;
alter table atlas.commitment_items enable row level security;
alter table atlas.commitment_events enable row level security;

revoke all on atlas.commitment_plans from public,anon,authenticated;
revoke all on atlas.commitment_plan_generations from public,anon,authenticated;
revoke all on atlas.commitment_items from public,anon,authenticated;
revoke all on atlas.commitment_events from public,anon,authenticated;
grant select,insert on atlas.commitment_plans to service_role;
grant select,insert on atlas.commitment_plan_generations to service_role;
grant select,insert on atlas.commitment_items to service_role;
grant select,insert on atlas.commitment_events to service_role;

revoke all on function atlas.reject_commitment_history_mutation_v1() from public,anon,authenticated;
revoke all on function atlas.commitment_plan_current_generation_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.commit_plan_generation_v1(text,text,text,uuid,uuid,text,uuid,timestamptz,timestamptz,jsonb,text,text,uuid,text,uuid,jsonb) from public,anon,authenticated;
revoke all on function atlas.record_commitment_event_v1(uuid,uuid,uuid,text,text,text,uuid,uuid,jsonb,jsonb) from public,anon,authenticated;
revoke all on function atlas.capture_worker_day_commitment_shadow_v1(uuid,uuid,date,text,uuid) from public,anon,authenticated;

grant execute on function atlas.reject_commitment_history_mutation_v1() to service_role;
grant execute on function atlas.commitment_plan_current_generation_v1(uuid) to service_role;
grant execute on function atlas.commit_plan_generation_v1(text,text,text,uuid,uuid,text,uuid,timestamptz,timestamptz,jsonb,text,text,uuid,text,uuid,jsonb) to service_role;
grant execute on function atlas.record_commitment_event_v1(uuid,uuid,uuid,text,text,text,uuid,uuid,jsonb,jsonb) to service_role;
grant execute on function atlas.capture_worker_day_commitment_shadow_v1(uuid,uuid,date,text,uuid) to service_role;

comment on table atlas.commitment_plans is
  'Immutable identity envelope for a human/organizational commitment plan. Custody and recipient identity are separate so domains do not own the person.';
comment on table atlas.commitment_plan_generations is
  'Append-only committed plan generations. A changed plan requires a new generation with explicit source and reason; prior generations are never overwritten.';
comment on table atlas.commitment_items is
  'Immutable execution-item snapshots admitted to a specific plan generation, including the execution warrant Atlas relied on when making the commitment.';
comment on table atlas.commitment_events is
  'Append-only evidence explaining commitment creation, supersession, interruption, resumption, completion, withdrawal, and closure.';
comment on function atlas.commit_plan_generation_v1(text,text,text,uuid,uuid,text,uuid,timestamptz,timestamptz,jsonb,text,text,uuid,text,uuid,jsonb) is
  'Generic Atlas commitment writer. Identical content is a no-op; changed content creates a new immutable generation only with explicit source and reason.';
comment on function atlas.capture_worker_day_commitment_shadow_v1(uuid,uuid,date,text,uuid) is
  'Shadow-only farm adapter proving the neutral Commitment Ledger. Captures current validated Worker Day output but does not alter any worker-facing behavior.';

COMMIT;
