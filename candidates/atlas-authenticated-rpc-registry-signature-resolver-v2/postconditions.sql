-- Postconditions for Authenticated RPC Registry Signature Resolver v2.

do $$
declare
  v_named_oid oid;
  v_named_expected oid;
  v_alias_oid oid;
  v_alias_expected oid;
  v_long_oid oid;
  v_long_expected oid;
  v_stale_oid oid;
  v_drift_count integer;
begin
  v_named_oid := atlas.resolve_authenticated_rpc_registry_function_oid_v2(
    'atlas.configure_generic_email_endpoint_self_api_v1(p_organization_id uuid, p_organization_unit_id uuid, p_email_address text, p_display_name text, p_imap_host text, p_imap_port integer, p_imap_security text, p_smtp_host text, p_smtp_port integer, p_smtp_security text, p_username text, p_password text)'
  );
  v_named_expected := 'atlas.configure_generic_email_endpoint_self_api_v1(uuid,uuid,text,text,text,integer,text,text,integer,text,text,text)'::regprocedure::oid;

  if v_named_oid is distinct from v_named_expected then
    raise exception 'Named identity signature did not resolve to its current function OID.';
  end if;

  v_alias_oid := atlas.resolve_authenticated_rpc_registry_function_oid_v2(
    'atlas.issue_organization_employee_invitation_service_v1(uuid,timestamptz,uuid)'
  );
  v_alias_expected := 'atlas.issue_organization_employee_invitation_service_v1(uuid,timestamp with time zone,uuid)'::regprocedure::oid;

  if v_alias_oid is distinct from v_alias_expected then
    raise exception 'Type-alias registry signature did not preserve native regprocedure resolution.';
  end if;

  v_long_oid := atlas.resolve_authenticated_rpc_registry_function_oid_v2(
    'atlas.transition_organization_connected_source_authorization_self_api_v1(uuid,text,text[],jsonb,jsonb)'
  );
  v_long_expected := 'atlas.transition_organization_connected_source_authorization_self_api(uuid,text,text[],jsonb,jsonb)'::regprocedure::oid;

  if v_long_oid is distinct from v_long_expected then
    raise exception 'Long PostgreSQL identifier did not preserve native truncation resolution.';
  end if;

  v_stale_oid := atlas.resolve_authenticated_rpc_registry_function_oid_v2(
    'atlas.answer_owner_needs_from_you_v1(uuid,text,uuid,text,text)'
  );

  if v_stale_oid is not null then
    raise exception 'Genuinely absent historical overload must remain unresolved.';
  end if;

  select count(*) into v_drift_count
  from atlas.authenticated_rpc_registry_drift_v1();

  if v_drift_count < 0 then
    raise exception 'Impossible drift count.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.resolve_authenticated_rpc_registry_function_oid_v2(text)'::regprocedure,
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.resolve_authenticated_rpc_registry_function_oid_v2(text)'::regprocedure,
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'atlas.resolve_authenticated_rpc_registry_function_oid_v2(text)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Internal RPC registry resolver must not be directly executable by app/service roles.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.authenticated_rpc_registry_drift_v1()'::regprocedure,
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.authenticated_rpc_registry_drift_v1()'::regprocedure,
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.authenticated_rpc_registry_drift_v1()'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'RPC registry drift endpoint custody changed.';
  end if;
end
$$;
