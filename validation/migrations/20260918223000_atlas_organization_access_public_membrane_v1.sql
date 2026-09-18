do $validation$
declare
  v_public_oid oid := to_regprocedure('public.organization_access_self_api_v1()');
  v_atlas_oid oid := to_regprocedure('atlas.organization_access_self_api_v1()');
  v_public_def text;
  v_public_secdef boolean;
  v_atlas_secdef boolean;
  v_public_execute boolean;
begin
  if v_public_oid is null then
    raise exception 'Expected public organization-access browser membrane.';
  end if;
  if v_atlas_oid is null then
    raise exception 'Expected underlying Atlas organization-access authority.';
  end if;

  select p.prosecdef, pg_get_functiondef(p.oid)
    into v_public_secdef, v_public_def
  from pg_proc p
  where p.oid = v_public_oid;

  select p.prosecdef
    into v_atlas_secdef
  from pg_proc p
  where p.oid = v_atlas_oid;

  if v_public_secdef then
    raise exception 'Public organization-access wrapper must remain SECURITY INVOKER.';
  end if;
  if not v_atlas_secdef then
    raise exception 'Underlying Atlas organization-access authority unexpectedly lost SECURITY DEFINER.';
  end if;
  if pg_get_function_result(v_public_oid) <> 'jsonb' then
    raise exception 'Public organization-access wrapper must return jsonb.';
  end if;
  if position('atlas.organization_access_self_api_v1()' in v_public_def) = 0 then
    raise exception 'Public organization-access wrapper does not delegate to the expected Atlas authority.';
  end if;

  if not has_function_privilege('authenticated', v_public_oid, 'execute') then
    raise exception 'authenticated must execute public organization-access wrapper.';
  end if;
  if not has_function_privilege('service_role', v_public_oid, 'execute') then
    raise exception 'service_role must execute public organization-access wrapper.';
  end if;
  if has_function_privilege('anon', v_public_oid, 'execute') then
    raise exception 'anon must not execute public organization-access wrapper.';
  end if;

  select exists (
    select 1
    from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    where acl.grantee = 0
      and acl.privilege_type = 'EXECUTE'
  )
    into v_public_execute
  from pg_proc p
  where p.oid = v_public_oid;

  if v_public_execute then
    raise exception 'PUBLIC must not execute public organization-access wrapper.';
  end if;
end;
$validation$;
