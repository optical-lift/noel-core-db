BEGIN;

-- Execution Lease lifecycle closure v1.
-- Task completion closes the same live lease atomically. Human-plan amendments
-- require explicit lease transitions; planner recommendations remain advisory.

create or replace function atlas.expire_worker_execution_leases_before_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_before timestamptz,
  p_actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_org_id uuid;
  v_rec record;
  v_events jsonb:='[]'::jsonb;
begin
  select f.organization_id into v_org_id
  from atlas.farm_memberships fm
  join atlas.farms f on f.id=fm.farm_id
  where fm.id=p_membership_id and fm.farm_id=p_farm_id and fm.active=true;
  if v_org_id is null then
    raise exception 'Active worker membership required.' using errcode='42501';
  end if;

  for v_rec in
    select l.id,e.resulting_state
    from atlas.execution_leases l
    join lateral (
      select x.resulting_state
      from atlas.execution_lease_events x
      where x.lease_id=l.id
      order by x.occurred_at desc,x.id desc
      limit 1
    ) e on true
    where l.custody_kind='organization'
      and l.organization_id=v_org_id
      and l.recipient_kind='farm_membership'
      and l.recipient_id=p_membership_id
      and l.lease_kind='work_execution'
      and l.shadow_only=false
      and l.lease_end<=p_before
      and e.resulting_state in ('leased','started','interrupted')
    order by l.lease_end,l.id
  loop
    v_events:=v_events||jsonb_build_array(atlas.transition_execution_lease_v1(
      v_rec.id,
      'lease-window-expired:'||to_char(p_before at time zone 'UTC','YYYYMMDDHH24MISS'),
      'expired','Execution lease window ended before the next Worker Day opened.',
      'worker_day_rollover',null,p_actor_user_id,
      jsonb_build_object('expiredBefore',p_before),'{}'::jsonb,now()
    ));
  end loop;
  return jsonb_build_object('contractVersion','expire_worker_execution_leases_before_v1','events',v_events);
end;
$$;

revoke all on function atlas.expire_worker_execution_leases_before_v1(uuid,uuid,timestamptz,uuid) from public,anon,authenticated;
grant execute on function atlas.expire_worker_execution_leases_before_v1(uuid,uuid,timestamptz,uuid) to service_role;

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
  if new.status<>'done' or old.status='done' then
    return new;
  end if;

  for v_rec in
    select l.id,e.resulting_state
    from atlas.execution_leases l
    join lateral (
      select x.resulting_state
      from atlas.execution_lease_events x
      where x.lease_id=l.id
      order by x.occurred_at desc,x.id desc
      limit 1
    ) e on true
    where l.execution_kind='task'
      and l.execution_id=new.id
      and l.shadow_only=false
      and l.lease_start<=v_completed_at
      and e.resulting_state in ('leased','started','interrupted')
    order by l.lease_start desc,l.id desc
  loop
    perform atlas.transition_execution_lease_v1(
      v_rec.id,
      'task-status-completed:'||new.id::text||':'||md5(v_completed_at::text),
      'completed','The leased execution completed through its canonical task outcome.',
      'task_status_completion',new.id,
      coalesce(nullif(new.metadata->>'completed_by_user_id','')::uuid,auth.uid()),
      jsonb_build_object(
        'taskId',new.id,
        'taskStatus',new.status,
        'completedAt',v_completed_at,
        'previousTaskStatus',old.status
      ),
      jsonb_build_object('atomicWithTaskCompletion',true),
      v_completed_at
    );
  end loop;
  return new;
end;
$$;

drop trigger if exists close_live_execution_lease_from_task_completion_v1 on atlas.tasks;
create trigger close_live_execution_lease_from_task_completion_v1
after update of status on atlas.tasks
for each row
when (new.status='done' and old.status is distinct from new.status)
execute function atlas.close_live_execution_lease_from_task_completion_v1();

comment on function atlas.close_live_execution_lease_from_task_completion_v1() is
  'Task-domain adapter guard: any canonical task completion atomically closes the non-shadow live execution lease that handed that task to a human. Completion never depends on which task result adapter performed the transition.';

revoke all on function atlas.close_live_execution_lease_from_task_completion_v1() from public,anon,authenticated;
grant execute on function atlas.close_live_execution_lease_from_task_completion_v1() to service_role;

create or replace function atlas.worker_day_execution_lease_action_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date,
  p_lease_id uuid,
  p_action text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_actor_membership uuid;
  v_role text;
  v_target atlas.farm_memberships%rowtype;
  v_lease atlas.execution_leases%rowtype;
  v_state jsonb;
  v_readiness jsonb;
  v_fit jsonb;
  v_action text:=lower(btrim(coalesce(p_action,'')));
  v_event_key text;
  v_source_kind text;
begin
  if auth.uid() is null then raise exception 'Authenticated user required.' using errcode='42501'; end if;
  if p_day is null or p_lease_id is null or nullif(btrim(coalesce(p_reason,'')),'') is null then
    raise exception 'Worker Day lease action requires day, lease, and explicit reason.' using errcode='22023';
  end if;
  if v_action not in ('started','interrupted','resumed','withdrawn') then
    raise exception 'Unsupported Worker Day lease action.' using errcode='22023';
  end if;

  select * into v_target from atlas.farm_memberships fm
  where fm.id=p_membership_id and fm.farm_id=p_farm_id and fm.active=true;
  if v_target.id is null then raise exception 'Active target membership required.' using errcode='42501'; end if;

  v_actor_membership:=atlas.current_membership_id(p_farm_id);
  v_role:=atlas.current_farm_role(p_farm_id);

  if v_target.user_id=auth.uid() then
    if v_action not in ('started','resumed') then
      raise exception 'Farm hands may only start or resume their own leased work.' using errcode='42501';
    end if;
  elsif not atlas.is_farm_manager_or_owner(p_farm_id) then
    raise exception 'Only the target worker or farm management may amend this execution lease.' using errcode='42501';
  end if;

  select * into v_lease from atlas.execution_leases l where l.id=p_lease_id;
  if v_lease.id is null
     or v_lease.recipient_kind<>'farm_membership'
     or v_lease.recipient_id<>p_membership_id
     or v_lease.shadow_only then
    raise exception 'Live Worker Day execution lease not found for target member.' using errcode='P0002';
  end if;

  if v_action='resumed' then
    if v_lease.execution_kind='task' then
      v_readiness:=atlas.task_execution_readiness_v1(v_lease.execution_id);
      v_fit:=atlas.task_operation_fit_warrant_v1(v_lease.execution_id);
      if not coalesce((v_readiness->>'executionReady')::boolean,false)
         or not coalesce((v_fit->>'exactIdentitySupported')::boolean,false)
         or not exists(select 1 from atlas.tasks t where t.id=v_lease.execution_id and t.status='open') then
        raise exception 'Interrupted work cannot resume until its current execution warrant is valid again.' using errcode='23514';
      end if;
    end if;
  end if;

  v_event_key:='worker-day-action:'||v_action||':'||md5(p_reason||':'||clock_timestamp()::text);
  v_source_kind:=case when v_target.user_id=auth.uid() then 'worker_lease_action' else 'management_lease_action' end;
  v_state:=atlas.transition_execution_lease_v1(
    p_lease_id,v_event_key,v_action,p_reason,v_source_kind,
    v_actor_membership,auth.uid(),
    jsonb_strip_nulls(jsonb_build_object(
      'farmId',p_farm_id,'membershipId',p_membership_id,'serviceDate',p_day,
      'executionReadiness',v_readiness,'operationFit',v_fit
    )),
    jsonb_build_object('explicitHumanLeaseAmendment',true),now()
  );
  return v_state||jsonb_build_object('contractVersion','worker_day_execution_lease_action_v1');
end;
$$;

grant execute on function atlas.worker_day_execution_lease_action_v1(uuid,uuid,date,uuid,text,text) to authenticated,service_role;
revoke execute on function atlas.worker_day_execution_lease_action_v1(uuid,uuid,date,uuid,text,text) from public,anon;

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
  if not atlas.is_farm_manager_or_owner(p_farm_id) then
    raise exception 'Only farm management may grant replacement Worker Day execution leases.' using errcode='42501';
  end if;
  if p_day is null or p_task_id is null or nullif(btrim(coalesce(p_reason,'')),'') is null then
    raise exception 'Replacement lease requires day, task, and explicit reason.' using errcode='22023';
  end if;

  select fm.*,f.organization_id,coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
    into v_member
  from atlas.farm_memberships fm
  join atlas.farms f on f.id=fm.farm_id
  where fm.id=p_membership_id and fm.farm_id=p_farm_id and fm.active=true;
  -- Re-resolve organization/timezone without relying on composite extension fields.
  select f.organization_id,coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago') into v_org_id,v_timezone
  from atlas.farms f where f.id=p_farm_id;
  if v_member.id is null or v_org_id is null then raise exception 'Active target membership required.' using errcode='42501'; end if;

  v_start:=p_day::timestamp at time zone v_timezone;
  v_end:=(p_day+1)::timestamp at time zone v_timezone;
  if not coalesce((atlas.worker_day_live_execution_lease_packet_v1(p_farm_id,p_membership_id,p_day)->>'liveLeaseMode')::boolean,false) then
    raise exception 'Replacement requires an already-open Worker Day lease set.' using errcode='23514';
  end if;
  if exists(
    select 1 from atlas.execution_leases l
    where l.organization_id=v_org_id and l.recipient_kind='farm_membership' and l.recipient_id=p_membership_id
      and l.shadow_only=false and l.execution_kind='task' and l.execution_id=p_task_id
      and l.lease_start<v_end and l.lease_end>v_start
  ) then
    raise exception 'Task already has a live lease for this Worker Day.' using errcode='23505';
  end if;

  select * into v_task from atlas.tasks t where t.id=p_task_id and t.farm_id=p_farm_id and t.status='open';
  if v_task.id is null then raise exception 'Open task not found on farm.' using errcode='P0002'; end if;

  v_assignment:=v_task.assigned_membership_id=p_membership_id
    or v_task.assigned_user_id=v_member.user_id
    or v_task.metadata->>'executor_membership_id'=p_membership_id::text
    or (nullif(lower(btrim(v_member.worker_key)),'') is not null and lower(coalesce(
      nullif(v_task.metadata->>'executor_worker_key',''),nullif(v_task.metadata->>'assignee_key',''),
      nullif(v_task.metadata->>'assigned_to',''),nullif(v_task.metadata->>'work_route','')
    ))=nullif(lower(btrim(v_member.worker_key)),''));
  if not v_assignment then raise exception 'Replacement task is not assigned to target worker.' using errcode='42501'; end if;

  select * into v_planner
  from atlas.presented_work_selection_rows_v3(p_farm_id,p_membership_id,p_day) s
  where s.task_id=p_task_id
    and coalesce(s.presentation_reason,'') not in ('future','committed_other_day','consequence_resolution_required')
  limit 1;
  if v_planner.task_id is null then
    raise exception 'Task is not a lawful current-day planner candidate.' using errcode='23514';
  end if;

  v_readiness:=atlas.task_execution_readiness_v1(p_task_id);
  v_fit:=atlas.task_operation_fit_warrant_v1(p_task_id);
  if not coalesce((v_readiness->>'executionReady')::boolean,false)
     or not coalesce((v_fit->>'exactIdentitySupported')::boolean,false) then
    raise exception 'Replacement task does not currently carry an execution + identity warrant.' using errcode='23514';
  end if;

  select * into v_cp from atlas.task_capacity_plan_v1(v_task,p_day);
  v_capacity:=atlas.worker_week_day_capacity_v1(p_farm_id,p_membership_id,p_day);
  v_target:=case when v_capacity->>'capacityClass' in ('recovery','explicit_override')
    then greatest(coalesce((v_capacity->>'recoveryCapacityMinutes')::integer,0),0)
    else greatest(coalesce((v_capacity->>'plannedCapacityMinutes')::integer,0),0) end;
  v_heavy_cap:=greatest(least(coalesce((v_capacity->>'heavyMinutesSoftCap')::integer,v_target),v_target),0);

  select
    coalesce(sum(case when e.resulting_state in ('leased','started') then coalesce(nullif(l.metadata->>'expectedActiveMinutes','')::integer,0) else 0 end),0)::integer,
    coalesce(sum(case when e.resulting_state in ('leased','started') and l.metadata->>'physicalLoad'='heavy' then coalesce(nullif(l.metadata->>'expectedActiveMinutes','')::integer,0) else 0 end),0)::integer
  into v_used,v_used_heavy
  from atlas.execution_leases l
  join lateral (
    select x.resulting_state from atlas.execution_lease_events x where x.lease_id=l.id order by x.occurred_at desc,x.id desc limit 1
  ) e on true
  where l.organization_id=v_org_id and l.recipient_kind='farm_membership' and l.recipient_id=p_membership_id
    and l.shadow_only=false and l.lease_start<v_end and l.lease_end>v_start;

  if v_used+greatest(coalesce(v_cp.expected_active_minutes,0),0)>v_target
     or (v_cp.physical_load='heavy' and v_used_heavy+greatest(coalesce(v_cp.expected_active_minutes,0),0)>v_heavy_cap) then
    raise exception 'Replacement task does not fit remaining Worker Day execution capacity.' using errcode='23514';
  end if;

  return atlas.grant_execution_lease_v1(
    'worker_day_live:'||p_membership_id::text||':'||p_day::text||':task:'||p_task_id::text,
    'work_execution','organization',v_org_id,null,'farm_membership',p_membership_id,
    'task',p_task_id,'task',p_task_id,v_task.title,v_start,v_end,
    'worker_day_replacement_admission_warrant_v1',
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

grant execute on function atlas.grant_worker_day_replacement_execution_lease_v1(uuid,uuid,date,uuid,text) to authenticated,service_role;
revoke execute on function atlas.grant_worker_day_replacement_execution_lease_v1(uuid,uuid,date,uuid,text) from public,anon;

-- Current-day bundle v2 is replaced once more only to expire old nonterminal
-- leases before opening a new day. The rest of the lease-mode contract remains
-- identical to migration 20260831225100.
create or replace function atlas.worker_self_day_bundle_api_v2(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_timezone text:='America/Chicago';
  v_today date;
  v_day_start timestamptz;
  v_plan jsonb;
  v_task_ids uuid[]:=array[]::uuid[];
  v_cards jsonb:='[]'::jsonb;
  v_safe_cards jsonb:='[]'::jsonb;
  v_packet jsonb;
  v_reconciliation jsonb;
begin
  if auth.uid() is null then raise exception 'Authenticated user required.' using errcode='42501'; end if;
  if p_day is null then raise exception 'A worker day is required.' using errcode='22023'; end if;
  if not exists(select 1 from atlas.farm_memberships m where m.id=p_membership_id and m.farm_id=p_farm_id and m.user_id=auth.uid() and m.active=true and m.role='farm_hand') then
    raise exception 'The Farm Hand Worker Day bundle may only be read by that active Farm Hand.' using errcode='42501';
  end if;

  select coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago') into v_timezone from atlas.farms f where f.id=p_farm_id;
  v_today:=(now() at time zone coalesce(v_timezone,'America/Chicago'))::date;
  if p_day<>v_today then return atlas.worker_self_day_bundle_api_v1(p_farm_id,p_membership_id,p_day); end if;
  v_day_start:=p_day::timestamp at time zone v_timezone;

  perform atlas.expire_worker_execution_leases_before_v1(p_farm_id,p_membership_id,v_day_start,auth.uid());
  v_packet:=atlas.worker_day_live_execution_lease_packet_v1(p_farm_id,p_membership_id,p_day);
  if not coalesce((v_packet->>'liveLeaseMode')::boolean,false) then
    v_packet:=atlas.open_worker_day_execution_leases_v1(p_farm_id,p_membership_id,p_day,'Worker opened current Worker Day.',auth.uid());
  end if;
  v_reconciliation:=atlas.reconcile_worker_day_execution_leases_v1(p_farm_id,p_membership_id,p_day,auth.uid());
  v_plan:=atlas.worker_day_feed_plan_live_v1(p_farm_id,p_membership_id,p_day)||jsonb_build_object('clockTimeline',null,'suggestions','[]'::jsonb);

  select coalesce(array_agg(distinct x.task_id) filter(where x.task_id is not null),array[]::uuid[])
  into v_task_ids
  from (
    select nullif(row->>'taskId','')::uuid task_id
    from jsonb_array_elements(coalesce(v_plan->'realWork','[]'::jsonb)||coalesce(v_plan->'automaticWork','[]'::jsonb)) row
  ) x;
  v_cards:=atlas.worker_day_operational_task_cards_v3(p_farm_id,p_membership_id,p_day,v_task_ids);
  select coalesce(jsonb_agg(card-'move_context' order by ord),'[]'::jsonb) into v_safe_cards
  from jsonb_array_elements(v_cards) with ordinality as cards(card,ord);

  return jsonb_build_object('contractVersion','worker_self_day_bundle_execution_lease_v1','plan',v_plan,'taskCards',v_safe_cards,
    'executionLeaseReconciliation',v_reconciliation,
    'trustBoundary',jsonb_build_object('dayOpeningCreatesLeases',true,'feedReadsLeases',true,'doneAuthorityReadsSameLease',true,
      'interruptedLeaseRemainsVisible',true,'priorDayLeasesExpireBeforeNewDay',true));
end;
$$;

COMMIT;
