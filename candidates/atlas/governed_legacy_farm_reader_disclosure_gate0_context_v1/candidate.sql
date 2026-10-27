BEGIN;
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
COMMIT;
