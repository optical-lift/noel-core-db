-- Atlas universal financial obligation + settlement kernel v1
--
-- Money movement is evidence of economic settlement, not the economic relationship itself.
-- This layer preserves:
--   * who owes whom what and why;
--   * the canonical Reality entities participating in each economic event and their capacities;
--   * actual settlements, including non-cash settlements;
--   * many-to-many allocation of settlements to obligations;
--   * lineage for refunds/reversals/chargebacks/corrections;
--   * net settlement bundles for processors, payroll, marketplaces, property managers, etc.;
--   * links to governed resource/custody pools where ownership/use constraints matter.
--
-- It is upstream of accounting recognition and journal posting. Nothing in this migration posts a
-- journal entry. Source bank/provider transactions remain authoritative in the mixed-source layer;
-- settlement source links point to those identities rather than copying them.

create table if not exists atlas.financial_obligations (
  id uuid primary key default gen_random_uuid(),
  accounting_book_id uuid not null references atlas.accounting_books(id) on delete restrict,
  obligation_key text not null,
  obligation_kind text not null,
  face_amount numeric not null,
  currency text not null,
  incurred_on date not null,
  due_on date,
  settlement_state text not null default 'open',
  entitlement_state text not null default 'not_applicable',
  refundability_state text not null default 'not_applicable',
  evidence_record_id uuid references atlas.evidence_records(id) on delete restrict,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_by_principal_id uuid references atlas.principals(id) on delete restrict,
  created_by_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint financial_obligations_key_nonempty check (btrim(obligation_key)<>''),
  constraint financial_obligations_kind_check check (
    obligation_kind in (
      'trade_receivable','trade_payable','customer_advance','vendor_advance','debt_principal',
      'interest','compensation','commission','royalty','rent','tax','withholding','garnishment',
      'reimbursement','refund','stored_value','owner_loan','intercompany','distribution',
      'escrow','custody','grant','contribution','settlement_award','other'
    )
  ),
  constraint financial_obligations_amount_check check (face_amount>0),
  constraint financial_obligations_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint financial_obligations_due_check check (due_on is null or due_on>=incurred_on),
  constraint financial_obligations_settlement_state_check check (
    settlement_state in ('open','partially_settled','settled','forgiven','written_off','voided')
  ),
  constraint financial_obligations_entitlement_state_check check (
    entitlement_state in ('not_applicable','conditional','unearned','earned','released')
  ),
  constraint financial_obligations_refundability_state_check check (
    refundability_state in ('not_applicable','refundable','conditional','nonrefundable')
  ),
  constraint financial_obligations_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_obligations_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(accounting_book_id,obligation_key)
);

create index if not exists financial_obligations_book_state_idx
  on atlas.financial_obligations(accounting_book_id,settlement_state,due_on,incurred_on,id);

create table if not exists atlas.financial_obligation_parties (
  id uuid primary key default gen_random_uuid(),
  obligation_id uuid not null references atlas.financial_obligations(id) on delete restrict,
  entity_id uuid not null references reality.entities(id) on delete restrict,
  role_kind text not null,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint financial_obligation_parties_role_check check (
    role_kind in (
      'obligor','obligee','principal','agent','payer','payee','borrower','lender','employer','employee',
      'merchant','platform','government','custodian','beneficiary','issuer','holder','owner','other'
    )
  ),
  constraint financial_obligation_parties_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_obligation_parties_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(obligation_id,entity_id,role_kind)
);

create index if not exists financial_obligation_parties_entity_idx
  on atlas.financial_obligation_parties(entity_id,role_kind,obligation_id);

create table if not exists atlas.financial_settlements (
  id uuid primary key default gen_random_uuid(),
  accounting_book_id uuid not null references atlas.accounting_books(id) on delete restrict,
  settlement_key text not null,
  settlement_on date not null,
  settlement_kind text not null,
  amount numeric not null,
  currency text not null,
  medium_kind text not null,
  settlement_state text not null default 'confirmed',
  evidence_record_id uuid references atlas.evidence_records(id) on delete restrict,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_by_principal_id uuid references atlas.principals(id) on delete restrict,
  created_by_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint financial_settlements_key_nonempty check (btrim(settlement_key)<>''),
  constraint financial_settlements_kind_check check (
    settlement_kind in (
      'payment','receipt','refund','chargeback','transfer','net_payout','writeoff','forgiveness',
      'noncash','barter','distribution','capital_contribution','adjustment','other'
    )
  ),
  constraint financial_settlements_amount_check check (amount>0),
  constraint financial_settlements_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint financial_settlements_medium_check check (
    medium_kind in ('cash','bank','check','card','ach','wire','wallet','stored_value','barter','noncash','book_entry','other')
  ),
  constraint financial_settlements_state_check check (settlement_state in ('observed','confirmed','voided')),
  constraint financial_settlements_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_settlements_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(accounting_book_id,settlement_key)
);

create index if not exists financial_settlements_book_date_idx
  on atlas.financial_settlements(accounting_book_id,settlement_on,settlement_state,id);

create table if not exists atlas.financial_settlement_roles (
  id uuid primary key default gen_random_uuid(),
  settlement_id uuid not null references atlas.financial_settlements(id) on delete restrict,
  entity_id uuid not null references reality.entities(id) on delete restrict,
  role_kind text not null,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint financial_settlement_roles_role_check check (
    role_kind in (
      'payer','payee','principal','agent','processor','merchant','platform','employer','employee',
      'government','custodian','beneficiary','borrower','lender','owner','issuer','holder','other'
    )
  ),
  constraint financial_settlement_roles_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_settlement_roles_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(settlement_id,entity_id,role_kind)
);

create index if not exists financial_settlement_roles_entity_idx
  on atlas.financial_settlement_roles(entity_id,role_kind,settlement_id);

create table if not exists atlas.financial_settlement_source_links (
  id uuid primary key default gen_random_uuid(),
  settlement_id uuid not null references atlas.financial_settlements(id) on delete restrict,
  source_domain text not null,
  source_kind text not null,
  source_id text not null,
  relation_kind text not null default 'evidence_of',
  evidence_record_id uuid references atlas.evidence_records(id) on delete restrict,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint financial_settlement_source_domain_nonempty check (btrim(source_domain)<>''),
  constraint financial_settlement_source_kind_nonempty check (btrim(source_kind)<>''),
  constraint financial_settlement_source_id_nonempty check (btrim(source_id)<>''),
  constraint financial_settlement_source_relation_nonempty check (btrim(relation_kind)<>''),
  constraint financial_settlement_source_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_settlement_source_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(settlement_id,source_domain,source_kind,source_id,relation_kind)
);

create index if not exists financial_settlement_source_lookup_idx
  on atlas.financial_settlement_source_links(source_domain,source_kind,source_id,settlement_id);

create table if not exists atlas.financial_settlement_allocations (
  id uuid primary key default gen_random_uuid(),
  settlement_id uuid not null references atlas.financial_settlements(id) on delete restrict,
  obligation_id uuid not null references atlas.financial_obligations(id) on delete restrict,
  allocation_kind text not null,
  applied_amount numeric not null,
  currency text not null,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint financial_settlement_allocations_kind_check check (
    allocation_kind in (
      'principal','interest','fee','tax','revenue','refund','reimbursement','withholding','commission',
      'royalty','rent','stored_value','custody','distribution','other'
    )
  ),
  constraint financial_settlement_allocations_amount_check check (applied_amount>0),
  constraint financial_settlement_allocations_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint financial_settlement_allocations_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_settlement_allocations_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(settlement_id,obligation_id,allocation_kind)
);

create index if not exists financial_settlement_allocations_obligation_idx
  on atlas.financial_settlement_allocations(obligation_id,settlement_id);

create table if not exists atlas.financial_obligation_state_events (
  id uuid primary key default gen_random_uuid(),
  obligation_id uuid not null references atlas.financial_obligations(id) on delete restrict,
  event_key text not null,
  event_on date not null,
  event_kind text not null,
  event_amount numeric,
  evidence_record_id uuid references atlas.evidence_records(id) on delete restrict,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_by_principal_id uuid references atlas.principals(id) on delete restrict,
  created_by_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint financial_obligation_state_events_key_nonempty check (btrim(event_key)<>''),
  constraint financial_obligation_state_events_kind_check check (
    event_kind in (
      'condition_satisfied','became_unconditional','earned','released','became_nonrefundable',
      'forgiven','written_off','voided','other'
    )
  ),
  constraint financial_obligation_state_events_amount_check check (event_amount is null or event_amount>0),
  constraint financial_obligation_state_events_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_obligation_state_events_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(obligation_id,event_key)
);

create table if not exists atlas.financial_settlement_lineage (
  id uuid primary key default gen_random_uuid(),
  child_settlement_id uuid not null references atlas.financial_settlements(id) on delete restrict,
  parent_settlement_id uuid not null references atlas.financial_settlements(id) on delete restrict,
  relation_kind text not null,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint financial_settlement_lineage_distinct check (child_settlement_id<>parent_settlement_id),
  constraint financial_settlement_lineage_kind_check check (
    relation_kind in ('refund_of','reversal_of','chargeback_of','correction_of','replacement_of','rebate_of')
  ),
  constraint financial_settlement_lineage_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_settlement_lineage_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(child_settlement_id,parent_settlement_id,relation_kind)
);

create index if not exists financial_settlement_lineage_parent_idx
  on atlas.financial_settlement_lineage(parent_settlement_id,relation_kind,child_settlement_id);

create table if not exists atlas.financial_settlement_bundles (
  id uuid primary key default gen_random_uuid(),
  accounting_book_id uuid not null references atlas.accounting_books(id) on delete restrict,
  bundle_key text not null,
  bundle_kind text not null,
  settlement_on date not null,
  currency text not null,
  expected_net_amount numeric,
  bundle_state text not null default 'open',
  evidence_record_id uuid references atlas.evidence_records(id) on delete restrict,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint financial_settlement_bundles_key_nonempty check (btrim(bundle_key)<>''),
  constraint financial_settlement_bundles_kind_check check (
    bundle_kind in ('processor_payout','payroll','marketplace','property_owner_statement','consignment','intercompany_netting','other')
  ),
  constraint financial_settlement_bundles_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint financial_settlement_bundles_state_check check (bundle_state in ('open','reconciled','voided')),
  constraint financial_settlement_bundles_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_settlement_bundles_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(accounting_book_id,bundle_key)
);

create table if not exists atlas.financial_settlement_bundle_items (
  id uuid primary key default gen_random_uuid(),
  bundle_id uuid not null references atlas.financial_settlement_bundles(id) on delete restrict,
  settlement_id uuid not null references atlas.financial_settlements(id) on delete restrict,
  item_kind text not null,
  signed_net_effect numeric not null,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint financial_settlement_bundle_items_kind_check check (
    item_kind in ('gross_receipt','refund','fee','tax','reserve','payout','withholding','adjustment','other')
  ),
  constraint financial_settlement_bundle_items_effect_nonzero check (signed_net_effect<>0),
  constraint financial_settlement_bundle_items_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_settlement_bundle_items_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(bundle_id,settlement_id,item_kind)
);

create table if not exists atlas.financial_obligation_resource_links (
  id uuid primary key default gen_random_uuid(),
  obligation_id uuid not null references atlas.financial_obligations(id) on delete restrict,
  resource_pool_id uuid not null references atlas.accounting_resource_pools(id) on delete restrict,
  resource_interest_id uuid references atlas.accounting_resource_interests(id) on delete restrict,
  relation_kind text not null,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint financial_obligation_resource_links_relation_check check (
    relation_kind in ('funds','backed_by','held_for','restricts','secures','other')
  ),
  constraint financial_obligation_resource_links_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_obligation_resource_links_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(obligation_id,resource_pool_id,resource_interest_id,relation_kind)
);

alter table atlas.financial_obligations enable row level security;
alter table atlas.financial_obligation_parties enable row level security;
alter table atlas.financial_settlements enable row level security;
alter table atlas.financial_settlement_roles enable row level security;
alter table atlas.financial_settlement_source_links enable row level security;
alter table atlas.financial_settlement_allocations enable row level security;
alter table atlas.financial_obligation_state_events enable row level security;
alter table atlas.financial_settlement_lineage enable row level security;
alter table atlas.financial_settlement_bundles enable row level security;
alter table atlas.financial_settlement_bundle_items enable row level security;
alter table atlas.financial_obligation_resource_links enable row level security;

revoke all on table atlas.financial_obligations from public,anon,authenticated;
revoke all on table atlas.financial_obligation_parties from public,anon,authenticated;
revoke all on table atlas.financial_settlements from public,anon,authenticated;
revoke all on table atlas.financial_settlement_roles from public,anon,authenticated;
revoke all on table atlas.financial_settlement_source_links from public,anon,authenticated;
revoke all on table atlas.financial_settlement_allocations from public,anon,authenticated;
revoke all on table atlas.financial_obligation_state_events from public,anon,authenticated;
revoke all on table atlas.financial_settlement_lineage from public,anon,authenticated;
revoke all on table atlas.financial_settlement_bundles from public,anon,authenticated;
revoke all on table atlas.financial_settlement_bundle_items from public,anon,authenticated;
revoke all on table atlas.financial_obligation_resource_links from public,anon,authenticated;

create or replace function atlas.guard_financial_party_canonical_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if not exists(
    select 1 from reality.entities e
    where e.id=new.entity_id
      and e.identity_state='canonical'
  ) then
    raise exception 'Financial party must be a canonical Reality entity.' using errcode='23514';
  end if;
  return new;
end;
$$;
revoke all on function atlas.guard_financial_party_canonical_v1() from public,anon,authenticated;

create trigger financial_obligation_parties_canonical_guard_v1
before insert or update of entity_id on atlas.financial_obligation_parties
for each row execute function atlas.guard_financial_party_canonical_v1();

create trigger financial_settlement_roles_canonical_guard_v1
before insert or update of entity_id on atlas.financial_settlement_roles
for each row execute function atlas.guard_financial_party_canonical_v1();

create or replace function atlas.prevent_financial_append_only_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  raise exception 'Financial lineage, source links, state events, and established allocations are append-only.' using errcode='55000';
end;
$$;
revoke all on function atlas.prevent_financial_append_only_mutation_v1() from public,anon,authenticated;

create trigger financial_settlement_source_links_immutable_v1
before update or delete on atlas.financial_settlement_source_links
for each row execute function atlas.prevent_financial_append_only_mutation_v1();
create trigger financial_settlement_allocations_immutable_v1
before update or delete on atlas.financial_settlement_allocations
for each row execute function atlas.prevent_financial_append_only_mutation_v1();
create trigger financial_obligation_state_events_immutable_v1
before update or delete on atlas.financial_obligation_state_events
for each row execute function atlas.prevent_financial_append_only_mutation_v1();
create trigger financial_settlement_lineage_immutable_v1
before update or delete on atlas.financial_settlement_lineage
for each row execute function atlas.prevent_financial_append_only_mutation_v1();
create trigger financial_obligation_resource_links_immutable_v1
before update or delete on atlas.financial_obligation_resource_links
for each row execute function atlas.prevent_financial_append_only_mutation_v1();

comment on table atlas.financial_obligations is
  'Canonical economic claims/obligations. An obligation is not a payment, source bank transaction, or journal entry.';
comment on table atlas.financial_settlements is
  'Economic settlements of obligations or other value transfers. Source financial transactions remain separate evidence and are linked rather than copied.';
comment on table atlas.financial_settlement_allocations is
  'Many-to-many application of settlements to obligations. One source movement may settle several obligations and one obligation may be settled over many movements.';
comment on table atlas.financial_settlement_roles is
  'Canonical Reality capacities in a settlement. Role is event-specific and must not be inferred from the entity business type.';
comment on table atlas.financial_settlement_bundles is
  'Gross-to-net grouping for processor payouts, payroll, marketplaces, owner statements, consignment, and other net settlements.';
