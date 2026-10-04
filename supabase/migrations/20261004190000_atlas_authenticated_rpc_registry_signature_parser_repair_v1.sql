begin;

create or replace function atlas.authenticated_rpc_registry_drift_v1()
returns table(issue text, signature text, detail jsonb)
language sql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
  with actual as (
    select
      p.oid,
      format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes)) as signature,
      p.oid::regprocedure::text as regprocedure_signature,
      format('%I.%I(%s)',n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)) as named_signature,
      p.prosecdef as security_definer,
      has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute,
      has_function_privilege('service_role',p.oid,'EXECUTE') as service_execute,
      has_function_privilege('anon',p.oid,'EXECUTE') as anonymous_execute
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas' and p.prokind='f'
  ), registry_normalized as (
    select
      r.*,
      format(
        '%s.%s(%s)',
        split_part(split_part(btrim(r.signature),'(',1),'.',1),
        left(split_part(split_part(btrim(r.signature),'(',1),'.',2),63),
        regexp_replace(
          replace(
            regexp_replace(btrim(r.signature),'^[^(]*\((.*)\)$','\1'),
            'timestamptz',
            'timestamp with time zone'
          ),
          '\s*,\s*',
          ',',
          'g'
        )
      ) as normalized_signature
    from atlas.authenticated_rpc_registry r
  ), registry as (
    select r.*,a.oid as function_oid
    from registry_normalized r
    left join actual a
      on r.normalized_signature in (
        regexp_replace(btrim(a.regprocedure_signature),'\s*,\s*',',','g'),
        regexp_replace(btrim(a.named_signature),'\s*,\s*',',','g')
      )
  )
  select 'unregistered_authenticated'::text,a.signature,
         jsonb_build_object('authenticated_execute',true)
  from actual a
  where a.authenticated_execute
    and not exists(select 1 from registry r where r.function_oid=a.oid)

  union all
  select 'missing_expected_authenticated',r.signature,
         jsonb_build_object('function_exists',a.oid is not null,'authenticated_execute',coalesce(a.authenticated_execute,false))
  from registry r
  left join actual a on a.oid=r.function_oid
  where r.authenticated_execute_expected
    and (a.oid is null or not a.authenticated_execute)

  union all
  select 'unexpected_authenticated',r.signature,
         jsonb_build_object('authenticated_execute',a.authenticated_execute)
  from registry r
  join actual a on a.oid=r.function_oid
  where not r.authenticated_execute_expected and a.authenticated_execute

  union all
  select 'security_mode_mismatch',r.signature,
         jsonb_build_object('expected_security_definer',r.security_definer_expected,'actual_security_definer',a.security_definer)
  from registry r
  join actual a on a.oid=r.function_oid
  where r.security_definer_expected is distinct from a.security_definer

  union all
  select 'service_execute_mismatch',r.signature,
         jsonb_build_object('expected_service_execute',r.service_execute_expected,'actual_service_execute',a.service_execute)
  from registry r
  join actual a on a.oid=r.function_oid
  where r.service_execute_expected is distinct from a.service_execute

  union all
  select 'anonymous_execute',a.signature,
         jsonb_build_object('anonymous_execute',true,'expected',coalesce(r.anonymous_execute_expected,false))
  from actual a
  left join registry r on r.function_oid=a.oid
  where a.anonymous_execute and coalesce(r.anonymous_execute_expected,false)=false

  union all
  select 'missing_expected_anonymous',r.signature,
         jsonb_build_object('function_exists',a.oid is not null,'anonymous_execute',coalesce(a.anonymous_execute,false))
  from registry r
  left join actual a on a.oid=r.function_oid
  where r.anonymous_execute_expected
    and (a.oid is null or not a.anonymous_execute)
$function$;

comment on function atlas.authenticated_rpc_registry_drift_v1() is
  'Compares the authenticated RPC registry to live atlas functions without feeding named identity arguments into to_regprocedure. Registry signatures are normalized for timestamptz aliases, comma whitespace, and PostgreSQL identifier truncation before OID matching.';

do $validation$
declare
  v_count integer;
begin
  select count(*) into v_count
  from atlas.authenticated_rpc_registry_drift_v1();

  if v_count is null then
    raise exception 'Authenticated RPC registry drift parser repair did not produce a drift count.';
  end if;

  perform atlas.source_custody_release_packet_v1();
end
$validation$;

commit;
