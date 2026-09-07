create or replace function atlas.can_schedule_company_work_v1(
  p_work_item_id uuid
) returns boolean
language sql stable security definer
set search_path='pg_catalog','atlas','auth'
as $$
  select exists(
    select 1
    from atlas.work_items wi
    where wi.id=p_work_item_id
      and (
        atlas.is_organization_owner(wi.organization_id)
        or (
          exists(
            select 1
            from atlas.organization_memberships om
            where om.organization_id=wi.organization_id
              and om.user_id=auth.uid()
              and om.active
          )
          and exists(
            select 1
            from atlas.work_execution_adapters a
            join atlas.planned_work_occurrences pwo on pwo.id=a.planned_occurrence_id
            join atlas.farms f on f.id=pwo.farm_id
            join atlas.farm_memberships fm on fm.farm_id=f.id
            where a.work_item_id=wi.id
              and a.organization_id=wi.organization_id
              and a.state='active'
              and f.organization_id=wi.organization_id
              and fm.user_id=auth.uid()
              and fm.active
              and fm.role in ('owner','manager')
          )
        )
      )
  )
$$;

create or replace function atlas.company_work_planning_actor_membership_v1(
  p_work_item_id uuid
) returns uuid
language sql stable security definer
set search_path='pg_catalog','atlas','auth'
as $$
  select om.id
  from atlas.work_items wi
  join atlas.organization_memberships om
    on om.organization_id=wi.organization_id
   and om.user_id=auth.uid()
   and om.active
  where wi.id=p_work_item_id
    and atlas.can_schedule_company_work_v1(wi.id)
  order by case when om.role='owner' then 0 else 1 end,om.created_at,om.id
  limit 1
$$;

create or replace function atlas.organization_management_company_work_planning_queue_api_v1(
  p_organization_id uuid,
  p_window_start date default null,
  p_window_end date default null
) returns table(
  work_item_id uuid,
  title text,
  operation_class text,
  work_state text,
  responsibility_state text,
  responsible_membership_id uuid,
  responsible_user_id uuid,
  allocation_id uuid,
  planning_state text,
  planned_service_date date,
  exposure_service_date date,
  first_planned_service_date date,
  rollover_count integer,
  next_target_at timestamptz,
  hard_finish_at timestamptz,
  result_contract_key text,
  open_conflicts bigint,
  latest_result_kind text,
  latest_result_at timestamptz,
  latest_result_payload jsonb,
  attention_state text
)
language plpgsql stable security definer
set search_path='pg_catalog','atlas','auth'
as $$
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if not exists(
    select 1
    from atlas.organization_memberships om
    where om.organization_id=p_organization_id
      and om.user_id=auth.uid()
      and om.active
  ) then
    raise exception 'Active organization membership required.' using errcode='42501';
  end if;
  if not atlas.is_organization_owner(p_organization_id)
     and not exists(
       select 1
       from atlas.farms f
       join atlas.farm_memberships fm on fm.farm_id=f.id
       where f.organization_id=p_organization_id
         and fm.user_id=auth.uid()
         and fm.active
         and fm.role in ('owner','manager')
     ) then
    raise exception 'Company Work scheduling authority required.' using errcode='42501';
  end if;

  return query
  select wi.id,wi.title,wi.operation_class,wi.work_state,
    case when wa.id is null then 'unassigned' else 'assigned' end,
    wa.assignee_membership_id,om.user_id,wa.id,
    case when wa.id is null then 'unassigned' when ep.id is null then 'assigned_unscheduled' when ep.plan_state='needs_replan' then 'needs_replan' else 'scheduled' end,
    ep.planned_service_date,ep.exposure_service_date,ep.first_planned_service_date,coalesce(ep.rollover_count,0),
    tc.preferred_end_at,coalesce(tc.hard_finish_at,tc.latest_lawful_at),wi.result_contract_key,coalesce(pc.open_conflicts,0),
    lr.result_kind,lr.reported_at,lr.payload,
    case
      when lr.result_kind in ('blocked','unable') then 'worker_exception'
      when ep.plan_state='needs_replan' then 'needs_replan'
      when wa.id is null then 'needs_responsibility'
      when ep.id is null then 'needs_schedule'
      else 'none'
    end
  from atlas.work_items wi
  left join atlas.work_allocations wa on wa.organization_id=wi.organization_id and wa.work_item_id=wi.id and wa.state='active' and wa.allocation_role='responsible'
  left join atlas.organization_memberships om on om.id=wa.assignee_membership_id
  left join atlas.work_execution_plans ep on ep.organization_id=wi.organization_id and ep.work_item_id=wi.id and ep.plan_state in ('active','needs_replan')
  left join lateral(
    select x.preferred_end_at as preferred_end_at,x.hard_finish_at as hard_finish_at,x.latest_lawful_at as latest_lawful_at
    from atlas.work_time_contracts x
    where x.organization_id=wi.organization_id and x.work_item_id=wi.id and x.contract_state='active'
    order by x.created_at desc limit 1
  ) tc on true
  left join lateral(
    select count(*) as open_conflicts from atlas.work_planning_conflicts c
    where c.organization_id=wi.organization_id and c.work_item_id=wi.id and c.state='open'
  ) pc on true
  left join lateral(
    select r.result_kind as result_kind,r.reported_at as reported_at,r.payload as payload
    from atlas.work_execution_results r
    where r.organization_id=wi.organization_id and r.work_item_id=wi.id
    order by r.reported_at desc,r.id desc limit 1
  ) lr on true
  where wi.organization_id=p_organization_id
    and wi.work_state='open'
    and (
      atlas.is_organization_owner(p_organization_id)
      or atlas.can_schedule_company_work_v1(wi.id)
    )
    and (p_window_start is null or coalesce(ep.exposure_service_date,(tc.preferred_end_at at time zone 'UTC')::date,(tc.hard_finish_at at time zone 'UTC')::date)>=p_window_start)
    and (p_window_end is null or coalesce(ep.exposure_service_date,(tc.preferred_end_at at time zone 'UTC')::date,(tc.hard_finish_at at time zone 'UTC')::date)<=p_window_end)
  order by case
      when lr.result_kind in ('blocked','unable') then 0
      when wa.id is null then 1
      when ep.id is null then 2
      when ep.plan_state='needs_replan' then 3
      else 4
    end,
    coalesce(ep.exposure_service_date,(tc.preferred_end_at at time zone 'UTC')::date,(tc.hard_finish_at at time zone 'UTC')::date) nulls last,
    wi.created_at,wi.id;
end;
$$;

create or replace function atlas.organization_management_plan_company_work_week_api_v1(
  p_organization_id uuid,
  p_week_start date,
  p_plans jsonb
) returns jsonb
language plpgsql security definer
set search_path='pg_catalog','atlas','auth'
as $$
declare
  v_entry jsonb;
  v_work_id uuid;
  v_day date;
  v_actor uuid;
  v_results jsonb:='[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_week_start is null or p_week_start<>date_trunc('week',p_week_start::timestamp)::date then
    raise exception 'Week start must be a Monday.' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_plans,'[]'::jsonb))<>'array' then raise exception 'Plans must be an array.' using errcode='22023'; end if;
  if jsonb_array_length(coalesce(p_plans,'[]'::jsonb))>100 then raise exception 'Too many weekly plan entries.' using errcode='22023'; end if;

  for v_entry in select value from jsonb_array_elements(coalesce(p_plans,'[]'::jsonb)) loop
    begin v_work_id:=(v_entry->>'workItemId')::uuid; exception when others then raise exception 'Each plan needs a valid workItemId.' using errcode='22023'; end;
    begin v_day:=(v_entry->>'serviceDate')::date; exception when others then raise exception 'Each plan needs a valid serviceDate.' using errcode='22023'; end;
    if v_day<p_week_start or v_day>p_week_start+6 then raise exception 'Every planned day must fall inside the supplied week.' using errcode='22023'; end if;
    if not exists(select 1 from atlas.work_items where id=v_work_id and organization_id=p_organization_id) then
      raise exception 'A weekly plan entry belongs to another organization.' using errcode='42501';
    end if;
    if not atlas.can_schedule_company_work_v1(v_work_id) then
      raise exception 'Company Work scheduling authority required for this Work item.' using errcode='42501';
    end if;
    v_actor:=atlas.company_work_planning_actor_membership_v1(v_work_id);
    if v_actor is null then raise exception 'An active organization membership is required to record the manager plan.' using errcode='42501'; end if;

    v_results:=v_results||jsonb_build_array(atlas.set_company_work_execution_plan_internal_v1(
      v_work_id,v_day,v_actor,v_entry->>'reason',jsonb_build_object(
        'source','organization_management_plan_company_work_week_api_v1',
        'weekStart',p_week_start,
        'actorUserId',auth.uid(),
        'authority',case when atlas.is_organization_owner(p_organization_id) then 'organization_owner' else 'farm_manager' end
      )
    ));
  end loop;
  return jsonb_build_object('contractVersion','organization_management_plan_company_work_week_api_v1','organizationId',p_organization_id,'weekStart',p_week_start,'plans',v_results);
end;
$$;

create or replace function atlas.organization_management_clear_company_work_plan_api_v1(
  p_work_item_id uuid,
  p_reason text default null
) returns jsonb
language plpgsql security definer
set search_path='pg_catalog','atlas','auth'
as $$
declare
  v_work atlas.work_items%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
  v_actor uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_work from atlas.work_items where id=p_work_item_id;
  if v_work.id is null then raise exception 'Company Work item was not found.' using errcode='P0002'; end if;
  if not atlas.can_schedule_company_work_v1(v_work.id) then
    raise exception 'Company Work scheduling authority required for this Work item.' using errcode='42501';
  end if;
  v_actor:=atlas.company_work_planning_actor_membership_v1(v_work.id);
  if v_actor is null then raise exception 'An active organization membership is required to record the manager plan.' using errcode='42501'; end if;

  select * into v_plan from atlas.work_execution_plans where work_item_id=v_work.id and plan_state in ('active','needs_replan') limit 1 for update;
  if v_plan.id is null then return jsonb_build_object('state','already_unplanned','workItemId',v_work.id); end if;
  update atlas.work_execution_plans set plan_state='withdrawn',plan_reason=coalesce(nullif(btrim(p_reason),''),'manager_unplanned') where id=v_plan.id;
  insert into atlas.work_execution_plan_events(organization_id,work_item_id,plan_id,event_kind,from_planned_service_date,from_exposure_service_date,actor_membership_id,reason,metadata)
  values(v_plan.organization_id,v_plan.work_item_id,v_plan.id,'withdrawn',v_plan.planned_service_date,v_plan.exposure_service_date,v_actor,p_reason,jsonb_build_object(
    'source','organization_management_clear_company_work_plan_api_v1',
    'actorUserId',auth.uid(),
    'authority',case when atlas.is_organization_owner(v_work.organization_id) then 'organization_owner' else 'farm_manager' end
  ));
  perform atlas.sync_company_work_execution_plan_carrier_v1(v_work.id);
  return jsonb_build_object('state','unplanned','workItemId',v_work.id,'planId',v_plan.id);
end;
$$;

revoke all on function atlas.can_schedule_company_work_v1(uuid) from public;
grant execute on function atlas.can_schedule_company_work_v1(uuid) to authenticated;
revoke all on function atlas.company_work_planning_actor_membership_v1(uuid) from public;
grant execute on function atlas.company_work_planning_actor_membership_v1(uuid) to authenticated;
revoke all on function atlas.organization_management_company_work_planning_queue_api_v1(uuid,date,date) from public;
grant execute on function atlas.organization_management_company_work_planning_queue_api_v1(uuid,date,date) to authenticated;
revoke all on function atlas.organization_management_plan_company_work_week_api_v1(uuid,date,jsonb) from public;
grant execute on function atlas.organization_management_plan_company_work_week_api_v1(uuid,date,jsonb) to authenticated;
revoke all on function atlas.organization_management_clear_company_work_plan_api_v1(uuid,text) from public;
grant execute on function atlas.organization_management_clear_company_work_plan_api_v1(uuid,text) to authenticated;