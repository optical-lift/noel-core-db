revoke execute on function atlas.record_phone_outreach_result_v1(uuid,text,text,text,uuid) from authenticated;

with desired(signature,reason,truth_boundary) as (
  values
    ('atlas.bed_components_state_v1(uuid)'::text,'register_authenticated_bed_component_state_endpoint'::text,'The signed-in Atlas bed map/card surface reads governed bed-component state through this membership-scoped endpoint.'::text),
    ('atlas.crop_cycle_postproduction_state_v1(uuid, date)'::text,'register_authenticated_crop_postproduction_state_endpoint'::text,'The signed-in crop lifecycle surface may read governed postproduction state; the function enforces farm membership and exposes no anonymous execution.'::text),
    ('atlas.record_observed_crop_presence_for_member_v1(uuid, text, text, date, text, text)'::text,'register_authenticated_inline_crop_presence_endpoint'::text,'The signed-in inline crop-presence authoring surface records an explicit member observation through this governed write boundary.'::text),
    ('atlas.weed_selected_crop_turnover_focus_v1(uuid)'::text,'register_authenticated_selected_crop_turnover_focus_endpoint'::text,'The signed-in selected-crop turnover Weed card reads its governed crop-body focus through this task-scoped endpoint.'::text)
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
  signature,'app_endpoint','verified','active',
  authenticated_execute,anonymous_execute,security_definer,service_execute,
  caller_count,policy_reference_count,
  jsonb_build_object(
    'source','atlas_authenticated_rpc_custody_reconciliation_v3',
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
  v_old_phone_auth boolean;
  v_drift integer;
begin
  select count(*) into v_registered
  from atlas.authenticated_rpc_registry
  where signature in (
    'atlas.bed_components_state_v1(uuid)',
    'atlas.crop_cycle_postproduction_state_v1(uuid, date)',
    'atlas.record_observed_crop_presence_for_member_v1(uuid, text, text, date, text, text)',
    'atlas.weed_selected_crop_turnover_focus_v1(uuid)'
  )
    and classification='app_endpoint'
    and confidence='verified'
    and review_status='active'
    and authenticated_execute_expected=true
    and anonymous_execute_expected=false
    and security_definer_expected=true
    and service_execute_expected=true;

  if v_registered<>4 then
    raise exception 'Authenticated RPC custody reconciliation registered % of 4 required app endpoints.',v_registered;
  end if;

  select has_function_privilege('authenticated',p.oid,'EXECUTE') into v_old_phone_auth
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas' and p.proname='record_phone_outreach_result_v1'
    and oidvectortypes(p.proargtypes)='uuid, text, text, text, uuid';

  if coalesce(v_old_phone_auth,true) then
    raise exception 'Superseded phone outreach v1 still grants authenticated EXECUTE.';
  end if;

  select count(*) into v_drift from atlas.authenticated_rpc_registry_drift_v1();
  if v_drift<>0 then
    raise exception 'Authenticated RPC custody reconciliation ended with % drift rows.',v_drift;
  end if;
end
$verification$;