create or replace function atlas.refresh_production_transplant_gate_from_prep_task_v1() returns trigger
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare v_lot_id uuid;
begin
  if new.status is not distinct from old.status then return new; end if;

  select plt.production_lot_id into v_lot_id
  from atlas.production_lot_tasks plt
  where plt.task_id=new.id and plt.link_role='bed_preparation'
  order by plt.created_at desc limit 1;

  if v_lot_id is null then
    begin v_lot_id:=nullif(new.metadata->>'production_lot_id','')::uuid; exception when others then v_lot_id:=null; end;
  end if;

  if v_lot_id is null and new.generated_from='production_bed_assignment' then
    begin
      select production_lot_id into v_lot_id
      from atlas.production_bed_assignments
      where id=coalesce(new.generated_from_id,nullif(new.metadata->>'production_bed_assignment_id','')::uuid);
    exception when others then v_lot_id:=null;
    end;
  end if;

  if v_lot_id is not null and exists(select 1 from atlas.production_transplant_gates where production_lot_id=v_lot_id and gate_status<>'transplanted') then
    perform atlas.reconcile_production_work_v1(v_lot_id,null);
  end if;
  return new;
end;
$function$;
revoke all on function atlas.refresh_production_transplant_gate_from_prep_task_v1() from public,anon,authenticated,service_role;
grant execute on function atlas.refresh_production_transplant_gate_from_prep_task_v1() to postgres;

comment on function atlas.refresh_production_transplant_gate_from_prep_task_v1() is 'Wakes production reconciliation from canonical production_lot_tasks bed-preparation lineage, with task metadata/generated_from only as fallbacks.';