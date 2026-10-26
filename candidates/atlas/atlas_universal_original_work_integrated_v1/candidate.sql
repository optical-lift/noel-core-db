BEGIN;
-- HELD ATLAS ORIGINAL WORK SOURCE. NOT A RELEASE MIGRATION.

-- Original held candidate: universal_laundry_calibration_without_implicit_rhythm_v1/candidate.sql
-- Atlas V1 Laundry calibration remains signed, Household-scoped and config-only.
-- No implicit recurring Rhythm, Work, assignment, Clock right or deletion.
-- Reviewed source candidate; do not release until schema-clone + signed proofs.
CREATE OR REPLACE FUNCTION atlas.calibrate_personal_laundry_kernel_self_api_v1(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_household_id uuid;
  v_kernel_version integer;
  v_model atlas.world_kernel_models%rowtype;
  v_model_key text;
  v_config jsonb := '{}'::jsonb;
  v_location text;
  v_pattern text;
  v_special text[];
  v_notes text;
  v_expected integer;
  v_instance atlas.household_kernel_instances%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;
  if p_input is null or jsonb_typeof(p_input) <> 'object' then
    raise exception 'Laundry calibration input must be an object.' using errcode = '22023';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode = '42501';
  end if;

  select max(k.version) into v_kernel_version
  from atlas.world_kernel_definitions k
  where k.kernel_key = 'household.laundry' and k.active;

  v_model_key := nullif(trim(p_input->>'modelKey'), '');
  if v_model_key is not null then
    select * into v_model
    from atlas.world_kernel_models m
    where m.kernel_key = 'household.laundry'
      and m.kernel_version = v_kernel_version
      and m.model_key = v_model_key
      and m.active;
    if v_model.model_key is null then
      raise exception 'Unknown Laundry model.' using errcode = '22023';
    end if;
    v_config := v_model.configuration;
  end if;

  v_config := v_config || jsonb_strip_nulls(jsonb_build_object(
    'laundryLocation', nullif(trim(p_input->>'laundryLocation'), ''),
    'usualPattern', nullif(trim(p_input->>'usualPattern'), ''),
    'notes', nullif(trim(p_input->>'notes'), ''),
    'expectedMinutes', case when nullif(p_input->>'expectedMinutes','') is null then null else (p_input->>'expectedMinutes')::integer end
  ));

  if p_input ? 'specialTurnaround' then
    v_config := v_config || jsonb_build_object('specialTurnaround', p_input->'specialTurnaround');
  end if;

  v_location := nullif(trim(v_config->>'laundryLocation'), '');
  v_pattern := nullif(trim(v_config->>'usualPattern'), '');
  v_notes := nullif(trim(v_config->>'notes'), '');
  v_expected := coalesce(nullif(v_config->>'expectedMinutes','')::integer, 45);

  if v_location is not null and v_location not in ('home','shared_machines','laundromat','service','other') then
    raise exception 'Unsupported laundryLocation.' using errcode = '22023';
  end if;
  if v_pattern is not null and v_pattern not in ('little_most_days','few_times_week','main_day','as_needed','other') then
    raise exception 'Unsupported usualPattern.' using errcode = '22023';
  end if;
  if v_expected <= 0 then
    raise exception 'expectedMinutes must be positive.' using errcode = '22023';
  end if;

  select coalesce(array_agg(x), '{}'::text[]) into v_special
  from jsonb_array_elements_text(coalesce(v_config->'specialTurnaround', '[]'::jsonb)) t(x);
  v_config := v_config || jsonb_build_object('specialTurnaround', to_jsonb(v_special));

  if v_location is null or v_pattern is null then
    raise exception 'Laundry location and usual pattern are required after model selection/calibration.' using errcode = '22023';
  end if;

  insert into atlas.household_kernel_instances (
    household_id, kernel_key, kernel_version, state, configuration, calibrated_at, metadata
  ) values (
    v_household_id,
    'household.laundry',
    v_kernel_version,
    'active',
    v_config,
    now(),
    jsonb_strip_nulls(jsonb_build_object(
      'source', 'principal_calibration',
      'calibratedBy', auth.uid(),
      'calibrationContract', 'household_laundry_calibration_v1',
      'selectedModelKey', v_model_key,
      'selectedModelAudience', case when v_model_key is null then null else v_model.audience_key end
    ))
  )
  on conflict (household_id, kernel_key) do update set
    kernel_version = excluded.kernel_version,
    state = 'active',
    configuration = atlas.household_kernel_instances.configuration || excluded.configuration,
    calibrated_at = now(),
    metadata = atlas.household_kernel_instances.metadata || excluded.metadata,
    updated_at = now()
  returning * into v_instance;

  -- Calibration records arrangement only. Establishing a Rhythm is a distinct
  -- explicitly authorized operation; preserve any pre-existing Rhythm unchanged.


  return jsonb_build_object(
    'ok', true,
    'contractVersion', 'household_laundry_calibration_v1',
    'selectedModelKey', v_model_key,
    'instance', jsonb_build_object(
      'id', v_instance.id,
      'state', v_instance.state,
      'configuration', v_instance.configuration,
      'calibratedAt', v_instance.calibrated_at
    ),
    'rhythm', null,
    'claimsCreated', jsonb_build_object(
      'washerOwned', false,
      'dryerOwned', false,
      'childExists', false,
      'sportsUniformExists', false
    )
  );
end;
$function$;
-- Original held candidate: governed_legacy_farm_reader_disclosure_v1/candidate.sql
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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;
-- Original held candidate: governed_legacy_farm_reader_disclosure_gate0_extension_v1/candidate.sql
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
-- Original held candidate: governed_legacy_farm_reader_disclosure_gate0_context_v1/candidate.sql
-- Gate 0 source-only candidates: eight more old farm/role based readers,
-- including unbounded membership roster, crop-cycle and task card contexts.
-- None may infer broad disclosure from an inherited seat. Use native Ledger
-- governor source and exact signed Person Work Subject readers instead.
-- Source lookup failure is identical to signed nonauthorization for opaque IDs.
CREATE OR REPLACE FUNCTION atlas.maintenance_directive_context_v1(p_farm_id uuid, p_object_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_role text;
  v_membership_id uuid;
  v_object atlas.growing_objects%rowtype;
  v_weed_card atlas.weed_cards%rowtype;
  v_mowing_state atlas.rhythm_state%rowtype;
  v_weed_task_id uuid;
  v_mow_task_id uuid;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;

  v_role := atlas.current_farm_role(p_farm_id);
  v_membership_id := atlas.current_membership_id(p_farm_id);
  if v_role is null or v_membership_id is null then
    raise exception 'Active farm membership required.' using errcode = '42501';
  end if;

  select object_row.* into v_object
  from atlas.growing_objects object_row
  where object_row.farm_id = p_farm_id
    and object_row.stable_key = btrim(p_object_key)
  limit 1;

  if v_object.id is null then
    raise exception 'Growing object not found.' using errcode = 'P0002';
  end if;

  select card.* into v_weed_card
  from atlas.weed_cards card
  where card.object_id = v_object.id
  limit 1;

  if v_weed_card.id is not null then
    select task.id into v_weed_task_id
    from atlas.tasks task
    join atlas.task_objects object_link on object_link.task_id = task.id and object_link.object_id = v_object.id
    where task.farm_id = p_farm_id
      and task.status in ('open','blocked')
      and (
        task.action_key = 'weed'
        or task.task_type = 'maintenance'
        or task.metadata ->> 'weed_card_id' = v_weed_card.id::text
      )
    order by task.due_date nulls last, task.created_at
    limit 1;
  end if;

  select state.* into v_mowing_state
  from atlas.rhythm_state state
  where state.farm_id = p_farm_id
    and state.rhythm_key = 'mowing'
    and state.subject_kind = 'growing_object'
    and state.subject_id = v_object.id
  order by state.updated_at desc
  limit 1;

  if v_mowing_state.id is not null then
    select task.id into v_mow_task_id
    from atlas.tasks task
    where task.id = v_mowing_state.current_task_id
      and task.status in ('open','blocked');
  end if;

  return jsonb_build_object(
    'object', jsonb_build_object(
      'id', v_object.id,
      'key', v_object.stable_key,
      'label', v_object.label,
      'type', v_object.object_type
    ),
    'viewerRole', v_role,
    'viewerMembershipId', v_membership_id,
    'canAuthor', v_role in ('owner','manager'),
    'capabilities', jsonb_build_object(
      'weed', v_object.object_type not in ('room','building','structure'),
      'mow', v_mowing_state.id is not null
    ),
    'cards', jsonb_strip_nulls(jsonb_build_object(
      'weed', case when v_object.object_type in ('room','building','structure') then null else jsonb_build_object(
        'cardId', v_weed_card.id,
        'currentCondition', v_weed_card.current_condition,
        'targetCondition', coalesce(v_weed_card.target_condition,'clear'),
        'servingTaskId', v_weed_task_id
      ) end,
      'mow', case when v_mowing_state.id is null then null else jsonb_build_object(
        'rhythmStateId', v_mowing_state.id,
        'state', v_mowing_state.state,
        'servingTaskId', v_mow_task_id,
        'targetCutHeightInches', nullif(v_object.metadata ->> 'target_cut_height_inches', '')
      ) end
    )),
    'memberships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'membershipId', membership.id,
        'role', membership.role,
        'workerKey', membership.worker_key,
        'displayName', coalesce(profile.display_name, membership.worker_key, initcap(membership.role))
      ) order by case membership.role when 'owner' then 0 when 'manager' then 1 else 2 end, coalesce(profile.display_name, membership.worker_key))
      from atlas.farm_memberships membership
      left join atlas.user_profiles profile on profile.user_id = membership.user_id
      where membership.farm_id = p_farm_id and membership.active
    ), '[]'::jsonb),
    'directives', coalesce((
      select jsonb_agg(atlas.maintenance_directive_json_v1(directive.id) order by directive.due_date, directive.created_at)
      from atlas.maintenance_directives directive
      where directive.object_id = v_object.id
        and directive.status = 'active'
    ), '[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION atlas.manual_task_context_v1(p_object_key text, p_assigned_membership_id uuid DEFAULT NULL::uuid, p_due_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_object atlas.growing_objects%rowtype;
  v_role text;
  v_viewer_membership_id uuid;
  v_day_load jsonb;
begin
  select * into v_object
  from atlas.growing_objects
  where stable_key = p_object_key
  limit 1;

  IF v_object.id IS NULL THEN
    RAISE EXCEPTION 'Source unavailable to this Person.' USING ERRCODE='42501';
  END IF;
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(v_object.farm_id);

  v_role := atlas.current_farm_role(v_object.farm_id);
  if auth.uid() is null or v_role is null then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;

  select id into v_viewer_membership_id
  from atlas.farm_memberships
  where farm_id=v_object.farm_id and user_id=auth.uid() and active=true
  order by created_at
  limit 1;

  if p_assigned_membership_id is not null and p_due_date is not null then
    v_day_load := atlas.member_day_load_core_v1(v_object.farm_id,p_assigned_membership_id,p_due_date,null);
  end if;

  return jsonb_build_object(
    'farmId',v_object.farm_id,
    'object',jsonb_build_object('id',v_object.id,'key',v_object.stable_key,'label',v_object.label,'zoneId',v_object.zone_id),
    'canAuthor',v_role in ('owner','manager'),
    'viewerMembershipId',v_viewer_membership_id,
    'memberships',coalesce((
      select jsonb_agg(jsonb_build_object(
        'membershipId',m.id,
        'userId',m.user_id,
        'role',m.role,
        'workerKey',m.worker_key,
        'displayName',coalesce(p.display_name,m.worker_key,initcap(m.role)),
        'activeTaskCount',(select count(*) from atlas.tasks t where t.assigned_membership_id=m.id and t.status in ('open','blocked'))
      ) order by coalesce(p.display_name,m.worker_key,initcap(m.role)))
      from atlas.farm_memberships m
      left join atlas.user_profiles p on p.user_id=m.user_id
      where m.farm_id=v_object.farm_id and m.active=true
    ),'[]'::jsonb),
    'dayLoad',v_day_load
  );
end;
$function$;

CREATE OR REPLACE FUNCTION atlas.resolve_effective_rhythm_rule_v1(p_farm_id uuid, p_rhythm_key text, p_subject_kind text, p_subject_id uuid, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_organization_id uuid;
  v_zone_id uuid;
  v_object_id uuid;
  v_object_type text;
  v_object_mode text;
  v_life_status text;
  v_care_state text;
  v_crop_profile_id uuid;
  v_stage_key text;
  v_project_id uuid;
  v_project_stage text;
  v_candidate_count integer := 0;
  v_winner jsonb;
  v_as_of timestamptz := coalesce(p_as_of, now());
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  if auth.uid() is null or not atlas.is_farm_member(p_farm_id) then
    raise exception 'Farm membership is required to resolve a Rulebook rhythm.' using errcode = '42501';
  end if;

  if nullif(btrim(coalesce(p_rhythm_key, '')), '') is null
     or p_subject_kind not in ('farm', 'zone', 'growing_object', 'crop_cycle', 'project')
     or p_subject_id is null then
    raise exception 'Rhythm key and canonical subject are required.' using errcode = '22023';
  end if;

  if not atlas.rhythm_subject_belongs_to_farm_v1(p_farm_id, p_subject_kind, p_subject_id) then
    raise exception 'The Rulebook subject is not part of this farm.' using errcode = '22023';
  end if;

  select f.organization_id into v_organization_id
  from atlas.farms f
  where f.id = p_farm_id;

  if p_subject_kind = 'zone' then
    v_zone_id := p_subject_id;
  elsif p_subject_kind = 'growing_object' then
    v_object_id := p_subject_id;
    select o.zone_id, o.object_type, o.object_mode,
           os.life_status, os.care_state
    into v_zone_id, v_object_type, v_object_mode,
         v_life_status, v_care_state
    from atlas.growing_objects o
    left join atlas.object_state os on os.object_id = o.id
    where o.id = p_subject_id;

    select cc.crop_profile_id, cc.cycle_state
    into v_crop_profile_id, v_stage_key
    from atlas.crop_cycles cc
    where cc.object_id = p_subject_id
      and cc.lifecycle_status in ('planned', 'active')
    order by
      case cc.lifecycle_status when 'active' then 0 else 1 end,
      coalesce(cc.planted_date, cc.sown_date, cc.created_at::date) desc,
      cc.created_at desc
    limit 1;
  elsif p_subject_kind = 'crop_cycle' then
    select cc.object_id, cc.crop_profile_id, cc.cycle_state,
           o.zone_id, o.object_type, o.object_mode,
           os.life_status, os.care_state
    into v_object_id, v_crop_profile_id, v_stage_key,
         v_zone_id, v_object_type, v_object_mode,
         v_life_status, v_care_state
    from atlas.crop_cycles cc
    left join atlas.growing_objects o on o.id = cc.object_id
    left join atlas.object_state os on os.object_id = cc.object_id
    where cc.id = p_subject_id;
  elsif p_subject_kind = 'project' then
    v_project_id := p_subject_id;
    select p.zone_id, p.current_milestone
    into v_zone_id, v_project_stage
    from atlas.projects p
    where p.id = p_subject_id;
  end if;

  with candidates as (
    select
      b.id as binding_id,
      b.binding_key,
      b.inheritance_layer,
      b.subject_kind as binding_subject_kind,
      b.subject_id as binding_subject_id,
      b.subject_key as binding_subject_key,
      b.priority,
      r.id as rule_id,
      r.rule_key,
      r.rhythm_key,
      r.version,
      r.label,
      r.applicability,
      r.validity_interval_seconds,
      r.warning_window_seconds,
      r.grace_window_seconds,
      r.qualifying_touches,
      r.failure_consequence,
      r.player_routing,
      case b.inheritance_layer
        when 'temporary_exception' then 600
        when 'subject_override' then 500
        when 'contents_stage' then 400
        when 'zone_modifier' then 300
        when 'object_class' then 200
        when 'farm_default' then 100
        else 0
      end as layer_rank,
      case
        when b.inheritance_layer = 'farm_default' then 'farm:' || p_farm_id::text
        when b.inheritance_layer = 'object_class' then 'object_class:' || b.subject_key
        when b.inheritance_layer = 'zone_modifier' then 'zone:' || b.subject_id::text
        when b.subject_kind = 'crop_profile' then 'crop_profile:' || b.subject_id::text
        when b.subject_kind = 'crop_stage' then 'crop_stage:' || b.subject_key
        when b.subject_kind = 'room_state' then 'room_state:' || b.subject_key
        when b.subject_kind = 'project_stage' then 'project_stage:' || b.subject_key
        else b.subject_kind || ':' || b.subject_id::text
      end as matched_on
    from atlas.rhythm_bindings b
    join atlas.rhythm_rules r on r.id = b.rhythm_rule_id
    where b.farm_id = p_farm_id
      and r.farm_id = p_farm_id
      and r.rhythm_key = btrim(p_rhythm_key)
      and r.status = 'active'
      and b.active = true
      and (b.active_from is null or b.active_from <= v_as_of)
      and (b.active_until is null or b.active_until > v_as_of)
      and (
        (b.inheritance_layer = 'farm_default'
          and b.subject_kind = 'farm'
          and b.subject_id = p_farm_id)
        or
        (b.inheritance_layer = 'object_class'
          and b.subject_kind = 'object_class'
          and v_object_id is not null
          and b.subject_key = any(array_remove(array[
            v_object_type,
            case when v_object_type is not null then 'type:' || v_object_type end,
            v_object_mode,
            case when v_object_mode is not null then 'mode:' || v_object_mode end
          ], null)))
        or
        (b.inheritance_layer = 'zone_modifier'
          and b.subject_kind = 'zone'
          and v_zone_id is not null
          and b.subject_id = v_zone_id)
        or
        (b.inheritance_layer = 'contents_stage'
          and (
            (b.subject_kind = 'crop_profile'
              and v_crop_profile_id is not null
              and b.subject_id = v_crop_profile_id)
            or
            (b.subject_kind = 'crop_stage'
              and v_stage_key is not null
              and b.subject_key = any(array[v_stage_key, 'stage:' || v_stage_key]))
            or
            (b.subject_kind = 'room_state'
              and v_object_type = 'room'
              and (b.subject_id is null or b.subject_id = v_object_id)
              and b.subject_key = any(array_remove(array[
                v_life_status,
                case when v_life_status is not null then 'life:' || v_life_status end,
                v_care_state,
                case when v_care_state is not null then 'care:' || v_care_state end
              ], null)))
            or
            (b.subject_kind = 'project_stage'
              and v_project_id is not null
              and b.subject_id = v_project_id
              and v_project_stage is not null
              and b.subject_key = any(array[v_project_stage, 'stage:' || v_project_stage]))
          ))
        or
        (b.inheritance_layer in ('subject_override', 'temporary_exception')
          and (
            (b.subject_kind = p_subject_kind and b.subject_id = p_subject_id)
            or
            (p_subject_kind = 'crop_cycle'
              and b.subject_kind = 'growing_object'
              and v_object_id is not null
              and b.subject_id = v_object_id)
          ))
      )
  )
  select count(*) into v_candidate_count
  from candidates;

  with candidates as (
    select
      b.id as binding_id,
      b.binding_key,
      b.inheritance_layer,
      b.subject_kind as binding_subject_kind,
      b.subject_id as binding_subject_id,
      b.subject_key as binding_subject_key,
      b.priority,
      r.id as rule_id,
      r.rule_key,
      r.rhythm_key,
      r.version,
      r.label,
      r.applicability,
      r.validity_interval_seconds,
      r.warning_window_seconds,
      r.grace_window_seconds,
      r.qualifying_touches,
      r.failure_consequence,
      r.player_routing,
      case b.inheritance_layer
        when 'temporary_exception' then 600
        when 'subject_override' then 500
        when 'contents_stage' then 400
        when 'zone_modifier' then 300
        when 'object_class' then 200
        when 'farm_default' then 100
        else 0
      end as layer_rank,
      case
        when b.inheritance_layer = 'farm_default' then 'farm:' || p_farm_id::text
        when b.inheritance_layer = 'object_class' then 'object_class:' || b.subject_key
        when b.inheritance_layer = 'zone_modifier' then 'zone:' || b.subject_id::text
        when b.subject_kind = 'crop_profile' then 'crop_profile:' || b.subject_id::text
        when b.subject_kind = 'crop_stage' then 'crop_stage:' || b.subject_key
        when b.subject_kind = 'room_state' then 'room_state:' || b.subject_key
        when b.subject_kind = 'project_stage' then 'project_stage:' || b.subject_key
        else b.subject_kind || ':' || b.subject_id::text
      end as matched_on
    from atlas.rhythm_bindings b
    join atlas.rhythm_rules r on r.id = b.rhythm_rule_id
    where b.farm_id = p_farm_id
      and r.farm_id = p_farm_id
      and r.rhythm_key = btrim(p_rhythm_key)
      and r.status = 'active'
      and b.active = true
      and (b.active_from is null or b.active_from <= v_as_of)
      and (b.active_until is null or b.active_until > v_as_of)
      and (
        (b.inheritance_layer = 'farm_default'
          and b.subject_kind = 'farm'
          and b.subject_id = p_farm_id)
        or
        (b.inheritance_layer = 'object_class'
          and b.subject_kind = 'object_class'
          and v_object_id is not null
          and b.subject_key = any(array_remove(array[
            v_object_type,
            case when v_object_type is not null then 'type:' || v_object_type end,
            v_object_mode,
            case when v_object_mode is not null then 'mode:' || v_object_mode end
          ], null)))
        or
        (b.inheritance_layer = 'zone_modifier'
          and b.subject_kind = 'zone'
          and v_zone_id is not null
          and b.subject_id = v_zone_id)
        or
        (b.inheritance_layer = 'contents_stage'
          and (
            (b.subject_kind = 'crop_profile'
              and v_crop_profile_id is not null
              and b.subject_id = v_crop_profile_id)
            or
            (b.subject_kind = 'crop_stage'
              and v_stage_key is not null
              and b.subject_key = any(array[v_stage_key, 'stage:' || v_stage_key]))
            or
            (b.subject_kind = 'room_state'
              and v_object_type = 'room'
              and (b.subject_id is null or b.subject_id = v_object_id)
              and b.subject_key = any(array_remove(array[
                v_life_status,
                case when v_life_status is not null then 'life:' || v_life_status end,
                v_care_state,
                case when v_care_state is not null then 'care:' || v_care_state end
              ], null)))
            or
            (b.subject_kind = 'project_stage'
              and v_project_id is not null
              and b.subject_id = v_project_id
              and v_project_stage is not null
              and b.subject_key = any(array[v_project_stage, 'stage:' || v_project_stage]))
          ))
        or
        (b.inheritance_layer in ('subject_override', 'temporary_exception')
          and (
            (b.subject_kind = p_subject_kind and b.subject_id = p_subject_id)
            or
            (p_subject_kind = 'crop_cycle'
              and b.subject_kind = 'growing_object'
              and v_object_id is not null
              and b.subject_id = v_object_id)
          ))
      )
  )
  select jsonb_build_object(
    'bindingId', c.binding_id,
    'bindingKey', c.binding_key,
    'inheritanceLayer', c.inheritance_layer,
    'bindingSubjectKind', c.binding_subject_kind,
    'bindingSubjectId', c.binding_subject_id,
    'bindingSubjectKey', c.binding_subject_key,
    'priority', c.priority,
    'layerRank', c.layer_rank,
    'matchedOn', c.matched_on,
    'ruleId', c.rule_id,
    'ruleKey', c.rule_key,
    'rhythmKey', c.rhythm_key,
    'version', c.version,
    'label', c.label,
    'applicability', c.applicability,
    'validityIntervalSeconds', c.validity_interval_seconds,
    'warningWindowSeconds', c.warning_window_seconds,
    'graceWindowSeconds', c.grace_window_seconds,
    'qualifyingTouches', c.qualifying_touches,
    'failureConsequence', c.failure_consequence,
    'playerRouting', c.player_routing
  )
  into v_winner
  from candidates c
  order by c.layer_rank desc, c.priority desc, c.version desc, c.binding_id
  limit 1;

  return jsonb_build_object(
    'contractVersion', 'effective_rhythm_rule_v1',
    'resolvedAt', v_as_of,
    'farmId', p_farm_id,
    'organizationId', v_organization_id,
    'subject', jsonb_build_object(
      'kind', p_subject_kind,
      'id', p_subject_id,
      'zoneId', v_zone_id,
      'objectId', v_object_id,
      'objectType', v_object_type,
      'objectMode', v_object_mode,
      'cropProfileId', v_crop_profile_id,
      'stageKey', coalesce(v_stage_key, v_project_stage)
    ),
    'rhythmKey', btrim(p_rhythm_key),
    'effectiveRule', v_winner,
    'explanation', jsonb_build_object(
      'candidateCount', v_candidate_count,
      'winnerLayer', v_winner ->> 'inheritanceLayer',
      'matchedOn', v_winner ->> 'matchedOn',
      'resolutionRule', 'nearest_active_explicit_rule_wins',
      'inheritanceOrder', jsonb_build_array(
        'farm_default',
        'object_class',
        'zone_modifier',
        'contents_stage',
        'subject_override',
        'temporary_exception'
      ),
      'noMatch', v_winner is null
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION atlas.task_schedule_v1(p_farm_id uuid, p_start_date date, p_end_date date, p_include_overdue boolean DEFAULT false, p_include_undated boolean DEFAULT false, p_target_membership_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(task_id uuid, title text, task_type text, status text, priority text, due_date date, instruction text, blocker_text text, zone_id uuid, zone_key text, zone_label text, object_id uuid, object_key text, object_label text, assigned_membership_id uuid, assigned_display_name text, assigned_worker_key text, visibility_scope text, schedule_lane text, total_steps bigint, completed_steps bigint, can_act boolean, counts_for_window boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_role text;
  v_current_membership_id uuid;
  v_target_membership_id uuid;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  if p_start_date is null or p_end_date is null then
    raise exception 'Schedule start and end dates are required.' using errcode = '22023';
  end if;

  if p_end_date < p_start_date then
    raise exception 'Schedule end date must not precede start date.' using errcode = '22023';
  end if;

  if p_end_date - p_start_date > 62 then
    raise exception 'Schedule windows may not exceed 63 days.' using errcode = '22023';
  end if;

  v_role := atlas.current_farm_role(p_farm_id);
  if v_role is null then
    raise exception 'Active farm membership required.' using errcode = '42501';
  end if;

  v_current_membership_id := atlas.current_membership_id(p_farm_id);

  if v_role = 'farm_hand' then
    v_target_membership_id := v_current_membership_id;
  elsif p_target_membership_id is not null then
    select fm.id
    into v_target_membership_id
    from atlas.farm_memberships fm
    where fm.id = p_target_membership_id
      and fm.farm_id = p_farm_id
      and fm.active = true;

    if v_target_membership_id is null then
      raise exception 'Target membership is not active on this farm.' using errcode = '42501';
    end if;
  end if;

  return query
  select
    t.id,
    t.title,
    t.task_type,
    t.status,
    t.priority,
    t.due_date,
    coalesce(nullif(btrim(t.note), ''), nullif(btrim(t.unlock_text), '')),
    nullif(btrim(t.blocker_text), ''),
    z.id,
    z.stable_key,
    z.label,
    primary_object.object_id,
    primary_object.object_key,
    primary_object.object_label,
    t.assigned_membership_id,
    coalesce(up.display_name, assigned.worker_key, 'Farm Team')::text,
    assigned.worker_key,
    t.visibility_scope,
    case
      when t.status = 'done' then 'completed'
      when t.status = 'blocked' then 'blocked'
      when t.due_date is not null and t.due_date < p_start_date then 'overdue'
      when t.due_date is null then 'undated'
      when p_start_date = p_end_date and t.due_date = p_start_date then 'today'
      else 'scheduled'
    end,
    (
      select count(*)
      from atlas.tasks child
      where child.farm_id = t.farm_id
        and (
          child.parent_task_id = t.id
          or child.metadata->>'parent_task_id' = t.id::text
        )
        and child.status <> 'archived'
    ),
    (
      select count(*)
      from atlas.tasks child
      where child.farm_id = t.farm_id
        and (
          child.parent_task_id = t.id
          or child.metadata->>'parent_task_id' = t.id::text
        )
        and child.status = 'done'
    ),
    v_role = 'farm_hand'
      and t.status in ('open', 'blocked')
      and t.visibility_scope = 'assigned_worker'
      and t.assigned_membership_id = v_current_membership_id,
    coalesce(t.due_date between p_start_date and p_end_date, false)
  from atlas.tasks t
  left join atlas.zones z on z.id = t.zone_id
  left join atlas.farm_memberships assigned on assigned.id = t.assigned_membership_id
  left join atlas.user_profiles up on up.user_id = assigned.user_id
  left join lateral (
    select
      go.id as object_id,
      go.stable_key as object_key,
      go.label as object_label
    from atlas.task_objects task_link
    join atlas.growing_objects go on go.id = task_link.object_id
    where task_link.task_id = t.id
    order by
      case when task_link.role = 'target' then 0 else 1 end,
      go.sort_order,
      go.label
    limit 1
  ) primary_object on true
  where t.farm_id = p_farm_id
    and t.status in ('open', 'blocked', 'done')
    and t.parent_task_id is null
    and t.metadata->>'parent_task_id' is null
    and coalesce((t.metadata->>'is_child_task')::boolean, false) = false
    and (
      (v_role = 'owner' and t.visibility_scope in ('owner', 'management', 'assigned_worker', 'farm_shared'))
      or (v_role = 'manager' and t.visibility_scope in ('management', 'assigned_worker', 'farm_shared'))
      or (
        v_role = 'farm_hand'
        and (
          (t.visibility_scope = 'assigned_worker' and t.assigned_membership_id = v_current_membership_id)
          or t.visibility_scope = 'farm_shared'
        )
      )
    )
    and (
      v_target_membership_id is null
      or t.assigned_membership_id = v_target_membership_id
      or t.visibility_scope = 'farm_shared'
    )
    and (
      t.due_date between p_start_date and p_end_date
      or (
        t.status in ('open', 'blocked')
        and p_include_overdue
        and t.due_date < p_start_date
      )
      or (
        t.status in ('open', 'blocked')
        and p_include_undated
        and t.due_date is null
      )
    )
  order by
    case
      when t.status = 'blocked' then 0
      when t.status in ('open', 'blocked') and t.due_date is not null and t.due_date < p_start_date then 1
      when t.status = 'done' then 3
      when t.due_date is null then 4
      else 2
    end,
    t.due_date nulls last,
    case t.priority
      when 'urgent' then 0
      when 'high' then 1
      when 'normal' then 2
      when 'low' then 3
      else 4
    end,
    coalesce((t.metadata->>'day_order')::integer, 999),
    t.created_at
  limit 1000;
end;
$function$;

CREATE OR REPLACE FUNCTION atlas.tending_bed_v1(p_farm_id uuid, p_object_key text, p_worker_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare v_role text; v_membership_id uuid; v_worker_key text; v_requested_worker_key text:=nullif(lower(btrim(p_worker_key)),''); v_object_id uuid; v_task_id uuid; v_cycle_id uuid; v_harvest_on date; v_gates jsonb; v_card jsonb; v_fallback jsonb;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  v_role:=atlas.current_farm_role(p_farm_id); v_membership_id:=atlas.current_membership_id(p_farm_id);
  if v_role is null or v_membership_id is null then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  select nullif(lower(btrim(fm.worker_key)),'') into v_worker_key from atlas.farm_memberships fm where fm.id=v_membership_id and fm.farm_id=p_farm_id and fm.active=true;
  if v_worker_key is null then raise exception 'Current Atlas worker identity was not found.' using errcode='P0002'; end if;
  if v_requested_worker_key is not null and v_requested_worker_key is distinct from v_worker_key then raise exception 'Tending may only load the signed-in membership.' using errcode='42501'; end if;
  select go.id into v_object_id from atlas.growing_objects go where go.farm_id=p_farm_id and go.stable_key=p_object_key;
  if v_object_id is null then raise exception 'Tending bed not found.' using errcode='P0002'; end if;
  select x.task_id,x.crop_cycle_id,case when atlas.tending_unlock_label_v1(x.unlock_text,x.task_metadata,null) is not null and x.lifecycle_status<>'planned' and x.gate_key in ('weed','clear') then null else x.expected_harvest_watch_start end
  into v_task_id,v_cycle_id,v_harvest_on from atlas.tending_task_track_v1 x
  where x.farm_id=p_farm_id and x.object_id=v_object_id and x.task_status='open' and x.released_at is not null and x.planned_occurrence_id is not null
    and (x.visibility_scope='farm_shared' or (x.visibility_scope='assigned_worker' and x.assigned_membership_id=v_membership_id) or (v_role='owner' and x.visibility_scope='owner' and (x.assigned_membership_id is null or x.assigned_membership_id=v_membership_id)))
    and x.gate_key in ('weed','clear','sow','plant','transplant','pot_up','harden_off','germination_check','observe','pinch','water','support','thin','prune','harvest_watch','harvest')
    and coalesce(x.care_state,'unknown') not in ('resting','suppressed')
    and not (x.gate_key in ('weed','clear') and coalesce(x.ordinary_weeding_allowed,true)=false)
  order by x.due_date nulls last,case x.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end,x.task_created_at limit 1;
  if v_task_id is not null then
    v_gates:=atlas.tending_gates_v1(v_object_id,v_cycle_id,v_task_id,v_harvest_on);
    v_card:=atlas.tending_card_json_v2(v_task_id,v_object_id,v_gates,true);
    return jsonb_build_object('miniGamesEnabled',false,'bed',v_card);
  end if;
  select jsonb_strip_nulls(jsonb_build_object('bedKey',go.stable_key,'bedLabel',go.label,'zoneKey',z.stable_key,'zoneLabel',z.label,'objectType',go.object_type,'objectMode',go.object_mode,'cropCycleId',cc.id,'cropLabel',coalesce(nullif(cc.variety,''),cc.crop_label),'cropStage',cc.cycle_state,'cropLifecycleStatus',cc.lifecycle_status,'harvestMetricType',case when coalesce(cp.harvest_pattern,cc.metadata->>'harvest_pattern') in ('single_cut','seasonal_single_flush') then 'harvest' when coalesce(cp.harvest_pattern,cc.metadata->>'harvest_pattern') in ('cut_and_come_again','repeat_pick','seasonal_repeat_cut') then 'harvest_rounds' else 'harvest_opportunities' end,'firstOrNextHarvestOn',cc.expected_harvest_watch_start,'harvestWindowEndsOn',cc.expected_harvest_watch_end,'clockBasis',case when cc.sown_date is not null or cc.planted_date is not null then 'confirmed' else 'forecast' end,'sownOn',cc.sown_date,'plantedOn',cc.planted_date,'gates',atlas.tending_gates_v1(go.id,cc.id,null,cc.expected_harvest_watch_start),'remainingGateCount',(select count(*)::integer from jsonb_array_elements(atlas.tending_gates_v1(go.id,cc.id,null,cc.expected_harvest_watch_start)) gate where gate->>'status' not in ('complete','skipped')),'unlockLabel',coalesce(nullif(cc.variety,''),cc.crop_label),'requiresObservation',false,'isActionableNow',false,'sectionKey',case when cc.lifecycle_status='planned' then 'unlock_next' else 'protect_harvests' end,'miniGame',null)) into v_fallback
  from atlas.growing_objects go left join atlas.zones z on z.id=go.zone_id join lateral (select cycle.* from atlas.crop_cycles cycle where cycle.farm_id=p_farm_id and cycle.object_id=go.id and cycle.lifecycle_status in ('active','planned') order by case when cycle.lifecycle_status='active' then 0 else 1 end,cycle.expected_harvest_watch_start nulls last,cycle.created_at desc limit 1) cc on true left join atlas.crop_profiles cp on cp.id=cc.crop_profile_id where go.id=v_object_id;
  if v_fallback is null then raise exception 'No active or planned crop track exists for this place.' using errcode='P0002'; end if;
  return jsonb_build_object('miniGamesEnabled',false,'bed',v_fallback);
end
$function$;

CREATE OR REPLACE FUNCTION atlas.weed_selected_crop_turnover_focus_v1(p_task_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_task atlas.tasks%rowtype;
  v_cycle atlas.crop_cycles%rowtype;
  v_role text;
  v_membership_id uuid;
  v_beds jsonb;
  v_surfaces jsonb;
  v_zone_label text;
begin
  select * into v_task from atlas.tasks where id=p_task_id;
  IF v_task.id IS NULL THEN
    RAISE EXCEPTION 'Source unavailable to this Person.' USING ERRCODE='42501';
  END IF;
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(v_task.farm_id);

  v_role:=atlas.current_farm_role(v_task.farm_id);
  v_membership_id:=atlas.current_membership_id(v_task.farm_id);
  if not atlas.is_farm_owner(v_task.farm_id)
     and not (v_role in ('farm_hand','manager') and v_membership_id is not null and v_task.assigned_membership_id=v_membership_id)
  then
    raise exception 'This Weed turnover card is not available to the signed-in farm member.' using errcode='42501';
  end if;

  if coalesce(v_task.metadata->>'weed_management_mode','')<>'clear_selected_crop' then
    return null;
  end if;

  select cc.* into v_cycle
  from atlas.task_crop_cycles tc join atlas.crop_cycles cc on cc.id=tc.crop_cycle_id
  where tc.task_id=v_task.id and tc.role='clears'
  order by tc.created_at limit 1;
  if v_cycle.id is null then raise exception 'Selected crop turnover has no crop body.' using errcode='P0002'; end if;

  select z.label into v_zone_label
  from atlas.task_objects x
  join atlas.growing_objects go on go.id=x.object_id
  left join atlas.zones z on z.id=go.zone_id
  where x.task_id=v_task.id and x.role='work_carrier'
  order by go.sort_order,go.label limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'objectId',go.id,
    'objectKey',go.stable_key,
    'objectLabel',go.label,
    'cardId',wc.id,
    'occupancyState',coalesce(q.occ->>'occupancyState','empty'),
    'availableForPlanting',coalesce((q.occ->>'availableForPlanting')::boolean,true),
    'occupancyGroups',coalesce(q.occ->'groups','[]'::jsonb)
  ) order by go.sort_order,go.label),'[]'::jsonb) into v_beds
  from atlas.task_objects x
  join atlas.growing_objects go on go.id=x.object_id
  left join atlas.weed_cards wc on wc.object_id=go.id
  left join lateral (select atlas.object_crop_occupancy_v1(go.id) as occ) q on true
  where x.task_id=v_task.id and x.role='work_carrier';

  select coalesce(jsonb_agg(jsonb_build_object(
    'objectId',go.id,
    'objectKey',go.stable_key,
    'objectLabel',go.label,
    'occupancyState',coalesce(q.occ->>'occupancyState','empty'),
    'availableForPlanting',coalesce((q.occ->>'availableForPlanting')::boolean,true),
    'occupancyGroups',coalesce(q.occ->'groups','[]'::jsonb)
  ) order by go.sort_order,go.label),'[]'::jsonb) into v_surfaces
  from atlas.task_objects x
  join atlas.growing_objects go on go.id=x.object_id
  left join lateral (select atlas.object_crop_occupancy_v1(go.id) as occ) q on true
  where x.task_id=v_task.id and x.role='capacity_surface';

  return jsonb_build_object(
    'contractVersion','weed_selected_crop_turnover_focus_v1',
    'taskId',v_task.id,
    'taskStatus',v_task.status,
    'taskDueDate',v_task.due_date,
    'mode','clear_selected_crop',
    'zoneLabel',coalesce(v_zone_label,'Elm Farm'),
    'collectionLabel',coalesce(nullif(v_task.metadata->>'turnover_collection_label',''),v_task.metadata->>'display_location','Bed turnover'),
    'selectedCrop',jsonb_build_object(
      'cropCycleId',v_cycle.id,
      'cropLabel',v_cycle.crop_label,
      'variety',v_cycle.variety,
      'cycleState',v_cycle.cycle_state,
      'biomassDestination',v_task.metadata->>'biomass_destination'
    ),
    'wholeBedTurnover',false,
    'rootBedPositionKnown',coalesce((v_task.metadata->>'selected_crop_root_bed_position_known')::boolean,false),
    'beds',v_beds,
    'capacitySurfaces',v_surfaces
  );
end;
$function$;

CREATE OR REPLACE FUNCTION atlas.worker_day_operational_task_cards_v1(p_farm_id uuid, p_membership_id uuid, p_task_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_target atlas.farm_memberships%rowtype;
  v_move_context jsonb := '{}'::jsonb;
  v_cards jsonb := '[]'::jsonb;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  select * into v_target
  from atlas.farm_memberships membership
  where membership.id = p_membership_id
    and membership.farm_id = p_farm_id
    and membership.active = true;

  if v_target.id is null then
    raise exception 'Active target membership required.' using errcode='42501';
  end if;

  if v_target.user_id is distinct from auth.uid()
     and not atlas.is_farm_manager_or_owner(p_farm_id) then
    raise exception 'Only farm management may read another member''s operational Day cards.' using errcode='42501';
  end if;

  if coalesce(array_length(p_task_ids, 1), 0) = 0 then
    return '[]'::jsonb;
  end if;

  v_move_context := coalesce(atlas.task_move_context_batch_v1(p_task_ids), '{}'::jsonb);

  select coalesce(jsonb_agg(card order by card.ordinal), '[]'::jsonb)
  into v_cards
  from (
    select
      array_position(p_task_ids, task.id) as ordinal,
      jsonb_build_object(
        'farm_key', farm.stable_key,
        'task_id', task.id,
        'title', task.title,
        'task_type', task.task_type,
        'status', task.status,
        'priority', task.priority,
        'due_date', task.due_date,
        'unlock_text', task.unlock_text,
        'blocker_text', task.blocker_text,
        'note', task.note,
        'generated_from', task.generated_from,
        'generated_from_id', task.generated_from_id,
        'action_key', task.action_key,
        'work_class', task.work_class,
        'operation_class', task.operation_class,
        'operation_class_source', task.operation_class_source,
        'parent_task_id', task.parent_task_id,
        'task_series_key', task.task_series_key,
        'engine_instance_key', task.engine_instance_key,
        'created_at', task.created_at,
        'updated_at', task.updated_at,
        'metadata', coalesce(task.metadata, '{}'::jsonb),
        'zone_id', zone.id,
        'zone_key', zone.stable_key,
        'zone_label', zone.label,
        'objects', coalesce(objects.items, '[]'::jsonb),
        'resource_requirements', '[]'::jsonb,
        'action_templates', '[]'::jsonb,
        'task_logs', '[]'::jsonb,
        'task_outcomes', coalesce(outcome.items, '[]'::jsonb),
        'task_transitions', coalesce(transition.items, '[]'::jsonb),
        'move_context', v_move_context -> task.id::text
      ) as card
    from atlas.tasks task
    join atlas.farms farm on farm.id = task.farm_id
    left join atlas.zones zone on zone.id = task.zone_id
    left join lateral (
      select jsonb_agg(jsonb_build_object(
        'object_id', growing.id,
        'object_key', growing.stable_key,
        'object_label', growing.label,
        'object_type', growing.object_type,
        'object_mode', growing.object_mode,
        'life_status', state.life_status,
        'weed_pressure', state.weed_pressure,
        'water_status', state.water_status,
        'last_touched_at', state.last_touched_at,
        'last_weeded_at', state.last_weeded_at,
        'last_watered_at', state.last_watered_at,
        'last_checked_at', state.last_checked_at,
        'decision_required', state.decision_required,
        'presentability', state.presentability,
        'state_metadata', state.metadata
      ) order by link.role, growing.label, growing.id) as items
      from atlas.task_objects link
      join atlas.growing_objects growing on growing.id = link.object_id
      left join atlas.object_state state on state.object_id = growing.id
      where link.task_id = task.id
    ) objects on true
    left join lateral (
      select jsonb_agg(item) as items
      from (
        select jsonb_build_object(
          'event_id', event.id,
          'outcome', event.outcome,
          'lane_key', event.lane_key,
          'work_key', event.work_key,
          'blocker_reason', event.blocker_reason,
          'note', event.note,
          'created_at', event.created_at
        ) as item
        from atlas.task_outcome_events event
        where event.task_id = task.id
        order by event.created_at desc, event.id desc
        limit 1
      ) latest
    ) outcome on true
    left join lateral (
      select jsonb_agg(item) as items
      from (
        select jsonb_build_object(
          'transition_id', event.id,
          'transition', event.transition,
          'previous_status', event.previous_status,
          'next_status', event.next_status,
          'previous_due_date', event.previous_due_date,
          'target_date', event.target_date,
          'action_key', event.action_key,
          'work_class', event.work_class,
          'note', event.note,
          'reason', event.reason,
          'field_log_id', event.field_log_id,
          'created_at', event.created_at
        ) as item
        from atlas.task_transitions event
        where event.task_id = task.id
        order by event.created_at desc, event.id desc
        limit 1
      ) latest
    ) transition on true
    where task.farm_id = p_farm_id
      and task.id = any(p_task_ids)
      and coalesce(task.visibility_scope,'') <> 'system_internal'
      and (task.status='done' or (atlas.task_temporally_eligible_v1(task.id,(now() at time zone 'America/Chicago')::date) and atlas.task_required_resources_available_v1(task.id)))
      and (
        task.assigned_membership_id = p_membership_id
        or task.metadata ->> 'executor_membership_id' = p_membership_id::text
        or task.id in (
          select placement.task_id
          from atlas.worker_day_task_placements placement
          where placement.farm_id = p_farm_id
            and placement.membership_id = p_membership_id
            and placement.task_id = task.id
        )
      )
  ) card;

  return v_cards;
end;
$function$;

CREATE OR REPLACE FUNCTION atlas.worker_hand_context_v1(p_farm_id uuid, p_target_membership_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(farm_id uuid, farm_name text, viewer_role text, worker_membership_id uuid, worker_display_name text, worker_key text, can_act boolean, unassigned_worker_task_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_role text;
  v_current_membership_id uuid;
  v_target_membership_id uuid;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  v_role := atlas.current_farm_role(p_farm_id);
  if v_role is null then
    raise exception 'Active farm membership required.' using errcode = '42501';
  end if;

  v_current_membership_id := atlas.current_membership_id(p_farm_id);
  v_target_membership_id := atlas.resolve_worker_view_membership_v1(
    p_farm_id,
    p_target_membership_id
  );

  return query
  select
    f.id,
    f.name,
    v_role,
    fm.id,
    coalesce(up.display_name, au.email, fm.worker_key, 'Farm Hand')::text,
    fm.worker_key,
    (v_role = 'farm_hand' and fm.id = v_current_membership_id),
    case
      when v_role in ('owner', 'manager') then (
        select count(*)
        from atlas.tasks t
        where t.farm_id = p_farm_id
          and t.visibility_scope = 'assigned_worker'
          and t.assigned_membership_id is null
          and t.status in ('open', 'blocked')
      )
      else 0::bigint
    end
  from atlas.farms f
  left join atlas.farm_memberships fm
    on fm.id = v_target_membership_id
  left join auth.users au
    on au.id = fm.user_id
  left join atlas.user_profiles up
    on up.user_id = fm.user_id
  where f.id = p_farm_id;
end;
$function$;
-- Original held candidate: universal_subject_bounded_disclosure_v1/candidate.sql
-- A Person's exact Work responsibility and a native Ledger seat never grant
-- broad Subject discovery. Governor decisions are append-only and field-bounded.
CREATE TABLE atlas.subject_disclosure_decision_events_v1 (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
 ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
 target_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 subject_domain text NOT NULL,
 subject_kind text NOT NULL,
 subject_id uuid NOT NULL,
 disclosure_class text NOT NULL CHECK(disclosure_class IN ('identity','condition')),
 decision_kind text NOT NULL CHECK(decision_kind IN ('grant','withhold')),
 source_action_id uuid NOT NULL,
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 12 AND 1600),
 decided_by_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT subject_disclosure_action_identity_v1 UNIQUE(ledger_id,source_action_id),
 CONSTRAINT subject_disclosure_supported_subject_v1 CHECK(
   subject_domain='spatial' AND subject_kind='growing_object'
 )
);
CREATE OR REPLACE FUNCTION atlas.block_subject_disclosure_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 RAISE EXCEPTION 'Original Subject disclosure decisions are append-only.'
 USING ERRCODE='42501';
END;
$function$;
REVOKE ALL ON FUNCTION atlas.block_subject_disclosure_mutation_v1()
 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER subject_disclosure_append_only_v1
 BEFORE UPDATE OR DELETE ON atlas.subject_disclosure_decision_events_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.block_subject_disclosure_mutation_v1();

CREATE INDEX subject_disclosure_current_lookup_v1
 ON atlas.subject_disclosure_decision_events_v1(
 ledger_id,target_person_id,subject_domain,subject_kind,subject_id,
 disclosure_class,recorded_at DESC,id DESC);
ALTER TABLE atlas.subject_disclosure_decision_events_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.subject_disclosure_decision_events_v1 FROM PUBLIC,anon,authenticated;

-- Deliberately not accessible from the browser or authenticated RPC directly.
-- Strict current decision, not 'an old grant somewhere in history'.
CREATE OR REPLACE FUNCTION atlas.has_current_subject_disclosure_v1(
 p_ledger_id uuid,p_person_id uuid,p_subject_domain text,p_subject_kind text,
 p_subject_id uuid,p_disclosure_class text
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT coalesce((
  SELECT e.decision_kind='grant'
  FROM atlas.subject_disclosure_decision_events_v1 e
  WHERE e.ledger_id=p_ledger_id AND e.target_person_id=p_person_id
   AND e.subject_domain=p_subject_domain AND e.subject_kind=p_subject_kind
   AND e.subject_id=p_subject_id AND e.disclosure_class=p_disclosure_class
  ORDER BY e.recorded_at DESC,e.id DESC LIMIT 1
 ),false);
$function$;
REVOKE ALL ON FUNCTION atlas.has_current_subject_disclosure_v1(
 uuid,uuid,text,text,uuid,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION atlas.governor_set_subject_disclosure_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_target_person_id uuid,
 p_subject_domain text,p_subject_kind text,p_subject_id uuid,
 p_disclosure_class text,p_decision_kind text,p_source_action_id uuid,p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_owner uuid;v_existing atlas.subject_disclosure_decision_events_v1%rowtype;
 v_created atlas.subject_disclosure_decision_events_v1%rowtype;
BEGIN
 IF p_target_person_id IS NULL OR p_subject_id IS NULL OR p_source_action_id IS NULL
   OR p_subject_domain<>'spatial' OR p_subject_kind<>'growing_object'
   OR p_disclosure_class NOT IN ('identity','condition')
   OR p_decision_kind NOT IN ('grant','withhold')
   OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 12 AND 1600 THEN
   RAISE EXCEPTION 'Exact bounded original Subject disclosure decision required.'
     USING ERRCODE='22023';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF NOT atlas.person_has_native_ledger_connection_v1(
    p_organization_id,p_ledger_id,p_target_person_id) THEN
   RAISE EXCEPTION 'Connected Person or Ledger unavailable.' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(
   SELECT 1 FROM atlas.growing_objects o
   JOIN atlas.farms f ON f.id=o.farm_id
   WHERE o.id=p_subject_id AND f.organization_id=p_organization_id
 ) THEN
   RAISE EXCEPTION 'Original Subject unavailable on governed Ledger.'
     USING ERRCODE='42501';
 END IF;
 -- Serialize all competing grants/withholds on this exact Person + Subject
 -- + field class, not just retries with the same idempotency key.
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'atlas.subject_disclosure:'||p_ledger_id::text||':'||
  p_target_person_id::text||':'||p_subject_domain||':'||
  p_subject_kind||':'||p_subject_id::text||':'||p_disclosure_class,0));
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'atlas.subject_action:'||p_ledger_id::text||':'||p_source_action_id::text,0));
 SELECT * INTO v_existing
 FROM atlas.subject_disclosure_decision_events_v1
 WHERE ledger_id=p_ledger_id AND source_action_id=p_source_action_id;
 IF v_existing.id IS NOT NULL THEN
   IF v_existing.organization_id IS DISTINCT FROM p_organization_id
    OR v_existing.target_person_id IS DISTINCT FROM p_target_person_id
    OR v_existing.subject_domain IS DISTINCT FROM p_subject_domain
    OR v_existing.subject_kind IS DISTINCT FROM p_subject_kind
    OR v_existing.subject_id IS DISTINCT FROM p_subject_id
    OR v_existing.disclosure_class IS DISTINCT FROM p_disclosure_class
    OR v_existing.decision_kind IS DISTINCT FROM p_decision_kind
    OR v_existing.reason IS DISTINCT FROM btrim(p_reason) THEN
    RAISE EXCEPTION 'Decision action ID already used for different disclosure.'
      USING ERRCODE='23505';
   END IF;
   v_created:=v_existing;
 ELSE
   INSERT INTO atlas.subject_disclosure_decision_events_v1(
     organization_id,ledger_id,target_person_id,subject_domain,subject_kind,
     subject_id,disclosure_class,decision_kind,source_action_id,reason,decided_by_person_id,recorded_at
   ) VALUES(
     p_organization_id,p_ledger_id,p_target_person_id,p_subject_domain,p_subject_kind,
     p_subject_id,p_disclosure_class,p_decision_kind,p_source_action_id,btrim(p_reason),v_owner,clock_timestamp()
   ) RETURNING * INTO v_created;
 END IF;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','bounded_original_subject_disclosure_v1',
   'decisionId',v_created.id,'sourceActionId',p_source_action_id,
   'organizationId',p_organization_id,'ledgerId',p_ledger_id,
   'targetPersonId',p_target_person_id,'subjectDomain',p_subject_domain,
   'subjectKind',p_subject_kind,'subjectId',p_subject_id,
   'disclosureClass',p_disclosure_class,'decisionKind',p_decision_kind,
   'currentlyGranted',atlas.has_current_subject_disclosure_v1(
     p_ledger_id,p_target_person_id,p_subject_domain,p_subject_kind,
     p_subject_id,p_disclosure_class),
   'historicalDecisionPreserved',true
 );
END;
$function$;
REVOKE ALL ON FUNCTION atlas.governor_set_subject_disclosure_self_api_v1(
 uuid,uuid,uuid,text,text,uuid,text,text,uuid,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.governor_set_subject_disclosure_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_target_person_id uuid,
 p_subject_domain text,p_subject_kind text,p_subject_id uuid,
 p_disclosure_class text,p_decision_kind text,p_source_action_id uuid,p_reason text
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.governor_set_subject_disclosure_self_api_v1(
 p_organization_id,p_ledger_id,p_target_person_id,
 p_subject_domain,p_subject_kind,p_subject_id,
 p_disclosure_class,p_decision_kind,p_source_action_id,p_reason);
$function$;
REVOKE ALL ON FUNCTION public.governor_set_subject_disclosure_self_api_v1(
 uuid,uuid,uuid,text,text,uuid,text,text,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.governor_set_subject_disclosure_self_api_v1(
 uuid,uuid,uuid,text,text,uuid,text,text,uuid,text) TO authenticated;

-- Read ONE named original Subject via ONE actual admitted original Work.
-- A disclosed label/condition never implies authority over other children,
-- crop cycles, history, other Work, or full-farm aggregate views.
CREATE OR REPLACE FUNCTION atlas.connected_person_original_work_subject_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_subject_domain text,p_subject_kind text,p_subject_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_person uuid;v_owner boolean:=false;v_identity boolean:=false;
 v_condition boolean:=false;v_object atlas.growing_objects%rowtype;
 v_condition_state atlas.object_state%rowtype;
BEGIN
 IF auth.uid() IS NULL OR
   (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
   OR p_subject_domain<>'spatial' OR p_subject_kind<>'growing_object'
   OR p_work_item_id IS NULL OR p_subject_id IS NULL THEN
   RAISE EXCEPTION 'Original Work Subject unavailable.' USING ERRCODE='42501';
 END IF;
 v_person:=atlas.current_person_id_v1();
 IF v_person IS NULL OR NOT atlas.person_has_native_ledger_connection_v1(
   p_organization_id,p_ledger_id,v_person) THEN
   RAISE EXCEPTION 'Original Work Subject unavailable.' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(
   SELECT 1 FROM atlas.work_items w
   JOIN atlas.company_work_native_ledger_relevance rel
     ON rel.work_item_id=w.id AND rel.organization_id=w.organization_id
      AND rel.ledger_id=p_ledger_id AND rel.attribution_state='active'
   JOIN atlas.work_item_context_links link
     ON link.work_item_id=w.id AND link.organization_id=w.organization_id
      AND link.subject_domain=p_subject_domain
      AND link.subject_kind=p_subject_kind AND link.subject_id=p_subject_id
   WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id
      AND w.work_state='open'
 ) THEN
   RAISE EXCEPTION 'Original Work Subject unavailable.' USING ERRCODE='42501';
 END IF;
 -- The relevant Work also must be the signed Person's own accepted responsibility
 -- unless they actually govern this native Ledger.
 BEGIN
   PERFORM atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
   v_owner:=true;
 EXCEPTION WHEN OTHERS THEN v_owner:=false;
 END;
 IF NOT v_owner AND NOT EXISTS(
    SELECT 1 FROM atlas.work_allocations a
    WHERE a.work_item_id=p_work_item_id
      AND a.organization_id=p_organization_id
      AND a.assignee_canonical_person_id=v_person
      AND a.allocation_role='responsible' AND a.state='active'
   ) THEN
   RAISE EXCEPTION 'Original Work Subject unavailable.' USING ERRCODE='42501';
 END IF;
 v_identity:=v_owner OR atlas.has_current_subject_disclosure_v1(
   p_ledger_id,v_person,p_subject_domain,p_subject_kind,p_subject_id,'identity');
 IF NOT v_identity THEN
   RAISE EXCEPTION 'Original Work Subject unavailable.' USING ERRCODE='42501';
 END IF;
 v_condition:=v_owner OR atlas.has_current_subject_disclosure_v1(
   p_ledger_id,v_person,p_subject_domain,p_subject_kind,p_subject_id,'condition');
 SELECT o.* INTO v_object FROM atlas.growing_objects o
 JOIN atlas.farms f ON f.id=o.farm_id
 WHERE o.id=p_subject_id AND f.organization_id=p_organization_id;
 IF v_object.id IS NULL THEN
   RAISE EXCEPTION 'Original Work Subject unavailable.' USING ERRCODE='42501';
 END IF;
 IF v_condition THEN
   SELECT * INTO v_condition_state FROM atlas.object_state
    WHERE object_id=v_object.id;
 END IF;
 RETURN jsonb_build_object(
    'ok',true,'contractVersion','connected_person_original_work_subject_v1',
    'workItemId',p_work_item_id,'ledgerId',p_ledger_id,
    'subjectDomain',p_subject_domain,'subjectKind',p_subject_kind,
    'subjectId',v_object.id,'subjectLabel',v_object.label,
    'subjectType',v_object.object_type,
    'conditionDisclosed',v_condition,
    'condition',CASE WHEN v_condition THEN jsonb_strip_nulls(jsonb_build_object(
       'lifeStatus',v_condition_state.life_status,
       'careState',v_condition_state.care_state,
       'careObservedAt',v_condition_state.care_observed_at,
       'careFreshness',v_condition_state.care_freshness
    )) ELSE NULL END,
    'cropPlacementDetailsDisclosed',false,
    'notesAndMetadataDisclosed',false,
    'fullFarmReaderAccessGranted',false
 );
END;
$function$;
REVOKE ALL ON FUNCTION atlas.connected_person_original_work_subject_self_api_v1(
 uuid,uuid,uuid,text,text,uuid) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.connected_person_original_work_subject_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_subject_domain text,p_subject_kind text,p_subject_id uuid
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.connected_person_original_work_subject_self_api_v1(
 p_organization_id,p_ledger_id,p_work_item_id,
 p_subject_domain,p_subject_kind,p_subject_id);
$function$;
REVOKE ALL ON FUNCTION public.connected_person_original_work_subject_self_api_v1(
 uuid,uuid,uuid,text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.connected_person_original_work_subject_self_api_v1(
 uuid,uuid,uuid,text,text,uuid) TO authenticated;
-- Enumerate only the signed Person's admitted original Subject links for one
-- exact authorized Work; never publish undisclosed subjects or their counts.
CREATE OR REPLACE FUNCTION atlas.connected_person_work_subject_links_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_limit integer DEFAULT 30,p_after_subject_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_person uuid;v_owner boolean:=false;v_rows jsonb:='[]'::jsonb;
 v_more boolean:=false;v_next uuid;
BEGIN
 IF auth.uid() IS NULL OR
    (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
    OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 OR p_work_item_id IS NULL THEN
  RAISE EXCEPTION 'Original Work Subjects unavailable.' USING ERRCODE='42501';
 END IF;
 v_person:=atlas.current_person_id_v1();
 IF v_person IS NULL OR NOT atlas.person_has_native_ledger_connection_v1(
    p_organization_id,p_ledger_id,v_person) THEN
  RAISE EXCEPTION 'Original Work Subjects unavailable.' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(
    SELECT 1 FROM atlas.work_items w
    JOIN atlas.company_work_native_ledger_relevance r
     ON r.work_item_id=w.id AND r.organization_id=w.organization_id
       AND r.ledger_id=p_ledger_id AND r.attribution_state='active'
    WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id
 ) THEN
  RAISE EXCEPTION 'Original Work Subjects unavailable.' USING ERRCODE='42501';
 END IF;
 BEGIN
   PERFORM atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
   v_owner:=true;
 EXCEPTION WHEN OTHERS THEN v_owner:=false;
 END;
 IF NOT v_owner AND NOT EXISTS(
    SELECT 1 FROM atlas.work_items w
    JOIN atlas.work_allocations a ON a.work_item_id=w.id
      AND a.organization_id=w.organization_id
    WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id
      AND w.work_state='open'
      AND a.assignee_canonical_person_id=v_person
      AND a.allocation_role='responsible' AND a.state='active'
 ) THEN
    RAISE EXCEPTION 'Original Work Subjects unavailable.' USING ERRCODE='42501';
 END IF;
 WITH allowed AS (
   SELECT DISTINCT ON(c.subject_id)
     c.subject_id,c.subject_domain,c.subject_kind,o.label
   FROM atlas.work_item_context_links c
   JOIN atlas.growing_objects o ON o.id=c.subject_id
   JOIN atlas.farms f ON f.id=o.farm_id AND f.organization_id=p_organization_id
   WHERE c.organization_id=p_organization_id
      AND c.work_item_id=p_work_item_id
      AND c.subject_domain='spatial' AND c.subject_kind='growing_object'
      AND (p_after_subject_id IS NULL OR c.subject_id>p_after_subject_id)
      AND (v_owner OR atlas.has_current_subject_disclosure_v1(
         p_ledger_id,v_person,c.subject_domain,c.subject_kind,c.subject_id,'identity'))
   ORDER BY c.subject_id
 ), page AS (
    SELECT *,row_number() OVER(ORDER BY subject_id) rn
    FROM allowed ORDER BY subject_id LIMIT p_limit+1
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
     'subjectDomain',q.subject_domain,'subjectKind',q.subject_kind,
     'subjectId',q.subject_id,'subjectLabel',q.label
    ) ORDER BY q.subject_id) FILTER(WHERE q.rn<=p_limit),'[]'::jsonb),
    count(*)>p_limit,max(q.subject_id) FILTER(WHERE q.rn<=p_limit)
 INTO v_rows,v_more,v_next FROM page q;
 RETURN jsonb_build_object(
    'ok',true,'contractVersion','connected_person_work_subject_links_v1',
    'workItemId',p_work_item_id,'ledgerId',p_ledger_id,
    'items',v_rows,'hasMore',v_more,
    'nextAfterSubjectId',CASE WHEN v_more THEN v_next ELSE NULL END,
    'undisclosedSubjectsOmitted',true
 );
END;
$function$;
REVOKE ALL ON FUNCTION atlas.connected_person_work_subject_links_self_api_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.connected_person_work_subject_links_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_limit integer DEFAULT 30,p_after_subject_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.connected_person_work_subject_links_self_api_v1(
 p_organization_id,p_ledger_id,p_work_item_id,p_limit,p_after_subject_id);
$function$;
REVOKE ALL ON FUNCTION public.connected_person_work_subject_links_self_api_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.connected_person_work_subject_links_self_api_v1(
 uuid,uuid,uuid,integer,uuid) TO authenticated;
-- Original held candidate: governor_effective_subject_disclosure_review_v1/candidate.sql
-- Governor-only disclosure observation. Original source grants remain authority.
-- Never infer the target actor's successful signed call from a review projection.
CREATE OR REPLACE FUNCTION atlas.owner_effective_subject_disclosure_review_self_api_v1(
 p_organization_id uuid, p_ledger_id uuid, p_target_person_id uuid,
 p_limit integer DEFAULT 50, p_after_work_item_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
 v_owner uuid; v_primary uuid;
 v_target_governs boolean:=false;
 v_farms jsonb:='[]'::jsonb;
 v_work jsonb:='[]'::jsonb;
 v_more boolean:=false;
 v_next uuid;
BEGIN
 IF p_target_person_id IS NULL OR p_organization_id IS NULL OR p_ledger_id IS NULL
    OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 THEN
   RAISE EXCEPTION 'Exact Ledger, Person and bounded page required.' USING ERRCODE='22023';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF NOT EXISTS (
   SELECT 1 FROM ledger.seats s
   JOIN reality.entities e ON e.id=s.person_entity_id
    AND e.entity_kind='person' AND e.identity_state='canonical'
   WHERE s.ledger_id=p_ledger_id AND s.person_entity_id=p_target_person_id
    AND s.seat_state='active' AND s.ended_at IS NULL
 ) THEN
   RAISE EXCEPTION 'Connected Person unavailable on governed Ledger.' USING ERRCODE='42501';
 END IF;
 SELECT lop.ledger_id INTO v_primary FROM atlas.ledger_organization_participations lop
 WHERE lop.organization_id=p_organization_id AND lop.status='active' AND lop.ended_at IS NULL
   AND lop.is_compatibility_primary AND lop.participation_kind='governing' LIMIT 1;
 -- The target's own independent authority must still be signed-tested.
 SELECT EXISTS(
   SELECT 1 FROM atlas.principals p
   JOIN atlas.principal_ledger_authorities a ON a.principal_id=p.id
    AND a.ledger_id=p_ledger_id AND a.status='active'
    AND a.authority_kind='root_governing' AND a.ended_at IS NULL
   JOIN atlas.principal_ledger_authorities g ON g.principal_id=p.id
    AND g.ledger_id=v_primary AND g.status='active'
    AND g.authority_kind='root_governing' AND g.ended_at IS NULL
   WHERE p.person_id=p_target_person_id AND p.status='active'
 ) INTO v_target_governs;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
    'farmId',q.farm_id,
    'legacyFarmMembershipPresent',q.legacy_count>0,
    'legacyRoles',q.legacy_roles,
    'oldMembershipConfersCurrentDisclosure',false,
    'wideReaderRule','governing_ledger_authority_only',
    'governorSourceEstimate',v_target_governs,
    'directSignedCallStillRequired',true
 ) ORDER BY q.farm_id),'[]'::jsonb) INTO v_farms
 FROM (
   SELECT f.id farm_id,count(fm.id) legacy_count,
     coalesce(jsonb_agg(DISTINCT fm.role) FILTER(WHERE fm.id IS NOT NULL),'[]'::jsonb) legacy_roles
   FROM atlas.farms f
   LEFT JOIN atlas.farm_memberships fm ON fm.farm_id=f.id AND fm.active
     AND EXISTS (
       SELECT 1 FROM reality.auth_person_bindings b
       WHERE b.auth_user_id=fm.user_id AND b.person_entity_id=p_target_person_id
          AND b.binding_state='active' AND b.retired_at IS NULL
     )
   WHERE f.organization_id=p_organization_id
   GROUP BY f.id
 ) q;
 WITH selected AS (
    SELECT w.id,w.title,w.work_state,a.id allocation_id
    FROM atlas.work_items w
    JOIN atlas.work_allocations a ON a.work_item_id=w.id
      AND a.organization_id=w.organization_id
      AND a.assignee_canonical_person_id=p_target_person_id
      AND a.state='active' AND a.allocation_role='responsible'
    JOIN atlas.company_work_native_ledger_relevance rel
      ON rel.work_item_id=w.id AND rel.organization_id=w.organization_id
      AND rel.ledger_id=p_ledger_id AND rel.attribution_state='active'
    WHERE w.organization_id=p_organization_id AND w.work_state='open'
      AND (p_after_work_item_id IS NULL OR w.id>p_after_work_item_id)
    ORDER BY w.id
    LIMIT p_limit+1
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
     'workItemId',b.id,'title',b.title,'workState',b.work_state,
     'allocationId',b.allocation_id
   ) ORDER BY b.id) FILTER(WHERE b.rn<=p_limit),'[]'::jsonb),
   count(*)>p_limit,
   max(b.id) FILTER(WHERE b.rn<=p_limit)
 INTO v_work,v_more,v_next
 FROM (SELECT selected.*,row_number() over (order by id) rn FROM selected) b;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','governor_effective_subject_disclosure_review_v1',
   'organizationId',p_organization_id,'ledgerId',p_ledger_id,
   'reviewedPersonId',p_target_person_id,'governorPersonId',v_owner,
   'governorOnly',true,'isSignedTargetAccessProof',false,
   'targetActiveNativeLedgerConnectionConfirmed',true,
   'legacyFarmSources',v_farms,
   'broadLegacyFarmReaderPaths',jsonb_build_array(
      'zone_registry_source_v1','object_crop_bed_map_v1','farm_care_zone_v1',
      'farm_care_object_v1','farm_care_summary_v1','farm_snapshot_for_member_v1',
      'bed_components_state_v1',
      'farm_continuity_audit_v1',
      'farm_continuity_audit_v2',
      'farm_continuity_audit_v3',
      'grow_room_state_v1',
      'mowing_rhythm_dashboard_v1',
      'real_operation_explanation_v1',
      'tending_board_v1',
      'walkway_cards_v1',
      'weed_card_task_focus_v1',
      'weeding_cycle_v1',
      'weeding_rhythm_pilot_v1',
      'maintenance_directive_context_v1',
      'manual_task_context_v1',
      'resolve_effective_rhythm_rule_v1',
      'task_schedule_v1',
      'tending_bed_v1',
      'weed_selected_crop_turnover_focus_v1',
      'worker_day_operational_task_cards_v1',
      'worker_hand_context_v1'),
   'broadReadersRequireCurrentGoverningAuthority',true,
   'signedAlternativeReaderCoverageComplete',false,
   'canonicalWork',v_work,'hasMore',v_more,
   'nextAfterWorkItemId',CASE WHEN v_more THEN v_next ELSE NULL END,
   'directSignedOwnerWorkerOutsiderAndAnonymousTestsRequired',true
 );
END;
$function$;
REVOKE ALL ON FUNCTION atlas.owner_effective_subject_disclosure_review_self_api_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.owner_effective_subject_disclosure_review_self_api_v1(
 p_organization_id uuid, p_ledger_id uuid, p_target_person_id uuid,
 p_limit integer DEFAULT 50, p_after_work_item_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.owner_effective_subject_disclosure_review_self_api_v1(
  p_organization_id,p_ledger_id,p_target_person_id,p_limit,p_after_work_item_id);
$function$;
REVOKE ALL ON FUNCTION public.owner_effective_subject_disclosure_review_self_api_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.owner_effective_subject_disclosure_review_self_api_v1(
 uuid,uuid,uuid,integer,uuid) TO authenticated;
-- Original held candidate: original_subject_choices_for_work_decomposition_v1/candidate.sql
-- The user chooses exact existing Subjects; no title-matching or farm-task import.
-- This generic Work-subject choice seam may gain further source adapters in
-- reviewed migrations. Current spatial choice reads original growing_objects.
CREATE OR REPLACE FUNCTION atlas.owner_original_subject_choices_for_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_limit integer DEFAULT 80,p_after_subject_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
 v_person uuid;
 v_rows jsonb:='[]'::jsonb;
 v_next uuid;
 v_more boolean:=false;
BEGIN
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR p_work_item_id IS NULL THEN
  RAISE EXCEPTION 'Exact Work and bounded page required' USING ERRCODE='22023';
 END IF;
 v_person:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF NOT EXISTS(
    SELECT 1 FROM atlas.work_items w
    JOIN atlas.company_work_native_ledger_relevance rel
      ON rel.work_item_id=w.id AND rel.organization_id=w.organization_id
      AND rel.ledger_id=p_ledger_id AND rel.attribution_state='active'
    WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id
      AND w.work_state='open'
 ) THEN
  RAISE EXCEPTION 'Original Work not admitted on this Ledger' USING ERRCODE='42501';
 END IF;
 WITH page AS(
  SELECT o.id, o.label, o.object_type,
   row_number() OVER(ORDER BY o.id) rn
  FROM atlas.growing_objects o
  JOIN atlas.farms f ON f.id=o.farm_id
  WHERE f.organization_id=p_organization_id
    AND (p_after_subject_id IS NULL OR o.id>p_after_subject_id)
  ORDER BY o.id LIMIT p_limit+1
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
    'subjectDomain','spatial','subjectKind','growing_object',
    'subjectId',q.id,'label',q.label,'kindLabel',q.object_type)
    ORDER BY q.id) FILTER(WHERE q.rn<=p_limit),'[]'::jsonb),
    count(*)>p_limit,max(q.id) FILTER(WHERE q.rn<=p_limit)
 INTO v_rows,v_more,v_next FROM page q;
 RETURN jsonb_build_object('ok',true,
   'contractVersion','owner_original_subject_choices_for_work_v1',
   'organizationId',p_organization_id,'ledgerId',p_ledger_id,
   'workItemId',p_work_item_id,'choices',v_rows,'hasMore',v_more,
   'nextAfterSubjectId',CASE WHEN v_more THEN v_next ELSE NULL END,
   'choicesAreNotResponsibilities',true);
END;
$function$;
REVOKE ALL ON FUNCTION atlas.owner_original_subject_choices_for_work_self_api_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC,authenticated,anon;
CREATE OR REPLACE FUNCTION public.owner_original_subject_choices_for_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_limit integer DEFAULT 80,p_after_subject_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.owner_original_subject_choices_for_work_self_api_v1(
 p_organization_id,p_ledger_id,p_work_item_id,p_limit,p_after_subject_id);
$function$;
REVOKE ALL ON FUNCTION public.owner_original_subject_choices_for_work_self_api_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.owner_original_subject_choices_for_work_self_api_v1(
 uuid,uuid,uuid,integer,uuid) TO authenticated;
-- Original held candidate: universal_original_work_decomposition_v1/candidate.sql
-- Reuse atlas.work_items, work_allocations, plans, results and original
-- Ledger relevance; this is decomposition/provenance, NOT a new task system.
ALTER TABLE atlas.work_item_context_links
 DROP CONSTRAINT work_item_context_links_subject_pair_v1;
ALTER TABLE atlas.work_item_context_links
 ADD CONSTRAINT work_item_context_links_subject_pair_v1 CHECK (
   (subject_domain='spatial' AND subject_kind IN ('zone','place','growing_object'))
   OR (subject_domain='identity' AND subject_kind IN ('identity_subject','external_relationship'))
   OR (subject_domain='temporal' AND subject_kind='occurrence')
 );

CREATE TABLE atlas.work_decomposition_groups (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 parent_work_item_id uuid NOT NULL REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
 authorized_ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
 action_id uuid NOT NULL,
 source_fingerprint text NOT NULL,
 decision_reason text NOT NULL CHECK(length(btrim(decision_reason)) BETWEEN 12 AND 1600),
 decided_by_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT work_decomposition_once_per_parent UNIQUE(parent_work_item_id),
 CONSTRAINT work_decomposition_unique_action UNIQUE(parent_work_item_id,action_id)
);
CREATE TABLE atlas.work_decomposition_members (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 group_id uuid NOT NULL REFERENCES atlas.work_decomposition_groups(id) ON DELETE RESTRICT,
 child_work_item_id uuid NOT NULL UNIQUE REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
 part_ordinal integer NOT NULL CHECK(part_ordinal BETWEEN 1 AND 12),
 subject_domain text NOT NULL,
 subject_kind text NOT NULL,
 subject_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT work_decomposition_member_unique_ordinal UNIQUE(group_id,part_ordinal),
 CONSTRAINT work_decomposition_member_distinct_subject UNIQUE(group_id,subject_domain,subject_kind,subject_id)
);
CREATE INDEX work_decomposition_subject_lookup_v1
 ON atlas.work_decomposition_members(subject_domain,subject_kind,subject_id);
ALTER TABLE atlas.work_decomposition_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.work_decomposition_members ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.work_decomposition_groups,atlas.work_decomposition_members
 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION atlas.split_original_canonical_work_owner_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_parent_work_item_id uuid,
 p_parts jsonb,p_action_id uuid,p_decision_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
 v_owner uuid;
 v_parent atlas.work_items%rowtype;
 v_group atlas.work_decomposition_groups%rowtype;
 v_part jsonb;
 v_subject_domain text;
 v_subject_kind text;
 v_subject_id uuid;
 v_title text;
 v_instructions text;
 v_result_contract text;
 v_child uuid;
 v_ordinal integer:=0;
 v_fingerprint text;
 v_children jsonb:='[]'::jsonb;
 v_count integer;
BEGIN
 IF p_organization_id IS NULL OR p_ledger_id IS NULL OR
    p_parent_work_item_id IS NULL OR p_action_id IS NULL OR
    jsonb_typeof(p_parts) IS DISTINCT FROM 'array' OR
    jsonb_array_length(p_parts) NOT BETWEEN 2 AND 12 OR
    length(btrim(coalesce(p_decision_reason,''))) NOT BETWEEN 12 AND 1600 THEN
   RAISE EXCEPTION 'Exact original Work, parts, action and decision required.' USING ERRCODE='22023';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 -- Serializes retries and competing decompositions of the SAME original ID.
 PERFORM pg_advisory_xact_lock(hashtextextended(
   'atlas.work.decomposition:'||p_parent_work_item_id::text,0));
 SELECT * INTO v_parent FROM atlas.work_items
  WHERE id=p_parent_work_item_id AND organization_id=p_organization_id FOR UPDATE;
 IF v_parent.id IS NULL THEN
   RAISE EXCEPTION 'Original Work unavailable on governed Ledger.' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS (
   SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
    WHERE rel.work_item_id=v_parent.id AND rel.organization_id=p_organization_id
      AND rel.ledger_id=p_ledger_id AND rel.attribution_state='active'
 ) THEN
   RAISE EXCEPTION 'Work lacks established relevance to governed Ledger.' USING ERRCODE='42501';
 END IF;
 v_fingerprint:=md5(p_parts::text||'|'||btrim(p_decision_reason));
 SELECT * INTO v_group FROM atlas.work_decomposition_groups
  WHERE parent_work_item_id=v_parent.id;
 IF v_group.id IS NOT NULL THEN
   IF v_group.action_id IS DISTINCT FROM p_action_id OR
      v_group.source_fingerprint IS DISTINCT FROM v_fingerprint THEN
     RAISE EXCEPTION 'Work was already decomposed by a different decision.' USING ERRCODE='23505';
   END IF;
   SELECT coalesce(jsonb_agg(jsonb_build_object(
      'workItemId',m.child_work_item_id,'resultContractKey',(
         SELECT w.result_contract_key FROM atlas.work_items w WHERE w.id=m.child_work_item_id
       ),'subjectDomain',m.subject_domain,
      'subjectKind',m.subject_kind,'subjectId',m.subject_id)
     ORDER BY m.part_ordinal),'[]'::jsonb) INTO v_children
     FROM atlas.work_decomposition_members m WHERE m.group_id=v_group.id;
   RETURN jsonb_build_object('ok',true,'contractVersion','original_canonical_work_decomposition_v1',
     'parentWorkItemId',v_parent.id,'decompositionId',v_group.id,'children',v_children,
     'idempotent',true,'parentHistoryPreserved',true,'childrenUnassigned',true);
 END IF;
 IF v_parent.work_state<>'open' THEN
   RAISE EXCEPTION 'Original Work must be open and current before decomposition.' USING ERRCODE='23514';
 END IF;
 -- No copies from old task rows; each part must be a different independently
 -- actionable original Subject with an admitted exact source.
 FOR v_part IN SELECT value FROM jsonb_array_elements(p_parts) LOOP
   v_ordinal:=v_ordinal+1;
   IF jsonb_typeof(v_part) IS DISTINCT FROM 'object' THEN
     RAISE EXCEPTION 'Each Work part must be a typed original Subject.' USING ERRCODE='22023';
   END IF;
   v_subject_domain:=nullif(btrim(v_part->>'subjectDomain'),'');
   v_subject_kind:=nullif(btrim(v_part->>'subjectKind'),'');
   v_title:=nullif(btrim(v_part->>'title'),'');
   v_instructions:=nullif(btrim(v_part->>'instructions'),'');
   v_result_contract:=coalesce(nullif(btrim(v_part->>'resultContractKey'),''),
     v_parent.result_contract_key);
   -- Preserving existing manager acceptance is the default. Changing it
   -- for one independently actionable part requires the governor's explicit
   -- physical worker-attestation decision, not an inferred old task setting.
   IF v_result_contract IS DISTINCT FROM v_parent.result_contract_key THEN
     IF v_parent.result_contract_key<>'ordinary_company_work_manager_acceptance_v1'
       OR v_result_contract<>'ordinary_company_work_worker_attestation_v1'
       OR coalesce(v_part->>'confirmWorkerAttestationAuthority','')<>'true'
       OR NOT EXISTS(
          SELECT 1 FROM atlas.work_result_contract_policies p
          WHERE p.contract_key=v_result_contract AND p.active
            AND p.source_domain='organization'
            AND p.acceptance_mode='worker_attestation'
       ) THEN
       RAISE EXCEPTION 'Original Work result authority change requires explicit authorized worker-attestation selection.'
         USING ERRCODE='23514';
     END IF;
   END IF;
   IF v_title IS NULL OR length(v_title)>300 OR
      length(coalesce(v_instructions,''))>3000 OR
      nullif(v_part->>'subjectId','') IS NULL THEN
     RAISE EXCEPTION 'Each part needs a meaningful bounded title and subject.' USING ERRCODE='22023';
   END IF;
   BEGIN v_subject_id:=(v_part->>'subjectId')::uuid;
   EXCEPTION WHEN others THEN
     RAISE EXCEPTION 'Invalid original Subject identifier.' USING ERRCODE='22023';
   END;
   IF v_subject_domain='spatial' AND v_subject_kind='growing_object' THEN
     IF NOT EXISTS(
       SELECT 1 FROM atlas.growing_objects obj
       JOIN atlas.farms f ON f.id=obj.farm_id
       WHERE obj.id=v_subject_id AND f.organization_id=p_organization_id
     ) THEN
       RAISE EXCEPTION 'Original Subject not admitted to governed Organization.'
         USING ERRCODE='42501';
     END IF;
   ELSIF v_subject_domain='temporal' AND v_subject_kind='occurrence' THEN
     IF NOT EXISTS(
       SELECT 1 FROM atlas.work_item_context_links c
       WHERE c.work_item_id=v_parent.id AND c.organization_id=p_organization_id
         AND c.subject_domain='temporal' AND c.subject_kind='occurrence'
         AND c.subject_id=v_subject_id
     ) THEN
       RAISE EXCEPTION 'Event part must retain its existing original Event link.'
         USING ERRCODE='42501';
     END IF;
   ELSE
     RAISE EXCEPTION 'Unverified Subject adapter; split is not authorized.'
       USING ERRCODE='42501';
   END IF;
   IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_parts) q
     WHERE q.value<>v_part
       AND q.value->>'subjectDomain'=v_subject_domain
       AND q.value->>'subjectKind'=v_subject_kind
       AND q.value->>'subjectId'=v_subject_id::text) THEN
     RAISE EXCEPTION 'Each part must have a distinct original Subject.'
       USING ERRCODE='23505';
   END IF;
 END LOOP;
 INSERT INTO atlas.work_decomposition_groups(
   parent_work_item_id,authorized_ledger_id,action_id,
   source_fingerprint,decision_reason,decided_by_person_id)
 VALUES (v_parent.id,p_ledger_id,p_action_id,v_fingerprint,
   btrim(p_decision_reason),v_owner) RETURNING * INTO v_group;
 v_ordinal:=0;
 FOR v_part IN SELECT value FROM jsonb_array_elements(p_parts) LOOP
   v_ordinal:=v_ordinal+1;
   v_subject_domain:=btrim(v_part->>'subjectDomain');
   v_subject_kind:=btrim(v_part->>'subjectKind');
   v_subject_id:=(v_part->>'subjectId')::uuid;
   v_title:=btrim(v_part->>'title');
   v_instructions:=nullif(btrim(v_part->>'instructions'),'');
   v_result_contract:=coalesce(nullif(btrim(v_part->>'resultContractKey'),''),
     v_parent.result_contract_key);
   INSERT INTO atlas.work_items(
      organization_id,title,instructions,work_state,source_object_type,
      source_object_id,result_contract_key,created_by_user_id,stable_key,metadata)
   VALUES (
      p_organization_id,v_title,v_instructions,'open','work_decomposition',
      v_parent.id,v_result_contract,auth.uid(),
      'decomposition:'||v_parent.id::text||':'||v_ordinal::text,
      jsonb_build_object(
        'canonicalWorkDecompositionGroupId',v_group.id,
        'originalParentWorkItemId',v_parent.id,
        'originalParentSourceType',v_parent.source_object_type,
        'originalParentSourceId',v_parent.source_object_id,
        'partOrdinal',v_ordinal,'notAnAssignment',true,
        'originalResultContractRetained',v_result_contract IS NOT DISTINCT FROM v_parent.result_contract_key,
        'resultAuthoritySelectedByGovernor',v_result_contract,
        'workerAttestationExplicit',v_result_contract='ordinary_company_work_worker_attestation_v1'
          AND v_result_contract IS DISTINCT FROM v_parent.result_contract_key
      )
   ) RETURNING id INTO v_child;
   INSERT INTO atlas.work_decomposition_members(
     group_id,child_work_item_id,part_ordinal,subject_domain,subject_kind,subject_id)
   VALUES (v_group.id,v_child,v_ordinal,v_subject_domain,v_subject_kind,v_subject_id);
   INSERT INTO atlas.work_item_context_links(
     organization_id,work_item_id,subject_domain,subject_kind,subject_id,
     relation_kind,provenance,metadata)
   VALUES (p_organization_id,v_child,v_subject_domain,v_subject_kind,v_subject_id,
     'acts_on',jsonb_build_object('source','original_work_decomposition',
     'parentWorkItemId',v_parent.id,'decisionId',v_group.id),'{}'::jsonb);
   INSERT INTO atlas.company_work_native_ledger_relevance(
     organization_id,work_item_id,ledger_id,evidence_kind,
     attestation_source_ref,attestation_reason,established_by_person_id)
   VALUES (p_organization_id,v_child,p_ledger_id,'owner_attested',
      'original-canonical-work:'||v_parent.id::text,
      btrim(p_decision_reason),v_owner);
   v_children:=v_children||jsonb_build_array(jsonb_build_object(
      'workItemId',v_child,'resultContractKey',v_result_contract,
      'subjectDomain',v_subject_domain,
      'subjectKind',v_subject_kind,'subjectId',v_subject_id));
 END LOOP;
 -- Stop the old combined Work from remaining an executable duplicate.
 -- Withdraw, do not rewrite or delete original plans, allocation or history.
 UPDATE atlas.work_execution_plans SET plan_state='withdrawn',
   plan_reason='Original Work decomposed into distinct current subjects.'
 WHERE work_item_id=v_parent.id AND plan_state IN ('active','needs_replan');
 UPDATE atlas.work_allocations SET state='released',
   released_at=now(),release_reason='Original Work decomposed; owner must establish distinct current responsibility.'
 WHERE work_item_id=v_parent.id AND state='active';
 UPDATE atlas.work_items SET work_state='superseded',
   metadata=metadata||jsonb_build_object('decomposedIntoWorkGroupId',v_group.id)
 WHERE id=v_parent.id AND work_state='open';
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count<>1 THEN RAISE EXCEPTION 'Original Work was not retired atomically.' USING ERRCODE='23514'; END IF;
 RETURN jsonb_build_object('ok',true,'contractVersion','original_canonical_work_decomposition_v1',
   'parentWorkItemId',v_parent.id,'decompositionId',v_group.id,'children',v_children,
   'idempotent',false,'parentHistoryPreserved',true,'childrenUnassigned',true,
   'originalResultContractKey',v_parent.result_contract_key);
END;
$function$;
REVOKE ALL ON FUNCTION atlas.split_original_canonical_work_owner_self_api_v1(
 uuid,uuid,uuid,jsonb,uuid,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.split_original_canonical_work_owner_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_parent_work_item_id uuid,
 p_parts jsonb,p_action_id uuid,p_decision_reason text
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.split_original_canonical_work_owner_self_api_v1(
   p_organization_id,p_ledger_id,p_parent_work_item_id,
   p_parts,p_action_id,p_decision_reason);
$function$;
REVOKE ALL ON FUNCTION public.split_original_canonical_work_owner_self_api_v1(
 uuid,uuid,uuid,jsonb,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.split_original_canonical_work_owner_self_api_v1(
 uuid,uuid,uuid,jsonb,uuid,text) TO authenticated;
-- Original held candidate: universal_household_canonical_work_custody_v1/candidate.sql
-- One canonical Work identity. Household is another protected custody context,
-- never a fabricated Organization. This release candidate MUST be applied after
-- the original growing-object Work Subject extension in PR #2265.
-- Keep old Organization/production/Event writers on their unchanged path.

ALTER TABLE atlas.work_items
 ADD COLUMN household_id uuid REFERENCES atlas.households(id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_items ALTER COLUMN organization_id DROP NOT NULL;
ALTER TABLE atlas.work_items
 ADD CONSTRAINT work_items_one_native_custody_v1
 CHECK ((organization_id IS NULL) <> (household_id IS NULL));

ALTER TABLE atlas.work_allocations
 ADD COLUMN household_id uuid REFERENCES atlas.households(id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_allocations ALTER COLUMN organization_id DROP NOT NULL;
ALTER TABLE atlas.work_allocations
 ADD CONSTRAINT work_allocations_one_native_custody_v1
 CHECK ((organization_id IS NULL) <> (household_id IS NULL));

ALTER TABLE atlas.work_execution_plans
 ADD COLUMN household_id uuid REFERENCES atlas.households(id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_execution_plans ALTER COLUMN organization_id DROP NOT NULL;
ALTER TABLE atlas.work_execution_plans
 ADD CONSTRAINT work_execution_plans_one_native_custody_v1
 CHECK ((organization_id IS NULL) <> (household_id IS NULL));

ALTER TABLE atlas.work_execution_plan_events
 ADD COLUMN household_id uuid REFERENCES atlas.households(id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_execution_plan_events ALTER COLUMN organization_id DROP NOT NULL;
ALTER TABLE atlas.work_execution_plan_events
 ADD CONSTRAINT work_execution_plan_events_one_native_custody_v1
 CHECK ((organization_id IS NULL) <> (household_id IS NULL));

ALTER TABLE atlas.work_execution_results
 ADD COLUMN household_id uuid REFERENCES atlas.households(id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_execution_results ALTER COLUMN organization_id DROP NOT NULL;
ALTER TABLE atlas.work_execution_results
 ADD CONSTRAINT work_execution_results_one_native_custody_v1
 CHECK ((organization_id IS NULL) <> (household_id IS NULL));

ALTER TABLE atlas.work_result_acceptances
 ADD COLUMN household_id uuid REFERENCES atlas.households(id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_result_acceptances ALTER COLUMN organization_id DROP NOT NULL;
ALTER TABLE atlas.work_result_acceptances
 ADD CONSTRAINT work_result_acceptances_one_native_custody_v1
 CHECK ((organization_id IS NULL) <> (household_id IS NULL));

ALTER TABLE atlas.work_item_context_links
 ADD COLUMN household_id uuid REFERENCES atlas.households(id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_item_context_links ALTER COLUMN organization_id DROP NOT NULL;
ALTER TABLE atlas.work_item_context_links
 ADD CONSTRAINT work_item_context_links_one_native_custody_v1
 CHECK ((organization_id IS NULL) <> (household_id IS NULL));

ALTER TABLE atlas.work_time_contracts
 ADD COLUMN household_id uuid REFERENCES atlas.households(id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_time_contracts ALTER COLUMN organization_id DROP NOT NULL;
ALTER TABLE atlas.work_time_contracts
 ADD CONSTRAINT work_time_contracts_one_native_custody_v1
 CHECK ((organization_id IS NULL) <> (household_id IS NULL));

-- An original Work and its dependent receipts can never be converted from
-- Household to Institution or the reverse by editing their custody columns.
-- The protected source requires a new Work identity and explicit provenance
-- for a genuine transfer, not a rewritten original.
CREATE OR REPLACE FUNCTION atlas.guard_canonical_work_custody_immutability_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF NEW.organization_id IS DISTINCT FROM OLD.organization_id OR
    NEW.household_id IS DISTINCT FROM OLD.household_id THEN
   RAISE EXCEPTION 'Original Work custody cannot be rewritten.'
     USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION atlas.guard_canonical_work_custody_immutability_v1()
 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER work_items_immutable_custody_v1
 BEFORE UPDATE OF organization_id,household_id ON atlas.work_items
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
CREATE TRIGGER work_allocations_immutable_custody_v1
 BEFORE UPDATE OF organization_id,household_id ON atlas.work_allocations
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
CREATE TRIGGER work_execution_plans_immutable_custody_v1
 BEFORE UPDATE OF organization_id,household_id ON atlas.work_execution_plans
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
CREATE TRIGGER work_execution_plan_events_immutable_custody_v1
 BEFORE UPDATE OF organization_id,household_id ON atlas.work_execution_plan_events
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
CREATE TRIGGER work_execution_results_immutable_custody_v1
 BEFORE UPDATE OF organization_id,household_id ON atlas.work_execution_results
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
CREATE TRIGGER work_result_acceptances_immutable_custody_v1
 BEFORE UPDATE OF organization_id,household_id ON atlas.work_result_acceptances
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
CREATE TRIGGER work_item_context_links_immutable_custody_v1
 BEFORE UPDATE OF organization_id,household_id ON atlas.work_item_context_links
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
CREATE TRIGGER work_time_contracts_immutable_custody_v1
 BEFORE UPDATE OF organization_id,household_id ON atlas.work_time_contracts
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();

-- Reference the SAME Work ID across contexts; composite foreign keys also
-- prevent cross-household Work/Plan/Result copying.
CREATE UNIQUE INDEX work_items_household_id_id_v1
 ON atlas.work_items(household_id,id);
CREATE UNIQUE INDEX work_items_household_stable_key_v1
 ON atlas.work_items(household_id,stable_key)
 WHERE household_id IS NOT NULL AND stable_key IS NOT NULL;
ALTER TABLE atlas.work_allocations
 ADD CONSTRAINT work_allocations_household_original_work_fk_v1
 FOREIGN KEY(household_id,work_item_id)
 REFERENCES atlas.work_items(household_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_execution_plans
 ADD CONSTRAINT work_execution_plans_household_original_work_fk_v1
 FOREIGN KEY(household_id,work_item_id)
 REFERENCES atlas.work_items(household_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_execution_results
 ADD CONSTRAINT work_execution_results_household_original_work_fk_v1
 FOREIGN KEY(household_id,work_item_id)
 REFERENCES atlas.work_items(household_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_result_acceptances
 ADD CONSTRAINT work_result_acceptances_household_original_work_fk_v1
 FOREIGN KEY(household_id,work_item_id)
 REFERENCES atlas.work_items(household_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_item_context_links
 ADD CONSTRAINT work_item_context_links_household_original_work_fk_v1
 FOREIGN KEY(household_id,work_item_id)
 REFERENCES atlas.work_items(household_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_time_contracts
 ADD CONSTRAINT work_time_contracts_household_original_work_fk_v1
 FOREIGN KEY(household_id,work_item_id)
 REFERENCES atlas.work_items(household_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_execution_plan_events
 ADD CONSTRAINT work_execution_plan_events_household_original_work_fk_v1
 FOREIGN KEY(household_id,work_item_id)
 REFERENCES atlas.work_items(household_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_execution_plans
 ADD CONSTRAINT work_execution_plans_household_allocation_fk_v1
 FOREIGN KEY (responsible_allocation_id)
 REFERENCES atlas.work_allocations(id) ON DELETE RESTRICT;

-- A real Household member can carry Work without an account; canonical
-- Person identity is never forged on behalf of a non-account household member.
ALTER TABLE atlas.work_allocations
 ADD COLUMN assignee_household_member_id uuid
 REFERENCES atlas.household_members(id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_allocations
 DROP CONSTRAINT work_allocations_exact_assignee_carrier_v1;
ALTER TABLE atlas.work_allocations
 ADD CONSTRAINT work_allocations_exact_assignee_carrier_v1 CHECK (
  (organization_id IS NOT NULL AND
   (assignee_membership_id IS NOT NULL OR
    (assignee_canonical_person_id IS NOT NULL AND
     establishment_basis_kind IN(
       'person_connection_receiver_uptake','delegated_under_standing_scope',
       'ledger_connection_direct_assignment',
       'original_subject_direct_assignment_v1'
     ))) AND assignee_household_member_id IS NULL)
  OR
  (household_id IS NOT NULL
   AND assignee_membership_id IS NULL
   AND assigned_by_membership_id IS NULL
   AND establishment_basis_kind='household_explicit_carrier_v1'
   AND (assignee_household_member_id IS NOT NULL
        OR assignee_canonical_person_id IS NOT NULL))
 );

-- Keep the original Work-to-Subject table, not a second Household task link.
ALTER TABLE atlas.work_item_context_links
 DROP CONSTRAINT work_item_context_links_subject_pair_v1;
ALTER TABLE atlas.work_item_context_links
 ADD CONSTRAINT work_item_context_links_subject_pair_v1 CHECK (
   (subject_domain='spatial' AND subject_kind IN ('zone','place','growing_object'))
   OR (subject_domain='identity' AND subject_kind IN ('identity_subject','external_relationship'))
   OR (subject_domain='temporal' AND subject_kind='occurrence')
   OR (subject_domain='household' AND subject_kind IN ('kernel_instance','household_space'))
 );

-- The source satisfaction registry is one append-only table. Farm retains
-- its existing Rule/Binding/State FKs; Household has a genuine accepted Rhythm
-- from the protected Household source, never a synthetic farm or company.
ALTER TABLE atlas.rhythm_satisfactions
 ADD COLUMN household_id uuid REFERENCES atlas.households(id) ON DELETE RESTRICT,
 ADD COLUMN household_rhythm_id uuid REFERENCES atlas.household_rhythms(id) ON DELETE RESTRICT;
ALTER TABLE atlas.rhythm_satisfactions ALTER COLUMN organization_id DROP NOT NULL;
ALTER TABLE atlas.rhythm_satisfactions ALTER COLUMN farm_id DROP NOT NULL;
ALTER TABLE atlas.rhythm_satisfactions ALTER COLUMN rhythm_state_id DROP NOT NULL;
ALTER TABLE atlas.rhythm_satisfactions ALTER COLUMN rhythm_binding_id DROP NOT NULL;
ALTER TABLE atlas.rhythm_satisfactions ALTER COLUMN rhythm_rule_id DROP NOT NULL;
ALTER TABLE atlas.rhythm_satisfactions
 DROP CONSTRAINT rhythm_satisfactions_subject_kind_check;
ALTER TABLE atlas.rhythm_satisfactions
 ADD CONSTRAINT rhythm_satisfactions_subject_kind_check CHECK (
   subject_kind IN ('farm','zone','growing_object','crop_cycle','project',
     'seed_lot','household_kernel_instance')
 );
ALTER TABLE atlas.rhythm_satisfactions
 ADD CONSTRAINT rhythm_satisfactions_one_native_custody_v1 CHECK (
   (farm_id IS NOT NULL AND organization_id IS NOT NULL
    AND household_id IS NULL AND household_rhythm_id IS NULL
    AND rhythm_state_id IS NOT NULL
    AND rhythm_binding_id IS NOT NULL AND rhythm_rule_id IS NOT NULL)
   OR
   (household_id IS NOT NULL AND household_rhythm_id IS NOT NULL
    AND organization_id IS NULL AND farm_id IS NULL
    AND rhythm_state_id IS NULL AND rhythm_binding_id IS NULL
    AND rhythm_rule_id IS NULL)
 );
CREATE UNIQUE INDEX rhythm_satisfactions_household_key_v1
 ON atlas.rhythm_satisfactions(household_id,satisfaction_key)
 WHERE household_id IS NOT NULL;

-- Old guarded business operations continue to execute unchanged whenever
-- organization_id is populated; they must never interpret Household Work as
-- an Organization and invent a company ledger completion or employee seat.
DROP TRIGGER work_allocations_participation_establishment_guard_v1 ON atlas.work_allocations;
CREATE TRIGGER work_allocations_participation_establishment_guard_v1 BEFORE INSERT OR UPDATE OF allocation_role, state, assignee_membership_id, assigned_by_membership_id, establishment_basis_kind, establishment_basis ON atlas.work_allocations FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL) EXECUTE FUNCTION atlas.guard_work_allocation_participation_establishment_v1();

DROP TRIGGER work_allocations_reconcile_execution_plan_v1 ON atlas.work_allocations;
CREATE TRIGGER work_allocations_reconcile_execution_plan_v1 AFTER INSERT OR UPDATE OF state, assignee_membership_id ON atlas.work_allocations FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL) EXECUTE FUNCTION atlas.reconcile_company_work_execution_plan_responsibility_trigger_v1();

DROP TRIGGER work_allocations_responsibility_establishment_guard_v2 ON atlas.work_allocations;
CREATE TRIGGER work_allocations_responsibility_establishment_guard_v2 BEFORE INSERT OR UPDATE OF allocation_role, state, assignee_membership_id, assigned_by_membership_id, establishment_basis_kind, establishment_basis ON atlas.work_allocations FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL) EXECUTE FUNCTION atlas.guard_work_allocation_responsibility_establishment_v2();

DROP TRIGGER work_allocations_sync_production_carrier_v1 ON atlas.work_allocations;
CREATE TRIGGER work_allocations_sync_production_carrier_v1 AFTER INSERT OR UPDATE OF state, assignee_membership_id, allocation_role ON atlas.work_allocations FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL) EXECUTE FUNCTION atlas.sync_production_company_work_responsibility_carrier_trigger_v1();

DROP TRIGGER work_allocations_validate_active_membership_v1 ON atlas.work_allocations;
CREATE TRIGGER work_allocations_validate_active_membership_v1 BEFORE INSERT OR UPDATE OF state, assignee_membership_id, assigned_by_membership_id, organization_id ON atlas.work_allocations FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL) EXECUTE FUNCTION atlas.validate_active_work_allocation_membership_v1();

DROP TRIGGER work_execution_plans_validate_v1 ON atlas.work_execution_plans;
CREATE TRIGGER work_execution_plans_validate_v1 BEFORE INSERT OR UPDATE ON atlas.work_execution_plans FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL) EXECUTE FUNCTION atlas.validate_work_execution_plan_v1();

DROP TRIGGER a_work_items_guard_governed_completion_v1 ON atlas.work_items;
CREATE TRIGGER a_work_items_guard_governed_completion_v1 BEFORE UPDATE OF work_state ON atlas.work_items FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL) EXECUTE FUNCTION atlas.guard_governed_company_work_completion_v1();

DROP TRIGGER guard_company_work_cancel_dependencies_v1 ON atlas.work_items;
CREATE TRIGGER guard_company_work_cancel_dependencies_v1 BEFORE UPDATE OF work_state ON atlas.work_items FOR EACH ROW WHEN ((NEW.organization_id IS NOT NULL) AND (((old.work_state IS DISTINCT FROM new.work_state) AND (new.work_state = 'cancelled'::text)))) EXECUTE FUNCTION atlas.guard_company_work_cancel_dependencies_v1();

DROP TRIGGER work_items_complete_bundle_members_v1 ON atlas.work_items;
CREATE TRIGGER work_items_complete_bundle_members_v1 AFTER UPDATE OF work_state ON atlas.work_items FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL) EXECUTE FUNCTION atlas.complete_company_work_bundle_members_v1();

DROP TRIGGER work_items_complete_execution_plan_v1 ON atlas.work_items;
CREATE TRIGGER work_items_complete_execution_plan_v1 AFTER UPDATE OF work_state ON atlas.work_items FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL) EXECUTE FUNCTION atlas.complete_company_work_execution_plan_v1();

DROP TRIGGER work_items_project_completed_company_work_to_ledger_v1 ON atlas.work_items;
CREATE TRIGGER work_items_project_completed_company_work_to_ledger_v1 AFTER UPDATE OF work_state ON atlas.work_items FOR EACH ROW WHEN ((NEW.organization_id IS NOT NULL) AND (((new.work_state = 'completed'::text) AND (old.work_state IS DISTINCT FROM new.work_state)))) EXECUTE FUNCTION atlas.project_completed_company_work_to_ledger_v1();

-- A separate source guard/writer for household rows follows in this
-- same staged release; until then, the new private household rows are inert.
-- Original held candidate: universal_household_canonical_work_guards_v1/candidate.sql
-- Must follow universal_household_canonical_work_custody_v1.
-- A Need is not a task: it is the original, still-applicable physical
-- transition. Only an explicit decision creates original canonical Work.
CREATE TABLE atlas.household_need_occurrences_v1 (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 household_id uuid NOT NULL REFERENCES atlas.households(id) ON DELETE RESTRICT,
 instance_id uuid NOT NULL REFERENCES atlas.household_kernel_instances(id) ON DELETE RESTRICT,
 need_key text NOT NULL CHECK(length(btrim(need_key)) BETWEEN 2 AND 100),
 state text NOT NULL CHECK(state IN ('open','satisfied','withdrawn')),
 opened_by_observation_id uuid NOT NULL
   REFERENCES atlas.care_observation_events(id) ON DELETE RESTRICT,
 source_action_id uuid NOT NULL,
 current_work_item_id uuid REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
 satisfied_by_care_result_id uuid
   REFERENCES atlas.care_result_events(id) ON DELETE RESTRICT,
 satisfied_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT household_need_action_idempotency_v1 UNIQUE (household_id,source_action_id),
 CONSTRAINT household_need_state_facts_v1 CHECK(
  (state='open' AND satisfied_at IS NULL AND satisfied_by_care_result_id IS NULL)
   OR (state='satisfied' AND satisfied_at IS NOT NULL
      AND satisfied_by_care_result_id IS NOT NULL)
   OR (state='withdrawn' AND satisfied_by_care_result_id IS NULL)
 )
);
CREATE UNIQUE INDEX household_need_one_open_real_transition_v1
 ON atlas.household_need_occurrences_v1(instance_id,need_key)
 WHERE state='open';
ALTER TABLE atlas.household_need_occurrences_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.household_need_occurrences_v1
 FROM PUBLIC,anon,authenticated;


-- These exact source guards apply ONLY to household-owned original canonical
-- work rows. Existing Organization/Event source guards remain unchanged.
CREATE OR REPLACE FUNCTION atlas.household_work_actor_v1(p_household_id uuid)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_person uuid;
BEGIN
 IF auth.uid() IS NULL OR
   (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready' THEN
   RAISE EXCEPTION 'Signed canonical Household Person required.' USING ERRCODE='42501';
 END IF;
 v_person:=atlas.current_person_id_v1();
 IF v_person IS NULL OR p_household_id IS NULL OR NOT EXISTS(
   SELECT 1 FROM atlas.households h
   JOIN atlas.principals p ON p.id=h.principal_id
   WHERE h.id=p_household_id AND h.status='active' AND (
       (p.status='active' AND p.user_id=auth.uid() AND p.person_id=v_person)
     OR EXISTS(
       SELECT 1 FROM atlas.household_members hm
       WHERE hm.household_id=h.id AND hm.active AND hm.person_id=v_person
         AND hm.user_id=auth.uid()
     )
   )
 ) THEN
   RAISE EXCEPTION 'Household identity unavailable.' USING ERRCODE='42501';
 END IF;
 RETURN v_person;
END;
$function$;
REVOKE ALL ON FUNCTION atlas.household_work_actor_v1(uuid)
 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION atlas.require_household_governor_self_v1(p_household_id uuid)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_person uuid;
BEGIN
 v_person:=atlas.household_work_actor_v1(p_household_id);
 IF NOT EXISTS(
   SELECT 1 FROM atlas.households h
   JOIN atlas.principals p ON p.id=h.principal_id
   WHERE h.id=p_household_id AND h.status='active' AND
     p.status='active' AND p.user_id=auth.uid() AND p.person_id=v_person
 ) THEN
   RAISE EXCEPTION 'Household governor required.' USING ERRCODE='42501';
 END IF;
 RETURN v_person;
END;
$function$;
REVOKE ALL ON FUNCTION atlas.require_household_governor_self_v1(uuid)
 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION atlas.guard_original_household_work_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF NEW.household_id IS NULL THEN RETURN NEW; END IF;
 IF TG_OP='INSERT' THEN
   PERFORM atlas.require_household_governor_self_v1(NEW.household_id);
 ELSIF NEW.work_state='completed' AND OLD.work_state='open'
   AND NEW.title IS NOT DISTINCT FROM OLD.title
   AND NEW.instructions IS NOT DISTINCT FROM OLD.instructions
   AND NEW.metadata IS NOT DISTINCT FROM OLD.metadata
   AND NEW.stable_key IS NOT DISTINCT FROM OLD.stable_key
   AND NEW.operation_class IS NOT DISTINCT FROM OLD.operation_class THEN
   -- The signed carrier may close only one original Work with the accepted
   -- qualifying physical Actual, not revise its Work scope or instructions.
   PERFORM atlas.household_work_actor_v1(NEW.household_id);
 ELSE
   PERFORM atlas.require_household_governor_self_v1(NEW.household_id);
 END IF;
 IF NEW.organization_id IS NOT NULL OR NEW.organization_unit_id IS NOT NULL
    OR NOT EXISTS(
      SELECT 1 FROM atlas.household_need_occurrences_v1 need
      WHERE need.id=NEW.source_object_id
        AND need.household_id=NEW.household_id
    )
    OR NEW.work_definition_id IS NOT NULL
    OR NEW.source_object_type<>'household_need_occurrence'
    OR NEW.source_object_id IS NULL
    OR NEW.result_contract_key<>'household_laundry_begin_cycle_v1' THEN
  RAISE EXCEPTION 'Household Work must remain an original protected Need-bound Work.'
    USING ERRCODE='23514';
 END IF;
 IF TG_OP='UPDATE' THEN
  IF OLD.household_id IS DISTINCT FROM NEW.household_id
     OR OLD.organization_id IS DISTINCT FROM NEW.organization_id
     OR OLD.source_object_type IS DISTINCT FROM NEW.source_object_type
     OR OLD.source_object_id IS DISTINCT FROM NEW.source_object_id
     OR OLD.result_contract_key IS DISTINCT FROM NEW.result_contract_key THEN
    RAISE EXCEPTION 'Canonical Work custody and source cannot be reassigned.'
     USING ERRCODE='23514';
  END IF;
  IF NEW.work_state='completed' AND OLD.work_state IS DISTINCT FROM 'completed'
   AND NOT EXISTS(
     SELECT 1 FROM atlas.work_result_acceptances a
     JOIN atlas.work_execution_results r ON r.id=a.execution_result_id
     WHERE a.household_id=NEW.household_id
       AND a.work_item_id=NEW.id AND a.decision='accepted'
       AND r.household_id=NEW.household_id AND r.work_item_id=NEW.id
       AND r.result_kind='completed'
       AND r.result_contract_key='household_laundry_begin_cycle_v1'
   ) THEN
    RAISE EXCEPTION 'Household Work cannot complete without accepted physical Actual.'
     USING ERRCODE='23514';
  END IF;
 END IF;
 RETURN NEW;
END;
$function$;
CREATE TRIGGER b_guard_original_household_work_v1
 BEFORE INSERT OR UPDATE ON atlas.work_items
 FOR EACH ROW WHEN (NEW.household_id IS NOT NULL)
 EXECUTE FUNCTION atlas.guard_original_household_work_v1();

CREATE OR REPLACE FUNCTION atlas.guard_household_work_allocation_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_person uuid;
BEGIN
 IF NEW.household_id IS NULL THEN RETURN NEW; END IF;
 v_person:=atlas.require_household_governor_self_v1(NEW.household_id);
 IF NEW.organization_id IS NOT NULL OR NEW.assignee_membership_id IS NOT NULL
   OR NEW.assigned_by_membership_id IS NOT NULL
   OR NEW.allocation_role<>'responsible'
   OR NEW.establishment_basis_kind<>'household_explicit_carrier_v1'
   OR jsonb_typeof(NEW.establishment_basis) IS DISTINCT FROM 'object'
   OR NEW.establishment_basis->>'householdId' IS DISTINCT FROM NEW.household_id::text
   OR NEW.establishment_basis->>'workItemId' IS DISTINCT FROM NEW.work_item_id::text
   OR NEW.establishment_basis->>'senderPersonId' IS DISTINCT FROM v_person::text
   OR NULLIF(btrim(NEW.establishment_basis->>'decisionReason'),'') IS NULL
   OR length(btrim(NEW.establishment_basis->>'decisionReason'))<12
   OR NOT EXISTS(
      SELECT 1 FROM atlas.work_items w
      WHERE w.id=NEW.work_item_id AND w.household_id=NEW.household_id
        AND w.work_state IN ('open','completed')
   ) THEN
  RAISE EXCEPTION 'Household responsibility lacks exact original and explicit carrier.'
    USING ERRCODE='23514';
 END IF;
 IF NEW.assignee_household_member_id IS NOT NULL THEN
   IF NOT EXISTS (
     SELECT 1 FROM atlas.household_members m
     WHERE m.id=NEW.assignee_household_member_id
       AND m.household_id=NEW.household_id AND m.active
       AND (NEW.assignee_canonical_person_id IS NULL
         OR m.person_id=NEW.assignee_canonical_person_id)
   ) THEN
     RAISE EXCEPTION 'Household carrier is not an actual active member.'
       USING ERRCODE='23514';
   END IF;
 ELSIF NEW.assignee_canonical_person_id IS NOT NULL THEN
   IF NOT EXISTS(
     SELECT 1 FROM atlas.households h
     JOIN atlas.principals p ON p.id=h.principal_id
     WHERE h.id=NEW.household_id AND p.status='active'
       AND p.person_id=NEW.assignee_canonical_person_id
   ) AND NOT EXISTS(
     SELECT 1 FROM atlas.household_members m
     WHERE m.household_id=NEW.household_id AND m.active
       AND m.person_id=NEW.assignee_canonical_person_id
   ) THEN
     RAISE EXCEPTION 'Signed Person must belong to this Household.'
       USING ERRCODE='23514';
   END IF;
 ELSE
   RAISE EXCEPTION 'Unresolved carrier is not an allocation.'
    USING ERRCODE='23514';
 END IF;
 IF TG_OP='UPDATE' THEN
   IF OLD.household_id IS DISTINCT FROM NEW.household_id
      OR OLD.work_item_id IS DISTINCT FROM NEW.work_item_id
      OR OLD.assignee_household_member_id IS DISTINCT FROM NEW.assignee_household_member_id
      OR OLD.establishment_basis IS DISTINCT FROM NEW.establishment_basis THEN
     RAISE EXCEPTION 'Household Work allocation source is immutable.'
       USING ERRCODE='23514';
   END IF;
 END IF;
 RETURN NEW;
END;
$function$;
CREATE TRIGGER z_guard_household_work_allocation_v1
 BEFORE INSERT OR UPDATE ON atlas.work_allocations
 FOR EACH ROW WHEN (NEW.household_id IS NOT NULL)
 EXECUTE FUNCTION atlas.guard_household_work_allocation_v1();

CREATE OR REPLACE FUNCTION atlas.guard_household_work_plan_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF NEW.household_id IS NULL THEN RETURN NEW; END IF;
 PERFORM atlas.require_household_governor_self_v1(NEW.household_id);
 IF NEW.organization_id IS NOT NULL OR
   NOT EXISTS(
     SELECT 1 FROM atlas.work_items w
     JOIN atlas.work_allocations a ON a.work_item_id=w.id
       AND a.household_id=w.household_id AND a.id=NEW.responsible_allocation_id
     WHERE w.id=NEW.work_item_id AND w.household_id=NEW.household_id
       AND w.work_state='open' AND a.state='active'
       AND a.allocation_role='responsible'
       AND a.assignee_membership_id IS NULL
       AND NEW.assignee_membership_id IS NULL
   ) THEN
    RAISE EXCEPTION 'Household Work plan requires its own active original allocation.'
      USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$function$;
CREATE TRIGGER z_guard_household_work_plan_v1
 BEFORE INSERT OR UPDATE ON atlas.work_execution_plans
 FOR EACH ROW WHEN (NEW.household_id IS NOT NULL)
 EXECUTE FUNCTION atlas.guard_household_work_plan_v1();

CREATE OR REPLACE FUNCTION atlas.guard_household_work_subject_link_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF NEW.household_id IS NULL THEN RETURN NEW; END IF;
 PERFORM atlas.require_household_governor_self_v1(NEW.household_id);
 IF NEW.organization_id IS NOT NULL OR NEW.subject_domain<>'household'
   OR NEW.subject_kind<>'kernel_instance' OR NEW.relation_kind<>'acts_on'
   OR NOT EXISTS (
     SELECT 1 FROM atlas.work_items w
     JOIN atlas.household_need_occurrences_v1 need
       ON need.id=w.source_object_id AND need.household_id=w.household_id
     JOIN atlas.household_kernel_instances inst ON inst.id=need.instance_id
     WHERE w.id=NEW.work_item_id AND w.household_id=NEW.household_id
       AND inst.id=NEW.subject_id AND inst.household_id=NEW.household_id
   ) THEN
    RAISE EXCEPTION 'Household Work link must be its actual original Laundry Subject.'
      USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$function$;
CREATE TRIGGER z_guard_household_work_subject_link_v1
 BEFORE INSERT OR UPDATE ON atlas.work_item_context_links
 FOR EACH ROW WHEN (NEW.household_id IS NOT NULL)
 EXECUTE FUNCTION atlas.guard_household_work_subject_link_v1();

CREATE OR REPLACE FUNCTION atlas.guard_household_work_actual_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF NEW.household_id IS NULL THEN RETURN NEW; END IF;
 PERFORM atlas.household_work_actor_v1(NEW.household_id);
 IF NEW.organization_id IS NOT NULL
    OR NEW.result_kind<>'completed'
    OR NEW.result_contract_key<>'household_laundry_begin_cycle_v1'
    OR NEW.reported_by_user_id IS DISTINCT FROM auth.uid()
    OR NOT EXISTS (
      SELECT 1 FROM atlas.work_items w
      JOIN atlas.household_need_occurrences_v1 need
        ON need.id=w.source_object_id AND need.household_id=w.household_id
      JOIN atlas.care_result_events r
        ON r.id=(NEW.payload->>'careResultId')::uuid
        AND r.scope_id=w.household_id AND r.scope_kind='household'
        AND r.subject_domain='household'
        AND r.subject_kind='household_kernel_instance'
        AND r.subject_id=need.instance_id::text
        AND r.actor_user_id=auth.uid()
        AND r.condition_after='washing'
        AND r.result_kind='improved_more_remains'
      WHERE w.id=NEW.work_item_id AND w.household_id=NEW.household_id
        AND w.result_contract_key=NEW.result_contract_key
        AND need.state='open'
        AND (
          EXISTS(
             SELECT 1 FROM atlas.households h
             JOIN atlas.principals p ON p.id=h.principal_id
             WHERE h.id=w.household_id AND p.status='active'
               AND p.user_id=auth.uid()
               AND p.person_id=atlas.current_person_id_v1()
          )
          OR EXISTS(
             SELECT 1 FROM atlas.work_allocations a
             WHERE a.work_item_id=w.id AND a.household_id=w.household_id
               AND a.state='active' AND a.allocation_role='responsible'
               AND (
                  a.assignee_canonical_person_id=atlas.current_person_id_v1()
                  OR EXISTS(
                    SELECT 1 FROM atlas.household_members hm
                    WHERE hm.id=a.assignee_household_member_id
                      AND hm.household_id=w.household_id AND hm.active
                      AND hm.user_id=auth.uid()
                      AND hm.person_id=atlas.current_person_id_v1()
                  )
               )
          )
        )
    ) THEN
  RAISE EXCEPTION 'Work Result needs real accepted Laundry step evidence.'
    USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$function$;
CREATE TRIGGER z_guard_household_work_actual_v1
 BEFORE INSERT ON atlas.work_execution_results
 FOR EACH ROW WHEN (NEW.household_id IS NOT NULL)
 EXECUTE FUNCTION atlas.guard_household_work_actual_v1();

CREATE OR REPLACE FUNCTION atlas.guard_household_work_acceptance_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF NEW.household_id IS NULL THEN RETURN NEW; END IF;
 PERFORM atlas.household_work_actor_v1(NEW.household_id);
 IF NEW.organization_id IS NOT NULL
   OR NEW.decision<>'accepted'
   OR NEW.accepted_by_domain<>'household_laundry_actual'
   OR NOT EXISTS(
     SELECT 1 FROM atlas.work_execution_results r
     WHERE r.id=NEW.execution_result_id
       AND r.household_id=NEW.household_id
       AND r.work_item_id=NEW.work_item_id
       AND r.result_kind='completed'
       AND r.result_contract_key='household_laundry_begin_cycle_v1'
   ) THEN
   RAISE EXCEPTION 'Household acceptance requires the original physical Work Result.'
     USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$function$;
CREATE TRIGGER z_guard_household_work_acceptance_v1
 BEFORE INSERT ON atlas.work_result_acceptances
 FOR EACH ROW WHEN (NEW.household_id IS NOT NULL)
 EXECUTE FUNCTION atlas.guard_household_work_acceptance_v1();

-- Keep original append-only acceptance and Actual guards; no new Household
-- reader or writer accepts farm_id, Organization Membership or employee seat.
-- Original held candidate: universal_household_rhythm_explicit_decision_v1/candidate.sql
-- Same original atlas.household_rhythms, not a new scheduler or task system.
-- An author-controlled metadata flag cannot substitute for this authorized
-- immutable decision history. Requires household canonical guards candidate.
CREATE TABLE atlas.household_rhythm_explicit_decisions_v1 (
 decision_seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 decision_id uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
 household_id uuid NOT NULL REFERENCES atlas.households(id) ON DELETE RESTRICT,
 rhythm_id uuid NOT NULL REFERENCES atlas.household_rhythms(id) ON DELETE RESTRICT,
 instance_id uuid NOT NULL REFERENCES atlas.household_kernel_instances(id) ON DELETE RESTRICT,
 decision_kind text NOT NULL CHECK(decision_kind IN ('establish','withdraw')),
 qualifying_event text NOT NULL CHECK(qualifying_event='wash_started'),
 renew_after_days integer CHECK(renew_after_days BETWEEN 1 AND 365),
 source_action_id uuid NOT NULL,
 decision_reason text NOT NULL CHECK(length(btrim(decision_reason)) BETWEEN 12 AND 1200),
 governor_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CONSTRAINT household_rhythm_explicit_action_once_v1 UNIQUE(household_id,source_action_id),
 CONSTRAINT household_rhythm_decision_value_v1 CHECK(
   (decision_kind='establish' AND renew_after_days IS NOT NULL)
   OR (decision_kind='withdraw' AND renew_after_days IS NULL)
 )
);
CREATE INDEX household_rhythm_decision_latest_v1
 ON atlas.household_rhythm_explicit_decisions_v1(household_id,rhythm_id,decision_seq DESC);
ALTER TABLE atlas.household_rhythm_explicit_decisions_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.household_rhythm_explicit_decisions_v1
 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION atlas.guard_household_rhythm_decision_immutable_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 RAISE EXCEPTION 'Original Household Rhythm decisions are append-only'
   USING ERRCODE='42501';
END;
$function$;
REVOKE ALL ON FUNCTION atlas.guard_household_rhythm_decision_immutable_v1()
 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER household_rhythm_decision_append_only_v1
 BEFORE UPDATE OR DELETE ON atlas.household_rhythm_explicit_decisions_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_household_rhythm_decision_immutable_v1();

CREATE OR REPLACE FUNCTION atlas.household_laundry_explicit_rhythm_decide_self_api_v1(
 p_kernel_instance_id uuid,p_action_id uuid,p_decision_kind text,
 p_renew_after_days integer,p_decision_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
 v_instance atlas.household_kernel_instances%rowtype;
 v_person uuid;
 v_rhythm atlas.household_rhythms%rowtype;
 v_existing atlas.household_rhythm_explicit_decisions_v1%rowtype;
 v_decision atlas.household_rhythm_explicit_decisions_v1%rowtype;
 v_latest atlas.household_rhythm_explicit_decisions_v1%rowtype;
 v_expect integer;
 v_key text:='kernel:household.laundry:general';
 v_is_new boolean:=false;
 v_reason text:=nullif(btrim(coalesce(p_decision_reason,'')),'');
BEGIN
 IF p_kernel_instance_id IS NULL OR p_action_id IS NULL
   OR p_decision_kind IS NULL OR p_decision_kind NOT IN ('establish','withdraw')
   OR (p_decision_kind='establish' AND
      (p_renew_after_days IS NULL OR p_renew_after_days NOT BETWEEN 1 AND 365))
   OR (p_decision_kind='withdraw' AND p_renew_after_days IS NOT NULL)
   OR v_reason IS NULL OR length(v_reason) NOT BETWEEN 12 AND 1200 THEN
  RAISE EXCEPTION 'Explicit bounded Household Rhythm decision required'
   USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_instance FROM atlas.household_kernel_instances
 WHERE id=p_kernel_instance_id AND kernel_key='household.laundry'
   AND state='active';
 IF v_instance.id IS NULL THEN
  RAISE EXCEPTION 'Original Laundry Subject not admitted' USING ERRCODE='42501';
 END IF;
 v_person:=atlas.require_household_governor_self_v1(v_instance.household_id);
 PERFORM pg_advisory_xact_lock(hashtextextended(
    'atlas.household.laundry.explicit_rhythm:'||v_instance.household_id::text,0));
 SELECT * INTO v_existing FROM atlas.household_rhythm_explicit_decisions_v1
 WHERE household_id=v_instance.household_id AND source_action_id=p_action_id;
 IF v_existing.decision_id IS NOT NULL THEN
   IF v_existing.instance_id IS DISTINCT FROM v_instance.id
      OR v_existing.decision_kind IS DISTINCT FROM p_decision_kind
      OR v_existing.renew_after_days IS DISTINCT FROM p_renew_after_days
      OR v_existing.decision_reason IS DISTINCT FROM v_reason
      OR v_existing.governor_person_id IS DISTINCT FROM v_person THEN
      RAISE EXCEPTION 'Rhythm decision ID previously used for different intent'
       USING ERRCODE='23505';
   END IF;
   v_decision:=v_existing;
 ELSE
   SELECT * INTO v_rhythm FROM atlas.household_rhythms
   WHERE household_id=v_instance.household_id AND stable_key=v_key FOR UPDATE;
   IF p_decision_kind='withdraw' AND v_rhythm.id IS NULL THEN
     RAISE EXCEPTION 'No original Household Rhythm to withdraw'
       USING ERRCODE='23514';
   END IF;
   IF p_decision_kind='establish' THEN
     v_expect:=CASE WHEN
       (v_instance.configuration->>'expectedMinutes') ~ '^[1-9][0-9]{0,3}$'
       THEN (v_instance.configuration->>'expectedMinutes')::integer ELSE 45 END;
     INSERT INTO atlas.household_rhythms(
       household_id,stable_key,area,title,cadence_rule,
       next_window_start,next_window_end,expected_minutes,
       protection_level,floor_class,interruptibility,principal_required,
       consequence,reason_for_floor,active,blocks_capacity,metadata)
     VALUES(
       v_instance.household_id,v_key,'laundry','Laundry',
       'every_'||p_renew_after_days::text||'_days',
       NULL,NULL,v_expect,'standard',1,'interruptible',false,
       'An actual laundry cycle may need attention after a prior wash.',
       v_reason,true,false,
       jsonb_build_object('worldKernelKey','household.laundry',
        'explicitRhythmDecision',true,'qualifyingEvent','wash_started',
        'renewAfterDays',p_renew_after_days,
        'source','household_laundry_explicit_rhythm_decision_v1'))
     ON CONFLICT(household_id,stable_key) DO UPDATE SET
       cadence_rule=excluded.cadence_rule,
       next_window_start=NULL,next_window_end=NULL,
       expected_minutes=excluded.expected_minutes,
       protection_level='standard',floor_class=1,principal_required=false,
       blocks_capacity=false,active=true,
       reason_for_floor=excluded.reason_for_floor,
       metadata=atlas.household_rhythms.metadata||excluded.metadata,
       updated_at=now()
     RETURNING * INTO v_rhythm;
   ELSE
     UPDATE atlas.household_rhythms
       SET active=false,blocks_capacity=false,principal_required=false,
          next_window_start=NULL,next_window_end=NULL,
          metadata=metadata||jsonb_build_object(
            'explicitRhythmDecision',false,
            'source','household_laundry_explicit_rhythm_decision_v1'),
          updated_at=now()
     WHERE id=v_rhythm.id RETURNING * INTO v_rhythm;
   END IF;
   INSERT INTO atlas.household_rhythm_explicit_decisions_v1(
     household_id,rhythm_id,instance_id,decision_kind,qualifying_event,
     renew_after_days,source_action_id,decision_reason,governor_person_id)
   VALUES (
     v_instance.household_id,v_rhythm.id,v_instance.id,p_decision_kind,
     'wash_started',p_renew_after_days,p_action_id,v_reason,v_person
   ) RETURNING * INTO v_decision;
   v_is_new:=true;
 END IF;
 SELECT * INTO v_latest FROM atlas.household_rhythm_explicit_decisions_v1
 WHERE household_id=v_instance.household_id AND rhythm_id=v_decision.rhythm_id
 ORDER BY decision_seq DESC LIMIT 1;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','household_laundry_explicit_rhythm_decision_v1',
   'householdId',v_instance.household_id,'instanceId',v_instance.id,
   'rhythmId',v_decision.rhythm_id,'decisionId',v_decision.decision_id,
   'actionId',p_action_id,'decisionKind',p_decision_kind,
   'renewAfterDays',p_renew_after_days,
   'currentlyEstablished',v_latest.decision_kind='establish',
   'isGovernedByOriginalDecision',true,
   'automaticCalibrationRhythmCreated',false,
   'workCreated',false,'idempotent',NOT v_is_new);
END;
$function$;
REVOKE ALL ON FUNCTION atlas.household_laundry_explicit_rhythm_decide_self_api_v1(
 uuid,uuid,text,integer,text) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.household_laundry_explicit_rhythm_decide_self_api_v1(
 p_kernel_instance_id uuid,p_action_id uuid,p_decision_kind text,
 p_renew_after_days integer,p_decision_reason text
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.household_laundry_explicit_rhythm_decide_self_api_v1(
 p_kernel_instance_id,p_action_id,p_decision_kind,p_renew_after_days,p_decision_reason);
$function$;
REVOKE ALL ON FUNCTION public.household_laundry_explicit_rhythm_decide_self_api_v1(
 uuid,uuid,text,integer,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.household_laundry_explicit_rhythm_decide_self_api_v1(
 uuid,uuid,text,integer,text) TO authenticated;
-- Original held candidate: household_laundry_original_work_actual_v1/candidate.sql
-- After universal_household_canonical_work_custody_v1 and
-- universal_household_canonical_work_guards_v1. Use exact original Work IDs.
INSERT INTO atlas.work_result_contract_policies(
 contract_key,source_domain,acceptance_mode,description,metadata
) VALUES ('household_laundry_begin_cycle_v1','household','domain_adapter',
 'A genuine wash_started physical Actual satisfies only the begin_cycle Need/Work; drying and return_to_use are separate.',
 jsonb_build_object('qualificationEvent','wash_started',
                    'noAutomaticRhythm',true,'physicalStepOnly',true))
ON CONFLICT (contract_key) DO NOTHING;
DO $policy$
BEGIN
 IF NOT EXISTS(
   SELECT 1 FROM atlas.work_result_contract_policies p
   WHERE p.contract_key='household_laundry_begin_cycle_v1'
    AND p.source_domain='household'
    AND p.acceptance_mode='domain_adapter' AND p.active
 ) THEN
   RAISE EXCEPTION 'Household physical-result contract conflicts with existing policy';
 END IF;
END;
$policy$;
CREATE UNIQUE INDEX IF NOT EXISTS work_execution_results_household_idempotency_v1
 ON atlas.work_execution_results(household_id,idempotency_key)
 WHERE household_id IS NOT NULL;

CREATE OR REPLACE FUNCTION atlas.record_household_laundry_observation_self_api_v1(
 p_kernel_instance_id uuid,p_action_id uuid,p_observation text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_household uuid;v_id uuid;v_new boolean:=false;
 v_old atlas.care_observation_events%rowtype;
BEGIN
 IF p_kernel_instance_id IS NULL OR p_action_id IS NULL
   OR nullif(btrim(coalesce(p_observation,'')),'') IS NULL
   OR length(btrim(p_observation))>1200 THEN
   RAISE EXCEPTION 'Exact Laundry observation and action required.'
    USING ERRCODE='22023';
 END IF;
 SELECT i.household_id INTO v_household
 FROM atlas.household_kernel_instances i
 WHERE i.id=p_kernel_instance_id AND i.kernel_key='household.laundry'
   AND i.state='active';
 IF v_household IS NULL THEN RAISE EXCEPTION 'Original Laundry unavailable.'
   USING ERRCODE='42501'; END IF;
 PERFORM atlas.require_household_governor_self_v1(v_household);
 INSERT INTO atlas.care_observation_events(
    subject_domain,subject_kind,subject_id,scope_kind,scope_id,
    condition_state,disposition,observed_by_user_id,source_kind,source_key,
    note,inferred_from_clock,metadata
 ) VALUES(
    'household','household_kernel_instance',p_kernel_instance_id::text,
    'household',v_household,'ready_for_cycle','intervene',auth.uid(),
    'household_laundry_confirmed_observation',
    'household-laundry-observation:'||v_household::text||':'||p_action_id::text,
    btrim(p_observation),false,
    jsonb_build_object('observationRole','physical_state_confirmed',
                       'isWorkCreation',false)
 ) ON CONFLICT (source_key) DO NOTHING RETURNING id INTO v_id;
 v_new:=v_id IS NOT NULL;
 IF NOT v_new THEN
  SELECT * INTO v_old FROM atlas.care_observation_events o
  WHERE o.source_key='household-laundry-observation:'||
    v_household::text||':'||p_action_id::text;
  IF v_old.id IS NULL OR v_old.scope_id<>v_household
    OR v_old.subject_id<>p_kernel_instance_id::text
    OR v_old.note IS DISTINCT FROM btrim(p_observation)
    OR v_old.condition_state<>'ready_for_cycle' THEN
    RAISE EXCEPTION 'Observation action key was used for different evidence.'
      USING ERRCODE='23505';
  END IF;
  v_id:=v_old.id;
 ELSE
  -- Existing care_apply_observation_current_state_v1 is the single
  -- observation-to-state writer. A second unconditional update here could
  -- overwrite a newer physical observation made in another session.
  NULL;
 END IF;
 RETURN jsonb_build_object('ok',true,
    'contractVersion','household_laundry_observation_v1',
    'householdId',v_household,'instanceId',p_kernel_instance_id,
    'observationId',v_id,'conditionState','ready_for_cycle',
    'workCreated',false,'idempotent',NOT v_new);
END;
$function$;
REVOKE ALL ON FUNCTION atlas.record_household_laundry_observation_self_api_v1(
 uuid,uuid,text) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.record_household_laundry_observation_self_api_v1(
 p_kernel_instance_id uuid,p_action_id uuid,p_observation text
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.record_household_laundry_observation_self_api_v1(
   p_kernel_instance_id,p_action_id,p_observation);
$function$;
REVOKE ALL ON FUNCTION public.record_household_laundry_observation_self_api_v1(
 uuid,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.record_household_laundry_observation_self_api_v1(
 uuid,uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION atlas.establish_household_laundry_original_work_self_api_v1(
 p_kernel_instance_id uuid,p_observation_id uuid,p_action_id uuid,
 p_self_carried boolean DEFAULT false,p_assignee_household_member_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_household uuid;v_governor uuid;v_need atlas.household_need_occurrences_v1%rowtype;
 v_work uuid;v_allocation uuid;v_person uuid;v_source_new boolean:=false;
BEGIN
 IF p_kernel_instance_id IS NULL OR p_observation_id IS NULL OR p_action_id IS NULL
    OR (p_self_carried AND p_assignee_household_member_id IS NOT NULL) THEN
   RAISE EXCEPTION 'Exact confirmed Need and one or no carrier required.'
     USING ERRCODE='22023';
 END IF;
 SELECT household_id INTO v_household FROM atlas.household_kernel_instances
 WHERE id=p_kernel_instance_id AND kernel_key='household.laundry'
    AND state='active';
 IF v_household IS NULL THEN
  RAISE EXCEPTION 'Original Laundry unavailable.' USING ERRCODE='42501';
 END IF;
 v_governor:=atlas.require_household_governor_self_v1(v_household);
 IF NOT EXISTS(
   SELECT 1 FROM atlas.care_observation_events o
   WHERE o.id=p_observation_id
     AND o.scope_kind='household' AND o.scope_id=v_household
     AND o.subject_domain='household' AND o.subject_kind='household_kernel_instance'
     AND o.subject_id=p_kernel_instance_id::text
     AND o.condition_state='ready_for_cycle'
     AND o.source_kind='household_laundry_confirmed_observation'
 ) OR NOT EXISTS(
   SELECT 1 FROM atlas.care_current_state c
   WHERE c.scope_kind='household' AND c.scope_id=v_household
    AND c.subject_domain='household' AND c.subject_kind='household_kernel_instance'
    AND c.subject_id=p_kernel_instance_id::text AND c.condition_state='ready_for_cycle'
 ) THEN
   RAISE EXCEPTION 'Laundry Need requires present confirmed physical state.'
     USING ERRCODE='23514';
 END IF;
 IF p_assignee_household_member_id IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM atlas.household_members m
    WHERE m.id=p_assignee_household_member_id
      AND m.household_id=v_household AND m.active
 ) THEN
   RAISE EXCEPTION 'Carrier must be a real active Household member.'
     USING ERRCODE='42501';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
    'household-laundry-need:'||p_kernel_instance_id::text||':begin_cycle',0));
 SELECT * INTO v_need FROM atlas.household_need_occurrences_v1
 WHERE instance_id=p_kernel_instance_id AND need_key='begin_cycle' AND state='open'
 FOR UPDATE;
 IF v_need.id IS NOT NULL THEN
   IF v_need.current_work_item_id IS NULL THEN
    RAISE EXCEPTION 'Existing Need lacks original Work; repair required.'
      USING ERRCODE='23514';
   END IF;
   -- Reading the same existing Need cannot assign somebody else by accident.
   RETURN jsonb_build_object('ok',true,
     'contractVersion','household_laundry_original_work_v1',
     'householdId',v_household,'instanceId',p_kernel_instance_id,
     'needOccurrenceId',v_need.id,'workItemId',v_need.current_work_item_id,
     'existingCurrentNeed',true,'noNewWorkCreated',true);
 END IF;
 INSERT INTO atlas.household_need_occurrences_v1(
   household_id,instance_id,need_key,state,opened_by_observation_id,source_action_id
 ) VALUES(
   v_household,p_kernel_instance_id,'begin_cycle','open',p_observation_id,p_action_id
 ) RETURNING * INTO v_need;
 INSERT INTO atlas.work_items(
  household_id,organization_id,source_object_type,source_object_id,
  work_state,title,instructions,stable_key,result_contract_key,
  created_by_user_id,metadata
 ) VALUES (
  v_household,NULL,'household_need_occurrence',v_need.id,
  'open','Start the wash',
  'Begin the actual wash. This step alone does not complete drying, readying, or return-to-use.',
  'household:laundry:begin_cycle:'||v_need.id::text,
  'household_laundry_begin_cycle_v1',auth.uid(),
  jsonb_build_object('needOccurrenceId',v_need.id,
    'worldKernelKey','household.laundry','partiallyCompletable',true,
    'carrierEstablishedOnlyByExplicitDecision',true)
 ) RETURNING id INTO v_work;
 UPDATE atlas.household_need_occurrences_v1
 SET current_work_item_id=v_work,updated_at=now() WHERE id=v_need.id;
 INSERT INTO atlas.work_item_context_links(
   household_id,organization_id,work_item_id,
   subject_domain,subject_kind,subject_id,relation_kind,
   provenance,metadata
 ) VALUES(
   v_household,NULL,v_work,'household','kernel_instance',
   p_kernel_instance_id,'acts_on',
   jsonb_build_object('source','household_laundry_need',
       'needOccurrenceId',v_need.id),'{}'::jsonb
 );
 IF p_self_carried OR p_assignee_household_member_id IS NOT NULL THEN
  IF p_self_carried THEN v_person:=v_governor;
  ELSE
   SELECT m.person_id INTO v_person FROM atlas.household_members m
   WHERE m.id=p_assignee_household_member_id AND m.household_id=v_household;
  END IF;
  INSERT INTO atlas.work_allocations(
   household_id,organization_id,work_item_id,allocation_role,state,
   assignee_household_member_id,assignee_canonical_person_id,
   establishment_basis_kind,establishment_basis,metadata
  ) VALUES(
   v_household,NULL,v_work,'responsible','active',
   p_assignee_household_member_id,v_person,
   'household_explicit_carrier_v1',jsonb_build_object(
     'householdId',v_household,'workItemId',v_work,
     'senderPersonId',v_governor,
     'decisionReason','Governor established exact Laundry Work carrier',
     'sourceActionId',p_action_id),
   jsonb_build_object('source','household_explicit_laundry_work_v1')
  ) RETURNING id INTO v_allocation;
 END IF;
 RETURN jsonb_build_object('ok',true,
   'contractVersion','household_laundry_original_work_v1',
   'householdId',v_household,'instanceId',p_kernel_instance_id,
   'observationId',p_observation_id,'needOccurrenceId',v_need.id,
   'workItemId',v_work,'allocationId',v_allocation,
   'assignedCanonicalPersonId',v_person,
   'childrenWithoutAccountsAreNotSignedUsers',true,
   'workOnDate',NULL,'clockAdmitted',false,
   'existingCurrentNeed',false,'noNewWorkCreated',false);
END;
$function$;
REVOKE ALL ON FUNCTION atlas.establish_household_laundry_original_work_self_api_v1(
 uuid,uuid,uuid,boolean,uuid) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.establish_household_laundry_original_work_self_api_v1(
 p_kernel_instance_id uuid,p_observation_id uuid,p_action_id uuid,
 p_self_carried boolean DEFAULT false,p_assignee_household_member_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.establish_household_laundry_original_work_self_api_v1(
  p_kernel_instance_id,p_observation_id,p_action_id,
  p_self_carried,p_assignee_household_member_id);
$function$;
REVOKE ALL ON FUNCTION public.establish_household_laundry_original_work_self_api_v1(
 uuid,uuid,uuid,boolean,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.establish_household_laundry_original_work_self_api_v1(
 uuid,uuid,uuid,boolean,uuid) TO authenticated;

-- A real physical Actual is accepted as exactly ONE work transition. It
-- cannot assert that the entire Laundry kernel or every Household Need is done.
CREATE OR REPLACE FUNCTION atlas.record_household_laundry_wash_started_self_api_v1(
 p_work_item_id uuid,p_action_id uuid,p_note text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_work atlas.work_items%rowtype;v_need atlas.household_need_occurrences_v1%rowtype;
 v_person uuid;v_source_key text;v_result uuid;v_observation uuid;v_work_result uuid;
 v_acceptance uuid;v_existing boolean:=false;v_before text;
 v_rhythm atlas.household_rhythms%rowtype;
 v_decision atlas.household_rhythm_explicit_decisions_v1%rowtype;
 v_satisfaction uuid;v_interval integer;
 v_at timestamptz:=clock_timestamp();
BEGIN
 IF p_work_item_id IS NULL OR p_action_id IS NULL OR
  length(coalesce(p_note,''))>1500 THEN
  RAISE EXCEPTION 'Exact Work and physical Actual action required.' USING ERRCODE='22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'household-laundry-work:'||p_work_item_id::text,0));
 SELECT * INTO v_work FROM atlas.work_items WHERE id=p_work_item_id FOR UPDATE;
 IF v_work.id IS NULL OR v_work.household_id IS NULL OR
  v_work.organization_id IS NOT NULL OR
  v_work.source_object_type<>'household_need_occurrence' OR
  v_work.result_contract_key<>'household_laundry_begin_cycle_v1' THEN
   RAISE EXCEPTION 'Original Household Laundry Work unavailable.' USING ERRCODE='42501';
 END IF;
 v_person:=atlas.household_work_actor_v1(v_work.household_id);
 SELECT * INTO v_need FROM atlas.household_need_occurrences_v1 need
  WHERE need.id=v_work.source_object_id AND need.household_id=v_work.household_id
    AND need.current_work_item_id=v_work.id FOR UPDATE;
 IF v_need.id IS NULL THEN
  RAISE EXCEPTION 'Work original Need record unavailable.' USING ERRCODE='23514';
 END IF;
 IF NOT EXISTS(
   SELECT 1 FROM atlas.households h JOIN atlas.principals p ON p.id=h.principal_id
   WHERE h.id=v_work.household_id AND p.status='active'
     AND p.user_id=auth.uid() AND p.person_id=v_person
 ) AND NOT EXISTS(
   SELECT 1 FROM atlas.work_allocations a
   LEFT JOIN atlas.household_members hm ON hm.id=a.assignee_household_member_id
   WHERE a.household_id=v_work.household_id AND a.work_item_id=v_work.id
     AND a.allocation_role='responsible' AND a.state='active'
     AND (a.assignee_canonical_person_id=v_person
       OR (hm.person_id=v_person AND hm.user_id=auth.uid() AND hm.active))
 ) THEN
  RAISE EXCEPTION 'Physical Work Actual requires authorized original carrier.'
   USING ERRCODE='42501';
 END IF;
  v_source_key:='household-laundry-wash-started:'||v_work.id::text||':'||p_action_id::text;
 SELECT id INTO v_result FROM atlas.care_result_events
 WHERE source_key=v_source_key AND scope_id=v_work.household_id
  AND subject_id=v_need.instance_id::text
  AND result_kind='improved_more_remains' AND condition_after='washing'
  AND note IS NOT DISTINCT FROM nullif(btrim(p_note),'');
 IF v_result IS NOT NULL THEN
  v_existing:=true;
  SELECT id INTO v_work_result FROM atlas.work_execution_results
  WHERE household_id=v_work.household_id AND work_item_id=v_work.id
    AND idempotency_key=v_source_key;
  IF v_work_result IS NULL OR v_work.work_state<>'completed' THEN
    RAISE EXCEPTION 'Partial physical Actual receipt requires source reconciliation.'
      USING ERRCODE='23514';
  END IF;
  SELECT id INTO v_acceptance FROM atlas.work_result_acceptances
   WHERE household_id=v_work.household_id AND execution_result_id=v_work_result;
  IF v_acceptance IS NULL OR v_need.state<>'satisfied' THEN
    RAISE EXCEPTION 'No accepted complete physical receipt for replay.'
     USING ERRCODE='23514';
  END IF;
  SELECT id INTO v_satisfaction FROM atlas.rhythm_satisfactions
  WHERE household_id=v_work.household_id
    AND satisfaction_key='wash_started:'||v_work.id::text;
  RETURN jsonb_build_object('ok',true,
    'contractVersion','household_laundry_wash_started_v1',
    'householdId',v_work.household_id,'instanceId',v_need.instance_id,
    'workItemId',v_work.id,'needOccurrenceId',v_need.id,
    'careResultId',v_result,'workResultId',v_work_result,
    'acceptanceId',v_acceptance,'rhythmSatisfactionId',v_satisfaction,
    'workCompleted',true,'laundryCompletelyDone',false,'idempotent',true);
 END IF;
 IF v_work.work_state<>'open' OR v_need.state<>'open' THEN
  RAISE EXCEPTION 'Work transition already closed or unavailable.'
   USING ERRCODE='23514';
 END IF;
 SELECT c.condition_state INTO v_before FROM atlas.care_current_state c
 WHERE c.scope_kind='household' AND c.scope_id=v_work.household_id
   AND c.subject_domain='household' AND c.subject_kind='household_kernel_instance'
   AND c.subject_id=v_need.instance_id::text FOR UPDATE;
 IF v_before<>'ready_for_cycle' THEN
  RAISE EXCEPTION 'Current confirmed Laundry need is no longer ready.'
    USING ERRCODE='23514';
 END IF;
 INSERT INTO atlas.care_result_events(
   subject_domain,subject_kind,subject_id,scope_kind,scope_id,
   result_kind,condition_before,condition_after,actor_user_id,
   source_kind,source_key,note,metadata,occurred_at
 ) VALUES(
   'household','household_kernel_instance',v_need.instance_id::text,
   'household',v_work.household_id,'improved_more_remains',
   v_before,'washing',auth.uid(),'household_laundry_physical_actual',
   v_source_key,nullif(btrim(p_note),''),
   jsonb_build_object('workItemId',v_work.id,'needOccurrenceId',v_need.id,
     'completedStep','wash_started','wholeLaundryDone',false),v_at
 ) RETURNING id INTO v_result;
 INSERT INTO atlas.care_observation_events(
   subject_domain,subject_kind,subject_id,scope_kind,scope_id,
   observed_at,condition_state,disposition,observed_by_user_id,
   source_kind,source_key,note,inferred_from_clock,metadata
 ) VALUES(
   'household','household_kernel_instance',v_need.instance_id::text,
   'household',v_work.household_id,v_at,'washing','observe',auth.uid(),
   'household_laundry_actual_state',
   'household-laundry-actual-observation:'||v_result::text,
   nullif(btrim(p_note),''),false,jsonb_build_object('careResultId',v_result)
 ) RETURNING id INTO v_observation;
 -- Existing observation trigger already applied the genuine
 -- 'washing' observation by observed_at; no second state update or
 -- silent overwrite of a newer independent observation.
 IF NOT EXISTS(
   SELECT 1 FROM atlas.care_current_state current_state
   WHERE current_state.scope_kind='household'
     AND current_state.scope_id=v_work.household_id
     AND current_state.subject_domain='household'
     AND current_state.subject_kind='household_kernel_instance'
     AND current_state.subject_id=v_need.instance_id::text
     AND current_state.condition_state='washing'
     AND current_state.last_observation_id=v_observation
 ) THEN
   RAISE EXCEPTION 'Original Laundry state readback failed after physical observation.'
    USING ERRCODE='23514';
 END IF;
 INSERT INTO atlas.work_execution_results(
   household_id,organization_id,work_item_id,reported_by_user_id,
   result_kind,result_contract_key,idempotency_key,payload,metadata,reported_at
 ) VALUES (
   v_work.household_id,NULL,v_work.id,auth.uid(),'completed',
   'household_laundry_begin_cycle_v1',v_source_key,
   jsonb_build_object('careResultId',v_result,'careObservationId',v_observation,
                      'step','wash_started','isWholeLaundryDone',false),
   jsonb_build_object('needOccurrenceId',v_need.id),v_at
 ) RETURNING id INTO v_work_result;
 INSERT INTO atlas.work_result_acceptances(
   household_id,organization_id,work_item_id,execution_result_id,
   decision,acceptance_kind,accepted_by_domain,evidence
 ) VALUES (
   v_work.household_id,NULL,v_work.id,v_work_result,'accepted',
   'source_qualified_physical_actual','household_laundry_actual',
   jsonb_build_object('careResultId',v_result,'step','wash_started')
 ) RETURNING id INTO v_acceptance;
 UPDATE atlas.work_items SET work_state='completed',completed_at=v_at,updated_at=now()
 WHERE id=v_work.id;
 UPDATE atlas.household_need_occurrences_v1
 SET state='satisfied',satisfied_at=v_at,
   satisfied_by_care_result_id=v_result,updated_at=now()
 WHERE id=v_need.id;
 -- Satisfy only a genuinely established, current, signed-governor
 -- Rhythm. Arbitrary metadata is NOT decision evidence. The latest
 -- immutable decision controls whether this physical event qualifies.
 SELECT h.* INTO v_rhythm FROM atlas.household_rhythms h
 WHERE h.household_id=v_work.household_id
   AND h.stable_key='kernel:household.laundry:general'
   AND h.active
   AND EXISTS(
     SELECT 1 FROM atlas.household_rhythm_explicit_decisions_v1 d
     WHERE d.household_id=h.household_id AND d.rhythm_id=h.id
       AND d.instance_id=v_need.instance_id
       AND d.decision_seq=(
          SELECT max(latest.decision_seq)
          FROM atlas.household_rhythm_explicit_decisions_v1 latest
          WHERE latest.household_id=h.household_id AND latest.rhythm_id=h.id
       )
       AND d.decision_kind='establish' AND d.qualifying_event='wash_started'
       AND d.renew_after_days BETWEEN 1 AND 365
   )
 FOR UPDATE OF h;
 IF v_rhythm.id IS NOT NULL THEN
   SELECT * INTO v_decision
   FROM atlas.household_rhythm_explicit_decisions_v1 d
   WHERE d.household_id=v_work.household_id
     AND d.rhythm_id=v_rhythm.id
   ORDER BY d.decision_seq DESC LIMIT 1;
   IF v_decision.decision_kind<>'establish'
      OR v_decision.qualifying_event<>'wash_started'
      OR v_decision.instance_id IS DISTINCT FROM v_need.instance_id
      OR v_decision.renew_after_days NOT BETWEEN 1 AND 365 THEN
     RAISE EXCEPTION 'Latest original Rhythm decision is not admitted.'
       USING ERRCODE='23514';
   END IF;
   v_interval:=v_decision.renew_after_days*86400;
   INSERT INTO atlas.rhythm_satisfactions(
     household_id,household_rhythm_id,organization_id,farm_id,
     rhythm_state_id,rhythm_rule_id,rhythm_binding_id,
     rhythm_key,subject_kind,subject_id,satisfaction_key,
     satisfaction_kind,satisfied_at,source_kind,source_id,source_event,
     renewal_interval_seconds,policy_match,evidence,created_by_user_id
   ) VALUES(
     v_work.household_id,v_rhythm.id,NULL,NULL,NULL,NULL,NULL,
     v_rhythm.stable_key,'household_kernel_instance',v_need.instance_id,
     'wash_started:'||v_work.id::text,'conditional',v_at,
     'household_laundry_physical_actual',v_result,'wash_started',
     v_interval,
     jsonb_build_object('qualifyingEvent','wash_started',
       'explicitDecisionId',v_decision.decision_id,
       'acceptedExplicitRhythm',true,'satisfiesOnly','begin_cycle'),
     jsonb_build_object('workItemId',v_work.id,'careResultId',v_result,
       'governedRhythmDecisionId',v_decision.decision_id),
     auth.uid()
   ) RETURNING id INTO v_satisfaction;
   UPDATE atlas.household_rhythms SET
     next_window_start=v_at+make_interval(secs=>v_interval),
     next_window_end=CASE WHEN next_window_start IS NOT NULL
       AND next_window_end IS NOT NULL
       THEN v_at+make_interval(secs=>v_interval)+
         (next_window_end-next_window_start)
       ELSE NULL END,
     updated_at=now()
   WHERE id=v_rhythm.id;
 END IF;
 RETURN jsonb_build_object('ok',true,
   'contractVersion','household_laundry_wash_started_v1',
   'householdId',v_work.household_id,'instanceId',v_need.instance_id,
   'workItemId',v_work.id,'needOccurrenceId',v_need.id,
   'careResultId',v_result,'careObservationId',v_observation,
   'workResultId',v_work_result,'acceptanceId',v_acceptance,
   'rhythmSatisfactionId',v_satisfaction,
   'workCompleted',true,'laundryCompletelyDone',false,
   'idempotent',false);
END;
$function$;
REVOKE ALL ON FUNCTION atlas.record_household_laundry_wash_started_self_api_v1(
 uuid,uuid,text) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.record_household_laundry_wash_started_self_api_v1(
 p_work_item_id uuid,p_action_id uuid,p_note text DEFAULT NULL
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.record_household_laundry_wash_started_self_api_v1(
   p_work_item_id,p_action_id,p_note);
$function$;
REVOKE ALL ON FUNCTION public.record_household_laundry_wash_started_self_api_v1(
 uuid,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.record_household_laundry_wash_started_self_api_v1(
 uuid,uuid,text) TO authenticated;
-- Original held candidate: household_laundry_original_work_read_v1/candidate.sql
-- Governor's original Laundry notebook; signed actor-only Work Focus by UUID.
-- No private Household data is inferred through Ledger or farm membership.
CREATE OR REPLACE FUNCTION atlas.household_laundry_current_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_household uuid;v_kernel atlas.household_kernel_instances%rowtype;
 v_condition text;v_observation uuid;v_need atlas.household_need_occurrences_v1%rowtype;
 v_work atlas.work_items%rowtype;v_allocation atlas.work_allocations%rowtype;
 v_last_completed_work_id uuid;v_last_completed_at timestamptz;
 v_rhythm atlas.household_rhythms%rowtype;
 v_rhythm_decision atlas.household_rhythm_explicit_decisions_v1%rowtype;
BEGIN
 v_household:=atlas.principal_current_household_id_v1();
 IF v_household IS NULL THEN
  RAISE EXCEPTION 'Original Household unavailable.' USING ERRCODE='42501';
 END IF;
 PERFORM atlas.require_household_governor_self_v1(v_household);
 SELECT * INTO v_kernel FROM atlas.household_kernel_instances
 WHERE household_id=v_household AND kernel_key='household.laundry'
 ORDER BY created_at DESC LIMIT 1;
 IF v_kernel.id IS NOT NULL THEN
  SELECT condition_state,last_observation_id INTO v_condition,v_observation
  FROM atlas.care_current_state
  WHERE scope_kind='household' AND scope_id=v_household
   AND subject_domain='household' AND subject_kind='household_kernel_instance'
   AND subject_id=v_kernel.id::text;
  -- Only current unsatisfied Need/Work belongs in this slot.
  -- Completed wash-started Work remains original history but must not
  -- prevent the next genuine observed Laundry cycle from being established.
  SELECT * INTO v_need FROM atlas.household_need_occurrences_v1
  WHERE household_id=v_household AND instance_id=v_kernel.id
    AND state='open'
  ORDER BY created_at DESC,id DESC LIMIT 1;
  SELECT w.id,n.satisfied_at INTO v_last_completed_work_id,v_last_completed_at
  FROM atlas.household_need_occurrences_v1 n
  JOIN atlas.work_items w ON w.id=n.current_work_item_id
    AND w.household_id=n.household_id
  WHERE n.household_id=v_household AND n.instance_id=v_kernel.id
    AND n.state='satisfied' AND w.work_state='completed'
  ORDER BY n.satisfied_at DESC,n.id DESC LIMIT 1;
  -- The original Household Rhythm remains a separate decision, not a
  -- presumed side effect of calibrating the world kernel.
  SELECT * INTO v_rhythm FROM atlas.household_rhythms r
   WHERE r.household_id=v_household
     AND r.stable_key='kernel:household.laundry:general';
  IF v_rhythm.id IS NOT NULL THEN
   SELECT * INTO v_rhythm_decision
   FROM atlas.household_rhythm_explicit_decisions_v1 d
   WHERE d.household_id=v_household AND d.rhythm_id=v_rhythm.id
     AND d.instance_id=v_kernel.id
   ORDER BY d.decision_seq DESC LIMIT 1;
  END IF;
  IF v_need.id IS NOT NULL THEN
    SELECT * INTO v_work FROM atlas.work_items w WHERE w.id=v_need.current_work_item_id
       AND w.household_id=v_household;
    SELECT * INTO v_allocation FROM atlas.work_allocations a
    WHERE a.household_id=v_household AND a.work_item_id=v_work.id
      AND a.allocation_role='responsible' AND a.state='active'
    ORDER BY a.allocated_at DESC LIMIT 1;
  END IF;
 END IF;
 RETURN jsonb_build_object(
  'ok',true,'contractVersion','household_laundry_current_v1',
  'householdId',v_household,
  'instanceId',v_kernel.id,
  'instanceState',v_kernel.state,
  'currentCondition',v_condition,
  'lastObservationId',v_observation,
  'needOccurrenceId',v_need.id,
  'needState',v_need.state,
  'workItemId',v_work.id,
  'lastCompletedWorkItemId',v_last_completed_work_id,
  'lastCompletedWashStartedAt',v_last_completed_at,
  'rhythmId',v_rhythm.id,
  'rhythmDecisionId',v_rhythm_decision.decision_id,
  'rhythmDecisionKind',v_rhythm_decision.decision_kind,
  'rhythmRenewAfterDays',v_rhythm_decision.renew_after_days,
  'rhythmCurrentlyEstablished',v_rhythm.active IS TRUE
    AND v_rhythm_decision.decision_kind='establish',
  'rhythmNextWindowStart',CASE WHEN v_rhythm.active
    AND v_rhythm_decision.decision_kind='establish'
    THEN v_rhythm.next_window_start ELSE NULL END,
  'workTitle',v_work.title,
  'workState',v_work.work_state,
  'carrierAllocationId',v_allocation.id,
  'assignedCanonicalPersonId',v_allocation.assignee_canonical_person_id,
  'assignedHouseholdMemberId',v_allocation.assignee_household_member_id,
  'workOnDate',NULL,
  'clockAdmitted',false,
  'wholeLaundryDone',false,
  'oneOriginalWork',true
 );
END;
$function$;
REVOKE ALL ON FUNCTION atlas.household_laundry_current_self_api_v1()
 FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.household_laundry_current_self_api_v1()
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.household_laundry_current_self_api_v1();
$function$;
REVOKE ALL ON FUNCTION public.household_laundry_current_self_api_v1()
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.household_laundry_current_self_api_v1()
 TO authenticated;

CREATE OR REPLACE FUNCTION atlas.household_original_work_focus_self_api_v1(
 p_household_id uuid,p_work_item_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_person uuid;v_governor boolean:=false;
 v_work atlas.work_items%rowtype;v_need atlas.household_need_occurrences_v1%rowtype;
 v_allocation atlas.work_allocations%rowtype;
 v_accepted atlas.work_result_acceptances%rowtype;
 v_result atlas.work_execution_results%rowtype;
BEGIN
 v_person:=atlas.household_work_actor_v1(p_household_id);
 SELECT * INTO v_work FROM atlas.work_items
 WHERE id=p_work_item_id AND household_id=p_household_id
  AND organization_id IS NULL AND source_object_type='household_need_occurrence';
 IF v_work.id IS NULL THEN
  RAISE EXCEPTION 'Original Household Work unavailable.' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_need FROM atlas.household_need_occurrences_v1 n
 WHERE n.id=v_work.source_object_id AND n.household_id=p_household_id
   AND n.current_work_item_id=v_work.id;
 IF v_need.id IS NULL THEN
  RAISE EXCEPTION 'Original Household Work unavailable.' USING ERRCODE='42501';
 END IF;
 SELECT EXISTS(
  SELECT 1 FROM atlas.households h JOIN atlas.principals p ON p.id=h.principal_id
  WHERE h.id=p_household_id AND p.status='active' AND p.user_id=auth.uid()
    AND p.person_id=v_person
 ) INTO v_governor;
 SELECT * INTO v_allocation FROM atlas.work_allocations a
 WHERE a.household_id=p_household_id AND a.work_item_id=v_work.id
  AND a.allocation_role='responsible' AND a.state='active'
 ORDER BY a.allocated_at DESC LIMIT 1;
 IF NOT v_governor AND NOT (
   v_allocation.assignee_canonical_person_id=v_person OR EXISTS(
    SELECT 1 FROM atlas.household_members hm
    WHERE hm.id=v_allocation.assignee_household_member_id AND hm.active
     AND hm.household_id=p_household_id AND hm.user_id=auth.uid()
     AND hm.person_id=v_person)
 ) THEN
  RAISE EXCEPTION 'Original Household Work unavailable.' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_result FROM atlas.work_execution_results r
 WHERE r.household_id=p_household_id AND r.work_item_id=v_work.id
 ORDER BY r.reported_at DESC,r.id DESC LIMIT 1;
 IF v_result.id IS NOT NULL THEN
  SELECT * INTO v_accepted FROM atlas.work_result_acceptances a
   WHERE a.execution_result_id=v_result.id
    AND a.household_id=p_household_id AND a.decision='accepted';
 END IF;
 RETURN jsonb_build_object(
  'ok',true,'contractVersion','household_original_work_focus_v1',
  'householdId',p_household_id,'workItemId',v_work.id,
  'subjectDomain','household','subjectKind','kernel_instance',
  'subjectId',v_need.instance_id,'needOccurrenceId',v_need.id,
  'needState',v_need.state,
  'title',v_work.title,'instructions',v_work.instructions,
  'workState',v_work.work_state,
  'allocationId',v_allocation.id,
  'assignedCanonicalPersonId',v_allocation.assignee_canonical_person_id,
  'resultContractKey',v_work.result_contract_key,
  'latestReportKind',v_result.result_kind,
  'acceptedResultKind',CASE WHEN v_accepted.id IS NOT NULL
   THEN v_result.result_kind ELSE NULL END,
  'canReportPhysicalActual',v_work.work_state='open' AND v_need.state='open'
   AND (v_governor OR v_allocation.id IS NOT NULL),
  'isSignedHouseholdPerson',true,'isCompany',false
 );
END;
$function$;
REVOKE ALL ON FUNCTION atlas.household_original_work_focus_self_api_v1(
 uuid,uuid) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.household_original_work_focus_self_api_v1(
 p_household_id uuid,p_work_item_id uuid
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.household_original_work_focus_self_api_v1(
 p_household_id,p_work_item_id);
$function$;
REVOKE ALL ON FUNCTION public.household_original_work_focus_self_api_v1(
 uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.household_original_work_focus_self_api_v1(
 uuid,uuid) TO authenticated;
-- Original held candidate: original_subject_work_existing_direct_responsibility_v1/guarded_native_reader_extensions.sql
-- Extension of the installed original canonical Person Work readers/guards.
-- Source definitions are based on the signed/current Noel function bodies
-- at 2026-10-26. Re-audit the full diff before applying after split candidate.
-- One native allocation identity, not a parallel farm task engine.
CREATE OR REPLACE FUNCTION atlas.connected_person_my_work_self_api_v1(p_limit integer DEFAULT 50, p_after_allocation_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_self uuid := atlas.current_person_id_v1();
  v_items jsonb := '[]'::jsonb;
  v_more boolean := false;
  v_next uuid := NULL;
BEGIN
  IF auth.uid() IS NULL OR v_self IS NULL THEN
    RAISE EXCEPTION 'Signed-in canonical Person required' USING errcode='42501';
  END IF;
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'Limit must be between 1 and 100' USING errcode='22023';
  END IF;

  WITH eligible AS MATERIALIZED (
    SELECT
      a.id allocation_id,w.id work_id,w.organization_id,
      (a.establishment_basis->>'nativeLedgerId')::uuid ledger_id,
      w.title,w.instructions,w.result_contract_key,
      a.establishment_basis_kind,a.allocated_at,
      plan.id plan_id,plan.plan_state,
      plan.planned_service_date,plan.exposure_service_date,
      coalesce(plan_counts.current_plan_count,0) current_plan_count,
      coalesce(relevance.has_relevance,false) has_relevance
    FROM atlas.work_allocations a
    JOIN atlas.work_items w ON w.id=a.work_item_id
      AND w.organization_id=a.organization_id
    LEFT JOIN LATERAL (
      SELECT p.id,p.plan_state,p.planned_service_date,p.exposure_service_date
      FROM atlas.work_execution_plans p
      WHERE p.work_item_id=w.id AND p.organization_id=w.organization_id
        AND p.responsible_allocation_id=a.id
        AND p.plan_state IN ('active','needs_replan')
      ORDER BY CASE WHEN p.plan_state='active' THEN 0 ELSE 1 END,
        p.updated_at DESC,p.id DESC LIMIT 1
    ) plan ON true
    LEFT JOIN LATERAL (
      SELECT count(*)::integer current_plan_count
      FROM atlas.work_execution_plans p
      WHERE p.work_item_id=w.id AND p.organization_id=w.organization_id
        AND p.plan_state IN ('active','needs_replan')
    ) plan_counts ON true
    LEFT JOIN LATERAL (
      SELECT EXISTS (
        SELECT 1 FROM atlas.company_work_native_ledger_relevance x
        WHERE x.work_item_id=w.id AND x.organization_id=w.organization_id
          AND x.ledger_id=(a.establishment_basis->>'nativeLedgerId')::uuid
          AND x.attribution_state='active'
          AND (
            x.evidence_kind IN ('owner_attested','participant_attested')
            OR (x.evidence_kind='source_verified' AND EXISTS (
              SELECT 1
              FROM atlas.company_work_native_ledger_exact_source_v1(
                x.work_item_id,x.ledger_id
              ) verified
              WHERE verified.source_schema=x.source_schema
                AND verified.source_table=x.source_table
                AND verified.source_id=x.source_id
            ))
          )
      ) has_relevance
    ) relevance ON true
    WHERE a.allocation_role='responsible' AND a.state='active'
      AND a.assignee_canonical_person_id=v_self
      AND a.assignee_membership_id IS NULL
      AND a.establishment_basis_kind IN (
        'person_connection_receiver_uptake','delegated_under_standing_scope',
        'ledger_connection_direct_assignment','original_subject_direct_assignment_v1'
      )
      AND w.work_state='open'
      AND (p_after_allocation_id IS NULL OR a.id>p_after_allocation_id)
      AND atlas.person_has_native_ledger_connection_v1(
        w.organization_id,(a.establishment_basis->>'nativeLedgerId')::uuid,v_self
      )
    ORDER BY a.id
    LIMIT p_limit+1
  ), numbered AS (
    SELECT e.*,row_number() OVER (ORDER BY e.allocation_id) rn
    FROM eligible e
  )
  SELECT
    coalesce(jsonb_agg(
      jsonb_build_object(
        'workItemId',r.work_id,'allocationId',r.allocation_id,
        'organizationId',r.organization_id,'ledgerId',r.ledger_id,
        'title',r.title,'instructions',r.instructions,
        'resultContractKey',r.result_contract_key,
        'establishmentBasisKind',r.establishment_basis_kind,
        'allocatedAt',r.allocated_at,'planId',r.plan_id,
        'planState',r.plan_state,'workOn',r.planned_service_date,
        'exposureDate',r.exposure_service_date,
        'workRelevanceVerified',r.has_relevance,
        'canPlace',r.has_relevance AND r.current_plan_count<=1,
        'scheduleState',CASE
          WHEN r.current_plan_count>1 THEN 'conflict'
          WHEN r.plan_id IS NULL AND r.current_plan_count>0 THEN 'unverified_plan'
          WHEN r.plan_id IS NULL THEN 'unscheduled'
          WHEN r.plan_state='needs_replan' THEN 'needs_replan'
          WHEN r.plan_state='active' AND
            r.planned_service_date IS NOT NULL AND
            r.exposure_service_date IS NOT NULL THEN 'scheduled'
          ELSE 'unverified_plan'
        END
      ) ORDER BY r.allocation_id
    ) FILTER(WHERE r.rn<=p_limit),'[]'::jsonb),
    count(*)>p_limit,
    (array_agg(r.allocation_id ORDER BY r.rn) FILTER (WHERE r.rn=p_limit))[1]
  INTO v_items,v_more,v_next
  FROM numbered r;

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','connected_person_my_work_v1',
    'personId',v_self,'items',v_items,
    'hasMore',v_more,'nextAllocationId',CASE WHEN v_more THEN v_next ELSE NULL END,
    'sourceScope','active_responsible_person_native_ledger_work',
    'scheduleReadAcrossAllDates',true,
    'optionalRequestsExcluded',true,'noPersonalTaskCreated',true
  );
END
$function$
;

CREATE OR REPLACE FUNCTION atlas.connected_person_place_work_self_api_v1(p_work_item_id uuid, p_service_date date, p_reason text DEFAULT 'Recipient selected the work day for their accepted Ledger responsibility.'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_person uuid;v_w atlas.work_items%rowtype;v_a atlas.work_allocations%rowtype;
 v_ledger uuid;v_old atlas.work_execution_plans%rowtype;
 v_plan atlas.work_execution_plans%rowtype;v_window jsonb;v_kind text;
 v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
begin
 if auth.uid() is null or (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready'
 then raise exception 'Signed-in canonical Person required' using errcode='42501';end if;
 v_person:=atlas.current_person_id_v1();
 if p_work_item_id is null or v_reason is null or length(v_reason) not between 12 and 1200
 then raise exception 'Exact Work and meaningful placement reason required' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(
   'atlas.company_work.responsibility:'||p_work_item_id::text,0));
 perform pg_advisory_xact_lock(hashtextextended(
   'atlas.company_work.plan:'||p_work_item_id::text,0));
 select * into v_w from atlas.work_items where id=p_work_item_id and work_state='open' for update;
 if v_w.id is null then raise exception 'Open Company Work required' using errcode='23514';end if;
 select * into v_a from atlas.work_allocations a
  where a.work_item_id=v_w.id and a.organization_id=v_w.organization_id
   and a.allocation_role='responsible' and a.state='active'
   and a.assignee_membership_id is null
   and a.assignee_canonical_person_id=v_person
   and a.establishment_basis_kind in ('person_connection_receiver_uptake','delegated_under_standing_scope','ledger_connection_direct_assignment','original_subject_direct_assignment_v1')
  order by a.allocated_at desc,a.id desc limit 1;
 if v_a.id is null then raise exception 'Only the active responsible Person may place their accepted Work' using errcode='42501';end if;
 v_ledger:=(v_a.establishment_basis->>'nativeLedgerId')::uuid;
 if v_ledger is null
   or not atlas.person_has_native_ledger_connection_v1(v_w.organization_id,v_ledger,v_person)
   or not exists(select 1 from atlas.company_work_native_ledger_relevance r
     where r.organization_id=v_w.organization_id and r.work_item_id=v_w.id
      and r.ledger_id=v_ledger and r.attribution_state='active')
 then raise exception 'Exact current Ledger connection and Work relevance required' using errcode='42501';end if;
 select * into v_old from atlas.work_execution_plans
   where work_item_id=v_w.id and organization_id=v_w.organization_id
     and plan_state in ('active','needs_replan') for update;
 if v_old.id is not null and v_old.responsible_allocation_id<>v_a.id
 then raise exception 'Existing plan belongs to another responsibility' using errcode='23514';end if;
 if v_old.id is not null and v_old.plan_state='active'
  and v_old.planned_service_date is not distinct from p_service_date
  and v_old.exposure_service_date is not distinct from p_service_date then
   return jsonb_build_object('ok',true,'contractVersion','connected_person_work_placement_v1',
    'state','already_placed','workItemId',v_w.id,'ledgerId',v_ledger,
    'responsiblePersonId',v_person,'planId',v_old.id,'executionDate',p_service_date,
    'newWorkCreated',false,'idempotent',true);
 end if;
 if p_service_date is null then
   if v_old.id is null then
    return jsonb_build_object('ok',true,'contractVersion','connected_person_work_placement_v1',
     'state','already_unplanned','workItemId',v_w.id,'ledgerId',v_ledger,
     'responsiblePersonId',v_person,'executionDate',null,'newWorkCreated',false);
   end if;
   update atlas.work_execution_plans set plan_state='withdrawn',plan_reason=v_reason,
    metadata=metadata||jsonb_build_object('actorPersonId',v_person,'source','person_self_unplan_v1')
    where id=v_old.id;
   insert into atlas.work_execution_plan_events(
     organization_id,work_item_id,plan_id,event_kind,
     from_planned_service_date,from_exposure_service_date,actor_membership_id,reason,metadata)
   values(v_w.organization_id,v_w.id,v_old.id,'withdrawn',
     v_old.planned_service_date,v_old.exposure_service_date,null,v_reason,
     jsonb_build_object('actorPersonId',v_person,'source','person_self_unplan_v1'));
   return jsonb_build_object('ok',true,'contractVersion','connected_person_work_placement_v1',
    'state','unplanned','workItemId',v_w.id,'ledgerId',v_ledger,
    'responsiblePersonId',v_person,'planId',v_old.id,'executionDate',null,'newWorkCreated',false);
 end if;
 v_window:=atlas.company_work_execution_plan_window_check_v1(v_w.id,p_service_date);
 if not coalesce((v_window->>'allowed')::boolean,false) then
  raise exception 'Requested work-on day conflicts with source Work window' using errcode='23514';end if;
 if v_old.id is null then
   insert into atlas.work_execution_plans(
    organization_id,work_item_id,responsible_allocation_id,assignee_membership_id,
    planned_by_membership_id,plan_state,first_planned_service_date,planned_service_date,
    exposure_service_date,plan_reason,metadata)
   values(v_w.organization_id,v_w.id,v_a.id,null,null,'active',
     p_service_date,p_service_date,p_service_date,v_reason,
     jsonb_build_object('actorPersonId',v_person,'source','person_self_place_v1',
      'personNative',true))
   returning * into v_plan;
   v_kind:='planned';
 else
   update atlas.work_execution_plans set
    planned_service_date=p_service_date,exposure_service_date=p_service_date,
    plan_state='active',plan_reason=v_reason,planned_by_membership_id=null,
    rollover_count=0,
    metadata=metadata||jsonb_build_object('actorPersonId',v_person,'sourceChange','person_self_place_v1')
    where id=v_old.id returning * into v_plan;
   v_kind:=case when v_old.planned_service_date is distinct from p_service_date
     then 'rescheduled' else 'planned' end;
 end if;
 insert into atlas.work_execution_plan_events(
    organization_id,work_item_id,plan_id,event_kind,
    from_planned_service_date,to_planned_service_date,
    from_exposure_service_date,to_exposure_service_date,
    actor_membership_id,reason,metadata)
 values(v_w.organization_id,v_w.id,v_plan.id,v_kind,
    v_old.planned_service_date,v_plan.planned_service_date,
    v_old.exposure_service_date,v_plan.exposure_service_date,
    null,v_reason,jsonb_build_object('actorPersonId',v_person,'source','person_self_place_v1'));
 return jsonb_build_object('ok',true,'contractVersion','connected_person_work_placement_v1',
   'state','placed','workItemId',v_w.id,'ledgerId',v_ledger,
   'responsiblePersonId',v_person,'planId',v_plan.id,'executionDate',p_service_date,
   'newWorkCreated',false,'workerReadProven',false);
end$function$
;

CREATE OR REPLACE FUNCTION atlas.guard_work_allocation_responsibility_establishment_v2()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_source text:=coalesce(new.metadata->>'source','');
  v_requires_basis boolean:=false;
  v_kind text:=lower(btrim(coalesce(new.establishment_basis_kind,'')));
  v_basis jsonb:=new.establishment_basis;
begin
  if tg_op='UPDATE' then
    if new.establishment_basis_kind is distinct from old.establishment_basis_kind
       or new.establishment_basis is distinct from old.establishment_basis then
      raise exception 'Exact Work responsibility establishment provenance is immutable once the allocation exists.'
        using errcode='23514';
    end if;
  end if;

  if new.allocation_role<>'responsible' or new.state<>'active' then
    return new;
  end if;

  if tg_op='INSERT' then
    v_requires_basis:=true;
  elsif old.allocation_role is distinct from new.allocation_role
        or old.state is distinct from new.state
        or old.assignee_membership_id is distinct from new.assignee_membership_id then
    v_requires_basis:=true;
  end if;

  -- Existing historical active responsibility can be updated/released without
  -- fabricating a retrospective establishment basis.
  if not v_requires_basis
     and new.establishment_basis_kind is null
     and new.establishment_basis is null then
    return new;
  end if;

  -- Two transitional farm adapters remain live. New rows created by exactly
  -- those named carriers are normalized as governed legacy reconstruction
  -- without changing the adapters or backfilling historical rows.
  if new.establishment_basis_kind is null
     and v_source in (
       'legacy_weekly_harvest_occurrence_assignment',
       'explicit_worker_task_company_work_adoption_v2'
     ) then
    if v_source='legacy_weekly_harvest_occurrence_assignment'
       and (
         nullif(btrim(coalesce(new.metadata->>'plannedOccurrenceId','')),'') is null
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='planned_work_occurrence'
             and work.source_object_id::text=(new.metadata->>'plannedOccurrenceId')
         )
       ) then
      raise exception 'Weekly-harvest reconstruction requires the exact planned-occurrence Work source.'
        using errcode='23514';
    end if;
    if v_source='explicit_worker_task_company_work_adoption_v2'
       and (
         nullif(btrim(coalesce(new.metadata->>'legacyTaskId','')),'') is null
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='legacy_task'
             and work.source_object_id::text=(new.metadata->>'legacyTaskId')
         )
       ) then
      raise exception 'Legacy-task reconstruction requires the exact legacy-task Work source.'
        using errcode='23514';
    end if;

    new.establishment_basis_kind:='legacy_governed_reconstruction';
    new.establishment_basis:=jsonb_strip_nulls(jsonb_build_object(
      'contractVersion','exact_work_responsibility_establishment_v2',
      'basisKind','legacy_governed_reconstruction',
      'organizationId',new.organization_id,
      'workItemId',new.work_item_id,
      'assigneeMembershipId',new.assignee_membership_id,
      'legacySource',v_source,
      'legacyTaskId',new.metadata->>'legacyTaskId',
      'plannedOccurrenceId',new.metadata->>'plannedOccurrenceId',
      'normalizedAt',now()
    ));
    v_kind:=new.establishment_basis_kind;
    v_basis:=new.establishment_basis;
  end if;

  if new.establishment_basis_kind is null
     or new.establishment_basis is null
     or jsonb_typeof(new.establishment_basis)<>'object' then
    raise exception 'Active exact Work responsibility requires a governed establishment basis.'
      using errcode='23514';
  end if;

  v_kind:=lower(btrim(new.establishment_basis_kind));
  v_basis:=new.establishment_basis;

  if v_kind not in (
    'self_claim',
    'self_adoption',
    'self_initiated_outbound',
    'delegated_under_standing_scope',
    'legacy_governed_reconstruction',
    'person_connection_receiver_uptake',
    'ledger_connection_direct_assignment',
    'original_subject_direct_assignment_v1'
  ) then
    raise exception 'Unsupported exact Work responsibility establishment basis: %.',v_kind
      using errcode='23514';
  end if;

  -- A Person-native receipt uses the same one-responsible-allocation table.
  -- Its source is an offered exact Work item, with receiver or witnessed
  -- uptake; no Organization Membership or employee classification is invented.

  -- A rooted native Ledger owner may issue an existing, source-bound Event
  -- obligation to another actual Person connected to the same Ledger.
  -- Unlike the legacy Event checklist, this uses the ORIGINAL Company Work ID.
  -- No employee membership, impersonation or synthetic worker assent.
  -- This is direct responsibility for an EXISTING original Work ID, not
  -- ledger_direct_create_work and not a new Company/farm task.
  if v_kind='original_subject_direct_assignment_v1' then
    if v_source<>'original_subject_direct_assignment_v1'
       or new.assignee_membership_id is not null
       or new.assigned_by_membership_id is not null
       or new.assignee_canonical_person_id is null
       or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
       or coalesce(v_basis->>'basisKind','')<>v_kind
       or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
       or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
       or coalesce(v_basis->>'assigneePersonId','')<>new.assignee_canonical_person_id::text
       or nullif(v_basis->>'nativeLedgerId','') is null
       or nullif(v_basis->>'decompositionId','') is null
       or nullif(v_basis->>'senderPersonId','') is null
       or nullif(v_basis->>'sourceActionId','') is null
       or coalesce(v_basis->>'authorizationBasis','')<>'governor_exact_existing_original_work'
    then
      raise exception 'Exact original Work direct responsibility source fields missing'
        using errcode='23514';
    end if;
    if atlas.current_person_id_v1() is distinct from (v_basis->>'senderPersonId')::uuid
       or atlas.company_work_native_ledger_owner_self_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid)
          is distinct from (v_basis->>'senderPersonId')::uuid
       or not atlas.person_has_native_ledger_connection_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
         new.assignee_canonical_person_id)
       or not exists(
         select 1 from atlas.work_decomposition_members m
         join atlas.work_decomposition_groups g on g.id=m.group_id
         join atlas.work_items w on w.id=m.child_work_item_id
         join atlas.company_work_native_ledger_relevance r
           on r.work_item_id=w.id and r.organization_id=w.organization_id
          and r.ledger_id=g.authorized_ledger_id and r.attribution_state='active'
         where m.child_work_item_id=new.work_item_id
           and g.id=(v_basis->>'decompositionId')::uuid
           and g.authorized_ledger_id=(v_basis->>'nativeLedgerId')::uuid
           and w.organization_id=new.organization_id
           and w.work_state='open' and w.source_object_type='work_decomposition'
           and w.metadata->>'originalParentWorkItemId'=g.parent_work_item_id::text
       ) then
       raise exception 'Exact original Work, connection or governing authority unavailable'
         using errcode='23514';
    end if;
    return new;
  end if;

  if v_kind='ledger_connection_direct_assignment'
     and v_source='existing_event_work_connected_direct_assignment_v1' then
    if new.assignee_membership_id is not null
       or new.assigned_by_membership_id is not null
       or new.assignee_canonical_person_id is null
       or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
       or coalesce(v_basis->>'basisKind','')<>v_kind
       or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
       or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
       or coalesce(v_basis->>'assigneePersonId','')<>new.assignee_canonical_person_id::text
       or nullif(v_basis->>'nativeLedgerId','') is null
       or nullif(v_basis->>'occurrenceId','') is null
       or nullif(v_basis->>'senderPersonId','') is null
       or coalesce(v_basis->>'authorizationBasis','')<>
          'governing_principal_and_active_mutual_ledger_connections'
    then raise exception 'Existing Event obligation lacks exact governing Person, Work, Ledger and Event basis'
      using errcode='23514';end if;
    if atlas.current_person_id_v1() is distinct from (v_basis->>'senderPersonId')::uuid
       or atlas.company_work_native_ledger_owner_self_v1(
           new.organization_id,(v_basis->>'nativeLedgerId')::uuid)
           is distinct from (v_basis->>'senderPersonId')::uuid
       or not atlas.person_has_native_ledger_connection_v1(
           new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
           new.assignee_canonical_person_id)
       or not exists(select 1 from atlas.work_items w
          join atlas.work_item_context_links ctx on ctx.work_item_id=w.id
           and ctx.organization_id=w.organization_id
           and ctx.subject_domain='temporal' and ctx.subject_kind='occurrence'
           and ctx.subject_id=(v_basis->>'occurrenceId')::uuid
          join atlas.company_work_native_ledger_relevance rel
           on rel.work_item_id=w.id and rel.organization_id=w.organization_id
           and rel.ledger_id=(v_basis->>'nativeLedgerId')::uuid
           and rel.attribution_state='active'
          where w.id=new.work_item_id and w.organization_id=new.organization_id
           and w.work_state='open'
           and w.result_contract_key='ordinary_company_work_worker_attestation_v1'
           and not exists(select 1 from atlas.ledger_occurrence_work_actions_v1 a
            where a.ledger_id=rel.ledger_id
             and a.occurrence_id=ctx.subject_id
             and a.work_item_id=w.id and a.action_kind='removed'))
    then raise exception 'Original Event Work or lawful owner/Person Ledger relationship is unavailable'
      using errcode='23514';end if;
    return new;
  end if;

  if v_kind='ledger_connection_direct_assignment' then
    if new.assignee_membership_id is not null or new.assigned_by_membership_id is not null
      or new.assignee_canonical_person_id is null
      or coalesce(new.metadata->>'source','')<>'ledger_connected_direct_assignment_v1'
      or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
      or coalesce(v_basis->>'basisKind','')<>v_kind
      or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
      or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
      or coalesce(v_basis->>'assigneePersonId','')<>new.assignee_canonical_person_id::text
      or nullif(v_basis->>'nativeLedgerId','') is null
      or nullif(v_basis->>'senderPersonId','') is null
      or coalesce(v_basis->>'authorizationBasis','')<>'active_mutual_native_ledger_connections'
    then raise exception 'Connected direct assignment requires exact original Person and Ledger source' using errcode='23514';end if;
    if atlas.current_person_id_v1() is distinct from (v_basis->>'senderPersonId')::uuid
      or not atlas.person_has_native_ledger_connection_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
         (v_basis->>'senderPersonId')::uuid)
      or not atlas.person_has_native_ledger_connection_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
         new.assignee_canonical_person_id)
      or not exists(select 1 from atlas.work_items w
         join atlas.company_work_native_ledger_relevance rel
          on rel.work_item_id=w.id and rel.organization_id=w.organization_id
          and rel.ledger_id=(v_basis->>'nativeLedgerId')::uuid
          and rel.attribution_state='active' and rel.evidence_kind='participant_attested'
         where w.id=new.work_item_id and w.organization_id=new.organization_id
           and w.work_state='open'
           and w.metadata->>'sourceContract'='ledger_connected_direct_assignment_v1'
           and w.metadata->>'createdByPersonId'=v_basis->>'senderPersonId'
           and w.metadata->>'recipientPersonId'=new.assignee_canonical_person_id::text)
    then raise exception 'Connection-direct responsibility has no verified original Person and Ledger' using errcode='23514';end if;
    return new;
  end if;

  if v_kind='person_connection_receiver_uptake' then
    if new.assignee_membership_id is not null
       or new.assignee_canonical_person_id is null
       or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
       or coalesce(v_basis->>'basisKind','')<>v_kind
       or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
       or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
       or coalesce(v_basis->>'targetPersonId','')<>new.assignee_canonical_person_id::text
       or coalesce(v_basis->>'nativeLedgerId','')=''
       or coalesce(v_basis->>'offerId','')=''
       or coalesce(v_basis->>'uptakeKind','') not in ('recipient_self_accepted','owner_witnessed_acceptance')
    then raise exception 'Exact Person-native receiver uptake provenance required' using errcode='23514';
    end if;
    if not exists(
      select 1 from atlas.company_work_initial_responsibility_offers o
      where o.id::text=v_basis->>'offerId'
        and o.work_item_id=new.work_item_id
        and o.organization_id=new.organization_id
        and o.target_person_id=new.assignee_canonical_person_id
        and o.ledger_id::text=v_basis->>'nativeLedgerId'
        and o.target_membership_id is null
        and o.offer_state in ('offered','accepted')
        and o.offered_by_membership_id is not distinct from new.assigned_by_membership_id
    ) then raise exception 'Person-native responsibility must trace to the exact accepted offer' using errcode='23514';
    end if;
    if not atlas.person_has_native_ledger_connection_v1(
       new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
       new.assignee_canonical_person_id) then
      raise exception 'Responsible Person native Ledger connection no longer present' using errcode='23514';
    end if;
    if coalesce(v_basis->>'uptakeKind','')='owner_witnessed_acceptance'
      and (length(btrim(coalesce(v_basis->>'receiverConsentEvidence','')))<16
         or coalesce(v_basis->>'witnessPersonId','')='') then
      raise exception 'Owner-witnessed uptake must preserve specific external consent evidence' using errcode='23514';
    end if;
    return new;
  end if;

  -- Native Ledger standing agreement: canonical Person is the assignee,
  -- without invented Organization/employee membership. The original
  -- membership-based delegated branch below remains unchanged.
  if v_kind='delegated_under_standing_scope'
     and new.assignee_canonical_person_id is not null then
    if new.assignee_membership_id is not null
      or (tg_op='INSERT' and new.assigned_by_membership_id is not null)
      or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
      or coalesce(v_basis->>'basisKind','')<>v_kind
      or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
      or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
      or coalesce(v_basis->>'assigneePersonId','')<>new.assignee_canonical_person_id::text
      or nullif(v_basis->>'scopeId','') is null
      or nullif(v_basis->>'nativeLedgerId','') is null then
       raise exception 'Exact canonical Person standing-scope provenance required'
         using errcode='23514';
    end if;
    if not exists(
      select 1 from atlas.company_work_standing_assignment_scopes s
      join atlas.work_items work
        on work.id=new.work_item_id and work.organization_id=s.organization_id
      -- Native governing authority belongs to the verified Principal,
      -- not an Organization Membership/role label.
      join atlas.principals issuer
        on issuer.person_id=s.proposed_by_person_id
        and issuer.status='active'
      join atlas.principal_ledger_authorities grantor
        on grantor.principal_id=issuer.id and grantor.ledger_id=s.ledger_id
        and grantor.authority_kind='root_governing'
        and grantor.status='active'
      join atlas.company_work_native_ledger_relevance relevance
        on relevance.work_item_id=work.id
        and relevance.organization_id=s.organization_id
        and relevance.ledger_id=s.ledger_id
      where s.id::text=v_basis->>'scopeId'
        and s.proposed_by_person_id=atlas.current_person_id_v1()
        and s.organization_id=new.organization_id
        and s.ledger_id::text=v_basis->>'nativeLedgerId'
        and s.worker_person_id=new.assignee_canonical_person_id
        and s.worker_membership_id is null
        and s.scope_state='active' and s.accepted_at is not null
        and s.accepted_by_person_id=new.assignee_canonical_person_id
        and (s.valid_until is null or s.valid_until>now())
        and (s.coverage_mode='ledger_all_work' OR
          (s.coverage_mode='operation_class' AND
           work.organization_unit_id=s.organization_unit_id AND
           work.operation_class=s.covered_operation_class))
        and work.work_state='open'
        and relevance.attribution_state='active'
        and (relevance.evidence_kind='owner_attested' or
          (relevance.evidence_kind='source_verified' and exists(
            select 1 from atlas.company_work_native_ledger_exact_source_v1(
              work.id,s.ledger_id) proof
            where proof.source_schema=relevance.source_schema
              and proof.source_table=relevance.source_table
              and proof.source_id=relevance.source_id)))
    ) then
      raise exception 'Accepted canonical Person standing scope is not current for exact Work'
         using errcode='23514';
    end if;
    if not atlas.person_has_native_ledger_connection_v1(
      new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
      new.assignee_canonical_person_id) then
      raise exception 'Canonical responsible Person no longer connected to this Ledger'
        using errcode='23514';
    end if;
    return new;
  end if;

  if coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
     or coalesce(v_basis->>'basisKind','')<>v_kind
     or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
     or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
     or coalesce(v_basis->>'assigneeMembershipId','')<>new.assignee_membership_id::text then
    raise exception 'Responsibility establishment basis does not match the exact allocation.'
      using errcode='23514';
  end if;

  if v_kind in ('self_claim','self_adoption','self_initiated_outbound') then
    if new.assigned_by_membership_id is null
       or new.assigned_by_membership_id is distinct from new.assignee_membership_id then
      raise exception 'Self-established Work responsibility requires actor and assignee to be the same membership.'
        using errcode='23514';
    end if;
    if coalesce(v_basis->>'actorMembershipId','')<>new.assignee_membership_id::text
       or coalesce(v_basis->>'assigneeMembershipId','')<>new.assignee_membership_id::text then
      raise exception 'Self-establishment basis membership provenance does not match the allocation.'
        using errcode='23514';
    end if;
  end if;

  if v_kind='self_claim'
     and (
       nullif(btrim(coalesce(v_basis->>'institutionalConversationId','')),'') is null
       or nullif(btrim(coalesce(v_basis->>'responseCaseId','')),'') is null
     ) then
    raise exception 'Self-claim responsibility requires conversation and response-case provenance.'
      using errcode='23514';
  end if;

  if v_kind='self_adoption'
     and (
       nullif(btrim(coalesce(v_basis->>'sourceKind','')),'') is null
       or nullif(btrim(coalesce(v_basis->>'sourceId','')),'') is null
     ) then
    raise exception 'Self-adopted responsibility requires an exact source kind and source id.'
      using errcode='23514';
  end if;

  if v_kind='self_initiated_outbound'
     and nullif(btrim(coalesce(v_basis->>'outboundOperationId','')),'') is null then
    raise exception 'Self-initiated outbound responsibility requires outbound-operation provenance.'
      using errcode='23514';
  end if;


  if v_kind='delegated_under_standing_scope' then
    if new.assigned_by_membership_id is null
      or new.assigned_by_membership_id=new.assignee_membership_id
      or coalesce(v_basis->>'scopeId','')=''
      or coalesce(v_basis->>'nativeLedgerId','')=''
      or coalesce(v_basis->>'positionId','')=''
      or coalesce(v_basis->>'actorMembershipId','')<>new.assigned_by_membership_id::text
    then
      raise exception 'Delegated assignment requires exact accepted scope and distinct owner authority'
        using errcode='23514';
    end if;
    -- Never retroactively claim a worker consented. Validate the
    -- captured source and current authority when creating responsibility.
    if v_requires_basis and not exists(
      select 1 from atlas.company_work_standing_assignment_scopes scope
      join atlas.organization_memberships worker
        on worker.id=scope.worker_membership_id and worker.organization_id=scope.organization_id
      join atlas.organization_position_appointments appointment
        on appointment.id=scope.position_appointment_id and appointment.organization_membership_id=worker.id
      join atlas.organization_positions pos
        on pos.id=scope.position_id and pos.organization_id=scope.organization_id
      join atlas.work_items work
        on work.id=new.work_item_id and work.organization_id=scope.organization_id
      join atlas.company_work_native_ledger_relevance relevance
        on relevance.work_item_id=work.id and relevance.organization_id=scope.organization_id
      where scope.id::text=v_basis->>'scopeId'
        and scope.scope_state='active' and scope.accepted_at is not null
        and scope.revoked_at is null
        and (scope.valid_until is null or scope.valid_until>now())
        and scope.organization_id=new.organization_id
        and scope.worker_membership_id=new.assignee_membership_id
        and scope.ledger_id::text=v_basis->>'nativeLedgerId'
        and scope.position_id::text=v_basis->>'positionId'
        and scope.position_appointment_id=appointment.id
        and scope.accepted_by_person_id=worker.person_id
        and worker.active
        and atlas.organization_membership_present_effective_at_v1(worker.id,worker.organization_id,now())
        and appointment.status='active' and appointment.ends_at is null
        and pos.status='active' and pos.organization_unit_id=work.organization_unit_id
        and pos.organization_unit_id=scope.organization_unit_id
        and relevance.ledger_id=scope.ledger_id and relevance.attribution_state='active'
        and (relevance.evidence_kind='owner_attested' or
          (relevance.evidence_kind='source_verified' and exists(
            select 1 from atlas.company_work_native_ledger_exact_source_v1(work.id,scope.ledger_id) proof
             where proof.source_schema=relevance.source_schema
               and proof.source_table=relevance.source_table and proof.source_id=relevance.source_id
          )))
        and exists(select 1 from atlas.organization_memberships manager
          where manager.id=new.assigned_by_membership_id
            and manager.organization_id=new.organization_id and manager.active and manager.role='owner')
    ) then
      raise exception 'Accepted exact-Ledger connection agreement cannot be proved for this Work'
        using errcode='23514';
    end if;
  end if;

  if v_kind='legacy_governed_reconstruction' then
    if v_source not in (
         'legacy_weekly_harvest_occurrence_assignment',
         'explicit_worker_task_company_work_adoption_v2'
       )
       or coalesce(v_basis->>'legacySource','')<>v_source then
      raise exception 'Legacy reconstruction basis is limited to the two named transitional carriers.'
        using errcode='23514';
    end if;

    if v_source='legacy_weekly_harvest_occurrence_assignment'
       and (
         coalesce(v_basis->>'plannedOccurrenceId','')<>coalesce(new.metadata->>'plannedOccurrenceId','')
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='planned_work_occurrence'
             and work.source_object_id::text=(v_basis->>'plannedOccurrenceId')
         )
       ) then
      raise exception 'Legacy weekly-harvest responsibility basis does not match the exact Work source.'
        using errcode='23514';
    end if;

    if v_source='explicit_worker_task_company_work_adoption_v2'
       and (
         coalesce(v_basis->>'legacyTaskId','')<>coalesce(new.metadata->>'legacyTaskId','')
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='legacy_task'
             and work.source_object_id::text=(v_basis->>'legacyTaskId')
         )
       ) then
      raise exception 'Legacy task responsibility basis does not match the exact Work source.'
        using errcode='23514';
    end if;
  end if;

  new.establishment_basis_kind:=v_kind;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION atlas.owner_set_connected_person_work_day_self_api_v1(p_work_item_id uuid, p_ledger_id uuid, p_service_date date, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
  v_old atlas.work_execution_plans%rowtype;
  v_owner uuid;
  v_owner_member uuid;
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
  v_window jsonb;
  v_event text;
begin
  if auth.uid() is null or p_work_item_id is null or p_ledger_id is null
    or v_reason is null or length(v_reason) not between 12 and 1200 then
    raise exception 'Exact owner Work, Ledger and meaningful planning reason required.'
      using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.responsibility:'||p_work_item_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.plan:'||p_work_item_id::text,0));
  select * into v_work from atlas.work_items
    where id=p_work_item_id and work_state='open' for update;
  if v_work.id is null then raise exception 'Open Work required for date changes.'
    using errcode='23514'; end if;
  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    v_work.organization_id,p_ledger_id);
  v_owner_member:=atlas.current_effective_organization_membership_v1(
    v_work.organization_id);
  if not exists (
    select 1 from atlas.organization_memberships m
    where m.id=v_owner_member and m.organization_id=v_work.organization_id
      and m.person_id=v_owner and m.role='owner' and m.active
  ) then raise exception 'Current authenticated owner membership required.'
    using errcode='42501'; end if;
  if not exists (
    select 1 from atlas.company_work_native_ledger_relevance rel
    where rel.organization_id=v_work.organization_id
      and rel.work_item_id=v_work.id
      and rel.ledger_id=p_ledger_id and rel.attribution_state='active'
      and (rel.evidence_kind in ('owner_attested','participant_attested') or
        (rel.evidence_kind='source_verified' and exists (
          select 1 from atlas.company_work_native_ledger_exact_source_v1(
            v_work.id,p_ledger_id) proof
          where proof.source_schema=rel.source_schema
            and proof.source_table=rel.source_table
            and proof.source_id=rel.source_id
        )))
  ) then raise exception 'Exact Ledger relevance required.' using errcode='42501'; end if;
  select * into v_allocation from atlas.work_allocations a
    where a.work_item_id=v_work.id and a.organization_id=v_work.organization_id
      and a.allocation_role='responsible' and a.state='active'
      and a.assignee_membership_id is null
      and a.assignee_canonical_person_id is not null
      and a.establishment_basis_kind in (
        'delegated_under_standing_scope','person_connection_receiver_uptake','original_subject_direct_assignment_v1')
      and a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text
    limit 1;
  if v_allocation.id is null or not atlas.person_has_native_ledger_connection_v1(
    v_work.organization_id,p_ledger_id,v_allocation.assignee_canonical_person_id) then
    raise exception 'Active connected Person responsibility required.'
      using errcode='23514';
  end if;
  select * into v_old from atlas.work_execution_plans
    where work_item_id=v_work.id and plan_state in ('active','needs_replan')
    for update;
  if v_old.id is not null and
    v_old.responsible_allocation_id<>v_allocation.id then
    raise exception 'Current plan belongs to different responsibility.'
      using errcode='23514';
  end if;

  if p_service_date is null then
    if v_old.id is null then
      return jsonb_build_object('ok',true,
        'contractVersion','native_person_work_plan_v1',
        'state','already_unplanned','workItemId',v_work.id,
        'ledgerId',p_ledger_id,'responsiblePersonId',
        v_allocation.assignee_canonical_person_id,'newWorkCreated',false);
    end if;
    update atlas.work_execution_plans
      set plan_state='withdrawn',plan_reason=v_reason,
      metadata=metadata||jsonb_build_object(
        'sourceChange','native_person_owner_unplan_v1',
        'withdrawalReason',v_reason)
    where id=v_old.id and plan_state in ('active','needs_replan');
    insert into atlas.work_execution_plan_events(
      organization_id,work_item_id,plan_id,event_kind,
      from_planned_service_date,from_exposure_service_date,
      actor_membership_id,reason,metadata)
    values (v_work.organization_id,v_work.id,v_old.id,'withdrawn',
      v_old.planned_service_date,v_old.exposure_service_date,
      v_owner_member,v_reason,
      jsonb_build_object('source','native_person_owner_unplan_v1'));
    return jsonb_build_object('ok',true,
      'contractVersion','native_person_work_plan_v1',
      'state','unplanned','workItemId',v_work.id,'ledgerId',p_ledger_id,
      'planId',v_old.id,'responsiblePersonId',
      v_allocation.assignee_canonical_person_id,'newWorkCreated',false);
  end if;
  v_window:=atlas.company_work_execution_plan_window_check_v1(
    v_work.id,p_service_date);
  if not coalesce((v_window->>'allowed')::boolean,false) then
    raise exception 'Selected date conflicts with source-owned Work window (%).',
      v_window->>'state' using errcode='23514';
  end if;
  if v_old.id is null then
    insert into atlas.work_execution_plans(
      organization_id,work_item_id,responsible_allocation_id,
      assignee_membership_id,planned_by_membership_id,
      plan_state,first_planned_service_date,planned_service_date,
      exposure_service_date,plan_reason,metadata)
    values (v_work.organization_id,v_work.id,v_allocation.id,null,
      v_owner_member,'active',p_service_date,p_service_date,
      p_service_date,v_reason,
      jsonb_build_object('source','native_person_owner_plan_v1'))
    returning * into v_plan;
    v_event:='planned';
  else
    update atlas.work_execution_plans
      set planned_service_date=p_service_date,exposure_service_date=p_service_date,
        plan_state='active',plan_reason=v_reason,
        planned_by_membership_id=v_owner_member,
        metadata=metadata||jsonb_build_object(
          'sourceChange','native_person_owner_plan_v1'),
        rollover_count=0
      where id=v_old.id returning * into v_plan;
    v_event:=case when v_old.planned_service_date is distinct from p_service_date
      then 'rescheduled' else 'planned' end;
  end if;
  insert into atlas.work_execution_plan_events(
    organization_id,work_item_id,plan_id,event_kind,
    from_planned_service_date,to_planned_service_date,
    from_exposure_service_date,to_exposure_service_date,
    actor_membership_id,reason,metadata)
  values (v_work.organization_id,v_work.id,v_plan.id,v_event,
    v_old.planned_service_date,v_plan.planned_service_date,
    v_old.exposure_service_date,v_plan.exposure_service_date,
    v_owner_member,v_reason,
    jsonb_build_object('source','native_person_owner_plan_v1'));
  return jsonb_build_object('ok',true,
    'contractVersion','native_person_work_plan_v1',
    'state','planned','workItemId',v_work.id,
    'ledgerId',p_ledger_id,'planId',v_plan.id,
    'plannedServiceDate',v_plan.planned_service_date,
    'responsiblePersonId',v_allocation.assignee_canonical_person_id,
    'newWorkCreated',false,'workerReadProven',false);
end
$function$
;

CREATE OR REPLACE FUNCTION atlas.report_connected_person_company_work_internal_v1(p_work_item_id uuid, p_result_kind text, p_idempotency_key text, p_payload jsonb, p_mode text, p_owner_ledger_id uuid, p_witness_evidence text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_actor uuid:=atlas.current_person_id_v1();
  v_kind text:=lower(btrim(coalesce(p_result_kind,'')));
  v_mode text:=lower(btrim(coalesce(p_mode,'')));
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_evidence text:=nullif(btrim(coalesce(p_witness_evidence,'')),'');
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_existing atlas.work_execution_results%rowtype;
  v_result atlas.work_execution_results%rowtype;
  v_acceptance atlas.work_result_acceptances%rowtype;
  v_reporter_ipr uuid;
begin
  if v_uid is null or v_actor is null then
    raise exception 'Signed-in canonical reporting Person required' using errcode='42501';
  end if;
  if p_work_item_id is null or v_kind not in ('completed','partial','blocked','unable')
    or v_mode not in ('own_work','owner_witness')
    or v_key is null or length(v_key)>160
    or p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'Exact Work, result, mode, idempotency and object payload required'
      using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.responsibility:'||p_work_item_id,0));
  select * into v_work from atlas.work_items
    where id=p_work_item_id for update;
  if v_work.id is null then raise exception 'Company Work not found' using errcode='P0002'; end if;
  select * into v_allocation from atlas.work_allocations a
    where a.work_item_id=v_work.id and a.organization_id=v_work.organization_id
      and a.allocation_role='responsible'
      and a.establishment_basis_kind in ('person_connection_receiver_uptake','delegated_under_standing_scope','ledger_connection_direct_assignment','original_subject_direct_assignment_v1')
      and a.state in ('active','completed')
    order by a.allocated_at desc limit 1;
  if v_allocation.id is null then
    raise exception 'Exact Person-native responsible allocation not found' using errcode='23514';
  end if;
  if v_mode='own_work' then
    if v_allocation.assignee_canonical_person_id<>v_actor then
      raise exception 'Only actual responsible Person can make own-work report' using errcode='42501';
    end if;
  else
    if v_evidence is null or length(v_evidence) not between 16 and 2000
      or (v_allocation.establishment_basis->>'nativeLedgerId') is distinct from
        p_owner_ledger_id::text
      or atlas.company_work_native_ledger_owner_self_v1(
        v_work.organization_id,p_owner_ledger_id)<>v_actor then
      raise exception 'Owner report requires exact Ledger and detailed external evidence'
        using errcode='42501';
    end if;
  end if;
  select * into v_existing from atlas.work_execution_results r
    where r.organization_id=v_work.organization_id and r.idempotency_key=v_key;
  if v_existing.id is not null then
    if v_existing.work_item_id<>v_work.id or v_existing.result_kind<>v_kind
      or v_existing.responsible_allocation_id<>v_allocation.id
      or v_existing.metadata->>'reportMode' is distinct from v_mode
      or v_existing.metadata->>'authenticatedReporterPersonId'
           is distinct from v_actor::text
      or (v_mode='owner_witness' and
          v_existing.payload->>'ownerWitnessEvidence' is distinct from v_evidence)
      or (v_mode='own_work' and
          (v_existing.payload-'claimedPerformerPersonId'-'ownerWitnessEvidence')
            is distinct from p_payload) then
      raise exception 'Result idempotency collision' using errcode='23505';
    end if;
    return jsonb_build_object('ok',true,'idempotent',true,
      'resultId',v_existing.id,'workItemId',v_work.id,
      'workState',v_work.work_state);
  end if;
  if v_work.work_state<>'open' or v_allocation.state<>'active' then
    raise exception 'Terminal Work cannot receive another result' using errcode='23514';
  end if;
  if v_work.result_contract_key<>'ordinary_company_work_worker_attestation_v1'
    or not exists(select 1 from atlas.work_result_contract_policies p
      where p.contract_key=v_work.result_contract_key and p.active
        and p.acceptance_mode='worker_attestation'
        and p.source_domain='organization') then
    raise exception 'Source-specific Work requires its authorized result channel'
      using errcode='23514';
  end if;
  select ipr.id into v_reporter_ipr
    from atlas.institutional_person_records ipr
    where ipr.organization_id=v_work.organization_id
      and ipr.person_id=v_actor and ipr.status='active'
    order by ipr.created_at limit 1;
  insert into atlas.work_execution_results(
    organization_id,work_item_id,responsible_allocation_id,
    reported_by_user_id,reported_by_organization_membership_id,
    reported_by_institutional_person_record_id,
    result_kind,result_contract_key,idempotency_key,payload,metadata
  ) values(
    v_work.organization_id,v_work.id,v_allocation.id,
    v_uid,null,v_reporter_ipr,
    v_kind,v_work.result_contract_key,v_key,
    p_payload||jsonb_strip_nulls(jsonb_build_object(
      'claimedPerformerPersonId',v_allocation.assignee_canonical_person_id,
      'ownerWitnessEvidence',case when v_mode='owner_witness'
        then v_evidence else null end)),
    jsonb_build_object('source','report_connected_person_company_work_internal_v1',
      'reportMode',v_mode,'authenticatedReporterPersonId',v_actor,
      'canonicalResponsiblePersonId',v_allocation.assignee_canonical_person_id,
      'performanceIsWitnessedClaim',v_mode='owner_witness',
      'employeeSeatRequired',false)
  ) returning * into v_result;
  if v_kind='completed' then
    insert into atlas.work_result_acceptances(
      organization_id,work_item_id,execution_result_id,
      decision,acceptance_kind,accepted_by_domain,evidence,metadata
    ) values (
      v_work.organization_id,v_work.id,v_result.id,'accepted',
      case when v_mode='own_work' then 'self_responsible_person_attestation'
        else 'owner_witnessed_person_result' end,
      'organization',
      jsonb_strip_nulls(jsonb_build_object(
        'responsibleAllocationId',v_allocation.id,
        'canonicalResponsiblePersonId',v_allocation.assignee_canonical_person_id,
        'authenticatedReporterPersonId',v_actor,
        'ownerWitnessEvidence',case when v_mode='owner_witness'
          then v_evidence else null end)),
      jsonb_build_object('source','report_connected_person_company_work_internal_v1',
        'reportMode',v_mode,'notAnEmployeeWorkerDayReport',true)
    ) returning * into v_acceptance;
    update atlas.work_items
      set work_state='completed',completed_at=coalesce(completed_at,now()),
        updated_at=now()
      where id=v_work.id and work_state='open';
    update atlas.work_allocations
      set state='completed',completed_at=coalesce(completed_at,now()),
        updated_at=now()
      where id=v_allocation.id and state='active';
  end if;
  return jsonb_build_object('ok',true,'idempotent',false,
    'contractVersion','connected_person_company_work_result_v1',
    'workItemId',v_work.id,'resultId',v_result.id,
    'resultKind',v_kind,'workState',
      case when v_kind='completed' then 'completed' else 'open' end,
    'acceptanceDecision',v_acceptance.decision,
    'reportMode',v_mode,'responsiblePersonId',
      v_allocation.assignee_canonical_person_id,
    'reporterPersonId',v_actor,'sourceHistoryPreserved',true);
end
$function$
;

CREATE OR REPLACE FUNCTION atlas.validate_active_work_allocation_membership_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
begin
  if new.state='active' then
    if new.allocation_role='responsible'
      and new.establishment_basis_kind in ('person_connection_receiver_uptake','delegated_under_standing_scope','ledger_connection_direct_assignment','original_subject_direct_assignment_v1')
      and new.assignee_canonical_person_id is not null then
      if new.assignee_membership_id is not null
        or new.assignee_canonical_person_id is null
        or not atlas.person_has_native_ledger_connection_v1(
          new.organization_id,(new.establishment_basis->>'nativeLedgerId')::uuid,
          new.assignee_canonical_person_id) then
        raise exception 'Person-native responsibility requires an exact active Ledger connection'
          using errcode='23514';
      end if;
    elsif not exists (
      select 1 from atlas.organization_memberships om
      where om.id=new.assignee_membership_id
        and om.organization_id=new.organization_id and om.active
    ) then
      raise exception 'Legacy active Work allocation requires active Organization Membership'
        using errcode='23514';
    end if;
    if new.assigned_by_membership_id is not null
      and (tg_op='INSERT'
        or old.assigned_by_membership_id is distinct from new.assigned_by_membership_id
        or old.state is distinct from new.state
        or old.organization_id is distinct from new.organization_id)
      and not exists (
        select 1 from atlas.organization_memberships om
        where om.id=new.assigned_by_membership_id
          and om.organization_id=new.organization_id and om.active
      ) then
      raise exception 'Active Work allocation cannot name an inactive assigning membership'
        using errcode='23514';
    end if;
  end if;
  return new;
end
$function$
;

CREATE OR REPLACE FUNCTION atlas.validate_work_execution_plan_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_delivery jsonb;
  v_ledger_id uuid;
begin
  select * into v_work from atlas.work_items where id=new.work_item_id;
  if v_work.id is null or v_work.organization_id<>new.organization_id then
    raise exception 'Execution plan must belong to its Company Work organization.'
      using errcode='23514';
  end if;
  select * into v_allocation from atlas.work_allocations
    where id=new.responsible_allocation_id;
  if v_allocation.id is null
    or v_allocation.organization_id<>new.organization_id
    or v_allocation.work_item_id<>new.work_item_id
    or v_allocation.assignee_membership_id is distinct from new.assignee_membership_id
    or v_allocation.allocation_role<>'responsible' then
    raise exception 'Execution plan must point to the exact responsible allocation.'
      using errcode='23514';
  end if;
  if new.plan_state='active' then
    -- The date-only deadline is independent of this service date, but a
    -- later plan cannot silently ignore the established deadline.
    if exists (
      select 1 from atlas.work_time_contracts t
      where t.work_item_id=new.work_item_id and t.contract_state='active'
        and t.due_on_date is not null
        and (new.planned_service_date>t.due_on_date
          or new.exposure_service_date>t.due_on_date)
    ) then
      raise exception 'Plan is beyond the governing date-only deadline.'
        using errcode='23514';
    end if;
    if v_work.work_state<>'open' or v_allocation.state<>'active' then
      raise exception 'Active plan requires open Work and active responsibility.'
        using errcode='23514';
    end if;
    if new.assignee_membership_id is not null then
      v_delivery:=atlas.company_work_execution_membership_check_v1(
        new.work_item_id,new.assignee_membership_id,new.planned_service_date);
      if not coalesce((v_delivery->>'allowed')::boolean,false) then
        raise exception 'Responsible membership is not eligible on planned day (%).',
          v_delivery->>'state' using errcode='23514';
      end if;
      v_delivery:=atlas.company_work_execution_membership_check_v1(
        new.work_item_id,new.assignee_membership_id,new.exposure_service_date);
      if not coalesce((v_delivery->>'allowed')::boolean,false) then
        raise exception 'Responsible membership is not eligible on exposure day (%).',
          v_delivery->>'state' using errcode='23514';
      end if;
    else
      -- A Person plan never creates a farm/employee execution credential.
      if v_allocation.assignee_canonical_person_id is null
        or v_allocation.establishment_basis_kind not in (
          'delegated_under_standing_scope','person_connection_receiver_uptake','ledger_connection_direct_assignment','original_subject_direct_assignment_v1')
        or coalesce(v_allocation.establishment_basis->>'nativeLedgerId','')
             !~ '^[0-9a-fA-F-]{36}$' then
        raise exception 'Person plan requires accepted canonical Person responsibility.'
          using errcode='23514';
      end if;
      v_ledger_id:=(v_allocation.establishment_basis->>'nativeLedgerId')::uuid;
      if not atlas.person_has_native_ledger_connection_v1(
          v_work.organization_id,v_ledger_id,v_allocation.assignee_canonical_person_id)
        or not exists (
          select 1 from atlas.company_work_native_ledger_relevance rel
          where rel.organization_id=v_work.organization_id and rel.work_item_id=v_work.id
            and rel.ledger_id=v_ledger_id and rel.attribution_state='active'
        ) then
        raise exception 'Person plan requires currently valid exact Ledger connection.'
          using errcode='23514';
      end if;
    end if;
  end if;
  new.updated_at:=now();
  return new;
end
$function$
;


-- Existing signed all-date Person Today, day, prerequisite and governor
-- activity readers admit the same directly assigned original Work identity.
CREATE OR REPLACE FUNCTION atlas.connected_person_company_work_day_self_api_v1(p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_self uuid:=atlas.current_person_id_v1();
  v_items jsonb;
BEGIN
  IF auth.uid() IS NULL OR v_self IS NULL OR p_date IS NULL THEN
    RAISE EXCEPTION 'Signed-in canonical Person and exact day required.' USING errcode='42501';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'workItemId',w.id,'allocationId',a.id,'planId',p.id,
    'organizationId',w.organization_id,
    'ledgerId',(a.establishment_basis->>'nativeLedgerId')::uuid,
    'title',w.title,'instructions',w.instructions,
    'executionDate',p.planned_service_date,'exposureDate',p.exposure_service_date,
    'dueDate',t.due_on_date,'taskClassification',
      coalesce(w.metadata->>'taskClassification','ordinary'),
    'workState',w.work_state,'allocationState',a.state,
    'completedAt',w.completed_at,
    'latestResultId',res.id,'latestResultKind',res.result_kind,
    'latestResultAt',res.reported_at,'latestAcceptanceDecision',res.acceptance_decision,
    'canReportOrdinaryCompletion',
      w.work_state='open' AND a.state='active'
      AND w.result_contract_key='ordinary_company_work_worker_attestation_v1'
  ) ORDER BY p.created_at,w.id),'[]'::jsonb) INTO v_items
  FROM atlas.work_allocations a
  JOIN atlas.work_items w ON w.id=a.work_item_id AND w.organization_id=a.organization_id
  JOIN atlas.work_execution_plans p ON p.work_item_id=w.id
    AND p.organization_id=w.organization_id
    AND p.responsible_allocation_id=a.id
    AND (
      (p.plan_state='active' AND w.work_state='open' AND a.state='active')
      OR
      (p.plan_state='completed' AND w.work_state='completed' AND a.state='completed')
    )
    AND p.exposure_service_date=p_date
    AND p.assignee_membership_id IS NULL
  LEFT JOIN LATERAL (
    SELECT due_on_date FROM atlas.work_time_contracts t
    WHERE t.work_item_id=w.id AND t.contract_state='active'
    ORDER BY t.created_at DESC LIMIT 1
  ) t ON true
  LEFT JOIN LATERAL (
    SELECT r.id,r.result_kind,r.reported_at,
      (SELECT ra.decision FROM atlas.work_result_acceptances ra
       WHERE ra.execution_result_id=r.id
       ORDER BY ra.accepted_at DESC,ra.id DESC LIMIT 1) AS acceptance_decision
    FROM atlas.work_execution_results r
    WHERE r.work_item_id=w.id AND r.responsible_allocation_id=a.id
    ORDER BY r.reported_at DESC,r.id DESC LIMIT 1
  ) res ON true
  WHERE a.assignee_canonical_person_id=v_self
    AND a.assignee_membership_id IS NULL
    AND a.allocation_role='responsible'
    AND a.establishment_basis_kind IN
      ('person_connection_receiver_uptake','delegated_under_standing_scope',
       'ledger_connection_direct_assignment','original_subject_direct_assignment_v1')
    AND ((a.state='active' AND w.work_state='open')
      OR (a.state='completed' AND w.work_state='completed'))
    AND atlas.person_has_native_ledger_connection_v1(
      w.organization_id,(a.establishment_basis->>'nativeLedgerId')::uuid,v_self);
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','connected_person_company_work_day_v1',
    'date',p_date,'personId',v_self,'items',v_items,
    'oneCanonicalWorkIdentity',true,'deliveryReadProven',false);
END
$function$
;

CREATE OR REPLACE FUNCTION atlas.connected_person_company_work_today_self_api_v1(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_self uuid:=atlas.current_person_id_v1();
  v_items jsonb:='[]'::jsonb;
begin
  if auth.uid() is null or v_self is null then
    raise exception 'Signed-in canonical Person required' using errcode='42501';
  end if;
  if p_limit not between 1 and 100 then
    raise exception 'Page size must be between 1 and 100' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'workItemId',row.work_id,'allocationId',row.allocation_id,
    'organizationId',row.organization_id,'ledgerId',row.ledger_id,
    'title',row.title,'instructions',row.instructions,
    'sourceType',row.source_type,'sourceId',row.source_id,
    'sourceDate',row.source_date,'sourceDateIsNotScheduledDay',true,
    'resultContractKey',row.result_contract,
    'canReportOrdinaryCompletion',row.result_contract=
      'ordinary_company_work_worker_attestation_v1',
    'uptakeKind',row.uptake_kind,'establishmentBasisKind',row.basis_kind,'employeeSeatRequired',false)
    order by row.allocated_at,row.work_id),'[]'::jsonb) into v_items
  from (
    select w.id work_id,a.id allocation_id,w.organization_id,
      (a.establishment_basis->>'nativeLedgerId')::uuid ledger_id,
      w.title,w.instructions,w.source_object_type source_type,
      w.source_object_id source_id,
      case when w.metadata->>'originalServiceDate' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        then w.metadata->>'originalServiceDate' else null end source_date,
      w.result_contract_key result_contract,
      a.establishment_basis->>'uptakeKind' uptake_kind,a.establishment_basis_kind basis_kind,a.allocated_at
    from atlas.work_allocations a
    join atlas.work_items w on w.id=a.work_item_id
      and w.organization_id=a.organization_id
    where a.allocation_role='responsible' and a.state='active'
      and a.assignee_canonical_person_id=v_self
      and a.establishment_basis_kind in ('person_connection_receiver_uptake','delegated_under_standing_scope','ledger_connection_direct_assignment','original_subject_direct_assignment_v1')
      and w.work_state='open'
    order by a.allocated_at,a.id
    limit p_limit
  ) row;
  return jsonb_build_object('ok',true,
    'contractVersion','connected_person_company_work_today_v1',
    'personId',v_self,'items',v_items,
    'sourceDateIsNotAWorkSchedule',true,'employeeSeatRequired',false);
end
$function$
;

CREATE OR REPLACE FUNCTION atlas.connected_person_work_prerequisites_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_downstream_work_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_person uuid;
  v_items jsonb := '[]'::jsonb;
begin
  -- auth.uid() alone is insufficient: require a live, genuine Auth session
  -- and ready canonical Personal Atlas, not a forged or expired JWT.
  if auth.uid() is null
     or (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready' then
    raise exception 'Current signed-in Atlas Person required.'
      using errcode='42501';
  end if;
  v_person:=atlas.current_person_id_v1();
  if v_person is null or p_organization_id is null or p_ledger_id is null
     or p_downstream_work_item_id is null then
    raise exception 'Exact connected Person and original Work source required.'
      using errcode='42501';
  end if;

  -- The member's Ledger seat alone NEVER grants an institution-wide read.
  -- An original, current responsible allocation to this exact downstream
  -- Work and this exact native Ledger is required. Keep the person-only
  -- carrier, no employee seats and no optional proposed work requests.
  if not atlas.person_has_native_ledger_connection_v1(
      p_organization_id,p_ledger_id,v_person)
     or not atlas.work_prerequisite_ledger_scope_v1(
      p_organization_id,p_ledger_id,p_downstream_work_item_id)
     or not exists (
       select 1
       from atlas.work_allocations a
       join atlas.work_items w
         on w.id=a.work_item_id and w.organization_id=a.organization_id
       where a.organization_id=p_organization_id
         and a.work_item_id=p_downstream_work_item_id
         and a.assignee_canonical_person_id=v_person
         and a.assignee_membership_id is null
         and a.allocation_role='responsible'
         and a.establishment_basis_kind in (
           'person_connection_receiver_uptake',
           'delegated_under_standing_scope',
           'ledger_connection_direct_assignment','original_subject_direct_assignment_v1'
         )
         and a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text
         and (
           (a.state='active' and w.work_state='open')
           or (a.state='completed' and w.work_state='completed')
         )
     ) then
    raise exception 'Current responsibility for this exact Ledger Work required.'
      using errcode='42501';
  end if;

  -- Only original active depends_on edges for the Work the person actually
  -- owns responsibility for. A prerequisite's title is included strictly
  -- because this original edge, authorized downstream allocation and
  -- independently evidenced relevance to the SAME native Ledger all exist.
  -- No unrelated Work listing, assignment/person identity, source metadata,
  -- private action-history, or institutional owner privileges are exposed.
  select coalesce(jsonb_agg(jsonb_build_object(
    'relationId',r.id,
    'relationKind','depends_on',
    'downstreamWorkItemId',r.from_work_item_id,
    'prerequisiteWorkItemId',r.to_work_item_id,
    'title',p.title,
    'prerequisiteWorkState',p.work_state,
    'active',r.active,
    'recordedSatisfiedAt',r.satisfied_at
  ) order by r.id),'[]'::jsonb)
  into v_items
  from atlas.work_item_relations r
  join atlas.work_items p
    on p.id=r.to_work_item_id and p.organization_id=r.organization_id
  where r.organization_id=p_organization_id
    and r.from_work_item_id=p_downstream_work_item_id
    and r.relation_kind='depends_on'
    and r.active
    and atlas.work_prerequisite_ledger_scope_v1(
      p_organization_id,p_ledger_id,r.to_work_item_id);

  return jsonb_build_object(
    'ok',true,
    'contractVersion','connected_person_work_prerequisites_v1',
    'organizationId',p_organization_id,
    'ledgerId',p_ledger_id,
    'downstreamWorkItemId',p_downstream_work_item_id,
    'personId',v_person,
    'relations',v_items,
    'sourceScope','original_responsible_person_downstream_work',
    'onlyCurrentLedgerEvidence',true,
    'activeRelationsOnly',true,
    'doesNotAuthorizeRelationChanges',true,
    'doesNotInferCompletionOrSatisfaction',true
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION atlas.today_work_assignment_activity_self_api_v1(p_date date, p_timezone text DEFAULT 'UTC'::text, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_person uuid;v_rows jsonb;v_count int;
begin
 if auth.uid() is null or p_date is null or p_limit not between 1 and 200
   or p_timezone is null or not exists(select 1 from pg_catalog.pg_timezone_names tz where tz.name=p_timezone)
   or (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready' then
   raise exception 'Signed-in Person, real day and valid timezone required' using errcode='42501';
 end if;
 v_person:=atlas.current_person_id_v1();
 with eligible as(
  select w.id,w.title,w.created_at,a.allocated_at,a.state allocation_state,
    a.assignee_canonical_person_id recipient_id,e.display_name recipient_name,
    l.id ledger_id,l.name ledger_name,
    ep.exposure_service_date,ep.id plan_id,
    a.establishment_basis_kind as activity_kind
  from atlas.work_items w
  join atlas.work_allocations a on a.work_item_id=w.id and a.organization_id=w.organization_id
    and a.allocation_role='responsible'
    and a.establishment_basis_kind in ('ledger_connection_direct_assignment','original_subject_direct_assignment_v1','delegated_under_standing_scope')
  join reality.entities e on e.id=a.assignee_canonical_person_id
    and e.entity_kind='person' and e.identity_state='canonical'
  join ledger.ledgers l on l.id=(a.establishment_basis->>'nativeLedgerId')::uuid
  left join lateral (
    select p.id,p.exposure_service_date from atlas.work_execution_plans p
    where p.work_item_id=w.id and p.organization_id=w.organization_id
      and p.responsible_allocation_id=a.id
    order by p.created_at desc,p.id desc limit 1
  ) ep on true
  where w.created_by_user_id=auth.uid()
    and a.establishment_basis->>'senderPersonId'=v_person::text
    and (a.allocated_at at time zone p_timezone)::date=p_date
    and exists(select 1 from ledger.seats s where s.ledger_id=l.id and s.person_entity_id=v_person
      and s.seat_state='active' and s.ended_at is null)
  order by a.allocated_at,w.id
  limit p_limit+1
 ), counted as(select count(*) n from eligible)
 select coalesce(jsonb_agg(jsonb_build_object(
  'workItemId',id,'title',title,'allocatedAt',allocated_at,'createdAt',created_at,
  'allocationState',allocation_state,'recipientPersonId',recipient_id,
  'recipientName',recipient_name,'ledgerId',ledger_id,'ledgerName',ledger_name,
  'workOn',exposure_service_date,'planId',plan_id,'kind',activity_kind)
  order by allocated_at,id) filter(where rn<=p_limit),'[]'::jsonb),(select n from counted)
 into v_rows,v_count
 from (select *,row_number() over(order by allocated_at,id) rn from eligible) ranked;
 return jsonb_build_object('ok',true,'contractVersion','today_work_assignment_activity_v1',
  'date',p_date,'timezone',p_timezone,'items',v_rows,'hasMore',v_count>p_limit,
  'actorPersonId',v_person,'source','work_allocations_original',
  'noNewJournalTestimony',true);
end $function$
;
-- Original held candidate: original_subject_work_existing_direct_responsibility_v1/candidate.sql
-- Requires original_work_decomposition + native guarded reader extensions.
-- Assigns ONE EXISTING canonical Work ID; never creates or imports another.
CREATE OR REPLACE FUNCTION atlas.owner_original_split_work_part_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_owner uuid;v_work atlas.work_items%rowtype;
 v_group atlas.work_decomposition_groups%rowtype;
 v_subject atlas.work_decomposition_members%rowtype;
BEGIN
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
 SELECT * INTO v_work FROM atlas.work_items
 WHERE id=p_work_item_id AND organization_id=p_organization_id;
 IF v_work.id IS NULL OR v_work.source_object_type<>'work_decomposition'
    OR v_work.work_state<>'open' THEN
  RAISE EXCEPTION 'Open original split Work unavailable.' USING ERRCODE='42501';
 END IF;
 SELECT m.* INTO v_subject
 FROM atlas.work_decomposition_members m
 JOIN atlas.work_decomposition_groups g ON g.id=m.group_id
 WHERE m.child_work_item_id=v_work.id
   AND g.authorized_ledger_id=p_ledger_id
   AND g.parent_work_item_id=v_work.source_object_id;
 IF v_subject.id IS NULL OR NOT EXISTS (
  SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
  WHERE rel.work_item_id=v_work.id AND rel.organization_id=p_organization_id
   AND rel.ledger_id=p_ledger_id AND rel.attribution_state='active'
 ) THEN RAISE EXCEPTION 'Exact original Work/Ledger relevance unavailable.'
    USING ERRCODE='42501';
 END IF;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','original_split_work_part_v1',
   'organizationId',p_organization_id,'ledgerId',p_ledger_id,
   'workItemId',v_work.id,'groupId',v_subject.group_id,
   'subjectDomain',v_subject.subject_domain,
   'subjectKind',v_subject.subject_kind,'subjectId',v_subject.subject_id,
   'isOneOriginalWork',true,'workerCanSelfAttest',
   v_work.result_contract_key='ordinary_company_work_worker_attestation_v1');
END;
$function$;
REVOKE ALL ON FUNCTION atlas.owner_original_split_work_part_self_api_v1(
 uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.owner_original_split_work_part_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.owner_original_split_work_part_self_api_v1(
 p_organization_id,p_ledger_id,p_work_item_id);
$function$;
REVOKE ALL ON FUNCTION public.owner_original_split_work_part_self_api_v1(
 uuid,uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.owner_original_split_work_part_self_api_v1(
 uuid,uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION atlas.owner_direct_assign_existing_original_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_target_person_id uuid,p_service_date date,p_action_id uuid,p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
 v_owner uuid;
 v_work atlas.work_items%rowtype;
 v_group atlas.work_decomposition_groups%rowtype;
 v_allocation atlas.work_allocations%rowtype;
 v_plan atlas.work_execution_plans%rowtype;
 v_window jsonb;
 v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
 v_created boolean:=false;
BEGIN
 IF p_organization_id IS NULL OR p_ledger_id IS NULL
    OR p_work_item_id IS NULL OR p_target_person_id IS NULL
    OR p_service_date IS NULL OR p_action_id IS NULL
    OR v_reason IS NULL OR length(v_reason) NOT BETWEEN 12 AND 1200 THEN
    RAISE EXCEPTION 'Exact existing Work, Person, date, action and reason required'
      USING ERRCODE='22023';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(
   p_organization_id,p_ledger_id);
 IF v_owner=p_target_person_id OR NOT atlas.person_has_native_ledger_connection_v1(
   p_organization_id,p_ledger_id,p_target_person_id) THEN
   RAISE EXCEPTION 'Direct allocation requires another genuinely connected Person'
      USING ERRCODE='42501';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'atlas.company_work.responsibility:'||p_work_item_id::text,0));
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'atlas.company_work.plan:'||p_work_item_id::text,0));
 SELECT * INTO v_work FROM atlas.work_items
 WHERE id=p_work_item_id AND organization_id=p_organization_id FOR UPDATE;
 IF v_work.id IS NULL OR v_work.work_state<>'open'
   OR v_work.source_object_type<>'work_decomposition'
   OR v_work.result_contract_key NOT IN(
      'ordinary_company_work_worker_attestation_v1',
      'ordinary_company_work_manager_acceptance_v1'
   ) THEN
   RAISE EXCEPTION 'Only still-open original decomposed Work can be directly assigned.'
     USING ERRCODE='23514';
 END IF;
 SELECT g.* INTO v_group FROM atlas.work_decomposition_groups g
 JOIN atlas.work_decomposition_members m ON m.group_id=g.id
 WHERE m.child_work_item_id=v_work.id AND g.authorized_ledger_id=p_ledger_id
   AND g.parent_work_item_id=v_work.source_object_id;
 IF v_group.id IS NULL OR NOT EXISTS(
   SELECT 1 FROM atlas.company_work_native_ledger_relevance r
   WHERE r.organization_id=p_organization_id
     AND r.ledger_id=p_ledger_id AND r.work_item_id=v_work.id
     AND r.attribution_state='active'
 ) THEN RAISE EXCEPTION 'Exact governed Work/Subject Ledger provenance unavailable.'
    USING ERRCODE='42501'; END IF;
 IF EXISTS(
   SELECT 1 FROM atlas.work_allocations a
   WHERE a.organization_id=p_organization_id AND a.work_item_id=v_work.id
     AND a.state='active' AND a.allocation_role='responsible'
     AND (a.assignee_canonical_person_id IS DISTINCT FROM p_target_person_id
       OR a.establishment_basis_kind<>'original_subject_direct_assignment_v1'
       OR a.establishment_basis->>'sourceActionId'<>p_action_id::text)
 ) THEN RAISE EXCEPTION 'Another live responsibility or decision exists; use governed transfer.'
    USING ERRCODE='23514'; END IF;
 SELECT * INTO v_allocation FROM atlas.work_allocations a
 WHERE a.organization_id=p_organization_id AND a.work_item_id=v_work.id
   AND a.state='active' AND a.allocation_role='responsible'
   AND a.establishment_basis_kind='original_subject_direct_assignment_v1';
 IF v_allocation.id IS NOT NULL THEN
   SELECT * INTO v_plan FROM atlas.work_execution_plans p
   WHERE p.organization_id=p_organization_id AND p.work_item_id=v_work.id
     AND p.responsible_allocation_id=v_allocation.id AND p.plan_state='active'
   ORDER BY p.created_at LIMIT 1;
   IF v_allocation.assignee_canonical_person_id IS DISTINCT FROM p_target_person_id
       OR v_allocation.establishment_basis->>'sourceActionId' IS DISTINCT FROM p_action_id::text
       OR v_plan.id IS NULL OR v_plan.planned_service_date IS DISTINCT FROM p_service_date
       OR v_allocation.establishment_basis->>'decisionReason' IS DISTINCT FROM v_reason THEN
      RAISE EXCEPTION 'Exact original direct assignment retry differs from stored decision.'
        USING ERRCODE='23505';
   END IF;
 ELSE
   v_window:=atlas.company_work_execution_plan_window_check_v1(
     p_work_item_id,p_service_date);
   IF NOT coalesce((v_window->>'allowed')::boolean,false) THEN
     RAISE EXCEPTION 'Original Work may not be scheduled on requested day.'
       USING ERRCODE='23514';
   END IF;
   INSERT INTO atlas.work_allocations(
     organization_id,work_item_id,assignee_membership_id,
     assignee_canonical_person_id,assigned_by_membership_id,
     allocation_role,state,allocated_at,establishment_basis_kind,
     establishment_basis,metadata
   ) VALUES(
     p_organization_id,p_work_item_id,NULL,p_target_person_id,NULL,
     'responsible','active',now(),'original_subject_direct_assignment_v1',
     jsonb_build_object(
       'contractVersion','exact_work_responsibility_establishment_v2',
       'basisKind','original_subject_direct_assignment_v1',
       'organizationId',p_organization_id,'nativeLedgerId',p_ledger_id,
       'workItemId',p_work_item_id,'decompositionId',v_group.id,
       'assigneePersonId',p_target_person_id,'senderPersonId',v_owner,
       'sourceActionId',p_action_id,'decisionReason',v_reason,
       'authorizationBasis','governor_exact_existing_original_work'),
     jsonb_build_object('source','original_subject_direct_assignment_v1',
       'sameOriginalCanonicalWork',true,'newTaskCreated',false,
       'employeeSeatRequired',false,'workerAttestedAsSelf',false)
   ) RETURNING * INTO v_allocation;
   INSERT INTO atlas.work_execution_plans(
     organization_id,work_item_id,responsible_allocation_id,
     assignee_membership_id,planned_by_membership_id,plan_state,
     first_planned_service_date,planned_service_date,exposure_service_date,
     plan_reason,metadata
   ) VALUES(
     p_organization_id,p_work_item_id,v_allocation.id,NULL,NULL,'active',
     p_service_date,p_service_date,p_service_date,v_reason,
     jsonb_build_object('source','original_subject_direct_assignment_v1',
       'senderPersonId',v_owner,'originalDecompositionId',v_group.id,
       'workerAttestedAsSelf',false)
   ) RETURNING * INTO v_plan;
   INSERT INTO atlas.work_execution_plan_events(
     organization_id,work_item_id,plan_id,event_kind,
     to_planned_service_date,to_exposure_service_date,reason,metadata
   ) VALUES(
     p_organization_id,p_work_item_id,v_plan.id,'planned',
     p_service_date,p_service_date,v_reason,
     jsonb_build_object('source','original_subject_direct_assignment_v1',
       'governorPersonId',v_owner,'sourceActionId',p_action_id)
   );
   v_created:=true;
 END IF;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','original_subject_work_direct_responsibility_v1',
   'organizationId',p_organization_id,'ledgerId',p_ledger_id,
   'workItemId',v_work.id,'subjectDecompositionId',v_group.id,
   'targetPersonId',p_target_person_id,'allocationId',v_allocation.id,
   'planId',v_plan.id,'plannedServiceDate',v_plan.planned_service_date,
   'newWorkCreated',false,'newTaskCreated',false,
   'acceptanceQuestionCreated',false,
   'workerAttestedAsSelf',false,'employeeSeatRequired',false,
   'assignmentNew',v_created,'idempotent',NOT v_created);
END;
$function$;
REVOKE ALL ON FUNCTION atlas.owner_direct_assign_existing_original_work_self_api_v1(
 uuid,uuid,uuid,uuid,date,uuid,text) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.owner_direct_assign_existing_original_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_target_person_id uuid,p_service_date date,p_action_id uuid,p_reason text
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.owner_direct_assign_existing_original_work_self_api_v1(
 p_organization_id,p_ledger_id,p_work_item_id,p_target_person_id,
 p_service_date,p_action_id,p_reason);
$function$;
REVOKE ALL ON FUNCTION public.owner_direct_assign_existing_original_work_self_api_v1(
 uuid,uuid,uuid,uuid,date,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.owner_direct_assign_existing_original_work_self_api_v1(
 uuid,uuid,uuid,uuid,date,uuid,text) TO authenticated;

COMMIT;
