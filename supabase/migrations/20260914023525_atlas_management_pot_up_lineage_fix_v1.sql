begin;

create or replace function atlas.organization_management_record_production_pot_up_api_v1(
  p_task_id uuid,
  p_outputs jsonb,
  p_care_date date default null,
  p_note text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas','auth'
as $$
declare
  v_uid uuid:=auth.uid();
  v_work_id uuid;
  v_task atlas.tasks%rowtype;
  v_group jsonb;
  v_tray jsonb;
  v_cycle_id uuid;
  v_tray_number integer;
  v_living numeric;
  v_group_living numeric;
  v_seen integer[];
  v_normalized jsonb:='[]'::jsonb;
  v_aggregate jsonb:='[]'::jsonb;
  v_result jsonb;
begin
  if v_uid is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_task_id is null then raise exception 'Pot-up task required.' using errcode='22023'; end if;
  if jsonb_typeof(p_outputs)<>'array' or jsonb_array_length(p_outputs)=0 then
    raise exception 'Pot-up output must contain at least one crop-cycle result.' using errcode='22023';
  end if;

  select a.work_item_id into v_work_id
  from atlas.work_execution_adapters a
  where a.task_id=p_task_id and a.state='active'
  order by a.created_at desc,a.id desc limit 1;
  if v_work_id is null then raise exception 'Active Company Work adapter for the pot-up task was not found.' using errcode='P0002'; end if;
  if not atlas.can_adjudicate_company_work_v1(v_work_id) then
    raise exception 'Management authority over this pot-up work is required.' using errcode='42501';
  end if;

  select * into v_task from atlas.tasks where id=p_task_id for update;
  if v_task.id is null then raise exception 'Pot-up task was not found.' using errcode='P0002'; end if;
  if lower(coalesce(v_task.action_key,''))<>'pot_up' and lower(coalesce(v_task.task_type,''))<>'pot_up' then
    raise exception 'Execution task is not pot-up.' using errcode='23514';
  end if;

  for v_group in select value from jsonb_array_elements(p_outputs)
  loop
    begin v_cycle_id:=(v_group->>'cropCycleId')::uuid;
    exception when others then raise exception 'Each output requires a valid cropCycleId.' using errcode='22023'; end;
    if jsonb_typeof(v_group->'physicalTrays')<>'array' or jsonb_array_length(v_group->'physicalTrays')=0 then
      raise exception 'Each crop cycle requires at least one physical output tray.' using errcode='22023';
    end if;
    if not exists(
      select 1 from atlas.task_crop_cycles tc
      where tc.task_id=p_task_id and tc.crop_cycle_id=v_cycle_id and tc.role in ('preserves','affects')
    ) then raise exception 'Crop cycle % is not governed by this pot-up task.',v_cycle_id using errcode='23514'; end if;

    v_group_living:=0;
    v_seen:=array[]::integer[];
    for v_tray in select value from jsonb_array_elements(v_group->'physicalTrays')
    loop
      begin
        v_tray_number:=(v_tray->>'trayNumber')::integer;
        v_living:=(v_tray->>'livingPlants')::numeric;
      exception when others then
        raise exception 'Each physical tray requires numeric trayNumber and livingPlants.' using errcode='22023';
      end;
      if v_tray_number<=0 or v_living<=0 then
        raise exception 'Tray number and living plant count must be positive.' using errcode='22023';
      end if;
      if v_tray_number=any(v_seen) then
        raise exception 'Physical tray numbers must be unique within a crop cycle.' using errcode='22023';
      end if;
      v_seen:=array_append(v_seen,v_tray_number);
      v_group_living:=v_group_living+v_living;
    end loop;

    v_normalized:=v_normalized||jsonb_build_array(jsonb_build_object(
      'cropCycleId',v_cycle_id,
      'containerKind',coalesce(nullif(btrim(v_group->>'containerKind'),''),v_task.metadata->>'output_container_kind'),
      'physicalTrays',v_group->'physicalTrays'
    ));
    v_aggregate:=v_aggregate||jsonb_build_array(jsonb_build_object(
      'cropCycleId',v_cycle_id,
      'livingPlants',v_group_living,
      'trayCount',jsonb_array_length(v_group->'physicalTrays'),
      'containerKind',coalesce(nullif(btrim(v_group->>'containerKind'),''),v_task.metadata->>'output_container_kind')
    ));
  end loop;

  insert into atlas.production_lot_tasks(production_lot_id,task_id,link_role,source,metadata)
  select distinct plc.production_lot_id,v_task.id,'pot_up',
    'organization_management_record_production_pot_up_api_v1',
    jsonb_build_object('cropCycleId',tc.crop_cycle_id,'companyWorkItemId',v_work_id,'managementActorUserId',v_uid)
  from atlas.task_crop_cycles tc
  join atlas.production_lot_crop_cycles plc
    on plc.crop_cycle_id=tc.crop_cycle_id and plc.relation_role='primary'
  join atlas.production_lots pl
    on pl.id=plc.production_lot_id and pl.farm_id=v_task.farm_id and pl.lifecycle_status='active'
  where tc.task_id=v_task.id and tc.role in ('preserves','affects')
  on conflict(production_lot_id,task_id,link_role) do update set
    source=excluded.source,
    metadata=atlas.production_lot_tasks.metadata||excluded.metadata;

  if not exists(
    select 1 from atlas.production_lot_tasks plt
    where plt.task_id=v_task.id and plt.link_role='pot_up'
  ) then raise exception 'Pot-up task has no unambiguous production-lot lineage.' using errcode='23514'; end if;

  update atlas.tasks
  set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'pot_up_physical_outputs',v_normalized,
        'pot_up_structured_result_source','organization_management_record_production_pot_up_api_v1',
        'pot_up_management_actor_user_id',v_uid
      ),updated_at=now()
  where id=p_task_id;

  v_result:=atlas.record_production_pot_up_v1(
    p_task_id,v_aggregate,coalesce(p_care_date,current_date),p_note,p_idempotency_key
  );

  update atlas.production_tray_batches b
  set metadata=coalesce(b.metadata,'{}'::jsonb)||jsonb_build_object(
        'physical_trays',g.value->'physicalTrays',
        'physical_trays_recorded_by',v_uid,
        'physical_trays_recorded_under','management_authority'
      ),updated_at=now()
  from jsonb_array_elements(v_normalized) g(value)
  where b.source_task_id=p_task_id and b.crop_cycle_id=(g.value->>'cropCycleId')::uuid;

  return jsonb_build_object(
    'ok',true,'state','production_pot_up_recorded_by_management',
    'workItemId',v_work_id,'domainResult',v_result
  );
end;
$$;

revoke all on function atlas.organization_management_record_production_pot_up_api_v1(uuid,jsonb,date,text,text) from public, anon;
grant execute on function atlas.organization_management_record_production_pot_up_api_v1(uuid,jsonb,date,text,text) to authenticated, service_role;

commit;