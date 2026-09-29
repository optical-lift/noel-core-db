begin;

-- Production bed-preparation truth belongs to Production.
-- Company Work completion and accepted execution results are admissible evidence,
-- but neither is itself prepared-capacity truth.

create table if not exists atlas.production_bed_preparation_actuals (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references atlas.farms(id),
  production_bed_assignment_id uuid not null references atlas.production_bed_assignments(id),
  work_item_id uuid references atlas.work_items(id),
  execution_result_id uuid references atlas.work_execution_results(id),
  work_result_acceptance_id uuid references atlas.work_result_acceptances(id),
  actual_state text not null check (actual_state in ('prepared','partially_prepared','not_prepared')),
  prepared_bed_feet numeric not null check (prepared_bed_feet >= 0),
  unit text not null default 'bed_feet' check (unit='bed_feet'),
  effective_at timestamptz not null,
  evidence jsonb not null default '{}'::jsonb,
  source_kind text not null,
  idempotency_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (farm_id,idempotency_key)
);

create unique index if not exists production_bed_preparation_actuals_execution_result_uidx
  on atlas.production_bed_preparation_actuals(execution_result_id)
  where execution_result_id is not null;

create index if not exists production_bed_preparation_actuals_assignment_asof_idx
  on atlas.production_bed_preparation_actuals(
    production_bed_assignment_id,effective_at desc,created_at desc,id desc
  );

alter table atlas.production_bed_preparation_actuals enable row level security;
revoke all on table atlas.production_bed_preparation_actuals from public,anon,authenticated;

create or replace function atlas.guard_production_bed_preparation_actual_immutability_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $function$
begin
  raise exception 'Production bed-preparation Actual history is append-only.' using errcode='55000';
end;
$function$;

drop trigger if exists guard_production_bed_preparation_actual_immutability_v1
  on atlas.production_bed_preparation_actuals;
create trigger guard_production_bed_preparation_actual_immutability_v1
before update or delete on atlas.production_bed_preparation_actuals
for each row execute function atlas.guard_production_bed_preparation_actual_immutability_v1();

create or replace function atlas.production_bed_preparation_actual_v1(
  p_assignment_id uuid,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_assignment atlas.production_bed_assignments%rowtype;
  v_actual atlas.production_bed_preparation_actuals%rowtype;
begin
  if p_assignment_id is null then
    raise exception 'Production bed assignment is required.' using errcode='22023';
  end if;
  if p_as_of is null then
    raise exception 'as_of is required.' using errcode='22023';
  end if;

  select * into v_assignment
  from atlas.production_bed_assignments
  where id=p_assignment_id;
  if v_assignment.id is null then
    raise exception 'Production bed assignment was not found.' using errcode='P0002';
  end if;

  select * into v_actual
  from atlas.production_bed_preparation_actuals a
  where a.production_bed_assignment_id=v_assignment.id
    and a.effective_at<=p_as_of
    and a.created_at<=p_as_of
  order by a.effective_at desc,a.created_at desc,a.id desc
  limit 1;

  if v_actual.id is null then
    return jsonb_build_object(
      'contractVersion','production_bed_preparation_actual_v1',
      'productionBedAssignmentId',v_assignment.id,
      'asOf',p_as_of,
      'established',false,
      'actualState','unknown',
      'preparedBedFeet',0,
      'requiredBedFeet',v_assignment.quantity_assigned,
      'truthBoundary',jsonb_build_object(
        'companyWorkCompletionIsNotSourceTruth',true,
        'acceptedExecutionResultIsEvidenceNotSourceTruth',true,
        'productionOwnsPreparedCapacityTruth',true
      )
    );
  end if;

  return jsonb_build_object(
    'contractVersion','production_bed_preparation_actual_v1',
    'productionBedAssignmentId',v_assignment.id,
    'asOf',p_as_of,
    'established',true,
    'actualId',v_actual.id,
    'actualState',v_actual.actual_state,
    'preparedBedFeet',v_actual.prepared_bed_feet,
    'requiredBedFeet',v_assignment.quantity_assigned,
    'effectiveAt',v_actual.effective_at,
    'createdAt',v_actual.created_at,
    'workItemId',v_actual.work_item_id,
    'executionResultId',v_actual.execution_result_id,
    'workResultAcceptanceId',v_actual.work_result_acceptance_id,
    'sourceKind',v_actual.source_kind,
    'evidence',v_actual.evidence,
    'truthBoundary',jsonb_build_object(
      'companyWorkCompletionIsNotSourceTruth',true,
      'acceptedExecutionResultIsEvidenceNotSourceTruth',true,
      'productionOwnsPreparedCapacityTruth',true
    )
  );
end;
$function$;

revoke all on function atlas.production_bed_preparation_actual_v1(uuid,timestamptz)
  from public,anon,authenticated;
grant execute on function atlas.production_bed_preparation_actual_v1(uuid,timestamptz)
  to postgres,service_role;

create or replace function atlas.adjudicate_production_bed_preparation_result_v1(
  p_execution_result_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_result atlas.work_execution_results%rowtype;
  v_acceptance atlas.work_result_acceptances%rowtype;
  v_work atlas.work_items%rowtype;
  v_assignment atlas.production_bed_assignments%rowtype;
  v_existing atlas.production_bed_preparation_actuals%rowtype;
  v_actual atlas.production_bed_preparation_actuals%rowtype;
  v_ledger jsonb;
  v_ledger_id uuid;
  v_gate jsonb;
begin
  if p_execution_result_id is null then
    raise exception 'Execution result is required.' using errcode='22023';
  end if;

  select * into v_result
  from atlas.work_execution_results
  where id=p_execution_result_id;
  if v_result.id is null then
    raise exception 'Execution result was not found.' using errcode='P0002';
  end if;

  select * into v_acceptance
  from atlas.work_result_acceptances
  where execution_result_id=v_result.id
    and decision='accepted'
  order by accepted_at desc,id desc
  limit 1;
  if v_acceptance.id is null then
    return jsonb_build_object(
      'state','result_not_accepted',
      'executionResultId',v_result.id,
      'productionTruthEstablished',false
    );
  end if;

  select * into v_work
  from atlas.work_items
  where id=v_result.work_item_id
    and organization_id=v_result.organization_id;
  if v_work.id is null then
    raise exception 'Company Work linked to execution result was not found.' using errcode='23514';
  end if;
  if v_result.result_kind<>'completed'
     or v_result.result_contract_key<>'production_bed_preparation_v1'
     or v_work.result_contract_key<>'production_bed_preparation_v1'
     or v_work.source_object_type<>'production_bed_assignment' then
    return jsonb_build_object(
      'state','unsupported_result',
      'executionResultId',v_result.id,
      'workItemId',v_work.id,
      'productionTruthEstablished',false
    );
  end if;

  select * into v_assignment
  from atlas.production_bed_assignments
  where id=v_work.source_object_id;
  if v_assignment.id is null then
    raise exception 'Production bed assignment linked to Company Work was not found.' using errcode='23514';
  end if;
  if v_assignment.assignment_status<>'assigned' then
    return jsonb_build_object(
      'state','source_assignment_not_active',
      'executionResultId',v_result.id,
      'workItemId',v_work.id,
      'productionBedAssignmentId',v_assignment.id,
      'productionTruthEstablished',false
    );
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('atlas.production.bed_preparation.actual:'||v_assignment.id::text,0)
  );

  select * into v_existing
  from atlas.production_bed_preparation_actuals
  where execution_result_id=v_result.id
  limit 1;
  if v_existing.id is not null then
    v_gate:=atlas.refresh_production_transplant_gate_v1(v_assignment.production_lot_id);
    return jsonb_build_object(
      'state','deduplicated',
      'actualId',v_existing.id,
      'actualState',v_existing.actual_state,
      'preparedBedFeet',v_existing.prepared_bed_feet,
      'productionBedAssignmentId',v_assignment.id,
      'workItemId',v_work.id,
      'executionResultId',v_result.id,
      'workResultAcceptanceId',v_acceptance.id,
      'productionTruthEstablished',true,
      'productionGate',v_gate
    );
  end if;

  -- Current Production contract: an accepted completed worker attestation is
  -- sufficient evidence for Production to establish this assignment as prepared.
  -- This is a Production adjudication rule, not a Company Work completion rule.
  insert into atlas.production_bed_preparation_actuals(
    farm_id,production_bed_assignment_id,work_item_id,execution_result_id,
    work_result_acceptance_id,actual_state,prepared_bed_feet,unit,effective_at,
    evidence,source_kind,idempotency_key,metadata
  ) values(
    v_assignment.farm_id,v_assignment.id,v_work.id,v_result.id,
    v_acceptance.id,'prepared',v_assignment.quantity_assigned,'bed_feet',v_result.reported_at,
    jsonb_build_object(
      'acceptedExecutionResultId',v_result.id,
      'workResultAcceptanceId',v_acceptance.id,
      'resultContractKey',v_result.result_contract_key,
      'acceptanceKind',v_acceptance.acceptance_kind,
      'acceptedByDomain',v_acceptance.accepted_by_domain
    ),
    'company_work_result',
    'company-work-result:'||v_result.id::text,
    jsonb_build_object(
      'adjudicator','adjudicate_production_bed_preparation_result_v1',
      'productionOwnsDownstreamTruth',true,
      'workCompletionIsEvidenceOnly',true,
      'workerAttestationIsSufficientUnderCurrentProductionRule',true
    )
  ) returning * into v_actual;

  v_ledger:=atlas.project_organization_ledger_event_internal_v1(
    v_work.organization_id,v_work.organization_unit_id,
    'production:bed-preparation-actual:'||v_assignment.id::text,
    'production','bed_preparation_actual',
    'production_bed_assignment:'||v_assignment.id::text||':bed_preparation_actual',
    v_actual.effective_at,v_work.title,
    v_actual.prepared_bed_feet::text||' bed-feet established prepared by Production.',
    'established','closed',
    jsonb_build_object(
      'productionLotId',v_assignment.production_lot_id,
      'productionBedAssignmentId',v_assignment.id,
      'destinationObjectId',v_assignment.object_id,
      'workItemId',v_work.id,
      'executionResultId',v_result.id,
      'workResultAcceptanceId',v_acceptance.id,
      'productionBedPreparationActualId',v_actual.id,
      'actualState',v_actual.actual_state,
      'preparedBedFeet',v_actual.prepared_bed_feet,
      'requiredBedFeet',v_assignment.quantity_assigned
    ),
    jsonb_build_object(
      'sourceTable','atlas.production_bed_preparation_actuals',
      'sourceId',v_actual.id,
      'sourceDomainAuthority','production',
      'projectedBy','adjudicate_production_bed_preparation_result_v1'
    ),
    jsonb_build_object(
      'companyWorkItemId',v_work.id,
      'executionResultId',v_result.id,
      'proposedEffectConsumed',true
    ),
    v_actual.created_at
  );
  v_ledger_id:=nullif(v_ledger->>'entryId','')::uuid;

  if v_ledger_id is not null then
    perform atlas.link_organization_ledger_subject_internal_v1(
      v_ledger_id,'production','production_bed_assignment',v_assignment.id::text,'source',
      jsonb_build_object('sourceDomainAuthority','production'),'{}'::jsonb
    );
    perform atlas.link_organization_ledger_subject_internal_v1(
      v_ledger_id,'production','production_lot',v_assignment.production_lot_id::text,'about',
      jsonb_build_object('sourceDomainAuthority','production'),'{}'::jsonb
    );
    perform atlas.link_organization_ledger_subject_internal_v1(
      v_ledger_id,'work','work_item',v_work.id::text,'evidence_from',
      jsonb_build_object('authority','company_work'),'{}'::jsonb
    );
  end if;

  v_gate:=atlas.refresh_production_transplant_gate_v1(v_assignment.production_lot_id);

  return jsonb_build_object(
    'state','production_actual_established',
    'actualId',v_actual.id,
    'actualState',v_actual.actual_state,
    'preparedBedFeet',v_actual.prepared_bed_feet,
    'productionBedAssignmentId',v_assignment.id,
    'workItemId',v_work.id,
    'executionResultId',v_result.id,
    'workResultAcceptanceId',v_acceptance.id,
    'ledgerEntryId',v_ledger_id,
    'productionTruthEstablished',true,
    'productionGate',v_gate
  );
end;
$function$;

revoke all on function atlas.adjudicate_production_bed_preparation_result_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.adjudicate_production_bed_preparation_result_v1(uuid)
  to postgres,service_role;

-- A ledger designation may close only from Production-owned source truth.
-- Company Work terminality can no longer close the Production requirement directly.
create or replace function atlas.guard_completed_company_work_ledger_designation_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_assignment_id uuid;
  v_actual jsonb;
begin
  if new.source_domain='production' and new.semantic_type='bed_preparation_required' then
    begin
      v_assignment_id:=nullif(new.payload->>'productionBedAssignmentId','')::uuid;
    exception when others then
      v_assignment_id:=null;
    end;

    if v_assignment_id is not null then
      v_actual:=atlas.production_bed_preparation_actual_v1(v_assignment_id,now());
      if coalesce((v_actual->>'established')::boolean,false)
         and coalesce(v_actual->>'actualState','')='prepared'
         and coalesce((v_actual->>'preparedBedFeet')::numeric,0)
             >= coalesce((v_actual->>'requiredBedFeet')::numeric,0) then
        new.designation_status:='closed';
        new.payload:=coalesce(new.payload,'{}'::jsonb)||jsonb_build_object(
          'sourceActualState','prepared',
          'sourceActualId',v_actual->>'actualId',
          'sourceActualAuthority','production_bed_preparation_actuals'
        );
      else
        new.designation_status:='unresolved';
        new.payload:=coalesce(new.payload,'{}'::jsonb)||jsonb_build_object(
          'sourceActualState',coalesce(v_actual->>'actualState','unknown'),
          'sourceActualAuthority','production_bed_preparation_actuals',
          'companyWorkCompletionDoesNotCloseSourceRequirement',true
        );
      end if;
    end if;
  end if;
  return new;
end;
$function$;

-- Production transplant readiness now reads Production-owned Actuals, not Work state.
create or replace function atlas.refresh_production_transplant_gate_v1(p_production_lot_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_lot atlas.production_lots%rowtype;
  v_batch atlas.production_tray_batches%rowtype;
  v_obs atlas.production_readiness_observations%rowtype;
  v_req atlas.production_capacity_requirements%rowtype;
  v_gate atlas.production_transplant_gates%rowtype;
  v_assigned numeric:=0;
  v_prepared numeric:=0;
  v_status text;
  v_blocker text;
  v_due date;
  v_next jsonb;
  v_occurrence_id uuid;
  v_task_id uuid;
  v_relation jsonb;
begin
  select * into v_lot from atlas.production_lots where id=p_production_lot_id for update;
  if v_lot.id is null then raise exception 'Production lot was not found' using errcode='P0002'; end if;

  select * into v_batch
  from atlas.production_tray_batches
  where production_lot_id=v_lot.id and status in ('seedling_care','hardening','transplant_ready')
  order by batch_number desc limit 1;

  select * into v_obs
  from atlas.production_readiness_observations
  where production_lot_id=v_lot.id and observation_outcome='ready'
  order by observed_date desc,created_at desc limit 1;

  if v_batch.id is null or v_obs.id is null then
    return jsonb_build_object('productionLotId',v_lot.id,'gateStatus','waiting_seedlings','changed',false);
  end if;

  select * into v_req from atlas.production_capacity_requirements
  where production_lot_id=v_lot.id and capacity_kind='bed_feet' limit 1;

  select coalesce(sum(quantity_assigned),0) into v_assigned
  from atlas.production_bed_assignments
  where production_lot_id=v_lot.id and assignment_status='assigned';

  -- Source truth: take the latest Production Actual for each active assignment.
  -- effective_at and created_at both participate so later-recorded backdating does
  -- not rewrite what Production could have established at an earlier as_of.
  select coalesce(sum(least(a.quantity_assigned,coalesce(x.prepared_bed_feet,0))),0)
  into v_prepared
  from atlas.production_bed_assignments a
  left join lateral (
    select pa.prepared_bed_feet
    from atlas.production_bed_preparation_actuals pa
    where pa.production_bed_assignment_id=a.id
      and pa.effective_at<=now()
      and pa.created_at<=now()
    order by pa.effective_at desc,pa.created_at desc,pa.id desc
    limit 1
  ) x on true
  where a.production_lot_id=v_lot.id
    and a.assignment_status='assigned';

  if v_req.id is null or v_req.calculation_status not in ('calculated','confirmed') or v_req.quantity_needed is null then
    v_status:='waiting_bed_math'; v_blocker:='Bed demand is not calculated from the counted surviving seedlings.';
  elsif v_assigned<v_req.quantity_needed then
    v_status:='waiting_bed_assignment'; v_blocker:=(v_req.quantity_needed-v_assigned)::text||' additional bed-feet must be assigned.';
  elsif v_prepared<v_req.quantity_needed then
    v_status:='waiting_bed_preparation'; v_blocker:=(v_req.quantity_needed-v_prepared)::text||' assigned bed-feet still need Production-established preparation.';
  else
    v_status:='ready'; v_blocker:=null;
  end if;

  insert into atlas.production_transplant_gates(
    farm_id,production_lot_id,tray_batch_id,readiness_observation_id,bed_requirement_id,
    required_bed_feet,assigned_bed_feet,prepared_bed_feet,gate_status,blocker_text,ready_at,refresh_version,metadata
  ) values(
    v_lot.farm_id,v_lot.id,v_batch.id,v_obs.id,v_req.id,v_req.quantity_needed,v_assigned,v_prepared,v_status,v_blocker,
    case when v_status='ready' then now() end,1,
    jsonb_build_object(
      'surviving_seedlings',v_obs.surviving_seedlings,
      'preparedBedFeetAuthority','production_bed_preparation_actuals',
      'companyWorkCompletionIsEvidenceOnly',true
    )
  )
  on conflict(production_lot_id,tray_batch_id) do update set
    readiness_observation_id=excluded.readiness_observation_id,
    bed_requirement_id=excluded.bed_requirement_id,
    required_bed_feet=excluded.required_bed_feet,
    assigned_bed_feet=excluded.assigned_bed_feet,
    prepared_bed_feet=excluded.prepared_bed_feet,
    gate_status=case when atlas.production_transplant_gates.gate_status='transplanted' then 'transplanted' else excluded.gate_status end,
    blocker_text=case when atlas.production_transplant_gates.gate_status='transplanted' then null else excluded.blocker_text end,
    ready_at=case when atlas.production_transplant_gates.gate_status='transplanted' then atlas.production_transplant_gates.ready_at when excluded.gate_status='ready' then coalesce(atlas.production_transplant_gates.ready_at,now()) else null end,
    refresh_version=atlas.production_transplant_gates.refresh_version+1,
    metadata=atlas.production_transplant_gates.metadata||excluded.metadata,
    updated_at=now()
  returning * into v_gate;

  if v_gate.gate_status='transplanted' then
    return jsonb_build_object('productionLotId',v_lot.id,'transplantGateId',v_gate.id,'transplantTaskId',v_gate.transplant_task_id,'gateStatus','transplanted');
  end if;

  v_due:=greatest(coalesce(v_lot.expected_transplant_start,v_obs.observed_date),v_obs.observed_date);
  begin v_occurrence_id:=nullif(v_gate.metadata->>'transplant_occurrence_id','')::uuid; exception when others then v_occurrence_id:=null; end;

  if v_status='ready' then
    select coalesce(jsonb_agg(jsonb_build_object('object_id',a.object_id,'role','target') order by a.object_id),'[]'::jsonb)
    into v_relation
    from atlas.production_bed_assignments a
    where a.production_lot_id=v_lot.id and a.assignment_status='assigned';

    v_next:=atlas.author_production_work_occurrence_v1(
      v_lot.farm_id,'transplant','production:transplant:'||v_gate.id::text,
      'Transplant — '||v_lot.lot_label,v_due,v_due,
      'production_transplant_gate',v_gate.id,'production_transplant','transplant','heavy','high','assigned_worker',
      (select assigned_membership_id from atlas.tasks where id=v_obs.task_id),
      (select assigned_user_id from atlas.tasks where id=v_obs.task_id),
      (select organization_id from atlas.tasks where id=v_obs.task_id),
      'Record the exact number of surviving plants placed in each assigned bed.',
      jsonb_build_object(
        'task_key','production_transplant_'||v_gate.id::text,'task_style','production_transplant',
        'production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,
        'production_transplant_gate_id',v_gate.id,'crop_cycle_id',v_batch.crop_cycle_id,
        'surviving_seedlings',v_obs.surviving_seedlings,'required_bed_feet',v_req.quantity_needed,
        'display_action','Transplant','display_subject',v_lot.lot_label,
        'display_detail',coalesce(v_req.quantity_needed::text,'?')||' bed-ft · '||v_obs.surviving_seedlings::text||' seedlings',
        'collection_zone','Assigned beds','relationship_kind','production_transplant'
      ),
      jsonb_build_object(
        'task_objects',coalesce(v_relation,'[]'::jsonb),
        'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'role','affects','confidence','confirmed','source','production_stage_engine','metadata',jsonb_build_object('transplant_gate_id',v_gate.id))),
        'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','transplant','source','production_stage_engine','metadata',jsonb_build_object('transplant_gate_id',v_gate.id,'tray_batch_id',v_batch.id))),
        'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()
      ),'process_continuation','dependency',coalesce(v_lot.expected_transplant_end,v_due+5),
      jsonb_build_object('kind','biological_pressure','effect','Ready seedlings are waiting for their governed transplant window.'),false
    );
    v_occurrence_id:=nullif(v_next->>'occurrenceId','')::uuid;
    v_task_id:=nullif(v_next->>'taskId','')::uuid;
    update atlas.production_transplant_gates
    set transplant_task_id=coalesce(v_task_id,transplant_task_id),
        metadata=metadata||jsonb_build_object('transplant_occurrence_id',v_occurrence_id,'transplant_due_date',v_due),updated_at=now()
    where id=v_gate.id;
  else
    if v_occurrence_id is not null then
      update atlas.planned_work_occurrences
      set state=case when state in ('completed','cancelled') then state else 'cancelled' end,
          metadata=metadata||jsonb_build_object('cancelled_by','production_transplant_gate','cancelled_at',now(),'cancelled_gate_status',v_status,'cancelled_reason',v_blocker),updated_at=now()
      where id=v_occurrence_id and state not in ('completed');
      select released_task_id into v_task_id from atlas.planned_work_occurrences where id=v_occurrence_id;
      if v_task_id is not null and exists(select 1 from atlas.tasks where id=v_task_id and status='open') then
        perform atlas.record_task_transition_v1_internal(v_task_id,'blocked',left('production-gate-blocked:'||v_gate.id::text||':'||v_gate.refresh_version::text,160),null,v_blocker,v_blocker,'transplant','production_lot',jsonb_build_object('production_lot_id',v_lot.id,'transplant_gate_id',v_gate.id,'gate_status',v_status),null);
      end if;
    end if;
  end if;

  return jsonb_build_object(
    'productionLotId',v_lot.id,'transplantGateId',v_gate.id,'transplantOccurrenceId',v_occurrence_id,
    'transplantTaskId',(select transplant_task_id from atlas.production_transplant_gates where id=v_gate.id),
    'gateStatus',v_status,'requiredBedFeet',v_req.quantity_needed,'assignedBedFeet',v_assigned,'preparedBedFeet',v_prepared,'blocker',v_blocker,
    'preparedBedFeetAuthority','production_bed_preparation_actuals'
  );
end;
$function$;

-- Completing Company Work closes its operational carrier and offers evidence to
-- Production. Production truth is established only through the source adjudicator.
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
  v_execution_result atlas.work_execution_results%rowtype;
  v_source jsonb;
  v_gate jsonb;
  v_required jsonb;
  v_evidence jsonb;
  v_required_ledger_id uuid;
  v_evidence_ledger_id uuid;
  v_occurrence_id uuid;
  v_completed_at timestamptz;
  v_source_established boolean:=false;
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

  -- These are Work-local terminal states. They do not establish the Production source state.
  update atlas.work_requirements r
  set state='satisfied',satisfied_at=coalesce(r.satisfied_at,v_completed_at),updated_at=now(),
      metadata=coalesce(r.metadata,'{}'::jsonb)||jsonb_build_object(
        'satisfiedByCompanyWorkItemId',v_work.id,
        'sourceDomainTruthStillRequiresProductionAdjudication',true
      )
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

  select r.* into v_execution_result
  from atlas.work_execution_results r
  join atlas.work_result_acceptances a
    on a.execution_result_id=r.id and a.decision='accepted'
  where r.organization_id=v_work.organization_id
    and r.work_item_id=v_work.id
    and r.result_kind='completed'
    and r.result_contract_key='production_bed_preparation_v1'
  order by a.accepted_at desc,r.reported_at desc,r.id desc
  limit 1;

  if v_execution_result.id is not null then
    v_source:=atlas.adjudicate_production_bed_preparation_result_v1(v_execution_result.id);
    v_source_established:=coalesce((v_source->>'productionTruthEstablished')::boolean,false);
  else
    v_source:=jsonb_build_object(
      'state','accepted_execution_result_missing',
      'productionTruthEstablished',false,
      'workItemId',v_work.id
    );
  end if;

  v_gate:=atlas.refresh_production_transplant_gate_v1(v_lot.id);

  v_required:=atlas.project_organization_ledger_event_internal_v1(
    v_work.organization_id,v_work.organization_unit_id,
    'production:bed-preparation-required:'||v_assignment.id::text,
    'production','bed_preparation_required',
    'production_bed_assignment:'||v_assignment.id::text||':bed_preparation_required',
    coalesce(v_assignment.created_at,v_completed_at),v_work.title,
    v_assignment.quantity_assigned::text||' bed-feet require Production-established preparation before transplant.',
    'established',case when v_source_established then 'closed' else 'unresolved' end,
    jsonb_build_object(
      'productionLotId',v_lot.id,'productionBedAssignmentId',v_assignment.id,
      'workRequirementId',v_req_id,'workItemId',v_work.id,
      'requiredBedFeet',v_assignment.quantity_assigned,'workState','completed',
      'responsibilityState','completed','responsibleAllocationId',v_allocation.id,
      'assigneeOrganizationMembershipId',v_allocation.assignee_membership_id,
      'sourceTruthState',case when v_source_established then 'established' else 'pending' end,
      'sourceAdjudication',v_source,
      'productionGate',v_gate
    ),
    jsonb_build_object(
      'sourceTable','atlas.production_bed_assignments','sourceId',v_assignment.id,
      'sourceDomainAuthority','production','companyWorkCompletionIsEvidenceOnly',true,
      'projectedBy','reconcile_production_bed_preparation_company_work_completion_v1'
    ),
    jsonb_build_object('productionLotId',v_lot.id,'companyWorkItemId',v_work.id,'companyWorkRequirementId',v_req_id),
    v_completed_at
  );
  v_required_ledger_id:=nullif(v_required->>'entryId','')::uuid;

  v_evidence:=atlas.project_organization_ledger_event_internal_v1(
    v_work.organization_id,v_work.organization_unit_id,
    'production:bed-preparation-work-result:'||v_assignment.id::text,
    'production','bed_preparation_work_result',
    'company_work_item:'||v_work.id::text||':accepted_result',
    v_completed_at,v_work.title,
    'Accepted Company Work result was offered to Production as bed-preparation evidence.',
    'established','closed',
    jsonb_build_object(
      'productionLotId',v_lot.id,'productionBedAssignmentId',v_assignment.id,
      'workRequirementId',v_req_id,'workItemId',v_work.id,
      'executionResultId',v_execution_result.id,
      'sourceAdjudication',v_source,
      'productionGate',v_gate
    ),
    jsonb_build_object(
      'sourceDomainAuthority','production','evidenceDomain','company_work',
      'companyWorkCompletionIsEvidenceOnly',true,
      'projectedBy','reconcile_production_bed_preparation_company_work_completion_v1'
    ),
    jsonb_build_object('productionLotId',v_lot.id,'companyWorkItemId',v_work.id),
    v_completed_at
  );
  v_evidence_ledger_id:=nullif(v_evidence->>'entryId','')::uuid;

  if v_evidence_ledger_id is not null then
    perform atlas.link_organization_ledger_subject_internal_v1(v_evidence_ledger_id,'production','production_bed_assignment',v_assignment.id::text,'source',jsonb_build_object('sourceDomainAuthority','production'),'{}'::jsonb);
    perform atlas.link_organization_ledger_subject_internal_v1(v_evidence_ledger_id,'production','production_lot',v_lot.id::text,'about',jsonb_build_object('sourceDomainAuthority','production'),'{}'::jsonb);
    perform atlas.link_organization_ledger_subject_internal_v1(v_evidence_ledger_id,'work','work_item',v_work.id::text,'evidence_from',jsonb_build_object('authority','company_work'),'{}'::jsonb);
  end if;

  return jsonb_build_object(
    'state',case when v_source_established then 'work_reconciled_source_established' else 'work_reconciled_source_pending' end,
    'workItemId',v_work.id,'productionLotId',v_lot.id,
    'productionBedAssignmentId',v_assignment.id,
    'executionResultId',v_execution_result.id,
    'requiredLedgerEntryId',v_required_ledger_id,
    'evidenceLedgerEntryId',v_evidence_ledger_id,
    'sourceAdjudication',v_source,
    'productionGate',v_gate
  );
end;
$function$;

revoke all on function atlas.reconcile_production_bed_preparation_company_work_completion_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.reconcile_production_bed_preparation_company_work_completion_v1(uuid)
  to postgres,service_role;

comment on table atlas.production_bed_preparation_actuals is
  'Append-only Production-owned bed-preparation Actual history. Company Work results are evidence; source-domain state is established here.';
comment on function atlas.production_bed_preparation_actual_v1(uuid,timestamptz) is
  'Resolves the latest Production-owned bed-preparation Actual as-of both effective and recorded time.';
comment on function atlas.adjudicate_production_bed_preparation_result_v1(uuid) is
  'Production-domain adjudicator: consumes an accepted exact Company Work execution result as evidence and, under the current Production contract, establishes a Production bed-preparation Actual.';
comment on function atlas.refresh_production_transplant_gate_v1(uuid) is
  'Refreshes transplant readiness from Production-owned source Actuals; Company Work completion alone never establishes prepared bed-feet.';
comment on function atlas.reconcile_production_bed_preparation_company_work_completion_v1(uuid) is
  'Closes Company Work-local execution state, offers accepted result evidence to Production, invokes the Production adjudicator when exact accepted evidence exists, and never treats Work terminality itself as source truth.';

commit;