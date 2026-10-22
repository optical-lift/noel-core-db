-- POST-CANDIDATE CHECKS: disposable production-schema clone ONLY.
-- Not a production migration; execute after reviewing/applying the candidate
-- to the clone. No tenant rows, source text or private data are read.
do $$
declare
  v_relation_has_org_fks int;
  v_other_rows bigint;
begin
  if not exists(
    select 1 from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas' and c.relname='work_item_relations'
      and c.relkind='r'
  ) then raise exception 'Canonical Work relation table missing.'; end if;

  select count(*) into v_relation_has_org_fks
  from pg_catalog.pg_constraint c
  where c.conrelid='atlas.work_item_relations'::regclass
    and c.contype='f'
    and pg_catalog.pg_get_constraintdef(c.oid) like
      '%organization_id%';
  if v_relation_has_org_fks<2 then
    raise exception 'Organization-coherent Work foreign keys missing.';
  end if;

  if not exists(select 1 from pg_catalog.pg_trigger t
    where t.tgrelid='atlas.work_item_relations'::regclass
      and t.tgname='guard_work_item_depends_on_cycle_v1'
      and not t.tgisinternal) then
    raise exception 'Global dependency cycle guard missing.';
  end if;

  if not exists(select 1 from pg_catalog.pg_class c
    where c.oid='atlas.work_item_prerequisite_events_v1'::regclass
      and c.relrowsecurity) then
    raise exception 'Prerequisite event evidence not RLS-protected.';
  end if;

  if pg_catalog.has_table_privilege(
    'authenticated','atlas.work_item_prerequisite_events_v1','SELECT') or
     pg_catalog.has_table_privilege(
    'anon','atlas.work_item_prerequisite_events_v1','SELECT') then
    raise exception 'Direct prerequisite event read permissions leaked.';
  end if;

  if pg_catalog.has_function_privilege(
    'anon','public.atlas_work_prerequisites_self_api_v1(uuid,uuid,uuid)','EXECUTE') or
     pg_catalog.has_function_privilege(
    'anon','public.atlas_set_work_prerequisite_self_api_v1(uuid,uuid,uuid,uuid,boolean,text,text)','EXECUTE') then
    raise exception 'Anonymous prerequisite RPC exposure.';
  end if;

  if not pg_catalog.has_function_privilege(
    'authenticated','public.atlas_work_prerequisites_self_api_v1(uuid,uuid,uuid)','EXECUTE') or
     not pg_catalog.has_function_privilege(
    'authenticated','public.atlas_set_work_prerequisite_self_api_v1(uuid,uuid,uuid,uuid,boolean,text,text)','EXECUTE') then
    raise exception 'Authenticated guarded RPC entrypoints unavailable.';
  end if;

  if not exists(select 1 from pg_catalog.pg_constraint c
    where c.conrelid='atlas.work_item_relations'::regclass
      and c.contype='c'
      and pg_catalog.pg_get_constraintdef(c.oid) like '%depends_on%') then
    raise exception 'Existing Work relation vocabulary was damaged.';
  end if;

  -- These postconditions do not prove user authorization. That requires
  -- distinct real authenticated principal and seat-only sessions in clone.
  raise notice 'Schema postconditions passed, but auth/cycle transaction tests remain required.';
end;
$$;
