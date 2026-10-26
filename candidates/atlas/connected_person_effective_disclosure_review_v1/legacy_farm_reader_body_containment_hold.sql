-- HOLD / REVIEW ONLY: transitional farm-wide read containment for Noel #2255.
-- Not production-ready. The existing farm_owner role is legacy source authority,
-- NOT exact native-Ledger/field-level grants. No complete nondisclosure claim.
-- This must not release without full direct + indirect read-path replacement,
-- worker-safe notebook parity and genuine signed negative/positive tests.
-- Snapshots, old home totals and old farm-member readers are coupled.
-- Preserve all original SQL outputs for continued authorized owner calls.
BEGIN;

-- Existing farm_care_zone_v1: guard narrowed; original projection body retained.
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
  if not atlas.is_farm_owner(p_farm_id) then
    raise exception 'Resource not found.' using errcode='P0002';
  end if;

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

-- Existing farm_snapshot_for_member_v1: guard narrowed; original projection body retained.
CREATE OR REPLACE FUNCTION atlas.farm_snapshot_for_member_v1(p_farm_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_year_start date := date_trunc('year', current_date)::date;
  v_total_beds integer := 0;
  v_growing_beds integer := 0;
  v_active_sqft numeric := 0;
  v_sowing_events integer := 0;
  v_sowing_logs integer := 0;
  v_stems_logged numeric := 0;
begin
  if v_user_id is null then
    raise exception 'Authenticated user required.' using errcode = '42501';
  end if;

  if not atlas.is_farm_owner(p_farm_id) then
    raise exception 'Resource not found.' using errcode='P0002';
  end if;

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

-- Existing object_crop_bed_map_v1: guard narrowed; original projection body retained.
CREATE OR REPLACE FUNCTION atlas.object_crop_bed_map_v1(p_object_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
DECLARE
  v_object atlas.growing_objects%rowtype;
  v_frame atlas.object_map_frames%rowtype;
  v_role text;
  v_rows jsonb;
  v_geometry jsonb;
BEGIN
  SELECT * INTO v_object FROM atlas.growing_objects WHERE id = p_object_id;
  IF v_object.id IS NULL OR NOT atlas.is_farm_owner(v_object.farm_id) THEN
    RAISE EXCEPTION 'Resource not found.' USING errcode = 'P0002';
  END IF;

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

-- Existing universal_home_v1: guard narrowed; original projection body retained.
CREATE OR REPLACE FUNCTION atlas.universal_home_v1(p_organization_id uuid DEFAULT NULL::uuid, p_preferred_farm_id uuid DEFAULT NULL::uuid, p_due_through date DEFAULT (CURRENT_DATE + 35), p_done_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_organization_id uuid;
  v_organization_role text;
  v_organization_home jsonb := null;
  v_project_tasks jsonb := '[]'::jsonb;
  v_active_farm_id uuid;
  v_farms jsonb := '[]'::jsonb;
  v_farm record;
  v_snapshot jsonb;
  v_task_cards jsonb;
  v_open_count integer;
  v_blocked_count integer;
  v_overdue_count integer;
  v_due_today_count integer;
  v_last_movement_at timestamptz;
begin
  if v_user_id is null then
    raise exception 'Authenticated user required.' using errcode = '42501';
  end if;

  if p_due_through < p_done_date then
    raise exception 'The universal home window cannot end before its done date.' using errcode = '22023';
  end if;

  select om.organization_id, om.role
  into v_organization_id, v_organization_role
  from atlas.organization_memberships om
  where om.user_id = v_user_id
    and om.active = true
    and (p_organization_id is null or om.organization_id = p_organization_id)
  order by
    case when om.organization_id = p_organization_id then 0 else 1 end,
    case when om.role = 'owner' then 0 when om.role = 'consultant' then 1 else 2 end,
    om.created_at
  limit 1;

  if v_organization_id is not null then
    v_organization_home := atlas.portfolio_home_v1(v_organization_id);

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'taskId', visible.task_id,
          'projectId', visible.project_id,
          'projectKey', visible.project_key,
          'projectTitle', visible.project_title,
          'farmId', visible.farm_id,
          'farmKey', visible.farm_key,
          'farmName', visible.farm_name,
          'workstream', visible.workstream,
          'title', visible.task_title,
          'status', visible.task_status,
          'priority', visible.priority,
          'dueDate', visible.due_date,
          'note', visible.note,
          'blockerText', visible.blocker_text,
          'assignedToViewer', visible.assigned_user_id = v_user_id,
          'createdByViewer', visible.created_by_user_id = v_user_id,
          'originKind', visible.origin_kind,
          'createdAt', visible.created_at,
          'updatedAt', visible.updated_at,
          'completedAt', visible.completed_at
        )
        order by
          case visible.task_status when 'blocked' then 0 when 'open' then 1 else 2 end,
          visible.due_date nulls last,
          visible.sort_order,
          visible.created_at
      ),
      '[]'::jsonb
    )
    into v_project_tasks
    from (
      select
        t.id as task_id,
        p.id as project_id,
        p.stable_key as project_key,
        p.title as project_title,
        p.farm_id,
        f.stable_key as farm_key,
        f.name as farm_name,
        p.workstream,
        t.title as task_title,
        t.status as task_status,
        t.priority,
        t.due_date,
        t.note,
        t.blocker_text,
        t.assigned_user_id,
        t.created_by_user_id,
        t.origin_kind,
        t.created_at,
        t.updated_at,
        t.completed_at,
        ptl.sort_order
      from atlas.projects p
      join atlas.project_task_links ptl on ptl.project_id = p.id
      join atlas.tasks t on t.id = ptl.task_id
      left join atlas.farms f on f.id = p.farm_id
      where p.organization_id = v_organization_id
        and p.status <> 'archived'
        and atlas.can_read_project(p.id)
        and t.task_scope = 'project'
        and lower(coalesce(t.metadata ->> 'project_tracking_only', 'false')) <> 'true'
        and atlas.project_task_visible_on_day_v1(
          t.status, t.due_date, t.completed_at, t.updated_at, t.metadata, p_done_date
        )
    ) visible;
  end if;

  select fm.farm_id
  into v_active_farm_id
  from atlas.farm_memberships fm
  join atlas.farms f on f.id = fm.farm_id
  where fm.user_id = v_user_id
    and fm.active = true
    and fm.role = 'owner'
    and f.status = 'active'
  order by
    case when fm.farm_id = p_preferred_farm_id then 0 else 1 end,
    case when fm.role = 'owner' then 0 when fm.role = 'manager' then 1 else 2 end,
    f.name,
    fm.created_at
  limit 1;

  for v_farm in
    select
      fm.id as membership_id,
      fm.farm_id,
      fm.role,
      fm.worker_key,
      fm.permissions,
      f.stable_key as farm_key,
      f.name as farm_name,
      f.status as farm_status,
      f.organization_id
    from atlas.farm_memberships fm
    join atlas.farms f on f.id = fm.farm_id
    where fm.user_id = v_user_id
      and fm.active = true
      and fm.role = 'owner'
      and f.status = 'active'
    order by
      case when fm.farm_id = v_active_farm_id then 0 else 1 end,
      case when fm.role = 'owner' then 0 when fm.role = 'manager' then 1 else 2 end,
      f.name,
      fm.created_at
  loop
    v_snapshot := atlas.farm_snapshot_for_member_v1(v_farm.farm_id);
    v_task_cards := '[]'::jsonb;

    if nullif(btrim(coalesce(v_farm.worker_key, '')), '') is not null then
      select coalesce(
        jsonb_agg(to_jsonb(card) order by card.due_date nulls last, card.created_at, card.task_id),
        '[]'::jsonb
      )
      into v_task_cards
      from atlas.home_task_cards_v2(
        v_farm.farm_id,
        v_farm.worker_key,
        p_due_through,
        p_done_date
      ) card;
    end if;

    if v_farm.role in ('owner', 'manager') then
      select
        count(*) filter (where t.status in ('open', 'blocked'))::integer,
        count(*) filter (where t.status = 'blocked')::integer,
        count(*) filter (
          where t.status = 'open'
            and t.due_date is not null
            and t.due_date < p_done_date
        )::integer,
        count(*) filter (
          where t.status in ('open', 'blocked')
            and t.due_date = p_done_date
        )::integer
      into v_open_count, v_blocked_count, v_overdue_count, v_due_today_count
      from atlas.tasks t
      where t.farm_id = v_farm.farm_id
        and t.task_scope = 'farm_operation'
        and t.status <> 'archived';
    else
      select
        count(*) filter (where (item ->> 'status') in ('open', 'blocked'))::integer,
        count(*) filter (where (item ->> 'status') = 'blocked')::integer,
        count(*) filter (
          where (item ->> 'status') = 'open'
            and nullif(item ->> 'due_date', '') is not null
            and (item ->> 'due_date')::date < p_done_date
        )::integer,
        count(*) filter (
          where (item ->> 'status') in ('open', 'blocked')
            and nullif(item ->> 'due_date', '') is not null
            and (item ->> 'due_date')::date = p_done_date
        )::integer
      into v_open_count, v_blocked_count, v_overdue_count, v_due_today_count
      from jsonb_array_elements(v_task_cards) item;
    end if;

    select greatest(
      (select max(t.updated_at) from atlas.tasks t where t.farm_id = v_farm.farm_id),
      (select max(fl.updated_at) from atlas.field_logs fl where fl.farm_id = v_farm.farm_id),
      (select max(oae.created_at) from atlas.object_activity_events oae where oae.farm_id = v_farm.farm_id)
    )
    into v_last_movement_at;

    v_farms := v_farms || jsonb_build_array(jsonb_build_object(
      'membershipId', v_farm.membership_id,
      'farmId', v_farm.farm_id,
      'farmKey', v_farm.farm_key,
      'farmName', v_farm.farm_name,
      'farmStatus', v_farm.farm_status,
      'organizationId', v_farm.organization_id,
      'role', v_farm.role,
      'workerKey', v_farm.worker_key,
      'permissions', coalesce(v_farm.permissions, '{}'::jsonb),
      'canManageFarm', v_farm.role in ('owner', 'manager'),
      'canUseOwnerTools', v_farm.role = 'owner',
      'snapshot', coalesce(v_snapshot, '{}'::jsonb),
      'taskCards', v_task_cards,
      'openTaskCount', coalesce(v_open_count, 0),
      'blockedTaskCount', coalesce(v_blocked_count, 0),
      'overdueTaskCount', coalesce(v_overdue_count, 0),
      'dueTodayCount', coalesce(v_due_today_count, 0),
      'lastMovementAt', v_last_movement_at
    ));
  end loop;

  if v_organization_id is null and jsonb_array_length(v_farms) = 0 then
    raise exception 'An active Atlas farm or organization membership is required.' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'viewer', jsonb_build_object(
      'userId', v_user_id,
      'organizationId', v_organization_id,
      'organizationRole', v_organization_role,
      'activeFarmId', v_active_farm_id,
      'hasOrganizationScope', v_organization_id is not null,
      'hasFarmScope', jsonb_array_length(v_farms) > 0
    ),
    'organizationHome', v_organization_home,
    'projectTasks', v_project_tasks,
    'farms', v_farms,
    'window', jsonb_build_object(
      'doneDate', p_done_date,
      'dueThrough', p_due_through
    )
  );
end;
$function$;

-- Existing zone_registry_source_v1: guard narrowed; original projection body retained.
CREATE OR REPLACE FUNCTION atlas.zone_registry_source_v1(p_farm_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Authenticated user required.' using errcode = '42501';
  end if;

  if not atlas.is_farm_owner(p_farm_id) then
    raise exception 'Resource not found.' using errcode='P0002';
  end if;

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

-- Deny direct browser-role invocation; indirect definer calls are independently
-- constrained by the replacement function bodies above.
REVOKE EXECUTE ON FUNCTION atlas.zone_registry_source_v1(uuid) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION atlas.object_crop_bed_map_v1(uuid) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION atlas.farm_care_zone_v1(uuid,text,integer) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION atlas.farm_snapshot_for_member_v1(uuid) FROM PUBLIC,anon,authenticated;
-- universal_home_v1 currently remains SQL EXECUTABLE for signed legacy home
-- compatibility, but farm-wide content is omitted for non-owner farm memberships.
-- DO NOT misread that as full source/field isolation.
COMMIT;
