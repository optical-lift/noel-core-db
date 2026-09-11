-- Atlas operational route pattern / Company Work integration postcondition.
-- Runs only against the disposable production-schema clone after the candidate migration.
-- This validation is transactional and MUST roll back.

begin;

do $$
declare
  v_org uuid:=gen_random_uuid();
  v_unit uuid:=gen_random_uuid();
  v_owner_membership uuid;
  v_owner_user uuid:=gen_random_uuid();
  v_work uuid;
  v_allocation uuid;
  v_plan uuid;
  v_pattern uuid;
  v_result jsonb;
  v_replay jsonb;
  v_route uuid;
  v_key text:='route-pattern-fixture-'||gen_random_uuid()::text;
  v_idempotency text:='route-pattern-materialize-fixture-'||gen_random_uuid()::text;
  v_before_allocations bigint;
  v_after_allocations bigint;
begin
  -- Production clone validation is schema-only, so create a disposable authority graph
  -- inside this transaction rather than depending on production rows.
  insert into auth.users(id) values (v_owner_user);

  insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state)
  values(v_org,v_key||'-org','Route integration fixture organization','active','{}'::jsonb,'ready');

  insert into atlas.organization_units(id,organization_id,stable_key,name,unit_kind,status,metadata)
  values(v_unit,v_org,v_key||'-unit','Route integration fixture unit','operating_unit','active','{}'::jsonb);

  insert into atlas.organization_memberships(organization_id,user_id,role,active,permissions)
  values(v_org,v_owner_user,'owner',true,'{}'::jsonb)
  returning id into v_owner_membership;

  perform set_config('request.jwt.claim.sub',v_owner_user::text,true);

  insert into atlas.work_items(
    organization_id,organization_unit_id,stable_key,title,work_state,operation_class,source_object_type,metadata
  ) values (
    v_org,v_unit,v_key||'-work','Fixture route work','open','route_execution','fixture',
    jsonb_build_object('fixture','atlas_operational_route_patterns_company_work_v1')
  ) returning id into v_work;

  insert into atlas.work_allocations(
    organization_id,work_item_id,assignee_membership_id,assigned_by_membership_id,
    allocation_role,state,metadata
  ) values (
    v_org,v_work,v_owner_membership,v_owner_membership,'responsible','active',
    jsonb_build_object('fixture','atlas_operational_route_patterns_company_work_v1')
  ) returning id into v_allocation;

  insert into atlas.work_execution_plans(
    organization_id,work_item_id,responsible_allocation_id,assignee_membership_id,
    planned_by_membership_id,plan_state,first_planned_service_date,planned_service_date,
    exposure_service_date,rollover_count,plan_reason,metadata
  ) values (
    v_org,v_work,v_allocation,v_owner_membership,v_owner_membership,'active',
    current_date+1,current_date+1,current_date+1,0,'Fixture manager plan',
    jsonb_build_object('fixture','atlas_operational_route_patterns_company_work_v1')
  ) returning id into v_plan;

  insert into atlas.operational_route_patterns(
    organization_id,organization_unit_id,stable_key,version,route_label,route_kind,status,
    operating_context,metadata
  ) values (
    v_org,v_unit,v_key,1,'Fixture reusable route','service','active',
    jsonb_build_object('purpose','fixture'),
    jsonb_build_object('fixture','atlas_operational_route_patterns_company_work_v1')
  ) returning id into v_pattern;

  insert into atlas.operational_route_pattern_stops(
    organization_id,operational_route_pattern_id,stable_key,sequence_number,stop_kind,
    destination_label,address_text,operating_context,metadata
  ) values
    (v_org,v_pattern,'first',1,'service_visit','Fixture Stop One','100 Fixture Ave',
      jsonb_build_object('stop_role','first'),jsonb_build_object('fixture',true)),
    (v_org,v_pattern,'second',2,'service_visit','Fixture Stop Two','200 Fixture Ave',
      jsonb_build_object('stop_role','second'),jsonb_build_object('fixture',true));

  if exists(
    select 1 from atlas.operational_routes
    where operational_route_pattern_id=v_pattern
  ) then
    raise exception 'A reusable route pattern became execution truth before materialization.';
  end if;

  select count(*) into v_before_allocations
  from atlas.work_allocations
  where work_item_id=v_work;

  v_result:=atlas.materialize_operational_route_pattern_for_company_work_self_v1(
    v_pattern,v_work,v_idempotency,jsonb_build_object('fixtureRun',true)
  );
  v_route:=(v_result->>'routeId')::uuid;

  if v_route is null or coalesce((v_result->>'idempotentReplay')::boolean,true) then
    raise exception 'Initial route materialization failed: %',v_result;
  end if;

  if not exists(
    select 1
    from atlas.operational_routes r
    where r.id=v_route
      and r.organization_id=v_org
      and r.organization_unit_id is not distinct from v_unit
      and r.operational_route_pattern_id=v_pattern
      and r.work_item_id=v_work
      and r.work_execution_plan_id=v_plan
      and r.assigned_organization_membership_id=v_owner_membership
      and r.external_custodian_label is null
      and r.route_date=current_date+1
  ) then
    raise exception 'Materialized route did not preserve Company Work plan provenance, date, unit, and assignee.';
  end if;

  if (select count(*) from atlas.operational_route_stops where operational_route_id=v_route)<>2 then
    raise exception 'Materialized route did not copy the reusable stop topology exactly once.';
  end if;

  if exists(
    select 1 from atlas.operational_route_stops
    where operational_route_id=v_route and worker_instruction is not null
  ) then
    raise exception 'Route pattern incorrectly manufactured durable worker procedure instead of leaving it to governed execution context.';
  end if;

  select count(*) into v_after_allocations
  from atlas.work_allocations
  where work_item_id=v_work;
  if v_after_allocations<>v_before_allocations then
    raise exception 'Route materialization invented or changed Company Work responsibility.';
  end if;

  v_replay:=atlas.materialize_operational_route_pattern_for_company_work_self_v1(
    v_pattern,v_work,v_idempotency,jsonb_build_object('fixtureRun',true)
  );
  if not coalesce((v_replay->>'idempotentReplay')::boolean,false)
     or (v_replay->>'routeId')::uuid is distinct from v_route then
    raise exception 'Exact idempotent replay did not return the original route: %',v_replay;
  end if;

  if not exists(
    select 1 from atlas.v_operational_route_execution_position_v1 p
    where p.operational_route_id=v_route
      and p.execution_authority_class='company_work_backed'
      and p.work_item_id=v_work
      and p.work_execution_plan_id=v_plan
  ) then
    raise exception 'Route execution position did not classify the run as Company Work-backed.';
  end if;
end;
$$;

rollback;
