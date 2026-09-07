create or replace function atlas.materialize_production_bed_preparation_company_work_v1(
  p_assignment_id uuid,
  p_as_of_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_assignment atlas.production_bed_assignments%rowtype;
  v_lot atlas.production_lots%rowtype;
  v_req_source atlas.production_capacity_requirements%rowtype;
  v_farm atlas.farms%rowtype;
  v_object atlas.growing_objects%rowtype;
  v_requirement atlas.work_requirements%rowtype;
  v_work atlas.work_items%rowtype;
  v_time atlas.work_time_contracts%rowtype;
  v_occurrence atlas.planned_work_occurrences%rowtype;
  v_adapter atlas.work_execution_adapters%rowtype;
  v_tz text;
  v_due_date date;
  v_earliest timestamptz;
  v_latest timestamptz;
  v_source_established_at timestamptz;
  v_work_key text;
  v_requirement_key text;
  v_active_allocations integer;
  v_ledger jsonb;
  v_ledger_id uuid;
begin
  select * into v_assignment
  from atlas.production_bed_assignments
  where id=p_assignment_id;

  if v_assignment.id is null then
    raise exception 'Production bed assignment not found.' using errcode='P0002';
  end if;

  if v_assignment.assignment_status<>'assigned' then
    return jsonb_build_object('state','assignment_not_active','assignmentId',p_assignment_id);
  end if;

  select * into v_lot
  from atlas.production_lots
  where id=v_assignment.production_lot_id;

  if v_lot.id is null or v_lot.lifecycle_status<>'active' then
    return jsonb_build_object('state','production_lot_not_active','assignmentId',p_assignment_id);
  end if;

  if v_assignment.requirement_id is not null then
    select * into v_req_source
    from atlas.production_capacity_requirements
    where id=v_assignment.requirement_id;
  end if;

  if v_req_source.id is null then
    select * into v_req_source
    from atlas.production_capacity_requirements
    where production_lot_id=v_lot.id
      and capacity_kind='bed_feet'
    order by created_at
    limit 1;
  end if;

  if v_req_source.id is null
     or v_req_source.calculation_status not in ('calculated','confirmed')
     or v_req_source.quantity_needed is null then
    return jsonb_build_object('state','capacity_not_resolved','assignmentId',p_assignment_id);
  end if;

  select * into v_farm
  from atlas.farms
  where id=v_assignment.farm_id;

  if v_farm.id is null
     or v_farm.organization_id is null
     or v_farm.organization_unit_id is null then
    raise exception 'Production source lacks Organization/Unit custody.' using errcode='23514';
  end if;

  if v_lot.farm_id<>v_farm.id or v_req_source.farm_id<>v_farm.id then
    raise exception 'Production source objects do not share farm custody.' using errcode='23514';
  end if;

  select * into v_object
  from atlas.growing_objects
  where id=v_assignment.object_id;

  if v_object.id is null or v_object.farm_id<>v_farm.id then
    raise exception 'Destination object custody mismatch.' using errcode='23514';
  end if;

  v_tz:=coalesce(nullif(v_farm.metadata->>'timezone',''),'America/Chicago');
  if not exists(select 1 from pg_timezone_names where name=v_tz) then
    v_tz:='America/Chicago';
  end if;

  v_due_date:=coalesce(
    v_req_source.preparation_due_date,
    v_assignment.planned_transplant_date,
    v_req_source.required_by_date,
    coalesce(p_as_of_date,(now() at time zone v_tz)::date)
  );
  v_source_established_at:=coalesce(v_assignment.created_at,v_req_source.created_at,now());
  v_latest:=(v_due_date+1)::timestamp at time zone v_tz;
  v_earliest:=least(v_source_established_at,v_latest);
  v_work_key:='production:bed-preparation:'||v_assignment.id::text;
  v_requirement_key:=v_work_key||':requirement';

  insert into atlas.work_requirements(
    organization_id,organization_unit_id,stable_key,requirement_kind,summary,
    source_object_type,source_object_id,state,established_at,requirement_began_at,
    earliest_relevant_at,latest_satisfactory_at,consequence_of_delay,jurisdiction_key,metadata
  ) values(
    v_farm.organization_id,v_farm.organization_unit_id,v_requirement_key,'operational',
    'Prepare '||v_object.label||' for '||v_lot.lot_label,
    'production_bed_assignment',v_assignment.id,'active',v_source_established_at,
    v_source_established_at,v_earliest,v_latest,
    jsonb_build_object(
      'kind','destination_preparation',
      'effect','The assigned destination must be prepared before transplant can proceed.'
    ),
    'operations.production',
    jsonb_build_object(
      'sourceDomain','production',
      'productionLotId',v_lot.id,
      'productionCapacityRequirementId',v_req_source.id,
      'productionBedAssignmentId',v_assignment.id,
      'destinationObjectId',v_object.id,
      'requiredBedFeet',v_assignment.quantity_assigned,
      'targetTransplantDate',v_assignment.planned_transplant_date,
      'preparationDueDate',v_due_date,
      'assigneeEncodedInWorkIdentity',false,
      'responsibilityAuthority','work_allocations'
    )
  )
  on conflict(organization_id,stable_key) where stable_key is not null
  do update set
    organization_unit_id=excluded.organization_unit_id,
    summary=excluded.summary,
    source_object_type=excluded.source_object_type,
    source_object_id=excluded.source_object_id,
    state=case when atlas.work_requirements.state='cancelled' then 'active' else atlas.work_requirements.state end,
    cancelled_at=case when atlas.work_requirements.state='cancelled' then null else atlas.work_requirements.cancelled_at end,
    earliest_relevant_at=excluded.earliest_relevant_at,
    latest_satisfactory_at=excluded.latest_satisfactory_at,
    consequence_of_delay=excluded.consequence_of_delay,
    jurisdiction_key=excluded.jurisdiction_key,
    metadata=atlas.work_requirements.metadata||excluded.metadata,
    updated_at=now()
  returning * into v_requirement;

  insert into atlas.work_items(
    organization_id,organization_unit_id,stable_key,title,instructions,work_state,
    operation_class,jurisdiction_key,source_object_type,source_object_id,result_contract_key,metadata
  ) values(
    v_farm.organization_id,v_farm.organization_unit_id,v_work_key,
    'Prepare '||v_object.label||' for '||v_lot.lot_label,
    'Weed, clear, prepare, and confirm water access for the assigned destination before transplant.',
    'open','bed_preparation','operations.production','production_bed_assignment',v_assignment.id,
    'production_bed_preparation_v1',
    jsonb_build_object(
      'sourceDomain','production',
      'productionLotId',v_lot.id,
      'productionCapacityRequirementId',v_req_source.id,
      'productionBedAssignmentId',v_assignment.id,
      'destinationObjectId',v_object.id,
      'requiredBedFeet',v_assignment.quantity_assigned,
      'targetTransplantDate',v_assignment.planned_transplant_date,
      'preparationDueDate',v_due_date,
      'legacyTaskRequiredForIdentity',false,
      'responsibilityAuthority','work_allocations',
      'executionCarrierAssignmentIsResponsibilityEvidence',false,
      'executionCarrierCanCompleteWork',true
    )
  )
  on conflict(organization_id,stable_key) where stable_key is not null
  do update set
    organization_unit_id=excluded.organization_unit_id,
    title=excluded.title,
    instructions=excluded.instructions,
    work_state=case when atlas.work_items.work_state='cancelled' then 'open' else atlas.work_items.work_state end,
    cancelled_at=case when atlas.work_items.work_state='cancelled' then null else atlas.work_items.cancelled_at end,
    operation_class=excluded.operation_class,
    jurisdiction_key=excluded.jurisdiction_key,
    source_object_type=excluded.source_object_type,
    source_object_id=excluded.source_object_id,
    result_contract_key=excluded.result_contract_key,
    metadata=atlas.work_items.metadata||excluded.metadata,
    updated_at=now()
  returning * into v_work;

  insert into atlas.work_requirement_links(
    organization_id,requirement_id,work_item_id,link_role,active,metadata
  ) values(
    v_farm.organization_id,v_requirement.id,v_work.id,'resolves',true,
    jsonb_build_object('source','production_bed_preparation_company_work_v1')
  )
  on conflict(requirement_id,work_item_id,link_role)
  do update set
    active=true,
    metadata=atlas.work_requirement_links.metadata||excluded.metadata;

  if v_work.work_state='open' then
    select * into v_time
    from atlas.work_time_contracts
    where organization_id=v_farm.organization_id
      and work_item_id=v_work.id
      and contract_state='active'
    order by created_at desc
    limit 1;

    if v_time.id is null then
      insert into atlas.work_time_contracts(
        organization_id,work_item_id,contract_state,earliest_lawful_at,preferred_end_at,
        latest_lawful_at,hard_finish_at,movement_policy,consequence_of_delay,
        source_kind,source_id,source_confidence,metadata
      ) values(
        v_farm.organization_id,v_work.id,'active',v_earliest,v_latest,v_latest,v_latest,'bounded',
        jsonb_build_object('kind','destination_preparation'),
        'production_bed_assignment',v_assignment.id,1,
        jsonb_build_object(
          'sourceDomain','production',
          'preparationDueDate',v_due_date,
          'targetTransplantDate',v_assignment.planned_transplant_date,
          'timezone',v_tz,
          'deadlineNotSilentlyMovedWhenOverdue',true
        )
      ) returning * into v_time;
    else
      update atlas.work_time_contracts
      set earliest_lawful_at=v_earliest,
          preferred_end_at=v_latest,
          latest_lawful_at=v_latest,
          hard_finish_at=v_latest,
          movement_policy='bounded',
          consequence_of_delay=jsonb_build_object('kind','destination_preparation'),
          source_kind='production_bed_assignment',
          source_id=v_assignment.id,
          source_confidence=1,
          metadata=metadata||jsonb_build_object(
            'sourceDomain','production',
            'preparationDueDate',v_due_date,
            'targetTransplantDate',v_assignment.planned_transplant_date,
            'timezone',v_tz,
            'deadlineNotSilentlyMovedWhenOverdue',true
          ),
          updated_at=now()
      where id=v_time.id
      returning * into v_time;
    end if;
  end if;

  select * into v_occurrence
  from atlas.planned_work_occurrences
  where farm_id=v_farm.id
    and occurrence_key=v_work_key
  order by created_at
  limit 1;

  if v_occurrence.id is not null then
    select * into v_adapter
    from atlas.work_execution_adapters
    where planned_occurrence_id=v_occurrence.id
    limit 1;

    if v_adapter.id is null then
      insert into atlas.work_execution_adapters(
        organization_id,organization_unit_id,work_item_id,adapter_kind,
        planned_occurrence_id,task_id,state,metadata
      ) values(
        v_farm.organization_id,v_farm.organization_unit_id,v_work.id,
        'legacy_production_planned_occurrence',v_occurrence.id,v_occurrence.released_task_id,
        case when v_work.work_state='completed' then 'completed' else 'active' end,
        jsonb_build_object(
          'transitional',true,
          'carrierCreatesWork',false,
          'carrierAssignmentIsResponsibilityEvidence',false,
          'responsibilityAuthority','work_allocations',
          'productionBedAssignmentId',v_assignment.id
        )
      ) returning * into v_adapter;
    elsif v_adapter.work_item_id<>v_work.id then
      raise exception 'Legacy Production occurrence is already bound to different Company Work.' using errcode='23514';
    else
      update atlas.work_execution_adapters
      set organization_id=v_farm.organization_id,
          organization_unit_id=v_farm.organization_unit_id,
          adapter_kind='legacy_production_planned_occurrence',
          task_id=coalesce(v_occurrence.released_task_id,task_id),
          state=case when v_work.work_state='completed' then 'completed' else 'active' end,
          completed_at=case when v_work.work_state='completed' then coalesce(completed_at,now()) else null end,
          retired_at=null,
          metadata=metadata||jsonb_build_object(
            'transitional',true,
            'carrierCreatesWork',false,
            'carrierAssignmentIsResponsibilityEvidence',false,
            'responsibilityAuthority','work_allocations',
            'productionBedAssignmentId',v_assignment.id
          ),
          updated_at=now()
      where id=v_adapter.id
      returning * into v_adapter;
    end if;
  end if;

  select count(*) into v_active_allocations
  from atlas.work_allocations
  where organization_id=v_farm.organization_id
    and work_item_id=v_work.id
    and state='active'
    and allocation_role='responsible';

  v_ledger:=atlas.project_organization_ledger_event_internal_v1(
    v_farm.organization_id,
    v_farm.organization_unit_id,
    'production:bed-preparation-required:'||v_assignment.id::text,
    'production',
    'bed_preparation_required',
    'production_bed_assignment:'||v_assignment.id::text||':bed_preparation_required',
    v_source_established_at,
    'Prepare '||v_object.label||' for '||v_lot.lot_label,
    v_assignment.quantity_assigned::text||' bed-feet require preparation before transplant.',
    'established',
    case when v_active_allocations=0 then 'unresolved' else 'designated' end,
    jsonb_build_object(
      'productionLotId',v_lot.id,
      'productionCapacityRequirementId',v_req_source.id,
      'productionBedAssignmentId',v_assignment.id,
      'destinationObjectId',v_object.id,
      'workRequirementId',v_requirement.id,
      'workItemId',v_work.id,
      'timeContractId',v_time.id,
      'requiredBedFeet',v_assignment.quantity_assigned,
      'preparationDueDate',v_due_date,
      'targetTransplantDate',v_assignment.planned_transplant_date,
      'responsibilityState',case when v_active_allocations=0 then 'unassigned' else 'assigned' end,
      'activeResponsibleAllocations',v_active_allocations
    ),
    jsonb_build_object(
      'sourceTable','atlas.production_bed_assignments',
      'sourceId',v_assignment.id,
      'sourceDomainAuthority','production',
      'projectedBy','materialize_production_bed_preparation_company_work_v1'
    ),
    jsonb_build_object(
      'productionLotId',v_lot.id,
      'companyWorkItemId',v_work.id,
      'companyWorkRequirementId',v_requirement.id
    ),
    now()
  );

  v_ledger_id:=nullif(v_ledger->>'entryId','')::uuid;
  if v_ledger_id is not null then
    perform atlas.link_organization_ledger_subject_internal_v1(
      v_ledger_id,'production','production_bed_assignment',v_assignment.id::text,'source',
      jsonb_build_object('sourceDomainAuthority','production'),'{}'::jsonb
    );
    perform atlas.link_organization_ledger_subject_internal_v1(
      v_ledger_id,'production','production_lot',v_lot.id::text,'about',
      jsonb_build_object('sourceDomainAuthority','production'),'{}'::jsonb
    );
    perform atlas.link_organization_ledger_subject_internal_v1(
      v_ledger_id,'production','growing_object',v_object.id::text,'destination',
      jsonb_build_object('sourceDomainAuthority','production'),'{}'::jsonb
    );
    perform atlas.link_organization_ledger_subject_internal_v1(
      v_ledger_id,'work','work_requirement',v_requirement.id::text,'requires',
      jsonb_build_object('authority','company_work'),'{}'::jsonb
    );
    perform atlas.link_organization_ledger_subject_internal_v1(
      v_ledger_id,'work','work_item',v_work.id::text,'resolved_by',
      jsonb_build_object('authority','company_work'),'{}'::jsonb
    );
  end if;

  return jsonb_build_object(
    'state','materialized',
    'organizationId',v_farm.organization_id,
    'organizationUnitId',v_farm.organization_unit_id,
    'requirementId',v_requirement.id,
    'workItemId',v_work.id,
    'timeContractId',v_time.id,
    'adapterId',v_adapter.id,
    'plannedOccurrenceId',v_occurrence.id,
    'ledgerEntryId',v_ledger_id,
    'ledgerState',v_ledger->>'state',
    'responsibilityState',case when v_active_allocations=0 then 'unassigned' else 'assigned' end,
    'activeResponsibleAllocations',v_active_allocations,
    'sourceAssignmentId',v_assignment.id
  );
end;
$function$;

revoke all on function atlas.materialize_production_bed_preparation_company_work_v1(uuid,date)
  from public,anon,authenticated;
grant execute on function atlas.materialize_production_bed_preparation_company_work_v1(uuid,date)
  to postgres,service_role;

create or replace function atlas.reconcile_production_company_work_v1(
  p_production_lot_id uuid,
  p_as_of_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_lot atlas.production_lots%rowtype;
  v_assignment record;
  v_result jsonb;
  v_work jsonb:='[]'::jsonb;
  v_closed jsonb:='[]'::jsonb;
  v_stale record;
  v_requirement_id uuid;
  v_ledger jsonb;
  v_ledger_id uuid;
begin
  if p_production_lot_id is null then
    raise exception 'Production lot is required.' using errcode='22023';
  end if;

  select * into v_lot from atlas.production_lots where id=p_production_lot_id;
  if v_lot.id is null then
    raise exception 'Production lot was not found.' using errcode='P0002';
  end if;

  for v_assignment in
    select a.id
    from atlas.production_bed_assignments a
    join atlas.production_capacity_requirements r
      on r.id=coalesce(a.requirement_id,r.id)
    where a.production_lot_id=v_lot.id
      and a.assignment_status='assigned'
      and r.production_lot_id=v_lot.id
      and r.capacity_kind='bed_feet'
      and r.calculation_status in ('calculated','confirmed')
      and r.quantity_needed is not null
    order by a.created_at,a.id
  loop
    v_result:=atlas.materialize_production_bed_preparation_company_work_v1(v_assignment.id,p_as_of_date);
    v_work:=v_work||jsonb_build_array(v_result);
  end loop;

  for v_stale in
    select wi.id as work_item_id,wi.organization_id,wi.organization_unit_id,wi.source_object_id,
           wi.title,wi.metadata
    from atlas.work_items wi
    where wi.source_object_type='production_bed_assignment'
      and wi.work_state='open'
      and wi.metadata->>'productionLotId'=v_lot.id::text
      and not exists(
        select 1
        from atlas.production_bed_assignments a
        where a.id=wi.source_object_id
          and a.production_lot_id=v_lot.id
          and a.assignment_status='assigned'
      )
  loop
    update atlas.work_items
    set work_state='cancelled',cancelled_at=now(),updated_at=now(),
        metadata=metadata||jsonb_build_object('cancelledBy','reconcile_production_company_work_v1','sourceRequirementActive',false)
    where id=v_stale.work_item_id and work_state='open';

    update atlas.work_requirements r
    set state='cancelled',cancelled_at=now(),updated_at=now(),
        metadata=r.metadata||jsonb_build_object('cancelledBy','reconcile_production_company_work_v1','sourceRequirementActive',false)
    from atlas.work_requirement_links l
    where l.work_item_id=v_stale.work_item_id
      and l.requirement_id=r.id
      and l.active
      and r.state='active';

    update atlas.work_time_contracts
    set contract_state='cancelled',updated_at=now(),
        metadata=metadata||jsonb_build_object('cancelledBy','reconcile_production_company_work_v1')
    where work_item_id=v_stale.work_item_id and contract_state='active';

    update atlas.work_execution_adapters
    set state='retired',retired_at=now(),updated_at=now(),
        metadata=metadata||jsonb_build_object('retirementReason','production_source_requirement_closed')
    where work_item_id=v_stale.work_item_id and state='active';

    select l.requirement_id into v_requirement_id
    from atlas.work_requirement_links l
    where l.work_item_id=v_stale.work_item_id and l.active
    order by l.created_at
    limit 1;

    v_ledger:=atlas.project_organization_ledger_event_internal_v1(
      v_stale.organization_id,
      v_stale.organization_unit_id,
      'production:bed-preparation-closed:'||v_stale.source_object_id::text,
      'production',
      'bed_preparation_requirement_closed',
      'production_bed_assignment:'||v_stale.source_object_id::text||':bed_preparation_closed',
      now(),
      v_stale.title,
      'Production no longer establishes this bed-preparation requirement.',
      'established','closed',
      jsonb_build_object(
        'productionLotId',v_lot.id,
        'productionBedAssignmentId',v_stale.source_object_id,
        'workRequirementId',v_requirement_id,
        'workItemId',v_stale.work_item_id,
        'workState','cancelled'
      ),
      jsonb_build_object(
        'sourceDomainAuthority','production',
        'projectedBy','reconcile_production_company_work_v1'
      ),
      jsonb_build_object('companyWorkItemId',v_stale.work_item_id),
      now()
    );
    v_ledger_id:=nullif(v_ledger->>'entryId','')::uuid;
    if v_ledger_id is not null then
      perform atlas.link_organization_ledger_subject_internal_v1(
        v_ledger_id,'production','production_bed_assignment',v_stale.source_object_id::text,'source',
        jsonb_build_object('sourceDomainAuthority','production'),'{}'::jsonb
      );
      perform atlas.link_organization_ledger_subject_internal_v1(
        v_ledger_id,'work','work_item',v_stale.work_item_id::text,'closed_work',
        jsonb_build_object('authority','company_work'),'{}'::jsonb
      );
    end if;

    v_closed:=v_closed||jsonb_build_array(jsonb_build_object(
      'workItemId',v_stale.work_item_id,
      'sourceAssignmentId',v_stale.source_object_id,
      'ledgerEntryId',v_ledger_id
    ));
  end loop;

  return jsonb_build_object(
    'contractVersion','reconcile_production_company_work_v1',
    'productionLotId',v_lot.id,
    'work',v_work,
    'closed',v_closed
  );
end;
$function$;

revoke all on function atlas.reconcile_production_company_work_v1(uuid,date)
  from public,anon,authenticated;
grant execute on function atlas.reconcile_production_company_work_v1(uuid,date)
  to postgres,service_role;

create or replace function atlas.reconcile_production_work_v1(
  p_production_lot_id uuid,
  p_as_of_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_prop jsonb;
  v_down jsonb;
  v_capacity jsonb;
  v_company jsonb;
  v_cleanup jsonb;
  v_stage text;
begin
  if p_production_lot_id is null then raise exception 'Production lot is required' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('atlas.production.reconcile:entry:'||p_production_lot_id::text,0));
  select current_stage into v_stage from atlas.production_lots where id=p_production_lot_id;
  if v_stage is null then raise exception 'Production lot was not found' using errcode='P0002'; end if;

  v_company:=atlas.reconcile_production_company_work_v1(p_production_lot_id,p_as_of_date);
  v_prop:=atlas.reconcile_production_propagation_work_v1(p_production_lot_id,p_as_of_date);
  if v_stage in ('germination_pending','reseed_decision','seedling_care') then
    v_down:=jsonb_build_object('currentStage',v_stage,'work','[]'::jsonb,'transplantGate',null,'harvestGate',null);
  else
    v_down:=atlas.reconcile_production_work_downstream_v1(p_production_lot_id,p_as_of_date);
  end if;
  v_capacity:=atlas.reconcile_production_capacity_work_v1(p_production_lot_id,p_as_of_date);
  v_cleanup:=atlas.cancel_obsolete_production_propagation_work_v1(p_production_lot_id);

  return jsonb_build_object(
    'productionLotId',p_production_lot_id,
    'authority','production_reconciler',
    'currentStage',coalesce(v_down->>'currentStage',v_prop->>'currentStage',v_stage),
    'work',coalesce(v_prop->'work','[]'::jsonb)||coalesce(v_down->'work','[]'::jsonb)||coalesce(v_capacity->'work','[]'::jsonb),
    'companyWork',v_company,
    'transplantGate',v_down->'transplantGate','harvestGate',v_down->'harvestGate','cleanup',v_cleanup
  );
end;
$function$;

create or replace function atlas.sync_explicit_worker_task_company_work_trigger_v2()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_adapter atlas.work_execution_adapters%rowtype;
  v_work atlas.work_items%rowtype;
begin
  if new.planned_occurrence_id is not null then
    select a.* into v_adapter
    from atlas.work_execution_adapters a
    join atlas.work_items wi
      on wi.organization_id=a.organization_id
     and wi.id=a.work_item_id
    where a.planned_occurrence_id=new.planned_occurrence_id
      and wi.source_object_type='production_bed_assignment'
      and coalesce((wi.metadata->>'executionCarrierAssignmentIsResponsibilityEvidence')::boolean,true)=false
    order by case when a.state='active' then 0 else 1 end,a.created_at desc
    limit 1;

    if v_adapter.id is not null then
      select * into v_work from atlas.work_items where id=v_adapter.work_item_id;

      if v_adapter.task_id is not null and v_adapter.task_id<>new.id then
        raise exception 'Production execution adapter is already bound to a different Task.' using errcode='23514';
      end if;

      update atlas.work_execution_adapters
      set task_id=new.id,
          state=case when new.status='archived' then 'retired' else 'active' end,
          retired_at=case when new.status='archived' then coalesce(retired_at,now()) else null end,
          metadata=metadata||jsonb_build_object(
            'executionCarrierTaskId',new.id,
            'carrierAssignmentIsResponsibilityEvidence',false,
            'responsibilityAuthority','work_allocations',
            'canonicalResponsibilityProtectedBy','sync_explicit_worker_task_company_work_trigger_v2'
          ),
          updated_at=now()
      where id=v_adapter.id;

      if new.status='done' then
        perform atlas.sync_explicit_worker_task_company_work_v2(new.id);
      end if;

      return new;
    end if;
  end if;

  perform atlas.sync_explicit_worker_task_company_work_v2(new.id);
  return new;
end;
$function$;

revoke all on function atlas.sync_explicit_worker_task_company_work_trigger_v2()
  from public,anon,authenticated;
grant execute on function atlas.sync_explicit_worker_task_company_work_trigger_v2()
  to postgres,service_role;

comment on function atlas.materialize_production_bed_preparation_company_work_v1(uuid,date) is
  'Production-owned admission of bed-preparation need into durable Company Work. Does not infer or create Responsibility.';
comment on function atlas.reconcile_production_company_work_v1(uuid,date) is
  'Converges active Production bed assignments into Company Work and Organization Ledger projection; closes stale source-owned work.';
comment on function atlas.sync_explicit_worker_task_company_work_trigger_v2() is
  'Legacy task adoption bridge. Production execution carriers may execute/complete canonical Work but their assignee fields are not Responsibility evidence.';

do $backfill$
declare
  v_lot record;
begin
  for v_lot in
    select distinct a.production_lot_id
    from atlas.production_bed_assignments a
    join atlas.production_lots pl on pl.id=a.production_lot_id
    join atlas.production_capacity_requirements r
      on r.id=a.requirement_id
    where a.assignment_status='assigned'
      and pl.lifecycle_status='active'
      and r.capacity_kind='bed_feet'
      and r.calculation_status in ('calculated','confirmed')
      and r.quantity_needed is not null
    order by a.production_lot_id
  loop
    perform atlas.reconcile_production_company_work_v1(v_lot.production_lot_id,null);
  end loop;
end;
$backfill$;