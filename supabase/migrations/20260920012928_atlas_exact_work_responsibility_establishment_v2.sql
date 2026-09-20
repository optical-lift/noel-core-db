begin;

alter table atlas.work_allocations
  add column establishment_basis_kind text,
  add column establishment_basis jsonb;

alter table atlas.work_allocations
  add constraint work_allocations_establishment_basis_shape_check
  check (
    (
      allocation_role<>'responsible'
      and establishment_basis_kind is null
      and establishment_basis is null
    )
    or (
      allocation_role='responsible'
      and (
        (establishment_basis_kind is null and establishment_basis is null)
        or (
          establishment_basis_kind is not null
          and establishment_basis is not null
          and jsonb_typeof(establishment_basis)='object'
        )
      )
    )
  );

comment on column atlas.work_allocations.establishment_basis_kind is
'Governing basis that established this exact active responsible allocation. Historical rows may remain null rather than receiving invented provenance.';

comment on column atlas.work_allocations.establishment_basis is
'Structured provenance for exact Work responsibility establishment. Responsibility basis is distinct from routing, planning, visibility, and execution warrant.';

create or replace function atlas.guard_work_allocation_responsibility_establishment_v2()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
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
    'legacy_governed_reconstruction'
  ) then
    raise exception 'Unsupported exact Work responsibility establishment basis: %.',v_kind
      using errcode='23514';
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
$function$;

drop trigger if exists work_allocations_responsibility_establishment_guard_v2
  on atlas.work_allocations;

create trigger work_allocations_responsibility_establishment_guard_v2
before insert or update of allocation_role,state,assignee_membership_id,assigned_by_membership_id,establishment_basis_kind,establishment_basis
on atlas.work_allocations
for each row
execute function atlas.guard_work_allocation_responsibility_establishment_v2();

create or replace function atlas.set_company_work_responsibility_with_basis_internal_v2(
  p_work_item_id uuid,
  p_assignee_membership_id uuid,
  p_assigned_by_membership_id uuid,
  p_establishment_basis_kind text,
  p_establishment_basis jsonb,
  p_reason text default null,
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_work atlas.work_items%rowtype;
  v_assignee atlas.organization_memberships%rowtype;
  v_assigner atlas.organization_memberships%rowtype;
  v_existing atlas.work_allocations%rowtype;
  v_new atlas.work_allocations%rowtype;
  v_kind text:=lower(btrim(coalesce(p_establishment_basis_kind,'')));
  v_basis jsonb:=coalesce(p_establishment_basis,'{}'::jsonb);
begin
  if p_work_item_id is null or p_assignee_membership_id is null then
    raise exception 'Company Work item and responsible membership are required.'
      using errcode='22023';
  end if;

  if v_kind not in ('self_claim','self_adoption','self_initiated_outbound')
     or jsonb_typeof(v_basis)<>'object' then
    raise exception 'A supported structured responsibility establishment basis is required.'
      using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('atlas.company_work.responsibility:'||p_work_item_id::text,0)
  );

  select * into v_work
  from atlas.work_items
  where id=p_work_item_id
  for update;

  if v_work.id is null then
    raise exception 'Company Work item was not found.' using errcode='P0002';
  end if;
  if v_work.work_state<>'open' then
    raise exception 'Responsibility can only be established while Company Work is open.'
      using errcode='22023';
  end if;

  select * into v_assignee
  from atlas.organization_memberships
  where id=p_assignee_membership_id
    and organization_id=v_work.organization_id
    and active;

  if v_assignee.id is null then
    raise exception 'Responsible membership must be active in the Work organization.'
      using errcode='23514';
  end if;

  if p_assigned_by_membership_id is not null then
    select * into v_assigner
    from atlas.organization_memberships
    where id=p_assigned_by_membership_id
      and organization_id=v_work.organization_id
      and active;
    if v_assigner.id is null then
      raise exception 'Establishing membership must be active in the Work organization.'
        using errcode='23514';
    end if;
  end if;

  if v_kind in ('self_claim','self_adoption','self_initiated_outbound')
     and p_assigned_by_membership_id is distinct from p_assignee_membership_id then
    raise exception 'Self-established Work responsibility requires the actor to be the assignee.'
      using errcode='23514';
  end if;

  v_basis:=v_basis||jsonb_build_object(
    'contractVersion','exact_work_responsibility_establishment_v2',
    'basisKind',v_kind,
    'organizationId',v_work.organization_id,
    'workItemId',v_work.id,
    'actorMembershipId',p_assigned_by_membership_id,
    'assigneeMembershipId',p_assignee_membership_id,
    'establishedAt',now()
  );

  select * into v_existing
  from atlas.work_allocations
  where organization_id=v_work.organization_id
    and work_item_id=v_work.id
    and allocation_role='responsible'
    and state='active'
  limit 1;

  if v_existing.id is not null
     and v_existing.assignee_membership_id=p_assignee_membership_id then
    perform atlas.sync_production_company_work_responsibility_carrier_v1(v_work.id);

    return jsonb_build_object(
      'contractVersion','exact_work_responsibility_establishment_v2',
      'state',case
        when v_existing.establishment_basis_kind is null then 'already_responsible_historical'
        else 'unchanged'
      end,
      'workItemId',v_work.id,
      'allocationId',v_existing.id,
      'assigneeMembershipId',v_existing.assignee_membership_id,
      'establishmentBasisKind',v_existing.establishment_basis_kind
    );
  end if;

  if v_existing.id is not null then
    raise exception 'Another member already carries this Work. Transfer requires a governed receiver-uptake process.'
      using errcode='0A000';
  end if;

  insert into atlas.work_allocations(
    organization_id,
    work_item_id,
    assignee_membership_id,
    assigned_by_membership_id,
    allocation_role,
    state,
    allocated_at,
    establishment_basis_kind,
    establishment_basis,
    metadata
  ) values(
    v_work.organization_id,
    v_work.id,
    p_assignee_membership_id,
    p_assigned_by_membership_id,
    'responsible',
    'active',
    now(),
    v_kind,
    v_basis,
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'source','set_company_work_responsibility_with_basis_internal_v2',
      'reason',nullif(btrim(coalesce(p_reason,'')),''),
      'responsibilityEstablishmentContract','exact_work_responsibility_establishment_v2'
    )
  )
  returning * into v_new;

  perform atlas.sync_production_company_work_responsibility_carrier_v1(v_work.id);

  return jsonb_build_object(
    'contractVersion','exact_work_responsibility_establishment_v2',
    'state','established',
    'workItemId',v_work.id,
    'allocationId',v_new.id,
    'assigneeMembershipId',v_new.assignee_membership_id,
    'establishmentBasisKind',v_new.establishment_basis_kind
  );
end;
$function$;

revoke all on function atlas.set_company_work_responsibility_with_basis_internal_v2(
  uuid,uuid,uuid,text,jsonb,text,jsonb
) from public,anon,authenticated,service_role;

comment on function atlas.set_company_work_responsibility_with_basis_internal_v2(
  uuid,uuid,uuid,text,jsonb,text,jsonb
) is
'Forward exact-Work responsibility creation seam. Requires a governed establishment basis and refuses implicit transfer from another current carrier.';

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
set search_path=pg_catalog,atlas
as $function$
declare
  v_work atlas.work_items%rowtype;
  v_existing atlas.work_allocations%rowtype;
  v_assigner atlas.organization_memberships%rowtype;
  v_source text:=coalesce(p_provenance->>'source','');
  v_basis jsonb;
begin
  if p_work_item_id is null then
    raise exception 'Company Work item is required.' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('atlas.company_work.responsibility:'||p_work_item_id::text,0)
  );

  select * into v_work
  from atlas.work_items
  where id=p_work_item_id
  for update;

  if v_work.id is null then
    raise exception 'Company Work item was not found.' using errcode='P0002';
  end if;
  if v_work.work_state<>'open' then
    raise exception 'Responsibility can only be changed while Company Work is open.'
      using errcode='22023';
  end if;

  if p_assigned_by_membership_id is not null then
    select * into v_assigner
    from atlas.organization_memberships
    where id=p_assigned_by_membership_id
      and organization_id=v_work.organization_id
      and active;
    if v_assigner.id is null then
      raise exception 'Acting membership must be active in the Work organization.'
        using errcode='23514';
    end if;
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
      raise exception 'Generic exact Work responsibility release is not a settled effect. Completion, transfer, cancellation, adjudication, or another governed domain release must establish the lifecycle change.'
        using errcode='0A000';
    end if;

    perform atlas.sync_production_company_work_responsibility_carrier_v1(v_work.id);
    return jsonb_build_object(
      'state','unchanged_unassigned','workItemId',v_work.id,'allocationId',null
    );
  end if;

  if v_source='claim_institutional_conversation_self_api_v1' then
    v_basis:=jsonb_build_object(
      'institutionalConversationId',p_provenance->>'institutionalConversationId',
      'responseCaseId',p_provenance->>'responseCaseId'
    );
    return atlas.set_company_work_responsibility_with_basis_internal_v2(
      p_work_item_id,p_assignee_membership_id,p_assigned_by_membership_id,
      'self_claim',v_basis,p_reason,p_provenance
    );
  end if;

  if v_source='ensure_outbound_conversation_responsibility_service_v1' then
    v_basis:=jsonb_build_object(
      'outboundOperationId',p_provenance->>'outboundOperationId'
    );
    return atlas.set_company_work_responsibility_with_basis_internal_v2(
      p_work_item_id,p_assignee_membership_id,p_assigned_by_membership_id,
      'self_initiated_outbound',v_basis,p_reason,p_provenance
    );
  end if;

  if v_source='create_communication_derived_work_self_api_v1'
     and p_assigned_by_membership_id is not distinct from p_assignee_membership_id then
    v_basis:=jsonb_build_object(
      'sourceKind','communication_derived_work_link',
      'sourceId',p_provenance->>'derivedWorkLinkId'
    );
    return atlas.set_company_work_responsibility_with_basis_internal_v2(
      p_work_item_id,p_assignee_membership_id,p_assigned_by_membership_id,
      'self_adoption',v_basis,p_reason,p_provenance
    );
  end if;

  raise exception 'A governed receiver-side responsibility establishment basis is required. Routing, owner authority, and handoff capability cannot create another member''s responsibility.'
    using errcode='0A000';
end;
$function$;

revoke all on function atlas.set_company_work_responsibility_internal_v1(
  uuid,uuid,uuid,text,jsonb
) from public,anon,authenticated,service_role;

comment on function atlas.set_company_work_responsibility_internal_v1(
  uuid,uuid,uuid,text,jsonb
) is
'Database-internal compatibility router. Known self-uptake callers delegate to v2. Generic creation, transfer, and release without a governed lifecycle basis fail closed.';

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values(
  'atlas.set_company_work_responsibility_with_basis_internal_v2(uuid,uuid,uuid,text,jsonb,text,jsonb)',
  'service_internal','verified','active',
  false,true,false,0,0,
  jsonb_build_object(
    'source','atlas_exact_work_responsibility_establishment_v2',
    'purpose','Database-internal persistence of exact Company Work responsibility after a governed domain command establishes uptake.',
    'truthBoundary','Routing, planning, visibility, owner authority, service-role technical access and execution capability are not responsibility establishment.',
    'directServiceExecute',false,
    'classificationRuleVersion',3
  ),
  now(),false
)
on conflict (signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values(
  'atlas.set_company_work_responsibility_internal_v1(uuid,uuid,uuid,text,jsonb)',
  'service_internal','verified','active',
  false,true,false,6,0,
  jsonb_build_object(
    'source','atlas_exact_work_responsibility_establishment_v2',
    'purpose','Database-internal compatibility router for governed responsibility callers while v1 call sites converge on explicit basis-aware commands.',
    'truthBoundary','No direct browser or service-role execution. Database SECURITY DEFINER callers remain the only forward path.',
    'directServiceExecute',false,
    'classificationRuleVersion',3
  ),
  now(),false
)
on conflict (signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

commit;
