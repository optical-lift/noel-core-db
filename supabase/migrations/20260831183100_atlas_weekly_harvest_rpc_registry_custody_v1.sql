-- Register the authenticated Weekly Harvest v3/v2 membrane endpoints in the
-- canonical Atlas RPC custody registry. The functions already exist in the
-- preceding harvest migrations; this migration closes the registry drift only.

begin;

insert into atlas.authenticated_rpc_registry (
  signature,
  classification,
  confidence,
  review_status,
  risk_acknowledged,
  authenticated_execute_expected,
  security_definer_expected,
  service_execute_expected,
  anonymous_execute_expected,
  evidence,
  reviewed_at
)
values
  (
    'atlas.owner_operator_record_weekly_harvest_row_v3(uuid,uuid,date,integer,text,atlas.flower_petals_damage_v1,atlas.flower_stem_length_bucket_v1,atlas.flower_opening_state_v1,text,text)',
    'owner_admin_endpoint'::atlas.authenticated_rpc_class,
    'high'::atlas.authenticated_rpc_confidence,
    'reviewed'::atlas.authenticated_rpc_review_status,
    false,
    true,
    true,
    true,
    false,
    'Weekly Harvest v3 owner/operator writer; authenticated owner-admin membrane introduced by 20260831162500 and verified against live privileges.',
    now()
  ),
  (
    'atlas.owner_operator_weekly_harvest_task_state_v2(uuid,date,date)',
    'owner_admin_endpoint'::atlas.authenticated_rpc_class,
    'high'::atlas.authenticated_rpc_confidence,
    'reviewed'::atlas.authenticated_rpc_review_status,
    false,
    true,
    true,
    true,
    false,
    'Weekly Harvest v2 owner/operator read membrane introduced by 20260831183000 and verified against live privileges.',
    now()
  ),
  (
    'atlas.record_weekly_harvest_row_for_member_v3(uuid,date,integer,text,atlas.flower_petals_damage_v1,atlas.flower_stem_length_bucket_v1,atlas.flower_opening_state_v1,text,text)',
    'app_endpoint'::atlas.authenticated_rpc_class,
    'high'::atlas.authenticated_rpc_confidence,
    'reviewed'::atlas.authenticated_rpc_review_status,
    false,
    true,
    true,
    true,
    false,
    'Weekly Harvest v3 signed-in member writer; authenticated app membrane introduced by 20260831160500 and verified against live privileges.',
    now()
  ),
  (
    'atlas.weekly_harvest_task_state_for_member_v2(date,date)',
    'app_endpoint'::atlas.authenticated_rpc_class,
    'high'::atlas.authenticated_rpc_confidence,
    'reviewed'::atlas.authenticated_rpc_review_status,
    false,
    true,
    true,
    true,
    false,
    'Weekly Harvest v2 signed-in member read membrane introduced by 20260831183000 and verified against live privileges.',
    now()
  )
on conflict (signature) do update
set
  classification = excluded.classification,
  confidence = excluded.confidence,
  review_status = excluded.review_status,
  risk_acknowledged = excluded.risk_acknowledged,
  authenticated_execute_expected = excluded.authenticated_execute_expected,
  security_definer_expected = excluded.security_definer_expected,
  service_execute_expected = excluded.service_execute_expected,
  anonymous_execute_expected = excluded.anonymous_execute_expected,
  evidence = excluded.evidence,
  reviewed_at = excluded.reviewed_at;

select atlas.assert_authenticated_rpc_registry_complete_v1();

commit;
