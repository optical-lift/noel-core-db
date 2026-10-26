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

-- Confirmed old farm-atlas deployed route calls farm_care_object_v1; held owner-only source narrowing.
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
  if not atlas.is_farm_owner(p_farm_id) then
    raise exception 'Resource not found.' using errcode='P0002';
  end if;

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

-- Confirmed old farm-atlas deployed route calls farm_care_summary_v1; held owner-only source narrowing.
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
  if not atlas.is_farm_owner(p_farm_id) then
    raise exception 'Resource not found.' using errcode='P0002';
  end if;

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

-- Confirmed old farm-atlas deployed route calls grow_room_state_v1; held owner-only source narrowing.
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
  if p_farm_id is null or not atlas.is_farm_owner(p_farm_id) then
    raise exception 'Resource not found.' using errcode='P0002';
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

-- Confirmed old farm-atlas deployed route calls object_workbench_v1; held owner-only source narrowing.
CREATE OR REPLACE FUNCTION atlas.object_workbench_v1(p_farm_id uuid, p_object_key text, p_history_days integer DEFAULT 14, p_future_days integer DEFAULT 365)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_role text;
  v_farm_key text;
  v_object atlas.v_object_workbench%rowtype;
  v_result jsonb;
begin
  v_role := atlas.current_farm_role(p_farm_id);
  if not atlas.is_farm_owner(p_farm_id) then
    raise exception 'Resource not found.' using errcode='P0002';
  end if;

  select f.stable_key into v_farm_key
  from atlas.farms f
  where f.id = p_farm_id;

  if v_farm_key is null then
    raise exception 'Farm was not found.' using errcode = 'P0002';
  end if;

  select workbench.* into v_object
  from atlas.v_object_workbench workbench
  where workbench.farm_id = p_farm_id
    and workbench.object_key = nullif(btrim(p_object_key), '');

  if v_object.object_id is null then
    raise exception 'Farm object was not found.' using errcode = 'P0002';
  end if;

  select jsonb_build_object(
    'object', to_jsonb(v_object),
    'cropCycles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', cc.id,
        'crop_cycle_key', cc.crop_cycle_key,
        'crop_label', cc.crop_label,
        'variety', cc.variety,
        'cycle_state', cc.cycle_state,
        'lifecycle_status', cc.lifecycle_status,
        'sown_date', cc.sown_date,
        'planted_date', cc.planted_date,
        'germination_checked_date', cc.germination_checked_date,
        'harvest_started_date', cc.harvest_started_date,
        'last_harvest_date', cc.last_harvest_date,
        'expected_germination_start', cc.expected_germination_start,
        'expected_germination_end', cc.expected_germination_end,
        'expected_harvest_watch_start', cc.expected_harvest_watch_start,
        'expected_harvest_watch_end', cc.expected_harvest_watch_end,
        'expected_clear_date', cc.expected_clear_date,
        'note', cc.note
      ) order by cc.created_at)
      from atlas.crop_cycles cc
      where cc.farm_id = p_farm_id
        and cc.object_id = v_object.object_id
        and cc.lifecycle_status = 'active'
    ), '[]'::jsonb),
    'plantInstances', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pi.id,
        'lineage_id', pi.lineage_id,
        'stable_key', pi.stable_key,
        'label', pi.label,
        'quantity', pi.quantity,
        'unit', pi.unit,
        'generation', pi.generation,
        'status', pi.status,
        'acquired_date', pi.acquired_date,
        'planted_date', pi.planted_date,
        'note', pi.note,
        'lineage', case when pl.id is null then null else jsonb_build_object(
          'id', pl.id,
          'stable_key', pl.stable_key,
          'lineage_name', pl.lineage_name,
          'common_name', pl.common_name,
          'botanical_name', pl.botanical_name,
          'source_name', pl.source_name,
          'source_type', pl.source_type,
          'origin_year', pl.origin_year,
          'origin_detail', pl.origin_detail,
          'propagation_goal', pl.propagation_goal
        ) end
      ) order by pi.created_at)
      from atlas.plant_instances pi
      left join atlas.plant_lineages pl on pl.id = pi.lineage_id
      where pi.farm_id = p_farm_id
        and pi.object_id = v_object.object_id
        and pi.status not in ('dead', 'removed', 'archived')
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
        'event_id', timeline.event_id,
        'object_id', timeline.object_id,
        'object_key', timeline.object_key,
        'object_label', timeline.object_label,
        'field_log_id', timeline.field_log_id,
        'crop_cycle_id', timeline.crop_cycle_id,
        'plant_instance_id', timeline.plant_instance_id,
        'entity_label', timeline.entity_label,
        'entity_kind', timeline.entity_kind,
        'event_type', timeline.event_type,
        'event_date', timeline.event_date,
        'note', timeline.note,
        'quantity', timeline.quantity,
        'unit', timeline.unit,
        'source', timeline.source,
        'created_at', timeline.created_at
      ) order by timeline.event_date desc, timeline.created_at desc)
      from (
        select *
        from atlas.v_object_event_timeline event_row
        where event_row.farm_id = p_farm_id
          and event_row.object_id = v_object.object_id
        order by event_row.event_date desc, event_row.created_at desc
        limit 40
      ) timeline
    ), '[]'::jsonb),
    'operationalTimeline', atlas.get_object_operational_timeline_v1(
      v_farm_key,
      v_object.object_key,
      greatest(coalesce(p_history_days, 14), 0),
      greatest(coalesce(p_future_days, 365), 0)
    )
  ) into v_result;

  return v_result;
end;
$function$;

-- Deny direct browser-role invocation; indirect definer calls are independently
-- constrained by the replacement function bodies above.
REVOKE EXECUTE ON FUNCTION atlas.zone_registry_source_v1(uuid) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION atlas.object_crop_bed_map_v1(uuid) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION atlas.farm_care_zone_v1(uuid,text,integer) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION atlas.farm_snapshot_for_member_v1(uuid) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION atlas.farm_care_object_v1(uuid,text,integer) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION atlas.farm_care_summary_v1(uuid,integer) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION atlas.grow_room_state_v1(uuid) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION atlas.object_workbench_v1(uuid,text,integer,integer) FROM PUBLIC,anon,authenticated;
-- universal_home_v1 currently remains SQL EXECUTABLE for signed legacy home
-- compatibility, but farm-wide content is omitted for non-owner farm memberships.
-- DO NOT misread that as full source/field isolation.
COMMIT;
