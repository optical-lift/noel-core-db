do $migration$
declare
  v_oid oid;
  v_def text;
  v_new text;
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas' and p.proname='record_production_pot_up_v1'
    and pg_get_function_identity_arguments(p.oid)='p_task_id uuid, p_outputs jsonb, p_care_date date, p_note text, p_idempotency_key text';
  if v_oid is null then raise exception 'record_production_pot_up_v1 not found'; end if;
  v_def := pg_get_functiondef(v_oid);
  v_new := replace(v_def,
    'if v_living is null or v_living<=0 then raise exception ''Pot-up livingPlants must be greater than zero for crop cycle %.''',
    'if v_living is not null and v_living<=0 then raise exception ''Pot-up livingPlants, when known, must be greater than zero for crop cycle %.''');
  v_new := replace(v_new,
    'if v_trays is null or v_trays<=0 or trunc(v_trays)<>v_trays then raise exception ''Pot-up trayCount must be a positive whole number for crop cycle %.''',
    'if v_trays is not null and (v_trays<=0 or trunc(v_trays)<>v_trays) then raise exception ''Pot-up trayCount, when known, must be a positive whole number for crop cycle %.''');
  if v_new = v_def then raise exception 'Expected pot-up validation clauses were not found; refusing silent patch'; end if;
  execute v_new;
end
$migration$;

comment on function atlas.record_production_pot_up_v1(uuid,jsonb,date,text,text) is
'Pot-up biological state transition. Exact living-plant and tray counts are optional observations and must never block successor biological timing; known values are still validated.';