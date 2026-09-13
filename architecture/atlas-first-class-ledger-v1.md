# Atlas First-Class Ledger v1

**Status:** Candidate implementation contract
**Date:** 2026-09-13
**Prerequisites:** Canonical Person v1; Person-first Principal/Membership resolution v1
**Immediate proving case:** current Feast Guild organization scope without yet adjudicating Elm/Feast Guild history

## 1. Purpose

Introduce Ledger as a first-class canonical institutional address instead of continuing to infer institutional reality solely from `organization_id`.

The governing distinction is:

> **Organization answers what institution this is. Ledger answers what canonical institutional reality belongs there.**

This tranche establishes Ledger identity, root Principal authority, compatibility attachment for current organization-ledger records, and safe read resolution. It does not perform historical institutional separation.

## 2. Governing order

```text
Person
  ↓
Principal
  ↓ authority over
Ledger
  ↓ governing reality of
Organization
```

Organization and Ledger are related but not interchangeable.

## 3. New canonical objects

### `atlas.ledgers`

Minimum v1 fields:

- `id uuid primary key`
- `stable_key text unique`
- `organization_id uuid not null references atlas.organizations(id)`
- `ledger_kind text not null`
- `status text not null`
- `metadata jsonb not null`
- `created_at timestamptz not null`
- `updated_at timestamptz not null`

V1 admits one primary governing Ledger per Organization. Enforce this with a uniqueness constraint on `organization_id`.

`ledger_kind` v1 value: `organization_governing`.

Ledger birth is noncommercial. No entitlement or purchase row is required to create or preserve a Ledger.

### `atlas.principal_ledger_authorities`

This is the root institutional authority relation and is distinct from operational `principal_authority_allocations`.

Minimum fields:

- `id uuid primary key`
- `principal_id uuid not null references atlas.principals(id)`
- `ledger_id uuid not null references atlas.ledgers(id)`
- `authority_kind text not null`
- `status text not null`
- `basis text not null`
- `established_at timestamptz not null`
- `ended_at timestamptz null`
- `metadata jsonb not null`
- `created_at timestamptz not null`
- `updated_at timestamptz not null`

V1 authority kind: `root_governing`.

Multiple Principals may eventually hold governed authority over one Ledger. One Principal may hold authority over many Ledgers.

Do not infer root Ledger authority from operational allocation rows.

## 4. Why `principal_authority_allocations` is not reused

`principal_authority_allocations` currently expresses operational authority claims against Organization Memberships, Portfolio Units, and Operating Functions. It is suited to delegated/operational authority, not the ontological root relation proving that a Principal governs a Ledger.

The new relation must remain inspectable even when no position, portfolio unit, or operating function exists.

## 5. Existing organization-ledger entries

`atlas.organization_ledger_entries` currently uses `organization_id` as the practical Ledger namespace.

This tranche adds `ledger_id` and backfills it through the Organization's governing Ledger.

Compatibility law:

- current writers may continue supplying `organization_id`;
- a database guard/derivation fills the canonical `ledger_id` from the Organization;
- `ledger_id` and `organization_id` must never point to different institutions;
- after backfill, existing entry IDs, revisions, payloads, provenance, and subject links remain unchanged.

`organization_id` remains meaningful compatibility/institution identity. It is not mechanically removed.

## 6. Commercial Ledger entitlement bindings

`ledger_entitlement_bindings` is a commercial capability/access structure, not Ledger identity.

Where such a binding exists, it should be capable of referring to the canonical Ledger it commercially affects. This tranche may add `ledger_id` derived from its existing `organization_id` while preserving the existing commercial columns and semantics.

A Ledger may exist without any entitlement binding.

An entitlement may never create the Ledger ontologically.

## 7. Current production backfill

Current production contains two Organizations:

- `atlas_reference_company`
- `feast_guild`

The current `feast_guild` Organization still contains mixed historical farm reality, including Elm and Waiting Room Farm organization units and existing organization-ledger entries.

Therefore this tranche must not label that institutional scope as already clean Feast Guild reality.

Backfill rule:

- create one governing Ledger for every current Organization;
- preserve Organization stable identity;
- for ordinary/unambiguous current organizations, metadata records `scope_state = canonical`;
- for current Organization `feast_guild`, metadata records `scope_state = legacy_mixed_pending_adjudication` and the reason;
- do not move, rename, delete, or reclassify Elm/Waiting Room records in this tranche.

The `feast_guild` Ledger created here is the first-class identity of the current historical organization scope. Later institutional separation will adjudicate which records remain with Feast Guild and which move to newly correct institutional Ledgers.

This avoids both bad outcomes:

1. pretending the historical scope is already clean Feast Guild; and
2. creating a second competing Feast Guild identity before adjudication.

## 8. Root authority backfill

Current `principals.organization_id` remains legacy compatibility evidence.

For each active Principal with a current `organization_id`, create `principal_ledger_authorities` for that Organization's governing Ledger with:

- `authority_kind = root_governing`
- `status = active`
- `basis = legacy_principal_organization_compatibility`

This establishes the new authority graph without deleting or changing `principals.organization_id` yet.

The legacy column stops being the future semantic answer to “which Ledger does this Principal govern?” once Ledger-aware readers exist.

## 9. Canonical read helpers

Introduce bounded read helpers:

### `primary_ledger_for_organization_v1(p_organization_id uuid) -> uuid`
Returns the active governing Ledger for the Organization.

### `principal_has_ledger_authority_v1(p_principal_id uuid, p_ledger_id uuid) -> boolean`
Returns whether the Principal currently holds active root governing authority over that Ledger.

### `principal_ledgers_self_api_v1() -> jsonb`
Authenticated safe projection using `current_principal_id_v1()`.

For each visible Ledger, return only safe institutional identity and authority facts, including:

- Ledger ID
- Ledger stable key
- Ledger name or Organization name projection
- Organization ID
- Organization stable key/name
- Ledger kind/status
- authority kind
- scope state

Do not expose arbitrary metadata, commercial details, or unrelated Organization state.

## 10. Security

- no `anon` direct table access;
- no `authenticated` direct table access to canonical Ledger/authority tables;
- authenticated clients use governed functions;
- helpers pin `search_path`;
- current Person-first Principal resolution remains the root authenticated identity seam;
- no service credential, Stripe state, or storefront session becomes Ledger identity.

## 11. Current organization-ledger projection compatibility

Existing functions such as organization-ledger owner reads and event projection may continue to accept `organization_id` in this tranche.

Their underlying entries acquire canonical `ledger_id` through database derivation/backfill.

A later tranche may introduce Ledger-addressed public/internal APIs once callers are ready.

Do not force a broad API rename in the identity tranche.

## 12. No historical separation in this migration

Explicit non-scope:

- create a new Elm Organization;
- move Elm Organization Units;
- move Waiting Room Farm;
- reassign six current Berry Walk organization-ledger entries;
- move institutional communication sources/endpoints;
- change Farm Steward responsibilities;
- clean Feast Guild memberships;
- rename historical records;
- delete the existing Feast Guild Organization;
- create flower-commerce tables;
- create new Organization/Ledger onboarding UI.

Those require separate adjudication after Ledger identity is live.

## 13. Required clone proof

Production-schema clone validation must prove:

1. every current Organization has exactly one active `organization_governing` Ledger;
2. every current Organization Ledger Entry maps to the Ledger belonging to the same Organization;
3. no Ledger Entry ID/revision/event key changes during backfill;
4. every current Principal with a legacy `organization_id` gets corresponding root Ledger authority;
5. one Principal may hold multiple Ledger authority rows without schema contradiction;
6. `feast_guild` Ledger is marked `legacy_mixed_pending_adjudication`;
7. `atlas_reference_company` is not incorrectly marked mixed;
8. Ledger existence has no dependency on `ledger_entitlements` or purchases;
9. direct browser table access remains denied;
10. current Organization-ledger APIs remain present with unchanged signatures.

## 14. Failure semantics

If an Organization lacks a governing Ledger after this tranche, Ledger-addressed resolution fails closed.

Do not silently create a Ledger from a read helper.

If an entry's Organization and Ledger conflict, writes must fail.

If a Principal lacks explicit Ledger authority, the new authority helper returns false even when some unrelated operational allocation exists.

## 15. Relationship to next tranche

Once first-class Ledger identity is live, Tranche D can safely introduce atomic noncommercial Organization + Ledger establishment:

```text
credential
  → Person
  → Principal authority
  → create Organization
  → create governing Ledger
  → create root Principal→Ledger authority
  → optionally create Person↔Organization membership
  → begin onboarding
```

That contract must ensure Organization + Ledger birth is atomic.

## 16. Feast Guild consequence

After this tranche the current historical scope can be addressed explicitly as a Ledger without claiming the institutional cleanup is finished.

Conceptually:

```text
Principal: Lex
  ↓ root authority
Ledger: feast_guild
  scope_state: legacy_mixed_pending_adjudication
  ↓
Organization: Feast Guild (historical mixed scope)
```

That gives Atlas a stable place from which the later Elm/Feast Guild separation can move institutional custody deliberately rather than inventing identities during cleanup.
