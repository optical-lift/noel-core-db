-- Principal Capacity self-writer v1
--
-- Canonical truth owner: atlas.principal_capacity_blocks.
-- This migration adds a narrow authenticated authoring membrane for temporary, user-confirmed
-- intervals in which the Principal is unavailable for placement.
--
-- It does NOT infer diagnosis, cause, urgency, priority, task identity, or a scheduling decision.
-- The fixed-time floor/protection values written here are structural treatment for an explicitly
-- unavailable interval already confirmed by the Principal: those minutes are not discretionary
-- capacity. They are not a generic priority score and do not authorize unrelated work.

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
  metadata jsonb not null default '{}'::jsonb,
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
  v_reason text;
  v_source_evidence_id uuid;
  v_metadata jsonb;
  v_row atlas.principal_capacity_blocks%rowtype;
  v_existing atlas.principal_capacity_blocks%rowtype;
  v_created boolean:=false;
begin
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Principal capacity input must be an object.' using errcode='22023';
  end if;

  select * into v_principal
  from atlas.principals p
  where p.user_id=v_user_id and p.status='active'
  limit 1;
  if v_principal.id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  v_source_key:=nullif(btrim(p_input->>'sourceKey'),'');
  v_title:=nullif(btrim(p_input->>'title'),'');
  v_block_kind:=nullif(btrim(p_input->>'blockKind'),'');
  v_starts_at:=nullif(btrim(p_input->>'startsAt'),'')::timestamptz;
  v_ends_at:=nullif(btrim(p_input->>'endsAt'),'')::timestamptz;
  v_reason:=nullif(btrim(p_input->>'reason'),'');
  v_source_evidence_id:=nullif(btrim(p_input->>'sourceEvidenceId'),'')::uuid;
  v_metadata:=coalesce(case when jsonb_typeof(p_input->'metadata')='object' then p_input->'metadata' end,'{}'::jsonb);

  if v_source_key is null or v_title is null or v_block_kind is null or v_starts_at is null or v_ends_at is null then
    raise exception 'sourceKey, title, blockKind, startsAt, and endsAt are required.' using errcode='22023';
  end if;
  if v_ends_at<=v_starts_at then
    raise exception 'endsAt must be later than startsAt.' using errcode='22023';
  end if;
  if v_block_kind not in ('human_fixed','household','family','travel','appointment','protected_strategy','recovery','other') then
    raise exception 'Unsupported Principal capacity block kind.' using errcode='22023';
  end if;

  if v_source_evidence_id is not null and not exists(
    select 1 from atlas.evidence_records e
    where e.id=v_source_evidence_id and e.scope_kind='person' and e.scope_id=v_user_id
  ) then
    raise exception 'sourceEvidenceId must identify evidence owned by the signed-in person.' using errcode='42501';
  end if;

  select * into v_existing
  from atlas.principal_capacity_blocks b
  where b.principal_id=v_principal.id
    and b.source_type='principal_self_capacity_v1'
    and b.source_id=v_source_key;

  if v_existing.id is not null then
    if v_existing.title is distinct from v_title
      or v_existing.block_kind is distinct from v_block_kind
      or v_existing.starts_at is distinct from v_starts_at
      or v_existing.ends_at is distinct from v_ends_at
      or v_existing.floor_class is distinct from 1
      or v_existing.protection_level is distinct from 'critical'
      or v_existing.interruptibility is distinct from 'should_not_interrupt'
      or v_existing.reason_for_floor is distinct from 'User-confirmed fixed interval in which Principal capacity is unavailable.'
      or v_existing.consequence is distinct from v_reason
      or coalesce(v_existing.metadata->>'sourceEvidenceId','') is distinct from coalesce(v_source_evidence_id::text,'')
      or (v_existing.metadata - 'sourceEvidenceId' - 'authoringContract' - 'truthBoundary') is distinct from v_metadata then
      raise exception 'sourceKey retry does not match existing Principal capacity block.' using errcode='23505';
    end if;
    v_row:=v_existing;
  else
    insert into atlas.principal_capacity_blocks(
      principal_id,title,block_kind,starts_at,ends_at,blocks_capacity,
      floor_class,protection_level,interruptibility,reason_for_floor,
      source_type,source_id,consequence,metadata
    ) values(
      v_principal.id,v_title,v_block_kind,v_starts_at,v_ends_at,true,
      1,'critical','should_not_interrupt',
      'User-confirmed fixed interval in which Principal capacity is unavailable.',
      'principal_self_capacity_v1',v_source_key,v_reason,
      v_metadata
        || case when v_source_evidence_id is null then '{}'::jsonb else jsonb_build_object('sourceEvidenceId',v_source_evidence_id) end
        || jsonb_build_object(
          'authoringContract','principal_capacity_self_writer_v1',
          'truthBoundary',jsonb_build_object(
            'intervalExplicitlyConfirmed',true,
            'diagnosisNotInferred',true,
            'causeNotInferred',true,
            'priorityScoreNotCreated',true,
            'taskNotCreated',true,
            'clockPlacementNotCreated',true,
            'unavailableMinutesAreNotDiscretionaryCapacity',true
          )
        )
    ) returning * into v_row;
    v_created:=true;

    insert into atlas.principal_capacity_block_events(
      capacity_block_id,principal_id,actor_user_id,event_kind,from_blocks_capacity,to_blocks_capacity,reason,metadata
    ) values(
      v_row.id,v_principal.id,v_user_id,'recorded',null,true,v_reason,
      jsonb_build_object('sourceKey',v_source_key,'authoringContract','principal_capacity_self_writer_v1')
    );
  end if;

  return jsonb_build_object(
    'ok',true,
    'created',v_created,
    'contractVersion','principal_capacity_self_writer_v1',
    'capacityBlock',jsonb_build_object(
      'id',v_row.id,
      'title',v_row.title,
      'blockKind',v_row.block_kind,
      'startsAt',v_row.starts_at,
      'endsAt',v_row.ends_at,
      'blocksCapacity',v_row.blocks_capacity,
      'sourceKey',v_row.source_id,
      'sourceEvidenceId',nullif(v_row.metadata->>'sourceEvidenceId','')
    ),
    'capacityStateOnStartDate',atlas.principal_capacity_day_state_v1(v_principal.id,(v_starts_at at time zone coalesce(nullif(v_principal.home_timezone,''),'America/Chicago'))::date),
    'truthBoundary',jsonb_build_object(
      'writerOwnsOnlyExplicitTemporaryUnavailability',true,
      'fixedTimeTreatmentIsStructuralNotPriorityScoring',true,
      'doesNotDiagnose',true,
      'doesNotCreateTask',true,
      'doesNotCreateOwnerObligation',true,
      'doesNotCreateClockPlacement',true,
      'doesNotInferCause',true
    )
  );
end;
$function$;

create or replace function atlas.transition_principal_capacity_block_self_api_v1(
  p_capacity_block_id uuid,
  p_transition text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_principal_id uuid;
  v_row atlas.principal_capacity_blocks%rowtype;
  v_transition text:=lower(nullif(btrim(p_transition),''));
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
  v_target boolean;
  v_event text;
begin
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_principal_id:=atlas.current_principal_id_v1();
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;
  if p_capacity_block_id is null or v_transition is null then
    raise exception 'capacityBlockId and transition are required.' using errcode='22023';
  end if;
  if v_transition not in ('cancel','reopen') then
    raise exception 'transition must be cancel or reopen.' using errcode='22023';
  end if;

  select * into v_row
  from atlas.principal_capacity_blocks b
  where b.id=p_capacity_block_id
    and b.principal_id=v_principal_id
    and b.source_type='principal_self_capacity_v1'
  for update;
  if v_row.id is null then raise exception 'Principal-authored capacity block not found.' using errcode='P0002'; end if;

  v_target:=v_transition='reopen';
  v_event:=case when v_target then 'reopened' else 'cancelled' end;

  if v_row.blocks_capacity is distinct from v_target then
    insert into atlas.principal_capacity_block_events(
      capacity_block_id,principal_id,actor_user_id,event_kind,from_blocks_capacity,to_blocks_capacity,reason,metadata
    ) values(
      v_row.id,v_principal_id,v_user_id,v_event,v_row.blocks_capacity,v_target,v_reason,
      jsonb_build_object('transitionContract','principal_capacity_self_transition_v1')
    );

    update atlas.principal_capacity_blocks
    set blocks_capacity=v_target,
        metadata=metadata||jsonb_strip_nulls(jsonb_build_object(
          'lastTransition',v_transition,
          'lastTransitionReason',v_reason,
          'lastTransitionAt',now()
        )),
        updated_at=now()
    where id=v_row.id
    returning * into v_row;
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','principal_capacity_self_transition_v1',
    'capacityBlock',jsonb_build_object(
      'id',v_row.id,'title',v_row.title,'startsAt',v_row.starts_at,'endsAt',v_row.ends_at,
      'blocksCapacity',v_row.blocks_capacity,'sourceKey',v_row.source_id
    ),
    'transition',v_transition,
    'truthBoundary',jsonb_build_object(
      'cancelDoesNotDeleteHistory',true,
      'reopenRestoresOnlyCapacityBlockingState',true,
      'transitionDoesNotCreateTask',true,
      'transitionDoesNotCreateClockPlacement',true
    )
  );
end;
$function$;

create or replace function atlas.principal_capacity_blocks_self_api_v1(
  p_start_at timestamptz default null,
  p_end_at timestamptz default null,
  p_include_inactive boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_principal_id uuid;
  v_items jsonb;
begin
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_principal_id:=atlas.current_principal_id_v1();
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;
  if p_start_at is not null and p_end_at is not null and p_end_at<=p_start_at then
    raise exception 'endAt must be later than startAt.' using errcode='22023';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',b.id,
    'title',b.title,
    'blockKind',b.block_kind,
    'startsAt',b.starts_at,
    'endsAt',b.ends_at,
    'blocksCapacity',b.blocks_capacity,
    'reason',b.consequence,
    'sourceKey',b.source_id,
    'sourceEvidenceId',nullif(b.metadata->>'sourceEvidenceId',''),
    'createdAt',b.created_at,
    'updatedAt',b.updated_at
  ) order by b.starts_at,b.created_at,b.id),'[]'::jsonb)
  into v_items
  from atlas.principal_capacity_blocks b
  where b.principal_id=v_principal_id
    and b.source_type='principal_self_capacity_v1'
    and (p_include_inactive or b.blocks_capacity)
    and (p_start_at is null or b.ends_at>p_start_at)
    and (p_end_at is null or b.starts_at<p_end_at);

  return jsonb_build_object(
    'ok',true,
    'contractVersion','principal_capacity_blocks_self_v1',
    'principalId',v_principal_id,
    'count',jsonb_array_length(v_items),
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'listIsCapacityTruthNotPriorityOrder',true,
      'inactiveRowsRemainHistoricalEvidence',true
    )
  );
end;
$function$;

revoke all on function atlas.record_principal_capacity_block_self_api_v1(jsonb) from public,anon;
revoke all on function atlas.transition_principal_capacity_block_self_api_v1(uuid,text,text) from public,anon;
revoke all on function atlas.principal_capacity_blocks_self_api_v1(timestamptz,timestamptz,boolean) from public,anon;
grant execute on function atlas.record_principal_capacity_block_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function atlas.transition_principal_capacity_block_self_api_v1(uuid,text,text) to authenticated,service_role;
grant execute on function atlas.principal_capacity_blocks_self_api_v1(timestamptz,timestamptz,boolean) to authenticated,service_role;

create or replace function public.record_principal_capacity_block_self_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.record_principal_capacity_block_self_api_v1(p_input); $function$;

create or replace function public.transition_principal_capacity_block_self_api_v1(
  p_capacity_block_id uuid,
  p_transition text,
  p_reason text default null
)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.transition_principal_capacity_block_self_api_v1(p_capacity_block_id,p_transition,p_reason); $function$;

create or replace function public.principal_capacity_blocks_self_api_v1(
  p_start_at timestamptz default null,
  p_end_at timestamptz default null,
  p_include_inactive boolean default false
)
returns jsonb language sql stable security definer set search_path=pg_catalog
as $function$ select atlas.principal_capacity_blocks_self_api_v1(p_start_at,p_end_at,p_include_inactive); $function$;

revoke all on function public.record_principal_capacity_block_self_api_v1(jsonb) from public,anon;
revoke all on function public.transition_principal_capacity_block_self_api_v1(uuid,text,text) from public,anon;
revoke all on function public.principal_capacity_blocks_self_api_v1(timestamptz,timestamptz,boolean) from public,anon;
grant execute on function public.record_principal_capacity_block_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function public.transition_principal_capacity_block_self_api_v1(uuid,text,text) to authenticated,service_role;
grant execute on function public.principal_capacity_blocks_self_api_v1(timestamptz,timestamptz,boolean) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
)
values
  (
    'atlas.record_principal_capacity_block_self_api_v1(p_input jsonb)',
    'owner_admin_endpoint','verified','active',true,true,true,false,1,0,
    jsonb_build_object(
      'purpose','Allow the authenticated Principal to record an explicit fixed interval of temporary unavailability.',
      'canonicalOwner','atlas.principal_capacity_blocks',
      'boundary','No diagnosis, task, Owner Obligation, generic priority score, or Clock placement is created.'
    ),now()
  ),
  (
    'atlas.transition_principal_capacity_block_self_api_v1(p_capacity_block_id uuid, p_transition text, p_reason text)',
    'owner_admin_endpoint','verified','active',true,true,true,false,1,0,
    jsonb_build_object(
      'purpose','Cancel or reopen only the authenticated Principal own self-authored temporary capacity block while retaining lifecycle evidence.',
      'canonicalOwner','atlas.principal_capacity_blocks'
    ),now()
  ),
  (
    'atlas.principal_capacity_blocks_self_api_v1(p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_include_inactive boolean)',
    'app_endpoint','verified','active',true,true,true,false,1,0,
    jsonb_build_object(
      'purpose','Read the authenticated Principal self-authored temporary capacity blocks without turning list order into priority authority.'
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
