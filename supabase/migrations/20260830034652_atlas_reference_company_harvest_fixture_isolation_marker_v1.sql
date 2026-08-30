do $block$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas' and p.proname='run_reference_company_harvest_depletion_ledger_v1' and p.prokind='f'
  limit 1;
  if v_def is null then raise exception 'Harvest depletion fixture runner not found'; end if;
  v_def := replace(
    v_def,
    'values(gen_random_uuid(),f.id,''farm_hand'',''reference_harvest_fixture'',true,jsonb_build_object(''system_fixture'',true,''reference_run_id'',v_run_id))',
    'values(gen_random_uuid(),f.id,''farm_hand'',''reference_harvest_fixture'',true,jsonb_build_object(''system_fixture'',true,''reference_fixture_membership'',true,''reference_run_id'',v_run_id))'
  );
  execute v_def;
end;
$block$;