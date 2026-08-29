create or replace function atlas.prepare_reference_tray_batch_source_v1()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  v_org_id uuid;
  v_task_id uuid;
  v_lot_label text;
begin
  if not atlas.is_system_fixture_farm_v1(new.farm_id) or new.source_task_id is not null then
    return new;
  end if;

  select f.organization_id into v_org_id from atlas.farms f where f.id=new.farm_id;
  select pl.lot_label into v_lot_label from atlas.production_lots pl where pl.id=new.production_lot_id;
  if v_org_id is null or v_lot_label is null then
    return new;
  end if;

  insert into atlas.tasks(
    farm_id,title,task_type,status,priority,due_date,completed_at,note,metadata,
    action_key,work_class,visibility_scope,origin_kind,task_scope,organization_id,
    work_lane,commitment_kind,effort_units
  ) values(
    new.farm_id,
    'Fixture predecessor — sow '||v_lot_label,
    'sowing','done','normal',coalesce(new.sown_date,(now() at time zone 'America/Chicago')::date),now(),
    'Synthetic historical predecessor created only to establish lawful tray-batch lineage in the Atlas Reference Company.',
    jsonb_build_object(
      'system_fixture',true,
      'synthetic_truth',true,
      'reference_fixture_predecessor',true,
      'production_lot_id',new.production_lot_id,
      'production_tray_batch_id',new.id,
      'warning','Fixture history only; not customer work.'
    ),
    'sow','standard','owner','generated','farm_operation',v_org_id,
    'process_continuation','dependency',1
  ) returning id into v_task_id;

  insert into atlas.production_lot_tasks(production_lot_id,task_id,link_role,source,metadata)
  values(
    new.production_lot_id,v_task_id,'sowing','reference_company_fixture_bootstrap',
    jsonb_build_object('system_fixture',true,'synthetic_truth',true,'tray_batch_id',new.id)
  );

  new.source_task_id:=v_task_id;
  return new;
end;
$function$;

revoke all on function atlas.prepare_reference_tray_batch_source_v1() from public,anon,authenticated;

drop trigger if exists aa_prepare_reference_tray_batch_source_v1 on atlas.production_tray_batches;
create trigger aa_prepare_reference_tray_batch_source_v1
before insert on atlas.production_tray_batches
for each row execute function atlas.prepare_reference_tray_batch_source_v1();

comment on function atlas.prepare_reference_tray_batch_source_v1() is 'Reference-company-only fixture adapter. When a synthetic scenario intentionally starts with an existing tray cohort, creates the completed synthetic sowing predecessor required by the real production lineage invariant. Does not alter non-fixture farms.';