\set ON_ERROR_STOP on

-- The physical mark kernel must exist as a private Noel-owned substrate.
do $$
declare
  missing_table text;
  r record;
  expected_tables text[] := array[
    'channel_registry','relation_registry','source_objects','surfaces','captures',
    'capture_surfaces','capture_equivalences','regions','instances','components',
    'component_relations','sequence_zones','sequence_members','record_supersessions'
  ];
begin
  if not exists (select 1 from pg_namespace where nspname='mark') then
    raise exception 'MARK_POSTCONDITION: mark schema missing';
  end if;

  foreach missing_table in array expected_tables loop
    if to_regclass('mark.' || missing_table) is null then
      raise exception 'MARK_POSTCONDITION: missing table mark.%', missing_table;
    end if;
  end loop;

  if (select count(*) from mark.channel_registry) < 6 then
    raise exception 'MARK_POSTCONDITION: expected at least six physical channel seeds';
  end if;

  if (select count(*) from mark.relation_registry) < 14 then
    raise exception 'MARK_POSTCONDITION: expected physical relation registry seeds';
  end if;

  for r in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='mark' and c.relkind='r'
  loop
    if not (select relrowsecurity from pg_class where oid=('mark.' || quote_ident(r.relname))::regclass) then
      raise exception 'MARK_POSTCONDITION: RLS not enabled on mark.%', r.relname;
    end if;
  end loop;

  if to_regprocedure('mark.guard_frozen_row_v1()') is null then
    raise exception 'MARK_POSTCONDITION: frozen-row guard function missing';
  end if;

  if to_regprocedure('mark.guard_append_only_v1()') is null then
    raise exception 'MARK_POSTCONDITION: append-only guard function missing';
  end if;
end
$$;

-- Application/runtime roles must have no direct schema membrane access.
do $$
declare role_name text;
begin
  foreach role_name in array array['anon','authenticated','service_role'] loop
    if has_schema_privilege(role_name,'mark','USAGE') or has_schema_privilege(role_name,'mark','CREATE') then
      raise exception 'MARK_POSTCONDITION: role % has direct mark schema privilege', role_name;
    end if;
  end loop;
end
$$;

-- Freeze must be an irreversible source-truth transition.
do $$
declare
  test_id bigint;
  blocked boolean := false;
begin
  insert into mark.source_objects(object_key,object_kind,record_status)
  values ('__mark_validation_freeze_v1__','validation_fixture','reviewed')
  returning source_object_id into test_id;

  update mark.source_objects
  set record_status='frozen'
  where source_object_id=test_id;

  if not exists (
    select 1 from mark.source_objects
    where source_object_id=test_id and record_status='frozen' and frozen_at is not null
  ) then
    raise exception 'MARK_POSTCONDITION: freeze transition did not set frozen_at';
  end if;

  begin
    update mark.source_objects
    set object_kind='forbidden_mutation'
    where source_object_id=test_id;
  exception when others then
    if position('MARK_FROZEN_RECORD_IMMUTABLE' in sqlerrm) > 0 then
      blocked := true;
    else
      raise;
    end if;
  end;

  if not blocked then
    raise exception 'MARK_POSTCONDITION: frozen record mutation was not blocked';
  end if;
end
$$;

-- Supersession lineage itself must be append-only.
do $$
declare
  sid bigint;
  blocked boolean := false;
begin
  insert into mark.record_supersessions(object_type,old_object_key,new_object_key,reason)
  values ('source_object','__mark_validation_old__','__mark_validation_new__','validation')
  returning supersession_id into sid;

  begin
    update mark.record_supersessions set reason='forbidden_mutation' where supersession_id=sid;
  exception when others then
    if position('MARK_APPEND_ONLY' in sqlerrm) > 0 then
      blocked := true;
    else
      raise;
    end if;
  end;

  if not blocked then
    raise exception 'MARK_POSTCONDITION: supersession lineage mutation was not blocked';
  end if;
end
$$;

-- Capture byte identity must be unique once known.
do $$
begin
  if not exists (
    select 1
    from pg_indexes
    where schemaname='mark'
      and tablename='captures'
      and indexname='captures_sha256_unique_when_known'
  ) then
    raise exception 'MARK_POSTCONDITION: verified capture SHA-256 uniqueness index missing';
  end if;
end
$$;
