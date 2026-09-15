-- Validation-only prerequisite row for the schema-only production clone.
-- Production already contains this canonical policy from migration
-- 20260910033803_atlas_delegated_worker_attestation_v1. The clone harness
-- restores schema without operational table data, so reproduce that exact
-- governed prerequisite for candidate validation only.

insert into atlas.work_result_contract_policies(
  contract_key, source_domain, acceptance_mode, active, description, metadata
) values (
  'ordinary_company_work_worker_attestation_v1',
  'organization',
  'worker_attestation',
  true,
  'Ordinary delegated Company Work where the current responsible employee attests completion and Atlas advances institutional work automatically.',
  jsonb_build_object(
    'workerDoneIsReport',true,
    'delegatedResponsibilityCarriesCompletionAuthority',true,
    'workerAttestationAcceptedByContract',true,
    'secondManagerClickRequired',false,
    'laterCorrectionReopensWithoutErasingHistory',true
  )
)
on conflict(contract_key) do update set
  source_domain=excluded.source_domain,
  acceptance_mode=excluded.acceptance_mode,
  active=excluded.active,
  description=excluded.description,
  metadata=excluded.metadata,
  updated_at=now();
