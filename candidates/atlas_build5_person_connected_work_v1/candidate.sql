begin;
-- Atlas Build 5, Person-native receiver uptake. Reviewed source only.
-- Depends on shared Person identity resolution PR #1802.
-- Retains the single canonical Work and pending-offer registries.
-- Accountless connections can be offered and owner-witnessed; no fake login.


-- A seat establishes Ledger participation, not finance, login, or work uptake.
create or replace function atlas.person_has_native_ledger_connection_v1(
  p_organization_id uuid,p_ledger_id uuid,p_canonical_person_id uuid)
returns boolean language sql stable security definer set search_path to ''
as $fn$
  select exists(
    select 1 from atlas.ledgers l
    join ledger.seats s on s.ledger_id=l.id
    join reality.entities e on e.id=s.person_entity_id
    where l.id=p_ledger_id and l.organization_id=p_organization_id
      and s.person_entity_id=p_canonical_person_id
      and e.entity_kind='person' and e.identity_state='canonical'
      and s.seat_state='active' and s.ended_at is null
  )
$fn$;
revoke all on function atlas.person_has_native_ledger_connection_v1(uuid,uuid,uuid)
  from public,anon,authenticated,service_role;
grant execute on function atlas.person_has_native_ledger_connection_v1(uuid,uuid,uuid)
  to authenticated;

-- Preserve the historical membership column as-is; Person-native allocation
-- uses a canonical Reality Person on the exact same allocation row.
alter table atlas.work_allocations
  add column if not exists assignee_canonical_person_id uuid
    references reality.entities(id) on delete restrict;
alter table atlas.work_allocations
  alter column assignee_membership_id drop not null;
alter table atlas.work_allocations
  add constraint work_allocations_exact_assignee_carrier_v1
  check (assignee_membership_id is not null
         or (assignee_canonical_person_id is not null
           and establishment_basis_kind='person_connection_receiver_uptake'));
create index if not exists work_allocations_canonical_person_active_v1
  on atlas.work_allocations(assignee_canonical_person_id,work_item_id)
  where state='active' and allocation_role='responsible'
    and assignee_canonical_person_id is not null;

-- The established offer continues to be the only pending-offer registry.
-- Existing membership offers remain untouched, accountless targets use null.
alter table atlas.company_work_initial_responsibility_offers
  alter column target_membership_id drop not null;

create or replace function atlas.validate_active_work_allocation_membership_v1()
returns trigger language plpgsql security definer set search_path to 'pg_catalog','atlas'
as $fn$
begin
  if new.state='active' then
    if new.allocation_role='responsible'
      and new.establishment_basis_kind='person_connection_receiver_uptake' then
      if new.assignee_membership_id is not null
        or new.assignee_canonical_person_id is null
        or not atlas.person_has_native_ledger_connection_v1(
          new.organization_id,(new.establishment_basis->>'nativeLedgerId')::uuid,
          new.assignee_canonical_person_id) then
        raise exception 'Person-native responsibility requires an exact active Ledger connection'
          using errcode='23514';
      end if;
    elsif not exists (
      select 1 from atlas.organization_memberships om
      where om.id=new.assignee_membership_id
        and om.organization_id=new.organization_id and om.active
    ) then
      raise exception 'Legacy active Work allocation requires active Organization Membership'
        using errcode='23514';
    end if;
    if new.assigned_by_membership_id is not null
      and (tg_op='INSERT'
        or old.assigned_by_membership_id is distinct from new.assigned_by_membership_id
        or old.state is distinct from new.state
        or old.organization_id is distinct from new.organization_id)
      and not exists (
        select 1 from atlas.organization_memberships om
        where om.id=new.assigned_by_membership_id
          and om.organization_id=new.organization_id and om.active
      ) then
      raise exception 'Active Work allocation cannot name an inactive assigning membership'
        using errcode='23514';
    end if;
  end if;
  return new;
end
$fn$;

create or replace function atlas.guard_work_allocation_canonical_person_immutability_v1()
returns trigger language plpgsql security definer set search_path to ''
as $fn$
begin
  if new.assignee_canonical_person_id is distinct from old.assignee_canonical_person_id then
    raise exception 'Canonical responsible Person cannot be rewritten; use governed transfer'
      using errcode='23514';
  end if;
  return new;
end
$fn$;
drop trigger if exists work_allocations_canonical_person_immutable_v1
  on atlas.work_allocations;
create trigger work_allocations_canonical_person_immutable_v1
  before update of assignee_canonical_person_id on atlas.work_allocations
  for each row execute function
  atlas.guard_work_allocation_canonical_person_immutability_v1();


CREATE OR REPLACE FUNCTION atlas.guard_work_allocation_responsibility_establishment_v2()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $fn$
declare
  v_source text:=coalesce(new.metadata->>'source','');
  v_requires_basis boolean:=false;
  v_kind text:=lower(btrim(coalesce(new.establishment_basis_kind,'')));
  v_basis jsonb:=new.establishment_basis;
begin
  if tg_op='UPDATE' then
    if new.establishment_basis_kind is distinct from old.establishment_basis_kind
       or new.establishment_basis is distinct from old.establishment_basis then
      raise exception 'Exact Work responsibility establishment provenance is immutable once the allocation exists.'
        using errcode='23514';
    end if;
  end if;

  if new.allocation_role<>'responsible' or new.state<>'active' then
    return new;
  end if;

  if tg_op='INSERT' then
    v_requires_basis:=true;
  elsif old.allocation_role is distinct from new.allocation_role
        or old.state is distinct from new.state
        or old.assignee_membership_id is distinct from new.assignee_membership_id then
    v_requires_basis:=true;
  end if;

  -- Existing historical active responsibility can be updated/released without
  -- fabricating a retrospective establishment basis.
  if not v_requires_basis
     and new.establishment_basis_kind is null
     and new.establishment_basis is null then
    return new;
  end if;

  -- Two transitional farm adapters remain live. New rows created by exactly
  -- those named carriers are normalized as governed legacy reconstruction
  -- without changing the adapters or backfilling historical rows.
  if new.establishment_basis_kind is null
     and v_source in (
       'legacy_weekly_harvest_occurrence_assignment',
       'explicit_worker_task_company_work_adoption_v2'
     ) then
    if v_source='legacy_weekly_harvest_occurrence_assignment'
       and (
         nullif(btrim(coalesce(new.metadata->>'plannedOccurrenceId','')),'') is null
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='planned_work_occurrence'
             and work.source_object_id::text=(new.metadata->>'plannedOccurrenceId')
         )
       ) then
      raise exception 'Weekly-harvest reconstruction requires the exact planned-occurrence Work source.'
        using errcode='23514';
    end if;
    if v_source='explicit_worker_task_company_work_adoption_v2'
       and (
         nullif(btrim(coalesce(new.metadata->>'legacyTaskId','')),'') is null
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='legacy_task'
             and work.source_object_id::text=(new.metadata->>'legacyTaskId')
         )
       ) then
      raise exception 'Legacy-task reconstruction requires the exact legacy-task Work source.'
        using errcode='23514';
    end if;

    new.establishment_basis_kind:='legacy_governed_reconstruction';
    new.establishment_basis:=jsonb_strip_nulls(jsonb_build_object(
      'contractVersion','exact_work_responsibility_establishment_v2',
      'basisKind','legacy_governed_reconstruction',
      'organizationId',new.organization_id,
      'workItemId',new.work_item_id,
      'assigneeMembershipId',new.assignee_membership_id,
      'legacySource',v_source,
      'legacyTaskId',new.metadata->>'legacyTaskId',
      'plannedOccurrenceId',new.metadata->>'plannedOccurrenceId',
      'normalizedAt',now()
    ));
    v_kind:=new.establishment_basis_kind;
    v_basis:=new.establishment_basis;
  end if;

  if new.establishment_basis_kind is null
     or new.establishment_basis is null
     or jsonb_typeof(new.establishment_basis)<>'object' then
    raise exception 'Active exact Work responsibility requires a governed establishment basis.'
      using errcode='23514';
  end if;

  v_kind:=lower(btrim(new.establishment_basis_kind));
  v_basis:=new.establishment_basis;

  if v_kind not in (
    'self_claim',
    'self_adoption',
    'self_initiated_outbound',
    'delegated_under_standing_scope',
    'legacy_governed_reconstruction',
    'person_connection_receiver_uptake'
  ) then
    raise exception 'Unsupported exact Work responsibility establishment basis: %.',v_kind
      using errcode='23514';
  end if;

  -- A Person-native receipt uses the same one-responsible-allocation table.
  -- Its source is an offered exact Work item, with receiver or witnessed
  -- uptake; no Organization Membership or employee classification is invented.
  if v_kind='person_connection_receiver_uptake' then
    if new.assignee_membership_id is not null
       or new.assignee_canonical_person_id is null
       or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
       or coalesce(v_basis->>'basisKind','')<>v_kind
       or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
       or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
       or coalesce(v_basis->>'targetPersonId','')<>new.assignee_canonical_person_id::text
       or coalesce(v_basis->>'nativeLedgerId','')=''
       or coalesce(v_basis->>'offerId','')=''
       or coalesce(v_basis->>'uptakeKind','') not in ('recipient_self_accepted','owner_witnessed_acceptance')
    then raise exception 'Exact Person-native receiver uptake provenance required' using errcode='23514';
    end if;
    if not exists(
      select 1 from atlas.company_work_initial_responsibility_offers o
      where o.id::text=v_basis->>'offerId'
        and o.work_item_id=new.work_item_id
        and o.organization_id=new.organization_id
        and o.target_person_id=new.assignee_canonical_person_id
        and o.ledger_id::text=v_basis->>'nativeLedgerId'
        and o.target_membership_id is null
        and o.offer_state in ('offered','accepted')
        and o.offered_by_membership_id=new.assigned_by_membership_id
    ) then raise exception 'Person-native responsibility must trace to the exact accepted offer' using errcode='23514';
    end if;
    if not atlas.person_has_native_ledger_connection_v1(
       new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
       new.assignee_canonical_person_id) then
      raise exception 'Responsible Person native Ledger connection no longer present' using errcode='23514';
    end if;
    if coalesce(v_basis->>'uptakeKind','')='owner_witnessed_acceptance'
      and (length(btrim(coalesce(v_basis->>'receiverConsentEvidence','')))<16
         or coalesce(v_basis->>'witnessPersonId','')='') then
      raise exception 'Owner-witnessed uptake must preserve specific external consent evidence' using errcode='23514';
    end if;
    return new;
  end if;

  if coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
     or coalesce(v_basis->>'basisKind','')<>v_kind
     or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
     or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
     or coalesce(v_basis->>'assigneeMembershipId','')<>new.assignee_membership_id::text then
    raise exception 'Responsibility establishment basis does not match the exact allocation.'
      using errcode='23514';
  end if;

  if v_kind in ('self_claim','self_adoption','self_initiated_outbound') then
    if new.assigned_by_membership_id is null
       or new.assigned_by_membership_id is distinct from new.assignee_membership_id then
      raise exception 'Self-established Work responsibility requires actor and assignee to be the same membership.'
        using errcode='23514';
    end if;
    if coalesce(v_basis->>'actorMembershipId','')<>new.assignee_membership_id::text
       or coalesce(v_basis->>'assigneeMembershipId','')<>new.assignee_membership_id::text then
      raise exception 'Self-establishment basis membership provenance does not match the allocation.'
        using errcode='23514';
    end if;
  end if;

  if v_kind='self_claim'
     and (
       nullif(btrim(coalesce(v_basis->>'institutionalConversationId','')),'') is null
       or nullif(btrim(coalesce(v_basis->>'responseCaseId','')),'') is null
     ) then
    raise exception 'Self-claim responsibility requires conversation and response-case provenance.'
      using errcode='23514';
  end if;

  if v_kind='self_adoption'
     and (
       nullif(btrim(coalesce(v_basis->>'sourceKind','')),'') is null
       or nullif(btrim(coalesce(v_basis->>'sourceId','')),'') is null
     ) then
    raise exception 'Self-adopted responsibility requires an exact source kind and source id.'
      using errcode='23514';
  end if;

  if v_kind='self_initiated_outbound'
     and nullif(btrim(coalesce(v_basis->>'outboundOperationId','')),'') is null then
    raise exception 'Self-initiated outbound responsibility requires outbound-operation provenance.'
      using errcode='23514';
  end if;


  if v_kind='delegated_under_standing_scope' then
    if new.assigned_by_membership_id is null
      or new.assigned_by_membership_id=new.assignee_membership_id
      or coalesce(v_basis->>'scopeId','')=''
      or coalesce(v_basis->>'nativeLedgerId','')=''
      or coalesce(v_basis->>'positionId','')=''
      or coalesce(v_basis->>'actorMembershipId','')<>new.assigned_by_membership_id::text
    then
      raise exception 'Delegated assignment requires exact accepted scope and distinct owner authority'
        using errcode='23514';
    end if;
    -- Never retroactively claim a worker consented. Validate the
    -- captured source and current authority when creating responsibility.
    if v_requires_basis and not exists(
      select 1 from atlas.company_work_standing_assignment_scopes scope
      join atlas.organization_memberships worker
        on worker.id=scope.worker_membership_id and worker.organization_id=scope.organization_id
      join atlas.organization_position_appointments appointment
        on appointment.id=scope.position_appointment_id and appointment.organization_membership_id=worker.id
      join atlas.organization_positions pos
        on pos.id=scope.position_id and pos.organization_id=scope.organization_id
      join atlas.work_items work
        on work.id=new.work_item_id and work.organization_id=scope.organization_id
      join atlas.company_work_native_ledger_relevance relevance
        on relevance.work_item_id=work.id and relevance.organization_id=scope.organization_id
      where scope.id::text=v_basis->>'scopeId'
        and scope.scope_state='active' and scope.accepted_at is not null
        and scope.revoked_at is null
        and (scope.valid_until is null or scope.valid_until>now())
        and scope.organization_id=new.organization_id
        and scope.worker_membership_id=new.assignee_membership_id
        and scope.ledger_id::text=v_basis->>'nativeLedgerId'
        and scope.position_id::text=v_basis->>'positionId'
        and scope.position_appointment_id=appointment.id
        and scope.accepted_by_person_id=worker.person_id
        and worker.active
        and atlas.organization_membership_present_effective_at_v1(worker.id,worker.organization_id,now())
        and appointment.status='active' and appointment.ends_at is null
        and pos.status='active' and pos.organization_unit_id=work.organization_unit_id
        and pos.organization_unit_id=scope.organization_unit_id
        and relevance.ledger_id=scope.ledger_id and relevance.attribution_state='active'
        and (relevance.evidence_kind='owner_attested' or
          (relevance.evidence_kind='source_verified' and exists(
            select 1 from atlas.company_work_native_ledger_exact_source_v1(work.id,scope.ledger_id) proof
             where proof.source_schema=relevance.source_schema
               and proof.source_table=relevance.source_table and proof.source_id=relevance.source_id
          )))
        and exists(select 1 from atlas.organization_memberships manager
          where manager.id=new.assigned_by_membership_id
            and manager.organization_id=new.organization_id and manager.active and manager.role='owner')
    ) then
      raise exception 'Accepted exact-Ledger connection agreement cannot be proved for this Work'
        using errcode='23514';
    end if;
  end if;

  if v_kind='legacy_governed_reconstruction' then
    if v_source not in (
         'legacy_weekly_harvest_occurrence_assignment',
         'explicit_worker_task_company_work_adoption_v2'
       )
       or coalesce(v_basis->>'legacySource','')<>v_source then
      raise exception 'Legacy reconstruction basis is limited to the two named transitional carriers.'
        using errcode='23514';
    end if;

    if v_source='legacy_weekly_harvest_occurrence_assignment'
       and (
         coalesce(v_basis->>'plannedOccurrenceId','')<>coalesce(new.metadata->>'plannedOccurrenceId','')
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='planned_work_occurrence'
             and work.source_object_id::text=(v_basis->>'plannedOccurrenceId')
         )
       ) then
      raise exception 'Legacy weekly-harvest responsibility basis does not match the exact Work source.'
        using errcode='23514';
    end if;

    if v_source='explicit_worker_task_company_work_adoption_v2'
       and (
         coalesce(v_basis->>'legacyTaskId','')<>coalesce(new.metadata->>'legacyTaskId','')
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='legacy_task'
             and work.source_object_id::text=(v_basis->>'legacyTaskId')
         )
       ) then
      raise exception 'Legacy task responsibility basis does not match the exact Work source.'
        using errcode='23514';
    end if;
  end if;

  new.establishment_basis_kind:=v_kind;
  return new;
end;
$fn$;

CREATE OR REPLACE FUNCTION atlas.sync_production_company_work_responsibility_carrier_v1(p_work_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $fn$
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


  -- Person-native responsibility is real, but never smuggles a synthetic
  -- employee/farm membership into the historical execution carrier.
  if v_allocation.assignee_membership_id is null
    and v_allocation.establishment_basis_kind='person_connection_receiver_uptake' then
    update atlas.planned_work_occurrences
    set task_payload=(coalesce(task_payload,'{}'::jsonb)
        - 'assigned_membership_id' - 'assigned_user_id')
       ||jsonb_build_object('visibility_scope','system_internal')
       ||jsonb_build_object('metadata',
          coalesce(task_payload->'metadata','{}'::jsonb)
          ||jsonb_build_object('responsibility_state','person_native_assigned',
             'responsibility_authority','work_allocations',
             'company_work_allocation_id',v_allocation.id,
             'legacy_assignment_suppressed',true)),
      updated_at=now()
    where id=v_occ.id;
    if v_adapter.task_id is not null then
      update atlas.tasks set assigned_membership_id=null,assigned_user_id=null,
        visibility_scope='system_internal',
        metadata=coalesce(metadata,'{}'::jsonb)
          ||jsonb_build_object('responsibility_state','person_native_assigned',
             'responsibility_authority','work_allocations',
             'company_work_allocation_id',v_allocation.id,
             'legacy_assignment_suppressed',true),
        updated_at=now()
      where id=v_adapter.task_id and status in ('open','blocked');
    end if;
    update atlas.work_execution_adapters
      set metadata=coalesce(metadata,'{}'::jsonb)
        ||jsonb_build_object('executionCarrierDeliveryState','person_native_today',
          'responsibilityAuthority','work_allocations',
          'companyWorkAllocationId',v_allocation.id,
          'carrierAssignmentIsResponsibilityEvidence',false),
        updated_at=now()
    where id=v_adapter.id;
    update atlas.work_planning_conflicts
      set state='resolved',resolution_kind='person_native_delivery',
        resolution_note='Canonical Person owns this Work; no fake employee carrier was created.',
        resolved_at=now(),updated_at=now()
    where organization_id=v_work.organization_id and work_item_id=v_work.id
      and state='open'
      and metadata->>'source'='company_work_execution_carrier_membership';
    perform atlas.materialize_production_bed_preparation_company_work_v1(
      v_work.source_object_id,null);
    return jsonb_build_object('state','person_native_today',
      'workItemId',v_work.id,'allocationId',v_allocation.id,
      'personId',v_allocation.assignee_canonical_person_id,
      'legacyEmployeeCarrierCreated',false);
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
$fn$;

CREATE OR REPLACE FUNCTION atlas.reconcile_company_work_execution_plan_responsibility_v1(p_work_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $fn$
declare
  v_plan atlas.work_execution_plans%rowtype;
  v_allocation atlas.work_allocations%rowtype;
begin
  select * into v_plan from atlas.work_execution_plans
  where work_item_id=p_work_item_id and plan_state in ('active','needs_replan') limit 1 for update;
  select * into v_allocation from atlas.work_allocations
  where work_item_id=p_work_item_id and state='active' and allocation_role='responsible' limit 1;

  if v_plan.id is not null and v_plan.plan_state='active'
     and (v_allocation.id is null or v_plan.responsible_allocation_id is distinct from v_allocation.id or v_plan.assignee_membership_id is distinct from v_allocation.assignee_membership_id) then
    update atlas.work_execution_plans set plan_state='needs_replan',plan_reason='Responsibility changed; the old worker-day plan was preserved as history but is no longer executable.' where id=v_plan.id;
    insert into atlas.work_execution_plan_events(
      organization_id,work_item_id,plan_id,event_kind,from_planned_service_date,to_planned_service_date,
      from_exposure_service_date,to_exposure_service_date,reason,metadata
    ) values(v_plan.organization_id,v_plan.work_item_id,v_plan.id,'needs_replan',v_plan.planned_service_date,v_plan.planned_service_date,
      v_plan.exposure_service_date,v_plan.exposure_service_date,'Responsibility changed; manager re-planning is required.',
      jsonb_strip_nulls(jsonb_build_object('priorAllocationId',v_plan.responsible_allocation_id,'currentAllocationId',v_allocation.id)));
  end if;
  perform atlas.sync_company_work_execution_plan_carrier_v1(p_work_item_id);
  return jsonb_build_object('workItemId',p_work_item_id,'planId',v_plan.id,'allocationId',v_allocation.id);
end;
$fn$;


-- People may be invited because they have an exact native Ledger seat, without
-- inventing an employee, credential, or duplicate Work object.
create or replace function atlas.offer_connected_person_company_work_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_target_canonical_person_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
declare
  v_owner uuid;
  v_member uuid;
  v_work atlas.work_items%rowtype;
  v_existing atlas.company_work_initial_responsibility_offers%rowtype;
  v_created atlas.company_work_initial_responsibility_offers%rowtype;
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
begin
  if auth.uid() is null or p_work_item_id is null or p_target_canonical_person_id is null
    or v_reason is null or length(v_reason) not between 8 and 1200 then
    raise exception 'Exact Work, canonical Person and offer reason required' using errcode='22023';
  end if;
  v_owner:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
  v_member:=atlas.current_effective_organization_membership_v1(p_organization_id);
  if not exists(select 1 from atlas.organization_memberships m
    where m.id=v_member and m.organization_id=p_organization_id
      and m.person_id=v_owner and m.active and m.role='owner') then
    raise exception 'Root owner organization membership required' using errcode='42501';
  end if;
  if p_target_canonical_person_id=v_owner then
    raise exception 'Owner must self-adopt own Work' using errcode='22023';
  end if;
  if not atlas.person_has_native_ledger_connection_v1(
    p_organization_id,p_ledger_id,p_target_canonical_person_id) then
    raise exception 'Person lacks an active exact Ledger connection' using errcode='23514';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.responsibility:'||p_work_item_id,0));
  select * into v_work from atlas.work_items
    where id=p_work_item_id and organization_id=p_organization_id for update;
  if v_work.id is null or v_work.work_state<>'open' then
    raise exception 'Existing open Company Work required' using errcode='23514';
  end if;
  if not exists (select 1 from atlas.company_work_native_ledger_relevance rel
    where rel.organization_id=p_organization_id and rel.work_item_id=v_work.id
      and rel.ledger_id=p_ledger_id and rel.attribution_state='active'
      and (rel.evidence_kind='owner_attested' or
        (rel.evidence_kind='source_verified' and exists(
          select 1 from atlas.company_work_native_ledger_exact_source_v1(
            v_work.id,p_ledger_id) proof
          where proof.source_schema=rel.source_schema
            and proof.source_table=rel.source_table and proof.source_id=rel.source_id)))) then
    raise exception 'Exact native Ledger Work relevance not proven' using errcode='23514';
  end if;
  if exists(select 1 from atlas.work_allocations a
    where a.work_item_id=v_work.id and a.state='active'
      and a.allocation_role='responsible') then
    raise exception 'Already assigned Work requires governed transfer' using errcode='23514';
  end if;
  select * into v_existing from atlas.company_work_initial_responsibility_offers o
    where o.work_item_id=v_work.id and o.offer_state='offered'
    for update;
  if v_existing.id is not null then
    if v_existing.target_person_id is distinct from p_target_canonical_person_id
      or v_existing.ledger_id is distinct from p_ledger_id
      or v_existing.target_membership_id is not null then
      raise exception 'Another exact Work offer remains pending' using errcode='23505';
    end if;
    return jsonb_build_object('ok',true,'contractVersion','person_connection_work_offer_v1',
      'state','offered','alreadyOffered',true,'offerId',v_existing.id,
      'workItemId',v_work.id,'responsibilityChanged',false);
  end if;
  insert into atlas.company_work_initial_responsibility_offers(
    organization_id,work_item_id,ledger_id,offered_by_person_id,
    offered_by_membership_id,target_person_id,target_membership_id,reason
  ) values(
    p_organization_id,v_work.id,p_ledger_id,v_owner,v_member,
    p_target_canonical_person_id,null,v_reason
  ) returning * into v_created;
  return jsonb_build_object('ok',true,'contractVersion','person_connection_work_offer_v1',
    'state','offered','alreadyOffered',false,'offerId',v_created.id,
    'workItemId',v_work.id,'targetPersonId',p_target_canonical_person_id,
    'responsibilityChanged',false,'loginRequiredToHoldSeat',false,
    'receiverConsentRecorded',false);
end
$fn$;
revoke all on function atlas.offer_connected_person_company_work_owner_self_api_v1(
  uuid,uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function atlas.offer_connected_person_company_work_owner_self_api_v1(
  uuid,uuid,uuid,uuid,text) to authenticated;

create or replace function atlas.establish_connected_person_company_work_from_offer_v1(
  p_offer_id uuid,p_uptake_kind text,p_consent_evidence text,p_witness_person_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
declare
  v_offer atlas.company_work_initial_responsibility_offers%rowtype;
  v_work atlas.work_items%rowtype;
  v_new atlas.work_allocations%rowtype;
  v_owner_id uuid;
  v_contract text:='ordinary_company_work_worker_attestation_v1';
  v_evidence text:=nullif(btrim(coalesce(p_consent_evidence,'')),'');
  v_kind text:=lower(btrim(coalesce(p_uptake_kind,'')));
begin
  -- Internal helper called only by authenticated receiver/owner-witness APIs.
  if v_kind not in ('recipient_self_accepted','owner_witnessed_acceptance')
    or (v_kind='owner_witnessed_acceptance'
      and (v_evidence is null or length(v_evidence) not between 16 and 2000
        or p_witness_person_id is null)) then
    raise exception 'Exact receiver uptake and external evidence required' using errcode='22023';
  end if;
  select * into v_offer from atlas.company_work_initial_responsibility_offers
    where id=p_offer_id for update;
  if v_offer.id is null or v_offer.offer_state<>'offered'
    or v_offer.target_membership_id is not null then
    raise exception 'Pending Person-native offer required' using errcode='23514';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.responsibility:'||v_offer.work_item_id,0));
  select * into v_work from atlas.work_items
    where id=v_offer.work_item_id and organization_id=v_offer.organization_id
    for update;
  if v_work.id is null or v_work.work_state<>'open'
    or not atlas.person_has_native_ledger_connection_v1(
      v_offer.organization_id,v_offer.ledger_id,v_offer.target_person_id) then
    raise exception 'Work or exact Ledger connection changed before uptake' using errcode='23514';
  end if;
  if exists(select 1 from atlas.work_allocations a
    where a.work_item_id=v_work.id and a.allocation_role='responsible'
      and a.state='active') then
    raise exception 'Another Person already owns this Work' using errcode='23514';
  end if;
  if not exists(select 1 from atlas.company_work_native_ledger_relevance rel
    where rel.organization_id=v_work.organization_id
      and rel.work_item_id=v_work.id and rel.ledger_id=v_offer.ledger_id
      and rel.attribution_state='active'
      and (rel.evidence_kind='owner_attested' or
        (rel.evidence_kind='source_verified' and exists(
          select 1 from atlas.company_work_native_ledger_exact_source_v1(
            v_work.id,v_offer.ledger_id) proof
          where proof.source_schema=rel.source_schema
            and proof.source_table=rel.source_table and proof.source_id=rel.source_id)))) then
    raise exception 'Offered Work source no longer matches native Ledger' using errcode='23514';
  end if;
  -- Ordinary existing Work can carry a reportable worker-attestation policy.
  -- Never replace an existing source-specific result contract.
  if v_work.result_contract_key is null and
    v_work.source_object_type in ('personal_dated_task','legacy_task') then
    if not exists(select 1 from atlas.work_result_contract_policies policy
      where policy.contract_key=v_contract and policy.active
        and policy.source_domain='organization'
        and policy.acceptance_mode='worker_attestation') then
      raise exception 'Ordinary Company Work result policy unavailable' using errcode='23514';
    end if;
    insert into atlas.company_work_result_contract_bindings_v1(
      organization_id,ledger_id,work_item_id,actor_person_id,
      actor_membership_id,contract_key,reason
    ) values(v_work.organization_id,v_offer.ledger_id,v_work.id,
      v_offer.offered_by_person_id,v_offer.offered_by_membership_id,v_contract,
      'Person-native receiver accepted an existing Company Work offer');
    update atlas.work_items set result_contract_key=v_contract,updated_at=now()
      where id=v_work.id and result_contract_key is null;
  end if;
  insert into atlas.work_allocations(
    organization_id,work_item_id,assignee_membership_id,
    assignee_canonical_person_id,assigned_by_membership_id,
    allocation_role,state,allocated_at,establishment_basis_kind,
    establishment_basis,metadata
  ) values(
    v_work.organization_id,v_work.id,null,v_offer.target_person_id,
    v_offer.offered_by_membership_id,'responsible','active',now(),
    'person_connection_receiver_uptake',
    jsonb_strip_nulls(jsonb_build_object(
      'contractVersion','exact_work_responsibility_establishment_v2',
      'basisKind','person_connection_receiver_uptake',
      'organizationId',v_work.organization_id,'workItemId',v_work.id,
      'targetPersonId',v_offer.target_person_id,
      'nativeLedgerId',v_offer.ledger_id,'offerId',v_offer.id,
      'uptakeKind',v_kind,'witnessPersonId',p_witness_person_id,
      'receiverConsentEvidence',v_evidence,'acceptedAt',now(),
      'evidenceTrust','owner_attested_not_independently_verified')),
    jsonb_build_object('source','establish_connected_person_company_work_from_offer_v1',
      'offerId',v_offer.id,'canonicalPersonCarrier',true,
      'employeeSeatRequired',false,'consentKind',v_kind)
  ) returning * into v_new;
  update atlas.company_work_initial_responsibility_offers
    set offer_state='accepted',resolved_at=now(),
      accepted_allocation_id=v_new.id,
      resolution_reason=case when v_kind='recipient_self_accepted'
        then 'recipient_accepted_person_connection_offer'
        else 'owner_witnessed_external_receiver_consent' end
    where id=v_offer.id;
  return jsonb_build_object(
    'ok',true,'contractVersion','person_connection_work_uptake_v1',
    'state','accepted','workItemId',v_work.id,'allocationId',v_new.id,
    'offerId',v_offer.id,'responsiblePersonId',v_offer.target_person_id,
    'responsibilityChanged',true,'uptakeKind',v_kind,
    'workerDayPlanCreated',false,'newWorkCreated',false,
    'employeeSeatRequired',false,'resultContractKey',
      (select result_contract_key from atlas.work_items where id=v_work.id));
end
$fn$;
revoke all on function atlas.establish_connected_person_company_work_from_offer_v1(
  uuid,text,text,uuid) from public,anon,authenticated,service_role;

create or replace function atlas.respond_connected_person_company_work_self_api_v1(
  p_offer_id uuid,p_decision text)
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
declare
  v_self uuid:=atlas.current_person_id_v1();
  v_offer atlas.company_work_initial_responsibility_offers%rowtype;
  v_decision text:=lower(btrim(coalesce(p_decision,'')));
begin
  if auth.uid() is null or v_self is null then
    raise exception 'Signed-in canonical Person required' using errcode='42501';
  end if;
  if p_offer_id is null or v_decision not in ('accepted','declined') then
    raise exception 'Accept or decline exact offered Work' using errcode='22023';
  end if;
  select * into v_offer from atlas.company_work_initial_responsibility_offers
    where id=p_offer_id for update;
  if v_offer.id is null or v_offer.target_person_id<>v_self
    or v_offer.target_membership_id is not null then
    raise exception 'Offer is not for current canonical Person' using errcode='42501';
  end if;
  if v_offer.offer_state<>'offered' then
    if v_offer.offer_state=v_decision then
      return jsonb_build_object('ok',true,'state',v_decision,
        'offerId',v_offer.id,'alreadyResolved',true,
        'allocationId',v_offer.accepted_allocation_id);
    end if;
    raise exception 'Offer already resolved' using errcode='23514';
  end if;
  if v_decision='declined' then
    update atlas.company_work_initial_responsibility_offers
      set offer_state='declined',resolved_at=now(),
        resolution_reason='person_connection_receiver_declined'
      where id=v_offer.id;
    return jsonb_build_object('ok',true,'state','declined','offerId',v_offer.id,
      'responsibilityChanged',false);
  end if;
  return atlas.establish_connected_person_company_work_from_offer_v1(
    p_offer_id,'recipient_self_accepted',null,null);
end
$fn$;
revoke all on function atlas.respond_connected_person_company_work_self_api_v1(
  uuid,text) from public,anon,authenticated,service_role;
grant execute on function atlas.respond_connected_person_company_work_self_api_v1(
  uuid,text) to authenticated;

-- No account is inferred or impersonated. The owner is explicitly the witness,
-- receiver's consent remains an attributed claim and may be disputed later.
create or replace function atlas.witness_connected_person_company_work_uptake_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_offer_id uuid,
  p_receiver_consent_evidence text)
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
declare
  v_owner uuid;
  v_offer atlas.company_work_initial_responsibility_offers%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  select * into v_offer from atlas.company_work_initial_responsibility_offers
    where id=p_offer_id for update;
  if v_offer.id is null or v_offer.organization_id<>p_organization_id
     or v_offer.ledger_id<>p_ledger_id
     or v_offer.target_person_id=v_owner then
    raise exception 'Exact other-Person offer on governed Ledger required' using errcode='42501';
  end if;
  return atlas.establish_connected_person_company_work_from_offer_v1(
    p_offer_id,'owner_witnessed_acceptance',p_receiver_consent_evidence,v_owner);
end
$fn$;
revoke all on function atlas.witness_connected_person_company_work_uptake_owner_self_api_v1(
  uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function atlas.witness_connected_person_company_work_uptake_owner_self_api_v1(
  uuid,uuid,uuid,text) to authenticated;


create or replace function atlas.connected_person_company_work_today_self_api_v1(
  p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
declare
  v_self uuid:=atlas.current_person_id_v1();
  v_items jsonb:='[]'::jsonb;
begin
  if auth.uid() is null or v_self is null then
    raise exception 'Signed-in canonical Person required' using errcode='42501';
  end if;
  if p_limit not between 1 and 100 then
    raise exception 'Page size must be between 1 and 100' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'workItemId',row.work_id,'allocationId',row.allocation_id,
    'organizationId',row.organization_id,'ledgerId',row.ledger_id,
    'title',row.title,'instructions',row.instructions,
    'sourceType',row.source_type,'sourceId',row.source_id,
    'sourceDate',row.source_date,'sourceDateIsNotScheduledDay',true,
    'resultContractKey',row.result_contract,
    'canReportOrdinaryCompletion',row.result_contract=
      'ordinary_company_work_worker_attestation_v1',
    'uptakeKind',row.uptake_kind,'employeeSeatRequired',false)
    order by row.allocated_at,row.work_id),'[]'::jsonb) into v_items
  from (
    select w.id work_id,a.id allocation_id,w.organization_id,
      (a.establishment_basis->>'nativeLedgerId')::uuid ledger_id,
      w.title,w.instructions,w.source_object_type source_type,
      w.source_object_id source_id,
      case when w.metadata->>'originalServiceDate' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        then w.metadata->>'originalServiceDate' else null end source_date,
      w.result_contract_key result_contract,
      a.establishment_basis->>'uptakeKind' uptake_kind,a.allocated_at
    from atlas.work_allocations a
    join atlas.work_items w on w.id=a.work_item_id
      and w.organization_id=a.organization_id
    where a.allocation_role='responsible' and a.state='active'
      and a.assignee_canonical_person_id=v_self
      and a.establishment_basis_kind='person_connection_receiver_uptake'
      and w.work_state='open'
    order by a.allocated_at,a.id
    limit p_limit
  ) row;
  return jsonb_build_object('ok',true,
    'contractVersion','connected_person_company_work_today_v1',
    'personId',v_self,'items',v_items,
    'sourceDateIsNotAWorkSchedule',true,'employeeSeatRequired',false);
end
$fn$;
revoke all on function atlas.connected_person_company_work_today_self_api_v1(integer)
  from public,anon,authenticated,service_role;
grant execute on function atlas.connected_person_company_work_today_self_api_v1(integer)
  to authenticated;

create or replace function atlas.connected_person_company_work_offers_self_api_v1()
returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
declare
  v_self uuid:=atlas.current_person_id_v1();
  v_items jsonb:='[]'::jsonb;
begin
  if auth.uid() is null or v_self is null then
    raise exception 'Signed-in canonical Person required' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'offerId',o.id,'workItemId',o.work_item_id,'workTitle',w.title,
    'organizationId',o.organization_id,'ledgerId',o.ledger_id,
    'offeredByPersonId',o.offered_by_person_id,'offeredAt',o.offered_at,
    'reason',o.reason,'state','offered','notAssignedYet',true)
    order by o.offered_at,o.id),'[]'::jsonb) into v_items
  from atlas.company_work_initial_responsibility_offers o
  join atlas.work_items w on w.id=o.work_item_id
    and w.organization_id=o.organization_id
  where o.target_person_id=v_self and o.target_membership_id is null
    and o.offer_state='offered';
  return jsonb_build_object('ok',true,
    'contractVersion','connected_person_company_work_offers_v1',
    'items',v_items,'acceptanceRequired',true,
    'accountlessPersonsCanHoldPendingOffer',true);
end
$fn$;
revoke all on function atlas.connected_person_company_work_offers_self_api_v1()
  from public,anon,authenticated,service_role;
grant execute on function atlas.connected_person_company_work_offers_self_api_v1()
  to authenticated;

-- This recorder separates the Person who did the Work from the authenticated
-- Person making the report; the evidence is immutable and idempotent.
create or replace function atlas.report_connected_person_company_work_internal_v1(
  p_work_item_id uuid,p_result_kind text,p_idempotency_key text,
  p_payload jsonb,p_mode text,p_owner_ledger_id uuid,p_witness_evidence text)
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
declare
  v_uid uuid:=auth.uid();
  v_actor uuid:=atlas.current_person_id_v1();
  v_kind text:=lower(btrim(coalesce(p_result_kind,'')));
  v_mode text:=lower(btrim(coalesce(p_mode,'')));
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_evidence text:=nullif(btrim(coalesce(p_witness_evidence,'')),'');
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_existing atlas.work_execution_results%rowtype;
  v_result atlas.work_execution_results%rowtype;
  v_acceptance atlas.work_result_acceptances%rowtype;
  v_reporter_ipr uuid;
begin
  if v_uid is null or v_actor is null then
    raise exception 'Signed-in canonical reporting Person required' using errcode='42501';
  end if;
  if p_work_item_id is null or v_kind not in ('completed','partial','blocked','unable')
    or v_mode not in ('own_work','owner_witness')
    or v_key is null or length(v_key)>160
    or p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'Exact Work, result, mode, idempotency and object payload required'
      using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.responsibility:'||p_work_item_id,0));
  select * into v_work from atlas.work_items
    where id=p_work_item_id for update;
  if v_work.id is null then raise exception 'Company Work not found' using errcode='P0002'; end if;
  select * into v_allocation from atlas.work_allocations a
    where a.work_item_id=v_work.id and a.organization_id=v_work.organization_id
      and a.allocation_role='responsible'
      and a.establishment_basis_kind='person_connection_receiver_uptake'
      and a.state in ('active','completed')
    order by a.allocated_at desc limit 1;
  if v_allocation.id is null then
    raise exception 'Exact Person-native responsible allocation not found' using errcode='23514';
  end if;
  if v_mode='own_work' then
    if v_allocation.assignee_canonical_person_id<>v_actor then
      raise exception 'Only actual responsible Person can make own-work report' using errcode='42501';
    end if;
  else
    if v_evidence is null or length(v_evidence) not between 16 and 2000
      or (v_allocation.establishment_basis->>'nativeLedgerId') is distinct from
        p_owner_ledger_id::text
      or atlas.company_work_native_ledger_owner_self_v1(
        v_work.organization_id,p_owner_ledger_id)<>v_actor then
      raise exception 'Owner report requires exact Ledger and detailed external evidence'
        using errcode='42501';
    end if;
  end if;
  select * into v_existing from atlas.work_execution_results r
    where r.organization_id=v_work.organization_id and r.idempotency_key=v_key;
  if v_existing.id is not null then
    if v_existing.work_item_id<>v_work.id or v_existing.result_kind<>v_kind
      or v_existing.responsible_allocation_id<>v_allocation.id
      or v_existing.metadata->>'reportMode'<>v_mode then
      raise exception 'Result idempotency collision' using errcode='23505';
    end if;
    return jsonb_build_object('ok',true,'idempotent',true,
      'resultId',v_existing.id,'workItemId',v_work.id,
      'workState',v_work.work_state);
  end if;
  if v_work.work_state<>'open' or v_allocation.state<>'active' then
    raise exception 'Terminal Work cannot receive another result' using errcode='23514';
  end if;
  if v_work.result_contract_key<>'ordinary_company_work_worker_attestation_v1'
    or not exists(select 1 from atlas.work_result_contract_policies p
      where p.contract_key=v_work.result_contract_key and p.active
        and p.acceptance_mode='worker_attestation'
        and p.source_domain='organization') then
    raise exception 'Source-specific Work requires its authorized result channel'
      using errcode='23514';
  end if;
  select ipr.id into v_reporter_ipr
    from atlas.institutional_person_records ipr
    where ipr.organization_id=v_work.organization_id
      and ipr.person_id=v_actor and ipr.status='active'
    order by ipr.created_at limit 1;
  insert into atlas.work_execution_results(
    organization_id,work_item_id,responsible_allocation_id,
    reported_by_user_id,reported_by_organization_membership_id,
    reported_by_institutional_person_record_id,
    result_kind,result_contract_key,idempotency_key,payload,metadata
  ) values(
    v_work.organization_id,v_work.id,v_allocation.id,
    v_uid,null,v_reporter_ipr,
    v_kind,v_work.result_contract_key,v_key,
    p_payload||jsonb_strip_nulls(jsonb_build_object(
      'claimedPerformerPersonId',v_allocation.assignee_canonical_person_id,
      'ownerWitnessEvidence',case when v_mode='owner_witness'
        then v_evidence else null end)),
    jsonb_build_object('source','report_connected_person_company_work_internal_v1',
      'reportMode',v_mode,'authenticatedReporterPersonId',v_actor,
      'canonicalResponsiblePersonId',v_allocation.assignee_canonical_person_id,
      'performanceIsWitnessedClaim',v_mode='owner_witness',
      'employeeSeatRequired',false)
  ) returning * into v_result;
  if v_kind='completed' then
    insert into atlas.work_result_acceptances(
      organization_id,work_item_id,execution_result_id,
      decision,acceptance_kind,accepted_by_domain,evidence,metadata
    ) values (
      v_work.organization_id,v_work.id,v_result.id,'accepted',
      case when v_mode='own_work' then 'self_responsible_person_attestation'
        else 'owner_witnessed_person_result' end,
      'organization',
      jsonb_strip_nulls(jsonb_build_object(
        'responsibleAllocationId',v_allocation.id,
        'canonicalResponsiblePersonId',v_allocation.assignee_canonical_person_id,
        'authenticatedReporterPersonId',v_actor,
        'ownerWitnessEvidence',case when v_mode='owner_witness'
          then v_evidence else null end)),
      jsonb_build_object('source','report_connected_person_company_work_internal_v1',
        'reportMode',v_mode,'notAnEmployeeWorkerDayReport',true)
    ) returning * into v_acceptance;
    update atlas.work_items
      set work_state='completed',completed_at=coalesce(completed_at,now()),
        updated_at=now()
      where id=v_work.id and work_state='open';
    update atlas.work_allocations
      set state='completed',completed_at=coalesce(completed_at,now()),
        updated_at=now()
      where id=v_allocation.id and state='active';
  end if;
  return jsonb_build_object('ok',true,'idempotent',false,
    'contractVersion','connected_person_company_work_result_v1',
    'workItemId',v_work.id,'resultId',v_result.id,
    'resultKind',v_kind,'workState',
      case when v_kind='completed' then 'completed' else 'open' end,
    'acceptanceDecision',v_acceptance.decision,
    'reportMode',v_mode,'responsiblePersonId',
      v_allocation.assignee_canonical_person_id,
    'reporterPersonId',v_actor,'sourceHistoryPreserved',true);
end
$fn$;
revoke all on function atlas.report_connected_person_company_work_internal_v1(
  uuid,text,text,jsonb,text,uuid,text) from public,anon,authenticated,service_role;

create or replace function atlas.report_connected_person_company_work_self_api_v1(
  p_work_item_id uuid,p_result_kind text,p_idempotency_key text,
  p_payload jsonb default '{}'::jsonb)
returns jsonb language sql security definer set search_path to ''
as $fn$
  select atlas.report_connected_person_company_work_internal_v1(
    p_work_item_id,p_result_kind,p_idempotency_key,p_payload,
    'own_work',null,null)
$fn$;
revoke all on function atlas.report_connected_person_company_work_self_api_v1(
  uuid,text,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function atlas.report_connected_person_company_work_self_api_v1(
  uuid,text,text,jsonb) to authenticated;

create or replace function atlas.witness_connected_person_company_work_result_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_result_kind text,p_idempotency_key text,p_evidence text)
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
begin
  if p_organization_id is null or p_work_item_id is null then
    raise exception 'Exact Organization and Work required' using errcode='22023';
  end if;
  if not exists(select 1 from atlas.work_items w
    where w.id=p_work_item_id and w.organization_id=p_organization_id) then
    raise exception 'Work not part of stated Organization' using errcode='42501';
  end if;
  perform atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  return atlas.report_connected_person_company_work_internal_v1(
    p_work_item_id,p_result_kind,p_idempotency_key,'{}'::jsonb,
    'owner_witness',p_ledger_id,p_evidence);
end
$fn$;
revoke all on function atlas.witness_connected_person_company_work_result_owner_self_api_v1(
  uuid,uuid,uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function atlas.witness_connected_person_company_work_result_owner_self_api_v1(
  uuid,uuid,uuid,text,text,text) to authenticated;


-- Thin SECURITY INVOKER RPCs keep PostgREST-facing interfaces explicit.
create or replace function public.offer_connected_person_company_work_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_target_canonical_person_id uuid,p_reason text)
returns jsonb language sql security invoker set search_path to ''
as $fn$
 select atlas.offer_connected_person_company_work_owner_self_api_v1(
   p_organization_id,p_ledger_id,p_work_item_id,p_target_canonical_person_id,p_reason)
$fn$;
revoke all on function public.offer_connected_person_company_work_owner_self_api_v1(
  uuid,uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.offer_connected_person_company_work_owner_self_api_v1(
  uuid,uuid,uuid,uuid,text) to authenticated;

create or replace function public.respond_connected_person_company_work_self_api_v1(
  p_offer_id uuid,p_decision text)
returns jsonb language sql security invoker set search_path to ''
as $fn$
 select atlas.respond_connected_person_company_work_self_api_v1(
   p_offer_id,p_decision)
$fn$;
revoke all on function public.respond_connected_person_company_work_self_api_v1(
  uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.respond_connected_person_company_work_self_api_v1(
  uuid,text) to authenticated;

create or replace function public.witness_connected_person_company_work_uptake_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_offer_id uuid,
  p_receiver_consent_evidence text)
returns jsonb language sql security invoker set search_path to ''
as $fn$
 select atlas.witness_connected_person_company_work_uptake_owner_self_api_v1(
   p_organization_id,p_ledger_id,p_offer_id,p_receiver_consent_evidence)
$fn$;
revoke all on function public.witness_connected_person_company_work_uptake_owner_self_api_v1(
  uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.witness_connected_person_company_work_uptake_owner_self_api_v1(
  uuid,uuid,uuid,text) to authenticated;

create or replace function public.connected_person_company_work_today_self_api_v1(
  p_limit integer default 100)
returns jsonb language sql stable security invoker set search_path to ''
as $fn$
 select atlas.connected_person_company_work_today_self_api_v1(p_limit)
$fn$;
revoke all on function public.connected_person_company_work_today_self_api_v1(
  integer) from public,anon,authenticated,service_role;
grant execute on function public.connected_person_company_work_today_self_api_v1(
  integer) to authenticated;

create or replace function public.connected_person_company_work_offers_self_api_v1()
returns jsonb language sql stable security invoker set search_path to ''
as $fn$
 select atlas.connected_person_company_work_offers_self_api_v1()
$fn$;
revoke all on function public.connected_person_company_work_offers_self_api_v1()
  from public,anon,authenticated,service_role;
grant execute on function public.connected_person_company_work_offers_self_api_v1()
  to authenticated;

create or replace function public.report_connected_person_company_work_self_api_v1(
  p_work_item_id uuid,p_result_kind text,p_idempotency_key text,
  p_payload jsonb default '{}'::jsonb)
returns jsonb language sql security invoker set search_path to ''
as $fn$
 select atlas.report_connected_person_company_work_self_api_v1(
   p_work_item_id,p_result_kind,p_idempotency_key,p_payload)
$fn$;
revoke all on function public.report_connected_person_company_work_self_api_v1(
  uuid,text,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.report_connected_person_company_work_self_api_v1(
  uuid,text,text,jsonb) to authenticated;

create or replace function public.witness_connected_person_company_work_result_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_result_kind text,p_idempotency_key text,p_evidence text)
returns jsonb language sql security invoker set search_path to ''
as $fn$
 select atlas.witness_connected_person_company_work_result_owner_self_api_v1(
   p_organization_id,p_ledger_id,p_work_item_id,p_result_kind,
   p_idempotency_key,p_evidence)
$fn$;
revoke all on function public.witness_connected_person_company_work_result_owner_self_api_v1(
  uuid,uuid,uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.witness_connected_person_company_work_result_owner_self_api_v1(
  uuid,uuid,uuid,text,text,text) to authenticated;


commit;
