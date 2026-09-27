-- Reality entity appellations v1 dependency validation.
-- Safe against the pre-migration production schema.

do $$
begin
  if to_regclass('reality.entities') is null then
    raise exception 'reality.entities is required';
  end if;

  if not exists(
    select 1 from information_schema.columns
    where table_schema='reality' and table_name='entities' and column_name='id' and data_type='uuid'
  ) or not exists(
    select 1 from information_schema.columns
    where table_schema='reality' and table_name='entities' and column_name='entity_kind'
  ) or not exists(
    select 1 from information_schema.columns
    where table_schema='reality' and table_name='entities' and column_name='display_name'
  ) or not exists(
    select 1 from information_schema.columns
    where table_schema='reality' and table_name='entities' and column_name='identity_state'
  ) then
    raise exception 'reality.entities identity contract is incomplete';
  end if;

  if not exists(select 1 from pg_roles where rolname='service_role') then
    raise exception 'service_role is required';
  end if;
end;
$$;
