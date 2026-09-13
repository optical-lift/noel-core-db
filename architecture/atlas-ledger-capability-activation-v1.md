# Atlas Ledger Capability Activation v1

**Status:** Governing Gate A architecture contract; no migration yet  
**Date:** 2026-09-13  
**Base:** `28845fffa873063992b41d7a9271fcd8c4f4d3ee` (`atlas_ledger_graph_v1`)  
**First proof capability:** `teaching` v1

## 1. Purpose

Establish the smallest canonical runtime seam by which Atlas can say:

> **A governed capability is available in this Ledger and is attached to this governed subject.**

This tranche exists so Titus can become the first vertical proof without creating a Titus-specific identity, permission, organization, entitlement, or product-state system.

The capability layer must sit on top of existing Atlas truth:

```text
Person -> Principal -> Principal/Ledger root authority
                         |
                         v
                       Ledger
                         |
                         +-- capability activation
                         |
                         +-- optional commercial entitlement grant
```

The governing Ledger is the authority boundary. Organization participation, product purchase, package branding, and UI routing are not substitutes for Ledger authority.

## 2. Governing laws

1. **Ledger first.** Every capability activation belongs to exactly one governing Ledger.
2. **Subject second.** The activation attaches to one governed subject address; it does not copy or convert that subject.
3. **Authority is reused, not recreated.** Gate A introduces no capability role table, permission table, faculty role, student role, or product-local administrator concept.
4. **Root authority is sufficient for v1.** Only an active Principal with active `root_governing` authority over the governing Ledger may create or transition an activation in Gate A.
5. **Commerce is separate.** A commercial entitlement may grant paid use of a capability to a Ledger, but it may not create the Ledger, create Principal authority, create the activation, or transition activation state.
6. **Activation is durable truth.** Pausing or retiring a capability never deletes historical capability evidence or domain records.
7. **Definitions are governed software.** Capability definitions are introduced by reviewed migrations/source, not customer-authored runtime records.
8. **No generic EAV domain platform.** Capability activation is a narrow generic seam. Academic, distribution, publishing, and other domain truth remains in real domain contracts.
9. **Browser table access stays closed.** Authenticated browser clients operate through bounded APIs, not direct writes to capability tables.
10. **Unknown capability keys fail closed.** No caller may create a free-form capability by passing an arbitrary string.

## 3. Existing canonical contracts reused unchanged

Gate A must reuse these current contracts rather than shadowing them:

- `atlas.people`
- `atlas.person_auth_credentials`
- `atlas.principals`
- `atlas.ledgers`
- `atlas.principal_ledger_authorities`
- `atlas.principal_has_ledger_authority_v1(uuid,uuid)`
- `atlas.current_person_id_v1()`
- `atlas.current_principal_id_v1()`
- `atlas.ledger_organization_participations`
- `atlas.ledger_relationships`
- `atlas.ledger_correlations`
- `atlas.ledger_entitlements`
- `atlas.ledger_entitlement_bindings`

Current production law already provides the exact root authority check Gate A needs:

```text
principal_has_ledger_authority_v1(principal_id, ledger_id)
  -> active Principal/Ledger root_governing authority
  -> active Ledger
```

No new owner/admin law belongs in Gate A.

## 4. Capability definition registry

Gate A introduces a small migration-owned registry:

```text
atlas.capability_definitions
  capability_key text
  capability_version integer
  status text
  eligible_subject_kinds text[]
  created_at timestamptz
  retired_at timestamptz nullable
```

Primary key:

```text
(capability_key, capability_version)
```

Initial state values:

- `active`
- `retired`

Rules:

- rows are created/changed only through governed migration/source custody;
- no browser mutation API exists;
- `anon` and `authenticated` receive no direct table privileges;
- definition rows contain only runtime identity and eligibility facts, not arbitrary domain schema or customer configuration;
- domain constitutions remain in reviewed source/architecture and domain-specific schema.

Initial seed:

```text
capability_key: teaching
capability_version: 1
status: active
eligible_subject_kinds: [ledger]
```

The first migration intentionally supports only `ledger` as a Teaching subject kind. This is enough to prove the vertical without pretending Atlas already has a universal cross-domain subject registry. Later subject kinds may be added only when their canonical address/existence contract is proven.

## 5. Capability activation

Gate A introduces:

```text
atlas.capability_activations
```

Minimum durable columns:

```text
id uuid primary key
ledger_id uuid not null
capability_key text not null
capability_version integer not null
subject_ledger_id uuid not null
subject_kind text not null
subject_id uuid nullable
subject_key text nullable
subject_path text nullable
state text not null
created_by_person_id uuid not null
created_by_principal_id uuid not null
created_at timestamptz not null
updated_at timestamptz not null
retired_at timestamptz nullable
```

Foreign keys:

- `ledger_id -> atlas.ledgers(id)`
- `(capability_key, capability_version) -> atlas.capability_definitions`
- `subject_ledger_id -> atlas.ledgers(id)`
- `created_by_person_id -> atlas.people(id)`
- `created_by_principal_id -> atlas.principals(id)`

Initial states:

- `draft`
- `active`
- `paused`
- `retired`

State shape:

- `draft`: `retired_at is null`
- `active`: `retired_at is null`
- `paused`: `retired_at is null`
- `retired`: `retired_at is not null`

Subject address law:

```text
subject_id is not null OR nonblank(subject_key)
```

For `teaching` v1, the only accepted subject shape is:

```text
subject_kind = 'ledger'
subject_ledger_id = subject_id
subject_key is null
subject_path is null
```

The governing Ledger and subject Ledger may be the same Ledger. Gate A does not require them to be universally identical because later capabilities may govern a derived use in one Ledger while referencing source reality in another. Cross-Ledger use must eventually be proven through existing Ledger Graph/correlation rules rather than copied truth.

## 6. Activation identity and idempotency

There may be at most one non-retired activation for the same semantic address:

```text
governing ledger
+ capability key/version
+ subject ledger
+ subject kind
+ subject id/key/path
```

A draft, active, or paused activation is the same durable activation moving through lifecycle states.

If a caller retries creation for the exact same non-retired semantic address, the API returns the existing activation rather than duplicating it.

If the prior activation was retired, a later new activation may be created. Historical rows remain intact.

## 7. Capability activation events

Current activation state is not sufficient evidence by itself. Gate A introduces append-only lifecycle evidence:

```text
atlas.capability_activation_events
```

Minimum columns:

```text
id uuid primary key
capability_activation_id uuid not null
ledger_id uuid not null
actor_person_id uuid not null
actor_principal_id uuid not null
principal_ledger_authority_id uuid not null
from_state text nullable
to_state text not null
event_kind text not null
reason text nullable
basis jsonb not null
occurred_at timestamptz not null
created_at timestamptz not null
```

Initial `event_kind` values:

- `created`
- `activated`
- `paused`
- `resumed`
- `retired`

Every event must point at the exact active `principal_ledger_authorities` row that authorized the transition at the time it happened.

This is evidence of authority use, not a new source of authority.

Events are never updated or deleted by ordinary runtime APIs.

## 8. Legal state transitions

Gate A allows only:

```text
create -> draft

draft  -> active
draft  -> retired

active -> paused
active -> retired

paused -> active
paused -> retired

retired -> terminal
```

`paused -> active` records `event_kind = resumed`.

Illegal transitions fail closed.

A Ledger must be active for creation and every non-retirement transition.

Retirement may remain possible when an activation already exists even if downstream domain objects remain, because retirement suppresses future active behavior rather than erasing history.

## 9. Activation authority

Gate A mutation authority is intentionally narrow.

For every creation or transition, the API must:

1. require a real authenticated user (`auth.uid()`);
2. resolve `current_person_id_v1()`;
3. resolve `current_principal_id_v1()`;
4. require both to exist and be active;
5. verify the Principal belongs to that Person;
6. require `principal_has_ledger_authority_v1(principal_id, ledger_id)`;
7. resolve the exact active `principal_ledger_authorities` row with `authority_kind='root_governing'`;
8. record that authority row on the lifecycle event.

Organization membership alone is insufficient.

Organization owner role alone is insufficient.

Knowing a Ledger UUID is insufficient.

Commercial purchase or entitlement is insufficient.

Gate A does **not** create delegated capability authority. A later Core tranche may add Ledger-scoped delegated jurisdiction only after a concrete need proves that existing Organization responsibility machinery is insufficient.

## 10. Commercial entitlement grant

Existing `ledger_entitlement_bindings` answers whether commercial Atlas capability has been bound to an existing Ledger. It does not identify which vertical capability a package grants.

Gate A therefore introduces one narrow commercial mapping:

```text
atlas.capability_entitlement_grants
```

Minimum columns:

```text
id uuid primary key
ledger_id uuid not null
ledger_entitlement_binding_id uuid not null
capability_key text not null
capability_version integer not null
state text not null
basis jsonb not null
established_at timestamptz not null
ended_at timestamptz nullable
created_at timestamptz not null
updated_at timestamptz not null
```

Initial states:

- `active`
- `ended`

Rules:

1. the referenced entitlement binding must belong to the same `ledger_id`;
2. the referenced entitlement binding must not be `ended` when the grant is established;
3. capability key/version must exist in the governed definition registry;
4. a live commercial grant does not create or activate `capability_activations`;
5. ending a commercial grant does not rewrite historical activation truth;
6. runtime paid-product availability may later require both a live commercial grant and an active capability activation, but the two sources remain separate;
7. no authenticated browser API may turn a purchase into activation authority.

Commercial grant establishment is service/practitioner-side only in v1 and must reuse existing commercial custody/entitlement evidence. Gate A does not expose a self-service browser mutation for it.

## 11. Why entitlement is not stored on the activation row

Do not add `ledger_entitlement_binding_id` directly to `capability_activations` as the source of activation identity.

Reasons:

- capability truth can outlive one commercial billing record;
- an entitlement can change or end without erasing the historical fact that Teaching was activated;
- future package composition may grant more than one capability from one commercial entitlement;
- internal/noncommercial governed use must remain architecturally possible;
- purchase must never become the explanation for who had authority to activate.

Commercial enablement and governed activation therefore remain parallel, correlatable facts.

## 12. Internal validation helpers

The migration should introduce internal helpers conceptually equivalent to:

```text
capability_definition_active_v1(key, version)
capability_subject_valid_v1(key, version, subject address)
capability_root_authority_context_v1(ledger_id)
capability_activation_transition_allowed_v1(from_state, to_state)
capability_entitlement_grant_live_v1(ledger_id, key, version)
```

These are internal contract helpers, not direct browser APIs unless explicitly stated otherwise.

`capability_subject_valid_v1` may contain the narrow `teaching v1 -> ledger subject` validation in Gate A. It must fail unknown keys/versions rather than accept arbitrary polymorphic addresses.

## 13. Browser APIs

Gate A should expose only bounded authenticated mutation/read contracts.

### Create draft activation

Conceptual signature:

```text
create_capability_activation_self_api_v1(
  p_ledger_id uuid,
  p_capability_key text,
  p_capability_version integer,
  p_subject_ledger_id uuid,
  p_subject_kind text,
  p_subject_id uuid,
  p_subject_key text,
  p_subject_path text
) -> jsonb
```

Behavior:

- authenticate;
- resolve Person + Principal;
- require root Ledger authority;
- require active capability definition;
- validate subject shape/existence;
- return same existing non-retired activation on exact retry;
- otherwise create `draft` activation;
- append `created` event with exact authority evidence.

### Transition activation

Conceptual signature:

```text
transition_capability_activation_self_api_v1(
  p_capability_activation_id uuid,
  p_to_state text,
  p_reason text default null
) -> jsonb
```

Behavior:

- authenticate;
- lock activation row;
- resolve Person + Principal;
- require root authority over activation Ledger;
- validate legal transition;
- validate definition/subject remain valid for transitions into active behavior;
- mutate current state;
- append lifecycle event in the same transaction;
- exact retry to the already-current state may return idempotently only when semantically safe; it must not manufacture a second event.

### Read own governed activations

Conceptual signature:

```text
capability_activations_self_api_v1(p_ledger_id uuid) -> jsonb
```

V1 visibility is limited to a Principal with root authority over the Ledger. Student/faculty relationship-aware reads belong to later Titus/projection work, not Gate A.

## 14. Read helper for later domain enforcement

Gate B academic mutation functions need one stable internal gate:

```text
capability_active_for_subject_v1(
  p_ledger_id uuid,
  p_capability_key text,
  p_capability_version integer,
  p_subject_ledger_id uuid,
  p_subject_kind text,
  p_subject_id uuid,
  p_subject_key text,
  p_subject_path text
) -> boolean
```

For the first Titus slice, academic creation/mutation functions may require:

```text
capability_key='teaching'
capability_version=1
state='active'
```

This helper answers runtime activation only. It does not answer who may perform an academic action; academic jurisdiction remains a separate contract.

## 15. Security boundary

All three new relations must have RLS enabled as defense in depth:

- `capability_definitions`
- `capability_activations`
- `capability_activation_events`
- `capability_entitlement_grants`

Direct browser privileges are revoked.

Any `SECURITY DEFINER` function must:

- live in the non-public `atlas` schema;
- set an explicit safe `search_path`;
- check `auth.uid()` for self APIs;
- explicitly resolve canonical Person/Principal identity;
- perform an object-level authority check rather than relying on `authenticated` alone;
- have default `PUBLIC` execute revoked;
- grant execute only to the intended role.

No service-role secret is exposed to the browser.

## 16. What Gate A explicitly does not build

Gate A does not introduce:

- Titus tables;
- Course, Enrollment, Assessment, Submission, or Evaluation yet;
- faculty/student global roles;
- delegated capability permission tables;
- organization-as-owner compatibility shortcuts;
- capability-specific UI;
- capability-specific files;
- calendar;
- tasks/learner obligations;
- custom domains/branding;
- projection composition;
- billing checkout;
- automatic activation from payment;
- automatic pause/retire from payment state;
- a generic capability object/field/value store.

## 17. Validation obligations for the migration tranche

Before merge, production-schema-clone validation must prove at least:

1. `teaching` v1 definition exists and is migration-owned/non-browser-mutable.
2. Unknown capability key/version creation fails.
3. Teaching v1 accepts the exact Ledger subject shape and rejects unsupported subject kinds.
4. A signed-in root Principal can create one draft activation.
5. Exact create retry is idempotent and produces no duplicate activation/event.
6. A signed-in Principal without root authority over that Ledger cannot create an activation.
7. Organization membership/owner role without Principal/Ledger root authority is insufficient.
8. A commercial entitlement binding without Principal/Ledger root authority is insufficient.
9. `draft -> active` succeeds for the authorized Principal and records the exact authority row.
10. `active -> paused -> active` succeeds and records pause/resume evidence.
11. `active|paused|draft -> retired` succeeds and preserves all lifecycle events.
12. `retired -> active` fails.
13. Direct `anon` and `authenticated` table access remains denied.
14. Self APIs reject unsigned callers.
15. A capability entitlement grant cannot be established for a different Ledger than its entitlement binding.
16. Ending/absence of a commercial grant does not delete or rewrite activation history.
17. Commercial grant existence never bypasses root activation authority.
18. No Organization, Ledger, Principal, Principal/Ledger authority, membership, or entitlement is created as a side effect of capability activation.
19. Existing Ledger Graph, commercial Ledger binding, communications, notebook, and application contracts remain unchanged.

## 18. Migration shape after this architecture freezes

The implementation tranche should be one additive migration plus production-shaped validation artifacts. It should not modify existing Ledger identity or commercial binding semantics except to reference them.

Expected additive database objects:

```text
atlas.capability_definitions
atlas.capability_activations
atlas.capability_activation_events
atlas.capability_entitlement_grants

internal validation/authority helpers
create_capability_activation_self_api_v1(...)
transition_capability_activation_self_api_v1(...)
capability_activations_self_api_v1(...)
capability_active_for_subject_v1(...)
```

The migration should seed only `teaching` v1.

## 19. Gate A completion criterion

Gate A is complete when Atlas can prove, from canonical database truth alone:

> A known governed capability definition (`teaching` v1) is attached to a valid governed subject inside a specific Ledger, currently has a durable lifecycle state, every mutation is attributable to an already-authorized Principal/Person using an existing root Ledger authority record, and any commercial permission to use that capability is recorded separately from governance.

Only after that proof is green should Gate B add the first academic objects.
