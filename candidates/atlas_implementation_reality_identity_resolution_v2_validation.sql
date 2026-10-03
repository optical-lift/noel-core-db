begin;

-- Validation for Atlas Implementation Reality Identity Resolution v2.
-- Run only after the candidate membrane is installed in a disposable clone.

do $validation$
declare
  v_internal_oid oid;
  v_public_oid oid;
  v_internal_source text;
  v_public_source text;
begin
  v_internal_oid := to_regprocedure(
    'atlas.implementation_reality_identity_options_self_api_v2(uuid,text,text,integer)'
  );
  v_public_oid := to_regprocedure(
    'public.implementation_reality_identity_options_self_api_v2(uuid,text,text,integer)'
  );

  if v_internal_oid is null then
    raise exception 'Internal identity resolver v2 is missing.';
  end if;
  if v_public_oid is null then
    raise exception 'Public identity resolver v2 membrane is missing.';
  end if;

  select pg_get_functiondef(v_internal_oid) into v_internal_source;
  select pg_get_functiondef(v_public_oid) into v_public_source;

  if position('organization_unit' in v_internal_source)=0 then
    raise exception 'Identity resolver v2 does not admit organization_unit.';
  end if;
  if position('case_bound_organization_unit' in v_internal_source)=0 then
    raise exception 'Organization Unit options do not preserve case-bound match basis.';
  end if;
  if position('b.state in (''bound'',''activated'')' in v_internal_source)=0 then
    raise exception 'Organization Unit resolution is not restricted to current bound/activated case scope.';
  end if;
  if position('u.status=''active''' in v_internal_source)=0 then
    raise exception 'Organization Unit resolution is not restricted to active Units.';
  end if;
  if position('implementation_reality_identity_options_self_api_v1' in v_internal_source)=0 then
    raise exception 'Identity resolver v2 must delegate legacy kinds to v1 rather than fork their semantics.';
  end if;

  if not exists(
    select 1
    from pg_proc p
    where p.oid=v_internal_oid
      and p.provolatile='s'
      and p.prosecdef
  ) then
    raise exception 'Internal identity resolver v2 must remain STABLE SECURITY DEFINER.';
  end if;

  if not exists(
    select 1
    from pg_proc p
    where p.oid=v_public_oid
      and p.provolatile='s'
      and p.prosecdef
  ) then
    raise exception 'Public identity resolver v2 must remain STABLE SECURITY DEFINER.';
  end if;

  if has_function_privilege(
    'anon',
    'public.implementation_reality_identity_options_self_api_v2(uuid,text,text,integer)',
    'EXECUTE'
  ) then
    raise exception 'anon must not execute the public identity resolver v2.';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.implementation_reality_identity_options_self_api_v2(uuid,text,text,integer)',
    'EXECUTE'
  ) then
    raise exception 'authenticated must execute the public identity resolver v2.';
  end if;

  if has_function_privilege(
    'authenticated',
    'atlas.implementation_reality_identity_options_self_api_v2(uuid,text,text,integer)',
    'EXECUTE'
  ) then
    raise exception 'authenticated must not execute the internal atlas identity resolver v2 directly.';
  end if;

  if position('insert into' in lower(v_internal_source))>0
     or position('update ' in lower(v_internal_source))>0
     or position('delete from' in lower(v_internal_source))>0 then
    raise exception 'Identity resolver v2 must remain read-only.';
  end if;

  if position('atlas.implementation_reality_identity_options_self_api_v2' in v_public_source)=0 then
    raise exception 'Public identity resolver v2 must delegate to the internal membrane.';
  end if;
end;
$validation$;

rollback;
