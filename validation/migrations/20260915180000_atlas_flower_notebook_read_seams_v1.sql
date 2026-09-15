-- Package 4 / Flower Operations notebook read seams v1 postcondition.
-- Runs only against the disposable production-schema clone after the candidate migration.
-- This validation is transactional and MUST roll back.

begin;

do $$
declare
  v_user uuid:=gen_random_uuid();
  v_other_user uuid:=gen_random_uuid();
  v_org uuid:=gen_random_uuid();
  v_other_org uuid:=gen_random_uuid();
  v_farm uuid:=gen_random_uuid();
  v_other_farm uuid:=gen_random_uuid();
  v_membership uuid;
  v_principal uuid:=gen_random_uuid();
  v_key text:='flower-notebook-fixture-'||gen_random_uuid()::text;
  v_payload jsonb;
  v_failed boolean:=false;
begin
  if not has_function_privilege('authenticated','public.flower_harvest_notebook_self_api_v1(uuid,date,date,integer)','execute') then
    raise exception 'Authenticated browser callers cannot execute the Harvest notebook read membrane.';
  end if;
  if has_function_privilege('anon','public.flower_harvest_notebook_self_api_v1(uuid,date,date,integer)','execute') then
    raise exception 'Anonymous callers can execute the Harvest notebook read membrane.';
  end if;
  if not has_function_privilege('authenticated','public.flower_ready_inventory_notebook_self_api_v1(uuid)','execute') then
    raise exception 'Authenticated browser callers cannot execute the Ready notebook read membrane.';
  end if;
  if has_function_privilege('anon','public.flower_ready_inventory_notebook_self_api_v1(uuid)','execute') then
    raise exception 'Anonymous callers can execute the Ready notebook read membrane.';
  end if;
  if has_function_privilege('authenticated','atlas.flower_harvest_notebook_self_api_v1(uuid,date,date,integer)','execute')
     or has_function_privilege('authenticated','atlas.flower_ready_inventory_notebook_self_api_v1(uuid)','execute') then
    raise exception 'Authenticated browser callers received direct atlas-schema execution authority.';
  end if;

  -- Every currently eligible Principal/farm pair must have the product-owned durable
  -- Harvest and Ready pages and the exact governed source bindings installed by the migration.
  if exists (
    select 1
    from atlas.principals p
    join atlas.organization_memberships m
      on m.user_id=p.user_id and m.active=true and m.role='owner'
    join atlas.farms f
      on f.organization_id=m.organization_id and f.status='active'
    where p.status='active'
      and not exists (
        select 1 from atlas.notebook_spread_instances s
        where s.principal_id=p.id
          and s.spread_key='flower-harvest:'||f.id::text
          and s.subject_domain='flower'
          and s.subject_kind='harvest'
          and s.subject_id=f.id::text
          and s.section_key='Flower Operations'
          and s.spread_state='open'
      )
  ) then
    raise exception 'At least one eligible Principal/farm pair is missing its Harvest spread.';
  end if;

  if exists (
    select 1
    from atlas.principals p
    join atlas.organization_memberships m
      on m.user_id=p.user_id and m.active=true and m.role='owner'
    join atlas.farms f
      on f.organization_id=m.organization_id and f.status='active'
    where p.status='active'
      and not exists (
        select 1
        from atlas.notebook_spread_instances s
        join atlas.notebook_spread_source_bindings b on b.spread_instance_id=s.id
        where s.principal_id=p.id
          and s.spread_key='flower-harvest:'||f.id::text
          and b.source_domain='flower'
          and b.source_kind='harvest_recent_v1'
          and b.source_id=f.id::text
          and b.relationship_kind='evidence'
          and b.binding_state='active'
      )
  ) then
    raise exception 'At least one Harvest spread is missing its governed Harvest source binding.';
  end if;

  if exists (
    select 1
    from atlas.principals p
    join atlas.organization_memberships m
      on m.user_id=p.user_id and m.active=true and m.role='owner'
    join atlas.farms f
      on f.organization_id=m.organization_id and f.status='active'
    where p.status='active'
      and not exists (
        select 1
        from atlas.notebook_spread_instances s
        join atlas.notebook_spread_source_bindings b on b.spread_instance_id=s.id
        where s.principal_id=p.id
          and s.spread_key='flower-ready:'||f.id::text
          and s.subject_domain='flower'
          and s.subject_kind='ready_inventory'
          and s.subject_id=f.id::text
          and s.section_key='Flower Operations'
          and b.source_domain='flower'
          and b.source_kind='ready_inventory_position_v1'
          and b.source_id=f.id::text
          and b.relationship_kind='state'
          and b.binding_state='active'
      )
  ) then
    raise exception 'At least one eligible Principal/farm pair is missing its Ready spread/binding.';
  end if;

  insert into auth.users(id) values(v_user),(v_other_user);

  insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state)
  values
    (v_org,v_key||'-org','Flower Notebook Fixture','active','{}'::jsonb,'ready'),
    (v_other_org,v_key||'-other-org','Other Flower Notebook Fixture','active','{}'::jsonb,'ready');

  insert into atlas.organization_memberships(organization_id,user_id,role,active,permissions)
  values(v_org,v_user,'owner',true,'{}'::jsonb)
  returning id into v_membership;

  insert into atlas.farms(id,organization_id,stable_key,name,status,metadata)
  values
    (v_farm,v_org,v_key||'-farm','Flower Notebook Farm','active','{}'::jsonb),
    (v_other_farm,v_other_org,v_key||'-other-farm','Other Flower Notebook Farm','active','{}'::jsonb);

  insert into atlas.principals(id,user_id,organization_id,stable_key,name,status,metadata)
  values(v_principal,v_user,v_org,v_key||'-principal','Flower Notebook Principal','active','{}'::jsonb);

  perform set_config('request.jwt.claim.sub',v_user::text,true);

  v_payload:=public.flower_harvest_notebook_self_api_v1(v_farm,current_date-29,current_date,250);
  if v_payload->>'contractVersion'<>'flower_harvest_notebook_self_api_v1'
     or v_payload#>>'{farm,id}'<>v_farm::text
     or v_payload#>>'{audience,role}'<>'owner'
     or jsonb_typeof(v_payload->'items')<>'array'
     or jsonb_array_length(v_payload->'items')<>0 then
    raise exception 'Harvest notebook read membrane did not preserve an empty authorized fixture correctly: %',v_payload;
  end if;

  v_payload:=public.flower_ready_inventory_notebook_self_api_v1(v_farm);
  if v_payload->>'contractVersion'<>'flower_ready_inventory_notebook_self_api_v1'
     or v_payload#>>'{farm,id}'<>v_farm::text
     or v_payload#>>'{audience,role}'<>'owner'
     or jsonb_typeof(v_payload->'items')<>'array'
     or jsonb_array_length(v_payload->'items')<>0 then
    raise exception 'Ready notebook read membrane did not preserve an empty authorized fixture correctly: %',v_payload;
  end if;

  begin
    perform public.flower_harvest_notebook_self_api_v1(v_other_farm,current_date-29,current_date,250);
  exception when insufficient_privilege then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'Harvest notebook read accepted a farm outside the caller membership.';
  end if;

  v_failed:=false;
  begin
    perform public.flower_ready_inventory_notebook_self_api_v1(v_other_farm);
  exception when insufficient_privilege then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'Ready notebook read accepted a farm outside the caller membership.';
  end if;

  if (v_payload->'truthBoundary'->>'routeAvailabilityIsSeparateEvidence')::boolean is distinct from true
     or (v_payload->'truthBoundary'->>'valuationIsNotTransactionPrice')::boolean is distinct from true then
    raise exception 'Ready notebook truth boundary collapsed route availability or transaction pricing.';
  end if;
end;
$$;

rollback;
