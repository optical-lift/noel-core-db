-- Atlas generic email account add API v1 postconditions.
-- Disposable production-schema clone only.
begin;

do $proof$
declare
  v_public regprocedure := to_regprocedure('public.configure_generic_email_endpoint_self_api_v1(uuid,uuid,text,text,text,integer,text,text,integer,text,text,text)');
  v_atlas regprocedure := to_regprocedure('atlas.configure_generic_email_endpoint_self_api_v1(uuid,uuid,text,text,text,integer,text,text,integer,text,text,text)');
begin
  if v_public is null then
    raise exception 'Public generic email setup RPC is missing.';
  end if;
  if v_atlas is null then
    raise exception 'Atlas generic email setup contract is missing.';
  end if;

  if has_function_privilege('anon',v_public,'EXECUTE')
     or has_function_privilege('anon',v_atlas,'EXECUTE') then
    raise exception 'Anonymous role received generic email setup authority.';
  end if;
  if not has_function_privilege('authenticated',v_public,'EXECUTE')
     or not has_function_privilege('authenticated',v_atlas,'EXECUTE') then
    raise exception 'Authenticated role is missing generic email setup authority.';
  end if;

  if not exists(
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where p.oid=v_atlas::oid
      and n.nspname='atlas'
      and p.prosecdef
  ) then
    raise exception 'Atlas generic email setup contract lost its security-definer boundary.';
  end if;
  if exists(
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where p.oid=v_public::oid
      and n.nspname='public'
      and p.prosecdef
  ) then
    raise exception 'Public generic email setup wrapper must remain a non-definer membrane.';
  end if;

  if not exists(
    select 1
    from atlas.authenticated_rpc_registry r
    where r.signature='atlas.configure_generic_email_endpoint_self_api_v1(p_organization_id uuid, p_organization_unit_id uuid, p_email_address text, p_display_name text, p_imap_host text, p_imap_port integer, p_imap_security text, p_smtp_host text, p_smtp_port integer, p_smtp_security text, p_username text, p_password text)'
      and r.classification='owner_admin_endpoint'
      and r.review_status='active'
      and r.authenticated_execute_expected
      and not r.anonymous_execute_expected
      and r.security_definer_expected
  ) then
    raise exception 'Generic email setup governance registration is incomplete.';
  end if;

  raise notice 'Atlas generic email account add API v1 postconditions passed.';
end;
$proof$;

rollback;