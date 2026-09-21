# Atlas Relationship Delivery Grant v1

**Status:** Candidate architecture only; not generated, clone-validated, released, or production-active.  
**Date:** 2026-09-21  
**Product authority:** Atlas Product Map `PMD-024` / `RELATIONSHIP-DELIVERY-MEMBRANE.md`

## Purpose

Establish the smallest canonical database primitive needed for Atlas to say:

> this real Person may receive these named delivery projection/response contracts because a source-owned relationship permits it.

The grant is deliberately cross-domain. It must support, without changing its schema:

- Organization / Company Work delivery to an employee, contractor, volunteer, or helper;
- Household delivery to a child or other household member;
- future relationship-owned delivery surfaces.

It does **not** create the Person, relationship, responsibility, source reality, credential, session, or result.

## Governing distinction

```text
Person
  ≠ source relationship
  ≠ Relationship Delivery Grant
  ≠ credential/session
  ≠ projection
  ≠ source-domain response/consequence
```

The source domain remains authoritative for whether the relationship exists and is effective.

## Canonical identity

A grant is anchored to:

- `recipient_person_id` — canonical `atlas.people`;
- `issuer_domain + issuer_kind + issuer_id` — source context allowing delivery;
- `relationship_domain + relationship_kind + relationship_id` — source-owned relationship explaining why this Person may receive delivery;
- validity and revocation state;
- immutable named contract assignments.

Atlas already uses domain/kind/id source addresses elsewhere. This grant adopts the same pattern rather than hard-coding Organization Membership or Household Member columns into the universal table.

## Contract assignments

A grant has one or more rows in `atlas.relationship_delivery_grant_contracts`.

Each row names:

- `projection` or `response`;
- a stable contract key;
- an explicit positive contract version.

Examples may later include:

```text
projection  institution.worker_day.today  v1
response    institution.company_work.result  v1

projection  household.grocery.current  v1
response    household.grocery.result  v1
```

These names do not themselves implement the contracts. Source/application adapters own the executable read/write behavior.

## Source-validation boundary

V1 grant storage intentionally does **not** dynamically dereference arbitrary source tables.

Therefore:

- direct application inserts are prohibited;
- browser roles receive no direct table privileges;
- a later source-specific issuance adapter must validate the relationship and issuer authority before creating a grant;
- every delivery read/write adapter must revalidate source relationship effectiveness before accepting the grant;
- the grant never upgrades a stale or invalid source relationship into authority.

This avoids a universal table becoming a second relationship ontology.

## Lifecycle

V1 uses:

- `active`;
- `revoked`.

Expiration is derived from `expires_at`; it is not a separately written truth state.

Changing the contract set should be modeled as issuing a replacement grant and revoking the old grant, preserving history.

## Security boundary

The tables are server-owned:

- RLS enabled as defense in depth;
- no direct `anon` or `authenticated` table privileges;
- no public browser RPC is introduced in this tranche;
- no bearer secret is stored here.

Credential/bootstrap/session storage is a separate later tranche.

## Pressure tests

The schema must admit all three shapes without a schema fork:

1. `organization / membership → Person Anna → worker projection/result contracts`;
2. `household / member → Person teenager → grocery projection/result contracts`;
3. large Organization issuing many independent grants to many People while querying by recipient/relationship indexes.

## Non-authority

Relationship Delivery Grant is not:

- Organization Membership;
- Household Member;
- Company Work Responsibility;
- Household Responsibility;
- Employee Seat;
- semantic exposure policy;
- authentication;
- Personal Atlas entitlement;
- a generic task;
- a public-link permission.

## Next tranche

After this grant primitive is generated and clone-validated:

1. add one-way-hashed bootstrap credential + short-lived session carriers;
2. add source-specific organization relationship validation/issuance;
3. adapt existing Worker Day/result authorities to the session;
4. prove Anna;
5. later add the Household adapter without changing the grant schema.
