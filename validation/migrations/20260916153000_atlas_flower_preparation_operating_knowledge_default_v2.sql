do $validation$
declare
  v_v1 oid;
  v_v2 oid;
  v_def text;
  v_secdef boolean;
  v_public_execute boolean;
  v_named_count integer;
  v_registry_count integer;
  v_table_rls boolean;
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
  where p.oid = v_v2;

  if not v_secdef then
    raise exception 'Flower Preparation v2 must remain SECURITY DEFINER.';
  end if;
  if pg_get_function_result(v_v2) <> 'jsonb' then
    raise exception 'Flower Preparation v2 must return jsonb.';
  end if;

  if position('resolve_company_operating_knowledge_v1' in v_def) = 0 then
    raise exception 'Flower Preparation v2 must resolve established Operating Knowledge for omitted bundle size.';
  end if;
  if position('record_flower_preparation_directive_v1' in v_def) = 0 then
    raise exception 'Flower Preparation v2 must delegate final directive/release authority to unchanged v1.';
  end if;
  if position('v_output_kind = ''bundle'' and v_stems_text = ''''' in v_def) = 0 then
    raise exception 'Flower Preparation v2 must resolve only an omitted bundle-size value.';
  end if;
  if position('v_output_kind = ''bundle''' in v_def) = 0
     or position('sourceKind'', ''owner_explicit''' in v_def) = 0 then
    raise exception 'Flower Preparation v2 must preserve explicit Owner bundle-size precedence.';
  end if;
  if position('p_owner_review_task_id::text || ''|'' || p_lines::text' in v_def) = 0 then
    raise exception 'Flower Preparation v2 must fingerprint the original Owner request before rule defaults.';
  end if;
  if position('flower_preparation_directive_line_knowledge_provenance' in v_def) = 0 then
    raise exception 'Flower Preparation v2 must preserve immutable per-line rule/source provenance.';
  end if;

  if not has_function_privilege('authenticated', v_v2, 'execute') then
    raise exception 'authenticated must execute Flower Preparation v2.';
  end if;
  if has_function_privilege('anon', v_v2, 'execute') then
    raise exception 'anon must not execute Flower Preparation v2.';
  end if;
  if has_function_privilege('service_role', v_v2, 'execute') then
    raise exception 'service_role must not execute Flower Preparation v2.';
  end if;

  select exists (
    select 1
    from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    where acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
  ) into v_public_execute
  from pg_proc p where p.oid = v_v2;

  if v_public_execute then
    raise exception 'PUBLIC must not execute Flower Preparation v2.';
  end if;

  select count(*) into v_named_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atlas'
    and p.proname = 'record_flower_preparation_directive_v2';

  if v_named_count <> 1 then
    raise exception 'Expected exactly one Flower Preparation v2 overload; found %', v_named_count;
  end if;

  if to_regclass('atlas.flower_preparation_directive_line_knowledge_provenance') is null then
    raise exception 'Flower Preparation knowledge provenance table is missing.';
  end if;

  select c.relrowsecurity into v_table_rls
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'atlas'
    and c.relname = 'flower_preparation_directive_line_knowledge_provenance';

  if coalesce(v_table_rls, false) is not true then
    raise exception 'Flower Preparation knowledge provenance must have RLS enabled.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'atlas'
      and c.relname = 'flower_preparation_directive_line_knowledge_provenance'
      and t.tgname = 'flower_prep_knowledge_provenance_immutable_v1'
      and not t.tgisinternal
  ) then
    raise exception 'Flower Preparation knowledge provenance immutability trigger is missing.';
  end if;

  select count(*) into v_registry_count
  from atlas.authenticated_rpc_registry r
  where r.signature = 'atlas.record_flower_preparation_directive_v2(uuid, jsonb, text, text)'
    and r.classification = 'app_endpoint'
    and r.review_status = 'active'
    and r.authenticated_execute_expected is true
    and r.anonymous_execute_expected is false
    and r.service_execute_expected is false
    and r.security_definer_expected is true;

  if v_registry_count <> 1 then
    raise exception 'Flower Preparation v2 authenticated RPC registry row is missing or inconsistent.';
  end if;

  if exists (
    select 1
    from atlas.authenticated_rpc_registry r
    where r.signature = 'atlas.record_flower_preparation_directive_v1(uuid, jsonb, text, text)'
      and r.review_status <> 'active'
  ) then
    raise exception 'Flower Preparation v1 authority was disturbed while adding v2.';
  end if;
end;
$validation$;