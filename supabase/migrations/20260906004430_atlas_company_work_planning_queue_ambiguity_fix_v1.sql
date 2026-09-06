create or replace function atlas.organization_owner_company_work_planning_queue_api_v1(
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
  open_conflicts bigint
)
language plpgsql stable security definer
set search_path='pg_catalog','atlas','auth'
as $$
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if not atlas.is_organization_owner(p_organization_id) then raise exception 'Organization owner authority required.' using errcode='42501'; end if;
  return query
  select wi.id,wi.title,wi.operation_class,wi.work_state,
    case when wa.id is null then 'unassigned' else 'assigned' end,
    wa.assignee_membership_id,om.user_id,wa.id,
    case
      when wa.id is null then 'unassigned'
      when ep.id is null then 'assigned_unscheduled'
      when ep.plan_state='needs_replan' then 'needs_replan'
      else 'scheduled'
    end,
    ep.planned_service_date,ep.exposure_service_date,ep.first_planned_service_date,coalesce(ep.rollover_count,0),
    tc.preferred_end_at,coalesce(tc.hard_finish_at,tc.latest_lawful_at),wi.result_contract_key,
    coalesce(pc.open_conflicts,0)
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
  where wi.organization_id=p_organization_id and wi.work_state='open'
    and (p_window_start is null or coalesce(ep.exposure_service_date,(tc.preferred_end_at at time zone 'UTC')::date,(tc.hard_finish_at at time zone 'UTC')::date)>=p_window_start)
    and (p_window_end is null or coalesce(ep.exposure_service_date,(tc.preferred_end_at at time zone 'UTC')::date,(tc.hard_finish_at at time zone 'UTC')::date)<=p_window_end)
  order by case when wa.id is null then 0 when ep.id is null then 1 when ep.plan_state='needs_replan' then 2 else 3 end,
           coalesce(ep.exposure_service_date,(tc.preferred_end_at at time zone 'UTC')::date,(tc.hard_finish_at at time zone 'UTC')::date) nulls last,
           wi.created_at,wi.id;
end;
$$;

create or replace function atlas.organization_owner_company_work_planning_queue_api_v2(
  p_organization_id uuid,
  p_window_start date default null,
  p_window_end date default null
) returns table(
  work_item_id uuid,title text,operation_class text,work_state text,
  responsibility_state text,responsible_membership_id uuid,responsible_user_id uuid,allocation_id uuid,
  planning_state text,planned_service_date date,exposure_service_date date,first_planned_service_date date,rollover_count integer,
  next_target_at timestamptz,hard_finish_at timestamptz,result_contract_key text,open_conflicts bigint,
  latest_result_kind text,latest_result_at timestamptz,latest_result_payload jsonb,attention_state text
)
language plpgsql stable security definer
set search_path='pg_catalog','atlas','auth'
as $$
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if not atlas.is_organization_owner(p_organization_id) then raise exception 'Organization owner authority required.' using errcode='42501'; end if;
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
  where wi.organization_id=p_organization_id and wi.work_state='open'
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