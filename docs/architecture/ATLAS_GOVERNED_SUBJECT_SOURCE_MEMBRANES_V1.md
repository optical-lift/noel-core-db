# Atlas Governed Subject Source Membranes V1

Status: **source implementation checkpoint; branch only, not applied to production**

Date: 2026-09-28

Branch: `governed-subject-observation-applicability-v1`

## 1. Purpose

The Atlas governed-reality work exposed two missing source-domain facts that cannot lawfully be manufactured by operational projections:

1. an append-only observation about one exact canonical `reality.resources` subject;
2. an explicit governed relation saying one exact institutional Responsibility scope applies to one exact resource subject for one exact operation.

This tranche adds source membranes for those facts without introducing Task state, Work state, execution authority, or a generic transition table.

## 2. Source separation

The architecture keeps three independent questions distinct:

```text
What is the observed condition of this physical/resource subject?
```

```text
Who currently carries this institutional Responsibility?
```

```text
Does this exact Responsibility scope apply to this exact subject for this exact operation?
```

The first and third questions are implemented here.

The existing institutional Responsibility resolver remains the authority for the second.

No function in this tranche derives a current Person carrier and no function grants an Execution Lease.

## 3. Resource observation membrane

### Canonical store

`reality.resource_observations`

Each row is append-only source evidence with:

- exact `resource_id`;
- nonblank `observation_type`;
- object-valued `observation_payload`;
- explicit `observer_ref`;
- optional canonical `observer_entity_id`;
- `observed_at`;
- independently recorded `recorded_at`;
- object-valued provenance;
- idempotency coordinates;
- deterministic payload fingerprint.

The subject is a canonical `reality.resources` row. A Task, card, queue item, maintenance row, Worker Day line, or operational encounter is not an observation subject surrogate.

### Admission

`reality.record_resource_observation_service_v1(...)`

Admission:

1. validates the exact active resource subject;
2. validates observation/provenance shape;
3. preserves observer and temporal coordinates;
4. computes the admitted semantic fingerprint;
5. replays the canonical receipt for the same idempotency key and same content;
6. fails if the same key is reused for different content;
7. inserts the source fact;
8. reads it back canonically before returning `admitted`.

The writer does not:

- mark a Task complete;
- create a Task;
- set readiness state;
- infer threshold crossing;
- infer safety;
- infer maintenance requirement;
- infer Venue readiness;
- resolve a Responsibility.

Those are downstream governed relations, if and only if their own basis warrants them.

### Read membrane

`reality.resolve_resource_observation_latest_v1(...)`

This read returns the latest admitted observation matching:

- exact resource;
- exact observation type;
- an `observed_at` upper bound;
- a `recorded_at` upper bound.

It deliberately returns `indeterminate / no_admitted_observation` when no source fact exists.

The resolver does not decide whether the observation is fresh enough or semantically sufficient for a particular relation. Freshness and sufficiency belong to the consuming governed relation.

## 4. Responsibility→resource applicability membrane

### Canonical store

`atlas.organization_responsibility_resource_applicability`

The relation points to:

- one exact `atlas.organization_responsibility_scopes.id`;
- one exact `reality.resources.id`;
- one exact nonblank `operation_key`;
- an effective interval;
- provenance and admission coordinates.

Using the exact Responsibility-scope row is deliberate.

The table does **not** duplicate:

- organization ID;
- Responsibility ID;
- `scope_kind`;
- polymorphic `scope_id`;
- scope relation kind.

Those remain owned by `atlas.organization_responsibility_scopes` and its parent Responsibility definition.

### Admission

`atlas.admit_organization_responsibility_resource_applicability_service_v1(...)`

Admission validates that:

- the exact Responsibility scope exists;
- the Responsibility belongs to the same Organization carried by that scope;
- the Organization and Responsibility are active at admission time;
- the resource exists and is active;
- the effective interval is valid;
- retries are idempotent;
- conflicting reuse of an idempotency key fails;
- two effective intervals for the same scope/resource/operation cannot overlap.

The admission path serializes competing writes for the same semantic relation before performing the overlap check.

Applicability means only:

> this exact institutional Responsibility scope is governed as relevant to this exact resource subject for this exact operation during this effective interval.

It does **not** mean:

- whoever carries the Responsibility owns the resource;
- whoever carries the Responsibility has general authority over the resource;
- the Person is assigned Work;
- an Execution Lease exists;
- the operation is currently needed;
- the operation is currently lawful for a particular actor;
- an operational encounter must be shown.

Those are separate relations.

## 5. Applicability resolution states

`atlas.resolve_organization_responsibility_resource_applicability_current_v1(...)`

The current resolver preserves three materially different states.

### `established_current`

Exactly one admitted relation covers the requested `as_of`.

### `established_not_current`

The exact applicability relation is known in source history, but none of its admitted effective intervals covers the requested `as_of`.

### `indeterminate`

Used when the source cannot warrant either current or not-current, including:

- malformed query;
- missing source identity;
- no applicability relation has ever been recorded;
- structurally impossible duplicate-current rows are found.

This is intentional:

```text
no applicability record
!=
proof that applicability is false
```

Missing governance remains unknown rather than silently becoming prohibition.

## 6. How this closes the Atlas architecture gap

The downstream Atlas proof can now target a source contract with the correct shape:

```text
canonical resource observation
→ physical-condition relation re-resolution
```

and separately:

```text
current institutional Responsibility
+
Responsibility→resource applicability
→ recipient support for this exact subject/operation
```

Then operational arbitration may combine:

```text
unresolved physical question
+
current Person-carried Responsibility
+
current applicability
→ clarification encounter
```

When a later canonical observation answers the physical question:

```text
physical question resolves
→ clarification encounter loses support
→ encounter disappears by re-derivation
```

No `done` state is required on the encounter.

## 7. Idempotency and correction boundary

The two admission functions establish replay identity for source facts/relations.

This tranche does **not** yet define a universal correction protocol.

Corrections must not be implemented by mutating operational projections. A later source tranche must distinguish at least:

- corrected/superseded observation testimony;
- ending or replacing an applicability interval;
- historical facts that remain real even when downstream interpretation changes.

Nothing here authorizes destructive history rewriting.

## 8. Behavioral proof

Rollback-only test:

`supabase/tests/20260928_governed_subject_observation_applicability_v1.sql`

The proof covers:

- valid observation admission;
- exact subject identity preservation;
- observed time separate from recorded time;
- same-key/same-content replay;
- same-key/different-content rejection;
- latest canonical readback;
- no cross-resource observation leakage;
- valid applicability admission;
- applicability replay;
- overlap rejection;
- current applicability resolution;
- absent applicability remains indeterminate;
- known historical applicability becomes established-not-current;
- no legacy `atlas.tasks` row is created as a side effect when that compatibility table exists.

The test is transaction-wrapped and ends with `rollback`.

## 9. Security boundary

The new tables are RLS-enabled and direct public/authenticated access is revoked.

The source admission/read functions are service membranes. Application-facing authorization should continue to happen in the governed application/service layer rather than by granting clients direct canonical-write access.

This branch has not been applied to production.

## 10. Non-goals

This tranche does not establish:

- a generic Observation ontology for every domain;
- a universal Responsibility→all-subjects graph;
- a Task replacement table;
- a generic transition engine;
- resource-condition semantics;
- freshness rules;
- execution authority;
- Work assignment;
- UI routing;
- Venue readiness;
- grounds-specific vocabulary in the universal kernel.

It adds only the two missing source facts required by the governed-reality proofs.

## 11. Governing findings

> **An observation is source evidence about a canonical subject, not completion state for an operational carrier.**

> **The applicability of an institutional Responsibility to a physical/resource subject is governed reality in its own right; it cannot be inferred from names, shared ownership, or organizational proximity.**

> **Absence of recorded applicability is epistemic absence, not automatic prohibition.**
