-- Canonical postconditions for Atlas Canonical Person v1.
-- Runs only against the disposable production-schema clone.

do $$
declare
  v_missing text[];
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
    from information_schema.columns
    where table_schema='atlas'
      and table_name='people'
      and column_name='stable_key'
      and is_generated='ALWAYS'
  ) then
    raise exception 'People stable_key is not generated.';
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
    raise exception 'Canonical Person internal helpers became browser RPCs.';
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

  if not exists (
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='principals' and column_name='user_id' and is_nullable='NO'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='organization_memberships' and column_name='user_id' and is_nullable='NO'
  ) then
    raise exception 'Legacy user_id compatibility was removed too early.';
  end if;

  if not exists (
    select 1
    from pg_constraint c
    where c.conrelid='atlas.person_auth_credentials'::regclass
      and c.contype='u'
      and pg_get_constraintdef(c.oid) ilike '%auth_user_id%'
  ) then
    raise exception 'One auth credential to one Person uniqueness is missing.';
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

  if to_regclass('atlas.person_identity_subject_bindings') is not null then
    raise exception 'Institution-local identity was bound globally in Person tranche 1.';
  end if;
end;
$$;
