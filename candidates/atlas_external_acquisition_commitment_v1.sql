begin;

create table if not exists atlas.external_acquisition_commitments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid,
  supplier_relationship_id uuid not null
    references atlas.external_relationships(id) on delete restrict,
  commitment_key text not null,
  commitment_kind text not null default 'supplier_order',
  committed_at timestamptz not null,
  expected_fulfillment_from_at timestamptz,
  expected_fulfillment_by_at timestamptz,
  economic_state text not null
    check (economic_state in ('known','partially_known','unresolved')),
  known_committed_amount numeric(14,4)
    check (known_committed_amount is null or known_committed_amount>=0),
  currency text
    check (currency is null or currency ~ '^[A-Z]{3}$'),
  cost_components jsonb not null default '[]'::jsonb
    check (jsonb_typeof(cost_components)='array'),
  accepted_terms jsonb not null default '{}'::jsonb
    check (jsonb_typeof(accepted_terms)='object'),
  source_kind text not null,
  source_ref text,
  evidence_record_id uuid
    references atlas.evidence_records(id) on delete restrict,
  connected_source_observation_id uuid
    references atlas.connected_source_observations(id) on delete restrict,
  authorization_basis jsonb not null
    check (jsonb_typeof(authorization_basis)='object'),
  commitment_sha256 text not null
    check (commitment_sha256 ~ '^[0-9a-f]{64}$'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint external_acquisition_commitments_unit_org_fk
    foreign key (organization_id,organization_unit_id)
    references atlas.organization_units(organization_id,id)
    on delete restrict,
  constraint external_acquisition_commitments_key_nonblank
    check (btrim(commitment_key)<>''),
  constraint external_acquisition_commitments_kind_nonblank
    check (btrim(commitment_kind)<>''),
  constraint external_acquisition_commitments_source_kind_nonblank
    check (btrim(source_kind)<>''),
  constraint external_acquisition_commitments_source_ref_nonblank
    check (source_ref is null or btrim(source_ref)<>''),
  constraint external_acquisition_commitments_window
    check (
      expected_fulfillment_by_at is null
      or expected_fulfillment_from_at is null
      or expected_fulfillment_by_at>=expected_fulfillment_from_at
    ),
  constraint external_acquisition_commitments_economics_shape
    check (
      (
        economic_state in ('known','partially_known')
        and known_committed_amount is not null
        and currency is not null
      )
      or
      (
        economic_state='unresolved'
        and known_committed_amount is null
      )
    ),
  unique(organization_id,commitment_key)
);

create index if not exists external_acquisition_commitments_supplier_idx
  on atlas.external_acquisition_commitments(
    supplier_relationship_id,committed_at desc,id
  );

comment on table atlas.external_acquisition_commitments is
'Immutable organization buy-side commitment to an external supplier. It records accepted acquisition terms and financial-obligation position but is not Organization Spend, payment, received inventory, sell-side Commercial Order, or supplier execution authority.';


create table if not exists atlas.external_acquisition_commitment_lines (
  id uuid primary key default gen_random_uuid(),
  external_acquisition_commitment_id uuid not null
    references atlas.external_acquisition_commitments(id) on delete restrict,
  line_key text not null,
  external_supply_offering_id uuid not null
    references atlas.external_supply_offerings(id) on delete restrict,
  external_supply_offer_observation_id uuid
    references atlas.external_supply_offer_observations(id) on delete restrict,
  source_line_key text,
  description text not null,
  ordered_quantity numeric(14,3) not null
    check (ordered_quantity>0),
  ordered_unit text not null,
  coverage_output_quantity numeric(14,3) not null
    check (coverage_output_quantity>0),
  coverage_output_unit text not null,
  known_line_amount numeric(14,4)
    check (known_line_amount is null or known_line_amount>=0),
  currency text
    check (currency is null or currency ~ '^[A-Z]{3}$'),
  accepted_terms jsonb not null default '{}'::jsonb
    check (jsonb_typeof(accepted_terms)='object'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint external_acquisition_commitment_lines_key_nonblank
    check (btrim(line_key)<>''),
  constraint external_acquisition_commitment_lines_source_line_nonblank
    check (source_line_key is null or btrim(source_line_key)<>''),
  constraint external_acquisition_commitment_lines_description_nonblank
    check (btrim(description)<>''),
  constraint external_acquisition_commitment_lines_ordered_unit_nonblank
    check (btrim(ordered_unit)<>''),
  constraint external_acquisition_commitment_lines_output_unit_nonblank
    check (btrim(coverage_output_unit)<>''),
  constraint external_acquisition_commitment_lines_amount_currency_pair
    check (
      (known_line_amount is null and currency is null)
      or
      (known_line_amount is not null and currency is not null)
    ),
  unique(external_acquisition_commitment_id,line_key)
);

create index if not exists external_acquisition_commitment_lines_offering_idx
  on atlas.external_acquisition_commitment_lines(
    external_supply_offering_id,external_acquisition_commitment_id
  );

comment on table atlas.external_acquisition_commitment_lines is
'Immutable accepted line of an External Acquisition Commitment. Ordered source quantity remains distinct from planned coverage-output quantity; neither quantity is received inventory.';


create table if not exists atlas.external_acquisition_requirement_allocations (
  id uuid primary key default gen_random_uuid(),
  external_acquisition_commitment_line_id uuid not null
    references atlas.external_acquisition_commitment_lines(id) on delete restrict,
  allocation_key text not null,
  work_requirement_id uuid not null
    references atlas.work_requirements(id) on delete restrict,
  coverage_quantity numeric(14,3) not null
    check (coverage_quantity>0),
  coverage_unit text not null,
  qualification_basis jsonb not null default '{}'::jsonb
    check (jsonb_typeof(qualification_basis)='object'),
  planning_basis jsonb not null default '{}'::jsonb
    check (jsonb_typeof(planning_basis)='object'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint external_acquisition_requirement_allocations_key_nonblank
    check (btrim(allocation_key)<>''),
  constraint external_acquisition_requirement_allocations_unit_nonblank
    check (btrim(coverage_unit)<>''),
  unique(external_acquisition_commitment_line_id,allocation_key),
  unique(external_acquisition_commitment_line_id,work_requirement_id)
);

create index if not exists external_acquisition_requirement_allocations_requirement_idx
  on atlas.external_acquisition_requirement_allocations(
    work_requirement_id,external_acquisition_commitment_line_id
  );

comment on table atlas.external_acquisition_requirement_allocations is
'Immutable source-owned allocation from one committed external acquisition line to one Company Work Requirement. It creates secured external-source coverage while the supplier commitment remains active; it is not a generic coverage row.';


create table if not exists atlas.external_acquisition_commitment_events (
  id uuid primary key default gen_random_uuid(),
  external_acquisition_commitment_id uuid not null
    references atlas.external_acquisition_commitments(id) on delete restrict,
  event_key text not null,
  event_kind text not null
    check (event_kind in ('cancelled','received','closed')),
  occurred_at timestamptz not null,
  source_kind text not null,
  source_ref text,
  evidence_record_id uuid
    references atlas.evidence_records(id) on delete restrict,
  connected_source_observation_id uuid
    references atlas.connected_source_observations(id) on delete restrict,
  event_sha256 text not null
    check (event_sha256 ~ '^[0-9a-f]{64}$'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint external_acquisition_commitment_events_key_nonblank
    check (btrim(event_key)<>''),
  constraint external_acquisition_commitment_events_source_kind_nonblank
    check (btrim(source_kind)<>''),
  constraint external_acquisition_commitment_events_source_ref_nonblank
    check (source_ref is null or btrim(source_ref)<>''),
  unique(external_acquisition_commitment_id,event_key)
);

create index if not exists external_acquisition_commitment_events_position_idx
  on atlas.external_acquisition_commitment_events(
    external_acquisition_commitment_id,occurred_at desc,created_at desc,id
  );

comment on table atlas.external_acquisition_commitment_events is
'Append-only lifecycle evidence for one External Acquisition Commitment. V1 supports cancelled, received, and closed; received hands current coverage to receiving/inventory/performance truth rather than asserting inventory itself.';


create or replace function atlas.guard_external_acquisition_scope_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_relationship atlas.external_relationships%rowtype;
  v_commitment atlas.external_acquisition_commitments%rowtype;
  v_offering atlas.external_supply_offerings%rowtype;
  v_observation atlas.external_supply_offer_observations%rowtype;
  v_line atlas.external_acquisition_commitment_lines%rowtype;
  v_requirement atlas.work_requirements%rowtype;
  v_total numeric;
begin
  if tg_table_name='external_acquisition_commitments' then
    select * into v_relationship
    from atlas.external_relationships
    where id=new.supplier_relationship_id;

    if v_relationship.id is null
       or v_relationship.organization_id is distinct from new.organization_id
       or v_relationship.organization_unit_id is distinct from new.organization_unit_id then
      raise exception 'External Acquisition Commitment must share supplier relationship organization/unit scope.'
        using errcode='23514';
    end if;

    if not exists(
      select 1
      from atlas.external_relationship_roles rr
      where rr.external_relationship_id=new.supplier_relationship_id
        and rr.role_key='supplier'
        and rr.role_state='active'
    ) then
      raise exception 'External Acquisition Commitment requires an active supplier relationship role.'
        using errcode='23514';
    end if;

    if new.connected_source_observation_id is not null
       and not exists(
         select 1
         from atlas.connected_source_observations cso
         join atlas.connected_sources cs on cs.id=cso.connected_source_id
         where cso.id=new.connected_source_observation_id
           and cs.custodian_organization_id=new.organization_id
           and (
             cs.custodian_organization_unit_id is null
             or cs.custodian_organization_unit_id is not distinct from new.organization_unit_id
           )
       ) then
      raise exception 'Connected source observation must belong to the same organization/unit scope.'
        using errcode='23514';
    end if;

    if nullif(btrim(coalesce(new.authorization_basis->>'authorityRef','')),'') is null
       or nullif(btrim(coalesce(new.authorization_basis->>'decisionRef','')),'') is null
       or nullif(btrim(coalesce(new.authorization_basis->>'authorizedAt','')),'') is null then
      raise exception 'External Acquisition Commitment requires authorityRef, decisionRef, and authorizedAt.'
        using errcode='23514';
    end if;

    begin
      perform (new.authorization_basis->>'authorizedAt')::timestamptz;
    exception when others then
      raise exception 'authorizationBasis.authorizedAt must be a valid timestamp.'
        using errcode='23514';
    end;

    new.commitment_key:=btrim(new.commitment_key);
    new.commitment_kind:=lower(btrim(new.commitment_kind));
    new.currency:=case when new.currency is null then null else upper(btrim(new.currency)) end;
    new.source_kind:=lower(btrim(new.source_kind));
    new.source_ref:=nullif(btrim(new.source_ref),'');
    return new;
  end if;

  if tg_table_name='external_acquisition_commitment_lines' then
    select * into v_commitment
    from atlas.external_acquisition_commitments
    where id=new.external_acquisition_commitment_id;

    select * into v_offering
    from atlas.external_supply_offerings
    where id=new.external_supply_offering_id;

    if v_commitment.id is null or v_offering.id is null
       or v_offering.organization_id is distinct from v_commitment.organization_id
       or v_offering.organization_unit_id is distinct from v_commitment.organization_unit_id
       or v_offering.supplier_relationship_id is distinct from v_commitment.supplier_relationship_id then
      raise exception 'Acquisition line offering must belong to the same supplier and organization/unit scope.'
        using errcode='23514';
    end if;

    if new.external_supply_offer_observation_id is not null then
      select * into v_observation
      from atlas.external_supply_offer_observations
      where id=new.external_supply_offer_observation_id;

      if v_observation.id is null
         or v_observation.external_supply_offering_id is distinct from new.external_supply_offering_id then
        raise exception 'Accepted supplier observation must belong to the acquisition line offering.'
          using errcode='23514';
      end if;
    end if;

    new.line_key:=btrim(new.line_key);
    new.source_line_key:=nullif(btrim(new.source_line_key),'');
    new.description:=btrim(new.description);
    new.ordered_unit:=lower(btrim(new.ordered_unit));
    new.coverage_output_unit:=lower(btrim(new.coverage_output_unit));
    new.currency:=case when new.currency is null then null else upper(btrim(new.currency)) end;

    if new.currency is not null
       and v_commitment.currency is not null
       and new.currency is distinct from v_commitment.currency then
      raise exception 'Acquisition line currency must match commitment currency in V1.'
        using errcode='23514';
    end if;

    return new;
  end if;

  if tg_table_name='external_acquisition_requirement_allocations' then
    select * into v_line
    from atlas.external_acquisition_commitment_lines
    where id=new.external_acquisition_commitment_line_id;

    select * into v_commitment
    from atlas.external_acquisition_commitments
    where id=v_line.external_acquisition_commitment_id;

    select * into v_requirement
    from atlas.work_requirements
    where id=new.work_requirement_id;

    if v_line.id is null or v_commitment.id is null or v_requirement.id is null
       or v_requirement.organization_id is distinct from v_commitment.organization_id then
      raise exception 'Acquisition allocation must remain inside the commitment organization scope.'
        using errcode='23514';
    end if;

    if v_requirement.state<>'active' then
      raise exception 'Acquisition allocation requires an active Company Work Requirement.'
        using errcode='23514';
    end if;

    if jsonb_typeof(v_requirement.metadata->'commercialFulfillment'->'quantity')<>'number'
       or nullif(btrim(coalesce(v_requirement.metadata->'commercialFulfillment'->>'unit','')),'') is null then
      raise exception 'Acquisition allocation requires a quantified Company Work Requirement.'
        using errcode='23514';
    end if;

    new.allocation_key:=btrim(new.allocation_key);
    new.coverage_unit:=lower(btrim(new.coverage_unit));

    if new.coverage_unit is distinct from v_line.coverage_output_unit
       or new.coverage_unit is distinct from lower(btrim(v_requirement.metadata->'commercialFulfillment'->>'unit')) then
      raise exception 'Acquisition allocation unit must match both line coverage-output unit and Work Requirement unit.'
        using errcode='23514';
    end if;

    if new.coverage_quantity>(v_requirement.metadata->'commercialFulfillment'->>'quantity')::numeric then
      raise exception 'Acquisition allocation cannot exceed the Work Requirement total quantity.'
        using errcode='23514';
    end if;

    select coalesce(sum(a.coverage_quantity),0)
    into v_total
    from atlas.external_acquisition_requirement_allocations a
    where a.external_acquisition_commitment_line_id=new.external_acquisition_commitment_line_id;

    if v_total+new.coverage_quantity>v_line.coverage_output_quantity then
      raise exception 'Acquisition allocations cannot exceed line coverage-output quantity.'
        using errcode='23514';
    end if;

    return new;
  end if;

  select * into v_commitment
  from atlas.external_acquisition_commitments
  where id=new.external_acquisition_commitment_id;

  if v_commitment.id is null then
    raise exception 'External Acquisition Commitment not found.'
      using errcode='P0002';
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
           or cs.custodian_organization_unit_id is not distinct from v_commitment.organization_unit_id
         )
     ) then
    raise exception 'Commitment event connected-source observation must share organization/unit scope.'
      using errcode='23514';
  end if;

  new.event_key:=btrim(new.event_key);
  new.source_kind:=lower(btrim(new.source_kind));
  new.source_ref:=nullif(btrim(new.source_ref),'');
  return new;
end;
$function$;


drop trigger if exists external_acquisition_commitments_scope_guard_v1
  on atlas.external_acquisition_commitments;
create trigger external_acquisition_commitments_scope_guard_v1
before insert on atlas.external_acquisition_commitments
for each row execute function atlas.guard_external_acquisition_scope_v1();

drop trigger if exists external_acquisition_commitment_lines_scope_guard_v1
  on atlas.external_acquisition_commitment_lines;
create trigger external_acquisition_commitment_lines_scope_guard_v1
before insert on atlas.external_acquisition_commitment_lines
for each row execute function atlas.guard_external_acquisition_scope_v1();

drop trigger if exists external_acquisition_requirement_allocations_scope_guard_v1
  on atlas.external_acquisition_requirement_allocations;
create trigger external_acquisition_requirement_allocations_scope_guard_v1
before insert on atlas.external_acquisition_requirement_allocations
for each row execute function atlas.guard_external_acquisition_scope_v1();

drop trigger if exists external_acquisition_commitment_events_scope_guard_v1
  on atlas.external_acquisition_commitment_events;
create trigger external_acquisition_commitment_events_scope_guard_v1
before insert on atlas.external_acquisition_commitment_events
for each row execute function atlas.guard_external_acquisition_scope_v1();


create or replace function atlas.prevent_external_acquisition_history_mutation_v1()
returns trigger
language plpgsql
set search_path=pg_catalog,atlas
as $function$
begin
  raise exception 'External Acquisition Commitment history is immutable; record later lifecycle evidence instead.'
    using errcode='55000';
end;
$function$;

drop trigger if exists external_acquisition_commitments_immutable_v1
  on atlas.external_acquisition_commitments;
create trigger external_acquisition_commitments_immutable_v1
before update or delete on atlas.external_acquisition_commitments
for each row execute function atlas.prevent_external_acquisition_history_mutation_v1();

drop trigger if exists external_acquisition_commitment_lines_immutable_v1
  on atlas.external_acquisition_commitment_lines;
create trigger external_acquisition_commitment_lines_immutable_v1
before update or delete on atlas.external_acquisition_commitment_lines
for each row execute function atlas.prevent_external_acquisition_history_mutation_v1();

drop trigger if exists external_acquisition_requirement_allocations_immutable_v1
  on atlas.external_acquisition_requirement_allocations;
create trigger external_acquisition_requirement_allocations_immutable_v1
before update or delete on atlas.external_acquisition_requirement_allocations
for each row execute function atlas.prevent_external_acquisition_history_mutation_v1();

drop trigger if exists external_acquisition_commitment_events_immutable_v1
  on atlas.external_acquisition_commitment_events;
create trigger external_acquisition_commitment_events_immutable_v1
before update or delete on atlas.external_acquisition_commitment_events
for each row execute function atlas.prevent_external_acquisition_history_mutation_v1();


create or replace function atlas.external_acquisition_commitment_preview_v1(
  p_input jsonb
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas,extensions
as $function$
declare
  v_org_id uuid;
  v_unit_id uuid;
  v_supplier_id uuid;
  v_relationship atlas.external_relationships%rowtype;
  v_commitment_key text;
  v_commitment_kind text;
  v_committed_at timestamptz;
  v_from_at timestamptz;
  v_by_at timestamptz;
  v_authorized_at timestamptz;
  v_economics jsonb;
  v_economic_state text;
  v_known_amount numeric;
  v_currency text;
  v_cost_components jsonb;
  v_source jsonb;
  v_source_kind text;
  v_line jsonb;
  v_alloc jsonb;
  v_offering atlas.external_supply_offerings%rowtype;
  v_observation atlas.external_supply_offer_observations%rowtype;
  v_requirement atlas.work_requirements%rowtype;
  v_line_keys text[]:='{}'::text[];
  v_alloc_keys text[];
  v_alloc_requirement_ids uuid[];
  v_line_key text;
  v_alloc_key text;
  v_offering_id uuid;
  v_observation_id uuid;
  v_requirement_id uuid;
  v_ordered_quantity numeric;
  v_ordered_unit text;
  v_output_quantity numeric;
  v_output_unit text;
  v_alloc_quantity numeric;
  v_alloc_unit text;
  v_alloc_total numeric;
  v_line_count integer:=0;
  v_allocation_count integer:=0;
  v_violations jsonb:='[]'::jsonb;
  v_warnings jsonb:='[]'::jsonb;
  v_hash text;
  v_existing atlas.external_acquisition_commitments%rowtype;
begin
  if p_input is null or jsonb_typeof(p_input)<>'object' then
    return jsonb_build_object(
      'contractVersion','external_acquisition_commitment_preview_v1',
      'state','blocked',
      'violations',jsonb_build_array(jsonb_build_object('key','input_not_object'))
    );
  end if;

  if p_input->>'contractVersion'<>'external_acquisition_commitment_input_v1' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','unsupported_contract_version'
    ));
  end if;

  begin
    v_org_id:=(p_input->>'organizationId')::uuid;
  exception when others then
    v_org_id:=null;
  end;

  begin
    v_unit_id:=nullif(btrim(coalesce(p_input->>'organizationUnitId','')),'')::uuid;
  exception when others then
    v_unit_id:=null;
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_organization_unit_id'
    ));
  end;

  begin
    v_supplier_id:=(p_input->>'supplierRelationshipId')::uuid;
  exception when others then
    v_supplier_id:=null;
  end;

  if v_org_id is null or not exists(select 1 from atlas.organizations where id=v_org_id) then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_organization_id'
    ));
  end if;

  select * into v_relationship
  from atlas.external_relationships
  where id=v_supplier_id;

  if v_relationship.id is null
     or v_relationship.organization_id is distinct from v_org_id
     or v_relationship.organization_unit_id is distinct from v_unit_id
     or not exists(
       select 1 from atlas.external_relationship_roles rr
       where rr.external_relationship_id=v_supplier_id
         and rr.role_key='supplier'
         and rr.role_state='active'
     ) then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_supplier_scope_or_role'
    ));
  end if;

  v_commitment_key:=nullif(btrim(coalesce(p_input->>'commitmentKey','')),'');
  v_commitment_kind:=nullif(lower(btrim(coalesce(p_input->>'commitmentKind','supplier_order'))),'');
  if v_commitment_key is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','missing_commitment_key'));
  end if;
  if v_commitment_kind is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','missing_commitment_kind'));
  end if;

  begin
    v_committed_at:=(p_input->>'committedAt')::timestamptz;
  exception when others then
    v_committed_at:=null;
  end;
  if v_committed_at is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_committed_at'));
  end if;

  if nullif(btrim(coalesce(p_input->>'expectedFulfillmentFromAt','')),'') is not null then
    begin
      v_from_at:=(p_input->>'expectedFulfillmentFromAt')::timestamptz;
    exception when others then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_expected_fulfillment_from'));
    end;
  end if;

  if nullif(btrim(coalesce(p_input->>'expectedFulfillmentByAt','')),'') is not null then
    begin
      v_by_at:=(p_input->>'expectedFulfillmentByAt')::timestamptz;
    exception when others then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_expected_fulfillment_by'));
    end;
  end if;

  if v_from_at is not null and v_by_at is not null and v_by_at<v_from_at then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_fulfillment_window'));
  end if;

  if jsonb_typeof(p_input->'acceptedTerms')<>'object' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_accepted_terms'));
  end if;

  if jsonb_typeof(p_input->'authorizationBasis')<>'object'
     or nullif(btrim(coalesce(p_input->'authorizationBasis'->>'authorityRef','')),'') is null
     or nullif(btrim(coalesce(p_input->'authorizationBasis'->>'decisionRef','')),'') is null
     or nullif(btrim(coalesce(p_input->'authorizationBasis'->>'authorizedAt','')),'') is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_authorization_basis'));
  else
    begin
      v_authorized_at:=(p_input->'authorizationBasis'->>'authorizedAt')::timestamptz;
    exception when others then
      v_authorized_at:=null;
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_authorized_at'));
    end;
  end if;

  if v_authorized_at is not null
     and v_committed_at is not null
     and v_authorized_at>v_committed_at then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','authorization_after_commitment',
      'authorizedAt',v_authorized_at,
      'committedAt',v_committed_at
    ));
  end if;

  v_economics:=p_input->'economics';
  if v_economics is null or jsonb_typeof(v_economics)<>'object' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_economics'));
  else
    v_economic_state:=lower(btrim(coalesce(v_economics->>'state','')));
    if v_economic_state not in ('known','partially_known','unresolved') then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_economic_state'));
    end if;

    if v_economics ? 'knownCommittedAmount' and v_economics->'knownCommittedAmount'<>'null'::jsonb then
      if jsonb_typeof(v_economics->'knownCommittedAmount')<>'number' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_known_committed_amount'));
      else
        v_known_amount:=(v_economics->>'knownCommittedAmount')::numeric;
        if v_known_amount<0 then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','negative_known_committed_amount'));
        end if;
      end if;
    end if;

    v_currency:=nullif(upper(btrim(coalesce(v_economics->>'currency',''))),'');
    if v_currency is not null and v_currency !~ '^[A-Z]{3}$' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_currency'));
    end if;

    if v_economic_state in ('known','partially_known')
       and (v_known_amount is null or v_currency is null) then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','known_economics_missing_amount_or_currency'));
    end if;

    if v_economic_state='unresolved' and v_known_amount is not null then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','unresolved_economics_has_amount'));
    end if;

    v_cost_components:=coalesce(v_economics->'costComponents','[]'::jsonb);
    if jsonb_typeof(v_cost_components)<>'array' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_cost_components'));
    elsif v_economic_state='partially_known'
       and not exists(
         select 1
         from jsonb_array_elements(v_cost_components) c
         where c->>'state'='unresolved'
           and coalesce((c->>'required')::boolean,true)
       ) then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','partially_known_requires_unresolved_component'));
    end if;
  end if;

  v_source:=p_input->'source';
  if v_source is null or jsonb_typeof(v_source)<>'object'
     or nullif(btrim(coalesce(v_source->>'kind','')),'') is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_source'));
  else
    v_source_kind:=lower(btrim(v_source->>'kind'));
  end if;

  if p_input ? 'metadata' and jsonb_typeof(p_input->'metadata')<>'object' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_metadata'));
  end if;

  if jsonb_typeof(p_input->'lines')<>'array'
     or jsonb_array_length(coalesce(p_input->'lines','[]'::jsonb))=0 then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','missing_lines'));
  else
    for v_line in select value from jsonb_array_elements(p_input->'lines')
    loop
      v_line_count:=v_line_count+1;
      v_alloc_total:=0;
      v_alloc_keys:='{}'::text[];
      v_alloc_requirement_ids:='{}'::uuid[];

      if jsonb_typeof(v_line)<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','line_not_object','lineIndex',v_line_count));
        continue;
      end if;

      v_line_key:=nullif(btrim(coalesce(v_line->>'lineKey','')),'');
      if v_line_key is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','missing_line_key','lineIndex',v_line_count));
        continue;
      elsif v_line_key=any(v_line_keys) then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','duplicate_line_key','lineKey',v_line_key));
        continue;
      else
        v_line_keys:=array_append(v_line_keys,v_line_key);
      end if;

      begin
        v_offering_id:=(v_line->>'externalSupplyOfferingId')::uuid;
      exception when others then
        v_offering_id:=null;
      end;

      select * into v_offering
      from atlas.external_supply_offerings
      where id=v_offering_id;

      if v_offering.id is null
         or v_offering.organization_id is distinct from v_org_id
         or v_offering.organization_unit_id is distinct from v_unit_id
         or v_offering.supplier_relationship_id is distinct from v_supplier_id then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_line_offering','lineKey',v_line_key));
      end if;

      v_observation_id:=null;
      if nullif(btrim(coalesce(v_line->>'externalSupplyOfferObservationId','')),'') is not null then
        begin
          v_observation_id:=(v_line->>'externalSupplyOfferObservationId')::uuid;
        exception when others then
          v_observation_id:=null;
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_line_observation_id','lineKey',v_line_key));
        end;

        select * into v_observation
        from atlas.external_supply_offer_observations
        where id=v_observation_id;

        if v_observation.id is null
           or v_observation.external_supply_offering_id is distinct from v_offering_id then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','line_observation_wrong_offering','lineKey',v_line_key));
        end if;
      end if;

      if jsonb_typeof(v_line->'orderedQuantity')<>'number'
         or (v_line->>'orderedQuantity')::numeric<=0 then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_ordered_quantity','lineKey',v_line_key));
      else
        v_ordered_quantity:=(v_line->>'orderedQuantity')::numeric;
      end if;

      v_ordered_unit:=nullif(lower(btrim(coalesce(v_line->>'orderedUnit',''))),'');
      if v_ordered_unit is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_ordered_unit','lineKey',v_line_key));
      end if;

      if jsonb_typeof(v_line->'coverageOutputQuantity')<>'number'
         or (v_line->>'coverageOutputQuantity')::numeric<=0 then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_coverage_output_quantity','lineKey',v_line_key));
      else
        v_output_quantity:=(v_line->>'coverageOutputQuantity')::numeric;
      end if;

      v_output_unit:=nullif(lower(btrim(coalesce(v_line->>'coverageOutputUnit',''))),'');
      if v_output_unit is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_coverage_output_unit','lineKey',v_line_key));
      end if;

      if nullif(btrim(coalesce(v_line->>'description','')),'') is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','missing_line_description','lineKey',v_line_key));
      end if;

      if v_line ? 'knownLineAmount' and v_line->'knownLineAmount'<>'null'::jsonb then
        if jsonb_typeof(v_line->'knownLineAmount')<>'number'
           or (v_line->>'knownLineAmount')::numeric<0
           or nullif(upper(btrim(coalesce(v_line->>'currency',''))),'') is null then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_line_amount','lineKey',v_line_key));
        elsif v_currency is not null
           and upper(btrim(v_line->>'currency'))<>v_currency then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','line_currency_mismatch','lineKey',v_line_key));
        end if;
      elsif v_line ? 'currency' and nullif(btrim(coalesce(v_line->>'currency','')),'') is not null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','line_currency_without_amount','lineKey',v_line_key));
      end if;

      if v_line ? 'acceptedTerms' and jsonb_typeof(v_line->'acceptedTerms')<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_line_terms','lineKey',v_line_key));
      end if;
      if v_line ? 'metadata' and jsonb_typeof(v_line->'metadata')<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_line_metadata','lineKey',v_line_key));
      end if;

      if v_line ? 'allocations' then
        if jsonb_typeof(v_line->'allocations')<>'array' then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_allocations','lineKey',v_line_key));
        else
          for v_alloc in select value from jsonb_array_elements(v_line->'allocations')
          loop
            v_allocation_count:=v_allocation_count+1;
            if jsonb_typeof(v_alloc)<>'object' then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','allocation_not_object','lineKey',v_line_key));
              continue;
            end if;

            v_alloc_key:=nullif(btrim(coalesce(v_alloc->>'allocationKey','')),'');
            if v_alloc_key is null then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','missing_allocation_key','lineKey',v_line_key));
              continue;
            elsif v_alloc_key=any(v_alloc_keys) then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','duplicate_allocation_key','lineKey',v_line_key,'allocationKey',v_alloc_key));
              continue;
            else
              v_alloc_keys:=array_append(v_alloc_keys,v_alloc_key);
            end if;

            begin
              v_requirement_id:=(v_alloc->>'workRequirementId')::uuid;
            exception when others then
              v_requirement_id:=null;
            end;

            if v_requirement_id is null then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_work_requirement_id','lineKey',v_line_key,'allocationKey',v_alloc_key));
              continue;
            elsif v_requirement_id=any(v_alloc_requirement_ids) then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','duplicate_line_work_requirement','lineKey',v_line_key,'workRequirementId',v_requirement_id));
              continue;
            else
              v_alloc_requirement_ids:=array_append(v_alloc_requirement_ids,v_requirement_id);
            end if;

            select * into v_requirement
            from atlas.work_requirements
            where id=v_requirement_id;

            if v_requirement.id is null
               or v_requirement.organization_id is distinct from v_org_id
               or v_requirement.state<>'active'
               or jsonb_typeof(v_requirement.metadata->'commercialFulfillment'->'quantity')<>'number'
               or nullif(btrim(coalesce(v_requirement.metadata->'commercialFulfillment'->>'unit','')),'') is null then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_allocation_requirement','lineKey',v_line_key,'allocationKey',v_alloc_key));
              continue;
            end if;

            if jsonb_typeof(v_alloc->'coverageQuantity')<>'number'
               or (v_alloc->>'coverageQuantity')::numeric<=0 then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_allocation_quantity','lineKey',v_line_key,'allocationKey',v_alloc_key));
              continue;
            else
              v_alloc_quantity:=(v_alloc->>'coverageQuantity')::numeric;
            end if;

            v_alloc_unit:=nullif(lower(btrim(coalesce(v_alloc->>'coverageUnit',''))),'');
            if v_alloc_unit is null
               or v_alloc_unit is distinct from v_output_unit
               or v_alloc_unit is distinct from lower(btrim(v_requirement.metadata->'commercialFulfillment'->>'unit')) then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','allocation_unit_mismatch','lineKey',v_line_key,'allocationKey',v_alloc_key));
            end if;

            if v_alloc_quantity>(v_requirement.metadata->'commercialFulfillment'->>'quantity')::numeric then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','allocation_exceeds_requirement','lineKey',v_line_key,'allocationKey',v_alloc_key));
            end if;

            if v_alloc ? 'qualificationBasis' and jsonb_typeof(v_alloc->'qualificationBasis')<>'object' then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_qualification_basis','lineKey',v_line_key,'allocationKey',v_alloc_key));
            end if;
            if v_alloc ? 'planningBasis' and jsonb_typeof(v_alloc->'planningBasis')<>'object' then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_planning_basis','lineKey',v_line_key,'allocationKey',v_alloc_key));
            end if;
            if v_alloc ? 'metadata' and jsonb_typeof(v_alloc->'metadata')<>'object' then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_allocation_metadata','lineKey',v_line_key,'allocationKey',v_alloc_key));
            end if;

            v_alloc_total:=v_alloc_total+v_alloc_quantity;
          end loop;
        end if;
      end if;

      if v_output_quantity is not null and v_alloc_total>v_output_quantity then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','allocations_exceed_line_output',
          'lineKey',v_line_key,
          'allocatedQuantity',v_alloc_total,
          'coverageOutputQuantity',v_output_quantity
        ));
      end if;
    end loop;
  end if;

  v_hash:=encode(
    extensions.digest(convert_to(p_input::text,'UTF8'),'sha256'),
    'hex'
  );

  if v_org_id is not null and v_commitment_key is not null then
    select * into v_existing
    from atlas.external_acquisition_commitments
    where organization_id=v_org_id
      and commitment_key=v_commitment_key;

    if v_existing.id is not null
       and v_existing.commitment_sha256 is distinct from v_hash then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','existing_commitment_conflicts',
        'existingExternalAcquisitionCommitmentId',v_existing.id
      ));
    end if;
  end if;

  return jsonb_build_object(
    'contractVersion','external_acquisition_commitment_preview_v1',
    'state',case when jsonb_array_length(v_violations)=0 then 'ready' else 'blocked' end,
    'organizationId',v_org_id,
    'organizationUnitId',v_unit_id,
    'supplierRelationshipId',v_supplier_id,
    'commitmentKey',v_commitment_key,
    'commitmentKind',v_commitment_kind,
    'committedAt',v_committed_at,
    'economicState',v_economic_state,
    'knownCommittedAmount',v_known_amount,
    'currency',v_currency,
    'lineCount',v_line_count,
    'allocationCount',v_allocation_count,
    'commitmentSha256',v_hash,
    'existingExternalAcquisitionCommitmentId',v_existing.id,
    'existingCompatible',(v_existing.id is not null and v_existing.commitment_sha256=v_hash),
    'violations',v_violations,
    'warnings',v_warnings,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'doesNotCreateCommitment',true,
      'doesNotCreateSpend',true,
      'doesNotCreateInventory',true,
      'doesNotCreatePayment',true,
      'doesNotExecuteSupplierAction',true
    )
  );
end;
$function$;


create or replace function atlas.record_external_acquisition_commitment_service_v1(
  p_input jsonb
)
returns jsonb
language plpgsql
set search_path=pg_catalog,atlas
as $function$
declare
  v_preview jsonb;
  v_commitment_id uuid;
  v_line_id uuid;
  v_line jsonb;
  v_alloc jsonb;
  v_economics jsonb;
  v_source jsonb;
begin
  v_preview:=atlas.external_acquisition_commitment_preview_v1(p_input);

  if v_preview->>'state'<>'ready' then
    if exists(
      select 1 from jsonb_array_elements(v_preview->'violations') x
      where x->>'key'='existing_commitment_conflicts'
    ) then
      raise exception 'External Acquisition Commitment key conflicts with different structural truth: %',
        (v_preview->'violations')::text
        using errcode='23505';
    end if;

    raise exception 'External Acquisition Commitment input is blocked: %',
      (v_preview->'violations')::text
      using errcode='22023';
  end if;

  if nullif(v_preview->>'existingExternalAcquisitionCommitmentId','') is not null then
    return jsonb_build_object(
      'contractVersion','record_external_acquisition_commitment_service_v1',
      'externalAcquisitionCommitmentId',(v_preview->>'existingExternalAcquisitionCommitmentId')::uuid,
      'created',false,
      'commitmentSha256',v_preview->>'commitmentSha256'
    );
  end if;

  v_economics:=p_input->'economics';
  v_source:=p_input->'source';

  insert into atlas.external_acquisition_commitments(
    organization_id,organization_unit_id,supplier_relationship_id,
    commitment_key,commitment_kind,committed_at,
    expected_fulfillment_from_at,expected_fulfillment_by_at,
    economic_state,known_committed_amount,currency,cost_components,
    accepted_terms,source_kind,source_ref,evidence_record_id,
    connected_source_observation_id,authorization_basis,
    commitment_sha256,metadata
  ) values (
    (p_input->>'organizationId')::uuid,
    nullif(p_input->>'organizationUnitId','')::uuid,
    (p_input->>'supplierRelationshipId')::uuid,
    btrim(p_input->>'commitmentKey'),
    lower(btrim(coalesce(p_input->>'commitmentKind','supplier_order'))),
    (p_input->>'committedAt')::timestamptz,
    nullif(p_input->>'expectedFulfillmentFromAt','')::timestamptz,
    nullif(p_input->>'expectedFulfillmentByAt','')::timestamptz,
    lower(btrim(v_economics->>'state')),
    case when v_economics->'knownCommittedAmount' is null
              or v_economics->'knownCommittedAmount'='null'::jsonb
         then null else (v_economics->>'knownCommittedAmount')::numeric end,
    nullif(upper(btrim(coalesce(v_economics->>'currency',''))),''),
    coalesce(v_economics->'costComponents','[]'::jsonb),
    coalesce(p_input->'acceptedTerms','{}'::jsonb),
    lower(btrim(v_source->>'kind')),
    nullif(btrim(v_source->>'ref'),''),
    nullif(v_source->>'evidenceRecordId','')::uuid,
    nullif(v_source->>'connectedSourceObservationId','')::uuid,
    p_input->'authorizationBasis',
    v_preview->>'commitmentSha256',
    coalesce(p_input->'metadata','{}'::jsonb)
  )
  returning id into v_commitment_id;

  for v_line in select value from jsonb_array_elements(p_input->'lines')
  loop
    insert into atlas.external_acquisition_commitment_lines(
      external_acquisition_commitment_id,line_key,
      external_supply_offering_id,external_supply_offer_observation_id,
      source_line_key,description,ordered_quantity,ordered_unit,
      coverage_output_quantity,coverage_output_unit,
      known_line_amount,currency,accepted_terms,metadata
    ) values (
      v_commitment_id,
      btrim(v_line->>'lineKey'),
      (v_line->>'externalSupplyOfferingId')::uuid,
      nullif(v_line->>'externalSupplyOfferObservationId','')::uuid,
      nullif(btrim(v_line->>'sourceLineKey'),''),
      btrim(v_line->>'description'),
      (v_line->>'orderedQuantity')::numeric,
      lower(btrim(v_line->>'orderedUnit')),
      (v_line->>'coverageOutputQuantity')::numeric,
      lower(btrim(v_line->>'coverageOutputUnit')),
      case when v_line->'knownLineAmount' is null
                or v_line->'knownLineAmount'='null'::jsonb
           then null else (v_line->>'knownLineAmount')::numeric end,
      nullif(upper(btrim(coalesce(v_line->>'currency',''))),''),
      coalesce(v_line->'acceptedTerms','{}'::jsonb),
      coalesce(v_line->'metadata','{}'::jsonb)
    )
    returning id into v_line_id;

    if jsonb_typeof(coalesce(v_line->'allocations','[]'::jsonb))='array' then
      for v_alloc in select value from jsonb_array_elements(coalesce(v_line->'allocations','[]'::jsonb))
      loop
        insert into atlas.external_acquisition_requirement_allocations(
          external_acquisition_commitment_line_id,allocation_key,
          work_requirement_id,coverage_quantity,coverage_unit,
          qualification_basis,planning_basis,metadata
        ) values (
          v_line_id,
          btrim(v_alloc->>'allocationKey'),
          (v_alloc->>'workRequirementId')::uuid,
          (v_alloc->>'coverageQuantity')::numeric,
          lower(btrim(v_alloc->>'coverageUnit')),
          coalesce(v_alloc->'qualificationBasis','{}'::jsonb),
          coalesce(v_alloc->'planningBasis','{}'::jsonb),
          coalesce(v_alloc->'metadata','{}'::jsonb)
        );
      end loop;
    end if;
  end loop;

  return jsonb_build_object(
    'contractVersion','record_external_acquisition_commitment_service_v1',
    'externalAcquisitionCommitmentId',v_commitment_id,
    'created',true,
    'commitmentSha256',v_preview->>'commitmentSha256',
    'position',atlas.external_acquisition_commitment_position_v1(v_commitment_id),
    'truthBoundary',jsonb_build_object(
      'createsBuySideCommitment',true,
      'createsRequirementAllocations',true,
      'doesNotCreateSpend',true,
      'doesNotCreatePayment',true,
      'doesNotCreateInventory',true,
      'doesNotCreateCommercialOrder',true,
      'doesNotCreateWorkRequirement',true,
      'doesNotExecuteSupplierAction',true
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
  v_state text;
  v_terminal_basis text;
  v_lines jsonb;
  v_events jsonb;
begin
  select * into v_commitment
  from atlas.external_acquisition_commitments
  where id=p_external_acquisition_commitment_id;

  if v_commitment.id is null then
    raise exception 'External Acquisition Commitment not found.'
      using errcode='P0002';
  end if;

  select * into v_latest_event
  from atlas.external_acquisition_commitment_events e
  where e.external_acquisition_commitment_id=v_commitment.id
  order by e.occurred_at desc,e.created_at desc,e.id desc
  limit 1;

  v_state:=coalesce(v_latest_event.event_kind,'committed');

  if exists(
    select 1 from atlas.external_acquisition_commitment_events e
    where e.external_acquisition_commitment_id=v_commitment.id
      and e.event_kind='received'
  ) then
    v_terminal_basis:='received';
  elsif exists(
    select 1 from atlas.external_acquisition_commitment_events e
    where e.external_acquisition_commitment_id=v_commitment.id
      and e.event_kind='cancelled'
  ) then
    v_terminal_basis:='cancelled';
  end if;

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
        'allocatedCoverageQuantity',coalesce(x.allocated_quantity,0),
        'unallocatedCoverageOutputQuantity',l.coverage_output_quantity-coalesce(x.allocated_quantity,0),
        'allocations',coalesce(x.allocations,'[]'::jsonb)
      )
      order by l.line_key,l.id
    ),
    '[]'::jsonb
  )
  into v_lines
  from atlas.external_acquisition_commitment_lines l
  left join lateral (
    select
      sum(a.coverage_quantity) as allocated_quantity,
      jsonb_agg(
        jsonb_build_object(
          'externalAcquisitionRequirementAllocationId',a.id,
          'allocationKey',a.allocation_key,
          'workRequirementId',a.work_requirement_id,
          'coverageQuantity',a.coverage_quantity,
          'coverageUnit',a.coverage_unit,
          'qualificationBasis',a.qualification_basis,
          'planningBasis',a.planning_basis,
          'metadata',a.metadata
        )
        order by a.allocation_key,a.id
      ) as allocations
    from atlas.external_acquisition_requirement_allocations a
    where a.external_acquisition_commitment_line_id=l.id
  ) x on true
  where l.external_acquisition_commitment_id=v_commitment.id;

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
    'events',v_events,
    'metadata',v_commitment.metadata,
    'truthBoundary',jsonb_build_object(
      'buySideCommitment',true,
      'notSpend',true,
      'notPayment',true,
      'notInventory',true,
      'notCommercialOrder',true
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

  if v_key='' or v_kind not in ('cancelled','received','closed') or p_occurred_at is null then
    raise exception 'Event key, supported event kind, and occurred time are required.'
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
      'position',atlas.external_acquisition_commitment_position_v1(p_external_acquisition_commitment_id)
    );
  end if;

  v_position:=atlas.external_acquisition_commitment_position_v1(p_external_acquisition_commitment_id);
  v_current_state:=v_position->>'state';

  if not (
    (v_current_state='committed' and v_kind in ('cancelled','received'))
    or
    (v_current_state in ('cancelled','received') and v_kind='closed')
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
    'position',atlas.external_acquisition_commitment_position_v1(p_external_acquisition_commitment_id)
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
  v_terminal_basis text;
  v_current_state text;
  v_normalized_state text;
  v_handoff boolean:=false;
  v_facts jsonb;
begin
  v_position:=atlas.external_acquisition_commitment_position_v1(p_external_acquisition_commitment_id);
  v_terminal_basis:=v_position->>'terminalBasis';
  v_current_state:=v_position->>'state';

  if v_terminal_basis='cancelled' then
    v_normalized_state:='released';
  elsif v_terminal_basis='received' then
    v_normalized_state:='unresolved';
    v_handoff:=true;
  else
    v_normalized_state:='secured';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'workRequirementId',a.work_requirement_id,
        'coverageFact',jsonb_build_object(
          'coverageKey','external_acquisition:'||p_external_acquisition_commitment_id::text||':'||a.id::text,
          'sourceRef',jsonb_build_object(
            'sourceDomain','external_acquisition_requirement_allocation',
            'sourceRef',a.id::text
          ),
          'state',v_normalized_state,
          'quantity',a.coverage_quantity,
          'unit',a.coverage_unit,
          'evidence',jsonb_build_array(jsonb_build_object(
            'source','external_acquisition_commitment',
            'externalAcquisitionCommitmentId',p_external_acquisition_commitment_id,
            'externalAcquisitionCommitmentLineId',l.id,
            'allocationId',a.id
          )),
          'metadata',jsonb_build_object(
            'commitmentState',v_current_state,
            'terminalBasis',v_terminal_basis,
            'handoffRequired',v_handoff,
            'allocationKey',a.allocation_key
          )
        )
      )
      order by a.work_requirement_id,a.allocation_key,a.id
    ),
    '[]'::jsonb
  )
  into v_facts
  from atlas.external_acquisition_requirement_allocations a
  join atlas.external_acquisition_commitment_lines l
    on l.id=a.external_acquisition_commitment_line_id
  where l.external_acquisition_commitment_id=p_external_acquisition_commitment_id;

  return jsonb_build_object(
    'contractVersion','external_acquisition_commitment_coverage_facts_v1',
    'externalAcquisitionCommitmentId',p_external_acquisition_commitment_id,
    'commitmentState',v_current_state,
    'terminalBasis',v_terminal_basis,
    'normalizedCoverageState',v_normalized_state,
    'handoffRequired',v_handoff,
    'facts',v_facts,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'sourceOwnedCoverageFacts',true,
      'receivedRequiresReceivingOrInventoryHandoff',true,
      'doesNotCreateCoverageRow',true,
      'doesNotCreateInventory',true,
      'doesNotCreateSpend',true
    )
  );
end;
$function$;


alter table atlas.external_acquisition_commitments enable row level security;
alter table atlas.external_acquisition_commitment_lines enable row level security;
alter table atlas.external_acquisition_requirement_allocations enable row level security;
alter table atlas.external_acquisition_commitment_events enable row level security;

revoke all on atlas.external_acquisition_commitments
  from public,anon,authenticated,service_role;
revoke all on atlas.external_acquisition_commitment_lines
  from public,anon,authenticated,service_role;
revoke all on atlas.external_acquisition_requirement_allocations
  from public,anon,authenticated,service_role;
revoke all on atlas.external_acquisition_commitment_events
  from public,anon,authenticated,service_role;

grant select,insert on atlas.external_acquisition_commitments to service_role;
grant select,insert on atlas.external_acquisition_commitment_lines to service_role;
grant select,insert on atlas.external_acquisition_requirement_allocations to service_role;
grant select,insert on atlas.external_acquisition_commitment_events to service_role;

revoke all on function atlas.external_acquisition_commitment_preview_v1(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.external_acquisition_commitment_preview_v1(jsonb)
  to service_role;

revoke all on function atlas.record_external_acquisition_commitment_service_v1(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.record_external_acquisition_commitment_service_v1(jsonb)
  to service_role;

revoke all on function atlas.external_acquisition_commitment_position_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.external_acquisition_commitment_position_v1(uuid)
  to service_role;

revoke all on function atlas.record_external_acquisition_commitment_event_service_v1(uuid,text,text,timestamptz,jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.record_external_acquisition_commitment_event_service_v1(uuid,text,text,timestamptz,jsonb,jsonb)
  to service_role;

revoke all on function atlas.external_acquisition_commitment_coverage_facts_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.external_acquisition_commitment_coverage_facts_v1(uuid)
  to service_role;


insert into atlas.architecture_truth_authorities(
  authority_key,domain_key,truth_question,authority_owner,authority_status,
  canonical_relations,canonical_functions,supporting_relations,
  consumer_surfaces,known_competitors,source_custody,rationale,updated_at
) values (
  'external_acquisition_commitment',
  'commercial_supply',
  'What external acquisition has this organization actually committed to, on what accepted terms, for what financial obligation, and which Company Work requirements does it currently secure?',
  'external_acquisition_commitments + lines + requirement allocations + events',
  'canonical',
  array[
    'atlas.external_acquisition_commitments',
    'atlas.external_acquisition_commitment_lines',
    'atlas.external_acquisition_requirement_allocations',
    'atlas.external_acquisition_commitment_events'
  ],
  array[
    'atlas.external_acquisition_commitment_preview_v1',
    'atlas.record_external_acquisition_commitment_service_v1',
    'atlas.external_acquisition_commitment_position_v1',
    'atlas.record_external_acquisition_commitment_event_service_v1',
    'atlas.external_acquisition_commitment_coverage_facts_v1'
  ],
  array[
    'atlas.external_relationships',
    'atlas.external_relationship_roles',
    'atlas.external_supply_offerings',
    'atlas.external_supply_offer_observations',
    'atlas.work_requirements',
    'atlas.evidence_records',
    'atlas.connected_source_observations'
  ],
  array[]::text[],
  array[
    'atlas.commercial_orders',
    'atlas.organization_spend_occurrences',
    'atlas.flower_ready_inventory_lots',
    'atlas.production_capacity_reservations'
  ],
  'External Acquisition Commitment owns accepted buy-side supplier commitment and source-owned requirement allocation. Supplier observations remain proposed source terms; Organization Spend remains occurred outlay; receiving/inventory remains post-receipt truth.',
  'Fills the missing buy-side commitment seam needed to turn an authorized fulfillment plan into secured source coverage without pretending planning is purchasing or purchasing is Spend.',
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
  'atlas.external_acquisition_commitment_preview_v1(jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_external_acquisition_commitment_v1","purpose":"Read-only validation of an authorized buy-side supplier commitment packet before persistence.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.record_external_acquisition_commitment_service_v1(jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_external_acquisition_commitment_v1","purpose":"Persist immutable external supplier acquisition commitment, lines, and source-owned Company Work allocations; creates no Spend or inventory.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.external_acquisition_commitment_position_v1(uuid)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_external_acquisition_commitment_v1","purpose":"Read current lifecycle/economic position for one External Acquisition Commitment.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.record_external_acquisition_commitment_event_service_v1(uuid,text,text,timestamptz,jsonb,jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_external_acquisition_commitment_v1","purpose":"Append governed cancellation/receipt/closure lifecycle evidence to one External Acquisition Commitment.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.external_acquisition_commitment_coverage_facts_v1(uuid)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_external_acquisition_commitment_v1","purpose":"Emit normalized source-owned Company Work coverage facts from committed external acquisition allocations.","classificationRuleVersion":3}'::jsonb,
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
