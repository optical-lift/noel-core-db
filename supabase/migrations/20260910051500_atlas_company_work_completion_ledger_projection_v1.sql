begin;

-- A completed governed Company Work item becomes organization-visible
-- accountability without carrying any Personal Atlas/private causality into the
-- institutional Ledger.
create or replace function atlas.project_completed_company_work_to_ledger_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_result atlas.work_execution_results%rowtype;
  v_acceptance atlas.work_result_acceptances%rowtype;
  v_projection jsonb;
  v_entry_id uuid;
  v_assignee_membership_id uuid;
  v_position_id uuid;
  v_position_title text;
begin
  if old.work_state is not distinct from new.work_state or new.work_state<>'completed' then
    return new;
  end if;

  select r.* into v_result
  from atlas.work_execution_results r
  join atlas.work_result_acceptances a
    on a.execution_result_id=r.id and a.decision='accepted'
  where r.organization_id=new.organization_id
    and r.work_item_id=new.id
    and r.result_kind='completed'
  order by a.accepted_at desc,r.reported_at desc,r.id desc
  limit 1;

  if v_result.id is null then
    return new;
  end if;

  select * into v_acceptance
  from atlas.work_result_acceptances a
  where a.execution_result_id=v_result.id and a.decision='accepted';

  v_assignee_membership_id:=v_result.reported_by_organization_membership_id;

  if v_assignee_membership_id is not null then
    select p.id,p.display_title
    into v_position_id,v_position_title
    from atlas.organization_position_appointments opa
    join atlas.organization_positions p
      on p.id=opa.position_id and p.organization_id=opa.organization_id
    where opa.organization_id=new.organization_id
      and opa.organization_membership_id=v_assignee_membership_id
      and opa.status='active'
      and opa.begins_at<=coalesce(new.completed_at,now())
      and (opa.ends_at is null or opa.ends_at>coalesce(new.completed_at,now()))
      and p.status='active'
    order by case when opa.appointment_kind='primary' then 0 else 1 end,opa.begins_at desc,opa.id
    limit 1;
  end if;

  v_projection:=atlas.project_organization_ledger_event_internal_v1(
    new.organization_id,
    new.organization_unit_id,
    'company-work-completed:'||new.id::text,
    'company_work',
    'company_work_completed',
    v_result.id::text,
    coalesce(new.completed_at,v_acceptance.accepted_at,v_result.reported_at,now()),
    new.title,
    null,
    'established',
    'closed',
    jsonb_strip_nulls(jsonb_build_object(
      'workItemId',new.id,
      'resultId',v_result.id,
      'resultKind',v_result.result_kind,
      'resultContractKey',v_result.result_contract_key,
      'acceptanceId',v_acceptance.id,
      'acceptanceKind',v_acceptance.acceptance_kind,
      'responsibleAllocationId',v_result.responsible_allocation_id,
      'reportedByOrganizationMembershipId',v_result.reported_by_organization_membership_id,
      'reportedByFarmMembershipId',v_result.reported_by_farm_membership_id,
      'taskId',v_result.task_id,
      'positionId',v_position_id,
      'positionTitle',v_position_title,
      'completedAt',new.completed_at
    )),
    jsonb_build_object(
      'source','project_completed_company_work_to_ledger_v1',
      'institutionalOnly',true,
      'personalAtlasCausalityIncluded',false
    ),
    jsonb_strip_nulls(jsonb_build_object(
      'workItemId',new.id,
      'executionResultId',v_result.id,
      'acceptanceId',v_acceptance.id
    )),
    v_acceptance.accepted_at
  );

  v_entry_id:=(v_projection->>'entryId')::uuid;

  perform atlas.link_organization_ledger_subject_internal_v1(
    v_entry_id,'company_work','work_item',new.id::text,'completed_by_result',
    jsonb_build_object('source','project_completed_company_work_to_ledger_v1'),
    '{}'::jsonb
  );
  perform atlas.link_organization_ledger_subject_internal_v1(
    v_entry_id,'company_work','execution_result',v_result.id::text,'evidence',
    jsonb_build_object('source','project_completed_company_work_to_ledger_v1'),
    '{}'::jsonb
  );

  if v_result.responsible_allocation_id is not null then
    perform atlas.link_organization_ledger_subject_internal_v1(
      v_entry_id,'company_work','responsibility_allocation',v_result.responsible_allocation_id::text,'responsibility',
      jsonb_build_object('source','project_completed_company_work_to_ledger_v1'),
      '{}'::jsonb
    );
  end if;

  if v_assignee_membership_id is not null then
    perform atlas.link_organization_ledger_subject_internal_v1(
      v_entry_id,'organization','membership',v_assignee_membership_id::text,'reported_by',
      jsonb_build_object('source','project_completed_company_work_to_ledger_v1'),
      '{}'::jsonb
    );
  end if;

  if v_position_id is not null then
    perform atlas.link_organization_ledger_subject_internal_v1(
      v_entry_id,'organization','position',v_position_id::text,'under_position',
      jsonb_build_object('source','project_completed_company_work_to_ledger_v1'),
      '{}'::jsonb
    );
  end if;

  if v_result.task_id is not null then
    perform atlas.link_organization_ledger_subject_internal_v1(
      v_entry_id,'execution','task',v_result.task_id::text,'execution_carrier',
      jsonb_build_object('source','project_completed_company_work_to_ledger_v1'),
      '{}'::jsonb
    );
  end if;

  return new;
end;
$function$;

drop trigger if exists work_items_project_completed_company_work_to_ledger_v1 on atlas.work_items;
create trigger work_items_project_completed_company_work_to_ledger_v1
after update of work_state on atlas.work_items
for each row
when (new.work_state='completed' and old.work_state is distinct from new.work_state)
execute function atlas.project_completed_company_work_to_ledger_v1();

commit;
