-- Disposable production-schema clone ONLY: schemas do not contain policy rows.
-- This is the already-admitted ordinary organization manager-acceptance policy.
-- Never migrate this fixture into production and never include worker/private rows.
INSERT INTO atlas.work_result_contract_policies (
  contract_key,source_domain,acceptance_mode,active
) VALUES (
  'ordinary_company_work_manager_acceptance_v1',
  'organization','manager_acceptance',true
);
