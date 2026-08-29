do $do$
declare
  v_def text;
  v_marker text := E'    insert into atlas.production_readiness_observations(\n';
  v_insert text := E'    insert into atlas.production_lot_tasks(production_lot_id,task_id,link_role,source,metadata)\n    values(v_lot_id,v_evidence_task_id,''transplant_readiness'',''reference_company_runner'',jsonb_build_object(''reference_run_id'',v_run_id,''system_fixture'',true));\n\n';
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas' and p.proname='run_reference_company_reconciler_idempotency_v1';
  if v_def is null then raise exception 'Reference idempotency runner v1 is missing'; end if;
  if position(E'values(v_lot_id,v_evidence_task_id,''transplant_readiness'',''reference_company_runner''' in v_def)>0 then
    return;
  end if;
  if position(v_marker in v_def)=0 then raise exception 'Expected readiness observation marker not found'; end if;
  execute replace(v_def,v_marker,v_insert||v_marker);
end
$do$;

update atlas.reference_company_scenarios
set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('runner_version',2),updated_at=now()
where stable_key='reconciler_idempotency_v1';