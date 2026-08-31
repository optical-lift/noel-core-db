BEGIN;

-- Reconcile authenticated RPC registry custody for the Worker Day execution-lease
-- cutover. These routines were already deployed with explicit authenticated and
-- service_role EXECUTE, no anonymous/PUBLIC execution, SECURITY DEFINER, and a
-- pinned search_path. This migration records those intended authority surfaces;
-- it does not broaden function privileges or change Worker Day behavior.

insert into atlas.authenticated_rpc_registry (
  signature,
  classification,
  confidence,
  review_status,
  authenticated_execute_expected,
  security_definer_expected,
  service_execute_expected,
  caller_count,
  policy_reference_count,
  evidence,
  reviewed_at,
  anonymous_execute_expected
)
values
  (
    'atlas.worker_day_execution_lease_action_v2(uuid, uuid, date, uuid, text, text, text)',
    'app_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    1,
    0,
    jsonb_build_object(
      'source', 'atlas_worker_day_lease_rpc_registry_custody_v1',
      'purpose', 'Record explicit start/resume actions by the target worker and management-authorized interruption/withdrawal actions on a live Worker Day execution lease.',
      'authorization', 'Authenticated target worker may start/resume own lease; active farm Owner/Manager may perform the explicitly supported management actions.',
      'historyTruth', 'Lease lifecycle amendments remain append-only execution-lease events with explicit reason and idempotency key.',
      'publicInheritanceRemoved', true
    ),
    now(),
    false
  ),
  (
    'atlas.grant_worker_day_replacement_execution_lease_v1(uuid, uuid, date, uuid, text)',
    'owner_admin_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    1,
    0,
    jsonb_build_object(
      'source', 'atlas_worker_day_lease_rpc_registry_custody_v1',
      'purpose', 'Grant one explicit management-approved replacement execution lease into an already-open Worker Day lease set.',
      'authorization', 'Authenticated farm Owner/Manager only; target membership, assignment, planner candidacy, readiness, exact identity, and remaining capacity are revalidated before grant.',
      'historyTruth', 'Replacement admission creates a durable execution lease; it does not rewrite prior lease history.',
      'publicInheritanceRemoved', true
    ),
    now(),
    false
  )
on conflict (signature) do update
set classification = excluded.classification,
    confidence = excluded.confidence,
    review_status = excluded.review_status,
    authenticated_execute_expected = excluded.authenticated_execute_expected,
    security_definer_expected = excluded.security_definer_expected,
    service_execute_expected = excluded.service_execute_expected,
    caller_count = excluded.caller_count,
    policy_reference_count = excluded.policy_reference_count,
    evidence = excluded.evidence,
    reviewed_at = excluded.reviewed_at,
    anonymous_execute_expected = excluded.anonymous_execute_expected;

do $$
begin
  if exists (
    select 1
    from atlas.authenticated_rpc_registry_drift_v1() d
    where d.signature in (
      'atlas.worker_day_execution_lease_action_v2(uuid, uuid, date, uuid, text, text, text)',
      'atlas.grant_worker_day_replacement_execution_lease_v1(uuid, uuid, date, uuid, text)'
    )
  ) then
    raise exception 'Worker Day execution-lease RPC registry custody remains unresolved.';
  end if;
end
$$;

COMMIT;
