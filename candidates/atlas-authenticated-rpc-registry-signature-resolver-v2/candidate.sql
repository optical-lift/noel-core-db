begin;

create or replace function atlas.resolve_authenticated_rpc_registry_function_oid_v2(
  p_signature text
)
returns oid
language plpgsql
stable
security invoker
set search_path = pg_catalog, atlas
as $$
declare
  v_oid oid;
  v_matches oid[];
begin
  if nullif(btrim(p_signature),'') is null then
    return null;
  end if;

  -- Preserve PostgreSQL's native regprocedure semantics whenever the registry
  -- signature is type-only. This handles aliases such as timestamptz and
  -- PostgreSQL's identifier-length truncation law.
  begin
    v_oid := pg_catalog.to_regprocedure(p_signature)::oid;
  exception
    when others then
      v_oid := null;
  end;

  if v_oid is not null then
    return v_oid;
  end if;

  -- Historical registry rows also contain the exact identity-argument form
  -- PostgreSQL reconstructs for ALTER FUNCTION and related identity commands.
  select array_agg(p.oid order by p.oid)
  into v_matches
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas'
    and p.prokind='f'
    and regexp_replace(
          p_signature,
          '[[:space:]]+',
          '',
          'g'
        ) = regexp_replace(
          format(
            '%I.%I(%s)',
            n.nspname,
            p.proname,
            pg_catalog.pg_get_function_identity_arguments(p.oid)
          ),
          '[[:space:]]+',
          '',
          'g'
        );

  if coalesce(array_length(v_matches,1),0)>1 then
    raise exception 'Authenticated RPC registry signature resolved ambiguously: %',p_signature
      using errcode='42725';
  end if;

  return v_matches[1];
end;
$$;

comment on function atlas.resolve_authenticated_rpc_registry_function_oid_v2(text) is
  'Internal mixed-format RPC registry identity resolver. Uses native regprocedure parsing first, then PostgreSQL identity-argument text for historical named-argument signatures. Returns NULL for a genuinely absent function and never grants endpoint authority.';

revoke all on function atlas.resolve_authenticated_rpc_registry_function_oid_v2(text)
  from public, anon, authenticated, service_role;


create or replace function atlas.authenticated_rpc_registry_drift_v1()
returns table(issue text,signature text,detail jsonb)
language sql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
  WITH actual AS (
    SELECT
      p.oid,
      format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes)) AS signature,
      p.prosecdef AS security_definer,
      has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute,
      has_function_privilege('service_role',p.oid,'EXECUTE') AS service_execute,
      has_function_privilege('anon',p.oid,'EXECUTE') AS anonymous_execute
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='atlas' AND p.prokind='f'
  ), registry AS (
    SELECT
      r.*,
      atlas.resolve_authenticated_rpc_registry_function_oid_v2(r.signature) AS function_oid
    FROM atlas.authenticated_rpc_registry r
  )
  SELECT 'unregistered_authenticated'::text,a.signature,
         jsonb_build_object('authenticated_execute',true)
  FROM actual a
  WHERE a.authenticated_execute
    AND NOT EXISTS(SELECT 1 FROM registry r WHERE r.function_oid=a.oid)

  UNION ALL
  SELECT 'missing_expected_authenticated',r.signature,
         jsonb_build_object('function_exists',a.oid IS NOT NULL,'authenticated_execute',coalesce(a.authenticated_execute,false))
  FROM registry r
  LEFT JOIN actual a ON a.oid=r.function_oid
  WHERE r.authenticated_execute_expected
    AND (a.oid IS NULL OR NOT a.authenticated_execute)

  UNION ALL
  SELECT 'unexpected_authenticated',r.signature,
         jsonb_build_object('authenticated_execute',a.authenticated_execute)
  FROM registry r
  JOIN actual a ON a.oid=r.function_oid
  WHERE NOT r.authenticated_execute_expected AND a.authenticated_execute

  UNION ALL
  SELECT 'security_mode_mismatch',r.signature,
         jsonb_build_object('expected_security_definer',r.security_definer_expected,'actual_security_definer',a.security_definer)
  FROM registry r
  JOIN actual a ON a.oid=r.function_oid
  WHERE r.security_definer_expected IS DISTINCT FROM a.security_definer

  UNION ALL
  SELECT 'service_execute_mismatch',r.signature,
         jsonb_build_object('expected_service_execute',r.service_execute_expected,'actual_service_execute',a.service_execute)
  FROM registry r
  JOIN actual a ON a.oid=r.function_oid
  WHERE r.service_execute_expected IS DISTINCT FROM a.service_execute

  UNION ALL
  SELECT 'anonymous_execute',a.signature,
         jsonb_build_object('anonymous_execute',true,'expected',coalesce(r.anonymous_execute_expected,false))
  FROM actual a
  LEFT JOIN registry r ON r.function_oid=a.oid
  WHERE a.anonymous_execute AND coalesce(r.anonymous_execute_expected,false)=false

  UNION ALL
  SELECT 'missing_expected_anonymous',r.signature,
         jsonb_build_object('function_exists',a.oid IS NOT NULL,'anonymous_execute',coalesce(a.anonymous_execute,false))
  FROM registry r
  LEFT JOIN actual a ON a.oid=r.function_oid
  WHERE r.anonymous_execute_expected
    AND (a.oid IS NULL OR NOT a.anonymous_execute)
$function$;

comment on function atlas.authenticated_rpc_registry_drift_v1() is
  'Service-only Atlas RPC privilege proof. Registry identity resolves safely across type-only and PostgreSQL named identity signatures; genuine missing functions remain visible as drift and PUBLIC execution is never accepted as an implicit boundary.';

revoke all on function atlas.authenticated_rpc_registry_drift_v1()
  from public, anon, authenticated;
grant execute on function atlas.authenticated_rpc_registry_drift_v1()
  to service_role;

commit;
