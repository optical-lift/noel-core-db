-- Register the authenticated Weekly Harvest v3/v2 membrane endpoints in the
-- canonical Atlas RPC custody registry. The functions already exist in the
-- preceding harvest migrations; this migration closes their registry drift only.

begin;

with desired(signature,classification,reason,truth_boundary) as (
  values
    (
      'atlas.owner_operator_record_weekly_harvest_row_v3(uuid, uuid, uuid, text, text, integer, text)'::text,
      'owner_admin_endpoint'::text,
      'register_weekly_harvest_v3_owner_operator_writer'::text,
      'Owner/operator writes one canonical Weekly Harvest crop-row result; usable harvest requires florist_grade or event_grade and non-harvest outcomes create no harvest inventory.'::text
    ),
    (
      'atlas.owner_operator_weekly_harvest_task_state_v2(uuid, uuid)'::text,
      'owner_admin_endpoint'::text,
      'register_weekly_harvest_v3_owner_operator_reader'::text,
      'Owner/operator reads the canonical Weekly Harvest task state including persisted harvest grade and current exception vocabulary.'::text
    ),
    (
      'atlas.record_weekly_harvest_row_for_member_v3(uuid, uuid, uuid, text, text, integer, text)'::text,
      'app_endpoint'::text,
      'register_weekly_harvest_v3_member_writer'::text,
      'Signed-in farm member writes one canonical Weekly Harvest crop-row result through membership and assignment checks.'::text
    ),
    (
      'atlas.weekly_harvest_task_state_for_member_v2(uuid, uuid)'::text,
      'app_endpoint'::text,
      'register_weekly_harvest_v3_member_reader'::text,
      'Signed-in farm member reads canonical Weekly Harvest task state through the membership-scoped read membrane.'::text
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
    ) as policy_reference_count,
    d.classification,
    d.reason,
    d.truth_boundary
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  join desired d on d.signature=format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes))
  where n.nspname='atlas'
)
insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,anonymous_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at,reviewed_at
)
select
  signature,classification,'verified','active',
  authenticated_execute,anonymous_execute,security_definer,service_execute,
  caller_count,policy_reference_count,
  jsonb_build_object(
    'source','atlas_weekly_harvest_rpc_registry_custody_v1',
    'reason',reason,
    'functionOid',oid,
    'truthBoundary',truth_boundary,
    'contractVersion','weekly_harvest_round_v3'
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
  v_target_drift integer;
begin
  select count(*) into v_registered
  from atlas.authenticated_rpc_registry
  where signature in (
    'atlas.owner_operator_record_weekly_harvest_row_v3(uuid, uuid, uuid, text, text, integer, text)',
    'atlas.owner_operator_weekly_harvest_task_state_v2(uuid, uuid)',
    'atlas.record_weekly_harvest_row_for_member_v3(uuid, uuid, uuid, text, text, integer, text)',
    'atlas.weekly_harvest_task_state_for_member_v2(uuid, uuid)'
  )
    and confidence='verified'
    and review_status='active'
    and authenticated_execute_expected=true
    and anonymous_execute_expected=false
    and security_definer_expected=true
    and service_execute_expected=true;

  if v_registered<>4 then
    raise exception 'Weekly Harvest RPC custody registered % of 4 required endpoints.',v_registered;
  end if;

  select count(*) into v_target_drift
  from atlas.authenticated_rpc_registry_drift_v1()
  where signature in (
    'atlas.owner_operator_record_weekly_harvest_row_v3(uuid, uuid, uuid, text, text, integer, text)',
    'atlas.owner_operator_weekly_harvest_task_state_v2(uuid, uuid)',
    'atlas.record_weekly_harvest_row_for_member_v3(uuid, uuid, uuid, text, text, integer, text)',
    'atlas.weekly_harvest_task_state_for_member_v2(uuid, uuid)'
  );

  if v_target_drift<>0 then
    raise exception 'Weekly Harvest RPC custody ended with % target drift rows.',v_target_drift;
  end if;
end
$verification$;

commit;
