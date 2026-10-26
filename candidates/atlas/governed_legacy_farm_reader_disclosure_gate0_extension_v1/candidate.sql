BEGIN;
-- Gate 0 continuation. Existing legacy membership-only calls can expose
-- other beds, counts, crop placements, history and even absent-auth aggregate
-- data. Reuse the same stricter signed native governing Ledger gate authored
-- in governed_legacy_farm_reader_disclosure_v1; DO NOT silently retrofit
-- broad worker membership to a source-specific Person grant.
-- All definitions below are source-preserving except an early fail-closed
-- permission check. Actual signed worker access must use exact original
-- Work/Subject source permissions instead.
CREATE OR REPLACE FUNCTION atlas.bed_components_state_v1(p_bed_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_bed atlas.growing_objects%rowtype;
  v_role text;
  v_result jsonb;
begin
  select * into v_bed from atlas.growing_objects where id=p_bed_id;
  if v_bed.id is null then raise exception 'Source unavailable to this Person.' using errcode='42501'; end if;

  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(v_bed.farm_id);

  v_role:=atlas.current_farm_role(v_bed.farm_id);
  if not atlas.is_farm_owner(v_bed.farm_id) and coalesce(v_role,'') not in ('farm_hand','manager') then
    raise exception 'Bed components are not available to the signed-in farm member.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'componentId',c.id,
    'componentKey',c.stable_key,
    'componentLabel',c.label,
    'componentKind',coalesce(c.metadata->>'component_kind','component'),
    'positionLabel',r.position_label,
    'mapSide',nullif(r.metadata->>'mapSide',''),
    'relationshipMetadata',r.metadata,
    'occupancyState',coalesce(o.occ->>'occupancyState','empty'),
    'availableForPlanting',coalesce((o.occ->>'availableForPlanting')::boolean,true),
    'occupancyGroups',coalesce(o.occ->'groups','[]'::jsonb)
  ) order by r.sort_order,c.label),'[]'::jsonb)
  into v_result
  from atlas.growing_object_relationships r
  join atlas.growing_objects c on c.id=r.child_object_id
  left join lateral (select atlas.object_crop_occupancy_v1(c.id) as occ) o on true
  where r.parent_object_id=v_bed.id
    and r.relationship_type='contains'
    and c.object_type='component';

  return jsonb_build_object(
    'bedId',v_bed.id,
    'bedKey',v_bed.stable_key,
    'bedLabel',v_bed.label,
    'components',coalesce(v_result,'[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION atlas.farm_continuity_audit_v1(p_farm_id uuid, p_as_of_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_day date := coalesce(p_as_of_date,(now() at time zone 'America/Chicago')::date);
  v_timezone text := 'America/Chicago';
  v_active_cycles integer := 0;
  v_current_covered integer := 0;
  v_future_covered integer := 0;
  v_background_observations integer := 0;
  v_terminal_count integer := 0;
  v_hardening_count integer := 0;
  v_closure_count integer := 0;
  v_propagation_gap_count integer := 0;
  v_overdue_emergence_count integer := 0;
  v_destination_count integer := 0;
  v_seed_readiness_count integer := 0;
  v_field_continuity_count integer := 0;
  v_reservation_gap_count integer := 0;
  v_high_count integer := 0;
  v_medium_count integer := 0;
  v_terminal_items jsonb := '[]'::jsonb;
  v_hardening_items jsonb := '[]'::jsonb;
  v_closure_items jsonb := '[]'::jsonb;
  v_propagation_items jsonb := '[]'::jsonb;
  v_overdue_emergence_items jsonb := '[]'::jsonb;
  v_destination_items jsonb := '[]'::jsonb;
  v_seed_readiness_items jsonb := '[]'::jsonb;
  v_field_continuity_items jsonb := '[]'::jsonb;
  v_reservation_gap_items jsonb := '[]'::jsonb;
  v_state text;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  if p_farm_id is null then
    raise exception 'A farm is required.' using errcode='22023';
  end if;

  if auth.uid() is not null and not atlas.is_farm_member(p_farm_id) then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;

  select coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
    into v_timezone
  from atlas.farms f
  where f.id=p_farm_id;

  with active_cycles as materialized (
    select
      cc.*,
      z.stable_key as zone_key,
      go.label as object_label
    from atlas.crop_cycles cc
    left join atlas.growing_objects go on go.id=cc.object_id
    left join atlas.zones z on z.id=go.zone_id
    where cc.farm_id=p_farm_id
      and coalesce(cc.lifecycle_status,'active')='active'
  ), farm_tasks as materialized (
    select t.id,t.status,t.metadata
    from atlas.tasks t
    where t.farm_id=p_farm_id
  ), task_cycle_links as materialized (
    select distinct ft.id as task_id,tc.crop_cycle_id
    from farm_tasks ft
    join atlas.task_crop_cycles tc on tc.task_id=ft.id
    union
    select distinct ft.id,c.id
    from farm_tasks ft
    join active_cycles c on ft.metadata->>'crop_cycle_id'=c.id::text
    union
    select distinct ft.id,c.id
    from farm_tasks ft
    join active_cycles c on coalesce(ft.metadata->'crop_cycle_ids','[]'::jsonb) ? c.id::text
  ), current_cycles as (
    select distinct l.crop_cycle_id
    from task_cycle_links l
    join farm_tasks t on t.id=l.task_id
    where t.status in ('open','blocked')
  ), future_cycles as (
    select distinct o.source_id as crop_cycle_id
    from atlas.planned_work_occurrences o
    join active_cycles c on c.id=o.source_id
    where o.farm_id=p_farm_id
      and o.state in ('planned','eligible','released')
      and o.source_kind='crop_cycle'
    union
    select distinct l.crop_cycle_id
    from atlas.planned_work_occurrences o
    join task_cycle_links l on l.task_id=o.released_task_id
    where o.farm_id=p_farm_id
      and o.state in ('planned','eligible','released')
  ), coverage as (
    select c.id,
      (cur.crop_cycle_id is not null) as has_current_task,
      (fut.crop_cycle_id is not null) as has_future_occurrence
    from active_cycles c
    left join current_cycles cur on cur.crop_cycle_id=c.id
    left join future_cycles fut on fut.crop_cycle_id=c.id
  ), classified as (
    select
      c.*,
      cov.has_current_task,
      cov.has_future_occurrence,
      case
        when c.cycle_state in ('failed','failed_germination','abandoned','absent','archived') then 'terminal_lifecycle_mismatch'
        when c.zone_key='grow_room' and c.cycle_state='hardening_off'
          and not cov.has_current_task and not cov.has_future_occurrence then 'hardening_off_uncovered'
        when c.zone_key='grow_room' and c.cycle_state in ('cleanup_needed','declining')
          and not cov.has_current_task and not cov.has_future_occurrence then 'closure_uncovered'
        when c.zone_key='grow_room' and c.cycle_state='sown_awaiting_emergence'
          and c.expected_germination_end is not null and c.expected_germination_end < v_day
          and not cov.has_current_task and not cov.has_future_occurrence then 'overdue_emergence_uncovered'
        when c.zone_key='grow_room' and c.cycle_state in ('germinated','seedling_care','propagation')
          and not cov.has_current_task and not cov.has_future_occurrence then 'propagation_transition_uncovered'
        when cov.has_current_task then 'current_work_covered'
        when cov.has_future_occurrence then 'future_gated_covered'
        else 'continuity_observation'
      end as continuity_state
    from active_cycles c
    join coverage cov using(id)
  )
  select
    count(*)::integer,
    count(*) filter(where continuity_state='current_work_covered')::integer,
    count(*) filter(where continuity_state='future_gated_covered')::integer,
    count(*) filter(where continuity_state='continuity_observation')::integer,
    count(*) filter(where continuity_state='terminal_lifecycle_mismatch')::integer,
    count(*) filter(where continuity_state='hardening_off_uncovered')::integer,
    count(*) filter(where continuity_state='closure_uncovered')::integer,
    count(*) filter(where continuity_state='propagation_transition_uncovered')::integer,
    count(*) filter(where continuity_state='overdue_emergence_uncovered')::integer,
    coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'cycleId',id,'cropLabel',crop_label,'variety',variety,'cycleState',cycle_state,
      'lifecycleStatus',lifecycle_status,'zoneKey',zone_key,'objectLabel',object_label,
      'repairOwner','farm_operations_data','reason','Cycle remains lifecycle-active while its state is terminal.'
    )) order by crop_label,variety nulls last) filter(where continuity_state='terminal_lifecycle_mismatch'),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'cycleId',id,'cropLabel',crop_label,'variety',variety,'cycleState',cycle_state,
      'zoneKey',zone_key,'objectLabel',object_label,'repairOwner','farm_operations_management',
      'reason','Hardening-off material has no current task or future/gated occurrence covering its next transition.'
    )) order by crop_label,variety nulls last) filter(where continuity_state='hardening_off_uncovered'),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'cycleId',id,'cropLabel',crop_label,'variety',variety,'cycleState',cycle_state,
      'zoneKey',zone_key,'objectLabel',object_label,'repairOwner','farm_operations',
      'reason','Closure/cleanup state has no current task or future/gated occurrence.'
    )) order by crop_label,variety nulls last) filter(where continuity_state='closure_uncovered'),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'cycleId',id,'cropLabel',crop_label,'variety',variety,'cycleState',cycle_state,
      'zoneKey',zone_key,'objectLabel',object_label,'expectedGerminationEnd',expected_germination_end,
      'repairOwner','farm_operations_propagation','reason','Living Grow Room material is in a transition-sensitive state with no current task or future/gated occurrence.'
    )) order by crop_label,variety nulls last) filter(where continuity_state='propagation_transition_uncovered'),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'cycleId',id,'cropLabel',crop_label,'variety',variety,'cycleState',cycle_state,
      'zoneKey',zone_key,'objectLabel',object_label,'expectedGerminationEnd',expected_germination_end,
      'repairOwner','farm_operations_propagation','reason','Expected germination window has passed with no current task or future/gated occurrence.'
    )) order by crop_label,variety nulls last) filter(where continuity_state='overdue_emergence_uncovered'),'[]'::jsonb)
  into
    v_active_cycles,v_current_covered,v_future_covered,v_background_observations,
    v_terminal_count,v_hardening_count,v_closure_count,v_propagation_gap_count,v_overdue_emergence_count,
    v_terminal_items,v_hardening_items,v_closure_items,v_propagation_items,v_overdue_emergence_items
  from classified;

  select
    count(*)::integer,
    coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'taskId',t.id,'title',t.title,'dueDate',t.due_date,
      'destinationReadiness',atlas.task_execution_destination_readiness_v1(t.id),
      'protectedFarmMinimum',atlas.task_protected_farm_minimum_v1(t.id,v_day),
      'repairOwner','farm_operations_management',
      'reason','Final transplant execution is blocked until a canonical destination is resolved.'
    )) order by t.due_date nulls last,t.title),'[]'::jsonb)
  into v_destination_count,v_destination_items
  from atlas.tasks t
  join atlas.zones z on z.id=t.zone_id
  where t.farm_id=p_farm_id
    and t.status in ('open','blocked')
    and t.task_type='transplanting'
    and z.stable_key='grow_room'
    and coalesce((atlas.task_execution_destination_readiness_v1(t.id)->>'ready')::boolean,false)=false;

  select
    count(*) filter(where coalesce(all_seed_allocations_ready,false)=false and outstanding_allocated_quantity>0)::integer,
    coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'productionLotId',production_lot_id,'lotLabel',lot_label,'plannedSowDate',planned_sow_date,
      'outstandingAllocatedQuantity',outstanding_allocated_quantity,'trustedCoveredQuantity',trusted_covered_quantity,
      'blockingReason',blocking_reason,'repairOwner','production_inventory',
      'reason','Future production lot has allocated seed demand without trusted inventory coverage.'
    )) order by planned_sow_date,lot_label)
      filter(where coalesce(all_seed_allocations_ready,false)=false and outstanding_allocated_quantity>0),'[]'::jsonb)
  into v_seed_readiness_count,v_seed_readiness_items
  from atlas.production_seed_readiness_v1
  where farm_id=p_farm_id;

  select
    count(*) filter(where audit_status<>'pass')::integer,
    coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'productionLotId',production_lot_id,'lotLabel',lot_label,'currentStage',current_stage,
      'lifecycleStatus',lifecycle_status,'auditStatus',audit_status,
      'missingFieldStandCount',missing_field_stand_count,
      'missingFieldCareStateCount',missing_field_care_state_count,
      'missingCarePolicyCount',missing_care_policy_count,
      'harvestGateStatus',harvest_gate_status,
      'repairOwner','production_systems'
    )) order by lot_label) filter(where audit_status<>'pass'),'[]'::jsonb)
  into v_field_continuity_count,v_field_continuity_items
  from atlas.production_field_continuity_audit_v1
  where farm_id=p_farm_id;

  select
    count(*)::integer,
    coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'reservationId',r.id,'productionLotId',r.production_lot_id,'windowStart',r.window_start,'windowEnd',r.window_end,
      'capacityPoolId',r.capacity_pool_id,'quantityReserved',r.quantity_reserved,'unit',r.unit,
      'repairOwner','production_systems','reason','Active future capacity reservation has no active production-lot lifecycle path.'
    )) order by r.window_start),'[]'::jsonb)
  into v_reservation_gap_count,v_reservation_gap_items
  from atlas.production_capacity_reservations r
  left join atlas.production_lots pl on pl.id=r.production_lot_id
  where r.farm_id=p_farm_id
    and coalesce(r.reservation_status,'active') not in ('released','cancelled','expired')
    and (pl.id is null or coalesce(pl.lifecycle_status,'') in ('cancelled','failed','complete','completed','archived'));

  v_high_count := v_terminal_count + v_hardening_count + v_closure_count + v_overdue_emergence_count + v_destination_count;
  v_medium_count := v_propagation_gap_count + v_seed_readiness_count + v_field_continuity_count + v_reservation_gap_count;

  v_state := case
    when v_high_count>0 then 'high_priority_continuity_attention'
    when v_medium_count>0 then 'continuity_attention'
    else 'no_actionable_continuity_gap_detected'
  end;

  return jsonb_build_object(
    'contractVersion','farm_continuity_audit_v1',
    'farmId',p_farm_id,
    'asOfDate',v_day,
    'timezone',v_timezone,
    'state',v_state,
    'farmTruthMutated',false,
    'principalEscalationCreated',false,
    'principalBoundary','Issues remain contained in Farm Operations unless an explicit escalation threshold is crossed.',
    'summary',jsonb_build_object(
      'activeCropCycleCount',v_active_cycles,
      'currentWorkCoveredCount',v_current_covered,
      'futureGatedCoveredCount',v_future_covered,
      'backgroundContinuityObservationCount',v_background_observations,
      'highPriorityIssueCount',v_high_count,
      'mediumPriorityIssueCount',v_medium_count,
      'terminalLifecycleMismatchCount',v_terminal_count,
      'hardeningOffUncoveredCount',v_hardening_count,
      'closureUncoveredCount',v_closure_count,
      'overdueEmergenceUncoveredCount',v_overdue_emergence_count,
      'propagationTransitionUncoveredCount',v_propagation_gap_count,
      'transplantDestinationUnresolvedCount',v_destination_count,
      'futureSeedReadinessGapCount',v_seed_readiness_count,
      'productionFieldContinuityIssueCount',v_field_continuity_count,
      'futureReservationReleasePathGapCount',v_reservation_gap_count
    ),
    'issueFamilies',jsonb_build_array(
      jsonb_build_object('key','terminal_lifecycle_mismatch','severity','high','count',v_terminal_count,'items',v_terminal_items),
      jsonb_build_object('key','hardening_off_uncovered','severity','high','count',v_hardening_count,'items',v_hardening_items),
      jsonb_build_object('key','closure_uncovered','severity','high','count',v_closure_count,'items',v_closure_items),
      jsonb_build_object('key','overdue_emergence_uncovered','severity','high','count',v_overdue_emergence_count,'items',v_overdue_emergence_items),
      jsonb_build_object('key','transplant_destination_unresolved','severity','high','count',v_destination_count,'items',v_destination_items),
      jsonb_build_object('key','propagation_transition_uncovered','severity','medium','count',v_propagation_gap_count,'items',v_propagation_items),
      jsonb_build_object('key','future_seed_readiness_gap','severity','medium','count',v_seed_readiness_count,'items',v_seed_readiness_items),
      jsonb_build_object('key','production_field_continuity','severity','medium','count',v_field_continuity_count,'items',v_field_continuity_items),
      jsonb_build_object('key','future_reservation_release_path_gap','severity','medium','count',v_reservation_gap_count,'items',v_reservation_gap_items)
    ),
    'auditCoverage',jsonb_build_object(
      'livingCropNextState','active_current_and_legacy_crop_cycles',
      'propagationDestination','active_grow_room_transition_states_plus_task_destination_readiness',
      'futureSeedSourceInventory','production_seed_readiness_v1',
      'fieldProductionLotContinuity','production_field_continuity_audit_v1',
      'futureCapacityReservationReleasePath','audited',
      'targetWithoutSufficientLots','not_fully_auditable_yet',
      'lotWithoutSufficientLandOrLabor','not_fully_auditable_yet',
      'harvestEndToTermination','partial_until_harvest_lifecycle_and_legacy_cycles_are_fully_unified'
    ),
    'backgroundContinuityObservationPolicy','Stable/background cycles without a direct task or occurrence are counted separately and are not treated as immediate Worker Day or Principal alarms.'
  );
end;
$function$;

CREATE OR REPLACE FUNCTION atlas.farm_continuity_audit_v2(p_farm_id uuid, p_as_of_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_base jsonb;
  v_harvest_gap_count integer:=0;
  v_reforecast_gap_count integer:=0;
  v_harvest_items jsonb:='[]'::jsonb;
  v_reforecast_items jsonb:='[]'::jsonb;
  v_high integer:=0;
  v_medium integer:=0;
  v_state text;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  if p_farm_id is null then raise exception 'A farm is required.' using errcode='22023'; end if;
  if auth.uid() is not null and not atlas.is_farm_member(p_farm_id) then raise exception 'Active farm membership required.' using errcode='42501'; end if;

  v_base:=atlas.farm_continuity_audit_v1(p_farm_id,p_as_of_date);

  with complete_harvest as (
    select distinct on (e.production_lot_id) e.production_lot_id,e.id,e.event_date,e.metadata
    from atlas.production_lot_events e
    where e.farm_id=p_farm_id and e.event_type='harvest_recorded' and coalesce(e.metadata->>'harvest_action','')='complete'
    order by e.production_lot_id,e.event_date desc,e.created_at desc
  ), gaps as (
    select ch.*,pl.lot_label
    from complete_harvest ch
    join atlas.production_lots pl on pl.id=ch.production_lot_id
    where not exists(select 1 from atlas.production_lot_events x where x.production_lot_id=ch.production_lot_id and x.event_type in ('cleared','turnover_completed') and x.event_date>=ch.event_date)
      and not exists(
        select 1 from atlas.production_lot_tasks plt join atlas.tasks t on t.id=plt.task_id
        where plt.production_lot_id=ch.production_lot_id and plt.link_role in ('clear','termination_decision','turnover') and t.status in ('open','blocked')
      )
  )
  select count(*)::integer,
    coalesce(jsonb_agg(jsonb_build_object('productionLotId',production_lot_id,'lotLabel',lot_label,'completeHarvestEventId',id,'completeHarvestDate',event_date,'repairOwner','farm_operations_management','reason','Counted complete harvest has no clear, termination-decision, turnover task, or later clear/turnover actual.')),'[]'::jsonb)
  into v_harvest_gap_count,v_harvest_items from gaps;

  with relevant_events as (
    select e.id,e.production_lot_id,e.event_type,e.event_date,pl.lot_label
    from atlas.production_lot_events e join atlas.production_lots pl on pl.id=e.production_lot_id
    where e.farm_id=p_farm_id and e.event_type in (
      'sown','germinated','germination_failed','transplanted','established','establishment_failed',
      'harvest_readiness_confirmed','harvest_not_ready','harvest_recorded','cleared','turnover_completed','labor_actual',
      'water_care_completed','weed_care_completed','pinch_care_completed','support_care_completed','fertility_care_completed'
    )
  ), gaps as (
    select r.* from relevant_events r
    where not exists(select 1 from atlas.production_reforecast_events rf where rf.source_event_id=r.id and rf.reforecast_version='production_actual_reforecast_v1')
  )
  select count(*)::integer,
    coalesce(jsonb_agg(jsonb_build_object('productionLotId',production_lot_id,'lotLabel',lot_label,'sourceEventId',id,'eventType',event_type,'eventDate',event_date,'repairOwner','production_systems','reason','Actual production event is missing its downstream reforecast evidence record.') order by event_date,lot_label),'[]'::jsonb)
  into v_reforecast_gap_count,v_reforecast_items from gaps;

  v_high:=coalesce((v_base->'summary'->>'highPriorityIssueCount')::integer,0)+v_harvest_gap_count;
  v_medium:=coalesce((v_base->'summary'->>'mediumPriorityIssueCount')::integer,0)+v_reforecast_gap_count;
  v_state:=case when v_high>0 then 'high_priority_continuity_attention' when v_medium>0 then 'continuity_attention' else 'no_actionable_continuity_gap_detected' end;

  return v_base
    || jsonb_build_object(
      'contractVersion','farm_continuity_audit_v2',
      'state',v_state,
      'summary',(v_base->'summary')||jsonb_build_object(
        'highPriorityIssueCount',v_high,
        'mediumPriorityIssueCount',v_medium,
        'completeHarvestWithoutTerminationPathCount',v_harvest_gap_count,
        'actualEventWithoutReforecastCount',v_reforecast_gap_count
      ),
      'issueFamilies',(v_base->'issueFamilies')||jsonb_build_array(
        jsonb_build_object('key','complete_harvest_without_termination_path','severity','high','count',v_harvest_gap_count,'items',v_harvest_items),
        jsonb_build_object('key','actual_event_without_reforecast','severity','medium','count',v_reforecast_gap_count,'items',v_reforecast_items)
      ),
      'auditCoverage',(v_base->'auditCoverage')||jsonb_build_object(
        'harvestEndToTermination','production_lot_path_audited; legacy crop-cycle harvest path remains partial',
        'actualEventToReforecast','audited'
      )
    );
end;
$function$;

CREATE OR REPLACE FUNCTION atlas.farm_continuity_audit_v3(p_farm_id uuid, p_as_of_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_day date := coalesce(p_as_of_date,(now() at time zone 'America/Chicago')::date);
  v_base jsonb;
  v_no_next_count integer := 0;
  v_missing_destination_count integer := 0;
  v_overclaimed_count integer := 0;
  v_destination_collision_count integer := 0;
  v_labor_capacity_count integer := 0;
  v_result_without_continuation_count integer := 0;
  v_orphaned_expected_stage_count integer := 0;
  v_no_next_items jsonb := '[]'::jsonb;
  v_missing_destination_items jsonb := '[]'::jsonb;
  v_overclaimed_items jsonb := '[]'::jsonb;
  v_destination_collision_items jsonb := '[]'::jsonb;
  v_labor_capacity_items jsonb := '[]'::jsonb;
  v_result_without_continuation_items jsonb := '[]'::jsonb;
  v_orphaned_expected_stage_items jsonb := '[]'::jsonb;
  v_high integer := 0;
  v_medium integer := 0;
  v_state text;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  if p_farm_id is null then
    raise exception 'A farm is required.' using errcode='22023';
  end if;
  if auth.uid() is not null and not atlas.is_farm_member(p_farm_id) then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;

  v_base := atlas.farm_continuity_audit_v2(p_farm_id,v_day);

  -- 1. Current living subjects for which canonical Reality Expression has no lawful continuation.
  with packets as materialized (
    select cc.id,cc.crop_cycle_key,cc.crop_label,cc.variety,cc.cycle_state,cc.lifecycle_status,
           atlas.crop_cycle_reality_expression_v4(cc.id) as packet
    from atlas.crop_cycles cc
    where cc.farm_id=p_farm_id
      and coalesce(cc.lifecycle_status,'active')='active'
  ), gaps as (
    select *
    from packets p
    where coalesce((p.packet #>> '{continuity,silentNothing}')::boolean,false)=true
      and exists (
        select 1
        from jsonb_array_elements(coalesce(p.packet->'issues','[]'::jsonb)) issue
        where issue->>'key'='living_subject_without_known_continuation'
      )
  )
  select count(*)::integer,
         coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'cropCycleId',id,
           'cropCycleKey',crop_cycle_key,
           'cropLabel',crop_label,
           'variety',variety,
           'cycleState',cycle_state,
           'lifecycleStatus',lifecycle_status,
           'continuity',packet->'continuity',
           'fittingOperation',packet->'fittingOperation',
           'repairOwner','farm_operations_continuity',
           'reason','A living subject is represented, but canonical Reality Expression has no lawful next state, gate, wait, inspection, or terminal classification.'
         )) order by crop_label,variety nulls last,id),'[]'::jsonb)
  into v_no_next_count,v_no_next_items
  from gaps;

  -- 2, 3 and 7. Production-lot destination, availability and expected-stage continuity.
  with packets as materialized (
    select pl.id,pl.stable_key,pl.lot_label,pl.current_stage,pl.lifecycle_status,
           pl.planned_sow_date,pl.expected_transplant_start,pl.expected_transplant_end,
           pl.expected_harvest_start,pl.expected_harvest_end,
           atlas.reality_expression_packet_v2(pl.id) as packet,
           case
             when pl.current_stage in ('planned','input_ready','ready_to_sow') then pl.planned_sow_date
             when pl.current_stage in ('sown','germinating','germinated','propagation','seedling','hardening_off') then pl.expected_transplant_start
             when pl.current_stage in ('transplanted','establishing','established','field','growing') then pl.expected_harvest_start
             when pl.current_stage in ('harvest','harvesting','harvest_ready') then pl.expected_harvest_end
             else null
           end as next_expected_date
    from atlas.production_lots pl
    where pl.farm_id=p_farm_id
      and coalesce(pl.lifecycle_status,'') not in ('cancelled','failed','complete','completed','archived','terminated')
  ), missing_destination as (
    select * from packets
    where coalesce(packet #>> '{flowBufferClaim,claims,destination,state}','unresolved')='unresolved'
      and coalesce(packet #>> '{flowBufferClaim,nextTransitionAvailability,operationFunction}','') <> 'continue_linked_crop_body'
  ), overclaimed as (
    select distinct p.*
    from packets p
    cross join lateral jsonb_array_elements(coalesce(p.packet #> '{flowBufferClaim,claims,seed,claimSets}','[]'::jsonb)) claim_set
    where coalesce(claim_set #>> '{collision,state}','')='established_overallocation'
       or coalesce((claim_set #>> '{collision,conflictEstablished}')::boolean,false)=true
  ), orphaned as (
    select * from packets
    where next_expected_date is not null
      and coalesce(packet #>> '{flowBufferClaim,nextTransitionAvailability,operationFunction}','') in ('','inspect','inspect_continuity')
  )
  select
    (select count(*)::integer from missing_destination),
    (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
       'productionLotId',id,'stableKey',stable_key,'lotLabel',lot_label,'currentStage',current_stage,
       'lifecycleStatus',lifecycle_status,'plannedSowDate',planned_sow_date,
       'daysUntilSow',case when planned_sow_date is null then null else planned_sow_date-v_day end,
       'horizonClass',case
         when planned_sow_date is null then 'undated'
         when planned_sow_date < v_day then 'overdue'
         when planned_sow_date <= v_day+30 then 'within_30_days'
         else 'future_preparation'
       end,
       'destinationClaim',packet #> '{flowBufferClaim,claims,destination}',
       'nextTransitionAvailability',packet #> '{flowBufferClaim,nextTransitionAvailability}',
       'repairOwner','farm_operations_management',
       'reason','The Production subject has no canonical destination claim. Existence or a future date is not executable availability.'
     )) order by planned_sow_date nulls last,lot_label),'[]'::jsonb) from missing_destination),
    (select count(*)::integer from overclaimed),
    (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
       'productionLotId',id,'stableKey',stable_key,'lotLabel',lot_label,'currentStage',current_stage,
       'seedClaims',packet #> '{flowBufferClaim,claims,seed}',
       'repairOwner','production_inventory',
       'reason','Trusted physical evidence establishes that claims exceed physical availability.'
     )) order by lot_label),'[]'::jsonb) from overclaimed),
    (select count(*)::integer from orphaned),
    (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
       'productionLotId',id,'stableKey',stable_key,'lotLabel',lot_label,'currentStage',current_stage,
       'nextExpectedDate',next_expected_date,
       'nextTransitionAvailability',packet #> '{flowBufferClaim,nextTransitionAvailability}',
       'repairOwner','production_systems',
       'reason','A canonical expected next-stage date exists, but no lawful fitting operation, preparation step, wait state, or continuation is represented.'
     )) order by next_expected_date,lot_label),'[]'::jsonb) from orphaned)
  into v_missing_destination_count,v_missing_destination_items,
       v_overclaimed_count,v_overclaimed_items,
       v_orphaned_expected_stage_count,v_orphaned_expected_stage_items;

  -- 4. Destination collision requires explicit overlapping placement evidence, not merely shared-object ambiguity.
  with active_placements as materialized (
    select cp.id as placement_id,cp.object_id,cp.crop_cycle_id,cp.placement_key,
           cp.planting_claim_id,
           cp.long_start_ft,cp.long_end_ft,cp.cross_start_ft,cp.cross_end_ft,
           cc.crop_label,cc.variety,cc.cycle_state,go.label as object_label,
           (
             cp.planting_claim_id is not null
             and pc.status='planted'
             and exists (
               select 1 from atlas.planting_claim_objects pco
               where pco.planting_claim_id=cp.planting_claim_id
                 and pco.object_id=cp.object_id
                 and pco.coverage_kind in ('whole_object','full_bed')
             )
           ) as exclusive_claim
    from atlas.crop_placements cp
    join atlas.crop_cycles cc on cc.id=cp.crop_cycle_id
    left join atlas.growing_objects go on go.id=cp.object_id
    left join atlas.planting_claims pc on pc.id=cp.planting_claim_id
    where cp.farm_id=p_farm_id
      and coalesce(cc.lifecycle_status,'active')='active'
  ), cell_pairs as (
    select least(a.crop_cycle_id,b.crop_cycle_id) as cycle_a,
           greatest(a.crop_cycle_id,b.crop_cycle_id) as cycle_b,
           a.object_id,
           case when a.exclusive_claim or b.exclusive_claim
                then 'explicit_cell_overlap_against_exclusive_claim'
                else 'explicit_cell_capacity_exceeded' end::text as evidence_type,
           min(ca.cell_key) as evidence_key
    from active_placements a
    join atlas.crop_placement_cells ca on ca.placement_id=a.placement_id
    join active_placements b on b.object_id=a.object_id and b.crop_cycle_id<>a.crop_cycle_id
    join atlas.crop_placement_cells cb on cb.placement_id=b.placement_id and cb.cell_key=ca.cell_key
    where a.crop_cycle_id<b.crop_cycle_id
      and (
        a.exclusive_claim or b.exclusive_claim
        or coalesce(ca.coverage_fraction,1)+coalesce(cb.coverage_fraction,1)>1
      )
    group by least(a.crop_cycle_id,b.crop_cycle_id),greatest(a.crop_cycle_id,b.crop_cycle_id),a.object_id,
             case when a.exclusive_claim or b.exclusive_claim
                  then 'explicit_cell_overlap_against_exclusive_claim'
                  else 'explicit_cell_capacity_exceeded' end
  ), rectangle_pairs as (
    select least(a.crop_cycle_id,b.crop_cycle_id) as cycle_a,
           greatest(a.crop_cycle_id,b.crop_cycle_id) as cycle_b,
           a.object_id,
           'explicit_rectangle_overlap_against_exclusive_claim'::text as evidence_type,
           null::text as evidence_key
    from active_placements a
    join active_placements b on b.object_id=a.object_id and a.crop_cycle_id<b.crop_cycle_id
    where (a.exclusive_claim or b.exclusive_claim)
      and a.long_start_ft is not null and a.long_end_ft is not null
      and a.cross_start_ft is not null and a.cross_end_ft is not null
      and b.long_start_ft is not null and b.long_end_ft is not null
      and b.cross_start_ft is not null and b.cross_end_ft is not null
      and least(a.long_end_ft,b.long_end_ft)>greatest(a.long_start_ft,b.long_start_ft)
      and least(a.cross_end_ft,b.cross_end_ft)>greatest(a.cross_start_ft,b.cross_start_ft)
  ), raw_pairs as (
    select * from cell_pairs
    union all
    select * from rectangle_pairs
  ), collisions as (
    select r.cycle_a,r.cycle_b,r.object_id,
           jsonb_agg(distinct to_jsonb(r.evidence_type)) as evidence_types,
           jsonb_agg(distinct to_jsonb(r.evidence_key)) filter(where r.evidence_key is not null) as evidence_keys,
           max(a.crop_label) filter(where a.crop_cycle_id=r.cycle_a) as crop_a_label,
           max(a.variety) filter(where a.crop_cycle_id=r.cycle_a) as crop_a_variety,
           max(b.crop_label) filter(where b.crop_cycle_id=r.cycle_b) as crop_b_label,
           max(b.variety) filter(where b.crop_cycle_id=r.cycle_b) as crop_b_variety,
           max(coalesce(a.object_label,b.object_label)) as object_label
    from raw_pairs r
    left join active_placements a on a.crop_cycle_id=r.cycle_a and a.object_id=r.object_id
    left join active_placements b on b.crop_cycle_id=r.cycle_b and b.object_id=r.object_id
    group by r.cycle_a,r.cycle_b,r.object_id
  )
  select count(*)::integer,
         coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'cropCycleA',cycle_a,'cropALabel',crop_a_label,'cropAVariety',crop_a_variety,
           'cropCycleB',cycle_b,'cropBLabel',crop_b_label,'cropBVariety',crop_b_variety,
           'objectId',object_id,'objectLabel',object_label,
           'evidenceTypes',evidence_types,'evidenceKeys',evidence_keys,
           'repairOwner','farm_operations_management',
           'reason','Two active crop bodies have explicit overlapping destination evidence and canonical exclusivity or capacity evidence establishes incompatibility.'
         )) order by object_label,crop_a_label,crop_b_label),'[]'::jsonb)
  into v_destination_collision_count,v_destination_collision_items
  from collisions;

    -- 5. Labor-capacity collision requires an actual Worker Day claim and a proven day-capacity contradiction.
  with placement_groups as materialized (
    select p.membership_id,p.service_date,
           sum(coalesce(p.planned_duration_minutes,0))::integer as planned_minutes,
           count(*)::integer as placed_task_count,
           jsonb_agg(jsonb_build_object(
             'placementId',p.id,'taskId',p.task_id,'minutes',p.planned_duration_minutes,
             'dayWindow',p.day_window,'plannedStartAt',p.planned_start_at
           ) order by p.sort_order,p.created_at) as placements
    from atlas.worker_day_task_placements p
    where p.farm_id=p_farm_id
      and p.state='placed'
      and p.service_date between v_day and v_day+30
      and (
        exists(select 1 from atlas.task_crop_cycles tc where tc.task_id=p.task_id)
        or exists(select 1 from atlas.production_lot_tasks plt where plt.task_id=p.task_id)
      )
    group by p.membership_id,p.service_date
  ), evaluated as materialized (
    select g.*,atlas.worker_week_day_capacity_v1(p_farm_id,g.membership_id,g.service_date) as capacity
    from placement_groups g
  ), conflicts as (
    select * from evaluated
    where capacity->>'state' in ('unavailable','non_working_day','policy_conflict')
       or (nullif(capacity->>'maximumUsableMinutes','') is not null
           and planned_minutes>(capacity->>'maximumUsableMinutes')::integer)
  )
  select count(*)::integer,
         coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'membershipId',membership_id,'serviceDate',service_date,
           'plannedMinutes',planned_minutes,'placedTaskCount',placed_task_count,
           'capacity',capacity,'placements',placements,
           'repairOwner','farm_operations_management',
           'reason','Committed Worker Day production work exceeds or contradicts the canonical capacity contract for that worker/date.'
         )) order by service_date,membership_id),'[]'::jsonb)
  into v_labor_capacity_count,v_labor_capacity_items
  from conflicts;

  -- 6. A recorded operation fruit must not leave its living subject with silent nothing afterward.
  with latest_actual as materialized (
    select distinct on (link.crop_cycle_id)
           link.crop_cycle_id,a.id as operation_actual_id,a.task_id,a.operation_class,a.observed_date,
           a.result_class,a.result_payload,a.created_at
    from atlas.production_operation_actual_crop_cycles link
    join atlas.production_operation_actuals a on a.id=link.operation_actual_id
    where a.farm_id=p_farm_id
    order by link.crop_cycle_id,a.created_at desc,a.id desc
  ), evaluated as (
    select la.*,cc.crop_label,cc.variety,cc.cycle_state,cc.lifecycle_status,
           atlas.crop_cycle_reality_expression_v4(la.crop_cycle_id) as packet
    from latest_actual la
    join atlas.crop_cycles cc on cc.id=la.crop_cycle_id
    where coalesce(cc.lifecycle_status,'active')='active'
  ), gaps as (
    select * from evaluated
    where coalesce((packet #>> '{continuity,silentNothing}')::boolean,false)=true
  )
  select count(*)::integer,
         coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'operationActualId',operation_actual_id,'taskId',task_id,'cropCycleId',crop_cycle_id,
           'cropLabel',crop_label,'variety',variety,'cycleState',cycle_state,
           'operationClass',operation_class,'observedDate',observed_date,'resultClass',result_class,
           'continuity',packet->'continuity',
           'repairOwner','farm_operations_continuity',
           'reason','Structured operation fruit exists, but the living subject currently has no represented continuation.'
         )) order by observed_date,crop_label,variety nulls last),'[]'::jsonb)
  into v_result_without_continuation_count,v_result_without_continuation_items
  from gaps;

  v_high := coalesce((v_base->'summary'->>'highPriorityIssueCount')::integer,0)
            + v_no_next_count + v_overclaimed_count + v_destination_collision_count
            + v_labor_capacity_count + v_result_without_continuation_count;
  v_medium := coalesce((v_base->'summary'->>'mediumPriorityIssueCount')::integer,0)
              + v_missing_destination_count + v_orphaned_expected_stage_count;
  v_state := case
    when v_high>0 then 'high_priority_continuity_attention'
    when v_medium>0 then 'continuity_attention'
    else 'no_actionable_continuity_gap_detected'
  end;

  return v_base || jsonb_build_object(
    'contractVersion','farm_continuity_audit_v3',
    'state',v_state,
    'farmTruthMutated',false,
    'principalEscalationCreated',false,
    'principalBoundary','Continuity findings remain Farm Operations truth until an explicit escalation threshold translates them into an ownership decision.',
    'summary',(v_base->'summary') || jsonb_build_object(
      'highPriorityIssueCount',v_high,
      'mediumPriorityIssueCount',v_medium,
      'noLawfulNextStateCount',v_no_next_count,
      'missingDestinationCount',v_missing_destination_count,
      'overclaimedAvailabilityCount',v_overclaimed_count,
      'destinationCollisionCount',v_destination_collision_count,
      'committedWorkWithoutLaborCapacityCount',v_labor_capacity_count,
      'resultWithoutContinuationCount',v_result_without_continuation_count,
      'orphanedExpectedNextStageCount',v_orphaned_expected_stage_count
    ),
    'issueFamilies',(v_base->'issueFamilies') || jsonb_build_array(
      jsonb_build_object('key','no_lawful_next_state','severity','high','count',v_no_next_count,'items',v_no_next_items),
      jsonb_build_object('key','missing_destination','severity','medium','count',v_missing_destination_count,'items',v_missing_destination_items),
      jsonb_build_object('key','overclaimed_availability','severity','high','count',v_overclaimed_count,'items',v_overclaimed_items),
      jsonb_build_object('key','destination_collision','severity','high','count',v_destination_collision_count,'items',v_destination_collision_items),
      jsonb_build_object('key','committed_work_without_labor_capacity','severity','high','count',v_labor_capacity_count,'items',v_labor_capacity_items),
      jsonb_build_object('key','result_without_continuation','severity','high','count',v_result_without_continuation_count,'items',v_result_without_continuation_items),
      jsonb_build_object('key','orphaned_expected_next_stage','severity','medium','count',v_orphaned_expected_stage_count,'items',v_orphaned_expected_stage_items)
    ),
    'auditCoverage',(v_base->'auditCoverage') || jsonb_build_object(
      'realityExpressionNoLawfulNextState','audited_from_crop_cycle_reality_expression_v4',
      'realityExpressionMissingDestination','audited_from_production_flow_buffer_claim_v1',
      'realityExpressionOverclaimedAvailability','audited_only_when_trusted_physical_warrant_establishes_overallocation',
      'realityExpressionDestinationCollision','audited_only_from_explicit_overlapping_crop placement geometry_or_cells',
      'realityExpressionCommittedLaborCapacity','audited_from_worker_day_placement_claims_against_worker_week_day_capacity_v1',
      'realityExpressionResultContinuation','audited_from_structured_operation_actual_to_current_crop_continuity',
      'realityExpressionExpectedNextStage','audited_from_expected_production_milestones_without_a_lawful_operation_or_gate'
    ),
    'truthBoundary',jsonb_build_object(
      'unresolvedRelationIsNotCollision',true,
      'sharedClaimsWithoutTrustedPhysicalWarrantAreNotOverclaimed',true,
      'laborEstimateIsNotLaborClaim',true,
      'futureDateIsNotExecutableOperation',true,
      'taskCompletionIsNotContinuationProof',true,
      'auditDoesNotCreatePrincipalWork',true
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION atlas.grow_room_state_v1(p_farm_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_zone_id uuid;
  v_zone jsonb := '{}'::jsonb;
  v_objects jsonb := '[]'::jsonb;
  v_relationships jsonb := '[]'::jsonb;
  v_batches jsonb := '[]'::jsonb;
  v_actions jsonb := '[]'::jsonb;
  v_visit_task jsonb := null;
  v_crop_profiles jsonb := '[]'::jsonb;
  v_destinations jsonb := '[]'::jsonb;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  if p_farm_id is null or not atlas.is_farm_member(p_farm_id) then
    raise exception 'Farm access is not active.' using errcode = '42501';
  end if;

  select z.id,
         jsonb_build_object('zoneId', z.id, 'zoneKey', z.stable_key, 'label', z.label)
    into v_zone_id, v_zone
  from atlas.zones z
  where z.farm_id = p_farm_id and z.stable_key = 'grow_room'
  limit 1;

  if v_zone_id is null then
    return jsonb_build_object(
      'farmId', p_farm_id, 'zone', null, 'objects', '[]'::jsonb,
      'relationships', '[]'::jsonb, 'batches', '[]'::jsonb,
      'actions', '[]'::jsonb, 'visitTask', null,
      'cropProfiles', '[]'::jsonb, 'destinations', '[]'::jsonb
    );
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'objectId', go.id,
    'objectKey', go.stable_key,
    'label', go.label,
    'objectType', go.object_type,
    'objectMode', go.object_mode,
    'sortOrder', go.sort_order,
    'metadata', coalesce(go.metadata, '{}'::jsonb)
  ) order by go.sort_order, go.label), '[]'::jsonb)
  into v_objects
  from atlas.growing_objects go
  where go.farm_id = p_farm_id and go.zone_id = v_zone_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'relationshipId', r.id,
    'parentObjectId', r.parent_object_id,
    'childObjectId', r.child_object_id,
    'relationshipType', r.relationship_type,
    'positionLabel', r.position_label,
    'sortOrder', r.sort_order,
    'metadata', r.metadata
  ) order by r.sort_order, r.created_at), '[]'::jsonb)
  into v_relationships
  from atlas.growing_object_relationships r
  join atlas.growing_objects parent on parent.id = r.parent_object_id
  join atlas.growing_objects child on child.id = r.child_object_id
  where r.farm_id = p_farm_id
    and (parent.zone_id = v_zone_id or child.zone_id = v_zone_id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'batchId', b.id,
    'productionLotId', b.production_lot_id,
    'batchNumber', b.batch_number,
    'batchLabel', b.batch_label,
    'containerKind', b.container_kind,
    'blockSizeIn', b.block_size_in,
    'trayCount', b.tray_count,
    'seedsSown', b.seeds_sown,
    'seedUnit', b.seed_unit,
    'status', b.status,
    'sownDate', b.sown_date,
    'expectedGerminationStart', b.expected_germination_start,
    'expectedGerminationEnd', b.expected_germination_end,
    'germinatedDate', b.germinated_date,
    'viableSeedlings', b.viable_seedlings,
    'currentQuantity', b.current_quantity,
    'currentUnit', b.current_unit,
    'actionRequired', b.action_required,
    'actionKey', b.action_key,
    'actionDueDate', b.action_due_date,
    'actionNote', b.action_note,
    'lastObservedAt', b.last_observed_at,
    'lastActionAt', b.last_action_at,
    'destinationObjectId', b.destination_object_id,
    'destinationLabel', destination.label,
    'sourceObjectId', b.source_object_id,
    'cropProfileId', lot.crop_profile_id,
    'cropLabel', coalesce(cp.crop_label, lot.metadata ->> 'crop_label_entered', lot.lot_label),
    'variety', coalesce(cp.variety, lot.metadata ->> 'variety_entered'),
    'lotLabel', lot.lot_label,
    'lotStage', lot.current_stage,
    'lotLifecycleStatus', lot.lifecycle_status,
    'expectedTransplantStart', lot.expected_transplant_start,
    'expectedTransplantEnd', lot.expected_transplant_end,
    'expectedHarvestStart', lot.expected_harvest_start,
    'expectedHarvestEnd', lot.expected_harvest_end,
    'locationObjectId', loc.location_object_id,
    'locationLabel', location.label,
    'positionLabel', loc.position_label,
    'metadata', coalesce(b.metadata, '{}'::jsonb)
  ) order by coalesce(location.sort_order, 999999), location.label nulls last, b.batch_label), '[]'::jsonb)
  into v_batches
  from atlas.production_tray_batches b
  join atlas.production_lots lot on lot.id = b.production_lot_id
  left join atlas.crop_profiles cp on cp.id = lot.crop_profile_id
  left join atlas.production_tray_batch_locations loc on loc.tray_batch_id = b.id and loc.removed_at is null
  left join atlas.growing_objects location on location.id = loc.location_object_id
  left join atlas.growing_objects destination on destination.id = b.destination_object_id
  where b.farm_id = p_farm_id and b.status not in ('closed', 'transplanted');

  select coalesce(jsonb_agg(jsonb_build_object(
    'taskId', t.id,
    'title', t.title,
    'taskType', t.task_type,
    'actionKey', t.action_key,
    'status', t.status,
    'priority', t.priority,
    'dueDate', t.due_date,
    'zoneLabel', z.label,
    'batchId', linked_batch.id,
    'batchLabel', linked_batch.batch_label,
    'metadata', coalesce(t.metadata, '{}'::jsonb)
  ) order by t.due_date nulls last, t.priority desc, t.created_at), '[]'::jsonb)
  into v_actions
  from atlas.tasks t
  left join atlas.zones z on z.id = t.zone_id
  left join lateral (
    select b1.id, b1.batch_label
    from atlas.production_tray_batches b1
    left join atlas.production_lot_tasks plt on plt.production_lot_id = b1.production_lot_id and plt.task_id = t.id
    where b1.farm_id = p_farm_id and (b1.source_task_id = t.id or plt.task_id is not null)
    order by b1.batch_number
    limit 1
  ) linked_batch on true
  where t.farm_id = p_farm_id
    and t.status in ('open', 'blocked')
    and not (t.task_type = 'grow_room_care' and lower(t.title) in ('grow room care', 'water + check grow room', 'check grow room'))
    and lower(coalesce(t.action_key, '')) not in ('water', 'watering')
    and (
      t.zone_id = v_zone_id
      or linked_batch.id is not null
      or coalesce(t.metadata ->> 'collection_zone', '') ilike '%grow room%'
      or coalesce(t.metadata ->> 'location_label', '') ilike '%grow room%'
      or coalesce(t.metadata ->> 'work_route', '') in ('grow_room_check', 'grow_room_audit', 'pot_up', 'hardening_off', 'soil_block')
    );

  select jsonb_build_object('taskId', t.id, 'title', t.title, 'dueDate', t.due_date, 'status', t.status)
  into v_visit_task
  from atlas.tasks t
  where t.farm_id = p_farm_id
    and t.status in ('open', 'blocked')
    and t.task_type = 'grow_room_care'
    and lower(t.title) in ('grow room care', 'water + check grow room', 'check grow room')
  order by case when t.due_date = current_date then 0 else 1 end, t.due_date nulls last, t.created_at desc
  limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'cropProfileId', cp.id,
    'stableKey', cp.stable_key,
    'cropLabel', cp.crop_label,
    'variety', cp.variety,
    'daysToGerminationMin', cp.days_to_germination_min,
    'daysToGerminationMax', cp.days_to_germination_max
  ) order by cp.crop_label, cp.variety nulls first), '[]'::jsonb)
  into v_crop_profiles
  from atlas.crop_profiles cp;

  select coalesce(jsonb_agg(jsonb_build_object(
    'objectId', go.id,
    'objectKey', go.stable_key,
    'label', go.label,
    'objectType', go.object_type,
    'objectMode', go.object_mode,
    'zoneId', z.id,
    'zoneKey', z.stable_key,
    'zoneLabel', z.label,
    'sortOrder', go.sort_order
  ) order by z.sort_order, z.label, go.sort_order, go.label), '[]'::jsonb)
  into v_destinations
  from atlas.growing_objects go
  left join atlas.zones z on z.id = go.zone_id
  where go.farm_id = p_farm_id
    and go.zone_id is distinct from v_zone_id
    and go.object_type in ('bed', 'arch_bed', 'area', 'room');

  return jsonb_build_object(
    'farmId', p_farm_id,
    'zone', v_zone,
    'objects', v_objects,
    'relationships', v_relationships,
    'batches', v_batches,
    'actions', v_actions,
    'visitTask', v_visit_task,
    'cropProfiles', v_crop_profiles,
    'destinations', v_destinations,
    'rules', jsonb_build_object(
      'wateringLogged', false,
      'ordinaryCareIsHabit', true,
      'onlyActionBearingChangesAreRecorded', true,
      'unknownSowingFactsStayUnknown', true
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION atlas.mowing_rhythm_dashboard_v1(p_farm_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare v_items jsonb;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  if auth.uid() is null or not atlas.is_farm_member(p_farm_id) then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'objectId',go.id,'objectKey',go.stable_key,'label',go.label,'zoneId',go.zone_id,'zoneLabel',z.label,
    'equipmentGroup',go.metadata->>'equipment_group','targetCutHeightInches',go.metadata->>'target_cut_height_inches',
    'cadenceDays',go.metadata->>'mowing_cadence_days','stateId',rs.id,'rhythmState',rs.state,
    'warningAt',rs.warning_at,'dueAt',rs.due_at,'failureAt',rs.failure_at,'currentTaskId',rs.current_task_id,
    'areaStatus',coalesce(ms.status,'unassessed'),'lastMowedAt',ms.last_mowed_at,'lastObservedAt',ms.last_observed_at,
    'nextCheckDate',ms.next_check_date,'note',ms.note,'bindingActive',rb.active
  ) order by coalesce((go.metadata->>'mowing_sort_order')::integer,999),go.label),'[]'::jsonb) into v_items
  from atlas.rhythm_state rs
  join atlas.rhythm_bindings rb on rb.id=rs.rhythm_binding_id
  join atlas.growing_objects go on go.id=rs.subject_id
  left join atlas.zones z on z.id=go.zone_id
  left join atlas.mowing_area_state ms on ms.object_id=go.id
  where rs.farm_id=p_farm_id and rs.rhythm_key='mowing' and rs.subject_kind='growing_object';
  return jsonb_build_object('contractVersion','mowing_rhythm_dashboard_v1','farmId',p_farm_id,'items',v_items);
end;
$function$;

CREATE OR REPLACE FUNCTION atlas.real_operation_explanation_v1(p_transition_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_transition atlas.task_transitions%rowtype;
  v_task atlas.tasks%rowtype;
  v_outcome atlas.task_outcome_events%rowtype;
  v_task_workflow atlas.workflow_events%rowtype;
  v_journal atlas.journal_event_index%rowtype;
  v_before jsonb := '[]'::jsonb;
  v_after jsonb := '[]'::jsonb;
  v_next jsonb := '[]'::jsonb;
  v_current_claims jsonb := '[]'::jsonb;
  v_reforecast_lots jsonb := '[]'::jsonb;
  v_subject_count integer := 0;
  v_operation_actual_count integer := 0;
  v_required_result_count integer := 0;
  v_production_lot_count integer := 0;
  v_planting_claim_count integer := 0;
  v_bell_worthy boolean := null;
  v_bell_requires_action boolean := null;
  v_bell_receipt_count integer := 0;
  v_rec record;
  v_before_event atlas.workflow_events%rowtype;
  v_after_event atlas.workflow_events%rowtype;
  v_packet jsonb;
  v_before_state text;
  v_before_lifecycle text;
  v_after_state text;
  v_after_lifecycle text;
  v_result_capture_state text;
  v_explanation_state text;
begin
  if p_transition_id is null then
    raise exception 'A task transition is required.' using errcode='22023';
  end if;

  select * into v_transition
  from atlas.task_transitions
  where id=p_transition_id;

  if v_transition.id is null then
    raise exception 'Source unavailable to this Person.' using errcode='42501';
  end if;

  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(v_transition.farm_id);

  if auth.uid() is not null and not atlas.is_farm_member(v_transition.farm_id) then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;

  select * into v_task
  from atlas.tasks
  where id=v_transition.task_id and farm_id=v_transition.farm_id;

  if v_task.id is null then
    raise exception 'Transition task was not found on its farm.' using errcode='P0002';
  end if;

  if v_transition.task_outcome_event_id is not null then
    select * into v_outcome
    from atlas.task_outcome_events
    where id=v_transition.task_outcome_event_id;
  end if;

  select * into v_task_workflow
  from atlas.workflow_events we
  where we.source_kind='task'
    and we.source_id=v_task.id
    and (
      (v_outcome.id is not null and we.payload->>'task_outcome_event_id'=v_outcome.id::text)
      or (we.created_at=v_transition.created_at and we.source_event=v_transition.transition)
    )
  order by case when v_outcome.id is not null and we.payload->>'task_outcome_event_id'=v_outcome.id::text then 0 else 1 end,
           we.created_at,we.id
  limit 1;

  if v_task_workflow.id is not null then
    select * into v_journal
    from atlas.journal_event_index je
    where je.source_workflow_event_id=v_task_workflow.id
    order by je.created_at,je.id
    limit 1;
  end if;

  if v_journal.id is not null then
    begin
      v_bell_worthy := atlas.bell_event_is_worthy_v1(v_journal.id);
    exception when others then
      v_bell_worthy := null;
    end;

    if v_transition.actor_user_id is not null then
      begin
        v_bell_requires_action := atlas.bell_event_requires_action_v1(v_journal.id,v_transition.actor_user_id);
      exception when others then
        v_bell_requires_action := null;
      end;
    end if;

    select count(*)::integer into v_bell_receipt_count
    from atlas.bell_event_receipts ber
    where ber.journal_event_id=v_journal.id;
  end if;

  select count(*)::integer into v_operation_actual_count
  from atlas.production_operation_actuals a
  where a.task_id=v_task.id;

  if jsonb_typeof(v_task.metadata->'worker_result_lines')='array' then
    v_required_result_count := jsonb_array_length(v_task.metadata->'worker_result_lines');
  else
    v_required_result_count := 0;
  end if;

  for v_rec in
    select cc.*,go.stable_key as object_key,go.label as object_label,tc.role as task_crop_role,tc.created_at as task_crop_linked_at
    from atlas.task_crop_cycles tc
    join atlas.crop_cycles cc on cc.id=tc.crop_cycle_id
    left join atlas.growing_objects go on go.id=cc.object_id
    where tc.task_id=v_task.id
    order by cc.crop_label,cc.variety,go.label,cc.id
  loop
    v_subject_count := v_subject_count+1;

    select * into v_before_event
    from atlas.workflow_events we
    where we.source_kind='crop_cycle'
      and we.source_id=v_rec.id
      and we.created_at<v_transition.created_at
    order by we.created_at desc,we.id desc
    limit 1;

    v_before_state := coalesce(v_before_event.payload->>'cycle_state','unresolved');
    v_before_lifecycle := coalesce(v_before_event.payload->>'lifecycle_status','unresolved');

    select * into v_after_event
    from atlas.workflow_events we
    where we.source_kind='crop_cycle'
      and we.source_id=v_rec.id
      and we.created_at>=v_transition.created_at
      and we.created_at<=v_transition.created_at+interval '1 second'
    order by we.created_at,we.id
    limit 1;

    v_after_state := coalesce(v_after_event.payload->>'cycle_state','unresolved');
    v_after_lifecycle := coalesce(v_after_event.payload->>'lifecycle_status','unresolved');

    v_packet := atlas.crop_cycle_reality_expression_v4(v_rec.id);

    v_before := v_before || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'subjectType','crop_cycle',
      'cropCycleId',v_rec.id,
      'cropCycleKey',v_rec.crop_cycle_key,
      'cropLabel',v_rec.crop_label,
      'variety',v_rec.variety,
      'objectId',v_rec.object_id,
      'objectKey',v_rec.object_key,
      'objectLabel',v_rec.object_label,
      'taskRelationRole',v_rec.task_crop_role,
      'taskLinkedAt',v_rec.task_crop_linked_at,
      'state',v_before_state,
      'lifecycleStatus',v_before_lifecycle,
      'evidenceAt',v_before_event.created_at,
      'sourceEvent',v_before_event.source_event,
      'reconstructionState',case when v_before_event.id is null then 'no_prior_subject_event' else 'event_reconstructed' end
    )));

    v_after := v_after || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'subjectType','crop_cycle',
      'cropCycleId',v_rec.id,
      'cropCycleKey',v_rec.crop_cycle_key,
      'cropLabel',v_rec.crop_label,
      'variety',v_rec.variety,
      'objectId',v_rec.object_id,
      'objectKey',v_rec.object_key,
      'objectLabel',v_rec.object_label,
      'stateAtOperation',v_after_state,
      'lifecycleStatusAtOperation',v_after_lifecycle,
      'operationEvidenceAt',v_after_event.created_at,
      'operationSourceEvent',v_after_event.source_event,
      'operationReconstructionState',case when v_after_event.id is null then 'no_direct_subject_event_at_transition' else 'event_reconstructed' end,
      'currentState',v_rec.cycle_state,
      'currentLifecycleStatus',v_rec.lifecycle_status,
      'currentRealityContract',v_packet->>'contractVersion',
      'currentIssues',coalesce(v_packet->'issues','[]'::jsonb),
      'currentContinuity',coalesce(v_packet->'continuity','{}'::jsonb)
    )));

    v_next := v_next || jsonb_build_array(jsonb_build_object(
      'cropCycleId',v_rec.id,
      'cropLabel',v_rec.crop_label,
      'variety',v_rec.variety,
      'objectLabel',v_rec.object_label,
      'fittingOperation',coalesce(v_packet->'fittingOperation','{}'::jsonb),
      'continuity',coalesce(v_packet->'continuity','{}'::jsonb),
      'silentNothing',coalesce((v_packet #>> '{continuity,silentNothing}')::boolean,false)
    ));

    if v_rec.planting_claim_id is not null then
      v_planting_claim_count := v_planting_claim_count+1;
    end if;

    v_current_claims := v_current_claims || jsonb_build_array(jsonb_build_object(
      'cropCycleId',v_rec.id,
      'objectLabel',v_rec.object_label,
      'plantingClaimId',v_rec.planting_claim_id,
      'plantingClaimState',coalesce(v_packet #>> '{spatialTruth,claim,state}',v_packet #>> '{flowBuffer,plantingClaim,status}','unresolved'),
      'productionLotLinkCount',coalesce((v_packet #>> '{claims,productionLotLinkCount}')::integer,0),
      'availabilityStatus',v_packet #>> '{claims,availabilityStatus}'
    ));
  end loop;

  with lots as (
    select distinct pl.id,pl.stable_key,pl.lot_label,pl.current_stage,pl.lifecycle_status
    from atlas.production_lots pl
    where exists (
      select 1 from atlas.production_lot_tasks plt
      where plt.production_lot_id=pl.id and plt.task_id=v_task.id
    )
    or exists (
      select 1
      from atlas.production_lot_crop_cycles plc
      join atlas.task_crop_cycles tc on tc.crop_cycle_id=plc.crop_cycle_id
      where plc.production_lot_id=pl.id and tc.task_id=v_task.id
    )
  )
  select count(*)::integer,
         coalesce(jsonb_agg(jsonb_build_object(
           'productionLotId',id,
           'stableKey',stable_key,
           'lotLabel',lot_label,
           'currentStage',current_stage,
           'lifecycleStatus',lifecycle_status,
           'preview',atlas.production_lot_reforecast_preview_v1(id,null)
         ) order by lot_label,id),'[]'::jsonb)
  into v_production_lot_count,v_reforecast_lots
  from lots;

  v_result_capture_state := case
    when v_required_result_count=0 then 'no_additional_result_evidence_required_by_task'
    when v_operation_actual_count>0 then 'structured_operation_actual_present'
    when coalesce(v_transition.note,'')<>'' or coalesce(v_transition.reason,'')<>'' then 'unstructured_transition_text_present_completeness_unproven'
    else 'required_result_evidence_not_captured'
  end;

  v_explanation_state := case
    when v_subject_count=0 then 'operation_subject_unrepresented'
    when exists(select 1 from jsonb_array_elements(v_after) x where x->>'operationReconstructionState'='event_reconstructed') then 'real_operation_reconstructed'
    else 'transition_recorded_subject_effect_unproven'
  end;

  return jsonb_build_object(
    'contractVersion','real_operation_explanation_v1',
    'state',v_explanation_state,
    'farmId',v_transition.farm_id,
    'transitionId',v_transition.id,
    'task',jsonb_build_object(
      'id',v_task.id,
      'title',v_task.title,
      'taskType',v_task.task_type,
      'actionKey',v_task.action_key,
      'operationClass',v_task.operation_class,
      'dueDate',v_task.due_date,
      'currentStatus',v_task.status
    ),
    'predictedBeforeState',jsonb_build_object(
      'state','historical_event_reconstruction',
      'subjects',v_before,
      'principle','The before state is reconstructed only from canonical subject events recorded before the human transition; current rows are not backdated into historical truth.'
    ),
    'expectedMove',jsonb_strip_nulls(jsonb_build_object(
      'actionKey',v_task.action_key,
      'operationClass',v_task.operation_class,
      'do',coalesce(nullif(v_task.metadata->>'execution_do',''),v_task.title),
      'how',v_task.metadata->'execution_how',
      'doneWhen',nullif(v_task.metadata->>'execution_done_when',''),
      'targetLabels',v_task.metadata->'target_labels',
      'requiredResultEvidence',v_task.metadata->'worker_result_lines'
    )),
    'actualEvidence',jsonb_build_object(
      'transition',jsonb_strip_nulls(jsonb_build_object(
        'id',v_transition.id,
        'transition',v_transition.transition,
        'previousStatus',v_transition.previous_status,
        'nextStatus',v_transition.next_status,
        'occurredAt',v_transition.created_at,
        'actorUserId',v_transition.actor_user_id,
        'actorMembershipId',v_transition.actor_membership_id,
        'actorRole',v_transition.actor_role,
        'note',v_transition.note,
        'reason',v_transition.reason,
        'payload',v_transition.payload
      )),
      'taskOutcomeEvent',case when v_outcome.id is null then null else jsonb_build_object(
        'id',v_outcome.id,'outcome',v_outcome.outcome,'createdAt',v_outcome.created_at,'metadata',v_outcome.metadata
      ) end,
      'structuredOperationActualCount',v_operation_actual_count,
      'resultEvidenceRequirementCount',v_required_result_count,
      'resultEvidenceCaptureState',v_result_capture_state,
      'principle','A historical Done transition proves that the transition was recorded. It does not retroactively prove missing quantities, minutes, claims, spatial geometry, or other result fields.'
    ),
    'afterState',jsonb_build_object(
      'subjects',v_after,
      'principle','State at the operation boundary comes from subject events emitted with the transition; current state is shown separately so later changes cannot be confused with the original fruit.'
    ),
    'claimMovement',jsonb_build_object(
      'state','historical_claim_movement_not_reconstructable_from_available_event_evidence',
      'movementEstablished',false,
      'currentPlantingClaimCount',v_planting_claim_count,
      'currentClaims',v_current_claims,
      'principle','The operation may have changed physical custody or spatial use, but claim movement is not asserted unless a claim-bearing evidence rail records it.'
    ),
    'reforecast',jsonb_build_object(
      'state',case when v_production_lot_count=0 then 'not_evaluable_no_production_lot_provenance' else 'current_production_reforecast_available' end,
      'productionLotCount',v_production_lot_count,
      'productionLots',v_reforecast_lots,
      'principle','A crop-cycle state change is not promoted to a Production reforecast when no Production Lot provenance connects the subject to the reforecast engine.'
    ),
    'nextOperation',jsonb_build_object(
      'subjects',v_next,
      'allSubjectsHaveContinuation',case
        when v_subject_count=0 then false
        else not exists(select 1 from jsonb_array_elements(v_next) x where coalesce((x->>'silentNothing')::boolean,false)=true)
      end,
      'principle','The operation is only institutionally complete when the changed subject has a lawful continuation, wait, gate, decision, or terminal state.'
    ),
    'visibleEffects',jsonb_build_object(
      'worker',jsonb_build_object(
        'taskStatus',v_task.status,
        'transitionRecorded',true,
        'actorMembershipId',v_transition.actor_membership_id,
        'actorRole',v_transition.actor_role
      ),
      'workflow',case when v_task_workflow.id is null then jsonb_build_object('state','no_linked_workflow_event_found') else jsonb_build_object(
        'state','recorded','eventId',v_task_workflow.id,'sourceEvent',v_task_workflow.source_event,'createdAt',v_task_workflow.created_at
      ) end,
      'journal',case when v_journal.id is null then jsonb_build_object('state','no_linked_journal_event_found') else jsonb_build_object(
        'state','recorded','eventId',v_journal.id,'eventKind',v_journal.event_kind,'title',v_journal.title,'occurredAt',v_journal.occurred_at
      ) end,
      'bell',jsonb_build_object(
        'classificationState',case when v_journal.id is null then 'not_evaluable_without_journal_event' when v_bell_worthy is true then 'bell_worthy' when v_bell_worthy is false then 'not_bell_worthy' else 'classification_unresolved' end,
        'worthy',v_bell_worthy,
        'requiresActorAction',v_bell_requires_action,
        'receiptCount',v_bell_receipt_count
      ),
      'principal',jsonb_build_object(
        'escalationCreatedByThisContract',false,
        'principle','A delegated operation and its evidence remain operational truth unless a separate explicit escalation threshold translates the consequence into Principal jurisdiction.'
      )
    ),
    'truthGaps',jsonb_build_object(
      'requiredResultEvidenceCaptureState',v_result_capture_state,
      'claimMovementEstablished',false,
      'productionReforecastEvaluable',v_production_lot_count>0,
      'currentRealityIssues',(
        select coalesce(jsonb_agg(jsonb_build_object(
          'cropCycleId',x->>'cropCycleId',
          'issues',coalesce(x->'currentIssues','[]'::jsonb)
        )),'[]'::jsonb)
        from jsonb_array_elements(v_after) x
      )
    ),
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'historicalTransitionIsEvidenceNotCompleteFruit',true,
      'currentRowsAreNotBackdated',true,
      'missingResultFieldsAreNotInvented',true,
      'unrepresentedClaimMovementIsNotInferred',true,
      'productionReforecastRequiresProductionLotProvenance',true,
      'taskCompletionIsNotContinuationProof',true,
      'principalEscalationIsSeparateJurisdiction',true
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION atlas.tending_board_v1(p_farm_id uuid, p_worker_key text DEFAULT NULL::text, p_due_through date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare v_role text; v_membership_id uuid; v_worker_key text; v_requested_worker_key text:=nullif(lower(btrim(p_worker_key)),''); v_result jsonb;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  v_role:=atlas.current_farm_role(p_farm_id); v_membership_id:=atlas.current_membership_id(p_farm_id);
  if v_role is null or v_membership_id is null then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  select nullif(lower(btrim(fm.worker_key)),'') into v_worker_key from atlas.farm_memberships fm where fm.id=v_membership_id and fm.farm_id=p_farm_id and fm.active=true;
  if v_worker_key is null then raise exception 'Current Atlas worker identity was not found.' using errcode='P0002'; end if;
  if v_requested_worker_key is not null and v_requested_worker_key is distinct from v_worker_key then raise exception 'Tending may only load the signed-in membership.' using errcode='42501'; end if;
  with visible as (
    select x.* from atlas.tending_task_track_v1 x
    where x.farm_id=p_farm_id and x.task_status='open' and x.released_at is not null and x.planned_occurrence_id is not null
      and (p_due_through is null or x.due_date is null or x.due_date<=p_due_through)
      and (x.visibility_scope='farm_shared' or (x.visibility_scope='assigned_worker' and x.assigned_membership_id=v_membership_id) or (v_role='owner' and x.visibility_scope='owner' and (x.assigned_membership_id is null or x.assigned_membership_id=v_membership_id)))
      and x.gate_key in ('weed','clear','sow','plant','transplant','pot_up','harden_off','germination_check','observe','pinch','water','support','thin','prune','harvest_watch','harvest')
      and (x.object_type in ('bed','row','plot','container','tray','grow_bag') or x.object_mode='annual_production')
      and coalesce(x.care_state,'unknown') not in ('resting','suppressed')
      and not (x.gate_key in ('weed','clear') and coalesce(x.ordinary_weeding_allowed,true)=false)
  ), ranked as (
    select x.*,row_number() over(partition by x.object_id order by x.due_date nulls last,case x.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end,x.task_created_at,x.task_id) as bed_rank from visible x
  ), prepared as (
    select x.*,atlas.tending_gates_v1(x.object_id,x.crop_cycle_id,x.task_id,case when atlas.tending_unlock_label_v1(x.unlock_text,x.task_metadata,null) is not null and x.lifecycle_status<>'planned' and x.gate_key in ('weed','clear') then null else x.expected_harvest_watch_start end) as gates from ranked x where x.bed_rank=1
  ), cards as (
    select x.*,atlas.tending_card_json_v2(x.task_id,x.object_id,x.gates,true) as card from prepared x
  )
  select jsonb_build_object('generatedAt',now(),'miniGamesEnabled',false,'actionableCount',count(*)::integer,'bedCount',count(distinct object_id)::integer,'nextHarvestOn',min(case when card ? 'firstOrNextHarvestOn' then (card->>'firstOrNextHarvestOn')::date end),'cards',coalesce(jsonb_agg(card order by case section_key when 'harvest_now' then 0 when 'unlock_next' then 1 when 'protect_harvests' then 2 else 3 end,due_date nulls last,zone_sort_order,object_sort_order,object_label),'[]'::jsonb)) into v_result from cards;
  return coalesce(v_result,jsonb_build_object('generatedAt',now(),'miniGamesEnabled',false,'actionableCount',0,'bedCount',0,'cards','[]'::jsonb));
end
$function$;

CREATE OR REPLACE FUNCTION atlas.walkway_cards_v1(p_farm_id uuid, p_object_key text DEFAULT NULL::text, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_cards jsonb;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  if not atlas.is_farm_member(p_farm_id) then
    raise exception 'This farm is outside the current membership.' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'cardId', card.id,
    'cardKey', card.card_key,
    'farmId', card.farm_id,
    'zoneId', card.zone_id,
    'zoneKey', zone.stable_key,
    'zoneLabel', zone.label,
    'objectId', object.id,
    'objectKey', object.stable_key,
    'objectLabel', object.label,
    'objectType', object.object_type,
    'strategy', card.strategy,
    'targetCondition', card.target_condition,
    'lastStrategyAt', card.last_strategy_at,
    'diebackIntervalSeconds', card.dieback_interval_seconds,
    'diebackReviewAt', card.dieback_review_at,
    'observedCondition', card.observed_condition,
    'observedAt', card.observed_at,
    'currentOccurrenceId', occurrence.id,
    'currentOccurrenceTitle', occurrence.title,
    'currentOccurrenceState', occurrence.state,
    'currentTaskId', coalesce(task.id, occurrence.released_task_id),
    'currentTaskTitle', coalesce(task.title, occurrence.title),
    'currentTaskStatus', coalesce(task.status, case when occurrence.state = 'released' then 'open' else occurrence.state end),
    'metadata', card.metadata,
    'derived', atlas.walkway_card_state_v1(card.id, p_as_of)
      || jsonb_build_object(
        'releaseState', occurrence.state,
        'releaseCapacityBlocked', occurrence.state = 'eligible' and occurrence.released_task_id is null
      )
  ) order by coalesce(object.metadata->>'clock_position', lpad(object.sort_order::text, 8, '0')), object.label), '[]'::jsonb)
  into v_cards
  from atlas.walkway_cards card
  join atlas.growing_objects object on object.id = card.object_id
  left join atlas.zones zone on zone.id = card.zone_id
  left join atlas.planned_work_occurrences occurrence on occurrence.id = card.current_occurrence_id
  left join atlas.tasks task on task.id = card.current_task_id
  where card.farm_id = p_farm_id
    and card.active
    and (p_object_key is null or object.stable_key = p_object_key);

  return jsonb_build_object(
    'contractVersion', 'walkway_cards_v1',
    'farmId', p_farm_id,
    'asOf', coalesce(p_as_of, now()),
    'cards', v_cards
  );
end;
$function$;

CREATE OR REPLACE FUNCTION atlas.weed_card_task_focus_v1(p_task_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_task atlas.tasks%rowtype;
  v_card atlas.weed_cards%rowtype;
  v_pass atlas.weed_passes%rowtype;
  v_object atlas.growing_objects%rowtype;
  v_state atlas.object_state%rowtype;
  v_latest_session atlas.weed_sessions%rowtype;
  v_zone_label text;
  v_role text;
  v_membership_id uuid;
  v_sessions jsonb;
  v_occupancy jsonb;
  v_condition text;
  v_state_logged_on date;
  v_state_condition text;
  v_state_last_weeded_on date;
  v_last_weeded_on date;
  v_last_logged_condition text;
  v_last_logged_on date;
  v_bed_use_category text;
  v_bed_trail jsonb;
begin
  select t.* into v_task from atlas.tasks t where t.id=p_task_id;
  if v_task.id is null then raise exception 'Source unavailable to this Person.' using errcode='42501'; end if;

  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(v_task.farm_id);

  v_role := atlas.current_farm_role(v_task.farm_id);
  v_membership_id := atlas.current_membership_id(v_task.farm_id);
  if not atlas.is_farm_owner(v_task.farm_id)
     and not (v_role in ('farm_hand','manager') and v_membership_id is not null and v_task.assigned_membership_id=v_membership_id)
  then
    raise exception 'This Weed Card is not available to the signed-in farm member.' using errcode='42501';
  end if;

  select c.* into v_card
  from atlas.weed_cards c join atlas.task_objects x on x.object_id=c.object_id
  where x.task_id=p_task_id limit 1;
  if v_card.id is null then return null; end if;

  select p.* into v_pass from atlas.weed_passes p
  where p.weed_card_id=v_card.id and p.status='active' limit 1;

  v_condition := coalesce(v_pass.current_condition,atlas.weed_card_condition_from_text_v1(v_task.metadata->>'condition'),v_card.current_condition);
  select go.* into v_object from atlas.growing_objects go where go.id=v_card.object_id;
  select os.* into v_state from atlas.object_state os where os.object_id=v_object.id;
  select z.label into v_zone_label from atlas.zones z where z.id=v_object.zone_id;
  v_occupancy := atlas.object_crop_occupancy_v1(v_object.id);

  select ws.* into v_latest_session
  from atlas.weed_sessions ws
  where ws.weed_card_id=v_card.id
  order by ws.work_date desc, ws.recorded_at desc
  limit 1;

  v_state_last_weeded_on := case
    when v_state.last_weeded_at is not null
      then (v_state.last_weeded_at at time zone 'America/Chicago')::date
    else null
  end;

  v_last_weeded_on := case
    when v_latest_session.work_date is null then v_state_last_weeded_on
    when v_state_last_weeded_on is null then v_latest_session.work_date
    else greatest(v_latest_session.work_date,v_state_last_weeded_on)
  end;

  v_state_logged_on := coalesce(
    case
      when v_state.last_checked_at is not null
        then (v_state.last_checked_at at time zone 'America/Chicago')::date
      else null
    end,
    case
      when coalesce(v_state.metadata->>'photo_truth_date','') ~ '^\d{4}-\d{2}-\d{2}$'
        then (v_state.metadata->>'photo_truth_date')::date
      else null
    end
  );

  v_state_condition := case lower(coalesce(v_state.weed_pressure,''))
    when 'high' then 'heavy'
    when 'heavy' then 'heavy'
    when 'severe' then 'heavy'
    when 'medium' then 'heavy'
    when 'moderate' then 'heavy'
    when 'low' then 'mostly_clear'
    when 'light' then 'mostly_clear'
    when 'maintained' then 'clear'
    when 'none' then 'clear'
    when 'clear' then 'clear'
    else null
  end;

  if v_latest_session.id is not null
     and (v_state_logged_on is null or v_latest_session.work_date >= v_state_logged_on)
  then
    v_last_logged_on := v_latest_session.work_date;
    v_last_logged_condition := coalesce(v_latest_session.condition_after,v_state_condition,v_condition);
  elsif v_state_logged_on is not null then
    v_last_logged_on := v_state_logged_on;
    v_last_logged_condition := coalesce(v_state_condition,v_condition,v_latest_session.condition_after);
  else
    v_last_logged_on := coalesce(v_latest_session.work_date,v_last_weeded_on);
    v_last_logged_condition := coalesce(v_latest_session.condition_after,v_state_condition,v_condition);
  end if;

  v_bed_use_category := coalesce(
    nullif(v_object.metadata->>'current_bed_use_category',''),
    case lower(coalesce(v_object.metadata->>'use',''))
      when 'cut_flower_production' then 'Cut flower production'
      when 'perennial_cut_flower' then 'Perennial cut flower'
      when 'hospitality' then 'Hospitality'
      when 'landscaping' then 'Landscaping'
      when 'landscape' then 'Landscaping'
      when 'production' then 'Production'
      else null
    end,
    case lower(coalesce(v_object.metadata->>'production_lane',''))
      when 'cut_flower' then 'Cut flower production'
      when 'production' then 'Production'
      else null
    end,
    case lower(coalesce(v_object.metadata->>'management_group',''))
      when 'production' then 'Production'
      when 'hospitality' then 'Hospitality'
      when 'landscaping' then 'Landscaping'
      else null
    end,
    case
      when lower(coalesce(v_object.metadata->>'perennial_zone','')) in ('true','1','yes','y') then 'Perennial bed'
      when lower(coalesce(v_object.metadata->>'landscape_strip','')) in ('true','1','yes','y') then 'Landscaping'
      when lower(coalesce(v_state.metadata->>'role','')) like '%mixed%' then 'Mixed bed'
      when lower(coalesce(v_state.metadata->>'purpose','')) like '%hospitality%' then 'Hospitality'
      when lower(coalesce(v_state.metadata->>'purpose','')) like '%landscap%' then 'Landscaping'
      when lower(coalesce(v_state.metadata->>'purpose','')) like '%production%' then 'Production'
      else null
    end,
    'Unclassified'
  );

  with candidates as (
    select distinct on (t.id)
      t.id as task_id,
      t.title,
      t.action_key,
      coalesce(t.completed_at::date,t.due_date,t.created_at::date) as event_date,
      linked.crop_cycle_id,
      coalesce(linked.crop_label,matched_perennial.crop_label) as crop_label,
      coalesce(linked.life_cycle,matched_perennial.life_cycle) as life_cycle,
      case
        when nullif(v_object.metadata->>'weed_trail_primary_crop_cycle_id','') is not null
         and linked.crop_cycle_id::text=v_object.metadata->>'weed_trail_primary_crop_cycle_id' then 0
        when lower(coalesce(linked.life_cycle,matched_perennial.life_cycle,''))='perennial' then 1
        else 2
      end as priority
    from atlas.task_objects x
    join atlas.tasks t on t.id=x.task_id
    left join lateral (
      select cc.id as crop_cycle_id, cc.crop_label, cp.life_cycle
      from atlas.task_crop_cycles tcc
      join atlas.crop_cycles cc on cc.id=tcc.crop_cycle_id
      left join atlas.crop_profiles cp on cp.id=cc.crop_profile_id
      where tcc.task_id=t.id
      order by
        (nullif(v_object.metadata->>'weed_trail_primary_crop_cycle_id','') is not null
          and cc.id::text=v_object.metadata->>'weed_trail_primary_crop_cycle_id') desc,
        (lower(coalesce(cp.life_cycle,''))='perennial') desc,
        tcc.created_at
      limit 1
    ) linked on true
    left join lateral (
      select cc.crop_label, cp.life_cycle
      from atlas.crop_cycles cc
      left join atlas.crop_profiles cp on cp.id=cc.crop_profile_id
      where cc.object_id=v_object.id
        and cc.lifecycle_status='active'
        and lower(coalesce(cp.life_cycle,''))='perennial'
        and lower(t.title) like '%'||lower(cc.crop_label)||'%'
      order by cc.created_at
      limit 1
    ) matched_perennial on linked.crop_cycle_id is null
    where x.object_id=v_object.id
      and t.status='done'
      and coalesce(t.action_key,'') <> 'weed'
      and coalesce(t.task_type,'') <> 'weeding'
      and (
        lower(coalesce(t.action_key,'')) in ('sow','plant','transplant','divide','deadhead','cut_back','prune','tend','perennial_tending')
        or lower(coalesce(t.task_type,'')) in ('sowing','planting','transplanting','perennial_tending')
      )
    order by t.id, priority, event_date desc
  ), ranked as (
    select * from candidates
    order by priority, event_date desc, title
    limit 5
  )
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'taskId',r.task_id,
    'eventKind',case
      when lower(coalesce(r.action_key,''))='sow' then 'Sown'
      when lower(coalesce(r.action_key,''))='plant' then 'Planted'
      when lower(coalesce(r.action_key,''))='transplant' then 'Transplanted'
      when lower(coalesce(r.action_key,''))='deadhead' then 'Deadheaded'
      when lower(coalesce(r.action_key,'')) in ('divide','cut_back','prune','tend','perennial_tending') then 'Tended'
      else 'Worked'
    end,
    'cropCycleId',r.crop_cycle_id,
    'cropLabel',r.crop_label,
    'title',r.title,
    'lifeCycle',r.life_cycle,
    'eventDate',r.event_date
  )) order by r.priority,r.event_date desc),'[]'::jsonb)
  into v_bed_trail
  from ranked r;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,'workDate',s.work_date,'minutes',s.minutes,'minutesKnown',s.minutes_known,
    'conditionBefore',s.condition_before,'conditionAfter',s.condition_after,'note',s.note,'recordedAt',s.recorded_at
  ) order by s.recorded_at desc),'[]'::jsonb)
  into v_sessions
  from (
    select ws.* from atlas.weed_sessions ws
    where ws.weed_card_id=v_card.id and (v_pass.id is null or ws.weed_pass_id=v_pass.id)
    order by ws.recorded_at desc limit 12
  ) s;

  return jsonb_build_object(
    'taskId',v_task.id,'taskStatus',v_task.status,'taskDueDate',v_task.due_date,
    'cardId',v_card.id,'passId',v_pass.id,'passStatus',coalesce(v_pass.status,'closed'),
    'objectId',v_object.id,'objectKey',v_object.stable_key,'objectLabel',v_object.label,
    'zoneLabel',coalesce(v_zone_label,'Elm Farm'),'occupancyGroups',coalesce(v_occupancy->'groups','[]'::jsonb),
    'condition',v_condition,'targetCondition',coalesce(v_pass.target_condition,v_card.target_condition),
    'lastWeededOn',v_last_weeded_on,
    'lastLoggedCondition',v_last_logged_condition,
    'lastLoggedOn',v_last_logged_on,
    'bedUseCategory',v_bed_use_category,
    'bedTrail',v_bed_trail,
    'totalMinutes',coalesce(v_pass.total_minutes,0),
    'sessionCount',case when v_pass.id is null then 0 else jsonb_array_length(v_sessions) end,
    'nextReviewOn',v_card.next_review_on,
    'sessions',case when v_pass.id is null then '[]'::jsonb else v_sessions end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION atlas.weeding_cycle_v1(p_farm_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_role text;
  v_membership_id uuid;
  v_result jsonb;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  v_role := atlas.current_farm_role(p_farm_id);
  if v_role is null then
    raise exception 'Active farm membership required.' using errcode = '42501';
  end if;

  v_membership_id := atlas.current_membership_id(p_farm_id);

  with hierarchy(rank, key, label, mode) as (
    values
      (1, 'field_rows', 'Field Rows', 'weeding'),
      (2, 'main_garden', 'Main Garden', 'weeding'),
      (3, 'berry_walk_flower_rows', 'Berry Walk', 'weeding'),
      (4, 'berry_walk_crescent_moon', 'Berry Walk Crescent Moon', 'weeding'),
      (5, 'entry_billboard', 'Entry Billboard', 'weeding'),
      (6, 'perennial_landscaping', 'Perennial beds + landscaping', 'weeding'),
      (7, 'barn_beds', 'Barn Beds', 'weeding'),
      (8, 'u_pick', 'U-Pick', 'fall_tillage'),
      (9, 'lilac_haven', 'Lilac Haven', 'weeding')
  ), visible_queue as (
    select
      qi.position,
      qi.state,
      qi.initial_batch,
      t.id as task_id,
      t.title,
      t.status as task_status,
      t.due_date,
      coalesce(
        nullif(t.metadata ->> 'display_subject', ''),
        nullif(t.metadata ->> 'collection_label', ''),
        go.label,
        t.title
      ) as label,
      coalesce(nullif(t.metadata ->> 'condition', ''), 'moderate') as condition,
      case
        when coalesce(t.metadata ->> 'estimated_minutes', '') ~ '^[0-9]+$'
          then (t.metadata ->> 'estimated_minutes')::integer
        else null
      end as estimated_minutes,
      go.stable_key as object_key
    from atlas.task_release_queue_items qi
    join atlas.tasks t on t.id = qi.task_id
    left join atlas.maintenance_objects mo on mo.id = qi.maintenance_object_id
    left join atlas.growing_objects go on go.id = mo.object_id
    where qi.farm_id = p_farm_id
      and qi.queue_key = 'field_rows_weeding_rotation'
      and (
        (v_role = 'owner' and t.visibility_scope in ('owner', 'management', 'assigned_worker', 'farm_shared'))
        or (v_role = 'manager' and t.visibility_scope in ('management', 'assigned_worker', 'farm_shared'))
        or (
          v_role = 'farm_hand'
          and (
            (t.visibility_scope = 'assigned_worker' and t.assigned_membership_id = v_membership_id)
            or t.visibility_scope = 'farm_shared'
          )
        )
      )
  ), stats as (
    select
      coalesce(nullif(mo.metadata ->> 'owner_hierarchy_rank', '')::integer, 99) as rank,
      count(*)::integer as total_objects,
      count(*) filter (where mo.active)::integer as active_objects,
      count(*) filter (
        where mo.active
          and mo.condition in ('heavy', 'reset', 'moderate')
          and coalesce(mo.remaining_effort_minutes, 0) > 0
      )::integer as needs_attention,
      count(*) filter (where mo.active and mo.condition = 'maintained')::integer as maintained,
      count(*) filter (where not mo.active)::integer as inactive
    from atlas.maintenance_objects mo
    where mo.farm_id = p_farm_id
      and mo.maintenance_type = 'weed'
    group by 1
  ), queue_counts as (
    select
      count(*) filter (where state = 'active')::integer as active_count,
      count(*) filter (where state = 'queued')::integer as queued_count,
      count(*) filter (where state = 'completed')::integer as completed_count
    from visible_queue
  ), resolved as (
    select
      case
        when qc.active_count + qc.queued_count > 0 then 1
        else coalesce((
          select min(h.rank)
          from hierarchy h
          left join stats s on s.rank = h.rank
          where h.mode = 'weeding'
            and coalesce(s.needs_attention, 0) > 0
        ), 1)
      end as current_rank,
      qc.active_count,
      qc.queued_count,
      qc.completed_count
    from queue_counts qc
  ), next_rank as (
    select min(h.rank) as rank
    from hierarchy h
    left join stats s on s.rank = h.rank
    cross join resolved r
    where h.rank > r.current_rank
      and h.mode = 'weeding'
      and coalesce(s.needs_attention, 0) > 0
  )
  select jsonb_build_object(
    'summary', jsonb_build_object(
      'current_rank', r.current_rank,
      'current_zone_label', (select label from hierarchy where rank = r.current_rank),
      'next_rank', nr.rank,
      'next_zone_label', (select label from hierarchy where rank = nr.rank),
      'active_count', r.active_count,
      'queued_count', r.queued_count,
      'completed_count', r.completed_count,
      'queue_next_label', (
        select label
        from visible_queue
        where state = 'queued'
        order by position
        limit 1
      )
    ),
    'queue', coalesce((
      select jsonb_agg(jsonb_build_object(
        'position', q.position,
        'state', q.state,
        'initial_batch', q.initial_batch,
        'task_id', q.task_id,
        'title', q.title,
        'task_status', q.task_status,
        'due_date', q.due_date,
        'label', q.label,
        'condition', q.condition,
        'estimated_minutes', q.estimated_minutes,
        'object_key', q.object_key
      ) order by q.position)
      from visible_queue q
    ), '[]'::jsonb),
    'hierarchy', coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', h.rank,
        'key', h.key,
        'label', h.label,
        'mode', h.mode,
        'total_objects', coalesce(s.total_objects, 0),
        'active_objects', coalesce(s.active_objects, 0),
        'needs_attention', coalesce(s.needs_attention, 0),
        'maintained', coalesce(s.maintained, 0),
        'inactive', coalesce(s.inactive, 0),
        'attention_labels', coalesce((
          select jsonb_agg(x.label order by x.owner_priority desc, x.label)
          from (
            select go.label, mo.owner_priority
            from atlas.maintenance_objects mo
            join atlas.growing_objects go on go.id = mo.object_id
            where mo.farm_id = p_farm_id
              and mo.maintenance_type = 'weed'
              and coalesce(nullif(mo.metadata ->> 'owner_hierarchy_rank', '')::integer, 99) = h.rank
              and mo.active
              and mo.condition in ('heavy', 'reset', 'moderate')
              and coalesce(mo.remaining_effort_minutes, 0) > 0
            order by mo.owner_priority desc, go.label
            limit 4
          ) x
        ), '[]'::jsonb)
      ) order by h.rank)
      from hierarchy h
      left join stats s on s.rank = h.rank
    ), '[]'::jsonb)
  )
  into v_result
  from resolved r
  cross join next_rank nr;

  return coalesce(v_result, jsonb_build_object(
    'summary', jsonb_build_object(
      'current_rank', 1,
      'current_zone_label', 'Field Rows',
      'next_rank', 2,
      'next_zone_label', 'Main Garden',
      'active_count', 0,
      'queued_count', 0,
      'completed_count', 0,
      'queue_next_label', null
    ),
    'queue', '[]'::jsonb,
    'hierarchy', '[]'::jsonb
  ));
end;
$function$;

CREATE OR REPLACE FUNCTION atlas.weeding_rhythm_pilot_v1(p_farm_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_result jsonb;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  if auth.uid() is null or not atlas.is_farm_member(p_farm_id) then
    raise exception 'Active farm membership is required to read the weeding rhythm pilot.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'contractVersion', 'weeding_rhythm_pilot_v1',
    'farmId', p_farm_id,
    'rhythmKey', 'weed_stewardship',
    'evaluatedAt', now(),
    'selectionRule', 'owner_authored_rulebook_clock',
    'physicalConditionRule', 'observation_only',
    'subjects', coalesce(jsonb_agg(jsonb_build_object(
      'stateId', state.id,
      'objectId', object.id,
      'objectKey', object.stable_key,
      'objectLabel', object.label,
      'zoneId', zone.id,
      'zoneKey', zone.stable_key,
      'zoneLabel', zone.label,
      'state', state.state,
      'leaseStartedAt', state.lease_started_at,
      'warningAt', state.warning_at,
      'dueAt', state.due_at,
      'failureAt', state.failure_at,
      'nextBoundaryAt', case state.state
        when 'resting' then state.warning_at
        when 'coming_due' then state.due_at
        when 'due' then state.failure_at
        else null
      end,
      'lastEvaluatedAt', state.last_evaluated_at,
      'rule', jsonb_build_object(
        'ruleId', rule.id,
        'ruleKey', rule.rule_key,
        'version', rule.version,
        'label', rule.label,
        'class', rule.metadata ->> 'ruleClass',
        'validityIntervalSeconds', rule.validity_interval_seconds,
        'warningWindowSeconds', rule.warning_window_seconds,
        'graceWindowSeconds', rule.grace_window_seconds,
        'timezoneName', coalesce(rule.metadata ->> 'timezoneName', 'America/Chicago'),
        'boundaryMode', coalesce(rule.metadata ->> 'boundaryMode', 'exact_timestamp'),
        'qualifyingTouches', rule.qualifying_touches,
        'failureConsequence', rule.failure_consequence,
        'playerRouting', rule.player_routing
      ),
      'lastSatisfaction', case when satisfaction.id is null then null else jsonb_build_object(
        'satisfactionId', satisfaction.id,
        'kind', satisfaction.satisfaction_kind,
        'satisfiedAt', satisfaction.satisfied_at,
        'renewalIntervalSeconds', satisfaction.renewal_interval_seconds,
        'sourceKind', satisfaction.source_kind,
        'sourceId', satisfaction.source_id,
        'sourceEvent', satisfaction.source_event,
        'evidence', satisfaction.evidence
      ) end,
      'currentTask', case when task.id is null then null else jsonb_build_object(
        'taskId', task.id,
        'title', task.title,
        'status', task.status,
        'dueDate', task.due_date,
        'priority', task.priority,
        'actionKey', task.action_key,
        'workClass', task.work_class
      ) end,
      'consequence', jsonb_build_object(
        'active', state.state = 'fallen_out_of_rhythm',
        'restoreRequired', coalesce((rule.failure_consequence ->> 'restoreRequired')::boolean, false),
        'blockScope', rule.failure_consequence ->> 'blockScope',
        'blockedActionKeys', coalesce(rule.failure_consequence -> 'blocksActionKeys', '[]'::jsonb),
        'physicalConditionClaim', rule.failure_consequence ->> 'physicalConditionClaim'
      ),
      'physicalCondition', jsonb_build_object(
        'known', maintenance.condition_reported_at is not null,
        'value', case when maintenance.condition_reported_at is not null then maintenance.condition else null end,
        'reportedAt', maintenance.condition_reported_at,
        'source', case when maintenance.condition_reported_at is not null then maintenance.estimate_source else null end,
        'authority', 'separate_observation_state',
        'inferredFromClock', false
      ),
      'explanation', jsonb_build_object(
        'governedBy', 'owner_authored_rule',
        'effectiveBindingId', binding.id,
        'effectiveBindingKey', binding.binding_key,
        'inheritanceLayer', binding.inheritance_layer,
        'basis', 'latest_qualifying_satisfaction_plus_owner_interval',
        'notBasedOn', jsonb_build_array('generic_recurrence', 'task_title', 'unobserved_physical_condition'),
        'pilotKey', state.metadata ->> 'pilotKey'
      )
    ) order by
      case state.state
        when 'fallen_out_of_rhythm' then 0
        when 'due' then 1
        when 'recovering' then 2
        when 'coming_due' then 3
        when 'resting' then 4
        when 'uninitialized' then 5
        else 6
      end,
      state.due_at nulls last,
      object.sort_order,
      object.label), '[]'::jsonb)
  )
  into v_result
  from atlas.rhythm_state state
  join atlas.rhythm_rules rule on rule.id = state.rhythm_rule_id
  join atlas.rhythm_bindings binding on binding.id = state.rhythm_binding_id
  join atlas.growing_objects object
    on state.subject_kind = 'growing_object' and object.id = state.subject_id
  left join atlas.zones zone on zone.id = object.zone_id
  left join atlas.rhythm_satisfactions satisfaction
    on satisfaction.id = state.last_qualifying_satisfaction_id
  left join atlas.tasks task on task.id = state.current_task_id
  left join lateral (
    select maintenance_object.*
    from atlas.maintenance_objects maintenance_object
    where maintenance_object.object_id = object.id
      and maintenance_object.maintenance_type = 'weed'
    order by maintenance_object.created_at
    limit 1
  ) maintenance on true
  where state.farm_id = p_farm_id
    and state.rhythm_key = 'weed_stewardship'
    and state.metadata ->> 'pilotKey' = 'elm_weeding_pilot_v1'
    and atlas.can_read_rhythm_state_v1(state.id);

  return coalesce(v_result, jsonb_build_object(
    'contractVersion', 'weeding_rhythm_pilot_v1',
    'farmId', p_farm_id,
    'rhythmKey', 'weed_stewardship',
    'evaluatedAt', now(),
    'selectionRule', 'owner_authored_rulebook_clock',
    'physicalConditionRule', 'observation_only',
    'subjects', '[]'::jsonb
  ));
end;
$function$;
COMMIT;
