do $do$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas' and p.proname='run_reference_company_completed_history_immutability_v1';
  if v_def is null then raise exception 'Completed-history runner is missing'; end if;
  if position('where a.run_id=(select r.id from atlas.reference_company_runs r where r.run_token=token)' in v_def)>0 then return; end if;
  if position('from atlas.reference_company_assertions a where a.run_id=run_reference_company_completed_history_immutability_v1.run_id' in v_def)=0 then raise exception 'Expected v2 assertion aggregation marker not found'; end if;
  execute replace(v_def,'from atlas.reference_company_assertions a where a.run_id=run_reference_company_completed_history_immutability_v1.run_id','from atlas.reference_company_assertions a where a.run_id=(select r.id from atlas.reference_company_runs r where r.run_token=token)');
end
$do$;

update atlas.reference_company_scenarios
set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('runner_version',3),updated_at=now()
where stable_key='completed_history_immutability_v1';