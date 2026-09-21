-- Postconditions for Atlas Organization Membership Person Root v1.
-- Runs only against the disposable production-schema clone.

do $$
declare
  v_person uuid;
  v_org uuid;
  v_membership uuid;
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema='atlas'
      and table_name='organization_memberships'
      and column_name='person_id'
      and is_nullable='NO'
  ) then
    raise exception 'organization_memberships.person_id is not required.';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema='atlas'
      and table_name='organization_memberships'
      and column_name='user_id'
      and is_nullable='YES'
  ) then
    raise exception 'organization_memberships.user_id is still credential-required.';
  end if;

  if not exists (
    select 1
    from pg_constraint c
    where c.conrelid='atlas.organization_memberships'::regclass
      and c.conname='organization_memberships_user_id_fkey'
      and pg_get_constraintdef(c.oid) ilike '%ON DELETE SET NULL%'
  ) then
    raise exception 'Organization Membership auth credential FK does not preserve the relationship on credential deletion.';
  end if;

  if not exists (
    select 1
    from pg_indexes i
    where i.schemaname='atlas'
      and i.tablename='organization_memberships'
      and i.indexname='organization_memberships_organization_person_uq'
      and i.indexdef ilike '%organization_id, person_id%'
  ) then
    raise exception 'Organization Membership Person uniqueness is missing.';
  end if;

  if exists (
    select 1
    from atlas.organization_memberships
    where person_id is null
  ) then
    raise exception 'Existing Organization Membership lacks canonical Person.';
  end if;

  if exists (
    select 1
    from atlas.organization_memberships m
    join atlas.person_auth_credentials c
      on c.auth_user_id=m.user_id
     and c.status='active'
    where m.user_id is not null
      and c.person_id is distinct from m.person_id
  ) then
    raise exception 'Existing Organization Membership credential resolves to a different Person.';
  end if;

  -- Prove a real Person↔Organization relationship can exist without auth.users.
  insert into atlas.organizations(stable_key,name,status,metadata,onboarding_state)
  values(
    'validation:organization-membership-person-root-v1',
    'Relationship Delivery Validation Organization',
    'active',
    jsonb_build_object('source','organization_membership_person_root_v1_validation'),
    'new'
  )
  returning id into v_org;

  insert into atlas.people(display_name,status,metadata)
  values(
    'Relationship Delivery Validation Person',
    'active',
    jsonb_build_object('source','organization_membership_person_root_v1_validation')
  )
  returning id into v_person;

  insert into atlas.organization_memberships(
    organization_id,
    user_id,
    person_id,
    role,
    active,
    permissions
  ) values(
    v_org,
    null,
    v_person,
    'member',
    true,
    '{}'::jsonb
  )
  returning id into v_membership;

  if not exists (
    select 1
    from atlas.organization_memberships
    where id=v_membership
      and person_id=v_person
      and user_id is null
      and active
  ) then
    raise exception 'Accountless Person↔Organization Membership could not be established.';
  end if;

  delete from atlas.organization_memberships where id=v_membership;
  delete from atlas.people where id=v_person;
  delete from atlas.organizations where id=v_org;
end;
$$;
