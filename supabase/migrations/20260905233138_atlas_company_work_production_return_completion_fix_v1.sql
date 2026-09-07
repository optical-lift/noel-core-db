create or replace function atlas.reconcile_production_bed_preparation_company_work_completion_v1(p_work_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_work atlas.work_items%rowtype;
  v_assignment atlas.production_bed_assignments%rowtype;
  v_lot atlas.production_lots%rowtype;
  v_farm atlas.farms%rowtype;
  v_req_id uuid;
  v_allocation atlas.work_allocations%rowtype;
  v_gate jsonb;
  v_required jsonb;
  v_completed jsonb;
  v_required_ledger_id uuid;
  v_completed_ledger_id uuid;
  v_occurrence_id uuid;
  v_completed_at timestamptz;
begin
  if p_work_item_id is null then raise exception 'Company Work item is required.' using errcode='22023'; end if;

  select * into v_work from atlas.work_items where id=p_work_item_id;
  if v_work.id is null then raise exception 'Company Work item was not found.' using errcode='P0002'; end if;
  if v_work.source_object_type<>'production_bed_assignment' then return jsonb_build_object('state','unsupported_source','workItemId',v_work.id); end if;
  if v_work.work_state<>'completed' then return jsonb_build_object('state','work_not_completed','workItemId',v_work.id,'workState',v_work.work_state); end if;

  select * into v_assignment from atlas.production_bed_assignments where id=v_work.source_object_id;
  if v_assignment.id is null then raise exception 'Production bed assignment linked to Company Work was not found.' using errcode='23514'; end if;
  select * into v_lot from atlas.production_lots where id=v_assignment.production_lot_id;
  select * into v_farm from atlas.farms where id=v_assignment.farm_id;
  if v_lot.id is null or v_farm.id is null or v_farm.organization_id<>v_work.organization_id then raise exception 'Production/Company Work custody mismatch.' using errcode='23514'; end if;

  v_completed_at:=coalesce(v_work.completed_at,now());

  select l.requirement_id into v_req_id
  from atlas.work_requirement_links l
  where l.organization_id=v_work.organization_id and l.work_item_id=v_work.id and l.active
  order by l.created_at
  limit 1;

  select * into v_allocation
  from atlas.work_allocations
  where organization_id=v_work.organization_id and work_item_id=v_work.id and allocation_role='responsible'
  order by allocated_at desc
  limit 1;

  update atlas.work_requirements r
  set state='satisfied',
      satisfied_at=coalesce(r.satisfied_at,v_completed_at),
      updated_at=now(),
      metadata=coalesce(r.metadata,'{}'::jsonb)||jsonb_build_object('satisfiedByCompanyWorkItemId',v_work.id)
  from atlas.work_requirement_links l
  where l.organization_id=v_work.organization_id
    and l.work_item_id=v_work.id
    and l.requirement_id=r.id
    and l.active
    and r.state='active';

  update atlas.work_time_contracts tc
  set contract_state='satisfied',updated_at=now(),
      metadata=coalesce(tc.metadata,'{}'::jsonb)||jsonb_build_object('satisfiedByCompanyWorkItemId',v_work.id)
  where tc.organization_id=v_work.organization_id and tc.work_item_id=v_work.id and tc.contract_state='active';

  update atlas.work_allocations wa
  set state='completed',completed_at=coalesce(wa.completed_at,v_completed_at),updated_at=now()
  where wa.organization_id=v_work.organization_id and wa.work_item_id=v_work.id and wa.state='active';

  update atlas.work_execution_adapters ea
  set state='completed',completed_at=coalesce(ea.completed_at,v_completed_at),updated_at=now(),
      metadata=coalesce(ea.metadata,'{}'::jsonb)||jsonb_build_object('completedByCompanyWork',true)
  where ea.organization_id=v_work.organization_id and ea.work_item_id=v_work.id and ea.state='active';

  for v_occurrence_id in
    select ea.planned_occurrence_id
    from atlas.work_execution_adapters ea
    where ea.organization_id=v_work.organization_id and ea.work_item_id=v_work.id and ea.planned_occurrence_id is not null
  loop
    update atlas.planned_work_occurrences pwo
    set state=case when pwo.state='cancelled' then pwo.state else 'completed' end,
        gate_satisfied_at=coalesce(pwo.gate_satisfied_at,v_completed_at),updated_at=now(),
        metadata=coalesce(pwo.metadata,'{}'::jsonb)||jsonb_build_object('completedByCompanyWork',true,'companyWorkItemId',v_work.id)
    where pwo.id=v_occurrence_id and pwo.state<>'cancelled';
  end loop;

  v_gate:=atlas.refresh_production_transplant_gate_v1(v_lot.id);

  v_required:=atlas.project_organization_ledger_event_internal_v1(
    v_work.organization_id,v_work.organization_unit_id,
    'production:bed-preparation-required:'||v_assignment.id::text,
    'production','bed_preparation_required',
    'production_bed_assignment:'||v_assignment.id::text||':bed_preparation_required',
    coalesce(v_assignment.created_at,v_completed_at),v_work.title,
    v_assignment.quantity_assigned::text||' bed-feet required preparation before transplant.',
    'established','closed',
    jsonb_build_object(
      'productionLotId',v_lot.id,'productionBedAssignmentId',v_assignment.id,
      'workRequirementId',v_req_id,'workItemId',v_work.id,
      'requiredBedFeet',v_assignment.quantity_assigned,'workState','completed',
      'responsibilityState','completed','responsibleAllocationId',v_allocation.id,
      'assigneeOrganizationMembershipId',v_allocation.assignee_membership_id,
      'productionGate',v_gate
    ),
    jsonb_build_object(
      'sourceTable','atlas.production_bed_assignments','sourceId',v_assignment.id,
      'sourceDomainAuthority','production','companyWorkCompletionAccepted',true,
      'projectedBy','reconcile_production_bed_preparation_company_work_completion_v1'
    ),
    jsonb_build_object('productionLotId',v_lot.id,'companyWorkItemId',v_work.id,'companyWorkRequirementId',v_req_id),
    v_completed_at
  );
  v_required_ledger_id:=nullif(v_required->>'entryId','')::uuid;

  v_completed:=atlas.project_organization_ledger_event_internal_v1(
    v_work.organization_id,v_work.organization_unit_id,
    'production:bed-preparation-completed:'||v_assignment.id::text,
    'production','bed_preparation_completed',
    'company_work_item:'||v_work.id::text||':completed',
    v_completed_at,v_work.title,
    'Company Work completion was accepted by Production as prepared destination capacity.',
    'established','closed',
    jsonb_build_object(
      'productionLotId',v_lot.id,'productionBedAssignmentId',v_assignment.id,
      'workRequirementId',v_req_id,'workItemId',v_work.id,
      'requiredBedFeet',v_assignment.quantity_assigned,'completedAt',v_completed_at,
      'responsibleAllocationId',v_allocation.id,'assigneeOrganizationMembershipId',v_allocation.assignee_membership_id,
      'productionGate',v_gate
    ),
    jsonb_build_object(
      'sourceDomainAuthority','production','acceptedEvidenceDomain','company_work',
      'projectedBy','reconcile_production_bed_preparation_company_work_completion_v1'
    ),
    jsonb_build_object('productionLotId',v_lot.id,'companyWorkItemId',v_work.id),
    v_completed_at
  );
  v_completed_ledger_id:=nullif(v_completed->>'entryId','')::uuid;

  if v_completed_ledger_id is not null then
    perform atlas.link_organization_ledger_subject_internal_v1(v_completed_ledger_id,'production','production_bed_assignment',v_assignment.id::text,'source',jsonb_build_object('sourceDomainAuthority','production'),'{}'::jsonb);
    perform atlas.link_organization_ledger_subject_internal_v1(v_completed_ledger_id,'production','production_lot',v_lot.id::text,'about',jsonb_build_object('sourceDomainAuthority','production'),'{}'::jsonb);
    perform atlas.link_organization_ledger_subject_internal_v1(v_completed_ledger_id,'work','work_item',v_work.id::text,'completed_work',jsonb_build_object('authority','company_work'),'{}'::jsonb);
    if v_allocation.id is not null then
      perform atlas.link_organization_ledger_subject_internal_v1(v_completed_ledger_id,'responsibility','work_allocation',v_allocation.id::text,'carried_by',jsonb_build_object('authority','company_work'),'{}'::jsonb);
    end if;
  end if;

  return jsonb_build_object(
    'state','reconciled','workItemId',v_work.id,'productionLotId',v_lot.id,
    'productionBedAssignmentId',v_assignment.id,'requiredLedgerEntryId',v_required_ledger_id,
    'completionLedgerEntryId',v_completed_ledger_id,'productionGate',v_gate
  );
end;
$function$;

revoke all on function atlas.reconcile_production_bed_preparation_company_work_completion_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.reconcile_production_bed_preparation_company_work_completion_v1(uuid) to postgres,service_role;
