do $do$
begin
  if to_regprocedure('atlas.run_reference_company_task_custody_cutover_v1(text)') is null then
    raise exception 'Task custody Reference Company runner is missing.';
  end if;
  if to_regprocedure('atlas.run_reference_company_prior_work_reconciliation_v1(text)') is null then
    raise exception 'Prior work reconciliation Reference Company runner is missing.';
  end if;

  update atlas.reference_company_scenarios
  set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
    'runner','run_reference_company_task_custody_cutover_v1',
    'runner_version',3,
    'implementation_state','executable',
    'fixture_contract','rollback_only'
  ), updated_at=now()
  where stable_key='task_custody_cutover_v1'
    and exists (
      select 1 from atlas.reference_company_runs r
      where r.scenario_id=reference_company_scenarios.id and r.status='passed'
    );

  update atlas.reference_company_scenarios
  set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
    'runner','run_reference_company_prior_work_reconciliation_v1',
    'runner_version',1,
    'implementation_state','executable',
    'fixture_contract','rollback_only'
  ), updated_at=now()
  where stable_key='prior_work_reconciliation_v1'
    and exists (
      select 1 from atlas.reference_company_runs r
      where r.scenario_id=reference_company_scenarios.id and r.status='passed'
    );
end
$do$;