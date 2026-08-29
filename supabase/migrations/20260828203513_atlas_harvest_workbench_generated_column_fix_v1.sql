do $do$
declare
  v_definition text;
  v_old_columns text := '      created_by_user_id,metadata,more_availability,bucket_halves';
  v_new_columns text := '      created_by_user_id,metadata,bucket_halves';
  v_old_values text := '      ),v_more,v_halves';
  v_new_values text := '      ),v_halves';
begin
  select pg_get_functiondef('atlas.record_flower_harvest_workbench_core_v1(uuid,uuid,text,jsonb,text,text,boolean)'::regprocedure)
  into v_definition;

  if position(v_old_columns in v_definition)=0 then
    raise exception 'Expected Harvest workbench observation column list was not found.';
  end if;
  if position(v_old_values in v_definition)=0 then
    raise exception 'Expected Harvest workbench observation values list was not found.';
  end if;

  v_definition := replace(v_definition,v_old_columns,v_new_columns);
  v_definition := replace(v_definition,v_old_values,v_new_values);
  execute v_definition;
end;
$do$;