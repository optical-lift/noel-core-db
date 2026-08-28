-- Register the owner/manager weeding-need ranking endpoint in the authenticated RPC custody registry.
-- The endpoint intentionally has authenticated EXECUTE, no anonymous access, and no service-role EXECUTE.

with target as (
  select
    p.oid,
    format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes)) as signature,
    p.prosecdef as security_definer,
    has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute,
    has_function_privilege('anon',p.oid,'EXECUTE') as anonymous_execute,
    has_function_privilege('service_role',p.oid,'EXECUTE') as service_execute,
    (
      select count(*)::integer
      from pg_proc caller
      join pg_namespace caller_namespace on caller_namespace.oid=caller.pronamespace and caller_namespace.nspname='atlas'
      where caller.oid<>p.oid and caller.prokind='f'
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
    and format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes))
      = 'atlas.set_weeding_need_rank_v1(uuid, uuid, integer, text, text, boolean)'
)
insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,anonymous_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at,reviewed_at
)
select
  signature,'owner_admin_endpoint','verified','active',
  authenticated_execute,anonymous_execute,security_definer,service_execute,
  caller_count,policy_reference_count,
  jsonb_build_object(
    'source','atlas_weeding_need_rank_rpc_custody_v1',
    'reason','register_owner_manager_weeding_need_rank_endpoint',
    'functionOid',oid,
    'classificationRuleVersion',3,
    'authorization','owner or manager farm membership',
    'truthBoundary','This endpoint changes canonical weeding need priority only after explicit owner/manager authorization; it is not a worker execution endpoint and it intentionally has no anonymous or service-role EXECUTE.'
  ),
  now(),now()
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
  v_registered integer;
  v_drift integer;
begin
  select count(*) into v_registered
  from atlas.authenticated_rpc_registry
  where signature='atlas.set_weeding_need_rank_v1(uuid, uuid, integer, text, text, boolean)'
    and classification='owner_admin_endpoint'
    and confidence='verified'
    and review_status='active'
    and authenticated_execute_expected=true
    and anonymous_execute_expected=false
    and security_definer_expected=true
    and service_execute_expected=false;

  if v_registered<>1 then
    raise exception 'Weeding need rank RPC custody registration did not match the live privilege contract.';
  end if;

  select count(*) into v_drift from atlas.authenticated_rpc_registry_drift_v1();
  if v_drift<>0 then
    raise exception 'Authenticated RPC custody reconciliation ended with % drift rows.',v_drift;
  end if;
end
$verification$;
