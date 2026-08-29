do $do$
declare
  v_def text;
  v_marker text := E'    v_task_2:=nullif(v_materialize_2->>''taskId'','''')::uuid;\n\n';
  v_insert text := E'    select coalesce(jsonb_agg(jsonb_build_object(\n      ''id'',id,''key'',occurrence_key,''state'',state,''due'',planned_due_date,''notBefore'',not_before_date,''hardFinish'',hard_finish_date\n    ) order by occurrence_key),''[]''::jsonb)\n    into v_first_set\n    from atlas.planned_work_occurrences\n    where farm_id=v_farm.id and coalesce(metadata->>''production_lot_id'','''')=v_lot_id::text and state<>''cancelled'';\n\n';
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.relnamespace
  where n.nspname='atlas' and p.proname='run_reference_company_reconciler_idempotency_v1';
  if v_def is null then raise exception 'Reference idempotency runner is missing'; end if;
  if position(E'v_task_2:=nullif(v_materialize_2->>''taskId'','''')::uuid;\n    select coalesce(jsonb_agg' in v_def)>0 then
    return;
  end if;
  if position(v_marker in v_def)=0 then raise exception 'Expected post-materialization marker not found'; end if;
  execute replace(v_def,v_marker,v_marker||v_insert);
end
$do$;

update atlas.reference_company_scenarios
set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('runner_version',3),updated_at=now()
where stable_key='reconciler_idempotency_v1';