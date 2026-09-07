create or replace function atlas.sync_production_company_work_responsibility_carrier_v1(p_work_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_work atlas.work_items%rowtype;
  v_adapter atlas.work_execution_adapters%rowtype;
  v_occ atlas.planned_work_occurrences%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_org_member atlas.organization_memberships%rowtype;
  v_farm_member atlas.farm_memberships%rowtype;
  v_farm_member_count integer:=0;
  v_conflict_id uuid;
  v_result jsonb;
begin
  if p_work_item_id is null then
    raise exception 'Company Work item is required.' using errcode='22023';
  end if;

  select * into v_work
  from atlas.work_items
  where id=p_work_item_id;

  if v_work.id is null then
    raise exception 'Company Work item was not found.' using errcode='P0002';
  end if;

  if v_work.source_object_type<>'production_bed_assignment' then
    return jsonb_build_object('state','unsupported_source','workItemId',v_work.id);
  end if;

  if v_work.work_state<>'open' then
    return jsonb_build_object('state','work_not_open','workItemId',v_work.id,'workState',v_work.work_state);
  end if;

  select * into v_adapter
  from atlas.work_execution_adapters
  where organization_id=v_work.organization_id
    and work_item_id=v_work.id
    and state='active'
    and planned_occurrence_id is not null
  order by created_at
  limit 1;

  if v_adapter.id is null then
    return jsonb_build_object('state','no_execution_carrier','workItemId',v_work.id);
  end if;

  select * into v_occ
  from atlas.planned_work_occurrences
  where id=v_adapter.planned_occurrence_id;

  if v_occ.id is null then
    return jsonb_build_object('state','missing_execution_occurrence','workItemId',v_work.id,'adapterId',v_adapter.id);
  end if;

  select * into v_allocation
  from atlas.work_allocations
  where organization_id=v_work.organization_id
    and work_item_id=v_work.id
    and state='active'
    and allocation_role='responsible'
  limit 1;

  if v_allocation.id is null then
    update atlas.planned_work_occurrences
    set task_payload=(coalesce(task_payload,'{}'::jsonb)-'assigned_membership_id'-'assigned_user_id')
          || jsonb_build_object('visibility_scope','system_internal')
          || jsonb_build_object('metadata',coalesce(task_payload->'metadata','{}'::jsonb)||jsonb_build_object(
               'responsibility_state','unresolved',
               'responsibility_authority','work_allocations',
               'legacy_assignment_suppressed',true
             )),
        updated_at=now()
    where id=v_occ.id;

    if v_adapter.task_id is not null then
      update atlas.tasks
      set assigned_membership_id=null,
          assigned_user_id=null,
          visibility_scope='system_internal',
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
            'responsibility_state','unresolved',
            'responsibility_authority','work_allocations',
            'legacy_assignment_suppressed',true
          ),
          updated_at=now()
      where id=v_adapter.task_id and status in ('open','blocked');
    end if;

    update atlas.work_execution_adapters
    set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'executionCarrierDeliveryState','responsibility_unresolved',
          'responsibilityAuthority','work_allocations',
          'carrierAssignmentIsResponsibilityEvidence',false
        ),
        updated_at=now()
    where id=v_adapter.id;

    update atlas.work_planning_conflicts
    set state='resolved',resolution_kind='responsibility_released',
        resolution_note='Canonical Responsibility is currently unassigned; no worker carrier should be inferred.',
        resolved_at=now(),updated_at=now()
    where organization_id=v_work.organization_id
      and work_item_id=v_work.id
      and state='open'
      and metadata->>'source'='company_work_execution_carrier_membership';

    perform atlas.materialize_production_bed_preparation_company_work_v1(v_work.source_object_id,null);

    return jsonb_build_object(
      'state','responsibility_unresolved',
      'workItemId',v_work.id,
      'adapterId',v_adapter.id,
      'occurrenceId',v_occ.id,
      'taskId',v_adapter.task_id
    );
  end if;

  select * into v_org_member
  from atlas.organization_memberships
  where id=v_allocation.assignee_membership_id
    and organization_id=v_work.organization_id
    and active;

  if v_org_member.id is null then
    raise exception 'Active responsible allocation points to an inactive or foreign Organization Membership.' using errcode='23514';
  end if;

  select count(*)::integer into v_farm_member_count
  from atlas.farm_memberships fm
  where fm.farm_id=v_occ.farm_id
    and fm.user_id=v_org_member.user_id
    and fm.active;

  if v_farm_member_count=1 then
    select * into v_farm_member
    from atlas.farm_memberships fm
    where fm.farm_id=v_occ.farm_id
      and fm.user_id=v_org_member.user_id
      and fm.active
    order by fm.created_at
    limit 1;

    update atlas.planned_work_occurrences
    set task_payload=(coalesce(task_payload,'{}'::jsonb)
          || jsonb_build_object(
               'assigned_membership_id',v_farm_member.id::text,
               'assigned_user_id',v_org_member.user_id::text,
               'visibility_scope','assigned_worker'
             ))
          || jsonb_build_object('metadata',coalesce(task_payload->'metadata','{}'::jsonb)||jsonb_build_object(
               'responsibility_state','assigned',
               'responsibility_authority','work_allocations',
               'company_work_allocation_id',v_allocation.id,
               'assignee_organization_membership_id',v_org_member.id,
               'execution_farm_membership_id',v_farm_member.id,
               'carrier_assignment_is_responsibility_evidence',false
             )),
        updated_at=now()
    where id=v_occ.id;

    if v_adapter.task_id is not null then
      update atlas.tasks
      set assigned_membership_id=v_farm_member.id,
          assigned_user_id=v_org_member.user_id,
          visibility_scope='assigned_worker',
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
            'responsibility_state','assigned',
            'responsibility_authority','work_allocations',
            'company_work_allocation_id',v_allocation.id,
            'assignee_organization_membership_id',v_org_member.id,
            'execution_farm_membership_id',v_farm_member.id,
            'carrier_assignment_is_responsibility_evidence',false
          ),
          updated_at=now()
      where id=v_adapter.task_id and status in ('open','blocked');
    end if;

    update atlas.work_execution_adapters
    set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'executionCarrierDeliveryState','ready',
          'responsibilityAuthority','work_allocations',
          'companyWorkAllocationId',v_allocation.id,
          'assigneeOrganizationMembershipId',v_org_member.id,
          'executionFarmMembershipId',v_farm_member.id,
          'carrierAssignmentIsResponsibilityEvidence',false
        ),
        updated_at=now()
    where id=v_adapter.id;

    update atlas.work_planning_conflicts
    set state='resolved',resolution_kind='execution_membership_resolved',
        resolution_note='Canonical Responsibility now resolves to exactly one active Farm Membership for this compatibility carrier.',
        resolved_at=now(),updated_at=now()
    where organization_id=v_work.organization_id
      and work_item_id=v_work.id
      and state='open'
      and metadata->>'source'='company_work_execution_carrier_membership';

    v_result:=jsonb_build_object(
      'state','carrier_ready',
      'workItemId',v_work.id,
      'allocationId',v_allocation.id,
      'organizationMembershipId',v_org_member.id,
      'farmMembershipId',v_farm_member.id,
      'occurrenceId',v_occ.id,
      'taskId',v_adapter.task_id
    );
  else
    update atlas.planned_work_occurrences
    set task_payload=(coalesce(task_payload,'{}'::jsonb)-'assigned_membership_id'-'assigned_user_id')
          || jsonb_build_object('visibility_scope','system_internal')
          || jsonb_build_object('metadata',coalesce(task_payload->'metadata','{}'::jsonb)||jsonb_build_object(
               'responsibility_state','assigned_delivery_unresolved',
               'responsibility_authority','work_allocations',
               'company_work_allocation_id',v_allocation.id,
               'assignee_organization_membership_id',v_org_member.id,
               'active_matching_farm_memberships',v_farm_member_count
             )),
        updated_at=now()
    where id=v_occ.id;

    if v_adapter.task_id is not null then
      update atlas.tasks
      set assigned_membership_id=null,
          assigned_user_id=null,
          visibility_scope='system_internal',
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
            'responsibility_state','assigned_delivery_unresolved',
            'responsibility_authority','work_allocations',
            'company_work_allocation_id',v_allocation.id,
            'assignee_organization_membership_id',v_org_member.id,
            'active_matching_farm_memberships',v_farm_member_count
          ),
          updated_at=now()
      where id=v_adapter.task_id and status in ('open','blocked');
    end if;

    update atlas.work_execution_adapters
    set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'executionCarrierDeliveryState','membership_unresolved',
          'responsibilityAuthority','work_allocations',
          'companyWorkAllocationId',v_allocation.id,
          'assigneeOrganizationMembershipId',v_org_member.id,
          'activeMatchingFarmMemberships',v_farm_member_count,
          'carrierAssignmentIsResponsibilityEvidence',false
        ),
        updated_at=now()
    where id=v_adapter.id;

    select pc.id into v_conflict_id
    from atlas.work_planning_conflicts pc
    where pc.organization_id=v_work.organization_id
      and pc.work_item_id=v_work.id
      and pc.state='open'
      and pc.metadata->>'source'='company_work_execution_carrier_membership'
    order by pc.detected_at desc
    limit 1;

    if v_conflict_id is null then
      insert into atlas.work_planning_conflicts(
        organization_id,work_item_id,allocation_id,conflict_kind,detected_at,required_by,
        capacity_snapshot,reason,state,metadata
      ) values(
        v_work.organization_id,v_work.id,v_allocation.id,'no_eligible_assignee',now(),
        (select preferred_end_at from atlas.work_time_contracts where work_item_id=v_work.id and contract_state='active' order by created_at desc limit 1),
        jsonb_build_object('activeMatchingFarmMemberships',v_farm_member_count),
        'Canonical Responsibility is established, but the legacy farm execution carrier cannot resolve the responsible Organization Membership to exactly one active Farm Membership. Responsibility remains true; carrier delivery is unresolved.',
        'open',jsonb_build_object(
          'source','company_work_execution_carrier_membership',
          'allocationId',v_allocation.id,
          'assigneeOrganizationMembershipId',v_org_member.id,
          'farmId',v_occ.farm_id
        )
      ) returning id into v_conflict_id;
    else
      update atlas.work_planning_conflicts
      set allocation_id=v_allocation.id,
          capacity_snapshot=jsonb_build_object('activeMatchingFarmMemberships',v_farm_member_count),
          reason='Canonical Responsibility is established, but the legacy farm execution carrier cannot resolve the responsible Organization Membership to exactly one active Farm Membership. Responsibility remains true; carrier delivery is unresolved.',
          metadata=metadata||jsonb_build_object('allocationId',v_allocation.id,'assigneeOrganizationMembershipId',v_org_member.id,'farmId',v_occ.farm_id),
          updated_at=now()
      where id=v_conflict_id;
    end if;

    v_result:=jsonb_build_object(
      'state','responsibility_assigned_carrier_unresolved',
      'workItemId',v_work.id,
      'allocationId',v_allocation.id,
      'organizationMembershipId',v_org_member.id,
      'activeMatchingFarmMemberships',v_farm_member_count,
      'planningConflictId',v_conflict_id,
      'occurrenceId',v_occ.id,
      'taskId',v_adapter.task_id
    );
  end if;

  perform atlas.materialize_production_bed_preparation_company_work_v1(v_work.source_object_id,null);
  return v_result;
end;
$function$;

revoke all on function atlas.sync_production_company_work_responsibility_carrier_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.sync_production_company_work_responsibility_carrier_v1(uuid) to postgres,service_role;

create or replace function atlas.set_company_work_responsibility_internal_v1(
  p_work_item_id uuid,
  p_assignee_membership_id uuid,
  p_assigned_by_membership_id uuid default null,
  p_reason text default null,
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_work atlas.work_items%rowtype;
  v_assignee atlas.organization_memberships%rowtype;
  v_assigner atlas.organization_memberships%rowtype;
  v_existing atlas.work_allocations%rowtype;
  v_new atlas.work_allocations%rowtype;
begin
  if p_work_item_id is null then
    raise exception 'Company Work item is required.' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('atlas.company_work.responsibility:'||p_work_item_id::text,0));

  select * into v_work from atlas.work_items where id=p_work_item_id for update;
  if v_work.id is null then raise exception 'Company Work item was not found.' using errcode='P0002'; end if;
  if v_work.work_state<>'open' then raise exception 'Responsibility can only be changed while Company Work is open.' using errcode='22023'; end if;

  if p_assigned_by_membership_id is not null then
    select * into v_assigner from atlas.organization_memberships
    where id=p_assigned_by_membership_id and organization_id=v_work.organization_id and active;
    if v_assigner.id is null then raise exception 'Assigning membership must be active in the Work organization.' using errcode='23514'; end if;
  end if;

  if p_assignee_membership_id is not null then
    select * into v_assignee from atlas.organization_memberships
    where id=p_assignee_membership_id and organization_id=v_work.organization_id and active;
    if v_assignee.id is null then raise exception 'Responsible membership must be active in the Work organization.' using errcode='23514'; end if;
  end if;

  select * into v_existing
  from atlas.work_allocations
  where organization_id=v_work.organization_id
    and work_item_id=v_work.id
    and allocation_role='responsible'
    and state='active'
  limit 1;

  if p_assignee_membership_id is null then
    if v_existing.id is not null then
      update atlas.work_allocations
      set state='released',released_at=now(),
          release_reason=coalesce(nullif(btrim(p_reason),''),'responsibility_released'),
          metadata=coalesce(metadata,'{}'::jsonb)||coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('releasedByMembershipId',p_assigned_by_membership_id),
          updated_at=now()
      where id=v_existing.id;
    else
      perform atlas.sync_production_company_work_responsibility_carrier_v1(v_work.id);
    end if;
    return jsonb_build_object('state',case when v_existing.id is null then 'unchanged_unassigned' else 'released' end,'workItemId',v_work.id,'allocationId',v_existing.id);
  end if;

  if v_existing.id is not null and v_existing.assignee_membership_id=p_assignee_membership_id then
    update atlas.work_allocations
    set metadata=coalesce(metadata,'{}'::jsonb)||coalesce(p_provenance,'{}'::jsonb),updated_at=now()
    where id=v_existing.id
    returning * into v_existing;
    perform atlas.sync_production_company_work_responsibility_carrier_v1(v_work.id);
    return jsonb_build_object('state','unchanged','workItemId',v_work.id,'allocationId',v_existing.id,'assigneeMembershipId',v_existing.assignee_membership_id);
  end if;

  if v_existing.id is not null then
    update atlas.work_allocations
    set state='released',released_at=now(),
        release_reason=coalesce(nullif(btrim(p_reason),''),'responsibility_reassigned'),
        metadata=coalesce(metadata,'{}'::jsonb)||coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('supersededByAssigneeMembershipId',p_assignee_membership_id),
        updated_at=now()
    where id=v_existing.id;
  end if;

  insert into atlas.work_allocations(
    organization_id,work_item_id,assignee_membership_id,assigned_by_membership_id,
    allocation_role,state,allocated_at,metadata
  ) values(
    v_work.organization_id,v_work.id,p_assignee_membership_id,p_assigned_by_membership_id,
    'responsible','active',now(),coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'source','set_company_work_responsibility_internal_v1',
      'reason',nullif(btrim(coalesce(p_reason,'')),'')
    )
  ) returning * into v_new;

  return jsonb_build_object('state','assigned','workItemId',v_work.id,'allocationId',v_new.id,'assigneeMembershipId',v_new.assignee_membership_id);
end;
$function$;

revoke all on function atlas.set_company_work_responsibility_internal_v1(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function atlas.set_company_work_responsibility_internal_v1(uuid,uuid,uuid,text,jsonb) to postgres,service_role;

create or replace function atlas.organization_owner_set_company_work_responsibility_api_v1(
  p_work_item_id uuid,
  p_assignee_membership_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_work atlas.work_items%rowtype;
  v_actor_membership_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select * into v_work from atlas.work_items where id=p_work_item_id;
  if v_work.id is null then raise exception 'Company Work item was not found.' using errcode='P0002'; end if;

  if not atlas.is_organization_owner(v_work.organization_id) then
    raise exception 'Organization owner authority required.' using errcode='42501';
  end if;

  select om.id into v_actor_membership_id
  from atlas.organization_memberships om
  where om.organization_id=v_work.organization_id
    and om.user_id=auth.uid()
    and om.active
    and om.role='owner'
  order by om.created_at
  limit 1;

  return atlas.set_company_work_responsibility_internal_v1(
    v_work.id,p_assignee_membership_id,v_actor_membership_id,p_reason,
    jsonb_build_object('source','organization_owner_set_company_work_responsibility_api_v1','actorUserId',auth.uid())
  );
end;
$function$;

revoke all on function atlas.organization_owner_set_company_work_responsibility_api_v1(uuid,uuid,text) from public,anon;
grant execute on function atlas.organization_owner_set_company_work_responsibility_api_v1(uuid,uuid,text) to authenticated;

create or replace function atlas.sync_production_company_work_responsibility_carrier_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
begin
  if new.allocation_role='responsible' then
    perform atlas.sync_production_company_work_responsibility_carrier_v1(new.work_item_id);
  end if;
  return new;
end;
$function$;

revoke all on function atlas.sync_production_company_work_responsibility_carrier_trigger_v1() from public,anon,authenticated;
grant execute on function atlas.sync_production_company_work_responsibility_carrier_trigger_v1() to postgres,service_role;

drop trigger if exists work_allocations_sync_production_carrier_v1 on atlas.work_allocations;
create trigger work_allocations_sync_production_carrier_v1
after insert or update of state,assignee_membership_id,allocation_role on atlas.work_allocations
for each row execute function atlas.sync_production_company_work_responsibility_carrier_trigger_v1();

create or replace function atlas.work_occurrence_gate_satisfied_v1(p_occurrence_id uuid,p_as_of_date date)
returns boolean
language sql
stable security definer
set search_path to 'pg_catalog','atlas'
as $function$
  select case
    when occurrence.id is null then false
    when exists(
      select 1
      from atlas.work_execution_adapters adapter
      join atlas.work_items work_item
        on work_item.organization_id=adapter.organization_id
       and work_item.id=adapter.work_item_id
      where adapter.planned_occurrence_id=occurrence.id
        and adapter.state='active'
        and work_item.work_state='open'
        and coalesce(adapter.metadata->>'responsibilityAuthority','')='work_allocations'
    ) and not exists(
      select 1
      from atlas.work_execution_adapters adapter
      join atlas.work_items work_item
        on work_item.organization_id=adapter.organization_id
       and work_item.id=adapter.work_item_id
      join atlas.work_allocations allocation
        on allocation.organization_id=work_item.organization_id
       and allocation.work_item_id=work_item.id
       and allocation.state='active'
       and allocation.allocation_role='responsible'
      join atlas.organization_memberships org_member
        on org_member.organization_id=allocation.organization_id
       and org_member.id=allocation.assignee_membership_id
       and org_member.active
      join atlas.farm_memberships farm_member
        on farm_member.farm_id=occurrence.farm_id
       and farm_member.user_id=org_member.user_id
       and farm_member.active
      where adapter.planned_occurrence_id=occurrence.id
        and adapter.state='active'
        and work_item.work_state='open'
        and coalesce(adapter.metadata->>'responsibilityAuthority','')='work_allocations'
        and nullif(occurrence.task_payload->>'assigned_membership_id','')::uuid=farm_member.id
        and nullif(occurrence.task_payload->>'assigned_user_id','')::uuid=org_member.user_id
    ) then false
    when exists(
      select 1
      from atlas.task_external_readiness_gates external_gate
      join atlas.tasks external_task on external_task.id=external_gate.task_id
      where external_task.planned_occurrence_id=occurrence.id
        and external_gate.gate_state='waiting'
    ) then false
    when exists(select 1 from atlas.task_release_queue_items qi where qi.planned_occurrence_id=occurrence.id and qi.state='queued') then exists(
      select 1 from atlas.task_release_queue_items qi
      where qi.planned_occurrence_id=occurrence.id and qi.state='queued'
        and not exists(select 1 from atlas.task_release_queue_items active_item where active_item.farm_id=qi.farm_id and active_item.queue_key=qi.queue_key and active_item.state='active')
        and qi.position=(select min(head.position) from atlas.task_release_queue_items head where head.farm_id=qi.farm_id and head.queue_key=qi.queue_key and head.state='queued')
        and (occurrence.not_before_date is null or occurrence.not_before_date<=p_as_of_date)
    )
    when coalesce(occurrence.task_payload->>'action_key','')='weed'
      and exists(select 1 from atlas.farm_memberships anna where anna.id=nullif(occurrence.task_payload->>'assigned_membership_id','')::uuid and anna.farm_id=occurrence.farm_id and anna.worker_key='anna' and anna.active=true)
      and exists(select 1 from atlas.task_release_queue_items qi where qi.farm_id=occurrence.farm_id and qi.queue_key='anna_weeding_rotation' and qi.state in ('active','queued'))
      and not exists(select 1 from atlas.task_release_queue_items qi where qi.planned_occurrence_id=occurrence.id and qi.queue_key='anna_weeding_rotation' and qi.state='active')
    then false
    when occurrence.state='eligible' then true
    when policy.gate_type in ('immediate','time_window','serial_queue') then occurrence.not_before_date is null or occurrence.not_before_date<=p_as_of_date
    when policy.gate_type='predecessor' then occurrence.gate_satisfied_at is not null or (occurrence.parent_occurrence_id is not null and exists(select 1 from atlas.planned_work_occurrences parent where parent.id=occurrence.parent_occurrence_id and parent.state in ('released','completed')))
    else occurrence.gate_satisfied_at is not null
  end
  from atlas.planned_work_occurrences occurrence
  join atlas.work_release_policies policy on policy.id=occurrence.release_policy_id
  where occurrence.id=p_occurrence_id
$function$;

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

  select * into v_req from atlas.production_capacity_requirements where production_lot_id=v_lot.id and capacity_kind='bed_feet' limit 1;
  select coalesce(sum(quantity_assigned),0) into v_assigned from atlas.production_bed_assignments where production_lot_id=v_lot.id and assignment_status='assigned';

  -- Company Work completion is the canonical execution result consumed by Production.
  -- Legacy Task completion may provide the evidence that closes Company Work, but the
  -- Task row is not itself Production's prepared-bed truth.
  select coalesce(sum(a.quantity_assigned),0) into v_prepared
  from atlas.production_bed_assignments a
  where a.production_lot_id=v_lot.id
    and a.assignment_status='assigned'
    and exists(
      select 1
      from atlas.work_items wi
      where wi.source_object_type='production_bed_assignment'
        and wi.source_object_id=a.id
        and wi.work_state='completed'
    );

  if v_req.id is null or v_req.calculation_status not in ('calculated','confirmed') or v_req.quantity_needed is null then
    v_status:='waiting_bed_math'; v_blocker:='Bed demand is not calculated from the counted surviving seedlings.';
  elsif v_assigned<v_req.quantity_needed then
    v_status:='waiting_bed_assignment'; v_blocker:=(v_req.quantity_needed-v_assigned)::text||' additional bed-feet must be assigned.';
  elsif v_prepared<v_req.quantity_needed then
    v_status:='waiting_bed_preparation'; v_blocker:=(v_req.quantity_needed-v_prepared)::text||' assigned bed-feet still need completed preparation.';
  else
    v_status:='ready'; v_blocker:=null;
  end if;

  insert into atlas.production_transplant_gates(
    farm_id,production_lot_id,tray_batch_id,readiness_observation_id,bed_requirement_id,
    required_bed_feet,assigned_bed_feet,prepared_bed_feet,gate_status,blocker_text,ready_at,refresh_version,metadata
  ) values(
    v_lot.farm_id,v_lot.id,v_batch.id,v_obs.id,v_req.id,v_req.quantity_needed,v_assigned,v_prepared,v_status,v_blocker,
    case when v_status='ready' then now() end,1,jsonb_build_object('surviving_seedlings',v_obs.surviving_seedlings,'preparedBedFeetAuthority','company_work')
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
    'preparedBedFeetAuthority','company_work'
  );
end;
$function$;

create or replace function atlas.guard_completed_company_work_ledger_designation_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_work_id uuid;
begin
  if new.source_domain='production' and new.semantic_type='bed_preparation_required' then
    begin v_work_id:=nullif(new.payload->>'workItemId','')::uuid; exception when others then v_work_id:=null; end;
    if v_work_id is not null and exists(select 1 from atlas.work_items wi where wi.id=v_work_id and wi.work_state='completed') then
      new.designation_status:='closed';
      new.payload:=coalesce(new.payload,'{}'::jsonb)||jsonb_build_object('responsibilityState','completed','workState','completed');
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists organization_ledger_guard_completed_company_work_v1 on atlas.organization_ledger_entries;
create trigger organization_ledger_guard_completed_company_work_v1
before insert or update of designation_status,payload on atlas.organization_ledger_entries
for each row execute function atlas.guard_completed_company_work_ledger_designation_v1();

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
  set state='satisfied',satisfied_at=coalesce(satisfied_at,v_completed_at),updated_at=now(),
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('satisfiedByCompanyWorkItemId',v_work.id)
  from atlas.work_requirement_links l
  where l.organization_id=v_work.organization_id
    and l.work_item_id=v_work.id
    and l.requirement_id=r.id
    and l.active
    and r.state='active';

  update atlas.work_time_contracts
  set contract_state='satisfied',updated_at=now(),
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('satisfiedByCompanyWorkItemId',v_work.id)
  where organization_id=v_work.organization_id and work_item_id=v_work.id and contract_state='active';

  update atlas.work_allocations
  set state='completed',completed_at=coalesce(completed_at,v_completed_at),updated_at=now()
  where organization_id=v_work.organization_id and work_item_id=v_work.id and state='active';

  update atlas.work_execution_adapters
  set state='completed',completed_at=coalesce(completed_at,v_completed_at),updated_at=now(),
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('completedByCompanyWork',true)
  where organization_id=v_work.organization_id and work_item_id=v_work.id and state='active';

  for v_occurrence_id in
    select planned_occurrence_id
    from atlas.work_execution_adapters
    where organization_id=v_work.organization_id and work_item_id=v_work.id and planned_occurrence_id is not null
  loop
    update atlas.planned_work_occurrences
    set state=case when state='cancelled' then state else 'completed' end,
        gate_satisfied_at=coalesce(gate_satisfied_at,v_completed_at),updated_at=now(),
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('completedByCompanyWork',true,'companyWorkItemId',v_work.id)
    where id=v_occurrence_id and state<>'cancelled';
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

create or replace function atlas.reconcile_production_company_work_completion_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
begin
  if new.work_state='completed' and old.work_state is distinct from new.work_state and new.source_object_type='production_bed_assignment' then
    perform atlas.reconcile_production_bed_preparation_company_work_completion_v1(new.id);
  end if;
  return new;
end;
$function$;

revoke all on function atlas.reconcile_production_company_work_completion_trigger_v1() from public,anon,authenticated;
grant execute on function atlas.reconcile_production_company_work_completion_trigger_v1() to postgres,service_role;

drop trigger if exists work_items_reconcile_production_completion_v1 on atlas.work_items;
create trigger work_items_reconcile_production_completion_v1
after update of work_state on atlas.work_items
for each row when (old.work_state is distinct from new.work_state)
execute function atlas.reconcile_production_company_work_completion_trigger_v1();

-- Backfill only the compatibility projection. No Responsibility is invented.
-- This clears stale legacy assignee pointers (including inactive memberships) from
-- unassigned Production Company Work and refreshes Ledger designation from canonical allocations.
do $block$
declare v_id uuid;
begin
  for v_id in
    select id from atlas.work_items
    where source_object_type='production_bed_assignment' and work_state='open'
    order by created_at,id
  loop
    perform atlas.sync_production_company_work_responsibility_carrier_v1(v_id);
  end loop;
end;
$block$;
