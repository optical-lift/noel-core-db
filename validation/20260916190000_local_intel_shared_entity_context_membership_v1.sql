begin;

-- Read-only contract validation for Shared Intelligence entity/context custody.
do $validation$
declare
  v_missing_memberships bigint;
  v_rls_enabled boolean;
  v_legacy_context_not_null boolean;
  v_trigger_count bigint;
  v_direct_app_grants bigint;
begin
  if to_regclass('local_intel.entity_context_memberships') is null then
    raise exception 'local_intel.entity_context_memberships is missing';
  end if;

  select count(*)
  into v_missing_memberships
  from local_intel.entities e
  left join local_intel.entity_context_memberships m
    on m.entity_id=e.id
   and m.local_context_id=e.local_context_id
  where m.id is null;

  if v_missing_memberships <> 0 then
    raise exception '% entities are missing the compatibility context membership', v_missing_memberships;
  end if;

  select c.relrowsecurity
  into v_rls_enabled
  from pg_class c
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='local_intel'
    and c.relname='entity_context_memberships';

  if coalesce(v_rls_enabled,false) is not true then
    raise exception 'entity_context_memberships must have RLS enabled';
  end if;

  select (c.is_nullable='NO')
  into v_legacy_context_not_null
  from information_schema.columns c
  where c.table_schema='local_intel'
    and c.table_name='entities'
    and c.column_name='local_context_id';

  if coalesce(v_legacy_context_not_null,false) is not true then
    raise exception 'v1 must preserve inherited entities.local_context_id NOT NULL compatibility';
  end if;

  select count(*)
  into v_trigger_count
  from pg_trigger t
  join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='local_intel'
    and c.relname='entities'
    and t.tgname='entities_context_membership_compatibility_v1'
    and not t.tgisinternal;

  if v_trigger_count <> 1 then
    raise exception 'entities_context_membership_compatibility_v1 trigger is missing or duplicated';
  end if;

  select count(*)
  into v_direct_app_grants
  from information_schema.role_table_grants g
  where g.table_schema='local_intel'
    and g.table_name='entity_context_memberships'
    and g.grantee in ('anon','authenticated','service_role');

  if v_direct_app_grants <> 0 then
    raise exception 'entity_context_memberships unexpectedly grants direct application-role table access';
  end if;

  if not exists (
    select 1
    from pg_description d
    join pg_class c on c.oid=d.objoid
    join pg_namespace n on n.oid=c.relnamespace
    join pg_attribute a on a.attrelid=c.oid and a.attnum=d.objsubid
    where n.nspname='local_intel'
      and c.relname='entities'
      and a.attname='local_context_id'
      and d.description ilike '%must not be interpreted as ownership%'
  ) then
    raise exception 'entities.local_context_id compatibility/ownership comment is missing';
  end if;
end;
$validation$;

rollback;
