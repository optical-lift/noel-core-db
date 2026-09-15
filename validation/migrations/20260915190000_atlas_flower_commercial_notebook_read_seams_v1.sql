-- Package 4 / Flower Operations commercial notebook read seams v1 postcondition.
-- Runs only against the disposable production-schema clone after the candidate migration.

begin;

do $$
declare
  v_user uuid:=gen_random_uuid();
  v_other_user uuid:=gen_random_uuid();
  v_org uuid:=gen_random_uuid();
  v_other_org uuid:=gen_random_uuid();
  v_farm uuid:=gen_random_uuid();
  v_other_farm uuid:=gen_random_uuid();
  v_farm_membership uuid;
  v_key text:='flower-commercial-fixture-'||gen_random_uuid()::text;
  v_payload jsonb;
  v_failed boolean:=false;
begin
  if not has_function_privilege('authenticated','public.flower_route_availability_notebook_self_api_v1(uuid)','execute') then
    raise exception 'Authenticated browser callers cannot execute route availability read membrane.';
  end if;
  if has_function_privilege('anon','public.flower_route_availability_notebook_self_api_v1(uuid)','execute') then
    raise exception 'Anonymous callers can execute route availability read membrane.';
  end if;
  if not has_function_privilege('authenticated','public.flower_commercial_commitments_notebook_self_api_v1(uuid,date,date)','execute') then
    raise exception 'Authenticated browser callers cannot execute commercial commitments read membrane.';
  end if;
  if has_function_privilege('anon','public.flower_commercial_commitments_notebook_self_api_v1(uuid,date,date)','execute') then
    raise exception 'Anonymous callers can execute commercial commitments read membrane.';
  end if;
  if has_function_privilege('authenticated','atlas.flower_route_availability_notebook_self_api_v1(uuid)','execute')
     or has_function_privilege('authenticated','atlas.flower_commercial_commitments_notebook_self_api_v1(uuid,date,date)','execute') then
    raise exception 'Authenticated browser callers received direct atlas-schema execution authority.';
  end if;

  if not exists (
    select 1
    from atlas.notebook_spread_instances s
    join atlas.notebook_spread_source_bindings b on b.spread_instance_id=s.id
    where s.principal_id='94190000-0000-4000-8000-000000000101'::uuid
      and s.spread_key='flower-ready:94190000-0000-4000-8000-000000000020'
      and s.subject_domain='flower'
      and s.subject_kind='ready_inventory'
      and s.subject_id='94190000-0000-4000-8000-000000000020'
      and s.section_key='Flower Operations'
      and b.source_domain='flower'
      and b.source_kind='route_availability_current_v1'
      and b.source_id='94190000-0000-4000-8000-000000000020'
      and b.relationship_kind='evidence'
      and b.binding_state='active'
  ) then
    raise exception 'Eligible fixture Principal did not receive route availability on Ready spread.';
  end if;

  if not exists (
    select 1
    from atlas.notebook_spread_instances s
    join atlas.notebook_spread_source_bindings b on b.spread_instance_id=s.id
    where s.principal_id='94190000-0000-4000-8000-000000000101'::uuid
      and s.spread_key='flower-orders:94190000-0000-4000-8000-000000000020'
      and s.subject_domain='flower'
      and s.subject_kind='commercial_commitments'
      and s.subject_id='94190000-0000-4000-8000-000000000020'
      and s.section_key='Flower Operations'
      and b.source_domain='flower'
      and b.source_kind='commercial_commitments_v1'
      and b.source_id='94190000-0000-4000-8000-000000000020'
      and b.relationship_kind='state'
      and b.binding_state='active'
  ) then
    raise exception 'Eligible fixture Principal did not receive Flower orders spread/binding.';
  end if;

  if exists (
    select 1 from atlas.notebook_spread_instances s
    where s.principal_id='94190000-0000-4000-8000-000000000102'::uuid
      and s.subject_domain='flower'
      and s.subject_id='94190000-0000-4000-8000-000000000020'
  ) then
    raise exception 'Organization ownership without farm authority admitted a commercial Flower spread.';
  end if;

  if exists (
    select 1
    from atlas.principals p
    join atlas.organization_memberships m on m.user_id=p.user_id and m.active=true and m.role='owner'
    join atlas.farms f on f.organization_id=m.organization_id and f.status='active'
    join atlas.farm_memberships fm on fm.user_id=p.user_id and fm.farm_id=f.id and fm.active=true and fm.role in ('owner','manager')
    where p.status='active'
      and not exists (
        select 1
        from atlas.notebook_spread_instances s
        join atlas.notebook_spread_source_bindings b on b.spread_instance_id=s.id
        where s.principal_id=p.id
          and s.spread_key='flower-orders:'||f.id::text
          and b.source_domain='flower'
          and b.source_kind='commercial_commitments_v1'
          and b.source_id=f.id::text
          and b.binding_state='active'
      )
  ) then
    raise exception 'At least one eligible Principal/farm pair is missing Flower orders.';
  end if;

  if exists (
    select 1
    from atlas.principals p
    join atlas.organization_memberships m on m.user_id=p.user_id and m.active=true and m.role='owner'
    join atlas.farms f on f.organization_id=m.organization_id and f.status='active'
    join atlas.farm_memberships fm on fm.user_id=p.user_id and fm.farm_id=f.id and fm.active=true and fm.role in ('owner','manager')
    where p.status='active'
      and not exists (
        select 1
        from atlas.notebook_spread_instances s
        join atlas.notebook_spread_source_bindings b on b.spread_instance_id=s.id
        where s.principal_id=p.id
          and s.spread_key='flower-ready:'||f.id::text
          and b.source_domain='flower'
          and b.source_kind='route_availability_current_v1'
          and b.source_id=f.id::text
          and b.binding_state='active'
      )
  ) then
    raise exception 'At least one eligible Principal/farm pair is missing route availability binding.';
  end if;

  insert into auth.users(id) values(v_user),(v_other_user);
  insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state)
  values
    (v_org,v_key||'-org','Flower Commercial Fixture','active','{}'::jsonb,'ready'),
    (v_other_org,v_key||'-other-org','Other Flower Commercial Fixture','active','{}'::jsonb,'ready');
  insert into atlas.organization_memberships(organization_id,user_id,role,active,permissions)
  values(v_org,v_user,'owner',true,'{}'::jsonb);
  insert into atlas.farms(id,organization_id,stable_key,name,status,metadata)
  values
    (v_farm,v_org,v_key||'-farm','Flower Commercial Farm','active','{}'::jsonb),
    (v_other_farm,v_other_org,v_key||'-other-farm','Other Flower Commercial Farm','active','{}'::jsonb);
  insert into atlas.farm_memberships(user_id,farm_id,role,active,permissions)
  values(v_user,v_farm,'owner',true,'{}'::jsonb)
  returning id into v_farm_membership;

  perform set_config('request.jwt.claim.sub',v_user::text,true);

  v_payload:=public.flower_route_availability_notebook_self_api_v1(v_farm);
  if v_payload->>'contractVersion'<>'flower_route_availability_notebook_self_api_v1'
     or v_payload#>>'{farm,id}'<>v_farm::text
     or v_payload#>>'{audience,role}'<>'owner'
     or v_payload#>>'{audience,membershipId}'<>v_farm_membership::text
     or jsonb_typeof(v_payload->'items')<>'array'
     or jsonb_array_length(v_payload->'items')<>0 then
    raise exception 'Route availability membrane did not preserve empty authorized fixture: %',v_payload;
  end if;
  if (v_payload->'truthBoundary'->>'routeAvailabilityIsSeparateFromReadyPosition')::boolean is distinct from true then
    raise exception 'Route availability truth boundary collapsed into Ready.';
  end if;

  v_payload:=public.flower_commercial_commitments_notebook_self_api_v1(v_farm,current_date-89,current_date);
  if v_payload->>'contractVersion'<>'flower_commercial_commitments_notebook_self_api_v1'
     or v_payload#>>'{farm,id}'<>v_farm::text
     or v_payload#>>'{audience,role}'<>'owner'
     or v_payload#>>'{audience,membershipId}'<>v_farm_membership::text
     or jsonb_typeof(v_payload->'demands')<>'array'
     or jsonb_typeof(v_payload->'sales')<>'array'
     or jsonb_array_length(v_payload->'demands')<>0
     or jsonb_array_length(v_payload->'sales')<>0 then
    raise exception 'Commercial commitments membrane did not preserve empty authorized fixture: %',v_payload;
  end if;
  if (v_payload->'truthBoundary'->>'demandReservationIsNotSale')::boolean is distinct from true
     or (v_payload->'truthBoundary'->>'saleIsNotFulfillment')::boolean is distinct from true
     or (v_payload->'truthBoundary'->>'fulfillmentIsNotPayment')::boolean is distinct from true
     or (v_payload->'truthBoundary'->>'buyerRelationshipIsNotCRM')::boolean is distinct from true then
    raise exception 'Commercial truth boundary collapsed source-owned realities.';
  end if;

  begin
    perform public.flower_route_availability_notebook_self_api_v1(v_other_farm);
  exception when insufficient_privilege then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'Route availability read accepted a farm outside caller membership.';
  end if;

  v_failed:=false;
  begin
    perform public.flower_commercial_commitments_notebook_self_api_v1(v_other_farm,current_date-89,current_date);
  exception when insufficient_privilege then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'Commercial commitments read accepted a farm outside caller membership.';
  end if;
end;
$$;

rollback;
