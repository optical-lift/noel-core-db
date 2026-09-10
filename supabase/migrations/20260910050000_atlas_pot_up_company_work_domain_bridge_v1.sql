begin;

-- Pot-up remains delegated employee work, but its source contract requires
-- actual output inventory before completion becomes institutional truth.
insert into atlas.work_result_contract_policies(
  contract_key,source_domain,acceptance_mode,active,description,metadata
) values (
  'production_pot_up_v1','production','domain_adapter',true,
  'Pot-up Company Work completes automatically from governed production output evidence; no manager approval is required.',
  jsonb_build_object(
    'delegatedResponsibilityCarriesExecutionAuthority',true,
    'ordinaryDoneAllowed',false,
    'structuredResultRequired',true,
    'inventoryStageTransitionRequired',true,
    'managerApprovalRequired',false,
    'domainResultAutoAccepted',true
  )
)
on conflict(contract_key) do update set
  source_domain=excluded.source_domain,
  acceptance_mode=excluded.acceptance_mode,
  active=excluded.active,
  description=excluded.description,
  metadata=excluded.metadata,
  updated_at=now();

create or replace function atlas.bind_planned_occurrence_company_work_adapter_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
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
  if v_count<>1 then
    raise exception 'Planned occurrence resolves to multiple open Company Work identities.' using errcode='23514';
  end if;

  select * into v_work
  from atlas.work_items w
  where w.organization_id=new.organization_id
    and w.source_object_type='planned_work_occurrence'
    and w.source_object_id=new.planned_occurrence_id
    and w.work_state='open'
  limit 1;

  insert into atlas.work_execution_adapters(
    organization_id,organization_unit_id,work_item_id,adapter_kind,planned_occurrence_id,task_id,state,metadata
  ) values(
    v_work.organization_id,v_work.organization_unit_id,v_work.id,'planned_occurrence_task',
    new.planned_occurrence_id,new.id,'active',
    jsonb_build_object(
      'source','bind_planned_occurrence_company_work_adapter_v1',
      'responsibilityAuthority','company_work',
      'executionCarrierAuthorityOnly',true
    )
  )
  on conflict(task_id) where task_id is not null do update set
    organization_id=excluded.organization_id,
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

drop trigger if exists aa_bind_planned_occurrence_company_work_adapter_v1 on atlas.tasks;
create trigger aa_bind_planned_occurrence_company_work_adapter_v1
after insert or update of planned_occurrence_id on atlas.tasks
for each row execute function atlas.bind_planned_occurrence_company_work_adapter_v1();

-- A generic Worker Day Done may not bypass a structured/domain result contract.
create or replace function atlas.guard_worker_delivery_structured_done_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if new.event_kind<>'done_reported' or new.projection_id is null then return new; end if;
  if exists(
    select 1
    from atlas.worker_week_projection_sources s
    join atlas.work_items w on w.id=s.work_item_id
    join atlas.work_result_contract_policies p on p.contract_key=w.result_contract_key and p.active
    where s.projection_id=new.projection_id
      and s.source_role='required'
      and w.work_state='open'
      and p.acceptance_mode in ('structured_submission','domain_adapter')
  ) then
    raise exception 'This Worker Day item requires its structured result before it can be marked done.' using errcode='23514';
  end if;
  return new;
end;
$function$;

drop trigger if exists worker_delivery_structured_done_guard_v1 on atlas.worker_delivery_pilot_events;
create trigger worker_delivery_structured_done_guard_v1
before insert on atlas.worker_delivery_pilot_events
for each row
when (new.event_kind='done_reported')
execute function atlas.guard_worker_delivery_structured_done_v1();

create or replace function atlas.skip_cancelled_occurrence_release_queue_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if new.state='cancelled' and old.state is distinct from new.state then
    update atlas.task_release_queue_items q
    set state='skipped',updated_at=now(),
        metadata=coalesce(q.metadata,'{}'::jsonb)||jsonb_build_object(
          'skipReason','source_occurrence_cancelled',
          'skippedAt',now(),
          'sourceOccurrenceId',new.id
        )
    where q.planned_occurrence_id=new.id and q.state='queued';
  end if;
  return new;
end;
$function$;

drop trigger if exists planned_occurrence_release_queue_cancel_skip_v1 on atlas.planned_work_occurrences;
create trigger planned_occurrence_release_queue_cancel_skip_v1
after update of state on atlas.planned_work_occurrences
for each row execute function atlas.skip_cancelled_occurrence_release_queue_v1();

-- Restore the Shasta vertical slice to the source-owned production result contract.
update atlas.work_items
set result_contract_key='production_pot_up_v1',
    metadata=(coalesce(metadata,'{}'::jsonb)-'completionAuthority'-'secondManagerClickRequired')||jsonb_build_object(
      'completionAuthority','production_domain_result',
      'structuredResultRequired',true,
      'managerApprovalRequired',false,
      'sourceContractRestored',true
    ),
    updated_at=now()
where stable_key='elm_pot_shasta_2026_09_09' and work_state='open';

-- Reconcile serial sequencing from already-recorded truth only. Missing historical
-- inventory remains unknown; no quantities are synthesized here.
update atlas.task_release_queue_items q
set state='completed',completed_at=coalesce(t.completed_at,now()),updated_at=now(),
    metadata=coalesce(q.metadata,'{}'::jsonb)||jsonb_build_object(
      'queueTruthReconciledBy','atlas_pot_up_company_work_domain_bridge_v1',
      'queueCompletionEvidence','existing_done_task',
      'historicalInventoryNotInvented',true
    )
from atlas.tasks t
where q.queue_key='anna_pot_up_serial'
  and q.state='active'
  and q.task_id=t.id
  and t.status='done';

update atlas.task_release_queue_items q
set state='completed',completed_at=o.updated_at,updated_at=now(),
    metadata=coalesce(q.metadata,'{}'::jsonb)||jsonb_build_object(
      'queueTruthReconciledBy','atlas_pot_up_company_work_domain_bridge_v1',
      'queueCompletionEvidence','owner_reconciled_completed_occurrence',
      'completionRecordedAt',o.updated_at,
      'historicalInventoryNotInvented',true,
      'inventoryReconciliationStillSeparate',true
    )
from atlas.planned_work_occurrences o
where q.queue_key='anna_pot_up_serial'
  and q.state='queued'
  and q.planned_occurrence_id=o.id
  and o.state='completed'
  and o.metadata->>'owner_reconciled_at' is not null;

update atlas.task_release_queue_items q
set state='skipped',updated_at=now(),
    metadata=coalesce(q.metadata,'{}'::jsonb)||jsonb_build_object(
      'skipReason','source_occurrence_already_cancelled',
      'skippedAt',now()
    )
from atlas.planned_work_occurrences o
where q.queue_key='anna_pot_up_serial'
  and q.state='queued'
  and q.planned_occurrence_id=o.id
  and o.state='cancelled';

do $repair$
declare
  v_work atlas.work_items%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
  v_occurrence atlas.planned_work_occurrences%rowtype;
  v_queue atlas.task_release_queue_items%rowtype;
  v_task_id uuid;
begin
  select * into v_work
  from atlas.work_items
  where stable_key='elm_pot_shasta_2026_09_09' and work_state='open'
  limit 1;
  if v_work.id is null then return; end if;

  select * into v_plan
  from atlas.work_execution_plans p
  where p.work_item_id=v_work.id and p.plan_state='active'
  order by p.updated_at desc limit 1;
  if v_plan.id is null then
    raise exception 'Shasta Company Work has no active governed execution plan.' using errcode='23514';
  end if;

  select * into v_occurrence
  from atlas.planned_work_occurrences o
  where o.id=v_work.source_object_id and v_work.source_object_type='planned_work_occurrence'
  for update;
  if v_occurrence.id is null then
    raise exception 'Shasta Company Work source occurrence is missing.' using errcode='23514';
  end if;

  select * into v_queue
  from atlas.task_release_queue_items q
  where q.planned_occurrence_id=v_occurrence.id and q.queue_key='anna_pot_up_serial'
  for update;
  if v_queue.id is null then
    raise exception 'Shasta pot-up queue item is missing.' using errcode='23514';
  end if;

  if exists(
    select 1 from atlas.task_release_queue_items prior
    where prior.farm_id=v_queue.farm_id and prior.queue_key=v_queue.queue_key
      and prior.position<v_queue.position and prior.state not in ('completed','skipped')
  ) then
    raise exception 'Shasta cannot enter execution while a prior serial queue item is unresolved.' using errcode='23514';
  end if;

  if v_occurrence.state not in ('released','completed') then
    update atlas.planned_work_occurrences
    set planned_due_date=v_plan.exposure_service_date,
        not_before_date=least(coalesce(not_before_date,v_plan.exposure_service_date),v_plan.exposure_service_date),
        gate_satisfied_at=coalesce(gate_satisfied_at,now()),
        state='eligible',
        task_payload=jsonb_set(
          jsonb_set(coalesce(task_payload,'{}'::jsonb),'{due_date}',to_jsonb(v_plan.exposure_service_date::text),true),
          '{metadata}',
          coalesce(task_payload->'metadata','{}'::jsonb)||jsonb_build_object(
            'execution_date',v_plan.exposure_service_date,
            'queueTruthReconciledBy','atlas_pot_up_company_work_domain_bridge_v1'
          ),true
        ),
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'queueTruthReconciledBy','atlas_pot_up_company_work_domain_bridge_v1',
          'reconciledToManagerPlanId',v_plan.id,
          'reconciledExecutionDate',v_plan.exposure_service_date,
          'historicalPredecessorInventoryNotInvented',true
        ),
        updated_at=now()
    where id=v_occurrence.id;

    perform atlas.materialize_specific_work_occurrence_v1(v_occurrence.id,v_plan.exposure_service_date);
  end if;

  select released_task_id into v_task_id
  from atlas.planned_work_occurrences where id=v_occurrence.id;
  if v_task_id is null then
    raise exception 'Shasta source occurrence did not materialize an execution task.' using errcode='23514';
  end if;

  update atlas.task_release_queue_items
  set task_id=v_task_id,state='active',activated_at=coalesce(activated_at,now()),updated_at=now(),
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'queueTruthReconciledBy','atlas_pot_up_company_work_domain_bridge_v1',
        'releaseArchitecture','reconciled_current_manager_plan',
        'releasedForDate',v_plan.exposure_service_date,
        'historicalPredecessorInventoryNotInvented',true
      )
  where id=v_queue.id;

  perform atlas.sync_task_release_queue_summary_v1(v_queue.farm_id,v_queue.queue_key);
end;
$repair$;

commit;
