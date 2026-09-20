do $validation$
declare
  v_org uuid:='96200000-0000-0000-0000-000000000001'::uuid;
  v_other_org uuid:='96200000-0000-0000-0000-000000000002'::uuid;
  v_owner uuid:='96300000-0000-0000-0000-000000000001'::uuid;
  v_bounded_owner uuid:='96300000-0000-0000-0000-000000000002'::uuid;
  v_member uuid:='96300000-0000-0000-0000-000000000003'::uuid;
  v_other_member uuid:='96300000-0000-0000-0000-000000000004'::uuid;
  v_later_owner uuid:='96300000-0000-0000-0000-000000000005'::uuid;
  v_endpoint uuid:='96400000-0000-0000-0000-000000000001'::uuid;
  v_new_endpoint uuid;
  v_result jsonb;
  v_old_compat uuid;
  v_count integer;
begin
  if not exists(
    select 1
    from pg_attribute
    where attrelid='atlas.communication_endpoint_member_grants'::regclass
      and attname='grant_basis_kind'
      and attnotnull
      and attnum>0
      and not attisdropped
  ) then
    raise exception 'Endpoint grant basis column is missing or nullable.';
  end if;

  select count(*) into v_count
  from atlas.communication_endpoint_member_grants
  where communication_endpoint_id=v_endpoint
    and membership_id=v_owner
    and grant_state='active'
    and grant_basis_kind='organization_owner_compatibility_cutover';

  if v_count<>6 then
    raise exception 'Unbounded current owner did not receive six compatibility grants.';
  end if;

  if exists(
    select 1 from atlas.communication_endpoint_member_grants
    where communication_endpoint_id=v_endpoint
      and membership_id=v_bounded_owner
  ) then
    raise exception 'Bounded owner received compatibility Endpoint authority without governed calendar context.';
  end if;

  if not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_owner,'view')
     or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_owner,'admin') then
    raise exception 'Materialized current owner Endpoint authority is not resolving.';
  end if;

  if atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_bounded_owner,'view') then
    raise exception 'Bounded owner resolved Endpoint authority without governed calendar context.';
  end if;

  begin
    insert into atlas.communication_endpoint_member_grants(
      communication_endpoint_id,membership_id,capability,
      granted_by_membership_id,grant_basis_kind,metadata
    ) values(
      v_endpoint,v_other_member,'view',
      v_owner,'explicit_owner_grant','{}'::jsonb
    );
    raise exception 'Cross-Organization Endpoint grant unexpectedly succeeded.';
  exception when sqlstate '23514' then
    null;
  end;

  begin
    insert into atlas.communication_endpoint_member_grants(
      communication_endpoint_id,membership_id,capability,
      granted_by_membership_id,grant_basis_kind,metadata
    ) values(
      v_endpoint,v_bounded_owner,'view',
      v_owner,'explicit_owner_grant','{}'::jsonb
    );
    raise exception 'Bounded target Endpoint grant unexpectedly succeeded.';
  exception when sqlstate '0A000' then
    null;
  end;

  perform set_config('request.jwt.claim.sub','96100000-0000-0000-0000-000000000001',true);

  v_result:=atlas.set_communication_endpoint_member_capability_self_api_v1(
    v_endpoint,v_member,'admin',true,'exact capability proof'
  );

  if (v_result->>'grantBasisKind')<>'explicit_owner_grant'
     or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_member,'admin')
     or atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_member,'view') then
    raise exception 'Exact explicit Endpoint capability leaked into sibling capabilities.';
  end if;

  select id into v_old_compat
  from atlas.communication_endpoint_member_grants
  where communication_endpoint_id=v_endpoint
    and membership_id=v_owner
    and capability='view'
    and grant_state='active'
    and grant_basis_kind='organization_owner_compatibility_cutover';

  perform atlas.set_communication_endpoint_member_capability_self_api_v1(
    v_endpoint,v_owner,'view',true,'explicitly retain view'
  );

  if not exists(
    select 1 from atlas.communication_endpoint_member_grants
    where id=v_old_compat
      and grant_state='revoked'
      and grant_basis_kind='organization_owner_compatibility_cutover'
  ) or not exists(
    select 1 from atlas.communication_endpoint_member_grants
    where communication_endpoint_id=v_endpoint
      and membership_id=v_owner
      and capability='view'
      and grant_state='active'
      and grant_basis_kind='explicit_owner_grant'
  ) then
    raise exception 'Explicit owner grant rewrote compatibility origin instead of revoke-and-append.';
  end if;

  begin
    update atlas.communication_endpoint_member_grants
    set grant_basis_kind='endpoint_creator_initial_grant'
    where communication_endpoint_id=v_endpoint
      and membership_id=v_owner
      and capability='view'
      and grant_state='active';
    raise exception 'Endpoint grant origin was mutable after creation.';
  exception when sqlstate '23514' then
    null;
  end;

  begin
    update atlas.communication_endpoint_member_grants
    set grant_state='active',revoked_at=null
    where id=v_old_compat;
    raise exception 'Revoked compatibility grant was reactivated in place.';
  exception when sqlstate '23514' then
    null;
  end;

  insert into atlas.organization_memberships(
    id,organization_id,user_id,role,active,permissions
  ) values(
    v_later_owner,v_org,
    '96100000-0000-0000-0000-000000000005'::uuid,
    'owner',true,'{}'::jsonb
  );

  perform set_config('request.jwt.claim.sub','96100000-0000-0000-0000-000000000005',true);

  v_result:=atlas.upsert_communication_endpoint_self_api_v1(
    v_org,null,'email','fixture@example.test',
    'Updated fixture inbox','{"updatedByLaterOwner":true}'::jsonb
  );

  if coalesce((v_result->>'created')::boolean,true)
     or exists(
       select 1 from atlas.communication_endpoint_member_grants
       where communication_endpoint_id=v_endpoint
         and membership_id=v_later_owner
     ) then
    raise exception 'Updating an existing Endpoint silently granted the editing owner authority.';
  end if;

  begin
    perform atlas.set_communication_endpoint_member_capability_self_api_v1(
      v_endpoint,v_other_member,'view',true,'cross organization target'
    );
    raise exception 'Root governance command accepted cross-Organization target.';
  exception when sqlstate '23514' then
    null;
  end;

  begin
    perform atlas.set_communication_endpoint_member_capability_self_api_v1(
      v_endpoint,v_bounded_owner,'view',true,'bounded target'
    );
    raise exception 'Root governance command accepted bounded target without calendar context.';
  exception when sqlstate '0A000' then
    null;
  end;

  v_result:=atlas.upsert_communication_endpoint_self_api_v1(
    v_org,null,'email','new-endpoint@example.test',
    'New governed endpoint','{}'::jsonb
  );
  v_new_endpoint:=(v_result->>'communicationEndpointId')::uuid;

  if not coalesce((v_result->>'created')::boolean,false) then
    raise exception 'New Endpoint creation did not report creation.';
  end if;

  select count(*) into v_count
  from atlas.communication_endpoint_member_grants
  where communication_endpoint_id=v_new_endpoint
    and membership_id=v_later_owner
    and grant_state='active'
    and grant_basis_kind='endpoint_creator_initial_grant';

  if v_count<>6 then
    raise exception 'New Endpoint creator did not receive six explicit initial grants.';
  end if;

  if not atlas.communication_endpoint_membership_has_capability_v1(
    v_new_endpoint,v_later_owner,'view'
  ) then
    raise exception 'Endpoint creator initial grant does not resolve.';
  end if;

  perform set_config('request.jwt.claim.sub','96100000-0000-0000-0000-000000000002',true);
  begin
    perform atlas.set_communication_endpoint_member_capability_self_api_v1(
      v_endpoint,v_member,'close',true,'bounded owner governance attempt'
    );
    raise exception 'Bounded owner governed Endpoint grants without calendar context.';
  exception when sqlstate '0A000' then
    null;
  end;

  update atlas.organization_memberships
  set role='member',updated_at=now()
  where id=v_owner;

  if exists(
    select 1 from atlas.communication_endpoint_member_grants
    where membership_id=v_owner
      and grant_state='active'
      and grant_basis_kind='organization_owner_compatibility_cutover'
  ) then
    raise exception 'Compatibility grants survived loss of owner continuity.';
  end if;

  if not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_owner,'view')
     or atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_owner,'admin') then
    raise exception 'Explicit grant did not persist independently or compatibility authority still resolved after role change.';
  end if;

  update atlas.organization_memberships
  set role='owner',updated_at=now()
  where id=v_owner;

  if atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_owner,'admin') then
    raise exception 'Restoring owner role resurrected old compatibility Endpoint authority.';
  end if;

  if not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_owner,'view') then
    raise exception 'Independent explicit Endpoint grant was lost when owner role changed.';
  end if;

  if not exists(
    select 1
    from atlas.communication_endpoint_member_grants
    where grant_basis_kind is not null
  ) then
    raise exception 'Endpoint grant-basis cutover produced no governed grants.';
  end if;
end;
$validation$;
