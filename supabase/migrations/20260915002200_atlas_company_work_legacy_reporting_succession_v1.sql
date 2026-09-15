begin;

do $block$
begin
  if not exists (
    select 1
    from atlas.work_result_contract_policies p
    where p.contract_key='ordinary_company_work_worker_attestation_v1'
      and p.active
      and p.acceptance_mode='worker_attestation'
  ) then
    raise exception 'ordinary_company_work_worker_attestation_v1 must be active before legacy quick-complete succession.';
  end if;
end;
$block$;

create or replace function atlas.inherit_legacy_quick_complete_result_contract_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if new.state<>'retired'
     and new.task_id is not null
     and exists(
       select 1
       from atlas.tasks t
       where t.id=new.task_id
         and lower(coalesce(t.metadata->>'quick_complete_allowed','false'))='true'
     ) then
    update atlas.work_items w
    set result_contract_key='ordinary_company_work_worker_attestation_v1',
        metadata=coalesce(w.metadata,'{}'::jsonb)||jsonb_build_object(
          'resultContractInheritedFromLegacyQuickComplete',true,
          'resultContractInheritanceSourceTaskId',new.task_id,
          'resultContractInheritanceSource','legacy_quick_complete_allowed_v1'
        ),
        updated_at=now()
    where w.id=new.work_item_id
      and w.organization_id=new.organization_id
      and w.result_contract_key is null;
  end if;
  return new;
end;
$function$;

comment on function atlas.inherit_legacy_quick_complete_result_contract_trigger_v1() is
  'Succession-only bridge: when an active legacy execution adapter explicitly carries quick_complete_allowed=true, preserve that evidence as the generic ordinary worker-attestation result contract on otherwise-uncontracted canonical Company Work. Never overwrites an existing canonical result contract.';

drop trigger if exists work_execution_adapters_inherit_legacy_quick_complete_v1 on atlas.work_execution_adapters;
create trigger work_execution_adapters_inherit_legacy_quick_complete_v1
after insert or update of work_item_id,task_id,state on atlas.work_execution_adapters
for each row execute function atlas.inherit_legacy_quick_complete_result_contract_trigger_v1();

update atlas.work_items w
set result_contract_key='ordinary_company_work_worker_attestation_v1',
    metadata=coalesce(w.metadata,'{}'::jsonb)||jsonb_build_object(
      'resultContractInheritedFromLegacyQuickComplete',true,
      'resultContractInheritanceSource','legacy_quick_complete_allowed_v1'
    ),
    updated_at=now()
where w.result_contract_key is null
  and exists(
    select 1
    from atlas.work_execution_adapters a
    join atlas.tasks t on t.id=a.task_id
    where a.work_item_id=w.id
      and a.organization_id=w.organization_id
      and a.state<>'retired'
      and lower(coalesce(t.metadata->>'quick_complete_allowed','false'))='true'
  );

create or replace function atlas.promote_legacy_owner_week_projection_plans_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_start_date date,
  p_days integer default 7
)
returns integer
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_row record;
  v_plan_id uuid;
  v_promoted integer:=0;
begin
  if p_farm_id is null or p_membership_id is null or p_start_date is null then
    raise exception 'Farm, delivery membership, and start date are required.' using errcode='22023';
  end if;
  if coalesce(p_days,0)<1 or p_days>31 then
    raise exception 'Worker Day range must be between 1 and 31 days.' using errcode='22023';
  end if;

  for v_row in
    with projection_work as (
      select wp.id projection_id,
             wp.organization_id,
             wp.organization_membership_id,
             wp.planned_date,
             coalesce(wp.original_planned_date,wp.planned_date) original_planned_date,
             wp.reason,
             wp.delivery_key,
             (array_agg(s.work_item_id order by s.work_item_id))[1] work_item_id,
             count(*) required_count
      from atlas.worker_week_projection wp
      join atlas.worker_week_projection_sources s
        on s.projection_id=wp.id
       and s.source_role='required'
      where wp.farm_id=p_farm_id
        and wp.membership_id=p_membership_id
        and wp.planned_date>=p_start_date
        and wp.planned_date<p_start_date+p_days
        and wp.plan_state in ('planned','conditional')
        and wp.reason like 'owner_week_plan_%'
      group by wp.id
    )
    select pw.*,
           wa.id responsible_allocation_id
    from projection_work pw
    join atlas.work_items w
      on w.id=pw.work_item_id
     and w.organization_id=pw.organization_id
     and w.work_state='open'
    join atlas.work_allocations wa
      on wa.organization_id=w.organization_id
     and wa.work_item_id=w.id
     and wa.allocation_role='responsible'
     and wa.state='active'
     and wa.assignee_membership_id=pw.organization_membership_id
    where pw.required_count=1
      and not exists(
        select 1
        from atlas.work_execution_plans ep
        where ep.organization_id=w.organization_id
          and ep.work_item_id=w.id
          and ep.plan_state in ('active','needs_replan')
      )
    order by pw.planned_date,pw.projection_id
  loop
    insert into atlas.work_execution_plans(
      organization_id,work_item_id,responsible_allocation_id,assignee_membership_id,
      planned_by_membership_id,plan_state,first_planned_service_date,
      planned_service_date,exposure_service_date,rollover_count,plan_reason,metadata
    ) values(
      v_row.organization_id,v_row.work_item_id,v_row.responsible_allocation_id,v_row.organization_membership_id,
      null,'active',v_row.original_planned_date,
      v_row.original_planned_date,v_row.planned_date,
      greatest(v_row.planned_date-v_row.original_planned_date,0),v_row.reason,
      jsonb_strip_nulls(jsonb_build_object(
        'source','legacy_owner_week_projection_succession_v1',
        'existingProjectionId',v_row.projection_id,
        'deliveryKey',v_row.delivery_key,
        'authorityEvidence',v_row.reason,
        'historicalPlannerUnknown',true,
        'transitional',true
      ))
    ) returning id into v_plan_id;

    insert into atlas.work_execution_plan_events(
      organization_id,work_item_id,plan_id,event_kind,
      to_planned_service_date,to_exposure_service_date,actor_membership_id,reason,metadata
    ) values(
      v_row.organization_id,v_row.work_item_id,v_plan_id,'planned',
      v_row.original_planned_date,v_row.planned_date,null,v_row.reason,
      jsonb_build_object(
        'source','legacy_owner_week_projection_succession_v1',
        'existingProjectionId',v_row.projection_id,
        'historicalPlannerUnknown',true,
        'transitional',true
      )
    );

    v_promoted:=v_promoted+1;
  end loop;

  return v_promoted;
end;
$function$;

comment on function atlas.promote_legacy_owner_week_projection_plans_v1(uuid,uuid,date,integer) is
  'Transitional succession bridge from already-persisted owner_week_plan Worker Day evidence into canonical work_execution_plans. Requires one canonical work source plus matching active Responsibility, preserves original/exposure dates, records unknown historical planner rather than inventing an actor, and never derives Responsibility from delivery.';

create or replace function atlas.company_work_projection_result_reporting_self_v1(
  p_projection_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_projection atlas.worker_week_projection%rowtype;
  v_farm_id uuid;
  v_context jsonb;
  v_work_ids uuid[];
  v_work atlas.work_items%rowtype;
  v_policy atlas.work_result_contract_policies%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
begin
  if v_uid is null then raise exception 'Authenticated employee required.' using errcode='42501'; end if;
  if p_projection_id is null then raise exception 'Worker Day projection required.' using errcode='22023'; end if;

  select * into v_projection from atlas.worker_week_projection p where p.id=p_projection_id;
  if v_projection.id is null then raise exception 'Worker Day projection was not found.' using errcode='P0002'; end if;

  select fm.farm_id into v_farm_id
  from atlas.farm_memberships fm
  where fm.id=v_projection.membership_id
    and fm.user_id=v_uid
    and fm.active;
  if v_farm_id is null then raise exception 'Worker Day projection is not available to the signed-in employee.' using errcode='42501'; end if;

  v_context:=atlas.organization_employee_worker_context_self_v1(v_farm_id,v_projection.membership_id);
  if not coalesce((v_context->>'ok')::boolean,false)
     or v_projection.organization_id is distinct from (v_context->>'organizationId')::uuid
     or v_projection.organization_membership_id is distinct from (v_context->>'organizationMembershipId')::uuid then
    raise exception 'Employee Worker Day authority required.' using errcode='42501';
  end if;

  select array_agg(s.work_item_id order by s.work_item_id) into v_work_ids
  from atlas.worker_week_projection_sources s
  where s.projection_id=v_projection.id and s.source_role='required';

  if coalesce(array_length(v_work_ids,1),0)=0 then
    return jsonb_build_object('reportable',false,'state','no_required_company_work');
  end if;
  if array_length(v_work_ids,1)<>1 then
    return jsonb_build_object('reportable',false,'state','multiple_required_company_work','workItemIds',to_jsonb(v_work_ids));
  end if;

  select * into v_work
  from atlas.work_items w
  where w.id=v_work_ids[1]
    and w.organization_id=(v_context->>'organizationId')::uuid;
  if v_work.id is null or v_work.work_state<>'open' then
    return jsonb_build_object('reportable',false,'state','company_work_not_open','workItemId',v_work_ids[1]);
  end if;

  select * into v_policy
  from atlas.work_result_contract_policies p
  where p.contract_key=v_work.result_contract_key and p.active;
  if v_policy.contract_key is null then
    return jsonb_build_object('reportable',false,'state','ungoverned_result_contract','workItemId',v_work.id);
  end if;
  if v_policy.acceptance_mode not in ('worker_attestation','manager_acceptance') then
    return jsonb_build_object(
      'reportable',false,'state','different_result_contract','workItemId',v_work.id,
      'resultContractKey',v_policy.contract_key,'acceptanceMode',v_policy.acceptance_mode
    );
  end if;

  select * into v_allocation
  from atlas.work_allocations a
  where a.organization_id=v_work.organization_id
    and a.work_item_id=v_work.id
    and a.allocation_role='responsible'
    and a.state='active'
    and a.assignee_membership_id=(v_context->>'organizationMembershipId')::uuid
  limit 1;
  if v_allocation.id is null then
    return jsonb_build_object('reportable',false,'state','responsibility_mismatch','workItemId',v_work.id);
  end if;

  select * into v_plan
  from atlas.work_execution_plans p
  where p.organization_id=v_work.organization_id
    and p.work_item_id=v_work.id
    and p.responsible_allocation_id=v_allocation.id
    and p.assignee_membership_id=(v_context->>'organizationMembershipId')::uuid
    and p.plan_state='active'
    and p.exposure_service_date=v_projection.planned_date
  limit 1;
  if v_plan.id is null then
    return jsonb_build_object(
      'reportable',false,'state','not_on_governed_plan','workItemId',v_work.id,
      'resultContractKey',v_policy.contract_key,'acceptanceMode',v_policy.acceptance_mode
    );
  end if;

  return jsonb_build_object(
    'reportable',true,
    'state','reportable',
    'workItemId',v_work.id,
    'resultContractKey',v_policy.contract_key,
    'acceptanceMode',v_policy.acceptance_mode,
    'supportedResultKinds',jsonb_build_array('completed','blocked','partial','unable')
  );
end;
$function$;

comment on function atlas.company_work_projection_result_reporting_self_v1(uuid) is
  'Read-only reportability contract for the signed-in employee Worker Day projection. Reporting is available only for exactly one open canonical Company Work source with an active governed result contract, current delegated Responsibility, and matching active canonical execution plan.';

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
  v_refreshed integer:=0;
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
      v_refreshed:=v_refreshed+atlas.refresh_worker_week_projection_internal_v1(
        v_row.farm_id,v_row.membership_id,p_start_date,p_days
      );
      v_promoted_plans:=v_promoted_plans+atlas.promote_legacy_owner_week_projection_plans_v1(
        v_row.farm_id,v_row.membership_id,p_start_date,p_days
      );
    end if;
  end loop;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','company_work_worker_day_refresh_v2',
    'startDate',p_start_date,
    'days',p_days,
    'eligibleDeliveryContexts',v_contexts,
    'refreshedProjectionCount',v_refreshed,
    'promotedLegacyOwnerWeekPlanCount',v_promoted_plans
  );
end;
$function$;

create or replace function atlas.company_work_worker_day_self_api_v1(
  p_start_date date,
  p_days integer default 7
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_items jsonb:='[]'::jsonb;
begin
  if v_uid is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_start_date is null then raise exception 'Worker Day start date required.' using errcode='22023'; end if;
  if coalesce(p_days,0)<1 or p_days>31 then raise exception 'Worker Day range must be between 1 and 31 days.' using errcode='22023'; end if;

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'projectionId',wp.id,
    'farmId',wp.farm_id,
    'deliveryMembershipId',wp.membership_id,
    'organizationId',wp.organization_id,
    'organizationMembershipId',wp.organization_membership_id,
    'plannedDate',wp.planned_date,
    'originalPlannedDate',wp.original_planned_date,
    'planOrder',wp.plan_order,
    'title',wp.title,
    'planState',wp.plan_state,
    'environment',wp.environment,
    'expectedActiveMinutes',wp.expected_active_minutes,
    'reason',wp.reason,
    'deliveryKey',wp.delivery_key,
    'deliveryPayload',wp.delivery_payload,
    'requiredWorkItemIds',coalesce((
      select jsonb_agg(s.work_item_id order by s.work_item_id)
      from atlas.worker_week_projection_sources s
      where s.projection_id=wp.id and s.source_role='required'
    ),'[]'::jsonb),
    'resultReporting',atlas.company_work_projection_result_reporting_self_v1(wp.id)
  )) order by wp.planned_date,wp.plan_order,wp.created_at,wp.id),'[]'::jsonb)
  into v_items
  from atlas.farm_memberships fm
  join atlas.farms f on f.id=fm.farm_id
  cross join lateral (
    select atlas.organization_employee_worker_context_self_v1(f.id,fm.id) ctx
  ) c
  join atlas.worker_week_projection wp
    on wp.farm_id=f.id
   and wp.membership_id=fm.id
   and wp.organization_id=(c.ctx->>'organizationId')::uuid
   and wp.organization_membership_id=(c.ctx->>'organizationMembershipId')::uuid
  where fm.user_id=v_uid
    and fm.active
    and fm.role='farm_hand'
    and coalesce((c.ctx->>'ok')::boolean,false)
    and wp.planned_date>=p_start_date
    and wp.planned_date<p_start_date+p_days;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','company_work_worker_day_v2',
    'startDate',p_start_date,
    'days',p_days,
    'items',v_items
  );
end;
$function$;

comment on function atlas.company_work_worker_day_self_api_v1(date,integer) is
  'Read-only Worker Day delivery projection for the signed-in employee. Each item carries an explicit resultReporting contract so the browser never offers Done/Blocked when canonical result authority is absent.';

revoke all on function atlas.inherit_legacy_quick_complete_result_contract_trigger_v1() from public,anon,authenticated;
revoke all on function atlas.promote_legacy_owner_week_projection_plans_v1(uuid,uuid,date,integer) from public,anon,authenticated;
revoke all on function atlas.company_work_projection_result_reporting_self_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.inherit_legacy_quick_complete_result_contract_trigger_v1() to postgres,service_role;
grant execute on function atlas.promote_legacy_owner_week_projection_plans_v1(uuid,uuid,date,integer) to postgres,service_role;
grant execute on function atlas.company_work_projection_result_reporting_self_v1(uuid) to postgres,service_role;

revoke all on function public.company_work_worker_day_refresh_self_api_v1(date,integer) from public,anon,authenticated;
revoke all on function public.company_work_worker_day_self_api_v1(date,integer) from public,anon,authenticated;
grant execute on function public.company_work_worker_day_refresh_self_api_v1(date,integer) to authenticated,service_role;
grant execute on function public.company_work_worker_day_self_api_v1(date,integer) to authenticated,service_role;

commit;
