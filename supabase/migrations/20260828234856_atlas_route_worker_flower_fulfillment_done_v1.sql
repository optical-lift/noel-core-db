create or replace function atlas.worker_record_task_transition_v1(
  p_task_id uuid,
  p_transition text,
  p_idempotency_key text,
  p_note text default null::text,
  p_reason text default null::text,
  p_payload jsonb default '{}'::jsonb,
  p_target_date date default null::date,
  p_lane_key text default null::text,
  p_work_key text default null::text,
  p_existing_field_log_id uuid default null::uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_farm_id uuid;
  v_visibility_scope text;
  v_assigned_membership_id uuid;
  v_task_type text;
  v_current_membership_id uuid;
  v_role text;
  v_payload jsonb;
  v_readiness jsonb;
  v_transition_card jsonb;
  v_timezone text := 'America/Chicago';
  v_service_date date;
begin
  select t.farm_id,t.visibility_scope,t.assigned_membership_id,t.task_type
  into v_farm_id,v_visibility_scope,v_assigned_membership_id,v_task_type
  from atlas.tasks t
  where t.id=p_task_id;

  if v_farm_id is null then
    raise exception 'Task not found.' using errcode='P0002';
  end if;

  select coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
  into v_timezone
  from atlas.farms f
  where f.id=v_farm_id;

  v_service_date := (now() at time zone coalesce(v_timezone,'America/Chicago'))::date;

  v_role := atlas.current_farm_role(v_farm_id);
  v_current_membership_id := atlas.current_membership_id(v_farm_id);

  if v_role not in ('farm_hand','manager')
    or v_current_membership_id is null
    or v_visibility_scope <> 'assigned_worker'
    or v_assigned_membership_id <> v_current_membership_id
  then
    raise exception 'This task is not assigned to the signed-in farm member.' using errcode='42501';
  end if;

  if p_transition not in (
    'done','partial','blocked','not_relevant','changed_plan',
    'rescheduled','unfinished','checklist_done','checklist_open','note'
  ) then
    raise exception 'Unsupported assigned-worker transition.' using errcode='22023';
  end if;

  if v_role='farm_hand' and p_transition in ('rescheduled','changed_plan','not_relevant') then
    raise exception 'Farm hands cannot move, reschedule, or close assigned work as a plan change.' using errcode='42501';
  end if;

  if p_transition in ('rescheduled','unfinished') and p_target_date is null then
    raise exception 'A target date is required for this transition.' using errcode='22023';
  end if;

  if p_transition='done'
     and coalesce(p_payload->>'structuredResultKind','')='flower_preparation_directive_final_tally_v1' then
    return atlas.record_flower_preparation_directive_result_for_member_v2(
      p_task_id,
      coalesce(p_payload->'lines','[]'::jsonb),
      coalesce(p_payload->'workerAddedLines','[]'::jsonb),
      coalesce(p_payload->'remainingStems','[]'::jsonb),
      p_idempotency_key
    );
  end if;

  -- Flower fulfillment is not an ordinary Done transition. The actual handoff is
  -- canonical domain truth and must be recorded atomically with task completion.
  -- It intentionally bypasses Worker Day placement authorization because the
  -- fulfillment core independently validates farm membership, assignment, sale
  -- state, cancellation state, and duplicate fulfillment.
  if p_transition='done' and v_task_type='flower_fulfillment' then
    return atlas.record_flower_fulfillment_core_v1(
      p_task_id,
      v_current_membership_id,
      v_role,
      p_note,
      p_idempotency_key,
      false
    );
  end if;

  if p_transition='done' then
    v_readiness := atlas.task_execution_readiness_v1(p_task_id);
    v_transition_card := atlas.worker_state_transition_card_v2(
      v_farm_id,
      v_current_membership_id,
      p_task_id,
      v_service_date
    );

    if not coalesce((v_readiness->>'ready')::boolean,false)
       or coalesce(v_transition_card#>>'{transition,state}','') <> 'authorized_for_routed_day'
    then
      raise exception 'This work is not executable in current farm reality.' using errcode='23514';
    end if;
  end if;

  v_payload := coalesce(p_payload,'{}'::jsonb) || jsonb_build_object(
    'actor_user_id',auth.uid(),
    'actor_membership_id',v_current_membership_id,
    'actor_role',v_role
  );

  return atlas.record_task_transition_v1(
    p_task_id,
    p_transition,
    p_idempotency_key,
    p_target_date,
    p_note,
    p_reason,
    p_lane_key,
    p_work_key,
    v_payload,
    p_existing_field_log_id
  );
end;
$function$;