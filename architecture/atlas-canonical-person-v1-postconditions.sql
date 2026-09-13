-- Atlas Canonical Person v1 postcondition proof.
--
-- Reviewed candidate source only. This is NOT a canonical validation/migrations file.
-- After the governed Supabase CLI creates the canonical migration identity, this
-- proof should be promoted under the matching validation/migrations version and
-- run only against the disposable production-schema clone.

BEGIN;

do $proof$
declare
  v_missing text[];
  v_before_auth bigint;
  v_fixture_a uuid;
  v_fixture_b uuid;
begin
  select array_agg(name order by name)
  into v_missing
  from (
    values
      ('atlas.people'),
      ('atlas.person_auth_credentials')
  ) as required(name)
  where to_regclass(name) is null;

  if v_missing is not null then
    raise exception 'Canonical Person relations missing: %', v_missing;
  end if;

  if not exists (
    select 1
    from information_schema.columns c
    where c.table_schema='atlas'
      and c.table_name='people'
      and c.column_name='stable_key'
      and c.is_generated='ALWAYS'
  ) then
    raise exception 'People stable_key is not generated from canonical Person identity.';
  end if;

  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname in ('people','person_auth_credentials')
      and not c.relrowsecurity
  ) then
    raise exception 'Canonical Person tables are missing RLS.';
  end if;

  if has_table_privilege('anon','atlas.people','SELECT')
     or has_table_privilege('authenticated','atlas.people','SELECT')
     or has_table_privilege('anon','atlas.people','INSERT')
     or has_table_privilege('authenticated','atlas.people','INSERT')
     or has_table_privilege('anon','atlas.person_auth_credentials','SELECT')
     or has_table_privilege('authenticated','atlas.person_auth_credentials','SELECT')
     or has_table_privilege('anon','atlas.person_auth_credentials','INSERT')
     or has_table_privilege('authenticated','atlas.person_auth_credentials','INSERT') then
    raise exception 'Canonical Person tables widened direct browser privileges.';
  end if;

  if to_regprocedure('atlas.ensure_person_for_auth_user_v1(uuid,text)') is null
     or to_regprocedure('atlas.current_person_id_v1()') is null then
    raise exception 'Canonical Person compatibility helpers are missing.';
  end if;

  if has_function_privilege('anon','atlas.ensure_person_for_auth_user_v1(uuid,text)','EXECUTE')
     or has_function_privilege('authenticated','atlas.ensure_person_for_auth_user_v1(uuid,text)','EXECUTE')
     or has_function_privilege('anon','atlas.current_person_id_v1()','EXECUTE')
     or has_function_privilege('authenticated','atlas.current_person_id_v1()','EXECUTE') then
    raise exception 'Canonical Person internal helpers became direct browser RPCs.';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='principals' and column_name='person_id'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='organization_memberships' and column_name='person_id'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='household_members' and column_name='person_id'
  ) then
    raise exception 'Canonical Person compatibility links are incomplete.';
  end if;

  -- Tranche 1 must preserve the old columns and their requiredness so existing
  -- application contracts continue to work before Person-first RPC cutover.
  if not exists (
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='principals' and column_name='user_id' and is_nullable='NO'
  ) then
    raise exception 'Principals user_id compatibility was removed too early.';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='organization_memberships' and column_name='user_id' and is_nullable='NO'
  ) then
    raise exception 'Organization Membership user_id compatibility was removed too early.';
  end if;

  if exists (
    select 1
    from atlas.principals p
    left join atlas.person_auth_credentials c
      on c.auth_user_id=p.user_id and c.status='active'
    where p.user_id is not null
      and (p.person_id is null or c.person_id is distinct from p.person_id)
  ) then
    raise exception 'Existing Principal is not canonically Person-bound.';
  end if;

  if exists (
    select 1
    from atlas.organization_memberships m
    left join atlas.person_auth_credentials c
      on c.auth_user_id=m.user_id and c.status='active'
    where m.user_id is not null
      and (m.person_id is null or c.person_id is distinct from m.person_id)
  ) then
    raise exception 'Existing Organization Membership is not canonically Person-bound.';
  end if;

  if exists (
    select 1
    from atlas.household_members hm
    left join atlas.person_auth_credentials c
      on c.auth_user_id=hm.user_id and c.status='active'
    where hm.user_id is not null
      and (hm.person_id is null or c.person_id is distinct from hm.person_id)
  ) then
    raise exception 'Existing authenticated Household Member is not canonically Person-bound.';
  end if;

  if (
    select count(*) from atlas.person_auth_credentials where status='active'
  ) <> (
    select count(distinct user_id)
    from (
      select user_id from atlas.principals where user_id is not null
      union all
      select user_id from atlas.organization_memberships where user_id is not null
      union all
      select user_id from atlas.household_members where user_id is not null
    ) roots
  ) then
    raise exception 'One active credential binding per current durable human credential was not preserved.';
  end if;

  if not exists (
    select 1
    from pg_indexes
    where schemaname='atlas'
      and tablename='person_auth_credentials'
      and indexdef ilike '%unique%auth_user_id%'
  ) then
    raise exception 'One-auth-credential-to-one-Person uniqueness is missing.';
  end if;

  if (
    select count(*)
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and t.tgname in (
        'principal_person_compatibility_v1',
        'organization_membership_person_compatibility_v1',
        'household_member_person_compatibility_v1'
      )
      and not t.tgisinternal
  ) <> 3 then
    raise exception 'Dual-write Person compatibility trigger set is incomplete.';
  end if;

  -- The migration must not pretend organization-local identity_subjects are
  -- globally reconciled. No bulk Person binding is introduced in tranche 1.
  if to_regclass('atlas.person_identity_subject_bindings') is not null then
    raise exception 'Institution-local identity was bound globally before a separate adjudication contract.';
  end if;

  -- Pre-auth / collision fixture: same display name is legal, no login is born.
  select count(*) into v_before_auth from auth.users;

  insert into atlas.people(display_name,metadata)
  values ('Canonical Person Collision Fixture',jsonb_build_object('validationFixture',true))
  returning id into v_fixture_a;

  insert into atlas.people(display_name,metadata)
  values ('Canonical Person Collision Fixture',jsonb_build_object('validationFixture',true))
  returning id into v_fixture_b;

  if v_fixture_a=v_fixture_b then
    raise exception 'Distinct People collapsed under duplicate display name.';
  end if;

  if (select count(*) from auth.users) <> v_before_auth then
    raise exception 'Pre-auth Person creation changed auth.users.';
  end if;

  if exists (
    select 1 from atlas.person_auth_credentials
    where person_id in (v_fixture_a,v_fixture_b)
  ) then
    raise exception 'Pre-auth Person creation fabricated credentials.';
  end if;
end;
$proof$;

ROLLBACK;
