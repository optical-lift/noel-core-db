-- HELD P3 candidate: EXACT live function snapshot at 2026-11-06.
-- Read-only production pg_get_functiondef MD5: 774ad5c6728a615ada5bf4ea823c5498.
-- Only 1 original source expression is replaced with a Result-only branch.
-- Not a generated migration; not approved for installation. No new grants.
-- Run accepted source-owner compatibility checks before migration.

CREATE OR REPLACE FUNCTION atlas.evaluate_rhythm_binding_v1(p_state_id uuid, p_as_of timestamp with time zone DEFAULT now(), p_trigger_kind text DEFAULT 'clock'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_state atlas.rhythm_state%rowtype;
  v_binding atlas.rhythm_bindings%rowtype;
  v_rule atlas.rhythm_rules%rowtype;
  v_satisfaction atlas.rhythm_satisfactions%rowtype;
  v_effective_rule jsonb;
  v_current_state text;
  v_next_state text;
  v_transition_kind text;
  v_boundary_kind text;
  v_boundary_at timestamptz;
  v_transition_key text;
  v_transition_id uuid;
  v_transition_ids jsonb := '[]'::jsonb;
  v_task_result jsonb := '{}'::jsonb;
  v_task_id uuid;
  v_occurrence_id uuid;
  v_timezone text := 'America/Chicago';
  v_boundary_mode text := 'exact_timestamp';
  v_lease_seconds integer;
  v_rule_changed boolean := false;
  v_visibility text;
  v_assigned_user_id uuid;
  v_as_of timestamptz := coalesce(p_as_of, now());
  v_changed_count integer := 0;
  v_loop_guard integer := 0;
begin
  select * into v_state from atlas.rhythm_state where id = p_state_id for update;
  if v_state.id is null then
    raise exception 'Rhythm state not found.' using errcode = 'P0002';
  end if;

  -- Resolve the winner on every evaluation so new overrides, stage changes,
  -- temporary exceptions, and binding deactivations take effect without reenrollment.
  v_effective_rule := atlas.resolve_effective_rhythm_rule_for_clock_v2(v_state.id, v_as_of);
  if v_effective_rule is not null and jsonb_typeof(v_effective_rule) <> 'null' then
    select * into v_binding
    from atlas.rhythm_bindings
    where id = (v_effective_rule ->> 'bindingId')::uuid;

    select * into v_rule
    from atlas.rhythm_rules
    where id = (v_effective_rule ->> 'ruleId')::uuid;
  end if;

  v_current_state := v_state.state;

  if v_binding.id is null or not v_binding.active or v_rule.id is null
     or v_rule.status in ('paused','retired')
     or (v_binding.active_from is not null and v_binding.active_from > v_as_of)
     or (v_binding.active_until is not null and v_binding.active_until <= v_as_of) then
    if v_current_state <> 'paused' then
      v_boundary_at := v_as_of;
      v_transition_key := 'clock:' || v_state.id::text || ':paused:' || extract(epoch from v_boundary_at)::bigint::text;
      v_transition_id := atlas.record_rhythm_transition_v1(
        v_state.id, v_transition_key, 'paused', v_current_state, 'paused', 'pause',
        v_boundary_at, v_as_of, v_state.last_qualifying_satisfaction_id,
        v_state.current_task_id, v_state.current_occurrence_id,
        jsonb_build_object('triggerKind', coalesce(p_trigger_kind, 'clock'))
      );
      v_transition_ids := v_transition_ids || jsonb_build_array(v_transition_id);
      v_changed_count := v_changed_count + 1;
      v_current_state := 'paused';
    end if;

    update atlas.rhythm_state
    set state = 'paused',
        last_evaluated_at = v_as_of,
        last_transition_at = case when v_changed_count > 0 then v_boundary_at else last_transition_at end,
        state_reason = jsonb_build_object('transitionKind', 'paused', 'triggerKind', coalesce(p_trigger_kind, 'clock')),
        updated_at = now()
    where id = v_state.id;

    return jsonb_build_object(
      'contractVersion', 'rhythm_evaluation_v1',
      'stateId', v_state.id,
      'changed', v_changed_count > 0,
      'transitionCount', v_changed_count,
      'transitions', v_transition_ids,
      'state', 'paused',
      'asOf', v_as_of
    );
  end if;

  if v_state.rhythm_binding_id <> v_binding.id or v_state.rhythm_rule_id <> v_rule.id or v_state.effective_rule_version <> v_rule.version then
    v_rule_changed := true;
    v_visibility := coalesce(nullif(v_rule.player_routing ->> 'visibilityScope', ''), v_state.visibility_scope, 'farm_shared');
    if v_visibility not in ('owner','management','assigned_worker','farm_shared','project_shared','system_internal') then
      v_visibility := 'farm_shared';
    end if;
    if nullif(v_rule.player_routing ->> 'assignedUserId', '') is not null then
      v_assigned_user_id := (v_rule.player_routing ->> 'assignedUserId')::uuid;
    else
      v_assigned_user_id := v_state.assigned_user_id;
    end if;

    update atlas.rhythm_state
    set rhythm_binding_id = v_binding.id,
        rhythm_rule_id = v_rule.id,
        rhythm_key = v_rule.rhythm_key,
        effective_rule_version = v_rule.version,
        visibility_scope = v_visibility,
        assigned_user_id = v_assigned_user_id,
        updated_at = now()
    where id = v_state.id;

    v_state.rhythm_binding_id := v_binding.id;
    v_state.rhythm_rule_id := v_rule.id;
    v_state.rhythm_key := v_rule.rhythm_key;
    v_state.effective_rule_version := v_rule.version;
    v_state.visibility_scope := v_visibility;
    v_state.assigned_user_id := v_assigned_user_id;
  end if;

  if v_state.last_qualifying_satisfaction_id is not null then
    select * into v_satisfaction
    from atlas.rhythm_satisfactions
    where id = v_state.last_qualifying_satisfaction_id;
  end if;

  if v_satisfaction.id is not null then
    v_timezone := coalesce(nullif(v_rule.metadata ->> 'timezoneName', ''), 'America/Chicago');
    v_boundary_mode := coalesce(nullif(v_rule.metadata ->> 'boundaryMode', ''), 'exact_timestamp');
    v_lease_seconds := coalesce(v_satisfaction.renewal_interval_seconds, v_rule.validity_interval_seconds);
    v_state.warning_at := atlas.rhythm_boundary_at_v1(
      v_satisfaction.satisfied_at,
      greatest(0, v_lease_seconds - v_rule.warning_window_seconds),
      v_timezone,
      v_boundary_mode
    );
    v_state.due_at := atlas.rhythm_boundary_at_v1(
      v_satisfaction.satisfied_at,
      v_lease_seconds,
      v_timezone,
      v_boundary_mode
    );
    v_state.failure_at := atlas.rhythm_boundary_at_v1(
      v_satisfaction.satisfied_at,
      v_lease_seconds + v_rule.grace_window_seconds,
      v_timezone,
      v_boundary_mode
    );
  else
    v_state.warning_at := null;
    v_state.due_at := null;
    v_state.failure_at := null;
  end if;

  -- A rule version change is explicit history. Reset to the new rule's lease base,
  -- then advance each crossed boundary in order below.
  if v_rule_changed then
    v_next_state := case when v_satisfaction.id is null then 'uninitialized' else 'resting' end;
    v_boundary_at := greatest(v_binding.updated_at, v_rule.updated_at);
    v_transition_key := 'clock:' || v_state.id::text || ':rule_changed:' || extract(epoch from v_boundary_at)::bigint::text;
    v_transition_id := atlas.record_rhythm_transition_v1(
      v_state.id, v_transition_key, 'rule_changed', v_current_state, v_next_state, 'rule_change',
      v_boundary_at, v_as_of, v_satisfaction.id, v_state.current_task_id,
      v_state.current_occurrence_id,
      jsonb_build_object('triggerKind', coalesce(p_trigger_kind, 'clock'), 'ruleVersion', v_rule.version)
    );
    v_transition_ids := v_transition_ids || jsonb_build_array(v_transition_id);
    v_changed_count := v_changed_count + 1;
    v_current_state := v_next_state;
    v_state.lease_started_at := case when v_satisfaction.id is null then null else v_satisfaction.satisfied_at end;
  end if;

  -- A newly linked satisfaction restores or renews the lease before time advances.
  if v_satisfaction.id is not null
     and (v_state.lease_started_at is null or v_state.lease_started_at <> v_satisfaction.satisfied_at) then
    v_transition_kind := case
      when v_current_state = 'uninitialized' then 'initialized'
      when v_current_state in ('coming_due','due','fallen_out_of_rhythm','recovering') then 'restored'
      else 'renewed'
    end;
    v_boundary_at := v_satisfaction.satisfied_at;
    v_transition_key := 'clock:' || v_state.id::text || ':' || v_transition_kind || ':' || extract(epoch from v_boundary_at)::bigint::text;
    v_transition_id := atlas.record_rhythm_transition_v1(
      v_state.id, v_transition_key, v_transition_kind, v_current_state, 'resting', 'satisfaction',
      v_boundary_at, v_as_of, v_satisfaction.id, v_state.current_task_id,
      v_state.current_occurrence_id,
      jsonb_build_object('triggerKind', coalesce(p_trigger_kind, 'clock'), 'satisfactionId', v_satisfaction.id)
    );
    v_transition_ids := v_transition_ids || jsonb_build_array(v_transition_id);
    v_changed_count := v_changed_count + 1;
    v_current_state := 'resting';
    v_state.lease_started_at := v_satisfaction.satisfied_at;
    v_state.recovery_started_at := null;
  elsif v_current_state = 'paused' then
    v_next_state := case when v_satisfaction.id is null then 'uninitialized' else 'resting' end;
    v_boundary_at := v_as_of;
    v_transition_key := 'clock:' || v_state.id::text || ':reactivated:' || extract(epoch from v_boundary_at)::bigint::text;
    v_transition_id := atlas.record_rhythm_transition_v1(
      v_state.id, v_transition_key, 'reactivated', 'paused', v_next_state, 'reactivation',
      v_boundary_at, v_as_of, v_satisfaction.id, v_state.current_task_id,
      v_state.current_occurrence_id,
      jsonb_build_object('triggerKind', coalesce(p_trigger_kind, 'clock'))
    );
    v_transition_ids := v_transition_ids || jsonb_build_array(v_transition_id);
    v_changed_count := v_changed_count + 1;
    v_current_state := v_next_state;
  end if;

  if v_satisfaction.id is null then
    v_current_state := 'uninitialized';
  end if;

  -- Advance every crossed boundary once. A late or retried tick can emit warning,
  -- due, and failure in sequence without duplicating any of them.
  loop
    v_loop_guard := v_loop_guard + 1;
    exit when v_loop_guard > 8;

    v_next_state := null;
    v_transition_kind := null;
    v_boundary_kind := null;
    v_boundary_at := null;

    if v_current_state = 'recovering' then
      exit;
    elsif v_current_state = 'resting' then
      if v_rule.warning_window_seconds > 0 and v_as_of >= v_state.warning_at then
        v_next_state := 'coming_due';
        v_transition_kind := 'warning';
        v_boundary_kind := 'warning';
        v_boundary_at := v_state.warning_at;
      elsif v_as_of >= v_state.due_at then
        v_next_state := 'due';
        v_transition_kind := 'due';
        v_boundary_kind := 'due';
        v_boundary_at := v_state.due_at;
      end if;
    elsif v_current_state = 'coming_due' and v_as_of >= v_state.due_at then
      v_next_state := 'due';
      v_transition_kind := 'due';
      v_boundary_kind := 'due';
      v_boundary_at := v_state.due_at;
    elsif v_current_state = 'due' and v_as_of >= v_state.failure_at then
      v_next_state := 'fallen_out_of_rhythm';
      v_transition_kind := 'failed';
      v_boundary_kind := 'failure';
      v_boundary_at := v_state.failure_at;
    end if;

    exit when v_next_state is null;

    v_task_result := '{}'::jsonb;
    v_task_id := null;
    v_occurrence_id := null;
    if v_next_state in ('due','fallen_out_of_rhythm') then
      if coalesce(p_trigger_kind,'clock') in
         ('workflow_precheck','workflow_result',
          'game_master_precheck','game_master_satisfaction',
          'activation_prerequisite_completed')
      then
        -- 2026-11-04 decision 6A. A Result is allowed to QUALIFY existing
        -- state and next eligibility, but may not issue a legacy task, a
        -- new original Work, offer, schedule, campaign or Clock placement.
        -- The separately reviewed U1/U2 issuer owns future issuance.
        v_task_result := jsonb_build_object(
          'taskId',null,'occurrenceId',null,
          'action','qualified_evaluation_no_successor',
          'triggerKind',p_trigger_kind,
          'noNewWorkCreated',true);
      else
        -- Legacy non-Result clock path is intentionally unchanged in this
        -- isolated P3 draft. U2C owns its separate accepted-first cutover.
        v_task_result := atlas.ensure_rhythm_task_v1(
          v_state.id,v_next_state,v_boundary_at);
      end if;
      v_task_id := nullif(v_task_result ->> 'taskId', '')::uuid;
      v_occurrence_id := nullif(v_task_result ->> 'occurrenceId', '')::uuid;
    end if;

    v_transition_key := 'clock:' || v_state.id::text || ':' || v_transition_kind || ':' || extract(epoch from v_boundary_at)::bigint::text;
    v_transition_id := atlas.record_rhythm_transition_v1(
      v_state.id, v_transition_key, v_transition_kind, v_current_state, v_next_state,
      v_boundary_kind, v_boundary_at, v_as_of, v_satisfaction.id,
      v_task_id, v_occurrence_id,
      jsonb_build_object(
        'triggerKind', coalesce(p_trigger_kind, 'clock'),
        'ruleVersion', v_state.effective_rule_version,
        'warningAt', v_state.warning_at,
        'dueAt', v_state.due_at,
        'failureAt', v_state.failure_at,
        'task', v_task_result
      )
    );
    v_transition_ids := v_transition_ids || jsonb_build_array(v_transition_id);
    v_changed_count := v_changed_count + 1;
    v_current_state := v_next_state;
    v_state.current_task_id := coalesce(v_task_id, v_state.current_task_id);
    v_state.current_occurrence_id := coalesce(v_occurrence_id, v_state.current_occurrence_id);
  end loop;

  update atlas.rhythm_state
  set state = v_current_state,
      lease_started_at = case when v_satisfaction.id is null then null else v_state.lease_started_at end,
      warning_at = v_state.warning_at,
      due_at = v_state.due_at,
      failure_at = v_state.failure_at,
      recovery_started_at = v_state.recovery_started_at,
      current_task_id = v_state.current_task_id,
      current_occurrence_id = v_state.current_occurrence_id,
      last_evaluated_at = v_as_of,
      last_transition_at = case when v_changed_count > 0 then coalesce(v_boundary_at, v_as_of) else last_transition_at end,
      state_reason = jsonb_build_object(
        'transitionCount', v_changed_count,
        'lastTransitionId', case when jsonb_array_length(v_transition_ids) > 0 then v_transition_ids -> -1 else null end,
        'triggerKind', coalesce(p_trigger_kind, 'clock')
      ),
      updated_at = now()
  where id = v_state.id;

  return jsonb_build_object(
    'contractVersion', 'rhythm_evaluation_v1',
    'stateId', v_state.id,
    'changed', v_changed_count > 0,
    'transitionCount', v_changed_count,
    'transitions', v_transition_ids,
    'state', v_current_state,
    'warningAt', v_state.warning_at,
    'dueAt', v_state.due_at,
    'failureAt', v_state.failure_at,
    'asOf', v_as_of
  );
end;
$function$

