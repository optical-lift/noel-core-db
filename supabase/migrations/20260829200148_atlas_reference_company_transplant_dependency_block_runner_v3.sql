do $migration$
declare
  v_def text;
  v_old text := $old$    update atlas.capacity_measurements
    set stable_key='snapdragon_in_row_spacing_inches',updated_at=now()
    where id=v_measurement_id;
$old$;
  v_new text := $new$    update atlas.capacity_measurements
    set stable_key='snapdragon_in_row_spacing_inches',value=value,updated_at=now()
    where id=v_measurement_id;
$new$;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas' and p.proname='run_reference_company_transplant_dependency_block_v1';

  if v_def is null or position(v_old in v_def)=0 then
    raise exception 'Expected transplant dependency runner v2 measurement-restore block was not found.' using errcode='23514';
  end if;

  execute replace(v_def,v_old,v_new);
end;
$migration$;

update atlas.reference_company_scenarios
set metadata=metadata||jsonb_build_object(
  'runner_version',3,
  'runner_repair','restore_capacity_measurement_through_value_update_trigger'
),updated_at=now()
where stable_key='transplant_dependency_block_v1';