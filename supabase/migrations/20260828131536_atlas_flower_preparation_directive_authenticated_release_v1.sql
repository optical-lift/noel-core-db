grant execute on function atlas.record_flower_preparation_directive_v1(uuid, jsonb, text, text) to authenticated;
revoke execute on function atlas.record_flower_preparation_directive_v1(uuid, jsonb, text, text) from anon, service_role;

with target as (
  select
    p.oid,
    format('%I.%I(%s)', n.nspname, p.proname, oidvectortypes(p.proargtypes)) as signature,
    p.prosecdef as security_definer,
    has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute,
    has_function_privilege('anon', p.oid, 'EXECUTE') as anonymous_execute,
    has_function_privilege('service_role', p.oid, 'EXECUTE') as service_execute,
    (
      select count(*)::integer
      from pg_proc caller
      join pg_namespace caller_namespace on caller_namespace.oid = caller.pronamespace and caller_namespace.nspname = 'atlas'
      where caller.oid <> p.oid
        and caller.prokind = 'f'
        and (
          position(lower(p.proname) || '(' in lower(pg_get_functiondef(caller.oid))) > 0
          or position(lower(p.proname) || ' (' in lower(pg_get_functiondef(caller.oid))) > 0
        )
    ) as caller_count,
    (
      select count(*)::integer
      from pg_policies policy
      where position(lower(p.proname) || '(' in lower(coalesce(policy.qual, '') || ' ' || coalesce(policy.with_check, ''))) > 0
         or position(lower(p.proname) || ' (' in lower(coalesce(policy.qual, '') || ' ' || coalesce(policy.with_check, ''))) > 0
    ) as policy_reference_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atlas'
    and p.proname = 'record_flower_preparation_directive_v1'
    and oidvectortypes(p.proargtypes) = 'uuid, jsonb, text, text'
)
insert into atlas.authenticated_rpc_registry(
  signature,
  classification,
  confidence,
  review_status,
  authenticated_execute_expected,
  anonymous_execute_expected,
  security_definer_expected,
  service_execute_expected,
  caller_count,
  policy_reference_count,
  evidence,
  registered_at,
  reviewed_at
)
select
  signature,
  'app_endpoint',
  'verified',
  'active',
  authenticated_execute,
  anonymous_execute,
  security_definer,
  service_execute,
  caller_count,
  policy_reference_count,
  jsonb_build_object(
    'source', 'atlas_flower_preparation_directive_authenticated_release_v1',
    'reason', 'activate_governed_direct_harvest_owner_submit',
    'functionOid', oid,
    'classificationRuleVersion', 3,
    'truthBoundary', 'Authenticated Owner/manager may issue one immutable flower preparation directive from the governed Direct Harvest task. The function itself validates Owner authority, harvest batch linkage, hidden worker occurrence state, requested line semantics, canonical completion, and continuation release. Anonymous and service-role execution remain disabled.'
  ),
  now(),
  now()
from target
on conflict (signature) do update
set classification = excluded.classification,
    confidence = excluded.confidence,
    review_status = excluded.review_status,
    authenticated_execute_expected = excluded.authenticated_execute_expected,
    anonymous_execute_expected = excluded.anonymous_execute_expected,
    security_definer_expected = excluded.security_definer_expected,
    service_execute_expected = excluded.service_execute_expected,
    caller_count = excluded.caller_count,
    policy_reference_count = excluded.policy_reference_count,
    evidence = coalesce(atlas.authenticated_rpc_registry.evidence, '{}'::jsonb) || excluded.evidence,
    reviewed_at = now();

do $verification$
declare
  v_oid oid;
  v_drift integer;
begin
  select p.oid into v_oid
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atlas'
    and p.proname = 'record_flower_preparation_directive_v1'
    and oidvectortypes(p.proargtypes) = 'uuid, jsonb, text, text';

  if v_oid is null then
    raise exception 'Flower preparation directive RPC was not found.';
  end if;

  if not has_function_privilege('authenticated', v_oid, 'EXECUTE') then
    raise exception 'Authenticated Direct Harvest submit was not enabled.';
  end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE') then
    raise exception 'Anonymous Direct Harvest submit must remain disabled.';
  end if;
  if has_function_privilege('service_role', v_oid, 'EXECUTE') then
    raise exception 'Service-role Direct Harvest submit must remain disabled.';
  end if;

  select count(*) into v_drift from atlas.authenticated_rpc_registry_drift_v1();
  if v_drift <> 0 then
    raise exception 'Direct Harvest RPC activation ended with % authenticated RPC drift rows.', v_drift;
  end if;
end
$verification$;