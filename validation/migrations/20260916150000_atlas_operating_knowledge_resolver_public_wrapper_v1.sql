do $validation$
declare
  v_public_oid oid;
  v_atlas_oid oid;
  v_public_def text;
  v_public_secdef boolean;
  v_atlas_secdef boolean;
  v_public_execute boolean;
  v_named_count integer;
begin
  v_public_oid := to_regprocedure('public.resolve_company_operating_knowledge_v1(uuid,text,jsonb,timestamptz)');
  v_atlas_oid := to_regprocedure('atlas.resolve_company_operating_knowledge_v1(uuid,text,jsonb,timestamptz)');

  if v_public_oid is null then
    raise exception 'Expected public Company Operating Knowledge resolver wrapper.';
  end if;
  if v_atlas_oid is null then
    raise exception 'Expected underlying Atlas Company Operating Knowledge resolver authority.';
  end if;

  select p.prosecdef, pg_get_functiondef(p.oid)
    into v_public_secdef, v_public_def
  from pg_proc p where p.oid=v_public_oid;

  select p.prosecdef into v_atlas_secdef
  from pg_proc p where p.oid=v_atlas_oid;

  if v_public_secdef then
    raise exception 'Public Company Operating Knowledge resolver wrapper must remain SECURITY INVOKER.';
  end if;
  if not v_atlas_secdef then
    raise exception 'Underlying Atlas Company Operating Knowledge resolver unexpectedly lost SECURITY DEFINER.';
  end if;
  if pg_get_function_result(v_public_oid) <> 'jsonb' then
    raise exception 'Public Company Operating Knowledge resolver wrapper must return jsonb.';
  end if;
  if position('atlas.resolve_company_operating_knowledge_v1(' in v_public_def)=0 then
    raise exception 'Public Company Operating Knowledge resolver wrapper does not delegate to Atlas authority.';
  end if;

  if not has_function_privilege('authenticated',v_public_oid,'execute') then
    raise exception 'authenticated must execute public Company Operating Knowledge resolver wrapper.';
  end if;
  if not has_function_privilege('service_role',v_public_oid,'execute') then
    raise exception 'service_role must execute public Company Operating Knowledge resolver wrapper.';
  end if;
  if has_function_privilege('anon',v_public_oid,'execute') then
    raise exception 'anon must not execute public Company Operating Knowledge resolver wrapper.';
  end if;

  select exists (
    select 1
    from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
    where acl.grantee=0 and acl.privilege_type='EXECUTE'
  ) into v_public_execute
  from pg_proc p where p.oid=v_public_oid;

  if v_public_execute then
    raise exception 'PUBLIC must not execute public Company Operating Knowledge resolver wrapper.';
  end if;

  select count(*) into v_named_count
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='resolve_company_operating_knowledge_v1';

  if v_named_count <> 1 then
    raise exception 'Expected exactly one public Company Operating Knowledge resolver overload; found %',v_named_count;
  end if;
end;
$validation$;
