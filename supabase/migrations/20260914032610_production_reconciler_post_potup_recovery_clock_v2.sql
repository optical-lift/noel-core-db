do $migration$
declare
  v_oid oid;
  v_def text;
  v_new text;
  v_old_due text := 'v_due:=greatest(coalesce(v_event.event_date,v_today),coalesce(v_lot.actual_sow_date,v_today)+coalesce(v_next_stage.timing_min_days,0),coalesce(nullif(v_lot.metadata->>''hardening_start_date'','''')::date,coalesce(v_event.event_date,v_today)));';
  v_new_due text := 'v_due:=greatest(coalesce(v_event.event_date,v_today),coalesce(v_lot.actual_sow_date,v_today)+coalesce(v_next_stage.timing_min_days,0),coalesce(nullif(v_batch.metadata->>''pot_up_date'','''')::date+14,nullif(v_lot.metadata->>''last_pot_up_date'','''')::date+14,coalesce(v_event.event_date,v_today)),coalesce(nullif(v_lot.metadata->>''hardening_start_date'','''')::date,coalesce(v_event.event_date,v_today)));';
  v_old_latest text := 'v_latest:=coalesce(case when v_next_stage.timing_max_days is null then null else coalesce(v_lot.actual_sow_date,v_today)+v_next_stage.timing_max_days end,v_lot.expected_transplant_start,v_due+7);';
  v_new_latest text := 'v_latest:=greatest(v_due,coalesce(case when v_next_stage.timing_max_days is null then null else coalesce(v_lot.actual_sow_date,v_today)+v_next_stage.timing_max_days end,v_lot.expected_transplant_start,v_due+7));';
begin
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas' and p.proname='reconcile_production_propagation_work_v1'
    and pg_get_function_identity_arguments(p.oid)='p_production_lot_id uuid, p_as_of_date date';
  if v_oid is null then raise exception 'reconcile_production_propagation_work_v1 not found'; end if;
  v_def:=pg_get_functiondef(v_oid);
  v_new:=replace(v_def,v_old_due,v_new_due);
  v_new:=replace(v_new,v_old_latest,v_new_latest);
  if v_new=v_def then raise exception 'Expected hardening timing clauses not found; refusing silent patch'; end if;
  execute v_new;
end
$migration$;