-- Atlas Relationship Delivery Grant v1.
-- Universal delivery permission substrate beneath source-owned relationships.
-- This tranche creates no credential/session carrier and no browser API.

begin;

create table atlas.relationship_delivery_grants (
  id uuid primary key default gen_random_uuid(),
  recipient_person_id uuid not null references atlas.people(id) on delete restrict,

  issuer_domain text not null,
  issuer_kind text not null,
  issuer_id text not null,

  relationship_domain text not null,
  relationship_kind text not null,
  relationship_id text not null,

  lifecycle_state text not null default 'active'
    check (lifecycle_state in ('active','revoked')),

  valid_from timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,

  provenance jsonb not null default '{}'::jsonb
    check (jsonb_typeof(provenance) = 'object'),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint relationship_delivery_grants_issuer_domain_nonblank
    check (length(btrim(issuer_domain)) > 0),
  constraint relationship_delivery_grants_issuer_kind_nonblank
    check (length(btrim(issuer_kind)) > 0),
  constraint relationship_delivery_grants_issuer_id_nonblank
    check (length(btrim(issuer_id)) > 0),

  constraint relationship_delivery_grants_relationship_domain_nonblank
    check (length(btrim(relationship_domain)) > 0),
  constraint relationship_delivery_grants_relationship_kind_nonblank
    check (length(btrim(relationship_kind)) > 0),
  constraint relationship_delivery_grants_relationship_id_nonblank
    check (length(btrim(relationship_id)) > 0),

  constraint relationship_delivery_grants_validity_window
    check (expires_at is null or expires_at > valid_from),

  constraint relationship_delivery_grants_revocation_accounting
    check (
      (lifecycle_state = 'active' and revoked_at is null)
      or
      (lifecycle_state = 'revoked' and revoked_at is not null)
    )
);

comment on table atlas.relationship_delivery_grants is
  'Revocable relationship-scoped delivery permission for one canonical Person. The source relationship remains authoritative; this grant does not create identity, relationship, responsibility, source truth, credential, or result.';

comment on column atlas.relationship_delivery_grants.recipient_person_id is
  'Canonical Atlas Person receiving the bounded delivery projection. Personal Atlas ownership or authentication is not required by this relation.';

comment on column atlas.relationship_delivery_grants.issuer_domain is
  'Source domain of the context authorizing delivery, such as organization or household. This address is provenance/context, not generic source authority by itself.';

comment on column atlas.relationship_delivery_grants.relationship_domain is
  'Source domain that owns the relationship explaining why this Person may receive the delivery. Delivery adapters must revalidate that source relation.';

comment on column atlas.relationship_delivery_grants.lifecycle_state is
  'Grant lifecycle only. Expiration is derived from expires_at; ending a grant does not end the underlying Person or source relationship.';

create index relationship_delivery_grants_recipient_active_idx
  on atlas.relationship_delivery_grants (
    recipient_person_id,
    lifecycle_state,
    valid_from,
    expires_at
  );

create index relationship_delivery_grants_relationship_active_idx
  on atlas.relationship_delivery_grants (
    relationship_domain,
    relationship_kind,
    relationship_id,
    lifecycle_state
  );

create index relationship_delivery_grants_issuer_active_idx
  on atlas.relationship_delivery_grants (
    issuer_domain,
    issuer_kind,
    issuer_id,
    lifecycle_state
  );

alter table atlas.relationship_delivery_grants enable row level security;
revoke all on table atlas.relationship_delivery_grants from public, anon, authenticated;

create table atlas.relationship_delivery_grant_contracts (
  grant_id uuid not null
    references atlas.relationship_delivery_grants(id) on delete cascade,

  contract_kind text not null
    check (contract_kind in ('projection','response')),

  contract_key text not null,
  contract_version integer not null
    check (contract_version > 0),

  created_at timestamptz not null default now(),

  primary key (grant_id, contract_kind, contract_key, contract_version),

  constraint relationship_delivery_grant_contracts_key_nonblank
    check (length(btrim(contract_key)) > 0)
);

comment on table atlas.relationship_delivery_grant_contracts is
  'Named versioned projection/response contracts admitted by one Relationship Delivery Grant. Contract rows name executable adapters but do not implement or own source-domain truth.';

create index relationship_delivery_grant_contracts_lookup_idx
  on atlas.relationship_delivery_grant_contracts (
    contract_kind,
    contract_key,
    contract_version,
    grant_id
  );

alter table atlas.relationship_delivery_grant_contracts enable row level security;
revoke all on table atlas.relationship_delivery_grant_contracts from public, anon, authenticated;

commit;
