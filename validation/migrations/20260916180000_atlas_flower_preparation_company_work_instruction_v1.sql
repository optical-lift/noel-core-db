do $validation$
declare
  v_sync oid;
  v_worker_day oid;
  v_worker_day_public oid;
  v_sync_def text;
  v_worker_day_def text;
  v_worker_day_public_def text;
  v_public_execute boolean;
  v_worker_public_authenticated_grant boolean;
  v_worker_public_anon_grant boolean;
  v_worker_public_service_grant boolean;
  v_worker_public_public_grant boolean;
begin
  v_sync := to_regprocedure('atlas.sync_flower_preparation_company_work_instruction_v1(uuid)');
  v_worker_day := to_regprocedure('atlas.company_work_worker_day_self_api_v1(date,integer)');
  v_worker_day_public := to_regprocedure('public.company_work_worker_day_self_api_v1(date,integer)');

  if v_sync is null then
    raise exception 'Flower Preparation -> Company Work instruction synchronizer is missing.';
  end if;
  if v_worker_day is null then
    raise exception 'Company Work Worker Day read is missing.';
  end if;
  if v_worker_day_public is null then
    raise exception 'Public Company Work Worker Day browser membrane is missing.';
  end if;

  select pg_get_functiondef(v_sync) into v_sync_def;
  select pg_get_functiondef(v_worker_day) into v_worker_day_def;
  select pg_get_functiondef(v_worker_day_public) into v_worker_day_public_def;

  if position('flower_preparation_directive_line_knowledge_provenance' in v_sync_def) = 0
     or position('work_execution_adapters' in v_sync_def) = 0
     or position('operatingInstructionSnapshot' in v_sync_def) = 0 then
    raise exception 'Flower Preparation instruction projection must derive from immutable directive provenance and the existing work adapter.';
  end if;

  if position('resolve_company_operating_knowledge_v1' in v_sync_def) > 0 then
    raise exception 'Company Work instruction projection must not re-resolve Operating Knowledge.';
  end if;

  if position('insert into atlas.work_items' in lower(v_sync_def)) > 0
     or position('insert into atlas.work_allocations' in lower(v_sync_def)) > 0 then
    raise exception 'Instruction projection must not create a second Company Work identity or responsibility allocation.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='flower_preparation_directive_line_knowledge_provenance'
      and t.tgname='flower_prep_project_company_work_instruction_v1'
      and not t.tgisinternal
  ) then
    raise exception 'Flower Preparation Company Work instruction trigger is missing.';
  end if;

  if has_function_privilege('authenticated', v_sync, 'execute')
     or has_function_privilege('anon', v_sync, 'execute')
     or has_function_privilege('service_role', v_sync, 'execute') then
    raise exception 'Internal Flower Preparation instruction synchronizer must not be directly executable by browser/service roles.';
  end if;

  select exists (
    select 1
    from aclexplode(coalesce(p.proacl, acldefault('f',p.proowner))) acl
    where acl.grantee=0 and acl.privilege_type='EXECUTE'
  ) into v_public_execute
  from pg_proc p where p.oid=v_sync;

  if v_public_execute then
    raise exception 'PUBLIC must not execute the internal Flower Preparation instruction synchronizer.';
  end if;

  if position('''requiredWork''' in v_worker_day_def) = 0
     or position('''instructions''' in v_worker_day_def) = 0
     or position('''operatingInstructionSnapshot''' in v_worker_day_def) = 0 then
    raise exception 'Worker Day must expose the frozen required Company Work instruction snapshot.';
  end if;

  if position('resolve_company_operating_knowledge_v1' in v_worker_day_def) > 0 then
    raise exception 'Worker Day must not resolve Company Operating Knowledge at read time.';
  end if;

  if position('worker_week_projection_sources' in v_worker_day_def) = 0
     or position('source_role=''required''' in replace(v_worker_day_def,' ','')) = 0 then
    raise exception 'Worker Day instruction enrichment must remain grounded in required Company Work sources.';
  end if;

  -- Preserve the established two-layer Worker Day membrane: the internal Atlas
  -- implementation is service-only, while authenticated browser execution is
  -- granted on the public delegating wrapper.
  if has_function_privilege('authenticated', v_worker_day, 'execute')
     or has_function_privilege('anon', v_worker_day, 'execute')
     or not has_function_privilege('service_role', v_worker_day, 'execute') then
    raise exception 'Internal Worker Day execution privilege membrane changed.';
  end if;

  if position('atlas.company_work_worker_day_self_api_v1' in v_worker_day_public_def) = 0 then
    raise exception 'Public Worker Day membrane no longer delegates to the governed Atlas implementation.';
  end if;

  -- The disposable Supabase clone recreates platform roles locally, so inherited
  -- effective-role answers from has_function_privilege() are not a production-role
  -- graph proof. Inspect the function ACL itself: authenticated + service_role are
  -- explicitly admitted; anon and PUBLIC are not.
  select
    coalesce(bool_or(acl.grantee=(select oid from pg_roles where rolname='authenticated') and acl.privilege_type='EXECUTE'),false),
    coalesce(bool_or(acl.grantee=(select oid from pg_roles where rolname='anon') and acl.privilege_type='EXECUTE'),false),
    coalesce(bool_or(acl.grantee=(select oid from pg_roles where rolname='service_role') and acl.privilege_type='EXECUTE'),false),
    coalesce(bool_or(acl.grantee=0 and acl.privilege_type='EXECUTE'),false)
  into
    v_worker_public_authenticated_grant,
    v_worker_public_anon_grant,
    v_worker_public_service_grant,
    v_worker_public_public_grant
  from pg_proc p
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f',p.proowner))) acl
  where p.oid=v_worker_day_public;

  if not v_worker_public_authenticated_grant then
    raise exception 'Authenticated public Worker Day direct execution grant was lost.';
  end if;
  if v_worker_public_anon_grant or v_worker_public_public_grant then
    raise exception 'Anonymous/PUBLIC direct Worker Day execution must remain denied.';
  end if;
  if not v_worker_public_service_grant then
    raise exception 'Service-role public Worker Day direct execution grant was lost.';
  end if;

  if to_regclass('atlas.flower_preparation_directive_line_knowledge_provenance') is null then
    raise exception 'Immutable Flower Preparation knowledge provenance authority is missing.';
  end if;

  if to_regprocedure('atlas.record_flower_preparation_directive_v1(uuid,jsonb,text,text)') is null
     or to_regprocedure('atlas.record_flower_preparation_directive_v2(uuid,jsonb,text,text)') is null then
    raise exception 'Flower Preparation v1/v2 authority was disturbed.';
  end if;
end;
$validation$;
