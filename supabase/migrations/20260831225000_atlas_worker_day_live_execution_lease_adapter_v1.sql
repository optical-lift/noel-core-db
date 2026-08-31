BEGIN;

-- Worker Day live Execution Lease adapter v1.
--
-- Trust boundary:
--   * planning is advisory;
--   * eligibility/readiness/operation identity are evaluated before capacity;
--   * opening a Worker Day atomically grants item-level live leases;
--   * once any live lease exists for the day, planner recomputation cannot add,
--     remove, or rewrite the human handoff;
--   * current-day shadow leases may be promoted once during cutover so a release
--     does not silently replan work already handed to a human.

create or replace function atlas.worker_day_lease_candidate_selection_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date
)
returns table(
  task_id uuid,
  planner_rank bigint,
  planner_reason text,
  admission_rank integer,
  admission_reason text,
  expected_active_minutes integer,
  physical_load text,
  readiness jsonb,
  operation_fit jsonb
)
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_capacity jsonb;
  v_capacity_known boolean;
  v_capacity_class text;
  v_target integer := 0;
  v_heavy_cap integer := 0;
  v_used integer := 0;
  v_used_heavy integer := 0;
  v_rank integer := 0;
  v_member atlas.farm_memberships%rowtype;
  v_rec record;
  v_readiness jsonb;
  v_fit jsonb;
  v_minutes integer;
  v_heavy integer;
  v_placed boolean;
  v_assignment boolean;
begin
  if p_day is null then
    raise exception 'Worker Day lease candidate selection requires a service date.' using errcode='22023';
  end if;

  select * into v_member
  from atlas.farm_memberships fm
  where fm.id=p_membership_id
    and fm.farm_id=p_farm_id
    and fm.active=true;
  if v_member.id is null then
    raise exception 'Active worker membership required.' using errcode='42501';
  end if;

  if not atlas.worker_day_available_v1(p_farm_id,p_membership_id,p_day) then
    return;
  end if;

  v_capacity:=atlas.worker_week_day_capacity_v1(p_farm_id,p_membership_id,p_day);
  v_capacity_known:=coalesce((v_capacity->>'capacityKnown')::boolean,false);
  if not v_capacity_known then
    raise exception 'Worker Day capacity must be known before execution leases can be granted.' using errcode='23514';
  end if;

  v_capacity_class:=coalesce(v_capacity->>'capacityClass','none');
  v_target:=case
    when v_capacity_class in ('recovery','explicit_override')
      then greatest(coalesce((v_capacity->>'recoveryCapacityMinutes')::integer,0),0)
    else greatest(coalesce((v_capacity->>'plannedCapacityMinutes')::integer,0),0)
  end;
  v_heavy_cap:=greatest(least(coalesce((v_capacity->>'heavyMinutesSoftCap')::integer,v_target),greatest(v_target,0)),0);

  for v_rec in
    select
      s.task_id,
      s.selection_rank,
      s.presentation_state,
      s.presentation_reason,
      s.work_lane,
      s.commitment_kind,
      t.*,
      cp.expected_active_minutes as cap_minutes,
      cp.physical_load as cap_load,
      exists(
        select 1
        from atlas.worker_day_task_placements p
        where p.farm_id=p_farm_id
          and p.membership_id=p_membership_id
          and p.service_date=p_day
          and p.task_id=s.task_id
          and p.state='placed'
      ) as placed_today
    from atlas.presented_work_selection_rows_v3(p_farm_id,p_membership_id,p_day) s
    join atlas.tasks t on t.id=s.task_id
    cross join lateral atlas.task_capacity_plan_v1(t,p_day) cp
    order by s.selection_rank,s.task_id
  loop
    if v_rec.status<>'open' then
      continue;
    end if;

    v_assignment :=
      v_rec.assigned_membership_id=p_membership_id
      or v_rec.assigned_user_id=v_member.user_id
      or v_rec.metadata->>'executor_membership_id'=p_membership_id::text
      or (
        nullif(lower(btrim(v_member.worker_key)),'') is not null
        and lower(coalesce(
          nullif(v_rec.metadata->>'executor_worker_key',''),
          nullif(v_rec.metadata->>'assignee_key',''),
          nullif(v_rec.metadata->>'assigned_to',''),
          nullif(v_rec.metadata->>'work_route','')
        ))=nullif(lower(btrim(v_member.worker_key)),'')
      );
    if not v_assignment then
      continue;
    end if;

    -- The existing planner remains the ordering/advisory source, but temporal
    -- holds and other-day commitments do not enter today's lease candidate pool.
    if not v_rec.placed_today and coalesce(v_rec.presentation_reason,'') in (
      'future','committed_other_day','consequence_resolution_required'
    ) then
      continue;
    end if;

    v_readiness:=atlas.task_execution_readiness_v1(v_rec.task_id);
    v_fit:=atlas.task_operation_fit_warrant_v1(v_rec.task_id);
    if not coalesce((v_readiness->>'executionReady')::boolean,false)
       or not coalesce((v_fit->>'exactIdentitySupported')::boolean,false) then
      continue;
    end if;

    v_minutes:=greatest(coalesce(v_rec.cap_minutes,0),0);
    v_heavy:=case when v_rec.cap_load='heavy' then v_minutes else 0 end;

    -- Explicit placement is already a human-authored commitment and therefore
    -- survives capacity calculation. Automatically selected work must fit.
    if not v_rec.placed_today then
      if v_used+v_minutes>v_target then
        continue;
      end if;
      if v_used_heavy+v_heavy>v_heavy_cap then
        continue;
      end if;
    end if;

    v_rank:=v_rank+1;
    v_used:=v_used+v_minutes;
    v_used_heavy:=v_used_heavy+v_heavy;

    task_id:=v_rec.task_id;
    planner_rank:=v_rec.selection_rank;
    planner_reason:=v_rec.presentation_reason;
    admission_rank:=v_rank;
    admission_reason:=case
      when v_rec.placed_today then 'explicit_placement_after_execution_warrant'
      when v_rec.presentation_state='held' then 'eligibility_backfill_after_capacity'
      else 'eligibility_before_capacity'
    end;
    expected_active_minutes:=v_minutes;
    physical_load:=v_rec.cap_load;
    readiness:=v_readiness;
    operation_fit:=v_fit;
    return next;
  end loop;
end;
$$;

comment on function atlas.worker_day_lease_candidate_selection_v1(uuid,uuid,date) is
  'Worker Day lease admission planner. Uses existing planner ordering only as advice, then requires current execution readiness + exact operation identity before consuming capacity. Invalid candidates cannot steal human-day capacity.';

revoke all on function atlas.worker_day_lease_candidate_selection_v1(uuid,uuid,date) from public,anon,authenticated;
grant execute on function atlas.worker_day_lease_candidate_selection_v1(uuid,uuid,date) to service_role;

create or replace function atlas.worker_day_live_execution_lease_packet_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_org_id uuid;
  v_timezone text;
  v_start timestamptz;
  v_end timestamptz;
  v_leases jsonb;
  v_count integer;
begin
  select f.organization_id,coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
    into v_org_id,v_timezone
  from atlas.farm_memberships fm
  join atlas.farms f on f.id=fm.farm_id
  where fm.id=p_membership_id and fm.farm_id=p_farm_id and fm.active=true;
  if v_org_id is null then
    raise exception 'Active worker membership required.' using errcode='42501';
  end if;

  v_start:=p_day::timestamp at time zone v_timezone;
  v_end:=(p_day+1)::timestamp at time zone v_timezone;

  select
    coalesce(jsonb_agg(jsonb_build_object(
      'leaseId',l.id,
      'leaseKey',l.lease_key,
      'executionKind',l.execution_kind,
      'executionId',l.execution_id,
      'title',l.title_snapshot,
      'leaseStart',l.lease_start,
      'leaseEnd',l.lease_end,
      'state',e.resulting_state,
      'actionable',e.resulting_state in ('leased','started'),
      'interrupted',e.resulting_state='interrupted',
      'terminal',e.resulting_state in ('completed','withdrawn','expired'),
      'lastEventKind',e.event_kind,
      'lastEventReason',e.reason,
      'lastEventAt',e.occurred_at,
      'admissionWarrant',l.admission_warrant,
      'metadata',l.metadata
    ) order by l.created_at,l.id),'[]'::jsonb),
    count(*)::integer
  into v_leases,v_count
  from atlas.execution_leases l
  join lateral (
    select x.event_kind,x.resulting_state,x.reason,x.occurred_at
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
    and l.lease_start<v_end
    and l.lease_end>v_start;

  return jsonb_build_object(
    'contractVersion','worker_day_live_execution_lease_packet_v1',
    'farmId',p_farm_id,
    'membershipId',p_membership_id,
    'serviceDate',p_day,
    'liveLeaseMode',coalesce(v_count,0)>0,
    'leaseCount',coalesce(v_count,0),
    'leases',v_leases,
    'truthBoundary',jsonb_build_object(
      'plannerIsAdvisory',true,
      'leaseIsExecutionAuthority',true,
      'leaseRemovalRequiresEvent',true
    )
  );
end;
$$;

revoke all on function atlas.worker_day_live_execution_lease_packet_v1(uuid,uuid,date) from public,anon,authenticated;
grant execute on function atlas.worker_day_live_execution_lease_packet_v1(uuid,uuid,date) to service_role;

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
  v_state text;
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
  if v_org_id is null then
    raise exception 'Active worker membership required.' using errcode='42501';
  end if;

  v_start:=p_day::timestamp at time zone v_timezone;
  v_end:=(p_day+1)::timestamp at time zone v_timezone;
  perform pg_advisory_xact_lock(hashtextextended('worker-day-live-lease:'||p_farm_id::text||':'||p_membership_id::text||':'||p_day::text,0));

  v_existing:=atlas.worker_day_live_execution_lease_packet_v1(p_farm_id,p_membership_id,p_day);
  if coalesce((v_existing->>'liveLeaseMode')::boolean,false) then
    return v_existing || jsonb_build_object(
      'state','already_open',
      'openingSource','existing_live_leases',
      'grantResults','[]'::jsonb
    );
  end if;

  select count(*)::integer into v_shadow_count
  from atlas.execution_leases l
  where l.custody_kind='organization'
    and l.organization_id=v_org_id
    and l.recipient_kind='farm_membership'
    and l.recipient_id=p_membership_id
    and l.lease_kind='work_execution'
    and l.shadow_only=true
    and l.lease_start<v_end
    and l.lease_end>v_start
    and l.metadata->>'farmId'=p_farm_id::text
    and l.metadata->>'serviceDate'=p_day::text;

  if v_shadow_count>0 then
    v_source:='frozen_shadow_promise';
    for v_rec in
      select l.*,e.resulting_state as current_state
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
        and l.shadow_only=true
        and l.lease_start<v_end
        and l.lease_end>v_start
        and l.metadata->>'farmId'=p_farm_id::text
        and l.metadata->>'serviceDate'=p_day::text
        and e.resulting_state not in ('withdrawn','expired')
      order by l.created_at,l.id
    loop
      v_grant:=atlas.grant_execution_lease_v1(
        'worker_day_live:'||p_membership_id::text||':'||p_day::text||':'||v_rec.execution_kind||':'||v_rec.execution_id::text,
        'work_execution','organization',v_org_id,null,
        'farm_membership',p_membership_id,
        v_rec.obligation_kind,v_rec.obligation_id,
        v_rec.execution_kind,v_rec.execution_id,v_rec.title_snapshot,
        v_start,v_end,
        'worker_day_shadow_promise_promotion_v1',
        jsonb_build_object(
          'authorized',true,
          'historicalHandoff',true,
          'shadowLeaseId',v_rec.id,
          'shadowAdmissionWarrant',v_rec.admission_warrant
        ),
        p_reason,'execution_lease_shadow_promotion',v_rec.id,p_actor_user_id,false,
        coalesce(v_rec.metadata,'{}'::jsonb)||jsonb_build_object(
          'shadowLeaseId',v_rec.id,
          'promotedToLiveAt',now(),
          'shadowOnly',false,
          'doesDrivePresentation',true
        )
      );
      v_grants:=v_grants||jsonb_build_array(v_grant);

      if v_rec.current_state='interrupted' then
        perform atlas.transition_execution_lease_v1(
          (v_grant->>'leaseId')::uuid,
          'shadow-promotion-interrupted:'||v_rec.id::text,
          'interrupted','Promoted historical handoff was already interrupted.',
          'execution_lease_shadow_promotion',v_rec.id,p_actor_user_id,
          jsonb_build_object('shadowLeaseState','interrupted'),'{}'::jsonb,now()
        );
      elsif v_rec.current_state='completed' then
        perform atlas.transition_execution_lease_v1(
          (v_grant->>'leaseId')::uuid,
          'shadow-promotion-completed:'||v_rec.id::text,
          'completed','Promoted historical handoff was already completed.',
          'execution_lease_shadow_promotion',v_rec.id,p_actor_user_id,
          jsonb_build_object('shadowLeaseState','completed'),'{}'::jsonb,now()
        );
      end if;
    end loop;
  else
    v_source:='eligibility_before_capacity';
    for v_rec in
      select *
      from atlas.worker_day_lease_candidate_selection_v1(p_farm_id,p_membership_id,p_day)
      order by admission_rank,task_id
    loop
      v_grant:=atlas.grant_execution_lease_v1(
        'worker_day_live:'||p_membership_id::text||':'||p_day::text||':task:'||v_rec.task_id::text,
        'work_execution','organization',v_org_id,null,
        'task',v_rec.task_id,
        'task',v_rec.task_id,
        (select t.title from atlas.tasks t where t.id=v_rec.task_id),
        v_start,v_end,
        'worker_day_lease_admission_warrant_v1',
        jsonb_build_object(
          'authorized',true,
          'executionReadiness',v_rec.readiness,
          'operationFit',v_rec.operation_fit,
          'plannerRank',v_rec.planner_rank,
          'plannerReason',v_rec.planner_reason,
          'admissionRank',v_rec.admission_rank,
          'admissionReason',v_rec.admission_reason
        ),
        p_reason,'worker_day_lease_admission_v1',null,p_actor_user_id,false,
        jsonb_build_object(
          'farmId',p_farm_id,
          'serviceDate',p_day,
          'timezone',v_timezone,
          'plannerRank',v_rec.planner_rank,
          'plannerReason',v_rec.planner_reason,
          'admissionRank',v_rec.admission_rank,
          'admissionReason',v_rec.admission_reason,
          'expectedActiveMinutes',v_rec.expected_active_minutes,
          'physicalLoad',v_rec.physical_load,
          'shadowOnly',false,
          'doesDrivePresentation',true
        )
      );
      v_grants:=v_grants||jsonb_build_array(v_grant);
    end loop;
  end if;

  return atlas.worker_day_live_execution_lease_packet_v1(p_farm_id,p_membership_id,p_day)
    || jsonb_build_object(
      'state','opened',
      'openingSource',v_source,
      'grantResults',v_grants,
      'truthBoundary',jsonb_build_object(
        'plannerIsAdvisory',true,
        'openingIsAtomicHumanHandoff',true,
        'laterPlannerRecomputeCannotChangeLeaseSet',true
      )
    );
end;
$$;

comment on function atlas.open_worker_day_execution_leases_v1(uuid,uuid,date,text,uuid) is
  'Atomically opens one Worker Day by granting live item-level execution leases. Existing shadow promises are promoted without replanning during cutover; otherwise eligibility/identity are evaluated before capacity.';

revoke all on function atlas.open_worker_day_execution_leases_v1(uuid,uuid,date,text,uuid) from public,anon,authenticated;
grant execute on function atlas.open_worker_day_execution_leases_v1(uuid,uuid,date,text,uuid) to service_role;

create or replace function atlas.reconcile_worker_day_execution_leases_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date,
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
  v_rec record;
  v_readiness jsonb;
  v_fit jsonb;
  v_reason text;
  v_events jsonb:='[]'::jsonb;
  v_candidates jsonb;
  v_proposal jsonb;
begin
  select f.organization_id,coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
    into v_org_id,v_timezone
  from atlas.farm_memberships fm
  join atlas.farms f on f.id=fm.farm_id
  where fm.id=p_membership_id and fm.farm_id=p_farm_id and fm.active=true;
  if v_org_id is null then
    raise exception 'Active worker membership required.' using errcode='42501';
  end if;

  v_start:=p_day::timestamp at time zone v_timezone;
  v_end:=(p_day+1)::timestamp at time zone v_timezone;

  for v_rec in
    select l.*,e.resulting_state as current_state
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
      and l.lease_start<v_end and l.lease_end>v_start
      and e.resulting_state not in ('completed','withdrawn','expired')
    order by l.created_at,l.id
  loop
    if v_rec.execution_kind<>'task' then
      continue;
    end if;

    if exists(select 1 from atlas.tasks t where t.id=v_rec.execution_id and t.status='done') then
      v_events:=v_events||jsonb_build_array(atlas.transition_execution_lease_v1(
        v_rec.id,'task-done-reconcile:'||v_rec.execution_id::text,
        'completed','Underlying execution is already complete.',
        'worker_day_lease_reconciliation',v_rec.execution_id,p_actor_user_id,
        jsonb_build_object('taskStatus','done'),'{}'::jsonb,now()
      ));
      continue;
    end if;

    v_readiness:=atlas.task_execution_readiness_v1(v_rec.execution_id);
    v_fit:=atlas.task_operation_fit_warrant_v1(v_rec.execution_id);

    if v_rec.current_state in ('leased','started')
       and (
         not coalesce((v_readiness->>'executionReady')::boolean,false)
         or not coalesce((v_fit->>'exactIdentitySupported')::boolean,false)
         or not exists(select 1 from atlas.tasks t where t.id=v_rec.execution_id and t.status='open')
       ) then
      v_reason:=case
        when not exists(select 1 from atlas.tasks t where t.id=v_rec.execution_id and t.status='open') then 'Underlying obligation is no longer open.'
        when not coalesce((v_readiness->>'executionReady')::boolean,false) then 'Current execution requirements are no longer satisfied.'
        else 'Current operation identity is no longer supported.'
      end;
      v_events:=v_events||jsonb_build_array(atlas.transition_execution_lease_v1(
        v_rec.id,
        'reality-interruption:'||md5(coalesce(v_readiness::text,'')||coalesce(v_fit::text,'')||v_reason),
        'interrupted',v_reason,
        'worker_day_lease_reconciliation',v_rec.execution_id,p_actor_user_id,
        jsonb_build_object('executionReadiness',v_readiness,'operationFit',v_fit),
        jsonb_build_object('automaticInterruption',true,'automaticResume',false),now()
      ));
    end if;
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object(
    'executionKind','task',
    'executionId',c.task_id,
    'title',t.title,
    'plannerRank',c.planner_rank,
    'plannerReason',c.planner_reason,
    'admissionRank',c.admission_rank,
    'admissionReason',c.admission_reason
  ) order by c.admission_rank,c.task_id),'[]'::jsonb)
  into v_candidates
  from atlas.worker_day_lease_candidate_selection_v1(p_farm_id,p_membership_id,p_day) c
  join atlas.tasks t on t.id=c.task_id;

  v_proposal:=atlas.execution_lease_reconciliation_proposal_v1(
    'organization',v_org_id,null,'farm_membership',p_membership_id,
    v_start,v_end,v_candidates
  );

  return atlas.worker_day_live_execution_lease_packet_v1(p_farm_id,p_membership_id,p_day)
    || jsonb_build_object(
      'reconciliationEvents',v_events,
      'plannerProposal',v_proposal,
      'truthBoundary',jsonb_build_object(
        'realityLossMayInterruptLease',true,
        'interruptedLeaseRemainsHistoricalHandoff',true,
        'plannerProposalHasNoMutationAuthority',true,
        'interruptedLeaseNeverAutoResumes',true,
        'replacementRequiresExplicitGrant',true
      )
    );
end;
$$;

revoke all on function atlas.reconcile_worker_day_execution_leases_v1(uuid,uuid,date,uuid) from public,anon,authenticated;
grant execute on function atlas.reconcile_worker_day_execution_leases_v1(uuid,uuid,date,uuid) to service_role;

COMMIT;
