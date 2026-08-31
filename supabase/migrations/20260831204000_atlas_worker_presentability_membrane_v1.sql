BEGIN;

-- Worker-facing work is not the same thing as an active obligation.
-- A task may remain true while current reality, routing, or operation identity
-- prevents a human from executing it. This migration establishes one membrane
-- for worker presentation and makes the newer canonical selection path the
-- routing authority used by the transition bridge.

create or replace function atlas.worker_task_routing_warrant_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_task_id uuid,
  p_service_date date
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_member atlas.farm_memberships%rowtype;
  v_placement_id uuid;
  v_selected boolean := false;
  v_assignment_match boolean := false;
  v_routed boolean := false;
  v_source text;
begin
  select * into v_member
  from atlas.farm_memberships m
  where m.id=p_membership_id and m.farm_id=p_farm_id and m.active=true;

  select * into v_task
  from atlas.tasks t
  where t.id=p_task_id and t.farm_id=p_farm_id;

  if v_member.id is null or v_task.id is null or p_service_date is null then
    return jsonb_build_object(
      'contractVersion','worker_task_routing_warrant_v1',
      'taskId',p_task_id,'membershipId',p_membership_id,'serviceDate',p_service_date,
      'routedForDay',false,'assignmentMatch',false,'state','invalid_subject'
    );
  end if;

  v_assignment_match :=
    v_task.assigned_membership_id=p_membership_id
    or v_task.assigned_user_id=v_member.user_id
    or v_task.metadata->>'executor_membership_id'=p_membership_id::text
    or (
      nullif(lower(btrim(v_member.worker_key)),'') is not null
      and lower(coalesce(
        nullif(v_task.metadata->>'executor_worker_key',''),
        nullif(v_task.metadata->>'assignee_key',''),
        nullif(v_task.metadata->>'assigned_to',''),
        nullif(v_task.metadata->>'work_route','')
      ))=nullif(lower(btrim(v_member.worker_key)),'')
    );

  select p.id into v_placement_id
  from atlas.worker_day_task_placements p
  where p.farm_id=p_farm_id
    and p.membership_id=p_membership_id
    and p.task_id=p_task_id
    and p.service_date=p_service_date
    and p.state='placed'
  order by p.updated_at desc,p.created_at desc
  limit 1;

  select exists(
    select 1
    from atlas.presented_work_selection_rows_live_v1(p_farm_id,p_membership_id,p_service_date) s
    where s.task_id=p_task_id and s.presentation_state='presented'
  ) into v_selected;

  v_routed:=v_assignment_match and (v_placement_id is not null or v_selected);
  v_source:=case
    when not v_assignment_match then 'assignment_mismatch'
    when v_placement_id is not null then 'explicit_placement'
    when v_selected then 'canonical_presented_selection'
    else 'not_routed'
  end;

  return jsonb_build_object(
    'contractVersion','worker_task_routing_warrant_v1',
    'taskId',p_task_id,
    'membershipId',p_membership_id,
    'serviceDate',p_service_date,
    'assignmentMatch',v_assignment_match,
    'explicitPlacement',v_placement_id is not null,
    'placementId',v_placement_id,
    'canonicalPresentedSelection',v_selected,
    'routedForDay',v_routed,
    'state',case when v_routed then 'routed' else 'not_routed' end,
    'source',v_source,
    'truthBoundary',jsonb_build_object(
      'assignmentIsNotRouting',true,
      'dueDateIsNotRouting',true,
      'overdueIsNotRouting',true,
      'explicitPlacementIsRouting',true,
      'canonicalPresentedSelectionIsRouting',true
    )
  );
end;
$function$;

create or replace function atlas.task_operation_fit_warrant_v1(p_task_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_rec record;
  v_packet jsonb;
  v_subject_count integer:=0;
  v_mismatch_count integer:=0;
  v_state text;
  v_function text;
  v_current_task_id uuid;
begin
  select * into v_task from atlas.tasks where id=p_task_id;
  if v_task.id is null then raise exception 'Task not found.' using errcode='P0002'; end if;

  for v_rec in
    select cc.id
    from atlas.task_crop_cycles l
    join atlas.crop_cycles cc on cc.id=l.crop_cycle_id
    where l.task_id=p_task_id
  loop
    v_subject_count:=v_subject_count+1;
    v_packet:=atlas.crop_cycle_reality_expression_v3(v_rec.id);
    v_state:=coalesce(v_packet#>>'{fittingOperation,state}','unresolved');
    begin
      v_current_task_id:=nullif(v_packet#>>'{fittingOperation,currentTaskId}','')::uuid;
    exception when invalid_text_representation then
      v_current_task_id:=null;
    end;
    if v_state not in ('available','required') or v_current_task_id is distinct from p_task_id then
      v_mismatch_count:=v_mismatch_count+1;
    end if;
  end loop;

  for v_rec in
    select lot.id
    from atlas.production_lot_tasks l
    join atlas.production_lots lot on lot.id=l.production_lot_id
    where l.task_id=p_task_id
  loop
    v_subject_count:=v_subject_count+1;
    v_packet:=atlas.reality_expression_packet_v2(v_rec.id);
    v_state:=coalesce(v_packet#>>'{flowBufferClaim,nextTransitionAvailability,state}','not_available');
    v_function:=nullif(v_packet#>>'{flowBufferClaim,nextTransitionAvailability,operationFunction}','');
    if v_state not in ('available_for_routing_unclaimed','claimed_for_execution_capacity_fit_unverified')
       or v_function is distinct from v_task.action_key then
      v_mismatch_count:=v_mismatch_count+1;
    end if;
  end loop;

  return jsonb_build_object(
    'contractVersion','task_operation_fit_warrant_v1',
    'taskId',p_task_id,
    'subjectCount',v_subject_count,
    'identityMismatchCount',v_mismatch_count,
    'exactIdentitySupported',v_mismatch_count=0,
    'state',case when v_mismatch_count=0 then 'supported' else 'unresolved' end,
    'truthBoundary',jsonb_build_object(
      'taskLabelIsNotIdentityProof',true,
      'zeroSubjectTaskUsesExecutionRequirements',true,
      'subjectBearingTaskRequiresExactRealityIdentity',true
    )
  );
end;
$function$;

create or replace function atlas.worker_task_presentability_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_task_id uuid,
  p_service_date date
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_readiness jsonb;
  v_routing jsonb;
  v_fit jsonb;
  v_obligation_active boolean:=false;
  v_execution_ready boolean:=false;
  v_assignment_match boolean:=false;
  v_routed boolean:=false;
  v_fit_ready boolean:=false;
  v_presentable boolean:=false;
  v_hold_reason text;
begin
  select * into v_task from atlas.tasks where id=p_task_id and farm_id=p_farm_id;
  if v_task.id is null then raise exception 'Task not found on farm.' using errcode='P0002'; end if;

  v_obligation_active:=v_task.status in ('open','blocked');
  v_readiness:=atlas.task_execution_readiness_v1(p_task_id);
  v_routing:=atlas.worker_task_routing_warrant_v1(p_farm_id,p_membership_id,p_task_id,p_service_date);
  v_fit:=atlas.task_operation_fit_warrant_v1(p_task_id);
  v_execution_ready:=coalesce((v_readiness->>'executionReady')::boolean,false);
  v_assignment_match:=coalesce((v_routing->>'assignmentMatch')::boolean,false);
  v_routed:=coalesce((v_routing->>'routedForDay')::boolean,false);
  v_fit_ready:=coalesce((v_fit->>'exactIdentitySupported')::boolean,false);

  v_presentable:=v_obligation_active
    and v_task.status='open'
    and v_execution_ready
    and v_assignment_match
    and v_routed
    and v_fit_ready;

  v_hold_reason:=case
    when not v_obligation_active then 'obligation_not_active'
    when v_task.status<>'open' then 'task_status_'||v_task.status
    when not v_assignment_match then 'not_assigned_here'
    when not v_execution_ready then 'execution_not_ready'
    when not v_fit_ready then 'operation_identity_unresolved'
    when not v_routed then 'not_routed_for_day'
    else null
  end;

  return jsonb_strip_nulls(jsonb_build_object(
    'contractVersion','worker_task_presentability_v1',
    'taskId',p_task_id,
    'membershipId',p_membership_id,
    'serviceDate',p_service_date,
    'obligationActive',v_obligation_active,
    'taskStatus',v_task.status,
    'executionReady',v_execution_ready,
    'assignedHere',v_assignment_match,
    'routedForDay',v_routed,
    'operationFit',v_fit_ready,
    'presentable',v_presentable,
    'holdReason',v_hold_reason,
    'ownerAttentionRequired',v_obligation_active and not v_presentable,
    'readiness',v_readiness,
    'routing',v_routing,
    'operationFitWarrant',v_fit,
    'truthBoundary',jsonb_build_object(
      'obligationDoesNotEqualExecution',true,
      'executionDoesNotEqualRouting',true,
      'routingDoesNotEqualPresentation',true,
      'workerPresentationRequiresAllWarrants',true
    )
  ));
end;
$function$;

create or replace function atlas.worker_state_transition_selection_bridge_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_task_id uuid,
  p_service_date date,
  p_card jsonb
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_card jsonb:=coalesce(p_card,'{}'::jsonb);
  v_task atlas.tasks%rowtype;
  v_readiness jsonb;
  v_routing jsonb;
  v_fit jsonb;
  v_capacity record;
begin
  if p_service_date is null
     or coalesce(v_card#>>'{transition,state}','')<>'not_routed'
     or coalesce(v_card#>>'{routing,state}','')<>'not_placed_for_worker_day' then
    return v_card;
  end if;

  select * into v_task
  from atlas.tasks t
  where t.id=p_task_id and t.farm_id=p_farm_id and t.status='open';
  if v_task.id is null then return v_card; end if;

  v_routing:=atlas.worker_task_routing_warrant_v1(p_farm_id,p_membership_id,p_task_id,p_service_date);
  if coalesce(v_routing->>'source','')<>'canonical_presented_selection'
     or not coalesce((v_routing->>'routedForDay')::boolean,false) then
    return v_card;
  end if;

  v_readiness:=atlas.task_execution_readiness_v1(p_task_id);
  v_fit:=atlas.task_operation_fit_warrant_v1(p_task_id);
  if not coalesce((v_readiness->>'executionReady')::boolean,false)
     or not coalesce((v_fit->>'exactIdentitySupported')::boolean,false)
     or coalesce((v_card#>>'{clock,definiteCapacityConflict}')::boolean,false) then
    return v_card;
  end if;

  select cp.expected_active_minutes,cp.physical_load
  into v_capacity
  from atlas.task_capacity_plan_v1(v_task,p_service_date) cp;

  v_card:=jsonb_set(v_card,'{routing,state}',to_jsonb('selected_for_worker_day'::text),true);
  v_card:=jsonb_set(v_card,'{routing,selectionAuthority}',v_routing,true);
  v_card:=jsonb_set(v_card,'{jurisdiction,state}',to_jsonb('selected_body_established'::text),true);
  v_card:=jsonb_set(v_card,'{clock,selectionClaim}',jsonb_build_object(
    'state','canonical_presented_selection',
    'exactTimeClaim',false,
    'principle','Canonical selection routes today ownership without inventing an exact Clock placement.'
  ),true);
  v_card:=jsonb_set(v_card,'{transition,state}',to_jsonb('authorized_for_routed_day'::text),true);
  v_card:=jsonb_set(v_card,'{transition,authorizedInstruction}',jsonb_strip_nulls(jsonb_build_object(
    'actionKey',v_task.action_key,
    'operationClass',v_task.operation_class,
    'do',coalesce(nullif(v_task.metadata->>'execution_do',''),v_task.title),
    'doneWhen',nullif(v_task.metadata->>'execution_done_when',''),
    'dayWindow',atlas.worker_task_day_window_v1(v_task.action_key,v_task.task_type,v_task.metadata),
    'plannedStartAt',null,
    'plannedDurationMinutes',v_capacity.expected_active_minutes
  )),true);
  v_card:=jsonb_set(v_card,'{truthBoundary,selectedDayBridge}',jsonb_build_object(
    'requiresCanonicalLiveSelection',true,
    'requiresExecutionReadiness',true,
    'requiresExactOperationFit',true,
    'requiresNoDefiniteCapacityConflict',true,
    'doesNotCreateClockPlacement',true
  ),true);
  return v_card;
end;
$function$;

create or replace function atlas.worker_day_work_projection_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date
)
returns table(
  task_id uuid,
  visibility_state text,
  visibility_reason text,
  presentation_state text,
  presentation_reason text,
  selection_rank bigint,
  work_lane text,
  commitment_kind text,
  effort_units numeric,
  budget_units numeric,
  notification_planned boolean,
  overload boolean
)
language sql
stable security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
  with selected as materialized (
    select * from atlas.presented_work_selection_rows_live_v1(p_farm_id,p_membership_id,p_day)
  ), floor as materialized (
    select * from atlas.worker_day_visibility_floor_v1(p_farm_id,p_membership_id,p_day)
  ), ids as (
    select s.task_id from selected s
    union
    select f.task_id from floor f
  ), candidates as (
    select
      i.task_id,
      coalesce(f.visibility_reason,'presentation_selected') as visibility_reason,
      case when s.task_id is not null then s.presentation_state else 'presented' end as presentation_state,
      coalesce(s.presentation_reason,'explicit_placement_presentable') as presentation_reason,
      coalesce(s.selection_rank,9223372036854775807::bigint) as selection_rank,
      coalesce(s.work_lane,t.work_lane,'required') as work_lane,
      coalesce(s.commitment_kind,t.commitment_kind,'none') as commitment_kind,
      coalesce(s.effort_units,t.effort_units,0::numeric) as effort_units,
      coalesce(s.budget_units,0::numeric) as budget_units,
      coalesce(s.notification_planned,false) as notification_planned,
      coalesce(s.overload,false) as overload,
      atlas.worker_task_presentability_v1(p_farm_id,p_membership_id,i.task_id,p_day) as warrant
    from ids i
    join atlas.tasks t on t.id=i.task_id
    left join selected s on s.task_id=i.task_id
    left join floor f on f.task_id=i.task_id
  )
  select
    c.task_id,
    'visible'::text,
    c.visibility_reason,
    c.presentation_state,
    c.presentation_reason,
    c.selection_rank,
    c.work_lane,
    c.commitment_kind,
    c.effort_units,
    c.budget_units,
    c.notification_planned,
    c.overload
  from candidates c
  where coalesce((c.warrant->>'presentable')::boolean,false)
  order by c.selection_rank,c.task_id;
$function$;

create or replace function atlas.worker_self_day_bundle_api_v1(p_farm_id uuid,p_membership_id uuid,p_day date)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_today date:=(now() at time zone 'America/Chicago')::date;
  v_plan jsonb;
  v_task_ids uuid[]:=array[]::uuid[];
  v_cards jsonb:='[]'::jsonb;
  v_safe_cards jsonb:='[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Authenticated user required.' using errcode='42501'; end if;
  if p_day is null then raise exception 'A worker day is required.' using errcode='22023'; end if;
  if not exists(select 1 from atlas.farm_memberships m where m.id=p_membership_id and m.farm_id=p_farm_id and m.user_id=auth.uid() and m.active=true and m.role='farm_hand') then
    raise exception 'The Farm Hand Worker Day bundle may only be read by that active Farm Hand.' using errcode='42501';
  end if;

  if p_day=v_today then
    v_plan:=atlas.worker_day_feed_plan_live_v1(p_farm_id,p_membership_id,p_day)
      || jsonb_build_object('deferredWork','[]'::jsonb,'nextUp','[]'::jsonb,'clockTimeline',jsonb_build_object('items','[]'::jsonb),'nextUpContractVersion','worker_self_next_up_deferred_v1','contractVersion','worker_self_day_plan_fast_v1');
  else
    v_plan:=atlas.worker_self_day_plan_api_v1(p_farm_id,p_membership_id,p_day);
  end if;

  select coalesce(array_agg(distinct x.task_id) filter(where x.task_id is not null),array[]::uuid[])
  into v_task_ids
  from (
    select nullif(row->>'taskId','')::uuid task_id
    from jsonb_array_elements(coalesce(v_plan->'realWork','[]'::jsonb)||coalesce(v_plan->'automaticWork','[]'::jsonb)) row
  ) x;

  v_cards:=atlas.worker_day_operational_task_cards_v3(p_farm_id,p_membership_id,p_day,v_task_ids);
  select coalesce(jsonb_agg(card-'move_context' order by ord),'[]'::jsonb)
  into v_safe_cards
  from jsonb_array_elements(v_cards) with ordinality as cards(card,ord);

  return jsonb_build_object('contractVersion','worker_self_day_bundle_presentability_v1','plan',v_plan,'taskCards',v_safe_cards);
end;
$function$;

create or replace function atlas.worker_self_day_bundle_api_v2(p_farm_id uuid,p_membership_id uuid,p_day date)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_timezone text:='America/Chicago';
  v_today date;
  v_plan jsonb;
  v_task_ids uuid[]:=array[]::uuid[];
  v_cards jsonb:='[]'::jsonb;
  v_safe_cards jsonb:='[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Authenticated user required.' using errcode='42501'; end if;
  if p_day is null then raise exception 'A worker day is required.' using errcode='22023'; end if;
  if not exists(select 1 from atlas.farm_memberships m where m.id=p_membership_id and m.farm_id=p_farm_id and m.user_id=auth.uid() and m.active=true and m.role='farm_hand') then
    raise exception 'The Farm Hand Worker Day bundle may only be read by that active Farm Hand.' using errcode='42501';
  end if;

  select coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago') into v_timezone from atlas.farms f where f.id=p_farm_id;
  v_today:=(now() at time zone coalesce(v_timezone,'America/Chicago'))::date;
  if p_day<>v_today then return atlas.worker_self_day_bundle_api_v1(p_farm_id,p_membership_id,p_day); end if;

  v_plan:=atlas.worker_day_feed_plan_live_v1(p_farm_id,p_membership_id,p_day)
    || jsonb_build_object('contractVersion','worker_self_day_live_presentability_v1','clockTimeline',null,'suggestions','[]'::jsonb);

  select coalesce(array_agg(distinct x.task_id) filter(where x.task_id is not null),array[]::uuid[])
  into v_task_ids
  from (
    select nullif(row->>'taskId','')::uuid task_id
    from jsonb_array_elements(coalesce(v_plan->'realWork','[]'::jsonb)||coalesce(v_plan->'automaticWork','[]'::jsonb)) row
  ) x;

  v_cards:=atlas.worker_day_operational_task_cards_v3(p_farm_id,p_membership_id,p_day,v_task_ids);
  select coalesce(jsonb_agg(card-'move_context' order by ord),'[]'::jsonb)
  into v_safe_cards
  from jsonb_array_elements(v_cards) with ordinality as cards(card,ord);

  return jsonb_build_object('contractVersion','worker_self_day_bundle_presentability_v2','plan',v_plan,'taskCards',v_safe_cards);
end;
$function$;

comment on function atlas.worker_task_routing_warrant_v1(uuid,uuid,uuid,date) is
  'Canonical Worker Day routing warrant. Assignment, due dates, and overdue state do not route work. Explicit placement or canonical live presentation selection does.';
comment on function atlas.task_operation_fit_warrant_v1(uuid) is
  'Read-only operation identity warrant shared by Worker Day presentability. Subject-bearing work requires exact canonical Reality identity; zero-subject work is governed by execution requirements.';
comment on function atlas.worker_task_presentability_v1(uuid,uuid,uuid,date) is
  'Canonical worker presentation membrane: active open obligation + execution readiness + assignment + day routing + operation fit are all required before work may reach a worker-facing surface.';
comment on function atlas.worker_day_work_projection_v1(uuid,uuid,date) is
  'Worker Day projection. Legacy visibility-floor rows remain candidate/audit coverage only; they cannot force visibility past worker_task_presentability_v1.';
comment on function atlas.worker_day_visibility_floor_v1(uuid,uuid,date) is
  'Compatibility coverage enumerator only. It must not be treated as Worker Day presentation authority.';
comment on function atlas.worker_day_operational_task_cards_v2(uuid,uuid,date,uuid[]) is
  'Internal compatibility card builder. Worker-facing bundles route through worker_day_operational_task_cards_v3.';

-- Keep compatibility helpers available to privileged internal callers while
-- removing them as direct authenticated/anonymous presentation surfaces.
revoke all on function atlas.worker_task_routing_warrant_v1(uuid,uuid,uuid,date) from public,anon,authenticated;
revoke all on function atlas.task_operation_fit_warrant_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.worker_task_presentability_v1(uuid,uuid,uuid,date) from public,anon,authenticated;
grant execute on function atlas.worker_task_routing_warrant_v1(uuid,uuid,uuid,date) to service_role;
grant execute on function atlas.task_operation_fit_warrant_v1(uuid) to service_role;
grant execute on function atlas.worker_task_presentability_v1(uuid,uuid,uuid,date) to service_role;

revoke all on function atlas.worker_day_visibility_floor_v1(uuid,uuid,date) from public,anon,authenticated;
revoke all on function atlas.worker_day_operational_task_cards_v2(uuid,uuid,date,uuid[]) from public,anon,authenticated;
grant execute on function atlas.worker_day_visibility_floor_v1(uuid,uuid,date) to service_role;
grant execute on function atlas.worker_day_operational_task_cards_v2(uuid,uuid,date,uuid[]) to service_role;

COMMIT;
