with desired(signature, reason, truth_boundary) as (
  values
    (
      'atlas.record_external_flower_intake_for_member_v1(uuid, uuid, text, text, jsonb, text)'::text,
      'register_weekly_harvest_external_intake_worker_endpoint'::text,
      'The assigned signed-in farm member records external flower custody on an open Weekly Harvest card. This endpoint records provenance and received quantities only; it does not create crop-cycle truth, Ready inventory, or release Flower Preparation.'::text
    ),
    (
      'atlas.owner_operator_record_external_flower_intake_v1(uuid, uuid, text, text, jsonb, text)'::text,
      'register_weekly_harvest_external_intake_owner_operator_endpoint'::text,
      'The Owner operator may record the same external flower custody while preserving effective worker membership and operator provenance. It does not create crop-cycle truth, Ready inventory, or release Flower Preparation.'::text
    )
), target as (
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
    ) as policy_reference_count,
    d.reason,
    d.truth_boundary
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  join desired d on d.signature = format('%I.%I(%s)', n.nspname, p.proname, oidvectortypes(p.proargtypes))
  where n.nspname = 'atlas'
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
    'source', 'atlas_external_flower_intake_rpc_custody_v1',
    'reason', reason,
    'functionOid', oid,
    'classificationRuleVersion', 3,
    'truthBoundary', truth_boundary
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
  v_registered integer;
  v_drift integer;
begin
  select count(*) into v_registered
  from atlas.authenticated_rpc_registry
  where signature in (
    'atlas.record_external_flower_intake_for_member_v1(uuid, uuid, text, text, jsonb, text)',
    'atlas.owner_operator_record_external_flower_intake_v1(uuid, uuid, text, text, jsonb, text)'
  )
    and classification = 'app_endpoint'
    and confidence = 'verified'
    and review_status = 'active'
    and authenticated_execute_expected = true
    and anonymous_execute_expected = false
    and security_definer_expected = true
    and service_execute_expected = true;

  if v_registered <> 2 then
    raise exception 'External flower intake RPC custody registered % of 2 required app endpoints.', v_registered;
  end if;

  select count(*) into v_drift
  from atlas.authenticated_rpc_registry_drift_v1();

  if v_drift <> 0 then
    raise exception 'External flower intake RPC custody ended with % drift rows.', v_drift;
  end if;
end
$verification$;