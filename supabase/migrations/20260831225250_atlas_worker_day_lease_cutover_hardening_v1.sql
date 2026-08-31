BEGIN;

-- Hardening before live cutover:
--   * shadow promotion inherits original commitment order/duration/load;
--   * task completion lease event is never backdated before its grant;
--   * human lease actions get an explicit idempotency key;
--   * replacement capacity derives duration/load even for migrated leases.

create or replace function atlas.open_worker_day_execution_leases_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date,
  p_reason text,
  p_actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_org_id uuid;
  v_timezone text;
  v_start timestamptz;
  v_end timestamptz;
  v_existing jsonb;
  v_shadow_count integer:=0;
  v_rec record;
  v_grant jsonb;
  v_grants jsonb:='[]'::jsonb;
  v_source text;
begin
  if p_day is null or nullif(btrim(coalesce(p_reason,'')),'') is null then
    raise exception 'Opening Worker Day execution leases requires a date and explicit reason.' using errcode='22023';
  end if;

  select f.organization_id,coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
    into v_org_id,v_timezone
  from atlas.farm_memberships fm
  join atlas.farms f on f.id=fm.farm_id
  where fm.id=p_membership_id and fm.farm_id=p_farm_id and fm.active=true;
  if v_org_id is null then raise exception 'Active worker membership required.' using errcode='42501'; end if;

  v_start:=p_day::timestamp at time zone v_timezone;
  v_end:=(p_day+1)::timestamp at time zone v_timezone;
  perform pg_advisory_xact_lock(hashtextextended('worker-day-live-lease:'||p_farm_id::text||':'||p_membership_id::text||':'||p_day::text,0));

  v_existing:=atlas.worker_day_live_execution_lease_packet_v1(p_farm_id,p_membership_id,p_day);
  if coalesce((v_existing->>'liveLeaseMode')::boolean,false) then
    return v_existing||jsonb_build_object('state','already_open','openingSource','existing_live_leases','grantResults','[]'::jsonb);
  end if;

  select count(*)::integer into v_shadow_count
  from atlas.execution_leases l
  where l.custody_kind='organization' and l.organization_id=v_org_id
    and l.recipient_kind='farm_membership' and l.recipient_id=p_membership_id
    and l.lease_kind='work_execution' and l.shadow_only=true
    and l.lease_start<v_end and l.lease_end>v_start
    and l.metadata->>'farmId'=p_farm_id::text and l.metadata->>'serviceDate'=p_day::text;

  if v_shadow_count>0 then
    v_source:='frozen_shadow_promise';
    for v_rec in
      select
        l.*,e.resulting_state as current_state,
        ci.sequence_number,
        ci.window_key,
        ci.expected_active_minutes,
        ci.physical_load,
        ci.admission_reason as commitment_admission_reason
      from atlas.execution_leases l
      join lateral (
        select x.resulting_state from atlas.execution_lease_events x
        where x.lease_id=l.id order by x.occurred_at desc,x.id desc limit 1
      ) e on true
      left join atlas.commitment_items ci
        on ci.id=coalesce(
          case when coalesce(l.metadata->>'commitmentItemId','') ~* '^[0-9a-f-]{36}$' then (l.metadata->>'commitmentItemId')::uuid else null end,
          case when l.source_kind='commitment_item' then l.source_id else null end
        )
      where l.custody_kind='organization' and l.organization_id=v_org_id
        and l.recipient_kind='farm_membership' and l.recipient_id=p_membership_id
        and l.lease_kind='work_execution' and l.shadow_only=true
        and l.lease_start<v_end and l.lease_end>v_start
        and l.metadata->>'farmId'=p_farm_id::text and l.metadata->>'serviceDate'=p_day::text
        and e.resulting_state not in ('withdrawn','expired')
      order by coalesce(ci.sequence_number,2147483647),l.created_at,l.id
    loop
      v_grant:=atlas.grant_execution_lease_v1(
        'worker_day_live:'||p_membership_id::text||':'||p_day::text||':'||v_rec.execution_kind||':'||v_rec.execution_id::text,
        'work_execution','organization',v_org_id,null,'farm_membership',p_membership_id,
        v_rec.obligation_kind,v_rec.obligation_id,v_rec.execution_kind,v_rec.execution_id,v_rec.title_snapshot,
        v_start,v_end,'worker_day_shadow_promise_promotion_v1',
        jsonb_build_object('authorized',true,'historicalHandoff',true,'shadowLeaseId',v_rec.id,
          'shadowAdmissionWarrant',v_rec.admission_warrant,'commitmentItemId',v_rec.source_id),
        p_reason,'execution_lease_shadow_promotion',v_rec.id,p_actor_user_id,false,
        coalesce(v_rec.metadata,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object(
          'shadowLeaseId',v_rec.id,'promotedToLiveAt',now(),'shadowOnly',false,'doesDrivePresentation',true,
          'admissionRank',v_rec.sequence_number,'dayWindow',v_rec.window_key,
          'expectedActiveMinutes',v_rec.expected_active_minutes,'physicalLoad',v_rec.physical_load,
          'admissionReason',v_rec.commitment_admission_reason
        ))
      );
      v_grants:=v_grants||jsonb_build_array(v_grant);
      if v_rec.current_state='interrupted' then
        perform atlas.transition_execution_lease_v1((v_grant->>'leaseId')::uuid,
          'shadow-promotion-interrupted:'||v_rec.id::text,'interrupted',
          'Promoted historical handoff was already interrupted.','execution_lease_shadow_promotion',v_rec.id,p_actor_user_id,
          jsonb_build_object('shadowLeaseState','interrupted'),'{}'::jsonb,now());
      elsif v_rec.current_state='completed' then
        perform atlas.transition_execution_lease_v1((v_grant->>'leaseId')::uuid,
          'shadow-promotion-completed:'||v_rec.id::text,'completed',
          'Promoted historical handoff was already completed.','execution_lease_shadow_promotion',v_rec.id,p_actor_user_id,
          jsonb_build_object('shadowLeaseState','completed'),'{}'::jsonb,now());
      end if;
    end loop;
  else
    v_source:='eligibility_before_capacity';
    for v_rec in select * from atlas.worker_day_lease_candidate_selection_v1(p_farm_id,p_membership_id,p_day) order by admission_rank,task_id
    loop
      v_grant:=atlas.grant_execution_lease_v1(
        'worker_day_live:'||p_membership_id::text||':'||p_day::text||':task:'||v_rec.task_id::text,
        'work_execution','organization',v_org_id,null,'farm_membership',p_membership_id,
        'task',v_rec.task_id,'task',v_rec.task_id,(select t.title from atlas.tasks t where t.id=v_rec.task_id),
        v_start,v_end,'worker_day_lease_admission_warrant_v1',
        jsonb_build_object('authorized',true,'executionReadiness',v_rec.readiness,'operationFit',v_rec.operation_fit,
          'plannerRank',v_rec.planner_rank,'plannerReason',v_rec.planner_reason,
          'admissionRank',v_rec.admission_rank,'admissionReason',v_rec.admission_reason),
        p_reason,'worker_day_lease_admission_v1',null,p_actor_user_id,false,
        jsonb_build_object('farmId',p_farm_id,'serviceDate',p_day,'timezone',v_timezone,
          'plannerRank',v_rec.planner_rank,'plannerReason',v_rec.planner_reason,
          'admissionRank',v_rec.admission_rank,'admissionReason',v_rec.admission_reason,
          'expectedActiveMinutes',v_rec.expected_active_minutes,'physicalLoad',v_rec.physical_load,
          'shadowOnly',false,'doesDrivePresentation',true)
      );
      v_grants:=v_grants||jsonb_build_array(v_grant);
    end loop;
  end if;

  return atlas.worker_day_live_execution_lease_packet_v1(p_farm_id,p_membership_id,p_day)
    ||jsonb_build_object('state','opened','openingSource',v_source,'grantResults',v_grants,
      'truthBoundary',jsonb_build_object('plannerIsAdvisory',true,'openingIsAtomicHumanHandoff',true,
        'laterPlannerRecomputeCannotChangeLeaseSet',true,'historicalPromiseOrderPreserved',true));
end;
$$;

create or replace function atlas.close_live_execution_lease_from_task_completion_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_completed_at timestamptz:=coalesce(new.completed_at,now());
  v_rec record;
begin
  if new.status<>'done' or old.status='done' then return new; end if;
  for v_rec in
    select l.id,e.resulting_state
    from atlas.execution_leases l
    join lateral (
      select x.resulting_state from atlas.execution_lease_events x
      where x.lease_id=l.id order by x.occurred_at desc,x.id desc limit 1
    ) e on true
    where l.execution_kind='task' and l.execution_id=new.id and l.shadow_only=false
      and l.lease_start<=v_completed_at and e.resulting_state in ('leased','started','interrupted')
    order by l.lease_start desc,l.id desc
  loop
    perform atlas.transition_execution_lease_v1(
      v_rec.id,'task-status-completed:'||new.id::text||':'||md5(v_completed_at::text),
      'completed','The leased execution completed through its canonical task outcome.',
      'task_status_completion',new.id,auth.uid(),
      jsonb_build_object('taskId',new.id,'taskStatus',new.status,'completedAt',v_completed_at,'previousTaskStatus',old.status),
      jsonb_build_object('atomicWithTaskCompletion',true),now()
    );
  end loop;
  return new;
end;
$$;

-- The six-argument v1 action remains internal compatibility only. New clients
-- must supply an idempotency key through v2.
revoke execute on function atlas.worker_day_execution_lease_action_v1(uuid,uuid,date,uuid,text,text) from authenticated;
grant execute on function atlas.worker_day_execution_lease_action_v1(uuid,uuid,date,uuid,text,text) to service_role;

create or replace function atlas.worker_day_execution_lease_action_v2(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date,
  p_lease_id uuid,
  p_action text,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_target atlas.farm_memberships%rowtype;
  v_lease atlas.execution_leases%rowtype;
  v_action text:=lower(btrim(coalesce(p_action,'')));
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_readiness jsonb;
  v_fit jsonb;
  v_source_kind text;
begin
  if auth.uid() is null then raise exception 'Authenticated user required.' using errcode='42501'; end if;
  if p_day is null or p_lease_id is null or nullif(btrim(coalesce(p_reason,'')),'') is null or v_key is null or length(v_key)>160 then
    raise exception 'Worker Day lease action requires day, lease, explicit reason, and idempotency key.' using errcode='22023';
  end if;
  if v_action not in ('started','interrupted','resumed','withdrawn') then raise exception 'Unsupported Worker Day lease action.' using errcode='22023'; end if;

  select * into v_target from atlas.farm_memberships fm
  where fm.id=p_membership_id and fm.farm_id=p_farm_id and fm.active=true;
  if v_target.id is null then raise exception 'Active target membership required.' using errcode='42501'; end if;
  if v_target.user_id=auth.uid() then
    if v_action not in ('started','resumed') then raise exception 'Farm hands may only start or resume their own leased work.' using errcode='42501'; end if;
  elsif not atlas.is_farm_manager_or_owner(p_farm_id) then
    raise exception 'Only the target worker or farm management may amend this execution lease.' using errcode='42501';
  end if;

  select * into v_lease from atlas.execution_leases l where l.id=p_lease_id;
  if v_lease.id is null or v_lease.recipient_kind<>'farm_membership' or v_lease.recipient_id<>p_membership_id or v_lease.shadow_only then
    raise exception 'Live Worker Day execution lease not found for target member.' using errcode='P0002';
  end if;

  if v_action='resumed' and v_lease.execution_kind='task' then
    v_readiness:=atlas.task_execution_readiness_v1(v_lease.execution_id);
    v_fit:=atlas.task_operation_fit_warrant_v1(v_lease.execution_id);
    if not coalesce((v_readiness->>'executionReady')::boolean,false)
       or not coalesce((v_fit->>'exactIdentitySupported')::boolean,false)
       or not exists(select 1 from atlas.tasks t where t.id=v_lease.execution_id and t.status='open') then
      raise exception 'Interrupted work cannot resume until its current execution warrant is valid again.' using errcode='23514';
    end if;
  end if;

  v_source_kind:=case when v_target.user_id=auth.uid() then 'worker_lease_action' else 'management_lease_action' end;
  return atlas.transition_execution_lease_v1(
    p_lease_id,'worker-day-action-v2:'||md5(p_lease_id::text||':'||v_key),v_action,p_reason,v_source_kind,
    p_membership_id,auth.uid(),jsonb_strip_nulls(jsonb_build_object('farmId',p_farm_id,'membershipId',p_membership_id,
      'serviceDate',p_day,'executionReadiness',v_readiness,'operationFit',v_fit,'idempotencyKey',v_key)),
    jsonb_build_object('explicitHumanLeaseAmendment',true),now()
  )||jsonb_build_object('contractVersion','worker_day_execution_lease_action_v2');
end;
$$;

grant execute on function atlas.worker_day_execution_lease_action_v2(uuid,uuid,date,uuid,text,text,text) to authenticated,service_role;
revoke execute on function atlas.worker_day_execution_lease_action_v2(uuid,uuid,date,uuid,text,text,text) from public,anon;

create or replace function atlas.grant_worker_day_replacement_execution_lease_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date,
  p_task_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_org_id uuid;
  v_timezone text;
  v_start timestamptz;
  v_end timestamptz;
  v_target integer:=0;
  v_heavy_cap integer:=0;
  v_used integer:=0;
  v_used_heavy integer:=0;
  v_capacity jsonb;
  v_task atlas.tasks%rowtype;
  v_cp record;
  v_readiness jsonb;
  v_fit jsonb;
  v_planner record;
  v_member atlas.farm_memberships%rowtype;
  v_assignment boolean;
begin
  if auth.uid() is null then raise exception 'Authenticated user required.' using errcode='42501'; end if;
  if not atlas.is_farm_manager_or_owner(p_farm_id) then raise exception 'Only farm management may grant replacement Worker Day execution leases.' using errcode='42501'; end if;
  if p_day is null or p_task_id is null or nullif(btrim(coalesce(p_reason,'')),'') is null then
    raise exception 'Replacement lease requires day, task, and explicit reason.' using errcode='22023';
  end if;

  select * into v_member from atlas.farm_memberships fm
  where fm.id=p_membership_id and fm.farm_id=p_farm_id and fm.active=true;
  select f.organization_id,coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago') into v_org_id,v_timezone
  from atlas.farms f where f.id=p_farm_id;
  if v_member.id is null or v_org_id is null then raise exception 'Active target membership required.' using errcode='42501'; end if;

  v_start:=p_day::timestamp at time zone v_timezone;
  v_end:=(p_day+1)::timestamp at time zone v_timezone;
  if not coalesce((atlas.worker_day_live_execution_lease_packet_v1(p_farm_id,p_membership_id,p_day)->>'liveLeaseMode')::boolean,false) then
    raise exception 'Replacement requires an already-open Worker Day lease set.' using errcode='23514';
  end if;
  if exists(select 1 from atlas.execution_leases l
    where l.organization_id=v_org_id and l.recipient_kind='farm_membership' and l.recipient_id=p_membership_id
      and l.shadow_only=false and l.execution_kind='task' and l.execution_id=p_task_id and l.lease_start<v_end and l.lease_end>v_start) then
    raise exception 'Task already has a live lease for this Worker Day.' using errcode='23505';
  end if;

  select * into v_task from atlas.tasks t where t.id=p_task_id and t.farm_id=p_farm_id and t.status='open';
  if v_task.id is null then raise exception 'Open task not found on farm.' using errcode='P0002'; end if;
  v_assignment:=v_task.assigned_membership_id=p_membership_id or v_task.assigned_user_id=v_member.user_id
    or v_task.metadata->>'executor_membership_id'=p_membership_id::text
    or (nullif(lower(btrim(v_member.worker_key)),'') is not null and lower(coalesce(
      nullif(v_task.metadata->>'executor_worker_key',''),nullif(v_task.metadata->>'assignee_key',''),
      nullif(v_task.metadata->>'assigned_to',''),nullif(v_task.metadata->>'work_route','')
    ))=nullif(lower(btrim(v_member.worker_key)),''));
  if not v_assignment then raise exception 'Replacement task is not assigned to target worker.' using errcode='42501'; end if;

  select * into v_planner from atlas.presented_work_selection_rows_v3(p_farm_id,p_membership_id,p_day) s
  where s.task_id=p_task_id and coalesce(s.presentation_reason,'') not in ('future','committed_other_day','consequence_resolution_required') limit 1;
  if v_planner.task_id is null then raise exception 'Task is not a lawful current-day planner candidate.' using errcode='23514'; end if;

  v_readiness:=atlas.task_execution_readiness_v1(p_task_id);
  v_fit:=atlas.task_operation_fit_warrant_v1(p_task_id);
  if not coalesce((v_readiness->>'executionReady')::boolean,false) or not coalesce((v_fit->>'exactIdentitySupported')::boolean,false) then
    raise exception 'Replacement task does not currently carry an execution + identity warrant.' using errcode='23514';
  end if;

  select * into v_cp from atlas.task_capacity_plan_v1(v_task,p_day);
  v_capacity:=atlas.worker_week_day_capacity_v1(p_farm_id,p_membership_id,p_day);
  v_target:=case when v_capacity->>'capacityClass' in ('recovery','explicit_override')
    then greatest(coalesce((v_capacity->>'recoveryCapacityMinutes')::integer,0),0)
    else greatest(coalesce((v_capacity->>'plannedCapacityMinutes')::integer,0),0) end;
  v_heavy_cap:=greatest(least(coalesce((v_capacity->>'heavyMinutesSoftCap')::integer,v_target),v_target),0);

  select
    coalesce(sum(case when e.resulting_state in ('leased','started')
      then coalesce(nullif(l.metadata->>'expectedActiveMinutes','')::integer,cp.expected_active_minutes,0) else 0 end),0)::integer,
    coalesce(sum(case when e.resulting_state in ('leased','started')
      and coalesce(nullif(l.metadata->>'physicalLoad',''),cp.physical_load)='heavy'
      then coalesce(nullif(l.metadata->>'expectedActiveMinutes','')::integer,cp.expected_active_minutes,0) else 0 end),0)::integer
  into v_used,v_used_heavy
  from atlas.execution_leases l
  join lateral (select x.resulting_state from atlas.execution_lease_events x where x.lease_id=l.id order by x.occurred_at desc,x.id desc limit 1) e on true
  left join atlas.tasks lt on l.execution_kind='task' and lt.id=l.execution_id
  left join lateral atlas.task_capacity_plan_v1(lt,p_day) cp on lt.id is not null
  where l.organization_id=v_org_id and l.recipient_kind='farm_membership' and l.recipient_id=p_membership_id
    and l.shadow_only=false and l.lease_start<v_end and l.lease_end>v_start;

  if v_used+greatest(coalesce(v_cp.expected_active_minutes,0),0)>v_target
     or (v_cp.physical_load='heavy' and v_used_heavy+greatest(coalesce(v_cp.expected_active_minutes,0),0)>v_heavy_cap) then
    raise exception 'Replacement task does not fit remaining Worker Day execution capacity.' using errcode='23514';
  end if;

  return atlas.grant_execution_lease_v1(
    'worker_day_live:'||p_membership_id::text||':'||p_day::text||':task:'||p_task_id::text,
    'work_execution','organization',v_org_id,null,'farm_membership',p_membership_id,
    'task',p_task_id,'task',p_task_id,v_task.title,v_start,v_end,'worker_day_replacement_admission_warrant_v1',
    jsonb_build_object('authorized',true,'executionReadiness',v_readiness,'operationFit',v_fit,
      'plannerRank',v_planner.selection_rank,'plannerReason',v_planner.presentation_reason),
    p_reason,'management_replacement_grant',p_task_id,auth.uid(),false,
    jsonb_build_object('farmId',p_farm_id,'serviceDate',p_day,'timezone',v_timezone,
      'plannerRank',v_planner.selection_rank,'plannerReason',v_planner.presentation_reason,
      'expectedActiveMinutes',v_cp.expected_active_minutes,'physicalLoad',v_cp.physical_load,
      'replacementGrant',true,'doesDrivePresentation',true)
  );
end;
$$;

COMMIT;
