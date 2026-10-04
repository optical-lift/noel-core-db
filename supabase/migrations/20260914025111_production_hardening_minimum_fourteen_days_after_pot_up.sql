do $$
declare
  v_oid oid;
  v_def text;
  v_old_due text := 'v_due:=greatest(p_care_date,coalesce(v_lot.actual_sow_date,p_care_date)+coalesce(v_next_stage.timing_min_days,0),coalesce(nullif(v_lot.metadata->>''hardening_start_date'','''')::date,p_care_date));';
  v_new_due text := 'v_due:=greatest(p_care_date+14,coalesce(v_lot.actual_sow_date,p_care_date)+coalesce(v_next_stage.timing_min_days,0),coalesce(nullif(v_lot.metadata->>''hardening_start_date'','''')::date,p_care_date+14));';
  v_old_latest text := 'v_latest:=coalesce(case when v_next_stage.timing_max_days is null then null else coalesce(v_lot.actual_sow_date,p_care_date)+v_next_stage.timing_max_days end,v_lot.expected_transplant_start);';
  v_new_latest text := 'v_latest:=greatest(v_due,coalesce(case when v_next_stage.timing_max_days is null then null else coalesce(v_lot.actual_sow_date,p_care_date)+v_next_stage.timing_max_days end,v_lot.expected_transplant_start,v_due));';
begin
  select p.oid into v_oid
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas'
    and p.proname='record_production_pot_up_v1'
    and pg_get_function_identity_arguments(p.oid)='p_task_id uuid, p_outputs jsonb, p_care_date date, p_note text, p_idempotency_key text';

  if v_oid is null then
    raise exception 'atlas.record_production_pot_up_v1 signature not found';
  end if;

  v_def := pg_get_functiondef(v_oid);
  if position(v_old_due in v_def)=0 then
    raise exception 'Expected hardening due-date expression not found';
  end if;
  if position(v_old_latest in v_def)=0 then
    raise exception 'Expected hardening latest-date expression not found';
  end if;

  v_def := replace(v_def,v_old_due,v_new_due);
  v_def := replace(v_def,v_old_latest,v_new_latest);
  execute v_def;
end
$$;