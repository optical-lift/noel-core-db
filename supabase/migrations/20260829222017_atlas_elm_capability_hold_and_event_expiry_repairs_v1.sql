do $block$
declare
  v_farm_id uuid;
  v_marshall_id uuid;
  v_marshall_user_id uuid;
  v_repair_task_id uuid;
  v_result jsonb;
begin
  select f.id into v_farm_id from atlas.farms f where f.stable_key='elm_farm';
  if v_farm_id is null then raise exception 'Elm Farm not found.'; end if;

  select fm.id,fm.user_id into v_marshall_id,v_marshall_user_id
  from atlas.farm_memberships fm
  where fm.farm_id=v_farm_id and fm.active=true and fm.worker_key='marshall'
  limit 1;
  if v_marshall_id is null then raise exception 'Marshall membership not found.'; end if;

  select t.id into v_repair_task_id
  from atlas.tasks t
  where t.farm_id=v_farm_id
    and t.metadata->>'task_key'='marshall_20260804_repair_curve3_and_small_fm_beds'
  order by t.created_at desc
  limit 1;
  if v_repair_task_id is null then raise exception 'Raised-bed repair task not found.'; end if;

  update atlas.tasks t
  set assigned_membership_id=v_marshall_id,
      assigned_user_id=v_marshall_user_id,
      metadata=(coalesce(t.metadata,'{}'::jsonb)
        - 'execution_date'
        - 'calendar_rollover'
        - 'calendar_rollover_at'
        - 'calendar_rollover_from'
        - 'calendar_rollover_to')
        || jsonb_build_object(
          'anna_task',false,
          'owner_task',false,
          'marshall_task',true,
          'assigned_to','Marshall',
          'assignee_key','marshall',
          'executor_role','manager',
          'executor_label','Marshall',
          'executor_worker_key','marshall',
          'executor_membership_id',v_marshall_id,
          'assignment_changed_at',now(),
          'assignment_changed_source','owner_instruction_20260829',
          'owner_problem_handoff_open',false,
          'owner_problem_handoff_closed_at',now(),
          'owner_problem_handoff_resolution','Reassigned to Marshall and held outside Worker Day until Marshall, cutting capability, and repair wood are available at Elm.',
          'external_readiness_required',true,
          'external_readiness_state','waiting',
          'external_readiness_key','raised_bed_repair_marshall_cutting_materials_ready',
          'external_readiness_label','Marshall + cutting capability + repair wood available at Elm',
          'capability_hold',true,
          'capability_hold_state','waiting'
        ),
      blocker_text='Waiting for Marshall to be at Elm with cutting capability and the repair wood/materials available.',
      updated_at=now()
  where t.id=v_repair_task_id;

  v_result:=atlas.set_task_capability_hold_internal_v1(
    v_repair_task_id,
    'waiting',
    array['person','capability','tool','material','travel','location'],
    'Waiting for Marshall to be at Elm with cutting capability and the repair wood/materials available.',
    'Do not place this task on Marshall or Anna''s Worker Day until the capability gate is explicitly released.',
    'owner_instruction_20260829'
  );

  perform atlas.reconcile_expired_event_bound_tasks_v1(v_farm_id,date '2026-08-29');
end;
$block$;