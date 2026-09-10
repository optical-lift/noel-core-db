BEGIN;

-- Atlas Organization Spend Kernel v1 schema proof.
-- Executable reviewed source only. NOT a canonical migration.
-- This file ends in ROLLBACK and must leave no production objects behind.

create table atlas.organization_spend_occurrences (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid references atlas.organization_units(id) on delete restrict,
  occurred_on date not null,
  occurred_at timestamptz,
  gross_amount numeric not null check (gross_amount > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  funding_kind text not null
    check (funding_kind in ('organization','organization_member','external_party','unresolved')),
  payer_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  payee_external_relationship_id uuid references atlas.external_relationships(id) on delete restrict,
  payee_label text,
  payment_method text,
  source_authority text not null check (btrim(source_authority) <> ''),
  source_system_key text,
  source_record_key text,
  recorded_by_membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  truth_state text not null default 'observed'
    check (truth_state in ('observed','confirmed','disputed','voided')),
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (payee_label is null or btrim(payee_label) <> ''),
  check (payment_method is null or btrim(payment_method) <> ''),
  check (
    (funding_kind='organization_member' and payer_membership_id is not null)
    or funding_kind<>'organization_member'
  ),
  unique (organization_id, source_authority, source_system_key, source_record_key),
  unique (id, organization_id)
);

create table atlas.organization_spend_allocations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  spend_occurrence_id uuid not null,
  organization_unit_id uuid references atlas.organization_units(id) on delete restrict,
  allocated_amount numeric not null check (allocated_amount > 0),
  operational_purpose text,
  subject_domain text,
  subject_kind text,
  subject_id text,
  allocation_state text not null default 'active'
    check (allocation_state in ('active','superseded','voided')),
  supersedes_allocation_id uuid references atlas.organization_spend_allocations(id) on delete restrict,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  foreign key (spend_occurrence_id, organization_id)
    references atlas.organization_spend_occurrences(id, organization_id)
    on delete cascade,
  check (operational_purpose is null or btrim(operational_purpose) <> ''),
  check (
    (subject_domain is null and subject_kind is null and subject_id is null)
    or
    (nullif(btrim(coalesce(subject_domain,'')),'') is not null
      and nullif(btrim(coalesce(subject_kind,'')),'') is not null
      and nullif(btrim(coalesce(subject_id,'')),'') is not null)
  ),
  unique (id, spend_occurrence_id, organization_id)
);

create table atlas.organization_spend_evidence_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  spend_occurrence_id uuid not null,
  spend_allocation_id uuid,
  evidence_record_id uuid not null references atlas.evidence_records(id) on delete restrict,
  relation_kind text not null default 'supporting'
    check (relation_kind in ('supporting','receipt','factura','invoice','transaction_observation','context')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  foreign key (spend_occurrence_id, organization_id)
    references atlas.organization_spend_occurrences(id, organization_id)
    on delete cascade,
  foreign key (spend_allocation_id, spend_occurrence_id, organization_id)
    references atlas.organization_spend_allocations(id, spend_occurrence_id, organization_id)
    on delete cascade,
  unique (spend_occurrence_id, spend_allocation_id, evidence_record_id, relation_kind)
);

create index organization_spend_occurrences_org_date_idx
  on atlas.organization_spend_occurrences (organization_id, occurred_on desc, id);

create index organization_spend_allocations_occurrence_state_idx
  on atlas.organization_spend_allocations (spend_occurrence_id, allocation_state, created_at, id);

create index organization_spend_evidence_links_occurrence_idx
  on atlas.organization_spend_evidence_links (spend_occurrence_id, relation_kind, created_at);

-- Organization/unit/member/payee custody guard.
create or replace function atlas.guard_organization_spend_occurrence_v1()
returns trigger
language plpgsql
set search_path=pg_catalog,atlas
as $function$
begin
  if new.organization_unit_id is not null and not exists (
    select 1 from atlas.organization_units ou
    where ou.id=new.organization_unit_id and ou.organization_id=new.organization_id
  ) then
    raise exception 'Spend organization unit must belong to organization.' using errcode='23503';
  end if;

  if not exists (
    select 1 from atlas.organization_memberships om
    where om.id=new.recorded_by_membership_id and om.organization_id=new.organization_id
  ) then
    raise exception 'Spend recorder membership must belong to organization.' using errcode='23503';
  end if;

  if new.payer_membership_id is not null and not exists (
    select 1 from atlas.organization_memberships om
    where om.id=new.payer_membership_id and om.organization_id=new.organization_id
  ) then
    raise exception 'Spend payer membership must belong to organization.' using errcode='23503';
  end if;

  if new.payee_external_relationship_id is not null and not exists (
    select 1 from atlas.external_relationships er
    where er.id=new.payee_external_relationship_id and er.organization_id=new.organization_id
  ) then
    raise exception 'Spend payee relationship must belong to organization.' using errcode='23503';
  end if;

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
  v_active_other numeric;
begin
  if new.organization_unit_id is not null and not exists (
    select 1 from atlas.organization_units ou
    where ou.id=new.organization_unit_id and ou.organization_id=new.organization_id
  ) then
    raise exception 'Spend allocation organization unit must belong to organization.' using errcode='23503';
  end if;

  select s.gross_amount into v_gross
  from atlas.organization_spend_occurrences s
  where s.id=new.spend_occurrence_id and s.organization_id=new.organization_id;

  if v_gross is null then
    raise exception 'Spend allocation occurrence is invalid.' using errcode='23503';
  end if;

  if new.allocation_state='active' then
    select coalesce(sum(a.allocated_amount),0) into v_active_other
    from atlas.organization_spend_allocations a
    where a.spend_occurrence_id=new.spend_occurrence_id
      and a.organization_id=new.organization_id
      and a.allocation_state='active'
      and a.id is distinct from new.id;

    if v_active_other + new.allocated_amount > v_gross then
      raise exception 'Active spend allocations cannot exceed occurrence gross amount.' using errcode='23514';
    end if;
  end if;

  if new.supersedes_allocation_id is not null and not exists (
    select 1 from atlas.organization_spend_allocations a
    where a.id=new.supersedes_allocation_id
      and a.spend_occurrence_id=new.spend_occurrence_id
      and a.organization_id=new.organization_id
  ) then
    raise exception 'Superseded allocation must belong to the same spend occurrence.' using errcode='23503';
  end if;

  return new;
end;
$function$;

create trigger guard_organization_spend_allocation_v1
before insert or update on atlas.organization_spend_allocations
for each row execute function atlas.guard_organization_spend_allocation_v1();

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
  s.source_authority,
  s.source_system_key,
  s.source_record_key,
  s.recorded_by_membership_id,
  s.truth_state,
  coalesce(sum(a.allocated_amount) filter (where a.allocation_state='active'),0) as allocated_amount,
  s.gross_amount - coalesce(sum(a.allocated_amount) filter (where a.allocation_state='active'),0) as unallocated_amount,
  count(a.id) filter (where a.allocation_state='active') as active_allocation_count
from atlas.organization_spend_occurrences s
left join atlas.organization_spend_allocations a
  on a.spend_occurrence_id=s.id and a.organization_id=s.organization_id
group by s.id;

-- Narrow authenticated organization-member command.
create or replace function atlas.record_organization_spend_api_v1(
  p_organization_id uuid,
  p_organization_unit_id uuid,
  p_occurred_on date,
  p_gross_amount numeric,
  p_currency text,
  p_funding_kind text,
  p_payer_membership_id uuid,
  p_payee_external_relationship_id uuid,
  p_payee_label text,
  p_payment_method text,
  p_source_authority text,
  p_source_system_key text,
  p_source_record_key text,
  p_operational_purpose text,
  p_subject_domain text,
  p_subject_kind text,
  p_subject_id text,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_membership_id uuid;
  v_spend atlas.organization_spend_occurrences%rowtype;
  v_allocation atlas.organization_spend_allocations%rowtype;
  v_existing atlas.organization_spend_occurrences%rowtype;
begin
  v_membership_id := atlas.current_organization_membership_v1(p_organization_id);
  if v_membership_id is null then
    raise exception 'Active organization membership required.' using errcode='42501';
  end if;

  if p_organization_unit_id is not null and not exists (
    select 1 from atlas.organization_units ou
    where ou.id=p_organization_unit_id and ou.organization_id=p_organization_id
  ) then
    raise exception 'Organization unit does not belong to organization.' using errcode='23503';
  end if;

  if p_payer_membership_id is not null and p_payer_membership_id<>v_membership_id
     and not atlas.is_organization_owner(p_organization_id) then
    raise exception 'Only an organization owner may record another member as payer.' using errcode='42501';
  end if;

  if nullif(btrim(coalesce(p_source_record_key,'')),'') is not null then
    select * into v_existing
    from atlas.organization_spend_occurrences s
    where s.organization_id=p_organization_id
      and s.source_authority=btrim(p_source_authority)
      and s.source_system_key is not distinct from nullif(btrim(coalesce(p_source_system_key,'')),'')
      and s.source_record_key is not distinct from nullif(btrim(coalesce(p_source_record_key,'')),'');
    if found then
      return jsonb_build_object(
        'contractVersion','record_organization_spend_api_v1',
        'state','already_in_custody',
        'spendOccurrenceId',v_existing.id,
        'grossAmount',v_existing.gross_amount,
        'currency',v_existing.currency
      );
    end if;
  end if;

  insert into atlas.organization_spend_occurrences(
    organization_id,organization_unit_id,occurred_on,gross_amount,currency,
    funding_kind,payer_membership_id,payee_external_relationship_id,payee_label,
    payment_method,source_authority,source_system_key,source_record_key,
    recorded_by_membership_id,truth_state,provenance,metadata
  ) values (
    p_organization_id,p_organization_unit_id,p_occurred_on,p_gross_amount,upper(btrim(p_currency)),
    p_funding_kind,p_payer_membership_id,p_payee_external_relationship_id,
    nullif(btrim(coalesce(p_payee_label,'')),''),nullif(btrim(coalesce(p_payment_method,'')),''),
    btrim(p_source_authority),nullif(btrim(coalesce(p_source_system_key,'')),''),
    nullif(btrim(coalesce(p_source_record_key,'')),''),v_membership_id,'confirmed',
    coalesce(p_provenance,'{}'::jsonb),coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_spend;

  if nullif(btrim(coalesce(p_operational_purpose,'')),'') is not null then
    insert into atlas.organization_spend_allocations(
      organization_id,spend_occurrence_id,organization_unit_id,allocated_amount,
      operational_purpose,subject_domain,subject_kind,subject_id,provenance
    ) values (
      p_organization_id,v_spend.id,p_organization_unit_id,p_gross_amount,
      btrim(p_operational_purpose),nullif(btrim(coalesce(p_subject_domain,'')),''),
      nullif(btrim(coalesce(p_subject_kind,'')),''),nullif(btrim(coalesce(p_subject_id,'')),''),
      coalesce(p_provenance,'{}'::jsonb)
    ) returning * into v_allocation;
  end if;

  return jsonb_build_object(
    'contractVersion','record_organization_spend_api_v1',
    'state','admitted',
    'spendOccurrenceId',v_spend.id,
    'allocationId',v_allocation.id,
    'grossAmount',v_spend.gross_amount,
    'currency',v_spend.currency,
    'unallocatedAmount',case when v_allocation.id is null then v_spend.gross_amount else 0 end
  );
end;
$function$;

-- No direct application write grants in this proof.
revoke all on atlas.organization_spend_occurrences from anon, authenticated;
revoke all on atlas.organization_spend_allocations from anon, authenticated;
revoke all on atlas.organization_spend_evidence_links from anon, authenticated;
revoke all on atlas.organization_spend_position_v1 from anon, authenticated;
revoke all on function atlas.record_organization_spend_api_v1(uuid,uuid,date,numeric,text,text,uuid,uuid,text,text,text,text,text,text,text,text,text,jsonb,jsonb) from public, anon;
grant execute on function atlas.record_organization_spend_api_v1(uuid,uuid,date,numeric,text,text,uuid,uuid,text,text,text,text,text,text,text,text,text,jsonb,jsonb) to authenticated;

ROLLBACK;
