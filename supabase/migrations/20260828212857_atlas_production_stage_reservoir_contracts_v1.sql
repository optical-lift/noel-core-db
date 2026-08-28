insert into atlas.work_definitions(farm_id,stable_key,title_template,task_type,source_kind,action_key,work_class,default_priority,default_visibility_scope,active,metadata)
values
('6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid,'production:hardening:v1','Harden off production cohort','hardening_off','production_stage_engine','hardening_off','standard','high','assigned_worker',true,jsonb_build_object('contractVersion','production_stage_handoff_v1','stage','hardening')),
('6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid,'production:transplant-readiness:v1','Check production transplant readiness','transplant_readiness','production_stage_engine','transplant_readiness','standard','high','assigned_worker',true,jsonb_build_object('contractVersion','production_stage_handoff_v1','stage','transplant_readiness'))
on conflict(farm_id,stable_key) do update set title_template=excluded.title_template,task_type=excluded.task_type,source_kind=excluded.source_kind,action_key=excluded.action_key,work_class=excluded.work_class,default_priority=excluded.default_priority,default_visibility_scope=excluded.default_visibility_scope,active=true,metadata=atlas.work_definitions.metadata||excluded.metadata,updated_at=now();

insert into atlas.work_release_policies(farm_id,work_definition_id,stable_key,gate_type,gate_config,horizon_days,maximum_active_instances,active,metadata)
select wd.farm_id,wd.id,wd.stable_key||':time-window','time_window',jsonb_build_object('automatic',true,'source_kind','production_stage_engine','notBeforeAuthoritative',true),30,50,true,jsonb_build_object('contractVersion','production_stage_handoff_v1')
from atlas.work_definitions wd
where wd.farm_id='6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid and wd.stable_key in ('production:hardening:v1','production:transplant-readiness:v1')
on conflict(farm_id,stable_key) do update set work_definition_id=excluded.work_definition_id,gate_type=excluded.gate_type,gate_config=excluded.gate_config,horizon_days=excluded.horizon_days,maximum_active_instances=excluded.maximum_active_instances,active=true,metadata=atlas.work_release_policies.metadata||excluded.metadata,updated_at=now();

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
  if v_lot_farm is distinct from new.farm_id or v_task_farm is distinct from new.farm_id or (new.crop_cycle_id is not null and v_cycle_farm is distinct from new.farm_id) then raise exception 'Tray batch records must stay inside one farm'; end if;
  select exists(select 1 from atlas.production_lot_tasks plt where plt.production_lot_id=new.production_lot_id and plt.task_id=new.source_task_id and plt.link_role='sowing') into v_sowing_source;
  select exists(
    select 1 from atlas.production_lot_tasks plt join atlas.tasks t on t.id=plt.task_id
    where plt.production_lot_id=new.production_lot_id and plt.task_id=new.source_task_id and plt.link_role='pot_up'
      and lower(coalesce(t.action_key,t.task_type,''))='pot_up' and new.crop_cycle_id is not null
      and exists(select 1 from atlas.production_lot_crop_cycles plc where plc.production_lot_id=new.production_lot_id and plc.crop_cycle_id=new.crop_cycle_id and plc.relation_role='primary')
  ) into v_pot_up_source;
  if not v_sowing_source and not v_pot_up_source then raise exception 'Tray batches require the production lot sowing task or a governed pot-up stage transition with crop lineage'; end if;
  return new;
end;
$function$;


do $$
declare v_def text; v_oid oid;
begin
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='atlas' and p.proname='record_production_readiness_v1';
  if v_oid is null then raise exception 'record_production_readiness_v1 not found'; end if;
  v_def:=pg_get_functiondef(v_oid);
  if position('v_batch.status not in (''seedling_care'',''hardening'',''transplant_ready'')' in v_def)=0 then
    if position('v_batch.status not in (''seedling_care'',''transplant_ready'')' in v_def)=0 then raise exception 'readiness allowed-status patch point not found'; end if;
    v_def:=replace(v_def,'v_batch.status not in (''seedling_care'',''transplant_ready'')','v_batch.status not in (''seedling_care'',''hardening'',''transplant_ready'')');
  end if;
  if position('status=case when v_batch.status=''hardening'' then ''hardening'' else ''seedling_care'' end' in v_def)=0 then
    if position('update atlas.production_tray_batches set status=''seedling_care'',current_quantity=p_surviving_seedlings' in v_def)=0 then raise exception 'readiness not-ready batch-stage patch point not found'; end if;
    v_def:=replace(v_def,'update atlas.production_tray_batches set status=''seedling_care'',current_quantity=p_surviving_seedlings,current_unit=''seedlings'',tray_count=coalesce(p_tray_count,tray_count),metadata=metadata||jsonb_build_object(''last_readiness_observation_id'',v_obs.id),updated_at=now() where id=v_batch.id;','update atlas.production_tray_batches set status=case when v_batch.status=''hardening'' then ''hardening'' else ''seedling_care'' end,current_quantity=p_surviving_seedlings,current_unit=''seedlings'',tray_count=coalesce(p_tray_count,tray_count),metadata=metadata||jsonb_build_object(''last_readiness_observation_id'',v_obs.id),updated_at=now() where id=v_batch.id;');
    v_def:=replace(v_def,'update atlas.production_lots set current_quantity=p_surviving_seedlings,current_unit=''seedlings'',current_stage=''seedling_care'',metadata=metadata||jsonb_build_object(''last_biological_event'',''transplant_not_ready''),updated_at=now() where id=v_lot.id;','update atlas.production_lots set current_quantity=p_surviving_seedlings,current_unit=''seedlings'',current_stage=case when v_batch.status=''hardening'' then ''hardening'' else ''seedling_care'' end,metadata=metadata||jsonb_build_object(''last_biological_event'',''transplant_not_ready''),updated_at=now() where id=v_lot.id;');
  end if;
  if position('coalesce(v_task.generated_from_id,(select nullif(plt.metadata->>''tray_batch_id'','''')::uuid' in v_def)=0 then
    v_def:=replace(v_def,
      'select * into v_batch from atlas.production_tray_batches where id=v_task.generated_from_id and production_lot_id=v_lot.id for update;',
      'select * into v_batch from atlas.production_tray_batches where id=coalesce(v_task.generated_from_id,(select nullif(plt.metadata->>''tray_batch_id'','''')::uuid from atlas.production_lot_tasks plt where plt.task_id=p_task_id and plt.production_lot_id=v_lot.id and plt.link_role=''transplant_readiness'' order by plt.created_at desc limit 1)) and production_lot_id=v_lot.id for update;'
    );
  end if;
  execute v_def;
end $$;