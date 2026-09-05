-- Atlas Production -> Company Work direct seam v1 — rollback proof only.
--
-- This is NOT a production migration. It proves that Production can establish
-- durable organization-owned work without resolving a worker or requiring a
-- legacy Task/planned-occurrence carrier as work identity.

begin;

create or replace function atlas.materialize_production_bed_preparation_company_work_proof_v1(
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
  v_tz text;
  v_today date;
  v_due_date date;
  v_earliest timestamptz;
  v_latest timestamptz;
  v_work_key text;
  v_requirement_key text;
  v_active_allocations integer;
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

  if v_lot.current_stage<>'transplant_ready' then
    return jsonb_build_object(
      'state','not_transplant_ready',
      'assignmentId',p_assignment_id,
      'currentStage',v_lot.current_stage
    );
  end if;

  select * into v_req_source
  from atlas.production_capacity_requirements
  where production_lot_id=v_lot.id
    and capacity_kind='bed_feet'
  order by created_at
  limit 1;

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

  v_today:=coalesce(p_as_of_date,(now() at time zone v_tz)::date);
  v_due_date:=coalesce(
    v_req_source.preparation_due_date,
    v_assignment.planned_transplant_date,
    v_req_source.required_by_date,
    v_today
  );

  -- Preserve an already-missed need as current unresolved work instead of
  -- constructing an impossible inverted time contract in this proof.
  if v_due_date<v_today then
    v_due_date:=v_today;
  end if;

  v_earliest:=v_today::timestamp at time zone v_tz;
  v_latest:=(v_due_date+1)::timestamp at time zone v_tz;
  v_work_key:='production:bed-preparation:'||v_assignment.id::text;
  v_requirement_key:=v_work_key||':requirement';

  insert into atlas.work_requirements(
    organization_id,
    organization_unit_id,
    stable_key,
    requirement_kind,
    summary,
    source_object_type,
    source_object_id,
    state,
    established_at,
    requirement_began_at,
    earliest_relevant_at,
    latest_satisfactory_at,
    consequence_of_delay,
    jurisdiction_key,
    metadata
  ) values(
    v_farm.organization_id,
    v_farm.organization_unit_id,
    v_requirement_key,
    'operational',
    'Prepare '||v_object.label||' for '||v_lot.lot_label,
    'production_bed_assignment',
    v_assignment.id,
    'active',
    now(),
    now(),
    v_earliest,
    v_latest,
    jsonb_build_object(
      'kind','destination_preparation',
      'effect','The assigned destination must be prepared before transplant can proceed.'
    ),
    'operations.production',
    jsonb_build_object(
      'sourceDomain','production',
      'productionLotId',v_lot.id,
      'productionBedAssignmentId',v_assignment.id,
      'destinationObjectId',v_object.id,
      'requiredBedFeet',v_assignment.quantity_assigned,
      'targetTransplantDate',v_assignment.planned_transplant_date,
      'assigneeEncodedInWorkIdentity',false
    )
  )
  on conflict(organization_id,stable_key) where stable_key is not null
  do update set
    organization_unit_id=excluded.organization_unit_id,
    summary=excluded.summary,
    earliest_relevant_at=excluded.earliest_relevant_at,
    latest_satisfactory_at=excluded.latest_satisfactory_at,
    consequence_of_delay=excluded.consequence_of_delay,
    jurisdiction_key=excluded.jurisdiction_key,
    metadata=atlas.work_requirements.metadata||excluded.metadata,
    updated_at=now()
  returning * into v_requirement;

  insert into atlas.work_items(
    organization_id,
    organization_unit_id,
    stable_key,
    title,
    instructions,
    work_state,
    operation_class,
    jurisdiction_key,
    source_object_type,
    source_object_id,
    result_contract_key,
    metadata
  ) values(
    v_farm.organization_id,
    v_farm.organization_unit_id,
    v_work_key,
    'Prepare '||v_object.label||' for '||v_lot.lot_label,
    'Weed, clear, prepare, and confirm the destination is ready for the planned transplant.',
    'open',
    'bed_preparation',
    'operations.production',
    'production_bed_assignment',
    v_assignment.id,
    'production_bed_preparation_v1',
    jsonb_build_object(
      'sourceDomain','production',
      'productionLotId',v_lot.id,
      'productionBedAssignmentId',v_assignment.id,
      'destinationObjectId',v_object.id,
      'targetTransplantDate',v_assignment.planned_transplant_date,
      'legacyTaskRequiredForIdentity',false
    )
  )
  on conflict(organization_id,stable_key) where stable_key is not null
  do update set
    organization_unit_id=excluded.organization_unit_id,
    title=excluded.title,
    instructions=excluded.instructions,
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
    v_farm.organization_id,
    v_requirement.id,
    v_work.id,
    'resolves',
    true,
    jsonb_build_object('source','production_bed_preparation_direct_v1')
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
        organization_id,
        work_item_id,
        contract_state,
        earliest_lawful_at,
        latest_lawful_at,
        hard_finish_at,
        movement_policy,
        consequence_of_delay,
        source_kind,
        source_id,
        source_confidence,
        metadata
      ) values(
        v_farm.organization_id,
        v_work.id,
        'active',
        v_earliest,
        v_latest,
        v_latest,
        'bounded',
        jsonb_build_object('kind','destination_preparation'),
        'production_bed_assignment',
        v_assignment.id,
        1,
        jsonb_build_object(
          'sourceDomain','production',
          'targetTransplantDate',v_assignment.planned_transplant_date,
          'timezone',v_tz
        )
      ) returning * into v_time;
    else
      update atlas.work_time_contracts
      set earliest_lawful_at=v_earliest,
          latest_lawful_at=v_latest,
          hard_finish_at=v_latest,
          movement_policy='bounded',
          consequence_of_delay=jsonb_build_object('kind','destination_preparation'),
          source_kind='production_bed_assignment',
          source_id=v_assignment.id,
          source_confidence=1,
          metadata=metadata||jsonb_build_object(
            'sourceDomain','production',
            'targetTransplantDate',v_assignment.planned_transplant_date,
            'timezone',v_tz
          ),
          updated_at=now()
      where id=v_time.id
      returning * into v_time;
    end if;
  end if;

  select count(*) into v_active_allocations
  from atlas.work_allocations
  where organization_id=v_farm.organization_id
    and work_item_id=v_work.id
    and state='active'
    and allocation_role='responsible';

  return jsonb_build_object(
    'state','materialized',
    'organizationId',v_farm.organization_id,
    'organizationUnitId',v_farm.organization_unit_id,
    'requirementId',v_requirement.id,
    'workItemId',v_work.id,
    'timeContractId',v_time.id,
    'responsibilityState',case when v_active_allocations=0 then 'unassigned' else 'assigned' end,
    'activeResponsibleAllocations',v_active_allocations,
    'sourceAssignmentId',v_assignment.id
  );
end;
$function$;

revoke all on function atlas.materialize_production_bed_preparation_company_work_proof_v1(uuid,date)
  from public,anon,authenticated;
grant execute on function atlas.materialize_production_bed_preparation_company_work_proof_v1(uuid,date)
  to postgres,service_role;

do $proof$
declare
  v_assignment uuid;
  v_lot uuid;
  v_first jsonb;
  v_second jsonb;
  v_work uuid;
  v_req uuid;
  v_time uuid;
begin
  select a.id,a.production_lot_id
  into v_assignment,v_lot
  from atlas.production_bed_assignments a
  join atlas.production_lots pl on pl.id=a.production_lot_id
  join atlas.production_capacity_requirements r
    on r.production_lot_id=pl.id
   and r.capacity_kind='bed_feet'
  where a.assignment_status='assigned'
    and pl.lifecycle_status='active'
    and r.calculation_status in('calculated','confirmed')
    and r.quantity_needed is not null
  order by a.created_at
  limit 1;

  if v_assignment is null then
    raise exception 'No Production bed-assignment fixture available.';
  end if;

  -- Existing production triggers may react inside this proof transaction.
  -- All such effects are rolled back. Assertions below target the new direct
  -- Company Work source identity specifically.
  update atlas.production_lots
  set current_stage='transplant_ready'
  where id=v_lot;

  v_first:=atlas.materialize_production_bed_preparation_company_work_proof_v1(
    v_assignment,'2026-09-05'
  );

  if v_first->>'state'<>'materialized' then
    raise exception 'Direct Production Company Work did not materialize: %',v_first;
  end if;
  if v_first->>'responsibilityState'<>'unassigned' then
    raise exception 'Production incorrectly assigned Responsibility.';
  end if;

  v_work:=(v_first->>'workItemId')::uuid;
  v_req:=(v_first->>'requirementId')::uuid;
  v_time:=(v_first->>'timeContractId')::uuid;

  if not exists(
    select 1 from atlas.work_items wi
    where wi.id=v_work
      and wi.source_object_type='production_bed_assignment'
      and wi.source_object_id=v_assignment
      and wi.work_state='open'
  ) then
    raise exception 'Company Work source identity is wrong.';
  end if;

  if not exists(
    select 1 from atlas.work_requirements wr
    where wr.id=v_req
      and wr.source_object_type='production_bed_assignment'
      and wr.source_object_id=v_assignment
      and wr.state='active'
  ) then
    raise exception 'Work Requirement source identity is wrong.';
  end if;

  if (select count(*) from atlas.work_allocations wa where wa.work_item_id=v_work)<>0 then
    raise exception 'Production created Responsibility allocation.';
  end if;

  if (select count(*) from atlas.work_execution_adapters wea where wea.work_item_id=v_work)<>0 then
    raise exception 'Direct Work identity unexpectedly requires legacy execution adapter.';
  end if;

  if not exists(
    select 1 from atlas.work_time_contracts wt
    where wt.id=v_time
      and wt.work_item_id=v_work
      and wt.source_kind='production_bed_assignment'
      and wt.contract_state='active'
  ) then
    raise exception 'Production timing did not land in Work time contract.';
  end if;

  v_second:=atlas.materialize_production_bed_preparation_company_work_proof_v1(
    v_assignment,'2026-09-05'
  );

  if (v_second->>'workItemId')::uuid<>v_work
     or (v_second->>'requirementId')::uuid<>v_req then
    raise exception 'Replay changed canonical Work identity.';
  end if;

  if (
    select count(*)
    from atlas.work_items wi
    where wi.organization_id=(v_first->>'organizationId')::uuid
      and wi.stable_key='production:bed-preparation:'||v_assignment::text
  )<>1 then
    raise exception 'Replay duplicated Work.';
  end if;

  if (
    select count(*)
    from atlas.work_time_contracts wt
    where wt.work_item_id=v_work
      and wt.contract_state='active'
  )<>1 then
    raise exception 'Replay duplicated active time contract.';
  end if;
end;
$proof$;

rollback;
