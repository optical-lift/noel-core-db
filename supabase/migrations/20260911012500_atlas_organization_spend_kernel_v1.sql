-- Atlas Organization Spend Kernel v1
-- Current-main canonical migration candidate.
-- This file is committed for governed clone validation. It is NOT applied to
-- production by this commit.

create table atlas.organization_spend_occurrences (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid references atlas.organization_units(id) on delete restrict,
  occurred_on date not null,
  occurred_at timestamptz,
  gross_amount numeric not null check (gross_amount > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  funding_kind text not null check (
    funding_kind in ('organization','organization_member','external_party','unresolved')
  ),
  payer_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  payee_external_relationship_id uuid references atlas.external_relationships(id) on delete restrict,
  payee_label text,
  payment_method text,
  source_kind text not null check (btrim(source_kind) <> ''),
  source_key text not null check (btrim(source_key) <> ''),
  recorded_by_membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  truth_state text not null default 'confirmed' check (
    truth_state in ('observed','confirmed','disputed','voided')
  ),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (occurred_at is null or occurred_at::date = occurred_on),
  check (payee_label is null or btrim(payee_label) <> ''),
  check (payment_method is null or btrim(payment_method) <> ''),
  check (
    (funding_kind='organization_member' and payer_membership_id is not null)
    or funding_kind<>'organization_member'
  ),
  unique (organization_id, source_kind, source_key),
  unique (id, organization_id)
);

comment on table atlas.organization_spend_occurrences is
  'Canonical organization-owned gross outlay occurrence. Reporting category, reimbursement treatment, tax treatment, and accounting classification are downstream interpretations.';

create table atlas.organization_spend_allocations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  spend_occurrence_id uuid not null,
  organization_unit_id uuid references atlas.organization_units(id) on delete restrict,
  allocated_amount numeric not null check (allocated_amount > 0),
  operational_purpose text,
  subject_domain text,
  subject_kind text,
  subject_id text,
  allocation_state text not null default 'active' check (
    allocation_state in ('active','superseded','voided')
  ),
  superseded_at timestamptz,
  superseded_by_event_id uuid,
  recorded_by_membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  foreign key (spend_occurrence_id, organization_id)
    references atlas.organization_spend_occurrences(id, organization_id)
    on delete cascade,
  check (operational_purpose is null or btrim(operational_purpose) <> ''),
  check (
    (subject_domain is null and subject_kind is null and subject_id is null)
    or (
      nullif(btrim(coalesce(subject_domain,'')),'') is not null
      and nullif(btrim(coalesce(subject_kind,'')),'') is not null
      and nullif(btrim(coalesce(subject_id,'')),'') is not null
    )
  ),
  check (
    (allocation_state='active' and superseded_at is null)
    or allocation_state<>'active'
  ),
  unique (id, spend_occurrence_id, organization_id)
);

comment on table atlas.organization_spend_allocations is
  'Operational-purpose allocation of a canonical Spend occurrence. CI categories and GL accounts do not belong here.';

create table atlas.organization_spend_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  spend_occurrence_id uuid not null,
  event_kind text not null check (
    event_kind in ('recorded','corrected','allocations_replaced','voided')
  ),
  actor_membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  source_kind text not null check (btrim(source_kind) <> ''),
  source_key text not null check (btrim(source_key) <> ''),
  occurred_at timestamptz not null default now(),
  reason text,
  before_state jsonb,
  after_state jsonb,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  foreign key (spend_occurrence_id, organization_id)
    references atlas.organization_spend_occurrences(id, organization_id)
    on delete cascade,
  check (reason is null or btrim(reason) <> ''),
  check (before_state is null or jsonb_typeof(before_state)='object'),
  check (after_state is null or jsonb_typeof(after_state)='object'),
  unique (organization_id, source_kind, source_key)
);

comment on table atlas.organization_spend_events is
  'Append-only audit events establishing or changing the effective typed Spend position.';

alter table atlas.organization_spend_allocations
  add constraint organization_spend_allocations_superseded_event_fk
  foreign key (superseded_by_event_id)
  references atlas.organization_spend_events(id)
  on delete restrict;

create table atlas.organization_spend_evidence_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  spend_occurrence_id uuid not null,
  spend_allocation_id uuid,
  evidence_record_id uuid not null references atlas.evidence_records(id) on delete restrict,
  relation_kind text not null default 'supporting' check (
    relation_kind in ('supporting','receipt','factura','invoice','transaction_observation','context')
  ),
  linked_by_membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  foreign key (spend_occurrence_id, organization_id)
    references atlas.organization_spend_occurrences(id, organization_id)
    on delete cascade,
  foreign key (spend_allocation_id, spend_occurrence_id, organization_id)
    references atlas.organization_spend_allocations(id, spend_occurrence_id, organization_id)
    on delete cascade
);

create unique index organization_spend_evidence_links_uq
  on atlas.organization_spend_evidence_links(
    spend_occurrence_id,
    coalesce(spend_allocation_id,'00000000-0000-0000-0000-000000000000'::uuid),
    evidence_record_id,
    relation_kind
  );

create index organization_spend_occurrences_org_date_idx
  on atlas.organization_spend_occurrences(organization_id, occurred_on desc, id);

create index organization_spend_occurrences_payer_idx
  on atlas.organization_spend_occurrences(organization_id, payer_membership_id, occurred_on desc)
  where payer_membership_id is not null;

create index organization_spend_allocations_occurrence_state_idx
  on atlas.organization_spend_allocations(spend_occurrence_id, allocation_state, created_at, id);

create index organization_spend_events_occurrence_time_idx
  on atlas.organization_spend_events(spend_occurrence_id, occurred_at, id);

create index organization_spend_evidence_links_occurrence_idx
  on atlas.organization_spend_evidence_links(spend_occurrence_id, relation_kind, created_at);

create or replace function atlas.organization_spend_assert_membership_v1(
  p_organization_id uuid,
  p_membership_id uuid,
  p_label text
)
returns void
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if p_membership_id is null or not exists (
    select 1
    from atlas.organization_memberships om
    where om.id=p_membership_id
      and om.organization_id=p_organization_id
      and om.active
  ) then
    raise exception '% membership must be active in the Spend organization.', coalesce(nullif(btrim(p_label),''),'Referenced') using errcode='23503';
  end if;
end;
$function$;

create or replace function atlas.organization_spend_assert_unit_v1(
  p_organization_id uuid,
  p_organization_unit_id uuid
)
returns void
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if p_organization_unit_id is not null and not exists (
    select 1
    from atlas.organization_units ou
    where ou.id=p_organization_unit_id
      and ou.organization_id=p_organization_id
  ) then
    raise exception 'Organization Unit does not belong to the Spend organization.' using errcode='23503';
  end if;
end;
$function$;

create or replace function atlas.organization_spend_occurrence_snapshot_v1(
  p_spend_occurrence_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  select jsonb_build_object(
    'id',s.id,
    'organizationId',s.organization_id,
    'organizationUnitId',s.organization_unit_id,
    'occurredOn',s.occurred_on,
    'occurredAt',s.occurred_at,
    'grossAmount',s.gross_amount,
    'currency',s.currency,
    'fundingKind',s.funding_kind,
    'payerMembershipId',s.payer_membership_id,
    'payeeExternalRelationshipId',s.payee_external_relationship_id,
    'payeeLabel',s.payee_label,
    'paymentMethod',s.payment_method,
    'truthState',s.truth_state
  )
  from atlas.organization_spend_occurrences s
  where s.id=p_spend_occurrence_id;
$function$;

create or replace function atlas.guard_organization_spend_occurrence_v1()
returns trigger
language plpgsql
set search_path=pg_catalog,atlas
as $function$
begin
  perform atlas.organization_spend_assert_unit_v1(new.organization_id,new.organization_unit_id);
  perform atlas.organization_spend_assert_membership_v1(new.organization_id,new.recorded_by_membership_id,'Recorder');

  if new.payer_membership_id is not null then
    perform atlas.organization_spend_assert_membership_v1(new.organization_id,new.payer_membership_id,'Payer');
  end if;

  if new.payee_external_relationship_id is not null and not exists (
    select 1
    from atlas.external_relationships er
    where er.id=new.payee_external_relationship_id
      and er.organization_id=new.organization_id
  ) then
    raise exception 'Payee relationship does not belong to the Spend organization.' using errcode='23503';
  end if;

  new.currency:=upper(btrim(new.currency));
  new.source_kind:=lower(btrim(new.source_kind));
  new.source_key:=btrim(new.source_key);
  new.payee_label:=nullif(btrim(coalesce(new.payee_label,'')),'');
  new.payment_method:=nullif(btrim(coalesce(new.payment_method,'')),'');
  new.updated_at:=now();
  return new;
end;
$function$;

create trigger guard_organization_spend_occurrence_v1
before insert or update on atlas.organization_spend_occurrences
for each row execute function atlas.guard_organization_spend_occurrence_v1();

create or replace function atlas.guard_organization_spend_allocation_v1()
returns trigger
language plpgsql
set search_path=pg_catalog,atlas
as $function$
declare
  v_gross numeric;
  v_truth_state text;
  v_other_active numeric;
begin
  perform atlas.organization_spend_assert_unit_v1(new.organization_id,new.organization_unit_id);
  perform atlas.organization_spend_assert_membership_v1(new.organization_id,new.recorded_by_membership_id,'Allocation recorder');

  select s.gross_amount,s.truth_state
  into v_gross,v_truth_state
  from atlas.organization_spend_occurrences s
  where s.id=new.spend_occurrence_id
    and s.organization_id=new.organization_id;

  if v_gross is null then
    raise exception 'Spend allocation occurrence is invalid.' using errcode='23503';
  end if;

  if new.allocation_state='active' and v_truth_state='voided' then
    raise exception 'A voided Spend occurrence cannot receive an active allocation.' using errcode='23514';
  end if;

  if new.allocation_state='active' then
    select coalesce(sum(a.allocated_amount),0)
    into v_other_active
    from atlas.organization_spend_allocations a
    where a.spend_occurrence_id=new.spend_occurrence_id
      and a.organization_id=new.organization_id
      and a.allocation_state='active'
      and a.id is distinct from new.id;

    if v_other_active + new.allocated_amount > v_gross then
      raise exception 'Active Spend allocations cannot exceed gross amount.' using errcode='23514';
    end if;
  end if;

  new.operational_purpose:=nullif(btrim(coalesce(new.operational_purpose,'')),'');
  new.subject_domain:=nullif(btrim(coalesce(new.subject_domain,'')),'');
  new.subject_kind:=nullif(btrim(coalesce(new.subject_kind,'')),'');
  new.subject_id:=nullif(btrim(coalesce(new.subject_id,'')),'');
  return new;
end;
$function$;

create trigger guard_organization_spend_allocation_v1
before insert or update on atlas.organization_spend_allocations
for each row execute function atlas.guard_organization_spend_allocation_v1();

create or replace function atlas.guard_organization_spend_event_v1()
returns trigger
language plpgsql
set search_path=pg_catalog,atlas
as $function$
begin
  perform atlas.organization_spend_assert_membership_v1(new.organization_id,new.actor_membership_id,'Event actor');
  if not exists (
    select 1
    from atlas.organization_spend_occurrences s
    where s.id=new.spend_occurrence_id and s.organization_id=new.organization_id
  ) then
    raise exception 'Spend event occurrence is invalid.' using errcode='23503';
  end if;
  new.source_kind:=lower(btrim(new.source_kind));
  new.source_key:=btrim(new.source_key);
  new.reason:=nullif(btrim(coalesce(new.reason,'')),'');
  return new;
end;
$function$;

create trigger guard_organization_spend_event_v1
before insert on atlas.organization_spend_events
for each row execute function atlas.guard_organization_spend_event_v1();

create or replace function atlas.guard_organization_spend_evidence_link_v1()
returns trigger
language plpgsql
set search_path=pg_catalog,atlas
as $function$
begin
  perform atlas.organization_spend_assert_membership_v1(new.organization_id,new.linked_by_membership_id,'Evidence linker');

  if not exists (
    select 1
    from atlas.evidence_records e
    where e.id=new.evidence_record_id
      and e.scope_kind='organization'
      and e.scope_id=new.organization_id
  ) then
    raise exception 'Spend evidence must be organization-scoped to the same organization.' using errcode='23503';
  end if;

  return new;
end;
$function$;

create trigger guard_organization_spend_evidence_link_v1
before insert or update on atlas.organization_spend_evidence_links
for each row execute function atlas.guard_organization_spend_evidence_link_v1();

create or replace view atlas.organization_spend_position_v1 as
select
  s.id as spend_occurrence_id,
  s.organization_id,
  s.organization_unit_id,
  s.occurred_on,
  s.occurred_at,
  s.gross_amount,
  s.currency,
  s.funding_kind,
  s.payer_membership_id,
  s.payee_external_relationship_id,
  s.payee_label,
  s.payment_method,
  s.source_kind,
  s.source_key,
  s.recorded_by_membership_id,
  s.truth_state,
  coalesce(sum(a.allocated_amount) filter (where a.allocation_state='active'),0) as allocated_amount,
  case
    when s.truth_state='voided' then 0
    else s.gross_amount-coalesce(sum(a.allocated_amount) filter (where a.allocation_state='active'),0)
  end as unallocated_amount,
  count(a.id) filter (where a.allocation_state='active') as active_allocation_count,
  s.created_at,
  s.updated_at
from atlas.organization_spend_occurrences s
left join atlas.organization_spend_allocations a
  on a.spend_occurrence_id=s.id
 and a.organization_id=s.organization_id
group by s.id;

create or replace function atlas.organization_spend_parse_allocations_internal_v1(
  p_organization_id uuid,
  p_spend_occurrence_id uuid,
  p_actor_membership_id uuid,
  p_allocations jsonb,
  p_provenance jsonb default '{}'::jsonb
)
returns integer
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_item jsonb;
  v_count integer:=0;
  v_unit_id uuid;
  v_amount numeric;
  v_purpose text;
  v_domain text;
  v_kind text;
  v_subject_id text;
begin
  if p_allocations is null then
    return 0;
  end if;
  if jsonb_typeof(p_allocations)<>'array' then
    raise exception 'Spend allocations must be a JSON array.' using errcode='22023';
  end if;

  for v_item in select value from jsonb_array_elements(p_allocations)
  loop
    if jsonb_typeof(v_item)<>'object' then
      raise exception 'Each Spend allocation must be an object.' using errcode='22023';
    end if;

    begin
      v_amount:=(v_item->>'amount')::numeric;
    exception when others then
      raise exception 'Each Spend allocation requires a numeric amount.' using errcode='22023';
    end;
    if v_amount is null or v_amount<=0 then
      raise exception 'Each Spend allocation amount must be greater than zero.' using errcode='22023';
    end if;

    begin
      v_unit_id:=nullif(v_item->>'organizationUnitId','')::uuid;
    exception when others then
      raise exception 'Spend allocation organizationUnitId must be a UUID.' using errcode='22023';
    end;

    v_purpose:=nullif(btrim(coalesce(v_item->>'operationalPurpose','')),'');
    v_domain:=nullif(btrim(coalesce(v_item->>'subjectDomain','')),'');
    v_kind:=nullif(btrim(coalesce(v_item->>'subjectKind','')),'');
    v_subject_id:=nullif(btrim(coalesce(v_item->>'subjectId','')),'');

    insert into atlas.organization_spend_allocations(
      organization_id,spend_occurrence_id,organization_unit_id,allocated_amount,
      operational_purpose,subject_domain,subject_kind,subject_id,
      recorded_by_membership_id,provenance,metadata
    ) values (
      p_organization_id,p_spend_occurrence_id,v_unit_id,v_amount,
      v_purpose,v_domain,v_kind,v_subject_id,
      p_actor_membership_id,coalesce(p_provenance,'{}'::jsonb),'{}'::jsonb
    );
    v_count:=v_count+1;
  end loop;
  return v_count;
end;
$function$;

create or replace function atlas.record_organization_spend_internal_v1(
  p_organization_id uuid,
  p_actor_membership_id uuid,
  p_organization_unit_id uuid,
  p_occurred_on date,
  p_occurred_at timestamptz,
  p_gross_amount numeric,
  p_currency text,
  p_funding_kind text,
  p_payer_membership_id uuid,
  p_payee_external_relationship_id uuid,
  p_payee_label text,
  p_payment_method text,
  p_source_kind text,
  p_source_key text,
  p_allocations jsonb default null,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_existing atlas.organization_spend_occurrences%rowtype;
  v_spend atlas.organization_spend_occurrences%rowtype;
  v_event_id uuid;
  v_allocation_count integer:=0;
  v_existing_allocations integer:=0;
  v_source_kind text:=lower(btrim(coalesce(p_source_kind,'')));
  v_source_key text:=btrim(coalesce(p_source_key,''));
  v_currency text:=upper(btrim(coalesce(p_currency,'')));
  v_payee_label text:=nullif(btrim(coalesce(p_payee_label,'')),'');
  v_payment_method text:=nullif(btrim(coalesce(p_payment_method,'')),'');
begin
  perform atlas.organization_spend_assert_membership_v1(p_organization_id,p_actor_membership_id,'Actor');
  perform atlas.organization_spend_assert_unit_v1(p_organization_id,p_organization_unit_id);

  if p_occurred_on is null or p_gross_amount is null or p_gross_amount<=0
     or v_currency !~ '^[A-Z]{3}$'
     or v_source_kind='' or v_source_key='' then
    raise exception 'Spend date, positive gross amount, three-letter currency, source kind, and source key are required.' using errcode='22023';
  end if;
  if p_funding_kind not in ('organization','organization_member','external_party','unresolved') then
    raise exception 'Unsupported Spend funding kind.' using errcode='22023';
  end if;
  if p_funding_kind='organization_member' and p_payer_membership_id is null then
    raise exception 'Member-funded Spend requires a payer membership.' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('atlas.organization_spend:'||p_organization_id::text||':'||v_source_kind||':'||v_source_key,0));

  select * into v_existing
  from atlas.organization_spend_occurrences s
  where s.organization_id=p_organization_id
    and s.source_kind=v_source_kind
    and s.source_key=v_source_key
  for update;

  if v_existing.id is not null then
    if v_existing.organization_unit_id is distinct from p_organization_unit_id
       or v_existing.occurred_on is distinct from p_occurred_on
       or v_existing.occurred_at is distinct from p_occurred_at
       or v_existing.gross_amount is distinct from p_gross_amount
       or v_existing.currency is distinct from v_currency
       or v_existing.funding_kind is distinct from p_funding_kind
       or v_existing.payer_membership_id is distinct from p_payer_membership_id
       or v_existing.payee_external_relationship_id is distinct from p_payee_external_relationship_id
       or v_existing.payee_label is distinct from v_payee_label
       or v_existing.payment_method is distinct from v_payment_method then
      raise exception 'Spend source identity already exists with different occurrence facts.' using errcode='23514';
    end if;
    select count(*) into v_existing_allocations
    from atlas.organization_spend_allocations a
    where a.spend_occurrence_id=v_existing.id and a.allocation_state='active';
    return jsonb_build_object(
      'contractVersion','record_organization_spend_internal_v1',
      'state','unchanged',
      'spendOccurrenceId',v_existing.id,
      'activeAllocationCount',v_existing_allocations
    );
  end if;

  insert into atlas.organization_spend_occurrences(
    organization_id,organization_unit_id,occurred_on,occurred_at,gross_amount,currency,
    funding_kind,payer_membership_id,payee_external_relationship_id,payee_label,payment_method,
    source_kind,source_key,recorded_by_membership_id,truth_state,provenance,metadata
  ) values (
    p_organization_id,p_organization_unit_id,p_occurred_on,p_occurred_at,p_gross_amount,v_currency,
    p_funding_kind,p_payer_membership_id,p_payee_external_relationship_id,v_payee_label,v_payment_method,
    v_source_kind,v_source_key,p_actor_membership_id,'confirmed',coalesce(p_provenance,'{}'::jsonb),coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_spend;

  v_allocation_count:=atlas.organization_spend_parse_allocations_internal_v1(
    p_organization_id,v_spend.id,p_actor_membership_id,p_allocations,p_provenance
  );

  insert into atlas.organization_spend_events(
    organization_id,spend_occurrence_id,event_kind,actor_membership_id,
    source_kind,source_key,reason,before_state,after_state,metadata
  ) values (
    p_organization_id,v_spend.id,'recorded',p_actor_membership_id,
    'spend_record',v_source_kind||':'||v_source_key,null,null,
    atlas.organization_spend_occurrence_snapshot_v1(v_spend.id),
    jsonb_build_object('allocationCount',v_allocation_count)
  ) returning id into v_event_id;

  return jsonb_build_object(
    'contractVersion','record_organization_spend_internal_v1',
    'state','admitted',
    'spendOccurrenceId',v_spend.id,
    'eventId',v_event_id,
    'activeAllocationCount',v_allocation_count,
    'grossAmount',v_spend.gross_amount,
    'currency',v_spend.currency,
    'unallocatedAmount',(
      select p.unallocated_amount
      from atlas.organization_spend_position_v1 p
      where p.spend_occurrence_id=v_spend.id
    )
  );
end;
$function$;

create or replace function atlas.record_organization_spend_self_api_v1(
  p_organization_id uuid,
  p_client_event_key text,
  p_organization_unit_id uuid,
  p_occurred_on date,
  p_occurred_at timestamptz,
  p_gross_amount numeric,
  p_currency text,
  p_funding_kind text,
  p_payer_membership_id uuid,
  p_payee_external_relationship_id uuid,
  p_payee_label text,
  p_payment_method text,
  p_allocations jsonb default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_membership_id uuid;
  v_payer_id uuid:=p_payer_membership_id;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;
  v_membership_id:=atlas.current_organization_membership_v1(p_organization_id);
  if v_membership_id is null then
    raise exception 'Active organization membership required.' using errcode='42501';
  end if;
  if nullif(btrim(coalesce(p_client_event_key,'')),'') is null then
    raise exception 'Client event key is required.' using errcode='22023';
  end if;

  if p_funding_kind='organization_member' and v_payer_id is null then
    v_payer_id:=v_membership_id;
  end if;
  if v_payer_id is not null and v_payer_id<>v_membership_id and not atlas.is_organization_owner(p_organization_id) then
    raise exception 'Only the organization owner may record another member as initial payer.' using errcode='42501';
  end if;

  return atlas.record_organization_spend_internal_v1(
    p_organization_id,v_membership_id,p_organization_unit_id,p_occurred_on,p_occurred_at,
    p_gross_amount,p_currency,p_funding_kind,v_payer_id,p_payee_external_relationship_id,
    p_payee_label,p_payment_method,'atlas_self_capture',btrim(p_client_event_key),p_allocations,
    jsonb_build_object('authority','record_organization_spend_self_api_v1','actorUserId',auth.uid()),
    coalesce(p_metadata,'{}'::jsonb)
  );
end;
$function$;

create or replace function atlas.replace_organization_spend_allocations_self_api_v1(
  p_spend_occurrence_id uuid,
  p_client_event_key text,
  p_allocations jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_spend atlas.organization_spend_occurrences%rowtype;
  v_actor uuid;
  v_event atlas.organization_spend_events%rowtype;
  v_before jsonb;
  v_count integer;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if nullif(btrim(coalesce(p_client_event_key,'')),'') is null then raise exception 'Client event key is required.' using errcode='22023'; end if;
  if p_allocations is null or jsonb_typeof(p_allocations)<>'array' then raise exception 'Replacement allocations must be a JSON array.' using errcode='22023'; end if;

  select * into v_spend from atlas.organization_spend_occurrences where id=p_spend_occurrence_id for update;
  if v_spend.id is null then raise exception 'Spend occurrence not found.' using errcode='P0002'; end if;
  v_actor:=atlas.current_organization_membership_v1(v_spend.organization_id);
  if v_actor is null then raise exception 'Active organization membership required.' using errcode='42501'; end if;
  if v_spend.recorded_by_membership_id<>v_actor and not atlas.is_organization_owner(v_spend.organization_id) then
    raise exception 'Owner authority is required to reallocate another member''s Spend.' using errcode='42501';
  end if;
  if v_spend.truth_state='voided' then raise exception 'A voided Spend cannot be reallocated.' using errcode='55000'; end if;

  select * into v_event
  from atlas.organization_spend_events e
  where e.organization_id=v_spend.organization_id
    and e.source_kind='spend_allocation_replace'
    and e.source_key=btrim(p_client_event_key);
  if v_event.id is not null then
    if v_event.spend_occurrence_id<>v_spend.id then raise exception 'Allocation event key is already bound to another Spend.' using errcode='23514'; end if;
    return jsonb_build_object('contractVersion','replace_organization_spend_allocations_self_api_v1','state','unchanged','spendOccurrenceId',v_spend.id,'eventId',v_event.id);
  end if;

  select jsonb_build_object(
    'allocations',coalesce(jsonb_agg(jsonb_build_object(
      'id',a.id,'amount',a.allocated_amount,'organizationUnitId',a.organization_unit_id,
      'operationalPurpose',a.operational_purpose,'subjectDomain',a.subject_domain,
      'subjectKind',a.subject_kind,'subjectId',a.subject_id
    ) order by a.created_at,a.id),'[]'::jsonb)
  ) into v_before
  from atlas.organization_spend_allocations a
  where a.spend_occurrence_id=v_spend.id and a.allocation_state='active';

  insert into atlas.organization_spend_events(
    organization_id,spend_occurrence_id,event_kind,actor_membership_id,
    source_kind,source_key,reason,before_state,after_state,metadata
  ) values (
    v_spend.organization_id,v_spend.id,'allocations_replaced',v_actor,
    'spend_allocation_replace',btrim(p_client_event_key),p_reason,v_before,null,'{}'::jsonb
  ) returning * into v_event;

  update atlas.organization_spend_allocations
  set allocation_state='superseded',superseded_at=now(),superseded_by_event_id=v_event.id
  where spend_occurrence_id=v_spend.id and allocation_state='active';

  v_count:=atlas.organization_spend_parse_allocations_internal_v1(
    v_spend.organization_id,v_spend.id,v_actor,p_allocations,
    jsonb_build_object('authority','replace_organization_spend_allocations_self_api_v1','eventId',v_event.id)
  );

  update atlas.organization_spend_events e
  set after_state=(
    select jsonb_build_object('allocations',coalesce(jsonb_agg(jsonb_build_object(
      'id',a.id,'amount',a.allocated_amount,'organizationUnitId',a.organization_unit_id,
      'operationalPurpose',a.operational_purpose,'subjectDomain',a.subject_domain,
      'subjectKind',a.subject_kind,'subjectId',a.subject_id
    ) order by a.created_at,a.id),'[]'::jsonb))
    from atlas.organization_spend_allocations a
    where a.spend_occurrence_id=v_spend.id and a.allocation_state='active'
  )
  where e.id=v_event.id;

  return jsonb_build_object(
    'contractVersion','replace_organization_spend_allocations_self_api_v1',
    'state','replaced','spendOccurrenceId',v_spend.id,'eventId',v_event.id,
    'activeAllocationCount',v_count,
    'unallocatedAmount',(select p.unallocated_amount from atlas.organization_spend_position_v1 p where p.spend_occurrence_id=v_spend.id)
  );
end;
$function$;

create or replace function atlas.correct_organization_spend_self_api_v1(
  p_spend_occurrence_id uuid,
  p_client_event_key text,
  p_occurred_on date,
  p_occurred_at timestamptz,
  p_gross_amount numeric,
  p_currency text,
  p_payee_external_relationship_id uuid,
  p_payee_label text,
  p_payment_method text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_spend atlas.organization_spend_occurrences%rowtype;
  v_actor uuid;
  v_event atlas.organization_spend_events%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_allocated numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if nullif(btrim(coalesce(p_client_event_key,'')),'') is null or nullif(btrim(coalesce(p_reason,'')),'') is null then
    raise exception 'Correction event key and reason are required.' using errcode='22023';
  end if;

  select * into v_spend from atlas.organization_spend_occurrences where id=p_spend_occurrence_id for update;
  if v_spend.id is null then raise exception 'Spend occurrence not found.' using errcode='P0002'; end if;
  v_actor:=atlas.current_organization_membership_v1(v_spend.organization_id);
  if v_actor is null then raise exception 'Active organization membership required.' using errcode='42501'; end if;
  if v_spend.recorded_by_membership_id<>v_actor and not atlas.is_organization_owner(v_spend.organization_id) then
    raise exception 'Owner authority is required to correct another member''s Spend.' using errcode='42501';
  end if;
  if v_spend.truth_state='voided' then raise exception 'A voided Spend cannot be corrected.' using errcode='55000'; end if;

  select * into v_event from atlas.organization_spend_events e
  where e.organization_id=v_spend.organization_id and e.source_kind='spend_correction' and e.source_key=btrim(p_client_event_key);
  if v_event.id is not null then
    if v_event.spend_occurrence_id<>v_spend.id then raise exception 'Correction event key is already bound to another Spend.' using errcode='23514'; end if;
    return jsonb_build_object('contractVersion','correct_organization_spend_self_api_v1','state','unchanged','spendOccurrenceId',v_spend.id,'eventId',v_event.id);
  end if;

  select coalesce(sum(a.allocated_amount),0) into v_allocated
  from atlas.organization_spend_allocations a
  where a.spend_occurrence_id=v_spend.id and a.allocation_state='active';
  if p_gross_amount is null or p_gross_amount<=0 or p_gross_amount<v_allocated then
    raise exception 'Corrected gross amount must be positive and cannot be below active allocations.' using errcode='23514';
  end if;

  v_before:=atlas.organization_spend_occurrence_snapshot_v1(v_spend.id);

  update atlas.organization_spend_occurrences s
  set occurred_on=coalesce(p_occurred_on,s.occurred_on),
      occurred_at=p_occurred_at,
      gross_amount=p_gross_amount,
      currency=upper(btrim(p_currency)),
      payee_external_relationship_id=p_payee_external_relationship_id,
      payee_label=nullif(btrim(coalesce(p_payee_label,'')),''),
      payment_method=nullif(btrim(coalesce(p_payment_method,'')),''),
      truth_state='confirmed',
      updated_at=now()
  where s.id=v_spend.id;

  v_after:=atlas.organization_spend_occurrence_snapshot_v1(v_spend.id);

  insert into atlas.organization_spend_events(
    organization_id,spend_occurrence_id,event_kind,actor_membership_id,
    source_kind,source_key,reason,before_state,after_state,metadata
  ) values (
    v_spend.organization_id,v_spend.id,'corrected',v_actor,
    'spend_correction',btrim(p_client_event_key),p_reason,v_before,v_after,'{}'::jsonb
  ) returning * into v_event;

  return jsonb_build_object('contractVersion','correct_organization_spend_self_api_v1','state','corrected','spendOccurrenceId',v_spend.id,'eventId',v_event.id);
end;
$function$;

create or replace function atlas.void_organization_spend_self_api_v1(
  p_spend_occurrence_id uuid,
  p_client_event_key text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_spend atlas.organization_spend_occurrences%rowtype;
  v_actor uuid;
  v_event atlas.organization_spend_events%rowtype;
  v_before jsonb;
  v_after jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if nullif(btrim(coalesce(p_client_event_key,'')),'') is null or nullif(btrim(coalesce(p_reason,'')),'') is null then
    raise exception 'Void event key and reason are required.' using errcode='22023';
  end if;

  select * into v_spend from atlas.organization_spend_occurrences where id=p_spend_occurrence_id for update;
  if v_spend.id is null then raise exception 'Spend occurrence not found.' using errcode='P0002'; end if;
  v_actor:=atlas.current_organization_membership_v1(v_spend.organization_id);
  if v_actor is null then raise exception 'Active organization membership required.' using errcode='42501'; end if;
  if v_spend.recorded_by_membership_id<>v_actor and not atlas.is_organization_owner(v_spend.organization_id) then
    raise exception 'Owner authority is required to void another member''s Spend.' using errcode='42501';
  end if;

  select * into v_event from atlas.organization_spend_events e
  where e.organization_id=v_spend.organization_id and e.source_kind='spend_void' and e.source_key=btrim(p_client_event_key);
  if v_event.id is not null then
    if v_event.spend_occurrence_id<>v_spend.id then raise exception 'Void event key is already bound to another Spend.' using errcode='23514'; end if;
    return jsonb_build_object('contractVersion','void_organization_spend_self_api_v1','state','unchanged','spendOccurrenceId',v_spend.id,'eventId',v_event.id);
  end if;
  if v_spend.truth_state='voided' then raise exception 'Spend is already voided under a different event key.' using errcode='55000'; end if;

  v_before:=atlas.organization_spend_occurrence_snapshot_v1(v_spend.id);
  update atlas.organization_spend_allocations
  set allocation_state='voided',superseded_at=now()
  where spend_occurrence_id=v_spend.id and allocation_state='active';
  update atlas.organization_spend_occurrences set truth_state='voided',updated_at=now() where id=v_spend.id;
  v_after:=atlas.organization_spend_occurrence_snapshot_v1(v_spend.id);

  insert into atlas.organization_spend_events(
    organization_id,spend_occurrence_id,event_kind,actor_membership_id,
    source_kind,source_key,reason,before_state,after_state,metadata
  ) values (
    v_spend.organization_id,v_spend.id,'voided',v_actor,
    'spend_void',btrim(p_client_event_key),p_reason,v_before,v_after,'{}'::jsonb
  ) returning * into v_event;

  return jsonb_build_object('contractVersion','void_organization_spend_self_api_v1','state','voided','spendOccurrenceId',v_spend.id,'eventId',v_event.id);
end;
$function$;

create or replace function atlas.organization_spend_window_self_api_v1(
  p_organization_id uuid,
  p_start_on date,
  p_end_on date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_membership_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  v_membership_id:=atlas.current_organization_membership_v1(p_organization_id);
  if v_membership_id is null then raise exception 'Active organization membership required.' using errcode='42501'; end if;
  if p_start_on is null or p_end_on is null or p_end_on<p_start_on then raise exception 'Valid Spend date window required.' using errcode='22023'; end if;

  return jsonb_build_object(
    'schemaVersion','atlas_organization_spend_window_v1',
    'organizationId',p_organization_id,
    'startOn',p_start_on,
    'endOn',p_end_on,
    'spend',coalesce((
      select jsonb_agg(jsonb_build_object(
        'spendOccurrenceId',p.spend_occurrence_id,
        'organizationUnitId',p.organization_unit_id,
        'occurredOn',p.occurred_on,
        'occurredAt',p.occurred_at,
        'grossAmount',p.gross_amount,
        'currency',p.currency,
        'fundingKind',p.funding_kind,
        'payerMembershipId',p.payer_membership_id,
        'payeeExternalRelationshipId',p.payee_external_relationship_id,
        'payeeLabel',p.payee_label,
        'paymentMethod',p.payment_method,
        'truthState',p.truth_state,
        'allocatedAmount',p.allocated_amount,
        'unallocatedAmount',p.unallocated_amount,
        'activeAllocationCount',p.active_allocation_count,
        'allocations',coalesce((
          select jsonb_agg(jsonb_build_object(
            'id',a.id,'organizationUnitId',a.organization_unit_id,'amount',a.allocated_amount,
            'operationalPurpose',a.operational_purpose,'subjectDomain',a.subject_domain,
            'subjectKind',a.subject_kind,'subjectId',a.subject_id
          ) order by a.created_at,a.id)
          from atlas.organization_spend_allocations a
          where a.spend_occurrence_id=p.spend_occurrence_id and a.allocation_state='active'
        ),'[]'::jsonb)
      ) order by p.occurred_on desc,p.created_at desc,p.spend_occurrence_id)
      from atlas.organization_spend_position_v1 p
      where p.organization_id=p_organization_id
        and p.occurred_on between p_start_on and p_end_on
    ),'[]'::jsonb)
  );
end;
$function$;

alter table atlas.organization_spend_occurrences enable row level security;
alter table atlas.organization_spend_allocations enable row level security;
alter table atlas.organization_spend_events enable row level security;
alter table atlas.organization_spend_evidence_links enable row level security;

revoke all on table atlas.organization_spend_occurrences from public, anon, authenticated;
revoke all on table atlas.organization_spend_allocations from public, anon, authenticated;
revoke all on table atlas.organization_spend_events from public, anon, authenticated;
revoke all on table atlas.organization_spend_evidence_links from public, anon, authenticated;
revoke all on table atlas.organization_spend_position_v1 from public, anon, authenticated;

revoke all on function atlas.organization_spend_assert_membership_v1(uuid,uuid,text) from public, anon, authenticated;
revoke all on function atlas.organization_spend_assert_unit_v1(uuid,uuid) from public, anon, authenticated;
revoke all on function atlas.organization_spend_occurrence_snapshot_v1(uuid) from public, anon, authenticated;
revoke all on function atlas.organization_spend_parse_allocations_internal_v1(uuid,uuid,uuid,jsonb,jsonb) from public, anon, authenticated;
revoke all on function atlas.record_organization_spend_internal_v1(uuid,uuid,uuid,date,timestamptz,numeric,text,text,uuid,uuid,text,text,text,text,jsonb,jsonb,jsonb) from public, anon, authenticated;
revoke all on function atlas.record_organization_spend_self_api_v1(uuid,text,uuid,date,timestamptz,numeric,text,text,uuid,uuid,text,text,jsonb,jsonb) from public, anon;
revoke all on function atlas.replace_organization_spend_allocations_self_api_v1(uuid,text,jsonb,text) from public, anon;
revoke all on function atlas.correct_organization_spend_self_api_v1(uuid,text,date,timestamptz,numeric,text,uuid,text,text,text) from public, anon;
revoke all on function atlas.void_organization_spend_self_api_v1(uuid,text,text) from public, anon;
revoke all on function atlas.organization_spend_window_self_api_v1(uuid,date,date) from public, anon;

grant execute on function atlas.record_organization_spend_self_api_v1(uuid,text,uuid,date,timestamptz,numeric,text,text,uuid,uuid,text,text,jsonb,jsonb) to authenticated;
grant execute on function atlas.replace_organization_spend_allocations_self_api_v1(uuid,text,jsonb,text) to authenticated;
grant execute on function atlas.correct_organization_spend_self_api_v1(uuid,text,date,timestamptz,numeric,text,uuid,text,text,text) to authenticated;
grant execute on function atlas.void_organization_spend_self_api_v1(uuid,text,text) to authenticated;
grant execute on function atlas.organization_spend_window_self_api_v1(uuid,date,date) to authenticated;

grant execute on function atlas.record_organization_spend_internal_v1(uuid,uuid,uuid,date,timestamptz,numeric,text,text,uuid,uuid,text,text,text,text,jsonb,jsonb,jsonb) to service_role;
