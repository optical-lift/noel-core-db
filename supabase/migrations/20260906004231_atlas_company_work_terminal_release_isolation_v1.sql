create or replace function atlas.release_after_task_terminal_v1()
returns trigger
language plpgsql security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_company_work_managed boolean:=false;
begin
  if current_setting('atlas.reservoir_migration',true)='on' then return new; end if;
  if current_setting('atlas.release_engine_active',true)='on' then return new; end if;

  if old.status in ('open','blocked') and new.status in ('done','archived','skipped') then
    select exists(
      select 1
      from atlas.work_execution_adapters a
      join atlas.work_items wi
        on wi.organization_id=a.organization_id
       and wi.id=a.work_item_id
      where a.task_id=new.id
        and a.state in ('active','completed','retired')
        and coalesce(wi.metadata->>'managerSchedulingAuthority','')='work_execution_plans'
    ) into v_company_work_managed;

    if new.planned_occurrence_id is not null then
      update atlas.planned_work_occurrences child
      set state=case when new.status='done' then 'completed' else 'cancelled' end,
          updated_at=now(),metadata=child.metadata || jsonb_build_object(
            'closed_with_parent_task_id',new.id,'closed_with_parent_status',new.status,'closed_at',now())
      where child.parent_occurrence_id=new.planned_occurrence_id and child.state in ('planned','eligible','failed');

      update atlas.planned_work_occurrences
      set state=case when new.status='done' then 'completed' else 'cancelled' end,
          updated_at=now(),metadata=metadata || jsonb_build_object(
            'terminal_task_status',new.status,'terminal_task_id',new.id,'terminal_at',now())
      where id=new.planned_occurrence_id;
    end if;

    -- Manager-scheduled Company Work has its own planning/release authority.
    -- Finishing one of these carriers must not invoke the unrelated legacy
    -- farm-wide release sweep; that sweep may still serve legacy farm work.
    if not v_company_work_managed then
      perform atlas.release_eligible_work_v1(new.farm_id,null,10);
    end if;
  end if;
  return new;
end;
$$;