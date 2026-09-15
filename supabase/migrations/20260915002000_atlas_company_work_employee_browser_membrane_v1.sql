begin;

-- Package 2 — Company Work + Employee Atlas browser membrane v1.
--
-- The canonical Company Work, Organization, employee-access, Position,
-- Responsibility, Worker Day projection, and result contracts already exist.
-- This migration does not create a second staff/work model. It exposes a narrow
-- browser-safe membrane over those governed contracts and adds the missing
-- owner command for appointing an accessed employee to an existing Position.

create or replace function atlas.organization_company_work_people_api_v1(
  p_organization_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_delivery_candidates jsonb := '[]'::jsonb;
  v_members jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_organization_id is null then
    raise exception 'Organization required.' using errcode='22023';
  end if;
  if not atlas.is_organization_owner(p_organization_id)
     and not exists(
       select 1
       from atlas.farms f
       join atlas.farm_memberships fm on fm.farm_id=f.id
       where f.organization_id=p_organization_id
         and fm.user_id=v_uid
         and fm.active
         and fm.role in ('owner','manager')
     ) then
    raise exception 'Organization management authority required.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(item order by item->>'organizationUnitName',item->>'displayName',item->>'deliveryMembershipId'),'[]'::jsonb)
  into v_delivery_candidates
  from (
    select jsonb_strip_nulls(jsonb_build_object(
      'deliveryMembershipId',fm.id,
      'farmId',f.id,
      'farmName',f.name,
      'organizationUnitId',f.organization_unit_id,
      'organizationUnitName',ou.name,
      'authUserId',fm.user_id,
      'email',u.email,
      'displayName',coalesce(isp.display_name,nullif(fm.worker_key,''),split_part(coalesce(u.email,''),'@',1)),
      'deliveryRole',fm.role,
      'deliveryEligibilityBeginsOn',fm.eligibility_begins_on,
      'deliveryEligibilityEndsOn',fm.eligibility_ends_on,
      'identitySubjectId',fm.identity_subject_id,
      'identityInOrganization',case when ids.id is null then false else true end,
      'suggestedInvitationIdentitySubjectId',case when ids.id is null then null else fm.identity_subject_id end,
      'organizationMembershipId',om.id,
      'employeeSeatId',seat.id,
      'employeeSeatStatus',seat.status,
      'employeeBillingState',seat.billing_state,
      'appointmentId',appt.id,
      'positionId',pos.id,
      'positionKey',pos.stable_key,
      'positionTitle',pos.display_title,
      'relationshipState',case
        when om.id is null then 'delivery_only'
        when seat.id is null then 'organization_member_without_employee_access'
        when appt.id is null then 'employee_access_without_position'
        else 'positioned_employee'
      end
    )) item
    from atlas.farms f
    join atlas.farm_memberships fm
      on fm.farm_id=f.id
     and fm.active
    left join atlas.organization_units ou
      on ou.id=f.organization_unit_id
     and ou.organization_id=f.organization_id
    left join auth.users u on u.id=fm.user_id
    left join atlas.identity_subject_projections isp on isp.subject_id=fm.identity_subject_id
    left join atlas.identity_subjects ids
      on ids.id=fm.identity_subject_id
     and ids.organization_id=p_organization_id
     and ids.state='active'
    left join atlas.organization_memberships om
      on om.organization_id=p_organization_id
     and om.user_id=fm.user_id
     and om.active
    left join atlas.organization_employee_seats seat
      on seat.organization_id=p_organization_id
     and seat.organization_membership_id=om.id
     and seat.status='active'
    left join lateral(
      select a.*
      from atlas.organization_position_appointments a
      where a.organization_id=p_organization_id
        and a.organization_membership_id=om.id
        and a.status='active'
        and a.begins_at<=now()
        and (a.ends_at is null or a.ends_at>now())
      order by case when a.appointment_kind='primary' then 0 else 1 end,a.begins_at,a.id
      limit 1
    ) appt on true
    left join atlas.organization_positions pos
      on pos.id=appt.position_id
     and pos.organization_id=p_organization_id
    where f.organization_id=p_organization_id
  ) x;

  select coalesce(jsonb_agg(item order by item->>'displayName',item->>'organizationMembershipId'),'[]'::jsonb)
  into v_members
  from (
    select jsonb_strip_nulls(jsonb_build_object(
      'organizationMembershipId',om.id,
      'personId',om.person_id,
      'identitySubjectId',om.identity_subject_id,
      'authUserId',om.user_id,
      'membershipRole',om.role,
      'email',u.email,
      'displayName',coalesce(pe.display_name,isp.display_name,split_part(coalesce(u.email,''),'@',1)),
      'employeeSeatId',seat.id,
      'employeeSeatStatus',seat.status,
      'employeeBillingState',seat.billing_state,
      'appointmentId',appt.id,
      'positionId',pos.id,
      'positionKey',pos.stable_key,
      'positionTitle',pos.display_title,
      'organizationUnitId',pos.organization_unit_id,
      'organizationUnitName',ou.name
    )) item
    from atlas.organization_memberships om
    left join atlas.people pe on pe.id=om.person_id
    left join atlas.identity_subject_projections isp on isp.subject_id=om.identity_subject_id
    left join auth.users u on u.id=om.user_id
    left join atlas.organization_employee_seats seat
      on seat.organization_id=om.organization_id
     and seat.organization_membership_id=om.id
     and seat.status='active'
    left join lateral(
      select a.*
      from atlas.organization_position_appointments a
      where a.organization_id=om.organization_id
        and a.organization_membership_id=om.id
        and a.status='active'
        and a.begins_at<=now()
        and (a.ends_at is null or a.ends_at>now())
      order by case when a.appointment_kind='primary' then 0 else 1 end,a.begins_at,a.id
      limit 1
    ) appt on true
    left join atlas.organization_positions pos on pos.id=appt.position_id
    left join atlas.organization_units ou on ou.id=pos.organization_unit_id
    where om.organization_id=p_organization_id
      and om.active
  ) x;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','organization_company_work_people_v1',
    'organizationId',p_organization_id,
    'deliveryCandidates',v_delivery_candidates,
    'members',v_members
  );
end;
$function$;

comment on function atlas.organization_company_work_people_api_v1(uuid) is
  'Management read for Company Work people. Projects existing Organization Membership, employee access, Position Appointment, and legacy delivery membership as compatibility evidence; creates no identity, access, position, responsibility, or Work truth.';

create or replace function atlas.company_work_employee_home_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_access jsonb;
  v_responsibilities jsonb := '[]'::jsonb;
  v_delivery_contexts jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_access:=atlas.organization_access_self_api_v1();

  select coalesce(jsonb_agg(to_jsonb(r) order by r.organization_name,r.organization_unit_name,r.title,r.work_item_id),'[]'::jsonb)
  into v_responsibilities
  from atlas.company_work_self_responsibilities_api_v1() r;

  select coalesce(jsonb_agg(jsonb_build_object(
    'farmId',f.id,
    'farmName',f.name,
    'deliveryMembershipId',fm.id,
    'context',atlas.organization_employee_worker_context_self_v1(f.id,fm.id)
  ) order by f.name,fm.id),'[]'::jsonb)
  into v_delivery_contexts
  from atlas.farm_memberships fm
  join atlas.farms f on f.id=fm.farm_id
  where fm.user_id=v_uid
    and fm.active
    and fm.role='farm_hand';

  return jsonb_build_object(
    'ok',true,
    'contractVersion','company_work_employee_home_v1',
    'access',v_access,
    'responsibilities',v_responsibilities,
    'deliveryContexts',v_delivery_contexts
  );
end;
$function$;

comment on function atlas.company_work_employee_home_self_api_v1() is
  'Employee Company Work home read. Responsibility truth comes from active Company Work allocations; delivery context is compatibility evidence for Worker Day and cannot create or remove responsibility.';

create or replace function atlas.company_work_worker_day_refresh_self_api_v1(
  p_start_date date,
  p_days integer default 7
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_row record;
  v_context jsonb;
  v_refreshed integer := 0;
  v_contexts integer := 0;
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
    end if;
  end loop;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','company_work_worker_day_refresh_v1',
    'startDate',p_start_date,
    'days',p_days,
    'eligibleDeliveryContexts',v_contexts,
    'refreshedProjectionCount',v_refreshed
  );
end;
$function$;

comment on function atlas.company_work_worker_day_refresh_self_api_v1(date,integer) is
  'Refreshes existing Worker Day projections only for the signed-in employee contexts that independently satisfy Organization access, credential, Position Appointment, and delivery-membership eligibility.';

create or replace function atlas.company_work_worker_day_self_api_v1(
  p_start_date date,
  p_days integer default 7
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_items jsonb := '[]'::jsonb;
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
    ),'[]'::jsonb)
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
    'contractVersion','company_work_worker_day_v1',
    'startDate',p_start_date,
    'days',p_days,
    'items',v_items
  );
end;
$function$;

comment on function atlas.company_work_worker_day_self_api_v1(date,integer) is
  'Read-only Worker Day delivery projection for the signed-in employee. Does not infer responsibility from presence in the day; required Company Work source links remain explicit.';

create or replace function atlas.organization_owner_appoint_employee_position_api_v1(
  p_organization_id uuid,
  p_organization_membership_id uuid,
  p_position_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_member atlas.organization_memberships%rowtype;
  v_position atlas.organization_positions%rowtype;
  v_existing atlas.organization_position_appointments%rowtype;
  v_appointment atlas.organization_position_appointments%rowtype;
begin
  if v_uid is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_organization_id is null or p_organization_membership_id is null or p_position_id is null then
    raise exception 'Organization, employee membership, and Position are required.' using errcode='22023';
  end if;
  if not atlas.is_organization_owner(p_organization_id) then
    raise exception 'Organization owner authority required.' using errcode='42501';
  end if;

  select * into v_member
  from atlas.organization_memberships m
  where m.id=p_organization_membership_id
    and m.organization_id=p_organization_id
    and m.active
    and m.identity_subject_id is not null;
  if v_member.id is null then
    raise exception 'Active employee Organization Membership with institutional identity required.' using errcode='23514';
  end if;

  if not exists(
    select 1 from atlas.organization_employee_seats s
    where s.organization_id=p_organization_id
      and s.organization_membership_id=v_member.id
      and s.identity_subject_id=v_member.identity_subject_id
      and s.seat_class='employee'
      and s.status='active'
      and s.billing_state in ('active','waived')
  ) then
    raise exception 'Active employee access is required before Position appointment.' using errcode='23514';
  end if;

  select * into v_position
  from atlas.organization_positions p
  where p.id=p_position_id
    and p.organization_id=p_organization_id
    and p.status='active';
  if v_position.id is null then
    raise exception 'Active Position in this Organization required.' using errcode='23514';
  end if;

  select * into v_existing
  from atlas.organization_position_appointments a
  where a.organization_id=p_organization_id
    and a.position_id=p_position_id
    and a.identity_subject_id=v_member.identity_subject_id
    and a.organization_membership_id=v_member.id
    and a.status='active'
    and a.begins_at<=now()
    and (a.ends_at is null or a.ends_at>now())
  order by a.begins_at,a.id
  limit 1;

  if v_existing.id is not null then
    return jsonb_build_object(
      'state','unchanged',
      'appointmentId',v_existing.id,
      'organizationMembershipId',v_member.id,
      'positionId',v_position.id,
      'positionKey',v_position.stable_key,
      'positionTitle',v_position.display_title
    );
  end if;

  insert into atlas.organization_position_appointments(
    organization_id,position_id,identity_subject_id,organization_membership_id,
    appointment_kind,status,begins_at,metadata
  ) values(
    p_organization_id,v_position.id,v_member.identity_subject_id,v_member.id,
    'primary','active',now(),jsonb_strip_nulls(jsonb_build_object(
      'source','organization_owner_appoint_employee_position_api_v1',
      'appointedByUserId',v_uid,
      'reason',nullif(btrim(coalesce(p_reason,'')),'')
    ))
  ) returning * into v_appointment;

  return jsonb_build_object(
    'state','appointed',
    'appointmentId',v_appointment.id,
    'organizationMembershipId',v_member.id,
    'positionId',v_position.id,
    'positionKey',v_position.stable_key,
    'positionTitle',v_position.display_title
  );
end;
$function$;

comment on function atlas.organization_owner_appoint_employee_position_api_v1(uuid,uuid,uuid,text) is
  'Owner command that appoints an already-accessed employee to an already-governed Position. The appointment takes up the Position responsibilities; it does not create new responsibility definitions, Company Work allocations, or execution authority.';

-- Internal Atlas functions remain non-browser surfaces.
revoke all on function atlas.organization_company_work_people_api_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.company_work_employee_home_self_api_v1() from public,anon,authenticated;
revoke all on function atlas.company_work_worker_day_refresh_self_api_v1(date,integer) from public,anon,authenticated;
revoke all on function atlas.company_work_worker_day_self_api_v1(date,integer) from public,anon,authenticated;
revoke all on function atlas.organization_owner_appoint_employee_position_api_v1(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function atlas.organization_company_work_people_api_v1(uuid) to postgres,service_role;
grant execute on function atlas.company_work_employee_home_self_api_v1() to postgres,service_role;
grant execute on function atlas.company_work_worker_day_refresh_self_api_v1(date,integer) to postgres,service_role;
grant execute on function atlas.company_work_worker_day_self_api_v1(date,integer) to postgres,service_role;
grant execute on function atlas.organization_owner_appoint_employee_position_api_v1(uuid,uuid,uuid,text) to postgres,service_role;

-- Public Data API membrane. Every wrapper delegates to an Atlas function that
-- performs the substantive auth/relationship checks. The wrappers expose no
-- tables directly and are unavailable to anon.
create or replace function public.company_work_employee_home_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select atlas.company_work_employee_home_self_api_v1();
$function$;

create or replace function public.company_work_worker_day_refresh_self_api_v1(
  p_start_date date,
  p_days integer default 7
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $function$
  select atlas.company_work_worker_day_refresh_self_api_v1(p_start_date,p_days);
$function$;

create or replace function public.company_work_worker_day_self_api_v1(
  p_start_date date,
  p_days integer default 7
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select atlas.company_work_worker_day_self_api_v1(p_start_date,p_days);
$function$;

create or replace function public.organization_company_work_people_api_v1(p_organization_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select atlas.organization_company_work_people_api_v1(p_organization_id);
$function$;

create or replace function public.organization_owner_appoint_employee_position_api_v1(
  p_organization_id uuid,
  p_organization_membership_id uuid,
  p_position_id uuid,
  p_reason text default null
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $function$
  select atlas.organization_owner_appoint_employee_position_api_v1(
    p_organization_id,p_organization_membership_id,p_position_id,p_reason
  );
$function$;

create or replace function public.organization_management_company_work_planning_queue_api_v1(
  p_organization_id uuid,
  p_window_start date default null,
  p_window_end date default null
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select jsonb_build_object(
    'ok',true,
    'contractVersion','organization_management_company_work_planning_queue_browser_v1',
    'organizationId',p_organization_id,
    'items',coalesce(jsonb_agg(to_jsonb(q) order by q.attention_state,q.exposure_service_date nulls last,q.work_item_id),'[]'::jsonb)
  )
  from atlas.organization_management_company_work_planning_queue_api_v1(
    p_organization_id,p_window_start,p_window_end
  ) q;
$function$;

create or replace function public.organization_owner_set_company_work_responsibility_api_v1(
  p_work_item_id uuid,
  p_assignee_membership_id uuid,
  p_reason text default null
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $function$
  select atlas.organization_owner_set_company_work_responsibility_api_v1(
    p_work_item_id,p_assignee_membership_id,p_reason
  );
$function$;

create or replace function public.organization_management_plan_company_work_week_api_v1(
  p_organization_id uuid,
  p_week_start date,
  p_plans jsonb
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $function$
  select atlas.organization_management_plan_company_work_week_api_v1(
    p_organization_id,p_week_start,p_plans
  );
$function$;

create or replace function public.organization_management_clear_company_work_plan_api_v1(
  p_work_item_id uuid,
  p_reason text default null
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $function$
  select atlas.organization_management_clear_company_work_plan_api_v1(p_work_item_id,p_reason);
$function$;

create or replace function public.worker_report_company_work_projection_self_api_v1(
  p_projection_id uuid,
  p_result_kind text,
  p_idempotency_key text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $function$
  select atlas.worker_report_company_work_projection_self_api_v1(
    p_projection_id,p_result_kind,p_idempotency_key,p_payload
  );
$function$;

revoke all on function public.company_work_employee_home_self_api_v1() from public,anon,authenticated;
revoke all on function public.company_work_worker_day_refresh_self_api_v1(date,integer) from public,anon,authenticated;
revoke all on function public.company_work_worker_day_self_api_v1(date,integer) from public,anon,authenticated;
revoke all on function public.organization_company_work_people_api_v1(uuid) from public,anon,authenticated;
revoke all on function public.organization_owner_appoint_employee_position_api_v1(uuid,uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.organization_management_company_work_planning_queue_api_v1(uuid,date,date) from public,anon,authenticated;
revoke all on function public.organization_owner_set_company_work_responsibility_api_v1(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.organization_management_plan_company_work_week_api_v1(uuid,date,jsonb) from public,anon,authenticated;
revoke all on function public.organization_management_clear_company_work_plan_api_v1(uuid,text) from public,anon,authenticated;
revoke all on function public.worker_report_company_work_projection_self_api_v1(uuid,text,text,jsonb) from public,anon,authenticated;

grant execute on function public.company_work_employee_home_self_api_v1() to authenticated,service_role;
grant execute on function public.company_work_worker_day_refresh_self_api_v1(date,integer) to authenticated,service_role;
grant execute on function public.company_work_worker_day_self_api_v1(date,integer) to authenticated,service_role;
grant execute on function public.organization_company_work_people_api_v1(uuid) to authenticated,service_role;
grant execute on function public.organization_owner_appoint_employee_position_api_v1(uuid,uuid,uuid,text) to authenticated,service_role;
grant execute on function public.organization_management_company_work_planning_queue_api_v1(uuid,date,date) to authenticated,service_role;
grant execute on function public.organization_owner_set_company_work_responsibility_api_v1(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.organization_management_plan_company_work_week_api_v1(uuid,date,jsonb) to authenticated,service_role;
grant execute on function public.organization_management_clear_company_work_plan_api_v1(uuid,text) to authenticated,service_role;
grant execute on function public.worker_report_company_work_projection_self_api_v1(uuid,text,text,jsonb) to authenticated,service_role;

commit;
