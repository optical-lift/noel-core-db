create or replace function atlas.sync_company_work_plan_after_adapter_task_v1()
returns trigger
language plpgsql security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_provenance_ready boolean:=true;
begin
  if new.task_id is distinct from old.task_id or (tg_op='INSERT' and new.task_id is not null) then
    if new.task_id is not null and new.planned_occurrence_id is not null then
      select (
        o.released_task_id=new.task_id
        or exists(
          select 1 from atlas.task_release_events e
          where e.task_id=new.task_id and e.occurrence_id=new.planned_occurrence_id
        )
      ) into v_provenance_ready
      from atlas.planned_work_occurrences o
      where o.id=new.planned_occurrence_id;

      if not coalesce(v_provenance_ready,false) then
        return new;
      end if;
    end if;
    perform atlas.sync_company_work_execution_plan_carrier_v1(new.work_item_id);
  end if;
  return new;
end;
$$;

create or replace function atlas.sync_company_work_plan_after_occurrence_release_v1()
returns trigger
language plpgsql security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_work_id uuid;
begin
  if new.released_task_id is null then return new; end if;
  if old.released_task_id is not distinct from new.released_task_id
     and old.state is not distinct from new.state then
    return new;
  end if;

  select a.work_item_id into v_work_id
  from atlas.work_execution_adapters a
  join atlas.work_items wi
    on wi.organization_id=a.organization_id
   and wi.id=a.work_item_id
  where a.planned_occurrence_id=new.id
    and a.task_id=new.released_task_id
    and a.state='active'
    and coalesce(wi.metadata->>'managerSchedulingAuthority','')='work_execution_plans'
  order by a.created_at
  limit 1;

  if v_work_id is not null then
    perform atlas.sync_company_work_execution_plan_carrier_v1(v_work_id);
  end if;
  return new;
end;
$$;

drop trigger if exists planned_work_occurrences_sync_company_work_plan_v1 on atlas.planned_work_occurrences;
create trigger planned_work_occurrences_sync_company_work_plan_v1
after update of state,released_task_id on atlas.planned_work_occurrences
for each row execute function atlas.sync_company_work_plan_after_occurrence_release_v1();