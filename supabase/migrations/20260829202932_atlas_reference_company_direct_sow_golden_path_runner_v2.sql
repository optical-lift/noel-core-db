do $migration$
declare
  v_definition text;
  v_old text := $old$    select t.id into v_germ_task_id
    from atlas.tasks t join atlas.task_crop_cycles tc on tc.task_id=t.id
    where tc.crop_cycle_id=v_cycle_id and t.task_type='germination_check' and t.status in ('open','blocked')
    order by t.created_at desc limit 1;
    if v_germ_task_id is null then raise exception 'Direct-sow germination observation carrier was not derived.' using errcode='23514'; end if;$old$;
  v_new text := $new$    select t.id into v_germ_task_id
    from atlas.tasks t
    left join atlas.task_crop_cycles tc on tc.task_id=t.id
    where t.farm_id=v_farm.id
      and t.task_type='germination_check'
      and t.status in ('open','blocked','archived')
      and (
        tc.crop_cycle_id=v_cycle_id
        or t.generated_from_id=v_cycle_id
        or t.metadata->>'crop_cycle_id'=v_cycle_id::text
        or t.metadata->>'source_sowing_task_id'=v_sow_task_id::text
      )
    order by
      case t.status when 'open' then 0 when 'blocked' then 1 when 'archived' then 2 else 3 end,
      t.created_at desc
    limit 1;
    if v_germ_task_id is null then raise exception 'Direct-sow germination observation carrier was not derived in any reservoir state.' using errcode='23514'; end if;$new$;
begin
  select pg_get_functiondef(p.oid)
  into v_definition
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas'
    and p.proname='run_reference_company_direct_sow_golden_path_v1'
    and pg_get_function_identity_arguments(p.oid)='p_source_revision text';

  if v_definition is null then
    raise exception 'Direct-sow Reference Company runner v1 was not found.' using errcode='P0002';
  end if;
  if position(v_old in v_definition)=0 then
    raise exception 'Direct-sow Reference Company runner v1 lookup contract no longer matches expected source.' using errcode='23514';
  end if;

  execute replace(v_definition,v_old,v_new);
end;
$migration$;

update atlas.reference_company_scenarios
set metadata=metadata||jsonb_build_object(
  'implementation_state','executable',
  'runner','run_reference_company_direct_sow_golden_path_v1',
  'runner_version',2,
  'carrier_identity_contract','canonical germination carriers remain valid conformance evidence while deferred in the central release reservoir'
),updated_at=now()
where stable_key='direct_sow_golden_path_v1';