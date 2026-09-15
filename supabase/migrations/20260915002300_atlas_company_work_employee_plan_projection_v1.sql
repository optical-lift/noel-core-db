begin;

create or replace function atlas.reconcile_company_work_worker_day_projections_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_organization_id uuid,
  p_organization_membership_id uuid,
  p_start_date date,
  p_days integer default 7
)
returns integer
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_end_date date;
  v_plan record;
  v_projection atlas.worker_week_projection%rowtype;
  v_projection_id uuid;
  v_reconciled integer:=0;
begin
  if p_farm_id is null
     or p_membership_id is null
     or p_organization_id is null
     or p_organization_membership_id is null
     or p_start_date is null then
    raise exception 'Farm, delivery membership, organization, organization membership, and start date are required.' using errcode='22023';
  end if;
  if coalesce(p_days,0)<1 or p_days>31 then
    raise exception 'Worker Day range must be between 1 and 31 days.' using errcode='22023';
  end if;
  v_end_date:=p_start_date+p_days-1;

  if not exists (
    select 1
    from atlas.farms f
    join atlas.farm_memberships fm
      on fm.id=p_membership_id
     and fm.farm_id=f.id
     and fm.active
     and fm.role='farm_hand'
     and fm.identity_subject_id is not null
    join atlas.organization_memberships om
      on om.id=p_organization_membership_id
     and om.organization_id=p_organization_id
     and om.user_id=fm.user_id
     and om.identity_subject_id=fm.identity_subject_id
     and om.active
     and om.role='member'
    where f.id=p_farm_id
      and f.organization_id=p_organization_id
  ) then
    raise exception 'Employee delivery context does not match the governed organization relationship.' using errcode='42501';
  end if;

  -- Retire only projections previously established by this canonical plan bridge.
  -- Legacy/unadjudicated Worker Day evidence remains visible until another package
  -- explicitly succeeds it; this function must not erase it by inference.
  delete from atlas.worker_week_projection wp
  where wp.farm_id=p_farm_id
    and wp.membership_id=p_membership_id
    and wp.organization_id=p_organization_id
    and wp.organization_membership_id=p_organization_membership_id
    and wp.planned_date between p_start_date and v_end_date
    and wp.source_kind='work_item'
    and coalesce(wp.delivery_payload->>'projectionAuthority','')='work_execution_plans'
    and not exists (
      select 1
      from atlas.work_execution_plans ep
      join atlas.work_items w
        on w.id=ep.work_item_id
       and w.organization_id=ep.organization_id
       and w.work_state='open'
      where ep.organization_id=p_organization_id
        and ep.work_item_id=wp.source_id
        and ep.assignee_membership_id=p_organization_membership_id
        and ep.plan_state='active'
        and ep.exposure_service_date=wp.planned_date
    );

  for v_plan in
    select ep.id plan_id,
           ep.organization_id,
           ep.work_item_id,
           ep.responsible_allocation_id,
           ep.assignee_membership_id,
           ep.first_planned_service_date,
           ep.planned_service_date,
           ep.exposure_service_date,
           ep.plan_reason,
           ep.metadata plan_metadata,
           w.title
    from atlas.work_execution_plans ep
    join atlas.work_items w
      on w.id=ep.work_item_id
     and w.organization_id=ep.organization_id
     and w.work_state='open'
    join atlas.work_allocations wa
      on wa.id=ep.responsible_allocation_id
     and wa.organization_id=ep.organization_id
     and wa.work_item_id=ep.work_item_id
     and wa.assignee_membership_id=ep.assignee_membership_id
     and wa.allocation_role='responsible'
     and wa.state='active'
    where ep.organization_id=p_organization_id
      and ep.assignee_membership_id=p_organization_membership_id
      and ep.plan_state='active'
      and ep.exposure_service_date between p_start_date and v_end_date
      and (
        exists (
          select 1
          from atlas.worker_week_projection existing_projection
          where existing_projection.farm_id=p_farm_id
            and existing_projection.membership_id=p_membership_id
            and existing_projection.organization_id=p_organization_id
            and existing_projection.organization_membership_id=p_organization_membership_id
            and existing_projection.source_kind='work_item'
            and existing_projection.source_id=ep.work_item_id
        )
        or exists (
          select 1
          from atlas.work_execution_adapters a
          join atlas.tasks t on t.id=a.task_id
          where a.organization_id=ep.organization_id
            and a.work_item_id=ep.work_item_id
            and a.state='active'
            and t.farm_id=p_farm_id
            and t.assigned_membership_id=p_membership_id
        )
        or exists (
          select 1
          from atlas.work_execution_adapters a
          join atlas.worker_day_task_placements placement
            on placement.task_id=a.task_id
           and placement.farm_id=p_farm_id
           and placement.membership_id=p_membership_id
           and placement.state='placed'
           and placement.service_date=ep.exposure_service_date
          where a.organization_id=ep.organization_id
            and a.work_item_id=ep.work_item_id
            and a.state='active'
        )
      )
    order by ep.exposure_service_date,ep.work_item_id
  loop
    v_projection:=null;
    v_projection_id:=null;

    select wp.* into v_projection
    from atlas.worker_week_projection wp
    where wp.farm_id=p_farm_id
      and wp.membership_id=p_membership_id
      and wp.organization_id=p_organization_id
      and wp.organization_membership_id=p_organization_membership_id
      and wp.source_kind='work_item'
      and wp.source_id=v_plan.work_item_id
    order by
      case when wp.planned_date=v_plan.exposure_service_date then 0 else 1 end,
      case when wp.locked then 0 else 1 end,
      wp.created_at,
      wp.id
    limit 1
    for update;

    if v_projection.id is null then
      insert into atlas.worker_week_projection(
        farm_id,membership_id,planned_date,source_kind,source_id,title,
        plan_state,reason,locked,plan_order,
        organization_id,organization_membership_id,original_planned_date,
        rollover_policy,delivery_key,delivery_payload
      ) values(
        p_farm_id,p_membership_id,v_plan.exposure_service_date,'work_item',v_plan.work_item_id,v_plan.title,
        'planned',coalesce(nullif(v_plan.plan_reason,''),'Governed Company Work execution plan.'),true,500,
        p_organization_id,p_organization_membership_id,
        coalesce(v_plan.first_planned_service_date,v_plan.planned_service_date,v_plan.exposure_service_date),
        'carry','company-work:'||v_plan.work_item_id::text,
        jsonb_strip_nulls(jsonb_build_object(
          'projectionAuthority','work_execution_plans',
          'canonicalCompanyWorkProjection',true,
          'managerPlanId',v_plan.plan_id,
          'plannedServiceDate',v_plan.planned_service_date,
          'exposureServiceDate',v_plan.exposure_service_date,
          'source','company_work_employee_plan_projection_v1'
        ))
      )
      returning id into v_projection_id;
    else
      update atlas.worker_week_projection
      set planned_date=v_plan.exposure_service_date,
          title=v_plan.title,
          plan_state='planned',
          reason=coalesce(nullif(v_plan.plan_reason,''),reason,'Governed Company Work execution plan.'),
          locked=true,
          organization_id=p_organization_id,
          organization_membership_id=p_organization_membership_id,
          original_planned_date=coalesce(v_plan.first_planned_service_date,v_plan.planned_service_date,original_planned_date,v_plan.exposure_service_date),
          rollover_policy='carry',
          delivery_key=coalesce(nullif(delivery_key,''),'company-work:'||v_plan.work_item_id::text),
          delivery_payload=coalesce(delivery_payload,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object(
            'projectionAuthority','work_execution_plans',
            'canonicalCompanyWorkProjection',true,
            'managerPlanId',v_plan.plan_id,
            'plannedServiceDate',v_plan.planned_service_date,
            'exposureServiceDate',v_plan.exposure_service_date,
            'source','company_work_employee_plan_projection_v1'
          )),
          updated_at=now()
      where id=v_projection.id
      returning id into v_projection_id;
    end if;

    -- One active Company Work plan owns one required Work identity in the employee projection.
    delete from atlas.worker_week_projection_sources
    where projection_id=v_projection_id
      and source_role='required'
      and work_item_id<>v_plan.work_item_id;

    insert into atlas.worker_week_projection_sources(projection_id,work_item_id,source_role)
    values(v_projection_id,v_plan.work_item_id,'required')
    on conflict(projection_id,work_item_id) do update
      set source_role='required';

    -- Any other projection for the same Company Work/delivery context is stale once
    -- a canonical plan-driven projection has been selected.
    delete from atlas.worker_week_projection duplicate_projection
    where duplicate_projection.farm_id=p_farm_id
      and duplicate_projection.membership_id=p_membership_id
      and duplicate_projection.organization_id=p_organization_id
      and duplicate_projection.organization_membership_id=p_organization_membership_id
      and duplicate_projection.source_kind='work_item'
      and duplicate_projection.source_id=v_plan.work_item_id
      and duplicate_projection.id<>v_projection_id;

    v_reconciled:=v_reconciled+1;
  end loop;

  return v_reconciled;
end;
$function$;

comment on function atlas.reconcile_company_work_worker_day_projections_v1(uuid,uuid,uuid,uuid,date,integer) is
  'Projects active canonical Company Work execution plans into locked employee Worker Day carriers. Existing owner-week Company Work evidence is succeeded in place; legacy/unadjudicated Worker Day evidence is not erased. The legacy capacity planner is not an Employee Atlas authority.';

create or replace function atlas.company_work_worker_day_refresh_self_api_v1(
  p_start_date date,
  p_days integer default 7
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_row record;
  v_context jsonb;
  v_reconciled integer:=0;
  v_contexts integer:=0;
  v_promoted_plans integer:=0;
begin
  if v_uid is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_start_date is null then raise exception 'Worker Day start date required.' using errcode='22023'; end if;
  if coalesce(p_days,0)<1 or p_days>31 then raise exception 'Worker Day range must be between 1 and 31 days.' using errcode='22023'; end if;

  for v_row in
    select f.id farm_id,fm.id membership_id
    from atlas.farm_memberships fm
    join atlas.farms f on f.id=fm.farm_id
    where fm.user_id=v_uid and fm.active and fm.role='farm_hand'
    order by f.id,fm.id
  loop
    v_context:=atlas.organization_employee_worker_context_self_v1(v_row.farm_id,v_row.membership_id);
    if coalesce((v_context->>'ok')::boolean,false) then
      v_contexts:=v_contexts+1;

      -- Preserve explicit owner-week evidence as canonical plans before projection
      -- reconciliation. Do not invoke the legacy capacity planner: it deletes
      -- unlocked owner-planned Company Work rows and is not an Organization
      -- Employee Atlas authority.
      v_promoted_plans:=v_promoted_plans+atlas.promote_legacy_owner_week_projection_plans_v1(
        v_row.farm_id,v_row.membership_id,p_start_date,p_days
      );

      v_reconciled:=v_reconciled+atlas.reconcile_company_work_worker_day_projections_v1(
        v_row.farm_id,
        v_row.membership_id,
        (v_context->>'organizationId')::uuid,
        (v_context->>'organizationMembershipId')::uuid,
        p_start_date,
        p_days
      );
    end if;
  end loop;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','company_work_worker_day_refresh_v3',
    'startDate',p_start_date,
    'days',p_days,
    'eligibleDeliveryContexts',v_contexts,
    'refreshedProjectionCount',v_reconciled,
    'reconciledProjectionCount',v_reconciled,
    'promotedLegacyOwnerWeekPlanCount',v_promoted_plans,
    'legacyCapacityRefreshInvoked',false
  );
end;
$function$;

comment on function atlas.company_work_worker_day_refresh_self_api_v1(date,integer) is
  'Employee Atlas Worker Day reconciliation. Promotes surviving explicit owner-week Company Work evidence into canonical execution plans, then projects canonical plans into locked employee carriers. It intentionally does not invoke the legacy worker-week capacity refresh.';

revoke all on function atlas.reconcile_company_work_worker_day_projections_v1(uuid,uuid,uuid,uuid,date,integer) from public,anon,authenticated;
grant execute on function atlas.reconcile_company_work_worker_day_projections_v1(uuid,uuid,uuid,uuid,date,integer) to postgres,service_role;

revoke all on function public.company_work_worker_day_refresh_self_api_v1(date,integer) from public,anon,authenticated;
grant execute on function public.company_work_worker_day_refresh_self_api_v1(date,integer) to authenticated,service_role;

commit;
