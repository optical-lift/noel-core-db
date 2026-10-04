create or replace function atlas.validate_production_tray_batch_v1()
returns trigger
language plpgsql
set search_path to 'atlas','public'
as $function$
declare
  v_lot_farm uuid;
  v_task_farm uuid;
  v_cycle_farm uuid;
  v_sowing_source boolean:=false;
  v_pot_up_source boolean:=false;
begin
  select farm_id into v_lot_farm from atlas.production_lots where id=new.production_lot_id;
  select farm_id into v_task_farm from atlas.tasks where id=new.source_task_id;
  if new.crop_cycle_id is not null then select farm_id into v_cycle_farm from atlas.crop_cycles where id=new.crop_cycle_id; end if;
  if v_lot_farm is distinct from new.farm_id
     or v_task_farm is distinct from new.farm_id
     or (new.crop_cycle_id is not null and v_cycle_farm is distinct from new.farm_id)
  then raise exception 'Tray batch records must stay inside one farm'; end if;

  select exists(
    select 1 from atlas.production_lot_tasks plt
    where plt.production_lot_id=new.production_lot_id
      and plt.task_id=new.source_task_id
      and plt.link_role='sowing'
  ) into v_sowing_source;

  select exists(
    select 1
    from atlas.tasks t
    where t.id=new.source_task_id
      and lower(coalesce(t.action_key,t.task_type,''))='pot_up'
      and new.crop_cycle_id is not null
      and exists(
        select 1 from atlas.production_lot_crop_cycles plc
        where plc.production_lot_id=new.production_lot_id
          and plc.crop_cycle_id=new.crop_cycle_id
          and plc.relation_role='primary'
      )
      and (
        exists(
          select 1 from atlas.production_lot_tasks plt
          where plt.production_lot_id=new.production_lot_id
            and plt.task_id=new.source_task_id
            and plt.link_role='pot_up'
        )
        or exists(
          select 1 from atlas.task_crop_cycles tc
          where tc.task_id=new.source_task_id
            and tc.crop_cycle_id=new.crop_cycle_id
            and tc.role in ('preserves','affects')
        )
      )
  ) into v_pot_up_source;

  if not v_sowing_source and not v_pot_up_source then
    raise exception 'Tray batches require the production lot sowing task or a governed pot-up stage transition with crop lineage';
  end if;
  return new;
end;
$function$;