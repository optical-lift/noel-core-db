BEGIN;
-- HELD Gate 0: original historical farm readers, same signature/return semantics; source-enforced native full-disclosure authority.
-- Read-only pg_get_functiondef inventory; no change to existing grants, roles, RLS or original records.

-- Original historical function: farm_day_task_cards_v1
CREATE OR REPLACE FUNCTION atlas.farm_day_task_cards_v1(p_farm_id uuid, p_work_date date DEFAULT ((now() AT TIME ZONE 'America/Chicago'::text))::date)
 RETURNS SETOF atlas.v_task_cards
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
DECLARE
  v_role text;
BEGIN
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  v_role := atlas.current_farm_role(p_farm_id);
  IF v_role NOT IN ('owner', 'manager') THEN
    RAISE EXCEPTION 'Farm management membership required.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH active_memberships AS (
    SELECT fm.id, fm.user_id, nullif(lower(btrim(fm.worker_key)), '') AS worker_key
    FROM atlas.farm_memberships fm
    WHERE fm.farm_id = p_farm_id
      AND fm.active = true
  ), chosen AS (
    SELECT t.id AS task_id, 0 AS source_rank, t.due_date, t.priority, t.created_at
    FROM atlas.tasks t
    WHERE t.farm_id = p_farm_id
      AND t.task_scope = 'farm_operation'
      AND t.parent_task_id IS NULL
      AND nullif(t.metadata ->> 'parent_task_id', '') IS NULL
      AND nullif(t.metadata ->> 'parentTaskId', '') IS NULL
      AND lower(coalesce(t.metadata ->> 'is_child_task', 'false')) <> 'true'
      AND EXISTS (
        SELECT 1
        FROM active_memberships member
        WHERE t.assigned_membership_id = member.id
           OR t.assigned_user_id = member.user_id
           OR t.metadata ->> 'executor_membership_id' = member.id::text
           OR (
             member.worker_key IS NOT NULL
             AND lower(coalesce(
               nullif(t.metadata ->> 'executor_worker_key', ''),
               nullif(t.metadata ->> 'assignee_key', ''),
               nullif(t.metadata ->> 'assigned_to', '')
             )) = member.worker_key
           )
      )
      AND (
        (t.status IN ('open', 'blocked') AND t.due_date IS NOT NULL AND t.due_date <= p_work_date)
        OR (t.status = 'done' AND t.due_date = p_work_date)
      )

    UNION ALL

    SELECT row.task_id, 1, NULL::date, 'normal'::text, now()
    FROM active_memberships member
    CROSS JOIN LATERAL atlas.presented_work_rows_v1(p_farm_id, member.id, p_work_date) row
    WHERE row.presentation_state IN ('attention', 'presented')
  ), picked AS (
    SELECT DISTINCT ON (task_id) task_id, source_rank, due_date, priority, created_at
    FROM chosen
    ORDER BY task_id, source_rank, due_date NULLS LAST, priority, created_at
  )
  SELECT card.*
  FROM picked
  JOIN atlas.v_task_cards card ON card.task_id = picked.task_id
  ORDER BY
    CASE card.status WHEN 'blocked' THEN 0 WHEN 'open' THEN 1 WHEN 'done' THEN 2 ELSE 3 END,
    card.due_date NULLS LAST,
    card.priority,
    card.created_at,
    card.task_id;
END;
$function$;

-- Original historical function: home_task_cards_v2
CREATE OR REPLACE FUNCTION atlas.home_task_cards_v2(p_farm_id uuid, p_worker_key text, p_due_through date, p_done_date date)
 RETURNS SETOF atlas.v_task_cards
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_membership_id uuid;
  v_worker_key text;
  v_requested_worker_key text := nullif(lower(btrim(p_worker_key)), '');
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  v_membership_id := atlas.current_membership_id(p_farm_id);
  if v_membership_id is null then
    raise exception 'Active farm membership required.' using errcode = '42501';
  end if;

  select nullif(lower(btrim(membership.worker_key)), '')
  into v_worker_key
  from atlas.farm_memberships membership
  where membership.id = v_membership_id
    and membership.farm_id = p_farm_id
    and membership.active = true;

  if v_worker_key is null then
    raise exception 'Current Atlas worker identity was not found.' using errcode = 'P0002';
  end if;

  if v_requested_worker_key is not null
     and v_requested_worker_key is distinct from v_worker_key then
    raise exception 'The home reader may only load the signed-in membership.' using errcode = '42501';
  end if;

  return query
  select card.*
  from atlas.home_task_cards_for_membership_v3(
    p_farm_id,
    v_membership_id,
    p_due_through,
    p_done_date
  ) card;
end;
$function$;

-- Original historical function: seed_inventory_dashboard_v1
CREATE OR REPLACE FUNCTION atlas.seed_inventory_dashboard_v1(p_farm_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_role text;
  v_items jsonb;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  if auth.uid() is null or not atlas.is_farm_member(p_farm_id) then
    raise exception 'Farm membership is required to read seed inventory.' using errcode='42501';
  end if;
  v_role:=atlas.current_farm_role(p_farm_id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'seedLotId',sip.seed_lot_id,
    'stableKey',sip.stable_key,
    'lotLabel',sip.lot_label,
    'cropLabel',sip.crop_label,
    'variety',sip.variety,
    'supplier',sip.supplier,
    'storageLocation',sip.storage_location,
    'seedLotStatus',sip.seed_lot_status,
    'recordedReceiptQuantity',sip.recorded_receipt_quantity,
    'quantityUnit',sip.quantity_unit,
    'observationStatus',coalesce(sip.observation_status,'verification_required'),
    'verifiedOnHandQuantity',sip.verified_on_hand_quantity,
    'projectedOnHandQuantity',sip.projected_on_hand_quantity,
    'outstandingReservedQuantity',sip.outstanding_reserved_quantity,
    'projectedUnreservedQuantity',sip.projected_unreserved_quantity,
    'lastVerifiedAt',sip.last_verified_at,
    'lastObservedAt',sip.last_observed_at,
    'countTrusted',coalesce(sip.count_trusted,false),
    'lowStockThreshold',sip.low_stock_threshold,
    'atOrBelowLowStockThreshold',coalesce(sip.at_or_below_low_stock_threshold,false),
    'stateNote',sip.state_note,
    'rhythm',case when sip.rhythm_state_id is null then null else jsonb_build_object(
      'stateId',sip.rhythm_state_id,'state',sip.rhythm_state,
      'warningAt',sip.warning_at,'dueAt',sip.due_at,'failureAt',sip.failure_at,
      'currentTaskId',coalesce(sip.rhythm_task_id,sip.state_task_id),
      'bindingActive',sip.binding_active
    ) end,
    'dependencies',coalesce((
      select jsonb_agg(jsonb_build_object(
        'allocationId',sac.allocation_id,
        'productionLotId',sac.production_lot_id,
        'productionLotLabel',sac.production_lot_label,
        'plannedSowDate',sac.planned_sow_date,
        'allocatedQuantity',sac.allocated_quantity,
        'outstandingQuantity',sac.outstanding_quantity,
        'coveredByTrustedInventory',sac.covered_by_trusted_inventory,
        'blockingReason',sac.blocking_reason
      ) order by sac.planned_sow_date nulls last,sac.allocation_id)
      from atlas.seed_allocation_coverage_v1 sac where sac.seed_lot_id=sip.seed_lot_id
    ),'[]'::jsonb),
    'eventCount',(select count(*) from atlas.seed_inventory_events sie where sie.seed_lot_id=sip.seed_lot_id)
  ) order by sip.crop_label,sip.variety,sip.lot_label),'[]'::jsonb)
  into v_items
  from atlas.seed_inventory_position_v1 sip
  where sip.farm_id=p_farm_id and sip.seed_lot_status<>'closed';

  return jsonb_build_object(
    'contractVersion','seed_inventory_dashboard_v1',
    'farmId',p_farm_id,
    'canManage',v_role='owner',
    'items',v_items
  );
end;
$function$;

-- Original historical function: task_cards_v1
CREATE OR REPLACE FUNCTION atlas.task_cards_v1(p_farm_id uuid, p_task_id uuid DEFAULT NULL::uuid)
 RETURNS SETOF atlas.v_task_cards
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_role text;
  v_membership_id uuid;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  v_role := atlas.current_farm_role(p_farm_id);
  if v_role is null then
    raise exception 'Active farm membership required.' using errcode = '42501';
  end if;

  v_membership_id := atlas.current_membership_id(p_farm_id);

  return query
  select cards.*
  from atlas.v_task_cards cards
  join atlas.tasks task on task.id = cards.task_id
  where task.farm_id = p_farm_id
    and task.status <> 'archived'
    and (v_role <> 'farm_hand' or p_task_id is not null or task.status <> 'blocked')
    and (p_task_id is null or task.id = p_task_id)
    and (
      (v_role = 'owner' and task.visibility_scope in ('owner', 'management', 'assigned_worker', 'farm_shared'))
      or (v_role = 'manager' and task.visibility_scope in ('management', 'assigned_worker', 'farm_shared'))
      or (
        v_role = 'farm_hand'
        and (
          (task.visibility_scope = 'assigned_worker' and task.assigned_membership_id = v_membership_id)
          or task.visibility_scope = 'farm_shared'
        )
      )
    )
  order by cards.due_date nulls last, cards.created_at;
end;
$function$;

-- Original historical function: tending_task_context_v1
CREATE OR REPLACE FUNCTION atlas.tending_task_context_v1(p_farm_id uuid, p_task_id uuid, p_worker_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_role text;
  v_membership_id uuid;
  v_worker_key text;
  v_requested_worker_key text := nullif(lower(btrim(p_worker_key)),'');
  v_row atlas.tending_task_track_v1%rowtype;
  v_gates jsonb;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  v_role := atlas.current_farm_role(p_farm_id);
  v_membership_id := atlas.current_membership_id(p_farm_id);
  if v_role is null or v_membership_id is null then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  select nullif(lower(btrim(fm.worker_key)),'') into v_worker_key from atlas.farm_memberships fm where fm.id=v_membership_id and fm.farm_id=p_farm_id and fm.active=true;
  if v_worker_key is null then raise exception 'Current Atlas worker identity was not found.' using errcode='P0002'; end if;
  if v_requested_worker_key is not null and v_requested_worker_key is distinct from v_worker_key then raise exception 'Tending may only load the signed-in membership.' using errcode='42501'; end if;

  select x.* into v_row
  from atlas.tending_task_track_v1 x
  where x.farm_id=p_farm_id and x.task_id=p_task_id and x.task_status<>'archived'
    and (
      x.visibility_scope='farm_shared'
      or (x.visibility_scope='assigned_worker' and x.assigned_membership_id=v_membership_id)
      or (v_role='owner' and x.visibility_scope='owner' and (x.assigned_membership_id is null or x.assigned_membership_id=v_membership_id))
    )
  limit 1;
  if v_row.task_id is null then raise exception 'Tending task context not found.' using errcode='P0002'; end if;

  v_gates := atlas.tending_gates_v1(v_row.object_id,v_row.crop_cycle_id,v_row.task_id,v_row.expected_harvest_watch_start);
  return jsonb_build_object(
    'miniGamesEnabled',false,
    'bed',atlas.tending_card_json_v1(v_row.task_id,v_gates,v_row.task_status='open' and v_row.released_at is not null)
  );
end;
$function$;

-- Original historical function: tending_task_context_v2
CREATE OR REPLACE FUNCTION atlas.tending_task_context_v2(p_farm_id uuid, p_task_id uuid, p_object_key text, p_worker_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare v_role text; v_membership_id uuid; v_worker_key text; v_requested_worker_key text:=nullif(lower(btrim(p_worker_key)),''); v_row atlas.tending_task_track_v1%rowtype; v_gates jsonb;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  v_role:=atlas.current_farm_role(p_farm_id); v_membership_id:=atlas.current_membership_id(p_farm_id);
  if v_role is null or v_membership_id is null then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  select nullif(lower(btrim(fm.worker_key)),'') into v_worker_key from atlas.farm_memberships fm where fm.id=v_membership_id and fm.farm_id=p_farm_id and fm.active=true;
  if v_worker_key is null then raise exception 'Current Atlas worker identity was not found.' using errcode='P0002'; end if;
  if v_requested_worker_key is not null and v_requested_worker_key is distinct from v_worker_key then raise exception 'Tending may only load the signed-in membership.' using errcode='42501'; end if;
  select x.* into v_row from atlas.tending_task_track_v1 x where x.farm_id=p_farm_id and x.task_id=p_task_id and x.object_key=p_object_key and x.task_status<>'archived' and (x.visibility_scope='farm_shared' or (x.visibility_scope='assigned_worker' and x.assigned_membership_id=v_membership_id) or (v_role='owner' and x.visibility_scope='owner' and (x.assigned_membership_id is null or x.assigned_membership_id=v_membership_id))) limit 1;
  if v_row.task_id is null then raise exception 'Tending task context not found.' using errcode='P0002'; end if;
  v_gates:=atlas.tending_gates_v1(v_row.object_id,v_row.crop_cycle_id,v_row.task_id,case when atlas.tending_unlock_label_v1(v_row.unlock_text,v_row.task_metadata,null) is not null and v_row.lifecycle_status<>'planned' and v_row.gate_key in ('weed','clear') then null else v_row.expected_harvest_watch_start end);
  return jsonb_build_object('miniGamesEnabled',false,'bed',atlas.tending_card_json_v2(v_row.task_id,v_row.object_id,v_gates,v_row.task_status='open' and v_row.released_at is not null));
end;
$function$;

-- Original historical function: worker_day_state_transition_cards_v1
CREATE OR REPLACE FUNCTION atlas.worker_day_state_transition_cards_v1(p_farm_id uuid, p_membership_id uuid, p_service_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_target atlas.farm_memberships%rowtype;
  v_is_management boolean := false;
  v_cards jsonb := '[]'::jsonb;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;
  if p_service_date is null then
    raise exception 'A service date is required.' using errcode='22023';
  end if;

  select * into v_target
  from atlas.farm_memberships membership
  where membership.id=p_membership_id
    and membership.farm_id=p_farm_id
    and membership.active=true;

  if v_target.id is null then
    raise exception 'Active target membership required.' using errcode='42501';
  end if;

  v_is_management := atlas.is_farm_manager_or_owner(p_farm_id);
  if v_target.user_id is distinct from auth.uid() and not v_is_management then
    raise exception 'Only the routed worker or farm management may read this Worker Day transition packet.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(
    atlas.worker_state_transition_card_v1(p_farm_id,p_membership_id,placement.task_id,p_service_date)
    order by case placement.day_window when 'morning' then 0 when 'afternoon' then 1 when 'evening' then 2 else 3 end,
             placement.sort_order,placement.created_at
  ),'[]'::jsonb)
  into v_cards
  from atlas.worker_day_task_placements placement
  where placement.farm_id=p_farm_id
    and placement.membership_id=p_membership_id
    and placement.service_date=p_service_date
    and placement.state='placed';

  return jsonb_build_object(
    'contractVersion','worker_day_state_transition_cards_v1',
    'farmId',p_farm_id,
    'membershipId',p_membership_id,
    'serviceDate',p_service_date,
    'cards',v_cards,
    'integrationState','diagnostic_parallel_to_legacy_worker_day',
    'principle','Phase 5 diagnoses routed work through Reality Expression before this contract is allowed to replace the legacy Worker Day card path.'
  );
end;
$function$;

-- Original historical function: worker_future_day_projection_source_v1
CREATE OR REPLACE FUNCTION atlas.worker_future_day_projection_source_v1(p_farm_id uuid, p_membership_id uuid, p_start_date date, p_end_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_paid_target integer;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  if v_user_id is null then
    raise exception 'Authenticated user required.' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from atlas.farm_memberships fm
    where fm.user_id = v_user_id
      and fm.farm_id = p_farm_id
      and fm.active = true
  ) then
    raise exception 'Active farm membership required.' using errcode = '42501';
  end if;

  select fm.role
    into v_role
  from atlas.farm_memberships fm
  where fm.id = p_membership_id
    and fm.farm_id = p_farm_id
    and fm.active = true
  limit 1;

  if v_role is null then
    raise exception 'Target membership is not active for this farm.' using errcode = '42501';
  end if;

  select mcs.regular_target_minutes
    into v_paid_target
  from atlas.member_capacity_settings mcs
  where mcs.farm_id = p_farm_id
    and mcs.membership_id = p_membership_id
    and mcs.active = true
  limit 1;

  v_paid_target := coalesce(
    v_paid_target,
    case
      when v_role = 'farm_hand' then 420
      when v_role = 'manager' then 360
      else 480
    end
  );

  return jsonb_build_object(
    'role', v_role,
    'paidTargetMinutes', v_paid_target,
    'projection', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', o.id,
          'plannedDate', o.planned_date,
          'sourceKind', o.source_kind,
          'sourceId', o.source_id,
          'title', o.title,
          'planState', o.plan_state,
          'environment', o.environment,
          'expectedActiveMinutes', o.expected_active_minutes,
          'reason', o.reason,
          'planOrder', o.plan_order
        )
        order by o.planned_date, o.plan_order, o.id
      )
      from atlas.worker_week_projection o
      where o.farm_id = p_farm_id
        and o.membership_id = p_membership_id
        and o.planned_date between p_start_date and p_end_date
    ), '[]'::jsonb),
    'weedQueue', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'position', qi.position,
          'state', qi.state,
          'plannedOccurrenceId', qi.planned_occurrence_id,
          'occurrenceState', pwo.state,
          'title', pwo.title,
          'taskPayload', pwo.task_payload
        )
        order by qi.position
      )
      from atlas.task_release_queue_items qi
      left join atlas.planned_work_occurrences pwo on pwo.id = qi.planned_occurrence_id
      where qi.farm_id = p_farm_id
        and qi.queue_key = 'anna_weeding_rotation'
    ), '[]'::jsonb)
  );
end;
$function$;
COMMIT;
