do $validation$
declare
  v_v1 oid;
  v_v2 oid;
  v_def text;
  v_secdef boolean;
  v_public_execute boolean;
  v_named_count integer;
  v_drift integer;
begin
  v_v1 := to_regprocedure('atlas.record_flower_preparation_directive_v1(uuid,jsonb,text,text)');
  v_v2 := to_regprocedure('atlas.record_flower_preparation_directive_v2(uuid,jsonb,text,text)');

  if v_v1 is null then
    raise exception 'Expected existing Flower Preparation v1 authority.';
  end if;
  if v_v2 is null then
    raise exception 'Expected Flower Preparation v2 authority.';
  end if;

  select p.prosecdef, pg_get_functiondef(p.oid)
  into v_secdef, v_def
  from pg_proc p
  where p.oid=v_v2;

  if not v_secdef then
    raise exception 'Flower Preparation v2 must remain SECURITY DEFINER.';
  end if;
  if pg_get_function_result(v_v2) <> 'jsonb' then
    raise exception 'Flower Preparation v2 must return jsonb.';
  end if;

  if position('resolve_company_operating_knowledge_v1' in v_def)=0 then
    raise exception 'Flower Preparation v2 must resolve established Operating Knowledge for omitted bundle size.';
  end if;
  if position('__bundleSizeSource'', ''owner_explicit''' in v_def)=0 then
    raise exception 'Flower Preparation v2 must preserve explicit Owner bundle-size precedence.';
  end if;
  if position('operating_knowledge_default' in v_def)=0
     or position('operatingKnowledgeDefault' in v_def)=0 then
    raise exception 'Flower Preparation v2 must preserve applied Operating Knowledge provenance.';
  end if;
  if position('p_owner_review_task_id::text || ''|'' || p_lines::text' in v_def)=0 then
    raise exception 'Flower Preparation v2 idempotency must fingerprint the original Owner request before defaults.';
  end if;

  if not has_function_privilege('authenticated',v_v2,'execute') then
    raise exception 'authenticated must execute Flower Preparation v2.';
  end if;
  if has_function_privilege('anon',v_v2,'execute') then
    raise exception 'anon must not execute Flower Preparation v2.';
  end if;
  if has_function_privilege('service_role',v_v2,'execute') then
    raise exception 'service_role must not execute Flower Preparation v2.';
  end if;

  select exists (
    select 1
    from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
    where acl.grantee=0 and acl.privilege_type='EXECUTE'
  ) into v_public_execute
  from pg_proc p where p.oid=v_v2;

  if v_public_execute then
    raise exception 'PUBLIC must not execute Flower Preparation v2.';
  end if;

  select count(*) into v_named_count
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas' and p.proname='record_flower_preparation_directive_v2';

  if v_named_count <> 1 then
    raise exception 'Expected exactly one Flower Preparation v2 overload; found %',v_named_count;
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema='atlas'
      and table_name='flower_preparation_directive_lines'
      and column_name='metadata'
      and data_type='jsonb'
  ) then
    raise exception 'Flower Preparation line metadata provenance seam is missing.';
  end if;

  select count(*) into v_drift from atlas.authenticated_rpc_registry_drift_v1();
  if v_drift <> 0 then
    raise exception 'Flower Preparation v2 validation found % authenticated RPC drift rows.',v_drift;
  end if;
end;
$validation$;