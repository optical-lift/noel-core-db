BEGIN;

-- Worker Day live execution-lease cutover introduced two signed-in application
-- endpoints after the authenticated RPC custody registry had already been
-- reconciled. Register exactly those live endpoints from pg_proc so the custody
-- expectation follows the functions' actual privilege/security contract rather
-- than weakening the drift gate.

with desired(signature,reason,truth_boundary) as (
  values
    (
      'atlas.worker_day_execution_lease_action_v2(uuid, uuid, date, uuid, text, text, text)'::text,
      'register_worker_day_execution_lease_action_v2'::text,
      'A signed-in worker may start/resume their own live lease and management may explicitly amend a live lease. The v2 boundary requires an idempotency key; the superseded six-argument v1 endpoint is service-only compatibility.'::text
    ),
    (
      'atlas.grant_worker_day_replacement_execution_lease_v1(uuid, uuid, date, uuid, text)'::text,
      'register_worker_day_replacement_execution_lease_v1'::text,
      'Signed-in farm management may explicitly replace a withdrawn or interrupted Worker Day lease only after assignment, readiness, operation-identity, planner-candidate, and remaining-capacity checks.'::text
    )
), target as (
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
    ) as policy_reference_count,
    d.reason,
    d.truth_boundary
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  join desired d
    on d.signature=format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes))
  where n.nspname='atlas'
)
insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,anonymous_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at,reviewed_at
)
select
  signature,'app_endpoint','verified','active',
  authenticated_execute,anonymous_execute,security_definer,service_execute,
  caller_count,policy_reference_count,
  jsonb_build_object(
    'source','atlas_worker_day_execution_lease_rpc_registry_custody_v1',
    'reason',reason,
    'functionOid',oid,
    'classificationRuleVersion',3,
    'truthBoundary',truth_boundary
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
  v_v1_authenticated boolean;
  v_drift integer;
begin
  select count(*) into v_registered
  from atlas.authenticated_rpc_registry
  where signature in (
    'atlas.worker_day_execution_lease_action_v2(uuid, uuid, date, uuid, text, text, text)',
    'atlas.grant_worker_day_replacement_execution_lease_v1(uuid, uuid, date, uuid, text)'
  )
    and classification='app_endpoint'
    and confidence='verified'
    and review_status='active'
    and authenticated_execute_expected=true
    and anonymous_execute_expected=false
    and security_definer_expected=true
    and service_execute_expected=true;

  if v_registered<>2 then
    raise exception 'Worker Day execution-lease RPC custody registered % of 2 required authenticated endpoints.',v_registered;
  end if;

  select has_function_privilege('authenticated',p.oid,'EXECUTE') into v_v1_authenticated
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas'
    and p.proname='worker_day_execution_lease_action_v1'
    and oidvectortypes(p.proargtypes)='uuid, uuid, date, uuid, text, text';

  if coalesce(v_v1_authenticated,true) then
    raise exception 'Superseded Worker Day execution-lease action v1 still grants authenticated EXECUTE.';
  end if;

  select count(*) into v_drift
  from atlas.authenticated_rpc_registry_drift_v1();

  if v_drift<>0 then
    raise exception 'Worker Day execution-lease RPC custody reconciliation ended with % drift rows.',v_drift;
  end if;
end
$verification$;

COMMIT;
