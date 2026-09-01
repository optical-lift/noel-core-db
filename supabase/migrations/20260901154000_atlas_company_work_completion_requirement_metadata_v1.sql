begin;

-- Company Work completion is a shared task-transition consequence. The
-- requirement-link UPDATE joins work_requirements and work_requirement_links,
-- both of which own a metadata column. Qualify the requirement row on the
-- right-hand side so any adopted Company Work task can complete without an
-- ambiguous-column failure.

create or replace function atlas.sync_weekly_harvest_company_work_task_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_adapter atlas.work_execution_adapters%rowtype;
  v_work atlas.work_items%rowtype;
begin
  if old.status is not distinct from new.status then
    return new;
  end if;

  select a.* into v_adapter
  from atlas.work_execution_adapters a
  where a.task_id = new.id
  order by a.updated_at desc
  limit 1;

  if v_adapter.id is null then
    return new;
  end if;

  select * into v_work
  from atlas.work_items
  where organization_id = v_adapter.organization_id
    and id = v_adapter.work_item_id;

  if v_work.id is null then
    return new;
  end if;

  if new.status = 'done' then
    update atlas.work_items
    set work_state = 'completed',
        completed_at = coalesce(completed_at,now()),
        metadata = metadata || jsonb_build_object(
          'completionSource','legacy_harvest_execution_adapter',
          'legacyTaskId',new.id
        ),
        updated_at = now()
    where organization_id = v_adapter.organization_id
      and id = v_adapter.work_item_id
      and work_state = 'open';

    update atlas.work_requirements r
    set state = 'satisfied',
        satisfied_at = coalesce(r.satisfied_at,now()),
        metadata = coalesce(r.metadata,'{}'::jsonb) || jsonb_build_object(
          'satisfactionSource','company_work_item_completion',
          'workItemId',v_adapter.work_item_id
        ),
        updated_at = now()
    from atlas.work_requirement_links l
    where l.organization_id = v_adapter.organization_id
      and l.work_item_id = v_adapter.work_item_id
      and l.requirement_id = r.id
      and l.active
      and l.link_role = 'resolves'
      and r.state = 'active';

    update atlas.work_allocations
    set state = 'completed',
        completed_at = coalesce(completed_at,now()),
        updated_at = now()
    where organization_id = v_adapter.organization_id
      and work_item_id = v_adapter.work_item_id
      and state = 'active';

    update atlas.work_time_contracts
    set contract_state = 'satisfied',
        updated_at = now()
    where organization_id = v_adapter.organization_id
      and work_item_id = v_adapter.work_item_id
      and contract_state = 'active';

    update atlas.work_execution_adapters
    set state = 'completed',
        completed_at = coalesce(completed_at,now()),
        retired_at = null,
        updated_at = now()
    where id = v_adapter.id;

    update atlas.work_planning_conflicts
    set state = 'resolved',
        resolution_kind = 'work_completed',
        resolution_note = 'The institutional work was completed through a worker-facing execution carrier.',
        resolved_at = now(),
        updated_at = now()
    where organization_id = v_adapter.organization_id
      and work_item_id = v_adapter.work_item_id
      and state = 'open';

    return new;
  end if;

  if new.status in ('archived','skipped') and v_work.work_state = 'open' then
    perform atlas.retire_weekly_harvest_company_work_adapter_v1(
      v_adapter.planned_occurrence_id,
      new.id,
      'Legacy weekly Harvest task became ' || new.status || ' while institutional Harvest work remains open.'
    );
  end if;

  return new;
end;
$function$;

commit;
