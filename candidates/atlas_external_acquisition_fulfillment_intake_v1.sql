begin;

create table if not exists atlas.external_acquisition_fulfillments (
  id uuid primary key default gen_random_uuid(),
  external_acquisition_commitment_id uuid not null
    references atlas.external_acquisition_commitments(id) on delete restrict,
  fulfillment_key text not null,
  fulfillment_kind text not null
    check (fulfillment_kind in ('delivery','service_performance','other')),
  occurred_at timestamptz not null,
  source_kind text not null,
  source_ref text,
  evidence_record_id uuid
    references atlas.evidence_records(id) on delete restrict,
  connected_source_observation_id uuid
    references atlas.connected_source_observations(id) on delete restrict,
  fulfillment_sha256 text not null
    check (fulfillment_sha256 ~ '^[0-9a-f]{64}$'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint external_acquisition_fulfillments_key_nonblank
    check (btrim(fulfillment_key)<>''),
  constraint external_acquisition_fulfillments_source_kind_nonblank
    check (btrim(source_kind)<>''),
  constraint external_acquisition_fulfillments_source_ref_nonblank
    check (source_ref is null or btrim(source_ref)<>''),
  unique(external_acquisition_commitment_id,fulfillment_key)
);

create index if not exists external_acquisition_fulfillments_commitment_idx
  on atlas.external_acquisition_fulfillments(
    external_acquisition_commitment_id,occurred_at,id
  );

comment on table atlas.external_acquisition_fulfillments is
'Immutable actual external supplier delivery/performance occurrence against one External Acquisition Commitment. It is not inventory, Spend, payment, internal Company Work execution, or customer fulfillment.';


create table if not exists atlas.external_acquisition_fulfillment_lines (
  id uuid primary key default gen_random_uuid(),
  external_acquisition_fulfillment_id uuid not null
    references atlas.external_acquisition_fulfillments(id) on delete restrict,
  line_key text not null,
  external_acquisition_commitment_line_id uuid not null
    references atlas.external_acquisition_commitment_lines(id) on delete restrict,
  source_quantity numeric(14,3)
    check (source_quantity is null or source_quantity>0),
  source_unit text,
  delivered_output_quantity numeric(14,3) not null
    check (delivered_output_quantity>0),
  accepted_output_quantity numeric(14,3) not null default 0
    check (accepted_output_quantity>=0),
  rejected_output_quantity numeric(14,3) not null default 0
    check (rejected_output_quantity>=0),
  unresolved_output_quantity numeric(14,3) not null default 0
    check (unresolved_output_quantity>=0),
  coverage_output_unit text not null,
  condition jsonb not null default '{}'::jsonb
    check (jsonb_typeof(condition)='object'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint external_acquisition_fulfillment_lines_key_nonblank
    check (btrim(line_key)<>''),
  constraint external_acquisition_fulfillment_lines_source_pair
    check (
      (source_quantity is null and source_unit is null)
      or
      (
        source_quantity is not null
        and source_unit is not null
        and btrim(source_unit)<>''
      )
    ),
  constraint external_acquisition_fulfillment_lines_output_unit_nonblank
    check (btrim(coverage_output_unit)<>''),
  constraint external_acquisition_fulfillment_lines_partition
    check (
      delivered_output_quantity =
        accepted_output_quantity
        + rejected_output_quantity
        + unresolved_output_quantity
    ),
  unique(external_acquisition_fulfillment_id,line_key)
);

create index if not exists external_acquisition_fulfillment_lines_commitment_line_idx
  on atlas.external_acquisition_fulfillment_lines(
    external_acquisition_commitment_line_id,external_acquisition_fulfillment_id
  );

comment on table atlas.external_acquisition_fulfillment_lines is
'Actual delivered/performed coverage-output quantity and receiving assessment against one acquisition commitment line. Accepted, rejected, and unresolved quantities partition delivered output. Actual overdelivery is preserved rather than capped.';


create table if not exists atlas.external_acquisition_fulfillment_allocations (
  id uuid primary key default gen_random_uuid(),
  external_acquisition_fulfillment_line_id uuid not null
    references atlas.external_acquisition_fulfillment_lines(id) on delete restrict,
  allocation_key text not null,
  external_acquisition_requirement_allocation_id uuid not null
    references atlas.external_acquisition_requirement_allocations(id) on delete restrict,
  accepted_coverage_quantity numeric(14,3) not null
    check (accepted_coverage_quantity>0),
  coverage_unit text not null,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint external_acquisition_fulfillment_allocations_key_nonblank
    check (btrim(allocation_key)<>''),
  constraint external_acquisition_fulfillment_allocations_unit_nonblank
    check (btrim(coverage_unit)<>''),
  unique(external_acquisition_fulfillment_line_id,allocation_key),
  unique(
    external_acquisition_fulfillment_line_id,
    external_acquisition_requirement_allocation_id
  )
);

create index if not exists external_acquisition_fulfillment_allocations_commitment_allocation_idx
  on atlas.external_acquisition_fulfillment_allocations(
    external_acquisition_requirement_allocation_id,
    external_acquisition_fulfillment_line_id
  );

comment on table atlas.external_acquisition_fulfillment_allocations is
'Immutable allocation of accepted external supplier output to one prior External Acquisition Requirement Allocation. It transfers only accepted quantity from supplier-commitment coverage to actual-fulfillment coverage.';


create or replace function atlas.guard_external_acquisition_fulfillment_scope_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_commitment atlas.external_acquisition_commitments%rowtype;
  v_fulfillment atlas.external_acquisition_fulfillments%rowtype;
  v_commitment_line atlas.external_acquisition_commitment_lines%rowtype;
  v_fulfillment_line atlas.external_acquisition_fulfillment_lines%rowtype;
  v_commitment_allocation atlas.external_acquisition_requirement_allocations%rowtype;
  v_current_state text;
  v_total_line_allocated numeric;
  v_total_commitment_allocated numeric;
begin
  if tg_table_name='external_acquisition_fulfillments' then
    select * into v_commitment
    from atlas.external_acquisition_commitments
    where id=new.external_acquisition_commitment_id;

    if v_commitment.id is null then
      raise exception 'External Acquisition Commitment not found.'
        using errcode='P0002';
    end if;

    v_current_state:=atlas.external_acquisition_commitment_position_v1(v_commitment.id)->>'state';

    if v_current_state in ('cancelled','closed') then
      raise exception 'Cannot record supplier fulfillment against a cancelled or closed acquisition commitment.'
        using errcode='23514';
    end if;

    if new.occurred_at<v_commitment.committed_at then
      raise exception 'External supplier fulfillment cannot predate acquisition commitment.'
        using errcode='23514';
    end if;

    if new.connected_source_observation_id is not null
       and not exists(
         select 1
         from atlas.connected_source_observations cso
         join atlas.connected_sources cs on cs.id=cso.connected_source_id
         where cso.id=new.connected_source_observation_id
           and cs.custodian_organization_id=v_commitment.organization_id
           and (
             cs.custodian_organization_unit_id is null
             or cs.custodian_organization_unit_id
                is not distinct from v_commitment.organization_unit_id
           )
       ) then
      raise exception 'Fulfillment connected-source observation must share commitment organization/unit scope.'
        using errcode='23514';
    end if;

    new.fulfillment_key:=btrim(new.fulfillment_key);
    new.fulfillment_kind:=lower(btrim(new.fulfillment_kind));
    new.source_kind:=lower(btrim(new.source_kind));
    new.source_ref:=nullif(btrim(new.source_ref),'');
    return new;
  end if;

  if tg_table_name='external_acquisition_fulfillment_lines' then
    select * into v_fulfillment
    from atlas.external_acquisition_fulfillments
    where id=new.external_acquisition_fulfillment_id;

    select * into v_commitment_line
    from atlas.external_acquisition_commitment_lines
    where id=new.external_acquisition_commitment_line_id;

    if v_fulfillment.id is null
       or v_commitment_line.id is null
       or v_commitment_line.external_acquisition_commitment_id
          is distinct from v_fulfillment.external_acquisition_commitment_id then
      raise exception 'External fulfillment line must belong to a commitment line from the same acquisition commitment.'
        using errcode='23514';
    end if;

    new.line_key:=btrim(new.line_key);
    new.source_unit:=nullif(lower(btrim(new.source_unit)),'');
    new.coverage_output_unit:=lower(btrim(new.coverage_output_unit));

    if new.coverage_output_unit is distinct from v_commitment_line.coverage_output_unit then
      raise exception 'External fulfillment line output unit must match acquisition commitment line output unit.'
        using errcode='23514';
    end if;

    return new;
  end if;

  select * into v_fulfillment_line
  from atlas.external_acquisition_fulfillment_lines
  where id=new.external_acquisition_fulfillment_line_id;

  select * into v_commitment_allocation
  from atlas.external_acquisition_requirement_allocations
  where id=new.external_acquisition_requirement_allocation_id;

  if v_fulfillment_line.id is null
     or v_commitment_allocation.id is null
     or v_commitment_allocation.external_acquisition_commitment_line_id
        is distinct from v_fulfillment_line.external_acquisition_commitment_line_id then
    raise exception 'Fulfillment allocation must reference a requirement allocation from the same acquisition commitment line.'
      using errcode='23514';
  end if;

  new.allocation_key:=btrim(new.allocation_key);
  new.coverage_unit:=lower(btrim(new.coverage_unit));

  if new.coverage_unit is distinct from v_fulfillment_line.coverage_output_unit
     or new.coverage_unit is distinct from v_commitment_allocation.coverage_unit then
    raise exception 'Fulfillment allocation unit must match both fulfillment output and commitment allocation unit.'
      using errcode='23514';
  end if;

  select coalesce(sum(a.accepted_coverage_quantity),0)
  into v_total_line_allocated
  from atlas.external_acquisition_fulfillment_allocations a
  where a.external_acquisition_fulfillment_line_id=new.external_acquisition_fulfillment_line_id;

  if v_total_line_allocated+new.accepted_coverage_quantity
     >v_fulfillment_line.accepted_output_quantity then
    raise exception 'Fulfillment allocations cannot exceed accepted output quantity.'
      using errcode='23514';
  end if;

  select coalesce(sum(a.accepted_coverage_quantity),0)
  into v_total_commitment_allocated
  from atlas.external_acquisition_fulfillment_allocations a
  where a.external_acquisition_requirement_allocation_id
        =new.external_acquisition_requirement_allocation_id;

  if v_total_commitment_allocated+new.accepted_coverage_quantity
     >v_commitment_allocation.coverage_quantity then
    raise exception 'Cumulative accepted fulfillment allocation cannot exceed original acquisition requirement allocation.'
      using errcode='23514';
  end if;

  return new;
end;
$function$;


drop trigger if exists external_acquisition_fulfillments_scope_guard_v1
  on atlas.external_acquisition_fulfillments;
create trigger external_acquisition_fulfillments_scope_guard_v1
before insert on atlas.external_acquisition_fulfillments
for each row execute function atlas.guard_external_acquisition_fulfillment_scope_v1();

drop trigger if exists external_acquisition_fulfillment_lines_scope_guard_v1
  on atlas.external_acquisition_fulfillment_lines;
create trigger external_acquisition_fulfillment_lines_scope_guard_v1
before insert on atlas.external_acquisition_fulfillment_lines
for each row execute function atlas.guard_external_acquisition_fulfillment_scope_v1();

drop trigger if exists external_acquisition_fulfillment_allocations_scope_guard_v1
  on atlas.external_acquisition_fulfillment_allocations;
create trigger external_acquisition_fulfillment_allocations_scope_guard_v1
before insert on atlas.external_acquisition_fulfillment_allocations
for each row execute function atlas.guard_external_acquisition_fulfillment_scope_v1();


create or replace function atlas.prevent_external_acquisition_fulfillment_mutation_v1()
returns trigger
language plpgsql
set search_path=pg_catalog,atlas
as $function$
begin
  raise exception 'External Acquisition Fulfillment history is immutable; record later source truth instead.'
    using errcode='55000';
end;
$function$;

drop trigger if exists external_acquisition_fulfillments_immutable_v1
  on atlas.external_acquisition_fulfillments;
create trigger external_acquisition_fulfillments_immutable_v1
before update or delete on atlas.external_acquisition_fulfillments
for each row execute function atlas.prevent_external_acquisition_fulfillment_mutation_v1();

drop trigger if exists external_acquisition_fulfillment_lines_immutable_v1
  on atlas.external_acquisition_fulfillment_lines;
create trigger external_acquisition_fulfillment_lines_immutable_v1
before update or delete on atlas.external_acquisition_fulfillment_lines
for each row execute function atlas.prevent_external_acquisition_fulfillment_mutation_v1();

drop trigger if exists external_acquisition_fulfillment_allocations_immutable_v1
  on atlas.external_acquisition_fulfillment_allocations;
create trigger external_acquisition_fulfillment_allocations_immutable_v1
before update or delete on atlas.external_acquisition_fulfillment_allocations
for each row execute function atlas.prevent_external_acquisition_fulfillment_mutation_v1();


create or replace function atlas.external_acquisition_fulfillment_position_v1(
  p_external_acquisition_fulfillment_id uuid
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas
as $function$
declare
  v_f atlas.external_acquisition_fulfillments%rowtype;
  v_lines jsonb;
begin
  select * into v_f
  from atlas.external_acquisition_fulfillments
  where id=p_external_acquisition_fulfillment_id;

  if v_f.id is null then
    raise exception 'External Acquisition Fulfillment not found.'
      using errcode='P0002';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'externalAcquisitionFulfillmentLineId',fl.id,
        'lineKey',fl.line_key,
        'externalAcquisitionCommitmentLineId',fl.external_acquisition_commitment_line_id,
        'sourceQuantity',fl.source_quantity,
        'sourceUnit',fl.source_unit,
        'deliveredOutputQuantity',fl.delivered_output_quantity,
        'acceptedOutputQuantity',fl.accepted_output_quantity,
        'rejectedOutputQuantity',fl.rejected_output_quantity,
        'unresolvedOutputQuantity',fl.unresolved_output_quantity,
        'coverageOutputUnit',fl.coverage_output_unit,
        'conditionState',case
          when fl.unresolved_output_quantity>0 then 'unresolved'
          when fl.accepted_output_quantity>0 and fl.rejected_output_quantity>0 then 'mixed'
          when fl.rejected_output_quantity>0 then 'rejected'
          else 'accepted'
        end,
        'condition',fl.condition,
        'acceptedAllocatedQuantity',coalesce(x.allocated_quantity,0),
        'acceptedUnallocatedQuantity',
          fl.accepted_output_quantity-coalesce(x.allocated_quantity,0),
        'allocations',coalesce(x.allocations,'[]'::jsonb),
        'metadata',fl.metadata
      )
      order by fl.line_key,fl.id
    ),
    '[]'::jsonb
  )
  into v_lines
  from atlas.external_acquisition_fulfillment_lines fl
  left join lateral (
    select
      sum(fa.accepted_coverage_quantity) as allocated_quantity,
      jsonb_agg(
        jsonb_build_object(
          'externalAcquisitionFulfillmentAllocationId',fa.id,
          'allocationKey',fa.allocation_key,
          'externalAcquisitionRequirementAllocationId',
            fa.external_acquisition_requirement_allocation_id,
          'acceptedCoverageQuantity',fa.accepted_coverage_quantity,
          'coverageUnit',fa.coverage_unit,
          'metadata',fa.metadata
        )
        order by fa.allocation_key,fa.id
      ) as allocations
    from atlas.external_acquisition_fulfillment_allocations fa
    where fa.external_acquisition_fulfillment_line_id=fl.id
  ) x on true
  where fl.external_acquisition_fulfillment_id=v_f.id;

  return jsonb_build_object(
    'contractVersion','external_acquisition_fulfillment_position_v1',
    'externalAcquisitionFulfillmentId',v_f.id,
    'externalAcquisitionCommitmentId',v_f.external_acquisition_commitment_id,
    'fulfillmentKey',v_f.fulfillment_key,
    'fulfillmentKind',v_f.fulfillment_kind,
    'occurredAt',v_f.occurred_at,
    'source',jsonb_build_object(
      'kind',v_f.source_kind,
      'ref',v_f.source_ref,
      'evidenceRecordId',v_f.evidence_record_id,
      'connectedSourceObservationId',v_f.connected_source_observation_id
    ),
    'lines',v_lines,
    'metadata',v_f.metadata,
    'truthBoundary',jsonb_build_object(
      'actualExternalFulfillment',true,
      'notInventory',true,
      'notSpend',true,
      'notPayment',true,
      'doesNotCloseCompanyWork',true
    )
  );
end;
$function$;


create or replace function atlas.external_acquisition_commitment_position_v1(
  p_external_acquisition_commitment_id uuid
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas
as $function$
declare
  v_commitment atlas.external_acquisition_commitments%rowtype;
  v_latest_event atlas.external_acquisition_commitment_events%rowtype;
  v_has_cancelled boolean:=false;
  v_has_closed boolean:=false;
  v_state text;
  v_terminal_basis text;
  v_lines jsonb;
  v_events jsonb;
  v_fulfillments jsonb;
  v_fulfillment_count integer:=0;
  v_any_unresolved boolean:=false;
  v_any_remaining boolean:=false;
  v_any_rejected boolean:=false;
begin
  select * into v_commitment
  from atlas.external_acquisition_commitments
  where id=p_external_acquisition_commitment_id;

  if v_commitment.id is null then
    raise exception 'External Acquisition Commitment not found.'
      using errcode='P0002';
  end if;

  select exists(
    select 1 from atlas.external_acquisition_commitment_events e
    where e.external_acquisition_commitment_id=v_commitment.id
      and e.event_kind='cancelled'
  ) into v_has_cancelled;

  select exists(
    select 1 from atlas.external_acquisition_commitment_events e
    where e.external_acquisition_commitment_id=v_commitment.id
      and e.event_kind='closed'
  ) into v_has_closed;

  select * into v_latest_event
  from atlas.external_acquisition_commitment_events e
  where e.external_acquisition_commitment_id=v_commitment.id
  order by e.occurred_at desc,e.created_at desc,e.id desc
  limit 1;

  select count(*) into v_fulfillment_count
  from atlas.external_acquisition_fulfillments f
  where f.external_acquisition_commitment_id=v_commitment.id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'externalAcquisitionCommitmentLineId',l.id,
        'lineKey',l.line_key,
        'externalSupplyOfferingId',l.external_supply_offering_id,
        'externalSupplyOfferObservationId',l.external_supply_offer_observation_id,
        'sourceLineKey',l.source_line_key,
        'description',l.description,
        'orderedQuantity',l.ordered_quantity,
        'orderedUnit',l.ordered_unit,
        'coverageOutputQuantity',l.coverage_output_quantity,
        'coverageOutputUnit',l.coverage_output_unit,
        'knownLineAmount',l.known_line_amount,
        'currency',l.currency,
        'acceptedTerms',l.accepted_terms,
        'committedAllocatedCoverageQuantity',coalesce(a.committed_allocated,0),
        'deliveredOutputQuantity',coalesce(f.delivered,0),
        'acceptedOutputQuantity',coalesce(f.accepted,0),
        'rejectedOutputQuantity',coalesce(f.rejected,0),
        'unresolvedOutputQuantity',coalesce(f.unresolved,0),
        'acceptedAllocatedQuantity',coalesce(f.accepted_allocated,0),
        'acceptedUnallocatedQuantity',
          greatest(coalesce(f.accepted,0)-coalesce(f.accepted_allocated,0),0),
        'remainingExpectedOutputQuantity',
          greatest(l.coverage_output_quantity-coalesce(f.delivered,0),0),
        'overdeliveredOutputQuantity',
          greatest(coalesce(f.delivered,0)-l.coverage_output_quantity,0),
        'fulfillmentState',case
          when coalesce(f.unresolved,0)>0 then 'unresolved'
          when coalesce(f.delivered,0)<l.coverage_output_quantity then
            case when coalesce(f.delivered,0)=0 then 'not_fulfilled' else 'partial' end
          when coalesce(f.rejected,0)>0 then 'fulfilled_with_exception'
          else 'fulfilled'
        end,
        'allocations',coalesce(a.allocations,'[]'::jsonb)
      )
      order by l.line_key,l.id
    ),
    '[]'::jsonb
  )
  into v_lines
  from atlas.external_acquisition_commitment_lines l
  left join lateral (
    select
      sum(ra.coverage_quantity) as committed_allocated,
      jsonb_agg(
        jsonb_build_object(
          'externalAcquisitionRequirementAllocationId',ra.id,
          'allocationKey',ra.allocation_key,
          'workRequirementId',ra.work_requirement_id,
          'coverageQuantity',ra.coverage_quantity,
          'coverageUnit',ra.coverage_unit,
          'acceptedFulfilledQuantity',coalesce(ff.accepted_fulfilled,0),
          'remainingSupplierCommitmentQuantity',
            greatest(ra.coverage_quantity-coalesce(ff.accepted_fulfilled,0),0)
        )
        order by ra.allocation_key,ra.id
      ) as allocations
    from atlas.external_acquisition_requirement_allocations ra
    left join lateral (
      select sum(fa.accepted_coverage_quantity) as accepted_fulfilled
      from atlas.external_acquisition_fulfillment_allocations fa
      where fa.external_acquisition_requirement_allocation_id=ra.id
    ) ff on true
    where ra.external_acquisition_commitment_line_id=l.id
  ) a on true
  left join lateral (
    select
      sum(fl.delivered_output_quantity) as delivered,
      sum(fl.accepted_output_quantity) as accepted,
      sum(fl.rejected_output_quantity) as rejected,
      sum(fl.unresolved_output_quantity) as unresolved,
      sum(coalesce(z.accepted_allocated,0)) as accepted_allocated
    from atlas.external_acquisition_fulfillment_lines fl
    join atlas.external_acquisition_fulfillments ef
      on ef.id=fl.external_acquisition_fulfillment_id
    left join lateral (
      select sum(fa.accepted_coverage_quantity) as accepted_allocated
      from atlas.external_acquisition_fulfillment_allocations fa
      where fa.external_acquisition_fulfillment_line_id=fl.id
    ) z on true
    where ef.external_acquisition_commitment_id=v_commitment.id
      and fl.external_acquisition_commitment_line_id=l.id
  ) f on true
  where l.external_acquisition_commitment_id=v_commitment.id;

  select
    exists(
      select 1 from jsonb_array_elements(v_lines) x
      where (x->>'unresolvedOutputQuantity')::numeric>0
    ),
    exists(
      select 1 from jsonb_array_elements(v_lines) x
      where (x->>'remainingExpectedOutputQuantity')::numeric>0
    ),
    exists(
      select 1 from jsonb_array_elements(v_lines) x
      where (x->>'rejectedOutputQuantity')::numeric>0
    )
  into v_any_unresolved,v_any_remaining,v_any_rejected;

  if v_has_closed then
    v_state:='closed';
    v_terminal_basis:=case when v_has_cancelled then 'cancelled' else 'fulfilled' end;
  elsif v_has_cancelled then
    v_state:='cancelled';
    v_terminal_basis:='cancelled';
  elsif v_fulfillment_count=0 then
    v_state:='committed';
  elsif v_any_unresolved then
    v_state:='fulfillment_unresolved';
  elsif v_any_remaining then
    v_state:='partially_fulfilled';
  elsif v_any_rejected then
    v_state:='fulfilled_with_exception';
  else
    v_state:='fulfilled';
    v_terminal_basis:='fulfilled';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'externalAcquisitionCommitmentEventId',e.id,
        'eventKey',e.event_key,
        'eventKind',e.event_kind,
        'occurredAt',e.occurred_at,
        'sourceKind',e.source_kind,
        'sourceRef',e.source_ref,
        'metadata',e.metadata
      )
      order by e.occurred_at,e.created_at,e.id
    ),
    '[]'::jsonb
  )
  into v_events
  from atlas.external_acquisition_commitment_events e
  where e.external_acquisition_commitment_id=v_commitment.id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'externalAcquisitionFulfillmentId',f.id,
        'fulfillmentKey',f.fulfillment_key,
        'fulfillmentKind',f.fulfillment_kind,
        'occurredAt',f.occurred_at
      )
      order by f.occurred_at,f.id
    ),
    '[]'::jsonb
  )
  into v_fulfillments
  from atlas.external_acquisition_fulfillments f
  where f.external_acquisition_commitment_id=v_commitment.id;

  return jsonb_build_object(
    'contractVersion','external_acquisition_commitment_position_v1',
    'externalAcquisitionCommitmentId',v_commitment.id,
    'organizationId',v_commitment.organization_id,
    'organizationUnitId',v_commitment.organization_unit_id,
    'supplierRelationshipId',v_commitment.supplier_relationship_id,
    'commitmentKey',v_commitment.commitment_key,
    'commitmentKind',v_commitment.commitment_kind,
    'committedAt',v_commitment.committed_at,
    'expectedFulfillmentFromAt',v_commitment.expected_fulfillment_from_at,
    'expectedFulfillmentByAt',v_commitment.expected_fulfillment_by_at,
    'state',v_state,
    'terminalBasis',v_terminal_basis,
    'economicState',v_commitment.economic_state,
    'knownCommittedAmount',v_commitment.known_committed_amount,
    'currency',v_commitment.currency,
    'costComponents',v_commitment.cost_components,
    'acceptedTerms',v_commitment.accepted_terms,
    'authorizationBasis',v_commitment.authorization_basis,
    'source',jsonb_build_object(
      'kind',v_commitment.source_kind,
      'ref',v_commitment.source_ref,
      'evidenceRecordId',v_commitment.evidence_record_id,
      'connectedSourceObservationId',v_commitment.connected_source_observation_id
    ),
    'lines',v_lines,
    'fulfillments',v_fulfillments,
    'events',v_events,
    'metadata',v_commitment.metadata,
    'truthBoundary',jsonb_build_object(
      'buySideCommitment',true,
      'fulfillmentStateDerivedFromActualIntake',true,
      'notSpend',true,
      'notPayment',true,
      'notInventory',true,
      'notCommercialOrder',true
    )
  );
end;
$function$;


create or replace function atlas.external_acquisition_fulfillment_preview_v1(
  p_input jsonb
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas,extensions
as $function$
declare
  v_commitment_id uuid;
  v_commitment atlas.external_acquisition_commitments%rowtype;
  v_commitment_position jsonb;
  v_key text;
  v_kind text;
  v_occurred_at timestamptz;
  v_source jsonb;
  v_source_kind text;
  v_line jsonb;
  v_alloc jsonb;
  v_commitment_line atlas.external_acquisition_commitment_lines%rowtype;
  v_commitment_allocation atlas.external_acquisition_requirement_allocations%rowtype;
  v_line_key text;
  v_line_id uuid;
  v_alloc_key text;
  v_alloc_id uuid;
  v_source_quantity numeric;
  v_source_unit text;
  v_delivered numeric;
  v_accepted numeric;
  v_rejected numeric;
  v_unresolved numeric;
  v_output_unit text;
  v_alloc_quantity numeric;
  v_alloc_unit text;
  v_line_allocated numeric;
  v_prior_allocation_quantity numeric;
  v_prior_delivered numeric;
  v_line_keys text[]:='{}'::text[];
  v_alloc_keys text[];
  v_alloc_ids uuid[];
  v_line_count integer:=0;
  v_allocation_count integer:=0;
  v_violations jsonb:='[]'::jsonb;
  v_warnings jsonb:='[]'::jsonb;
  v_hash text;
  v_existing atlas.external_acquisition_fulfillments%rowtype;
begin
  if p_input is null or jsonb_typeof(p_input)<>'object' then
    return jsonb_build_object(
      'contractVersion','external_acquisition_fulfillment_preview_v1',
      'state','blocked',
      'violations',jsonb_build_array(jsonb_build_object('key','input_not_object'))
    );
  end if;

  if p_input->>'contractVersion'<>'external_acquisition_fulfillment_input_v1' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','unsupported_contract_version'
    ));
  end if;

  begin
    v_commitment_id:=(p_input->>'externalAcquisitionCommitmentId')::uuid;
  exception when others then
    v_commitment_id:=null;
  end;

  select * into v_commitment
  from atlas.external_acquisition_commitments
  where id=v_commitment_id;

  if v_commitment.id is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_external_acquisition_commitment_id'
    ));
  else
    v_commitment_position:=atlas.external_acquisition_commitment_position_v1(v_commitment.id);
    if v_commitment_position->>'state' in ('cancelled','closed') then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','commitment_not_open',
        'commitmentState',v_commitment_position->>'state'
      ));
    end if;
  end if;

  v_key:=nullif(btrim(coalesce(p_input->>'fulfillmentKey','')),'');
  if v_key is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','missing_fulfillment_key'
    ));
  end if;

  v_kind:=lower(btrim(coalesce(p_input->>'fulfillmentKind','')));
  if v_kind not in ('delivery','service_performance','other') then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_fulfillment_kind'
    ));
  end if;

  begin
    v_occurred_at:=(p_input->>'occurredAt')::timestamptz;
  exception when others then
    v_occurred_at:=null;
  end;

  if v_occurred_at is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_occurred_at'
    ));
  elsif v_commitment.id is not null
     and v_occurred_at<v_commitment.committed_at then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','fulfillment_predates_commitment'
    ));
  end if;

  v_source:=p_input->'source';
  if v_source is null
     or jsonb_typeof(v_source)<>'object'
     or nullif(btrim(coalesce(v_source->>'kind','')),'') is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_source'
    ));
  else
    v_source_kind:=lower(btrim(v_source->>'kind'));
  end if;

  if p_input ? 'metadata' and jsonb_typeof(p_input->'metadata')<>'object' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_metadata'
    ));
  end if;

  if jsonb_typeof(p_input->'lines')<>'array'
     or jsonb_array_length(coalesce(p_input->'lines','[]'::jsonb))=0 then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','missing_lines'
    ));
  else
    for v_line in select value from jsonb_array_elements(p_input->'lines')
    loop
      v_line_count:=v_line_count+1;
      v_line_allocated:=0;
      v_alloc_keys:='{}'::text[];
      v_alloc_ids:='{}'::uuid[];
      v_line_id:=null;
      v_source_quantity:=null;
      v_source_unit:=null;
      v_delivered:=null;
      v_accepted:=null;
      v_rejected:=null;
      v_unresolved:=null;
      v_output_unit:=null;

      if jsonb_typeof(v_line)<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','line_not_object',
          'lineIndex',v_line_count
        ));
        continue;
      end if;

      v_line_key:=nullif(btrim(coalesce(v_line->>'lineKey','')),'');
      if v_line_key is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','missing_line_key',
          'lineIndex',v_line_count
        ));
        continue;
      elsif v_line_key=any(v_line_keys) then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','duplicate_line_key',
          'lineKey',v_line_key
        ));
        continue;
      end if;
      v_line_keys:=array_append(v_line_keys,v_line_key);

      begin
        v_line_id:=(v_line->>'externalAcquisitionCommitmentLineId')::uuid;
      exception when others then
        v_line_id:=null;
      end;

      select * into v_commitment_line
      from atlas.external_acquisition_commitment_lines
      where id=v_line_id;

      if v_commitment_line.id is null
         or v_commitment_line.external_acquisition_commitment_id
            is distinct from v_commitment_id then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_commitment_line',
          'lineKey',v_line_key
        ));
        continue;
      end if;

      if v_line ? 'sourceQuantity'
         and v_line->'sourceQuantity'<>'null'::jsonb then
        if jsonb_typeof(v_line->'sourceQuantity')<>'number'
           or (v_line->>'sourceQuantity')::numeric<=0 then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_source_quantity',
            'lineKey',v_line_key
          ));
        else
          v_source_quantity:=(v_line->>'sourceQuantity')::numeric;
        end if;
        v_source_unit:=nullif(lower(btrim(coalesce(v_line->>'sourceUnit',''))),'');
        if v_source_unit is null then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','source_quantity_without_unit',
            'lineKey',v_line_key
          ));
        end if;
      elsif nullif(btrim(coalesce(v_line->>'sourceUnit','')),'') is not null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','source_unit_without_quantity',
          'lineKey',v_line_key
        ));
      end if;

      if jsonb_typeof(v_line->'deliveredOutputQuantity')<>'number'
         or (v_line->>'deliveredOutputQuantity')::numeric<=0 then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_delivered_output_quantity',
          'lineKey',v_line_key
        ));
        continue;
      end if;
      v_delivered:=(v_line->>'deliveredOutputQuantity')::numeric;

      if jsonb_typeof(v_line->'acceptedOutputQuantity')<>'number'
         or (v_line->>'acceptedOutputQuantity')::numeric<0
         or jsonb_typeof(v_line->'rejectedOutputQuantity')<>'number'
         or (v_line->>'rejectedOutputQuantity')::numeric<0
         or jsonb_typeof(v_line->'unresolvedOutputQuantity')<>'number'
         or (v_line->>'unresolvedOutputQuantity')::numeric<0 then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_output_partition',
          'lineKey',v_line_key
        ));
        continue;
      end if;

      v_accepted:=(v_line->>'acceptedOutputQuantity')::numeric;
      v_rejected:=(v_line->>'rejectedOutputQuantity')::numeric;
      v_unresolved:=(v_line->>'unresolvedOutputQuantity')::numeric;

      if v_accepted+v_rejected+v_unresolved<>v_delivered then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','output_partition_mismatch',
          'lineKey',v_line_key,
          'deliveredOutputQuantity',v_delivered,
          'partitionTotal',v_accepted+v_rejected+v_unresolved
        ));
      end if;

      v_output_unit:=nullif(lower(btrim(coalesce(v_line->>'coverageOutputUnit',''))),'');
      if v_output_unit is null
         or v_output_unit is distinct from v_commitment_line.coverage_output_unit then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','output_unit_mismatch',
          'lineKey',v_line_key
        ));
      end if;

      if v_line ? 'condition' and jsonb_typeof(v_line->'condition')<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_condition',
          'lineKey',v_line_key
        ));
      end if;

      if v_line ? 'metadata' and jsonb_typeof(v_line->'metadata')<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_line_metadata',
          'lineKey',v_line_key
        ));
      end if;

      select coalesce(sum(fl.delivered_output_quantity),0)
      into v_prior_delivered
      from atlas.external_acquisition_fulfillment_lines fl
      join atlas.external_acquisition_fulfillments f
        on f.id=fl.external_acquisition_fulfillment_id
      where f.external_acquisition_commitment_id=v_commitment_id
        and fl.external_acquisition_commitment_line_id=v_line_id;

      if v_prior_delivered+v_delivered
         >v_commitment_line.coverage_output_quantity then
        v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object(
          'key','actual_overdelivery',
          'lineKey',v_line_key,
          'committedCoverageOutputQuantity',
            v_commitment_line.coverage_output_quantity,
          'cumulativeDeliveredOutputQuantity',
            v_prior_delivered+v_delivered
        ));
      end if;

      if v_line ? 'allocations' then
        if jsonb_typeof(v_line->'allocations')<>'array' then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_allocations',
            'lineKey',v_line_key
          ));
        else
          for v_alloc in
            select value from jsonb_array_elements(v_line->'allocations')
          loop
            v_allocation_count:=v_allocation_count+1;
            v_alloc_id:=null;
            v_alloc_quantity:=null;
            v_alloc_unit:=null;

            if jsonb_typeof(v_alloc)<>'object' then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','allocation_not_object',
                'lineKey',v_line_key
              ));
              continue;
            end if;

            v_alloc_key:=nullif(btrim(coalesce(v_alloc->>'allocationKey','')),'');
            if v_alloc_key is null then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','missing_allocation_key',
                'lineKey',v_line_key
              ));
              continue;
            elsif v_alloc_key=any(v_alloc_keys) then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','duplicate_allocation_key',
                'lineKey',v_line_key,
                'allocationKey',v_alloc_key
              ));
              continue;
            end if;
            v_alloc_keys:=array_append(v_alloc_keys,v_alloc_key);

            begin
              v_alloc_id:=(v_alloc->>'externalAcquisitionRequirementAllocationId')::uuid;
            exception when others then
              v_alloc_id:=null;
            end;

            if v_alloc_id is null or v_alloc_id=any(v_alloc_ids) then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key',case when v_alloc_id is null
                  then 'invalid_commitment_allocation_id'
                  else 'duplicate_commitment_allocation_in_fulfillment_line'
                end,
                'lineKey',v_line_key,
                'allocationKey',v_alloc_key
              ));
              continue;
            end if;
            v_alloc_ids:=array_append(v_alloc_ids,v_alloc_id);

            select * into v_commitment_allocation
            from atlas.external_acquisition_requirement_allocations
            where id=v_alloc_id;

            if v_commitment_allocation.id is null
               or v_commitment_allocation.external_acquisition_commitment_line_id
                  is distinct from v_line_id then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','commitment_allocation_wrong_line',
                'lineKey',v_line_key,
                'allocationKey',v_alloc_key
              ));
              continue;
            end if;

            if jsonb_typeof(v_alloc->'acceptedCoverageQuantity')<>'number'
               or (v_alloc->>'acceptedCoverageQuantity')::numeric<=0 then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','invalid_accepted_coverage_quantity',
                'lineKey',v_line_key,
                'allocationKey',v_alloc_key
              ));
              continue;
            end if;
            v_alloc_quantity:=(v_alloc->>'acceptedCoverageQuantity')::numeric;

            v_alloc_unit:=nullif(lower(btrim(coalesce(v_alloc->>'coverageUnit',''))),'');
            if v_alloc_unit is null
               or v_alloc_unit is distinct from v_output_unit
               or v_alloc_unit is distinct from v_commitment_allocation.coverage_unit then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','allocation_unit_mismatch',
                'lineKey',v_line_key,
                'allocationKey',v_alloc_key
              ));
            end if;

            select coalesce(sum(fa.accepted_coverage_quantity),0)
            into v_prior_allocation_quantity
            from atlas.external_acquisition_fulfillment_allocations fa
            where fa.external_acquisition_requirement_allocation_id=v_alloc_id;

            if v_prior_allocation_quantity+v_alloc_quantity
               >v_commitment_allocation.coverage_quantity then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','cumulative_fulfillment_exceeds_commitment_allocation',
                'lineKey',v_line_key,
                'allocationKey',v_alloc_key,
                'priorAcceptedFulfillmentQuantity',v_prior_allocation_quantity,
                'proposedAcceptedFulfillmentQuantity',v_alloc_quantity,
                'committedAllocationQuantity',v_commitment_allocation.coverage_quantity
              ));
            end if;

            if v_alloc ? 'metadata'
               and jsonb_typeof(v_alloc->'metadata')<>'object' then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','invalid_allocation_metadata',
                'lineKey',v_line_key,
                'allocationKey',v_alloc_key
              ));
            end if;

            v_line_allocated:=v_line_allocated+v_alloc_quantity;
          end loop;
        end if;
      end if;

      if v_line_allocated>v_accepted then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','allocations_exceed_accepted_output',
          'lineKey',v_line_key,
          'acceptedOutputQuantity',v_accepted,
          'allocatedQuantity',v_line_allocated
        ));
      end if;
    end loop;
  end if;

  v_hash:=encode(
    extensions.digest(convert_to(p_input::text,'UTF8'),'sha256'),
    'hex'
  );

  if v_commitment_id is not null and v_key is not null then
    select * into v_existing
    from atlas.external_acquisition_fulfillments
    where external_acquisition_commitment_id=v_commitment_id
      and fulfillment_key=v_key;

    if v_existing.id is not null
       and v_existing.fulfillment_sha256 is distinct from v_hash then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','existing_fulfillment_conflicts',
        'existingExternalAcquisitionFulfillmentId',v_existing.id
      ));
    end if;
  end if;

  return jsonb_build_object(
    'contractVersion','external_acquisition_fulfillment_preview_v1',
    'state',case when jsonb_array_length(v_violations)=0 then 'ready' else 'blocked' end,
    'externalAcquisitionCommitmentId',v_commitment_id,
    'fulfillmentKey',v_key,
    'fulfillmentKind',v_kind,
    'occurredAt',v_occurred_at,
    'lineCount',v_line_count,
    'allocationCount',v_allocation_count,
    'fulfillmentSha256',v_hash,
    'existingExternalAcquisitionFulfillmentId',v_existing.id,
    'existingCompatible',(v_existing.id is not null and v_existing.fulfillment_sha256=v_hash),
    'violations',v_violations,
    'warnings',v_warnings,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'actualOverdeliveryIsWarningNotSuppressed',true,
      'doesNotCreateFulfillment',true,
      'doesNotCreateInventory',true,
      'doesNotCreateSpend',true,
      'doesNotCreatePayment',true,
      'doesNotCloseCompanyWork',true
    )
  );
end;
$function$;


create or replace function atlas.record_external_acquisition_fulfillment_service_v1(
  p_input jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_preview jsonb;
  v_fulfillment_id uuid;
  v_fulfillment_line_id uuid;
  v_line jsonb;
  v_alloc jsonb;
  v_source jsonb;
begin
  v_preview:=atlas.external_acquisition_fulfillment_preview_v1(p_input);

  if v_preview->>'state'<>'ready' then
    if exists(
      select 1 from jsonb_array_elements(v_preview->'violations') x
      where x->>'key'='existing_fulfillment_conflicts'
    ) then
      raise exception 'External Acquisition Fulfillment key conflicts with different structural truth: %',
        (v_preview->'violations')::text
        using errcode='23505';
    end if;

    raise exception 'External Acquisition Fulfillment input is blocked: %',
      (v_preview->'violations')::text
      using errcode='22023';
  end if;

  if nullif(v_preview->>'existingExternalAcquisitionFulfillmentId','') is not null then
    return jsonb_build_object(
      'contractVersion','record_external_acquisition_fulfillment_service_v1',
      'externalAcquisitionFulfillmentId',
        (v_preview->>'existingExternalAcquisitionFulfillmentId')::uuid,
      'created',false,
      'fulfillmentSha256',v_preview->>'fulfillmentSha256',
      'commitmentPosition',
        atlas.external_acquisition_commitment_position_v1(
          (v_preview->>'externalAcquisitionCommitmentId')::uuid
        )
    );
  end if;

  v_source:=p_input->'source';

  insert into atlas.external_acquisition_fulfillments(
    external_acquisition_commitment_id,fulfillment_key,fulfillment_kind,
    occurred_at,source_kind,source_ref,evidence_record_id,
    connected_source_observation_id,fulfillment_sha256,metadata
  ) values (
    (p_input->>'externalAcquisitionCommitmentId')::uuid,
    btrim(p_input->>'fulfillmentKey'),
    lower(btrim(p_input->>'fulfillmentKind')),
    (p_input->>'occurredAt')::timestamptz,
    lower(btrim(v_source->>'kind')),
    nullif(btrim(v_source->>'ref'),''),
    nullif(v_source->>'evidenceRecordId','')::uuid,
    nullif(v_source->>'connectedSourceObservationId','')::uuid,
    v_preview->>'fulfillmentSha256',
    coalesce(p_input->'metadata','{}'::jsonb)
  )
  returning id into v_fulfillment_id;

  for v_line in select value from jsonb_array_elements(p_input->'lines')
  loop
    insert into atlas.external_acquisition_fulfillment_lines(
      external_acquisition_fulfillment_id,line_key,
      external_acquisition_commitment_line_id,
      source_quantity,source_unit,
      delivered_output_quantity,accepted_output_quantity,
      rejected_output_quantity,unresolved_output_quantity,
      coverage_output_unit,condition,metadata
    ) values (
      v_fulfillment_id,
      btrim(v_line->>'lineKey'),
      (v_line->>'externalAcquisitionCommitmentLineId')::uuid,
      case when v_line->'sourceQuantity' is null
                or v_line->'sourceQuantity'='null'::jsonb
           then null else (v_line->>'sourceQuantity')::numeric end,
      nullif(lower(btrim(coalesce(v_line->>'sourceUnit',''))),''),
      (v_line->>'deliveredOutputQuantity')::numeric,
      (v_line->>'acceptedOutputQuantity')::numeric,
      (v_line->>'rejectedOutputQuantity')::numeric,
      (v_line->>'unresolvedOutputQuantity')::numeric,
      lower(btrim(v_line->>'coverageOutputUnit')),
      coalesce(v_line->'condition','{}'::jsonb),
      coalesce(v_line->'metadata','{}'::jsonb)
    )
    returning id into v_fulfillment_line_id;

    if jsonb_typeof(coalesce(v_line->'allocations','[]'::jsonb))='array' then
      for v_alloc in
        select value from jsonb_array_elements(coalesce(v_line->'allocations','[]'::jsonb))
      loop
        insert into atlas.external_acquisition_fulfillment_allocations(
          external_acquisition_fulfillment_line_id,allocation_key,
          external_acquisition_requirement_allocation_id,
          accepted_coverage_quantity,coverage_unit,metadata
        ) values (
          v_fulfillment_line_id,
          btrim(v_alloc->>'allocationKey'),
          (v_alloc->>'externalAcquisitionRequirementAllocationId')::uuid,
          (v_alloc->>'acceptedCoverageQuantity')::numeric,
          lower(btrim(v_alloc->>'coverageUnit')),
          coalesce(v_alloc->'metadata','{}'::jsonb)
        );
      end loop;
    end if;
  end loop;

  return jsonb_build_object(
    'contractVersion','record_external_acquisition_fulfillment_service_v1',
    'externalAcquisitionFulfillmentId',v_fulfillment_id,
    'created',true,
    'fulfillmentSha256',v_preview->>'fulfillmentSha256',
    'position',atlas.external_acquisition_fulfillment_position_v1(v_fulfillment_id),
    'commitmentPosition',
      atlas.external_acquisition_commitment_position_v1(
        (p_input->>'externalAcquisitionCommitmentId')::uuid
      ),
    'truthBoundary',jsonb_build_object(
      'createsExternalFulfillmentTruth',true,
      'createsAcceptedCoverageAllocations',true,
      'doesNotCreateInventory',true,
      'doesNotCreateSpend',true,
      'doesNotCreatePayment',true,
      'doesNotCreateCommercialOrder',true,
      'doesNotCreateWorkRequirement',true,
      'doesNotCloseCompanyWork',true
    )
  );
end;
$function$;


create or replace function atlas.record_external_acquisition_commitment_event_service_v1(
  p_external_acquisition_commitment_id uuid,
  p_event_key text,
  p_event_kind text,
  p_occurred_at timestamptz,
  p_source jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,extensions
as $function$
declare
  v_position jsonb;
  v_current_state text;
  v_kind text:=lower(btrim(coalesce(p_event_kind,'')));
  v_key text:=btrim(coalesce(p_event_key,''));
  v_source_kind text;
  v_hash text;
  v_existing atlas.external_acquisition_commitment_events%rowtype;
  v_commitment atlas.external_acquisition_commitments%rowtype;
  v_latest_at timestamptz;
  v_id uuid;
begin
  select * into v_commitment
  from atlas.external_acquisition_commitments
  where id=p_external_acquisition_commitment_id;

  if v_commitment.id is null then
    raise exception 'External Acquisition Commitment not found.'
      using errcode='P0002';
  end if;

  if v_key='' or v_kind not in ('cancelled','closed') or p_occurred_at is null then
    raise exception 'Event key, cancelled/closed event kind, and occurred time are required.'
      using errcode='22023';
  end if;

  if p_source is null or jsonb_typeof(p_source)<>'object'
     or nullif(btrim(coalesce(p_source->>'kind','')),'') is null then
    raise exception 'Event source requires a nonblank kind.'
      using errcode='22023';
  end if;

  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Event metadata must be an object.'
      using errcode='22023';
  end if;

  v_source_kind:=lower(btrim(p_source->>'kind'));

  v_hash:=encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'externalAcquisitionCommitmentId',p_external_acquisition_commitment_id,
          'eventKey',v_key,
          'eventKind',v_kind,
          'occurredAt',p_occurred_at,
          'source',p_source,
          'metadata',p_metadata
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  select * into v_existing
  from atlas.external_acquisition_commitment_events e
  where e.external_acquisition_commitment_id=p_external_acquisition_commitment_id
    and e.event_key=v_key;

  if v_existing.id is not null then
    if v_existing.event_sha256 is distinct from v_hash then
      raise exception 'External Acquisition Commitment event key conflicts with different truth.'
        using errcode='23505';
    end if;

    return jsonb_build_object(
      'contractVersion','record_external_acquisition_commitment_event_service_v1',
      'externalAcquisitionCommitmentEventId',v_existing.id,
      'created',false,
      'position',
        atlas.external_acquisition_commitment_position_v1(
          p_external_acquisition_commitment_id
        )
    );
  end if;

  v_position:=atlas.external_acquisition_commitment_position_v1(
    p_external_acquisition_commitment_id
  );
  v_current_state:=v_position->>'state';

  if not (
    (
      v_kind='cancelled'
      and v_current_state in (
        'committed',
        'partially_fulfilled',
        'fulfillment_unresolved',
        'fulfilled_with_exception'
      )
    )
    or
    (
      v_kind='closed'
      and v_current_state in (
        'cancelled',
        'fulfilled',
        'fulfilled_with_exception'
      )
    )
  ) then
    raise exception 'Invalid External Acquisition Commitment transition: % -> %.',
      v_current_state,v_kind
      using errcode='23514';
  end if;

  select max(e.occurred_at)
  into v_latest_at
  from atlas.external_acquisition_commitment_events e
  where e.external_acquisition_commitment_id=p_external_acquisition_commitment_id;

  if p_occurred_at<v_commitment.committed_at
     or (v_latest_at is not null and p_occurred_at<v_latest_at) then
    raise exception 'External Acquisition Commitment events must not precede commitment time or prior lifecycle evidence.'
      using errcode='23514';
  end if;

  insert into atlas.external_acquisition_commitment_events(
    external_acquisition_commitment_id,event_key,event_kind,occurred_at,
    source_kind,source_ref,evidence_record_id,connected_source_observation_id,
    event_sha256,metadata
  ) values (
    p_external_acquisition_commitment_id,v_key,v_kind,p_occurred_at,
    v_source_kind,
    nullif(btrim(p_source->>'ref'),''),
    nullif(p_source->>'evidenceRecordId','')::uuid,
    nullif(p_source->>'connectedSourceObservationId','')::uuid,
    v_hash,p_metadata
  )
  returning id into v_id;

  return jsonb_build_object(
    'contractVersion','record_external_acquisition_commitment_event_service_v1',
    'externalAcquisitionCommitmentEventId',v_id,
    'created',true,
    'position',
      atlas.external_acquisition_commitment_position_v1(
        p_external_acquisition_commitment_id
      )
  );
end;
$function$;


create or replace function atlas.external_acquisition_commitment_coverage_facts_v1(
  p_external_acquisition_commitment_id uuid
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas
as $function$
declare
  v_position jsonb;
  v_state text;
  v_release_residual boolean:=false;
  v_facts jsonb;
begin
  v_position:=atlas.external_acquisition_commitment_position_v1(
    p_external_acquisition_commitment_id
  );
  v_state:=v_position->>'state';
  v_release_residual:=v_state in ('cancelled','closed');

  select coalesce(
    jsonb_agg(x.fact order by x.sort_key,x.fact->>'workRequirementId'),
    '[]'::jsonb
  )
  into v_facts
  from (
    select
      '1:'||fa.id::text as sort_key,
      jsonb_build_object(
        'workRequirementId',ra.work_requirement_id,
        'coverageFact',jsonb_build_object(
          'coverageKey','external_acquisition_fulfillment:'||fa.id::text,
          'sourceRef',jsonb_build_object(
            'sourceDomain','external_acquisition_fulfillment_allocation',
            'sourceRef',fa.id::text
          ),
          'state','secured',
          'quantity',fa.accepted_coverage_quantity,
          'unit',fa.coverage_unit,
          'evidence',jsonb_build_array(jsonb_build_object(
            'source','external_acquisition_fulfillment',
            'externalAcquisitionCommitmentId',p_external_acquisition_commitment_id,
            'externalAcquisitionFulfillmentId',f.id,
            'externalAcquisitionFulfillmentLineId',fl.id,
            'externalAcquisitionFulfillmentAllocationId',fa.id
          )),
          'metadata',jsonb_build_object(
            'coverageLayer','accepted_external_fulfillment',
            'commitmentState',v_state
          )
        )
      ) as fact
    from atlas.external_acquisition_fulfillment_allocations fa
    join atlas.external_acquisition_fulfillment_lines fl
      on fl.id=fa.external_acquisition_fulfillment_line_id
    join atlas.external_acquisition_fulfillments f
      on f.id=fl.external_acquisition_fulfillment_id
    join atlas.external_acquisition_requirement_allocations ra
      on ra.id=fa.external_acquisition_requirement_allocation_id
    where f.external_acquisition_commitment_id=p_external_acquisition_commitment_id

    union all

    select
      '2:'||ra.id::text as sort_key,
      jsonb_build_object(
        'workRequirementId',ra.work_requirement_id,
        'coverageFact',jsonb_build_object(
          'coverageKey','external_acquisition_commitment_residual:'||ra.id::text,
          'sourceRef',jsonb_build_object(
            'sourceDomain','external_acquisition_requirement_allocation',
            'sourceRef',ra.id::text
          ),
          'state',case when v_release_residual then 'released' else 'secured' end,
          'quantity',
            greatest(
              ra.coverage_quantity-coalesce(ff.accepted_fulfilled,0),
              0
            ),
          'unit',ra.coverage_unit,
          'evidence',jsonb_build_array(jsonb_build_object(
            'source','external_acquisition_commitment',
            'externalAcquisitionCommitmentId',p_external_acquisition_commitment_id,
            'externalAcquisitionCommitmentLineId',
              ra.external_acquisition_commitment_line_id,
            'externalAcquisitionRequirementAllocationId',ra.id
          )),
          'metadata',jsonb_build_object(
            'coverageLayer','remaining_supplier_commitment',
            'commitmentState',v_state
          )
        )
      ) as fact
    from atlas.external_acquisition_requirement_allocations ra
    join atlas.external_acquisition_commitment_lines cl
      on cl.id=ra.external_acquisition_commitment_line_id
    left join lateral (
      select sum(fa.accepted_coverage_quantity) as accepted_fulfilled
      from atlas.external_acquisition_fulfillment_allocations fa
      where fa.external_acquisition_requirement_allocation_id=ra.id
    ) ff on true
    where cl.external_acquisition_commitment_id=p_external_acquisition_commitment_id
      and greatest(
        ra.coverage_quantity-coalesce(ff.accepted_fulfilled,0),
        0
      )>0
  ) x;

  return jsonb_build_object(
    'contractVersion','external_acquisition_commitment_coverage_facts_v1',
    'externalAcquisitionCommitmentId',p_external_acquisition_commitment_id,
    'commitmentState',v_state,
    'coverageMode','split_commitment_and_accepted_fulfillment',
    'facts',v_facts,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'acceptedFulfillmentAndResidualCommitmentDoNotOverlap',true,
      'cancelOrCloseReleasesOnlyResidualCommitmentCoverage',true,
      'rejectedOutputCreatesNoCoverage',true,
      'unresolvedOutputCreatesNoCoverage',true,
      'doesNotCreateCoverageRow',true,
      'doesNotCreateInventory',true,
      'doesNotCreateSpend',true,
      'doesNotCloseCompanyWork',true
    )
  );
end;
$function$;


alter table atlas.external_acquisition_fulfillments enable row level security;
alter table atlas.external_acquisition_fulfillment_lines enable row level security;
alter table atlas.external_acquisition_fulfillment_allocations enable row level security;

revoke all on atlas.external_acquisition_fulfillments
  from public,anon,authenticated,service_role;
revoke all on atlas.external_acquisition_fulfillment_lines
  from public,anon,authenticated,service_role;
revoke all on atlas.external_acquisition_fulfillment_allocations
  from public,anon,authenticated,service_role;

grant select on atlas.external_acquisition_fulfillments to service_role;
grant select on atlas.external_acquisition_fulfillment_lines to service_role;
grant select on atlas.external_acquisition_fulfillment_allocations to service_role;

revoke all on function atlas.external_acquisition_fulfillment_preview_v1(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.external_acquisition_fulfillment_preview_v1(jsonb)
  to service_role;

revoke all on function atlas.record_external_acquisition_fulfillment_service_v1(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.record_external_acquisition_fulfillment_service_v1(jsonb)
  to service_role;

revoke all on function atlas.external_acquisition_fulfillment_position_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.external_acquisition_fulfillment_position_v1(uuid)
  to service_role;


insert into atlas.architecture_truth_authorities(
  authority_key,domain_key,truth_question,authority_owner,authority_status,
  canonical_relations,canonical_functions,supporting_relations,
  consumer_surfaces,known_competitors,source_custody,rationale,updated_at
) values (
  'external_acquisition_fulfillment',
  'commercial_supply',
  'What did an external supplier actually deliver or perform against an acquisition commitment, in what quantity and condition, and what accepted output now secures Company Work?',
  'external_acquisition_fulfillments + lines + accepted requirement allocations',
  'canonical',
  array[
    'atlas.external_acquisition_fulfillments',
    'atlas.external_acquisition_fulfillment_lines',
    'atlas.external_acquisition_fulfillment_allocations'
  ],
  array[
    'atlas.external_acquisition_fulfillment_preview_v1',
    'atlas.record_external_acquisition_fulfillment_service_v1',
    'atlas.external_acquisition_fulfillment_position_v1',
    'atlas.external_acquisition_commitment_position_v1',
    'atlas.external_acquisition_commitment_coverage_facts_v1'
  ],
  array[
    'atlas.external_acquisition_commitments',
    'atlas.external_acquisition_commitment_lines',
    'atlas.external_acquisition_requirement_allocations',
    'atlas.work_requirements',
    'atlas.evidence_records',
    'atlas.connected_source_observations'
  ],
  array[]::text[],
  array[
    'atlas.flower_external_intakes',
    'atlas.flower_ready_inventory_lots',
    'atlas.work_execution_results',
    'atlas.work_result_acceptances',
    'atlas.organization_spend_occurrences'
  ],
  'Actual supplier fulfillment remains separate from source commitment, inventory, internal work execution, and occurred Spend. Accepted output may feed those domains later through explicit adapters.',
  'Provides a partial, quantitative, source-owned handoff from outstanding supplier commitment coverage to actual accepted delivery/performance coverage without double counting.',
  now()
)
on conflict(authority_key) do update set
  domain_key=excluded.domain_key,
  truth_question=excluded.truth_question,
  authority_owner=excluded.authority_owner,
  authority_status=excluded.authority_status,
  canonical_relations=excluded.canonical_relations,
  canonical_functions=excluded.canonical_functions,
  supporting_relations=excluded.supporting_relations,
  consumer_surfaces=excluded.consumer_surfaces,
  known_competitors=excluded.known_competitors,
  source_custody=excluded.source_custody,
  rationale=excluded.rationale,
  updated_at=now();


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values
(
  'atlas.external_acquisition_fulfillment_preview_v1(jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_external_acquisition_fulfillment_intake_v1","purpose":"Read-only validation of actual external supplier delivery/performance intake.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.record_external_acquisition_fulfillment_service_v1(jsonb)',
  'service_internal','verified','active',
  false,true,true,0,1,
  '{"source":"atlas_external_acquisition_fulfillment_intake_v1","purpose":"Persist immutable actual external supplier delivery/performance and accepted Company Work allocations; creates no inventory or Spend.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.external_acquisition_fulfillment_position_v1(uuid)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_external_acquisition_fulfillment_intake_v1","purpose":"Read one external supplier fulfillment occurrence with accepted/rejected/unresolved output and accepted allocations.","classificationRuleVersion":3}'::jsonb,
  false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  reviewed_at=now();

commit;
