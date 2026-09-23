# Atlas Person Position Self Projection v0

**Status:** candidate architecture only  
**Date:** 2026-09-22  
**Repository role:** `optical-lift/noel-core-db` candidate custody. No migration identity, merge, production release, or application deployment is implied.

## Purpose

Recover the first executable read membrane for the Person Position architecture without creating a new truth domain.

Person Position answers one bounded question:

> **Where does this authenticated Person presently stand across the canonical reality Atlas is already authorized to expose to them?**

V0 is deliberately incomplete. It proves that Atlas can compose existing Person-rooted relationships into one self-only read while preserving the authority boundaries among identity, membership, durable responsibility, access, Ledger authority, source custody, work, money, time, and attention.

## Governing artery

```text
authenticated credential
→ canonical Person
→ Principal root where established
→ active Household identity where established
→ current institutional memberships
→ current durable institutional responsibilities
→ current organization access as a separate facet
→ current root-governing Ledger authorities
→ current Connected Source orientation
→ explicit unsupported facets
→ read-only Person Position
```

The projection does not establish or mutate any upstream truth.

## V0 non-collapse laws

V0 must preserve:

```text
Person != credential
Principal != Person
membership != access
membership != durable responsibility
durable responsibility != exact Company Work responsibility
exact Company Work responsibility != execution warrant
Ledger authority != Organization role
Ledger authority != commercial entitlement
Connected Source != life fact
source availability != source coverage
Person Position != attention entitlement
Person Position != Clock placement
```

## Why Work, finance, Calendar, and attention are not aggregated in v0

The current source-seam audit found strong current authority for Company Work, institutional Financial Reality, Spend, and Principal/Worker execution surfaces. Those reads are purpose-specific and authority-bound.

V0 does not bypass those membranes merely to appear complete.

Instead it reports those facets as separately available or unsupported:

- **Company Work:** existing Employee Atlas / Worker Day / governed Work reads remain authoritative. V0 does not direct-read all Company Work merely because the Person has a membership or responsibility.
- **Institutional financial position:** current Ledger-authorized financial reads remain on-demand. V0 reports the Ledger contexts that may legitimately be queried but does not pull full order/spend/reporting detail into every Person Position read.
- **Personal Money:** no canonical Personal Money read membrane currently exists; unsupported.
- **Calendar / whole-person commitments:** Connected Source state may say Calendar is connected. That does not establish appointments, reservations, or fixed commitments; unsupported.
- **Private → institutional availability:** no current governed derivation membrane exists; unsupported.
- **Attention Actuals:** no current universal attention-session authority exists; unsupported.

This is an architectural feature, not missing polish.

## V0 contract

`atlas.person_position_self_api_v1()` returns a self-only JSON document with these facets:

- `identity`
- `principalRoot`
- `householdContexts`
- `institutionalMemberships`
- `durableInstitutionalResponsibilities`
- `institutionalAccess`
- `ledgerContexts`
- `sourcePosition`
- `workPosition`
- `financialInstitutionalPosition`
- `stateQuality`
- `unsupportedFacets`
- `truthBoundary`

### Identity

The authenticated credential resolves through `atlas.current_person_id_v1()`.

The response may expose canonical Person identity and display label. It must not use auth email or login label as Person truth.

### Principal root

The response may expose the current active Principal relation and its active Household identity.

Principal remains a relationship/capacity over Person, not a replacement identity.

### Household contexts

V0 exposes only the active Household identity already bound to Principal.

It does not infer Household structure, relationship labels, residence, care needs, or other Household state from the existence of a Home notebook page.

### Institutional memberships

V0 may expose the Person's own active Organization Membership relations and organization labels.

The membership's compatibility role is identified as such. It is not projected as knowledge, action, responsibility, or governing authority.

### Durable institutional responsibilities

V0 wraps the current canonical internal read:

`atlas.effective_person_organization_responsibilities_current_v1(person_id, null)`

Only the current authenticated Person's own rows may cross the new self membrane.

Unresolved scope remains `indeterminate`; V0 may not upgrade it.

### Institutional access

V0 calls the already-governed `atlas.organization_access_self_api_v1()` separately from membership and responsibility.

An empty access list beside a real membership is a valid state.

### Ledger contexts

V0 calls the already-governed `atlas.principal_ledgers_self_api_v1()`.

Root-governing Ledger authority remains separate from Organization membership and commercial entitlement.

### Source position

Where the current governed Connected Source self-read exists, V0 returns that existing self projection as orientation.

Connected Source rows remain evidence-source custody, not discovered life truth.

If the read seam is absent from a receiving schema, V0 returns an explicit unsupported source-position state rather than falling back to raw source tables.

### Work position

V0 does not aggregate Company Work content.

It records that current Work position must be retrieved through existing Work / Employee Atlas membranes. This prevents durable responsibility or membership from silently becoming visibility to institutional content.

### Institutional financial position

V0 does not aggregate full financial detail.

It reports that current root-governing Ledger contexts have separate governed Financial Reality / Spend / reporting reads where those kernels apply.

Personal finance remains unsupported.

## Self-only security boundary

V0 is callable only by `authenticated`.

The function resolves `auth.uid()` → canonical Person internally.

It accepts no Person id parameter.

There is no manager, employer, practitioner, owner, administrator, or service-selected target-Person mode in V0.

A later cross-Person Position read would require its own knowledge/exposure law; V0 does not imply it.

## No persistence

Person Position is computed.

V0 adds no:

- `person_position` table;
- cached shadow profile;
- role matrix;
- visibility table;
- Work copy;
- finance copy;
- Calendar copy;
- source-observation copy.

The function must contain no durable mutation.

## First proof shapes

The disposable clone fixture should prove one contract against:

1. a Personal/Household-only Person;
2. a Person with one Organization Membership, one current durable responsibility, and one root-governing Ledger;
3. a Principal with two different Organization/Ledger contexts.

The contract passes only if all three use the same function without customer-specific branches.

## Required negative proofs

Validation must prove:

- unauthenticated callers cannot execute;
- a credential without canonical Person cannot become a synthetic Position;
- membership can exist while `institutionalAccess` is empty;
- membership does not manufacture durable responsibility;
- durable responsibility uses the canonical current resolver and preserves indeterminate scope;
- one Person can carry multiple institutional contexts without duplicate Person identity;
- Ledger authority is returned only through the existing Principal Ledger self membrane;
- unsupported Calendar, personal-finance, derived-availability, universal-capability, and Attention facets remain explicit;
- the function contains no `INSERT`, `UPDATE`, or `DELETE` path.

## Promotion boundary

This candidate may later be minted into one canonical Atlas migration only after:

1. candidate SQL and rollback proof are coherent on current main;
2. a migration identity is generated through the repository's canonical process;
3. Database Custody CI passes;
4. protected production-schema-clone validation passes on the immutable migration candidate;
5. any release remains separately authorized.

Passing clone validation does not release the projection.

## Explicit non-scope

This candidate does not implement:

- Notebook Composition from Position;
- domain Exposure Contracts;
- Time + Day;
- private-to-institutional derived availability;
- Shared Composition;
- Attention Trace;
- Knowledge Acquisition / Future Truth Preflight;
- Personal Money;
- Calendar ingestion;
- provider activation;
- Work mutation;
- Organization/Position/Responsibility mutation;
- any production or application change.


## Clone failure and repair boundary

The first generated migration package, `20260923005346_atlas_person_position_self_projection_v1`, was **not released**.

Production Schema Clone Validation run `35804043903` failed before candidate behavior executed. The canonical harness rejected the validation fixture because it contained a procedural `DO` block. The fixture contract permits DML-only prerequisite setup; behavioral/procedural construction belongs in the migration postconditions.

That failure exposed a second, independent architecture issue during repair review:

- `20260921150000_atlas_institutional_person_record_v1` made **Institutional Person Record** the canonical Organization-scoped human relation;
- Position Appointments are now canonically bound to `institutional_person_record_id`;
- `organization_membership_id` and `identity_subject_id` on Position Appointment are compatibility/provenance carriers and may be absent;
- the older `effective_person_organization_responsibilities_current_v1` still required Organization Membership + Identity Subject in its current-responsibility path.

The repaired candidate therefore does **not** manufacture those older carriers merely to satisfy the proof.

Instead it adds:

`atlas.effective_person_organization_responsibilities_current_v2(person_id, organization_id)`

with the current governing path:

```text
Person
→ active Institutional Person Record
→ current Position Appointment
→ Position
→ Position Responsibility
→ Responsibility Scope
→ current durable responsibility
```

Organization Membership and Identity Subject remain optional evidence/provenance.

The v1 reader remains in place for compatibility. Person Position v0 consumes v2.

### Repair proof

The repaired validation deliberately proves one Person who has:

- an authenticated Person + Principal + Household;
- a separate Organization Membership as participation/compatibility evidence;
- an Institutional Person Record;
- a current Position Appointment whose `organization_membership_id` is null;
- that same Position Appointment's `identity_subject_id` is null;
- one bounded durable Responsibility.

Person Position must still recover the durable Responsibility through the IPR-rooted appointment while leaving the optional older carriers absent.

That proof prevents the compatibility layer from silently becoming constitutional identity again.

### Fixture custody

The candidate fixture is now strictly DML-only:

- prerequisite `auth.users` rows;
- prerequisite Personal Atlas purchase rows.

All calls, procedural setup, Position/Responsibility construction, and assertions live in the postcondition file executed after the candidate migration on the disposable production-schema clone.

The failed `20260923005346` package is immutable historical evidence and must be superseded by a freshly generated migration after this repaired candidate reaches canonical source.
