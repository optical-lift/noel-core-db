create or replace function atlas.bind_planned_occurrence_company_work_adapter_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_work atlas.work_items%rowtype;
  v_count integer;
begin
  if new.planned_occurrence_id is null or new.organization_id is null then return new; end if;
  select count(*)::integer into v_count
  from atlas.work_items w
  where w.organization_id=new.organization_id
    and w.source_object_type='planned_work_occurrence'
    and w.source_object_id=new.planned_occurrence_id
    and w.work_state='open';
  if v_count=0 then return new; end if;
  if v_count<>1 then raise exception 'Planned occurrence resolves to multiple open Company Work identities.' using errcode='23514'; end if;
  select * into v_work
  from atlas.work_items w
  where w.organization_id=new.organization_id
    and w.source_object_type='planned_work_occurrence'
    and w.source_object_id=new.planned_occurrence_id
    and w.work_state='open'
  limit 1;

  update atlas.work_execution_adapters a
  set organization_id=v_work.organization_id,
      organization_unit_id=v_work.organization_unit_id,
      work_item_id=v_work.id,
      adapter_kind='planned_occurrence_task',
      task_id=new.id,
      state='active',
      completed_at=null,
      retired_at=null,
      metadata=coalesce(a.metadata,'{}'::jsonb)||jsonb_build_object('source','bind_planned_occurrence_company_work_adapter_v1','responsibilityAuthority','company_work','executionCarrierAuthorityOnly',true,'reboundByOccurrence',true),
      updated_at=now()
  where a.planned_occurrence_id=new.planned_occurrence_id;
  if found then return new; end if;

  insert into atlas.work_execution_adapters(organization_id,organization_unit_id,work_item_id,adapter_kind,planned_occurrence_id,task_id,state,metadata)
  values(v_work.organization_id,v_work.organization_unit_id,v_work.id,'planned_occurrence_task',new.planned_occurrence_id,new.id,'active',jsonb_build_object('source','bind_planned_occurrence_company_work_adapter_v1','responsibilityAuthority','company_work','executionCarrierAuthorityOnly',true))
  on conflict(task_id) where task_id is not null do update
  set organization_id=excluded.organization_id,
      organization_unit_id=excluded.organization_unit_id,
      work_item_id=excluded.work_item_id,
      adapter_kind=excluded.adapter_kind,
      planned_occurrence_id=excluded.planned_occurrence_id,
      state='active',completed_at=null,retired_at=null,
      metadata=atlas.work_execution_adapters.metadata||excluded.metadata,
      updated_at=now();
  return new;
end;
$function$;