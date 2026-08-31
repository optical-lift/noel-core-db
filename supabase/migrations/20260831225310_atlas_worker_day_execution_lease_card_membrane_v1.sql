BEGIN;

-- Lease-mode card membrane v1.
-- Legacy operational-card continuity deliberately includes completed tasks from
-- the same service date. That history remains useful outside lease-mode, but it
-- cannot expand the worker's current handed-work surface. In lease-mode the
-- requested task IDs come from the lease feed and are the exact card boundary.

create or replace function atlas.worker_day_operational_task_cards_v3(
  p_farm_id uuid,
  p_membership_id uuid,
  p_service_date date,
  p_task_ids uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_cards jsonb:='[]'::jsonb;
  v_result jsonb:='[]'::jsonb;
  v_card jsonb;
  v_task_id uuid;
  v_readiness jsonb;
  v_status text;
  v_transition_card jsonb;
  v_result_state text;
  v_metadata jsonb;
  v_lease jsonb;
  v_keep boolean;
  v_live_lease_mode boolean:=false;
begin
  v_live_lease_mode:=coalesce((atlas.worker_day_live_execution_lease_packet_v1(
    p_farm_id,p_membership_id,p_service_date
  )->>'liveLeaseMode')::boolean,false);

  v_cards:=atlas.worker_day_operational_task_cards_v2(p_farm_id,p_membership_id,p_service_date,p_task_ids);
  for v_card in select value from jsonb_array_elements(v_cards)
  loop
    v_task_id:=nullif(v_card->>'task_id','')::uuid;

    -- Once a human day has crossed the lease boundary, current actionable card
    -- membership is exact. Same-day completed continuity remains available to
    -- legacy/history readers but cannot leak into this Worker Day card packet.
    if v_live_lease_mode
       and not (v_task_id=any(coalesce(p_task_ids,array[]::uuid[]))) then
      continue;
    end if;

    v_status:=coalesce(v_card->>'status','');
    v_readiness:=atlas.task_execution_readiness_v1(v_task_id);
    v_lease:=atlas.worker_task_live_execution_lease_v1(p_farm_id,p_membership_id,v_task_id,p_service_date);
    v_keep:=v_status='done'
      or coalesce((v_readiness->>'executionReady')::boolean,false)
      or (coalesce((v_lease->>'liveLeaseMode')::boolean,false)
          and v_lease->>'leaseId' is not null
          and coalesce(v_lease->>'leaseState','') not in ('withdrawn','expired'));

    if v_keep then
      v_transition_card:=case when v_status='done' then null else atlas.worker_state_transition_card_v2(p_farm_id,p_membership_id,v_task_id,p_service_date) end;
      v_result_state:=coalesce(v_transition_card#>>'{resultReturn,state}','');
      v_metadata:=coalesce(v_card->'metadata','{}'::jsonb)||jsonb_build_object(
        'quick_complete_allowed',v_result_state='quick_complete_v1_available',
        'structured_result_required',v_result_state in ('structured_result_v1_available','structured_result_adapter_required'),
        'worker_result_return_state',nullif(v_result_state,''),
        'worker_transition_state',nullif(v_transition_card#>>'{transition,state}',''),
        'worker_result_authority','worker_state_transition_card_v2',
        'execution_lease_id',v_lease->>'leaseId',
        'execution_lease_state',v_lease->>'leaseState',
        'execution_lease_actionable',coalesce((v_lease->>'actionable')::boolean,false)
      );
      v_result:=v_result||jsonb_build_array(v_card||jsonb_build_object(
        'metadata',v_metadata,
        'worker_transition_card',v_transition_card,
        'resource_requirements',atlas.task_resource_requirement_packet_v1(v_task_id),
        'execution_readiness',v_readiness,
        'state_consequence_gate',v_readiness->'stateConsequenceGate',
        'preparation_required',coalesce((v_readiness->>'preparationRequired')::boolean,false),
        'execution_lease',v_lease
      ));
    end if;
  end loop;
  return v_result;
end;
$$;

comment on function atlas.worker_day_operational_task_cards_v3(uuid,uuid,date,uuid[]) is
  'Lease-aware operational card membrane. In live lease-mode, card membership is exactly the requested lease-feed task set; legacy same-day completed continuity cannot expand the current human handoff.';

-- Preserve the lease-feed order all the way through taskCards. This makes the
-- bundle a stable representation of one handed day rather than two independently
-- ordered collections that clients must guess how to reconcile.
create or replace function atlas.worker_self_day_bundle_api_v2(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_timezone text:='America/Chicago';
  v_today date;
  v_day_start timestamptz;
  v_plan jsonb;
  v_task_ids uuid[]:=array[]::uuid[];
  v_cards jsonb:='[]'::jsonb;
  v_safe_cards jsonb:='[]'::jsonb;
  v_packet jsonb;
  v_reconciliation jsonb;
begin
  if auth.uid() is null then raise exception 'Authenticated user required.' using errcode='42501'; end if;
  if p_day is null then raise exception 'A worker day is required.' using errcode='22023'; end if;
  if not exists(
    select 1 from atlas.farm_memberships m
    where m.id=p_membership_id
      and m.farm_id=p_farm_id
      and m.user_id=auth.uid()
      and m.active=true
      and m.role='farm_hand'
  ) then
    raise exception 'The Farm Hand Worker Day bundle may only be read by that active Farm Hand.' using errcode='42501';
  end if;

  select coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
    into v_timezone
  from atlas.farms f
  where f.id=p_farm_id;
  v_today:=(now() at time zone coalesce(v_timezone,'America/Chicago'))::date;
  if p_day<>v_today then
    return atlas.worker_self_day_bundle_api_v1(p_farm_id,p_membership_id,p_day);
  end if;
  v_day_start:=p_day::timestamp at time zone v_timezone;

  perform atlas.expire_worker_execution_leases_before_v1(p_farm_id,p_membership_id,v_day_start,auth.uid());
  v_packet:=atlas.worker_day_live_execution_lease_packet_v1(p_farm_id,p_membership_id,p_day);
  if not coalesce((v_packet->>'liveLeaseMode')::boolean,false) then
    v_packet:=atlas.open_worker_day_execution_leases_v1(
      p_farm_id,p_membership_id,p_day,'Worker opened current Worker Day.',auth.uid()
    );
  end if;
  v_reconciliation:=atlas.reconcile_worker_day_execution_leases_v1(p_farm_id,p_membership_id,p_day,auth.uid());
  v_plan:=atlas.worker_day_feed_plan_live_v1(p_farm_id,p_membership_id,p_day)
    ||jsonb_build_object('clockTimeline',null,'suggestions','[]'::jsonb);

  select coalesce(array_agg(d.task_id order by d.first_ord),array[]::uuid[])
    into v_task_ids
  from (
    select x.task_id,min(x.ord)::bigint first_ord
    from (
      select nullif(row->>'taskId','')::uuid task_id,ord
      from jsonb_array_elements(
        coalesce(v_plan->'realWork','[]'::jsonb)||coalesce(v_plan->'automaticWork','[]'::jsonb)
      ) with ordinality a(row,ord)
    ) x
    where x.task_id is not null
    group by x.task_id
  ) d;

  v_cards:=atlas.worker_day_operational_task_cards_v3(p_farm_id,p_membership_id,p_day,v_task_ids);
  select coalesce(
    jsonb_agg(cards.card-'move_context' order by array_position(v_task_ids,nullif(cards.card->>'task_id','')::uuid)),
    '[]'::jsonb
  ) into v_safe_cards
  from jsonb_array_elements(v_cards) as cards(card);

  return jsonb_build_object(
    'contractVersion','worker_self_day_bundle_execution_lease_v1',
    'plan',v_plan,
    'taskCards',v_safe_cards,
    'executionLeaseReconciliation',v_reconciliation,
    'trustBoundary',jsonb_build_object(
      'dayOpeningCreatesLeases',true,
      'feedReadsLeases',true,
      'taskCardsMatchLeaseFeed',true,
      'taskCardOrderMatchesLeaseFeed',true,
      'doneAuthorityReadsSameLease',true,
      'interruptedLeaseRemainsVisible',true,
      'priorDayLeasesExpireBeforeNewDay',true
    )
  );
end;
$$;

comment on function atlas.worker_self_day_bundle_api_v2(uuid,uuid,date) is
  'Current-day Farm Hand bundle. Live lease-mode is one coherent human handoff: feed membership, task-card membership/order, and action authority all derive from the same execution lease set.';

COMMIT;
