-- Disposable-clone validation fixture only.
-- The production schema snapshot intentionally excludes policy rows.
-- This matches the owner-reviewed ordinary manager-acceptance policy that is
-- already active in production; never releases or changes production data.
INSERT INTO atlas.work_result_contract_policies (
  contract_key, source_domain, acceptance_mode, active
) VALUES (
  'ordinary_company_work_manager_acceptance_v1',
  'organization',
  'manager_acceptance',
  true
);
