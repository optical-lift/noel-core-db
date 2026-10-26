BEGIN;
-- Protect inherited wide farm projections from old role/seat-based disclosure.
-- Narrow connected-Person subject readers are a separate source-authorized path.
-- Never publish filtered counts, notes, metadata, crop cycles or history by
-- granting arbitrary authenticated farm membership.
CREATE OR REPLACE FUNCTION atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_org uuid;
  v_ledger uuid;
BEGIN
  -- An old farm membership/role is not Ledger disclosure authority.
  -- Use exactly the signed canonical Person and primary governing Ledger.
  IF auth.uid() IS NULL OR
    (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready' OR
    atlas.current_person_id_v1() IS NULL THEN
    RAISE EXCEPTION 'Source unavailable to this Person.' USING ERRCODE='42501';
  END IF;
  SELECT f.organization_id, lop.ledger_id INTO v_org,v_ledger
  FROM atlas.farms f
  JOIN atlas.ledger_organization_participations lop
    ON lop.organization_id=f.organization_id
    AND lop.participation_kind='governing'
    AND lop.is_compatibility_primary
    AND lop.status='active' AND lop.ended_at IS NULL
  JOIN atlas.ledgers al ON al.id=lop.ledger_id AND al.status='active'
  JOIN ledger.ledgers nl ON nl.id=lop.ledger_id
    AND nl.ledger_state='active' AND nl.retired_at IS NULL
  WHERE f.id=p_farm_id
  ORDER BY lop.ledger_id LIMIT 1;
  IF v_org IS NULL OR v_ledger IS NULL THEN
    RAISE EXCEPTION 'Source unavailable to this Person.' USING ERRCODE='42501';
  END IF;
  -- A role, membership, Ledger seat, or credential alone never grants
  -- full metadata, farm history, crop placements or aggregate counts.
  BEGIN
    PERFORM atlas.company_work_native_ledger_owner_self_v1(v_org,v_ledger);
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Source unavailable to this Person.' USING ERRCODE='42501';
  END;
END
$function$;
REVOKE ALL ON FUNCTION atlas.require_governed_farm_full_disclosure_self_v1(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION atlas.zone_registry_source_v1(p_farm_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);

  return jsonb_build_object(
    'zones', coalesce((
      select jsonb_agg(to_jsonb(source_row) order by source_row.sort_order nulls last, source_row.label)
      from (
        select z.id, z.stable_key, z.label, z.zone_type, z.mode_bias,
               z.goal_text, z.current_state, z.sort_order, z.metadata
        from atlas.zones z
        where z.farm_id = p_farm_id
      ) source_row
    ), '[]'::jsonb),
    'objects', coalesce((
      select jsonb_agg(to_jsonb(source_row) order by source_row.sort_order nulls last, source_row.label)
      from (
        select go.id, go.zone_id, go.stable_key, go.label, go.object_type,
               go.object_mode, go.length_ft, go.width_ft, go.area_sqft,
               go.guest_visible, go.sort_order, go.metadata,
               os.life_status, os.presentability, os.active_task_count,
               os.decision_required, os.metadata as state_metadata
        from atlas.growing_objects go
        left join atlas.object_state os on os.object_id = go.id
        where go.farm_id = p_farm_id
      ) source_row
    ), '[]'::jsonb),
    'contents', coalesce((
      select jsonb_agg(to_jsonb(source_row) order by source_row.planted_date desc nulls last, source_row.id)
      from (
        select oc.id, oc.object_id, oc.content_label, oc.content_type, oc.variety,
               oc.planted_date, oc.status, oc.confidence, oc.start_method,
               oc.germinated_date, oc.pinch_required, oc.pinch_note,
               oc.bloom_start_date, oc.clear_bed_date, oc.next_crop_planned,
               oc.expected_germination_start, oc.expected_germination_end,
               oc.expected_harvest_watch_start, oc.expected_harvest_watch_end,
               oc.expected_clear_date, oc.note
        from atlas.object_contents oc
        join atlas.growing_objects go on go.id = oc.object_id
        where go.farm_id = p_farm_id
      ) source_row
    ), '[]'::jsonb),
    'cropCycles', coalesce((
      select jsonb_agg(to_jsonb(source_row) order by source_row.sown_date desc nulls last, source_row.crop_cycle_id)
      from (
        select v.crop_cycle_id, v.object_id, v.crop_label, v.variety,
               v.cycle_state, v.lifecycle_status, v.sown_date, v.planted_date,
               v.germination_checked_date, v.expected_germination_start,
               v.expected_germination_end, v.harvest_started_date,
               v.last_harvest_date, v.cleared_date,
               v.expected_harvest_watch_start, v.expected_harvest_watch_end,
               v.expected_clear_date, v.crop_profile_stable_key,
               v.default_planting_method, v.note
        from atlas.v_crop_cycle_registry v
        where v.farm_id = p_farm_id
          and v.lifecycle_status = 'active'
      ) source_row
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(to_jsonb(source_row) order by source_row.event_date, source_row.id)
      from (
        select e.id, e.object_id, e.object_content_id, e.event_type,
               e.event_date, e.note, e.metadata
        from atlas.object_activity_events e
        where e.farm_id = p_farm_id
      ) source_row
    ), '[]'::jsonb)
  );
end;
$function$

CREATE OR REPLACE FUNCTION atlas.object_crop_bed_map_v1(p_object_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
DECLARE
  v_object atlas.growing_objects%rowtype;
  v_frame atlas.object_map_frames%rowtype;
  v_rows jsonb;
  v_geometry jsonb;
BEGIN
  SELECT * INTO v_object FROM atlas.growing_objects WHERE id = p_object_id;
  IF v_object.id IS NULL THEN
    RAISE EXCEPTION 'Source unavailable to this Person.' USING ERRCODE='42501';
  END IF;
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(v_object.farm_id);

  SELECT * INTO v_frame FROM atlas.object_map_frames WHERE object_id = v_object.id;

  IF v_object.geometry->>'schema' = 'atlas_object_geometry_v1' THEN
    v_geometry := v_object.geometry;
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'placementId', q.placement_id,
    'cropCycleId', q.crop_cycle_id,
    'displayLabel', q.display_label,
    'stage', q.stage,
    'stageLabel', atlas.crop_stage_label_v1(q.stage),
    'establishmentDate', q.establishment_date,
    'establishmentKind', q.establishment_kind,
    'lifeCycle', CASE WHEN q.is_perennial THEN 'perennial' ELSE coalesce(q.life_cycle, 'annual') END,
    'placementMode', q.placement_mode,
    'placementLabel', q.placement_label,
    'rowCount', q.row_count,
    'rowLengthFt', q.row_length_ft,
    'areaSqft', q.area_sqft,
    'explicitPlantCount', q.explicit_plant_count,
    'clumpCount', q.clump_count,
    'expectedQuantity', q.expected_quantity,
    'expectedQuantityKind', q.expected_quantity_kind,
    'observedQuantity', q.observed_quantity,
    'observedQuantityUnit', q.observed_quantity_unit,
    'standPercent', q.stand_percent,
    'anchorEdge', q.anchor_edge,
    'longStartFt', q.long_start_ft,
    'longEndFt', q.long_end_ft,
    'crossStartFt', q.cross_start_ft,
    'crossEndFt', q.cross_end_ft,
    'positionConfidence', q.position_confidence
  )) ORDER BY q.anchor_edge NULLS LAST, q.display_label, q.crop_cycle_id), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      p.id placement_id,
      cc.id crop_cycle_id,
      CASE
        WHEN lower(cc.crop_label) = 'sunflower' AND nullif(btrim(coalesce(cc.variety, '')), '') IS NOT NULL
          THEN btrim(cc.variety) || ' sunflower'
        WHEN lower(cc.crop_label) IN ('bearded iris', 'iris') THEN 'Iris'
        ELSE cc.crop_label
      END display_label,
      coalesce(obs.stage, atlas.crop_stage_from_state_v1(cc.cycle_state, cp.life_cycle)) stage,
      coalesce(cc.planted_date, cc.sown_date) establishment_date,
      CASE WHEN cc.planted_date IS NOT NULL THEN 'planted' WHEN cc.sown_date IS NOT NULL THEN 'sown' ELSE NULL END establishment_kind,
      (
        lower(coalesce(cp.life_cycle, '')) = 'perennial'
        OR p.placement_mode IN ('edge_strip', 'clumps')
           AND lower(cc.crop_label) IN ('iris', 'bearded iris', 'lemon balm', 'yarrow', 'salvia')
      ) is_perennial,
      cp.life_cycle,
      p.placement_mode,
      p.placement_label,
      p.row_count,
      p.row_length_ft,
      p.area_sqft,
      p.explicit_plant_count,
      p.clump_count,
      p.expected_quantity,
      p.expected_quantity_kind,
      obs.observed_quantity,
      obs.quantity_unit observed_quantity_unit,
      obs.stand_percent,
      p.anchor_edge,
      p.long_start_ft,
      p.long_end_ft,
      p.cross_start_ft,
      p.cross_end_ft,
      p.position_confidence
    FROM atlas.crop_cycles cc
    LEFT JOIN atlas.crop_profiles cp ON cp.id = cc.crop_profile_id
    LEFT JOIN LATERAL (
      SELECT p0.*
      FROM atlas.crop_placements p0
      WHERE p0.crop_cycle_id = cc.id
      ORDER BY (p0.position_confidence = 'high') DESC,
               (p0.expected_quantity_kind = 'recorded') DESC,
               p0.created_at
      LIMIT 1
    ) p ON true
    LEFT JOIN LATERAL (
      SELECT o.stage, o.observed_quantity, o.quantity_unit, o.stand_percent
      FROM atlas.crop_observations o
      WHERE o.crop_cycle_id = cc.id
      ORDER BY o.observed_date DESC NULLS LAST, o.created_at DESC
      LIMIT 1
    ) obs ON true
    WHERE cc.object_id = p_object_id
      AND cc.lifecycle_status = 'active'
      AND coalesce(obs.stage, atlas.crop_stage_from_state_v1(cc.cycle_state, cp.life_cycle), 'unknown')
          NOT IN ('cleared', 'failed', 'dead', 'absent', 'abandoned', 'archived', 'removed', 'inactive')
  ) q;

  RETURN jsonb_build_object(
    'objectId', v_object.id,
    'objectKey', v_object.stable_key,
    'objectLabel', v_object.label,
    'lengthFt', v_object.length_ft,
    'widthFt', v_object.width_ft,
    'areaSqft', v_object.area_sqft,
    'geometry', v_geometry,
    'referenceGeometry', v_geometry->'reference',
    'orientationKnown', v_frame.object_id IS NOT NULL AND v_frame.long_axis <> 'unknown',
    'longAxis', coalesce(v_frame.long_axis, 'unknown'),
    'leftEdge', v_frame.left_edge,
    'rightEdge', v_frame.right_edge,
    'topEdge', v_frame.top_edge,
    'bottomEdge', v_frame.bottom_edge,
    'orientationSource', v_frame.orientation_source,
    'placements', coalesce(v_rows, '[]'::jsonb)
  );
END;
$function$

CREATE OR REPLACE FUNCTION atlas.farm_care_zone_v1(p_farm_id uuid, p_zone_key text, p_history_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_zone atlas.zones%rowtype;
  v_limit integer := least(greatest(coalesce(p_history_limit,20),1),100);
  v_result jsonb;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);

  select * into v_zone
  from atlas.zones
  where farm_id=p_farm_id
    and stable_key=p_zone_key;

  if not found then
    raise exception 'Zone % was not found for farm %.',p_zone_key,p_farm_id
      using errcode='P0002';
  end if;

  with objects as (
    select *
    from atlas.farm_care_object_projection_v1
    where farm_id=p_farm_id
      and zone_id=v_zone.id
  ),
  object_groups as (
    select coalesce(jsonb_object_agg(x.care_state,x.cards),'{}'::jsonb) as groups
    from (
      select
        care_state,
        jsonb_agg(atlas.farm_care_object_card_v1(object_id)
          order by object_sort_order,object_label) as cards
      from objects
      group by care_state
    ) x
  ),
  released as (
    select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'taskId',r.task_id,
      'title',r.title,
      'status',r.status,
      'dueDate',r.due_date,
      'objectIds',to_jsonb(r.object_ids),
      'estimatedMinutes',r.estimated_minutes,
      'action',r.action_label,
      'subject',r.subject_label,
      'lane',r.intervention_lane,
      'reasonLines',r.reason_lines,
      'desiredResult',r.desired_result,
      'doneDefinition',r.done_definition,
      'unlocks',r.unlock_text
    )) order by r.due_date nulls last,r.title),'[]'::jsonb) as cards
    from atlas.farm_care_released_intervention_v1 r
    where r.farm_id=p_farm_id
      and r.zone_id=v_zone.id
  ),
  planned as (
    select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'occurrenceId',p.occurrence_id,
      'objectId',p.object_id,
      'title',p.title,
      'plannedDueDate',p.planned_due_date,
      'notBeforeDate',p.not_before_date,
      'state',p.state,
      'estimatedMinutes',p.estimated_minutes,
      'desiredResult',p.desired_result,
      'doneDefinition',p.done_definition,
      'source','legacy_planned_occurrence'
    )) order by p.planned_due_date nulls last,p.title),'[]'::jsonb) as cards
    from atlas.farm_care_planned_intervention_v1 p
    where p.farm_id=p_farm_id
      and p.zone_id=v_zone.id
  ),
  history as (
    select coalesce(jsonb_agg(x.card order by x.occurred_at desc),'[]'::jsonb) as cards
    from (
      select
        h.occurred_at,
        jsonb_strip_nulls(jsonb_build_object(
          'historyId',h.id,
          'occurredAt',h.occurred_at,
          'objectId',h.object_id,
          'objectKey',go.stable_key,
          'objectLabel',go.label,
          'previousState',h.previous_state,
          'previousStateLabel',atlas.care_state_label_v1(h.previous_state),
          'resultingState',h.resulting_state,
          'resultingStateLabel',atlas.care_state_label_v1(h.resulting_state),
          'sourceKind',h.source_kind,
          'reason',h.reason
        )) as card
      from atlas.care_state_history h
      join atlas.growing_objects go on go.id=h.object_id
      where h.farm_id=p_farm_id
        and h.zone_id=v_zone.id
      order by h.occurred_at desc
      limit v_limit
    ) x
  )
  select atlas.farm_care_zone_card_v1(v_zone.id)
    || jsonb_build_object(
      'objectGroups',og.groups,
      'releasedInterventions',r.cards,
      'plannedRecommendations',p.cards,
      'history',h.cards
    )
  into v_result
  from object_groups og
  cross join released r
  cross join planned p
  cross join history h;

  return coalesce(v_result,atlas.farm_care_zone_card_v1(v_zone.id));
end
$function$

CREATE OR REPLACE FUNCTION atlas.farm_care_object_v1(p_farm_id uuid, p_object_key text, p_history_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_object atlas.growing_objects%rowtype;
  v_limit integer := least(greatest(coalesce(p_history_limit,20),1),100);
  v_result jsonb;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);

  select * into v_object
  from atlas.growing_objects go
  where go.farm_id=p_farm_id
    and go.stable_key=p_object_key
    and exists(
      select 1
      from atlas.maintenance_objects mo
      where mo.object_id=go.id
        and mo.active
    );

  if not found then
    raise exception 'Maintainable object % was not found for farm %.',
      p_object_key,p_farm_id
      using errcode='P0002';
  end if;

  with latest_observation as (
    select jsonb_strip_nulls(jsonb_build_object(
      'observationId',o.id,
      'observedAt',o.observed_at,
      'pressure',o.pressure_band,
      'intendedShapeReadable',o.intended_shape_readable,
      'functionProtected',o.function_protected,
      'recoveryRequired',o.recovery_required,
      'estimatedEffortMinutes',o.estimated_recovery_minutes,
      'note',o.note,
      'sourceKind',o.source_kind
    )) as observation
    from atlas.care_observations o
    where o.farm_id=p_farm_id
      and o.object_id=v_object.id
    order by o.observed_at desc,o.id desc
    limit 1
  ),
  history as (
    select coalesce(jsonb_agg(x.card order by x.occurred_at desc),'[]'::jsonb) as events
    from (
      select
        h.occurred_at,
        jsonb_strip_nulls(jsonb_build_object(
          'historyId',h.id,
          'occurredAt',h.occurred_at,
          'previousState',h.previous_state,
          'previousStateLabel',atlas.care_state_label_v1(h.previous_state),
          'resultingState',h.resulting_state,
          'resultingStateLabel',atlas.care_state_label_v1(h.resulting_state),
          'previousStrategy',h.previous_strategy,
          'previousStrategyLabel',atlas.care_strategy_label_v1(h.previous_strategy),
          'resultingStrategy',h.resulting_strategy,
          'resultingStrategyLabel',atlas.care_strategy_label_v1(h.resulting_strategy),
          'previousPressure',h.previous_pressure,
          'resultingPressure',h.resulting_pressure,
          'previousTrend',h.previous_trend,
          'resultingTrend',h.resulting_trend,
          'sourceKind',h.source_kind,
          'reason',h.reason
        )) as card
      from atlas.care_state_history h
      where h.farm_id=p_farm_id
        and h.object_id=v_object.id
      order by h.occurred_at desc
      limit v_limit
    ) x
  ),
  results as (
    select coalesce(jsonb_agg(x.card order by x.completed_at desc),'[]'::jsonb) as events
    from (
      select
        mh.completed_at,
        jsonb_strip_nulls(jsonb_build_object(
          'maintenanceHistoryId',mh.id,
          'completedAt',mh.completed_at,
          'outcome',mh.outcome,
          'conditionBefore',mh.condition_before,
          'conditionAfter',mh.condition_after,
          'estimatedMinutesBefore',mh.estimated_minutes_before,
          'actualMinutes',mh.actual_minutes,
          'remainingMinutesAfter',mh.remaining_minutes_after,
          'sourceTaskId',mh.source_task_id,
          'note',mh.note
        )) as card
      from atlas.maintenance_history mh
      where mh.farm_id=p_farm_id
        and mh.object_id=v_object.id
      order by mh.completed_at desc
      limit v_limit
    ) x
  )
  select
    atlas.farm_care_object_card_v1(v_object.id)
    || jsonb_build_object(
      'latestObservation',(select observation from latest_observation),
      'history',(select events from history),
      'results',(select events from results)
    )
  into v_result;

  return v_result;
end
$function$

CREATE OR REPLACE FUNCTION atlas.farm_care_summary_v1(p_farm_id uuid, p_history_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_history_days integer := least(greatest(coalesce(p_history_days,30),1),180);
  v_result jsonb;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);

  with objects as (
    select *
    from atlas.farm_care_object_projection_v1
    where farm_id=p_farm_id
  ),
  farm_record as (
    select id,stable_key,name,status
    from atlas.farms
    where id=p_farm_id
  ),
  counts as (
    select
      count(*)::integer as object_count,
      count(*) filter (where care_state='settled')::integer as settled_count,
      count(*) filter (where care_state='stirring')::integer as stirring_count,
      count(*) filter (where care_state='needs_tending')::integer as needs_tending_count,
      count(*) filter (where care_state='losing_shape')::integer as losing_shape_count,
      count(*) filter (where care_state='recovery_needed')::integer as recovery_needed_count,
      count(*) filter (where care_state='resting')::integer as resting_count,
      count(*) filter (where care_state='suppressed')::integer as suppressed_count,
      count(*) filter (where care_state='decision_needed')::integer as decision_needed_count,
      count(*) filter (where care_state='unknown')::integer as unknown_count,
      count(*) filter (where care_freshness='observed')::integer as observed_count,
      count(*) filter (where care_freshness='estimated')::integer as estimated_count,
      count(*) filter (where care_freshness='stale')::integer as stale_count,
      count(*) filter (where care_freshness='unknown')::integer as unknown_freshness_count,
      coalesce(sum(care_estimated_recovery_minutes) filter (
        where care_state in ('stirring','needs_tending')
      ),0)::integer as tending_minutes,
      coalesce(sum(care_estimated_recovery_minutes) filter (
        where care_state in ('losing_shape','recovery_needed')
      ),0)::integer as recovery_minutes,
      count(*) filter (where production_sensitive and care_state in (
        'stirring','needs_tending','losing_shape','recovery_needed'
      ))::integer as production_concern_count,
      count(*) filter (where guest_sensitive and care_state in (
        'stirring','needs_tending','losing_shape','recovery_needed'
      ))::integer as guest_concern_count,
      count(*) filter (where access_or_establishment_sensitive and care_state in (
        'stirring','needs_tending','losing_shape','recovery_needed'
      ))::integer as access_or_establishment_concern_count,
      count(*) filter (where spread_sensitive and care_state in (
        'stirring','needs_tending','losing_shape','recovery_needed'
      ))::integer as spread_concern_count,
      sum(released_intervention_count)::integer as released_intervention_count,
      sum(planned_recommendation_count)::integer as planned_recommendation_object_links
    from objects
  ),
  zone_cards as materialized (
    select
      z.sort_order,
      z.label,
      atlas.farm_care_zone_card_v1(z.id) as card
    from atlas.zones z
    where z.farm_id=p_farm_id
      and exists(select 1 from objects o where o.zone_id=z.id)
  ),
  zones as (
    select
      coalesce(jsonb_agg(card order by sort_order,label),'[]'::jsonb) as cards,
      count(*)::integer as zone_count
    from zone_cards
  ),
  zone_trends as (
    select
      count(*) filter (where card->>'careTrend'='improving')::integer as improving,
      count(*) filter (where card->>'careTrend'='stable')::integer as holding,
      count(*) filter (where card->>'careTrend'='rising')::integer as rising,
      count(*) filter (where card->>'careTrend'='unknown')::integer as unknown,
      count(*) filter (where card->>'careState' in ('recovery_needed','losing_shape'))::integer as recovery_zones
    from zone_cards
  ),
  released as (
    select
      count(*)::integer as task_count,
      coalesce(sum(r.estimated_minutes),0)::integer as estimated_minutes,
      coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'taskId',r.task_id,
        'zoneId',r.zone_id,
        'zoneKey',z.stable_key,
        'zoneLabel',z.label,
        'objectIds',to_jsonb(r.object_ids),
        'objectTargets',coalesce(targets.cards,'[]'::jsonb),
        'title',r.title,
        'status',r.status,
        'dueDate',r.due_date,
        'assignedMembershipId',r.assigned_membership_id,
        'estimatedMinutes',r.estimated_minutes,
        'action',r.action_label,
        'subject',r.subject_label,
        'lane',r.intervention_lane,
        'reasonLines',r.reason_lines,
        'desiredResult',r.desired_result,
        'doneDefinition',r.done_definition,
        'unlocks',r.unlock_text,
        'releaseReason',r.release_reason
      )) order by r.due_date nulls last,z.sort_order,r.title),'[]'::jsonb) as cards
    from atlas.farm_care_released_intervention_v1 r
    left join atlas.zones z on z.id=r.zone_id
    left join lateral (
      select jsonb_agg(jsonb_build_object(
        'objectId',o.object_id,
        'objectKey',o.object_key,
        'objectLabel',o.object_label,
        'careState',o.care_state,
        'careStateLabel',o.care_state_label
      ) order by o.object_sort_order,o.object_label) as cards
      from atlas.farm_care_object_projection_v1 o
      where o.object_id=any(r.object_ids)
    ) targets on true
    where r.farm_id=p_farm_id
  ),
  planned as (
    select count(*)::integer as occurrence_count,
           coalesce(sum(estimated_minutes),0)::integer as estimated_minutes
    from atlas.farm_care_planned_intervention_v1
    where farm_id=p_farm_id
  ),
  recent_wins as (
    select coalesce(jsonb_agg(x.card order by x.occurred_at desc),'[]'::jsonb) as cards
    from (
      select
        h.occurred_at,
        jsonb_strip_nulls(jsonb_build_object(
          'historyId',h.id,
          'occurredAt',h.occurred_at,
          'zoneId',h.zone_id,
          'zoneKey',z.stable_key,
          'zoneLabel',z.label,
          'objectId',h.object_id,
          'objectKey',go.stable_key,
          'objectLabel',go.label,
          'previousState',h.previous_state,
          'previousStateLabel',atlas.care_state_label_v1(h.previous_state),
          'resultingState',h.resulting_state,
          'resultingStateLabel',atlas.care_state_label_v1(h.resulting_state),
          'sourceKind',h.source_kind,
          'reason',h.reason
        )) as card
      from atlas.care_state_history h
      join atlas.growing_objects go on go.id=h.object_id
      left join atlas.zones z on z.id=h.zone_id
      where h.farm_id=p_farm_id
        and h.occurred_at>=now()-make_interval(days=>v_history_days)
        and h.previous_state in ('recovery_needed','losing_shape','needs_tending','stirring')
        and h.resulting_state in ('settled','needs_tending','stirring')
        and atlas.care_state_rank_v1(h.resulting_state)<atlas.care_state_rank_v1(h.previous_state)
      order by h.occurred_at desc
      limit 20
    ) x
  )
  select jsonb_strip_nulls(jsonb_build_object(
    'contractVersion','farm_care_phase2_v1',
    'farm',jsonb_build_object(
      'farmId',f.id,
      'farmKey',f.stable_key,
      'farmName',f.name,
      'status',f.status
    ),
    'generatedAt',now(),
    'summarySentence',case
      when c.object_count=0 then f.name||' has no active maintainable objects.'
      when c.recovery_needed_count+c.losing_shape_count>0 then
        f.name||' has '||(c.recovery_needed_count+c.losing_shape_count)::text||
        ' place'||case when c.recovery_needed_count+c.losing_shape_count=1 then '' else 's' end||
        ' needing recovery or clearer shape, with '||c.unknown_count::text||' still needing observation.'
      when c.unknown_count>0 then
        f.name||' has no verified recovery area, but '||c.unknown_count::text||
        ' place'||case when c.unknown_count=1 then '' else 's' end||' still need current observation.'
      else f.name||' is holding without a verified recovery area.'
    end,
    'objectCount',c.object_count,
    'zoneCount',zs.zone_count,
    'stateCounts',jsonb_build_object(
      'settled',c.settled_count,
      'stirring',c.stirring_count,
      'needsTending',c.needs_tending_count,
      'losingShape',c.losing_shape_count,
      'recoveryNeeded',c.recovery_needed_count,
      'resting',c.resting_count,
      'suppressed',c.suppressed_count,
      'decisionNeeded',c.decision_needed_count,
      'unknown',c.unknown_count
    ),
    'statePercentages',jsonb_build_object(
      'settled',round(100.0*c.settled_count/nullif(c.object_count,0),1),
      'stirring',round(100.0*c.stirring_count/nullif(c.object_count,0),1),
      'needsTending',round(100.0*c.needs_tending_count/nullif(c.object_count,0),1),
      'losingShape',round(100.0*c.losing_shape_count/nullif(c.object_count,0),1),
      'recoveryNeeded',round(100.0*c.recovery_needed_count/nullif(c.object_count,0),1),
      'resting',round(100.0*c.resting_count/nullif(c.object_count,0),1),
      'suppressed',round(100.0*c.suppressed_count/nullif(c.object_count,0),1),
      'decisionNeeded',round(100.0*c.decision_needed_count/nullif(c.object_count,0),1),
      'unknown',round(100.0*c.unknown_count/nullif(c.object_count,0),1)
    ),
    'zoneTrends',jsonb_build_object(
      'improving',zt.improving,
      'holding',zt.holding,
      'rising',zt.rising,
      'unknown',zt.unknown,
      'recoveryZones',zt.recovery_zones
    ),
    'observationCoverage',jsonb_build_object(
      'observed',c.observed_count,
      'estimated',c.estimated_count,
      'stale',c.stale_count,
      'unknown',c.unknown_freshness_count,
      'needsObservation',c.stale_count+c.unknown_freshness_count,
      'coveredPercent',round(100.0*(c.observed_count+c.estimated_count)/nullif(c.object_count,0),1)
    ),
    'effort',jsonb_build_object(
      'tendingMinutes',c.tending_minutes,
      'recoveryMinutes',c.recovery_minutes,
      'knownCareMinutes',c.tending_minutes+c.recovery_minutes,
      'releasedMinutes',r.estimated_minutes,
      'plannedMinutes',p.estimated_minutes
    ),
    'concerns',jsonb_build_object(
      'production',c.production_concern_count,
      'guestPresentation',c.guest_concern_count,
      'accessOrEstablishment',c.access_or_establishment_concern_count,
      'spread',c.spread_concern_count,
      'resting',c.resting_count,
      'suppressed',c.suppressed_count,
      'decisionNeeded',c.decision_needed_count
    ),
    'releasedInterventionCount',r.task_count,
    'releasedInterventions',r.cards,
    'plannedRecommendationCount',p.occurrence_count,
    'plannedRecommendationSource','legacy_planned_occurrence',
    'recentWins',rw.cards,
    'zones',zs.cards
  )) into v_result
  from farm_record f
  cross join counts c
  cross join zones zs
  cross join zone_trends zt
  cross join released r
  cross join planned p
  cross join recent_wins rw;

  if v_result is null then
    raise exception 'Farm % was not found.',p_farm_id using errcode='P0002';
  end if;

  return v_result;
end
$function$

CREATE OR REPLACE FUNCTION atlas.farm_snapshot_for_member_v1(p_farm_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_year_start date := date_trunc('year', current_date)::date;
  v_total_beds integer := 0;
  v_growing_beds integer := 0;
  v_active_sqft numeric := 0;
  v_sowing_events integer := 0;
  v_sowing_logs integer := 0;
  v_stems_logged numeric := 0;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);

  select count(*)::integer
  into v_total_beds
  from atlas.growing_objects go
  where go.farm_id = p_farm_id
    and go.object_type = 'bed';

  with active_objects as (
    select distinct oc.object_id
    from atlas.object_contents oc
    join atlas.growing_objects go on go.id = oc.object_id
    where oc.farm_id = p_farm_id
      and go.farm_id = p_farm_id
      and oc.status is not null
      and lower(oc.status) not in ('archived', 'cleared', 'dead', 'empty', 'failed', 'removed')
  )
  select
    count(*)::integer,
    coalesce(sum(coalesce(go.area_sqft, go.length_ft * go.width_ft, 0)), 0)
  into v_growing_beds, v_active_sqft
  from active_objects ao
  join atlas.growing_objects go on go.id = ao.object_id;

  select
    count(*) filter (
      where e.event_type in ('seeded', 'sowed', 'sowing_recorded')
    )::integer,
    coalesce(sum(case
      when e.event_type = 'harvested' and lower(coalesce(e.unit, '')) like '%stem%'
        then coalesce(e.quantity, 0)
      else 0
    end), 0)
  into v_sowing_events, v_stems_logged
  from atlas.object_activity_events e
  where e.farm_id = p_farm_id
    and e.event_date >= v_year_start
    and (
      e.event_type in ('seeded', 'sowed', 'sowing_recorded')
      or (e.event_type = 'harvested' and lower(coalesce(e.unit, '')) like '%stem%')
    );

  select count(*)::integer
  into v_sowing_logs
  from atlas.field_logs fl
  where fl.farm_id = p_farm_id
    and fl.log_date >= v_year_start
    and exists (
      select 1
      from unnest(coalesce(fl.action_types, array[]::text[])) action_type
      where lower(action_type) like '%sow%'
         or lower(action_type) like '%seed%'
    );

  return jsonb_build_object(
    'totalBeds', v_total_beds,
    'growingBeds', v_growing_beds,
    'activeSqft', round(v_active_sqft),
    'sowingsLogged', v_sowing_events + v_sowing_logs,
    'stemsLogged', round(v_stems_logged)
  );
end;
$function$

COMMIT;
