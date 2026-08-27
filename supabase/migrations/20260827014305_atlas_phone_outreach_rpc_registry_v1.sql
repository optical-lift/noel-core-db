with target as (
  select
    p.oid,
    format('%I.%I(%s)', n.nspname, p.proname, oidvectortypes(p.proargtypes)) as signature,
    p.prosecdef as security_definer,
    has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute,
    has_function_privilege('anon',p.oid,'EXECUTE') as anonymous_execute,
    has_function_privilege('service_role',p.oid,'EXECUTE') as service_execute,
    (
      select count(*)::integer
      from pg_proc caller
      join pg_namespace caller_namespace
        on caller_namespace.oid=caller.pronamespace
       and caller_namespace.nspname='atlas'
      where caller.oid<>p.oid
        and caller.prokind='f'
        and (
          position(lower(p.proname)||'(' in lower(pg_get_functiondef(caller.oid)))>0
          or position(lower(p.proname)||' (' in lower(pg_get_functiondef(caller.oid)))>0
        )
    ) as caller_count,
    (
      select count(*)::integer
      from pg_policies policy
      where position(lower(p.proname)||'(' in lower(coalesce(policy.qual,'')||' '||coalesce(policy.with_check,'')))>0
         or position(lower(p.proname)||' (' in lower(coalesce(policy.qual,'')||' '||coalesce(policy.with_check,'')))>0
    ) as policy_reference_count
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas'
    and p.proname='record_phone_outreach_result_and_complete_v2'
    and oidvectortypes(p.proargtypes)='uuid, text, text, text, uuid, text'
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
    'source','atlas_phone_outreach_rpc_registry_v1',
    'reason','register_authenticated_phone_outreach_completion_endpoint',
    'functionOid',oid,
    'classificationRuleVersion',2,
    'truthBoundary','The signed-in phone outreach route directly invokes this governed atomic completion RPC; registry expectations mirror the live function catalog privileges and security mode.'
  ),
  now(),
  now()
from target
on conflict (signature) do update
set classification=excluded.classification,
    confidence=excluded.confidence,
    review_status=excluded.review_status,
    authenticated_execute_expected=excluded.authenticated_execute_expected,
    anonymous_execute_expected=excluded.anonymous_execute_expected,
    security_definer_expected=excluded.security_definer_expected,
    service_execute_expected=excluded.service_execute_expected,
    caller_count=excluded.caller_count,
    policy_reference_count=excluded.policy_reference_count,
    evidence=coalesce(atlas.authenticated_rpc_registry.evidence,'{}'::jsonb)||excluded.evidence,
    reviewed_at=now();

do $verification$
declare
  v_signature text := 'atlas.record_phone_outreach_result_and_complete_v2(uuid, text, text, text, uuid, text)';
  v_drift integer;
begin
  if not exists (
    select 1
    from atlas.authenticated_rpc_registry
    where signature=v_signature
      and classification='app_endpoint'
      and confidence='verified'
      and review_status='active'
      and authenticated_execute_expected=true
      and anonymous_execute_expected=false
      and security_definer_expected=true
      and service_execute_expected=false
  ) then
    raise exception 'Phone outreach authenticated RPC registry row was not established with the live privilege contract.';
  end if;

  select count(*) into v_drift
  from atlas.authenticated_rpc_registry_drift_v1()
  where signature=v_signature;

  if v_drift<>0 then
    raise exception 'Phone outreach authenticated RPC registry reconciliation ended with % drift rows.', v_drift;
  end if;
end
$verification$;