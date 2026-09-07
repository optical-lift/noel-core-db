# Atlas Organization Ledger v1

## Purpose

Establish the generic institutional projection beneath the active Organization Atlas selected by Product Map decision `PMD-018`.

The governing product distinction is:

> **Personal Atlas compresses reality toward the human. Organization Atlas exposes institution-owned movement for accountability.**

The Organization Ledger answers:

> **What moved through this institution, and does Atlas know where it now belongs?**

This tranche is intentionally a projection/read-model proof. It does **not** create a universal canonical business-event authority, replace domain-owned truth, or deploy a new production surface.

## Governing sequence

```text
source-domain canonical truth / authorized source observation
        ↓
governed domain transition / admitted meaningful observation
        ↓
durable semantic movement identity + typed subject/provenance links
        ↓
Organization Ledger projection
        ↓
authorized organization-wide or operating-unit-bounded read
        ↓
source-owned drill-through / command when action is needed
```

A Ledger entry is admitted because it represents meaningful institutional movement, not because a PostgreSQL row changed.

## What this is not

The Organization Ledger is not:

- a second canonical database;
- a universal event-sourcing store for all Atlas truth;
- an audit log of UI clicks;
- the Personal Today surface;
- the Principal Clock;
- the Worker Day commitment;
- a task inbox;
- a fixed KPI dashboard;
- the Communication Ledger;
- the Commitment Ledger;
- a renamed version of the existing farm Journal.

## Existing backend reality discovered September 5, 2026

Atlas already contains three nearby but distinct historical structures.

### 1. Communication Ledger

`atlas.communication_events` and related custody tables preserve person-owned raw communication evidence. The Communication Ledger architecture explicitly forbids interpreting that custody layer directly into task, CRM, payment, Company Work, inventory, or other governing truth.

It is source custody, not institutional chronology.

### 2. Commitment Ledger

`atlas.commitment_plans`, generations, items, and events preserve immutable history of what Atlas committed to a human or organization plan.

It is commitment history, not all institutional movement.

### 3. Legacy Journal

`atlas.journal_event_index` is the closest existing precursor to the Organization Ledger.

It already carries:

- `organization_id`;
- occurrence date/time;
- source kind/id/event;
- actor and assigned user pointers;
- title/detail;
- visibility scope;
- importance;
- payload;
- provenance;
- generic many-to-many subject links through `atlas.journal_event_subjects`.

Live data already contains thousands of task, field, crop-cycle, rhythm, observation, and production movements.

However the current Journal is structurally farm-first:

- `farm_id` is mandatory;
- event identity is unique inside a farm;
- event kinds are a fixed farm-oriented check constraint;
- visibility rules call farm owner/manager/member helpers;
- `journal_day_v1()` begins from a farm membership;
- `workflow_events` are themselves farm-scoped;
- `index_workflow_event_v1()` classifies task/field/object/crop/maintenance events with farm-specific semantics.

Therefore the current Journal must not be promoted in place to universal Organization authority.

## Selected succession direction

The safe path is:

1. Keep the existing Journal live as a legacy farm projection/adapter.
2. Add a generic Organization Ledger projection beside it.
3. Preserve meaningful legacy Journal history by adapting qualifying Journal entries into the generic projection without making Journal the new truth owner.
4. Allow new domain-owned transitions to publish/admit Ledger movements through narrow governed adapters.
5. Retire/succeed the old Journal only after all live readers/writers are migrated and continuity is proven.

This is a Succession + Continuity problem, not a rename.

## Projection contract

The proof model uses two generic structures:

### `atlas.organization_ledger_entries`

A role-safe projection row for one meaningful institutional movement.

Conceptual fields:

- Organization custody;
- optional Organization Unit lens;
- durable organization-scoped event key;
- source domain;
- semantic type;
- source event key/reference;
- occurrence time;
- Atlas establishment time;
- role-safe title/detail;
- truth status;
- designation status;
- payload/provenance/correlation metadata;
- monotonic projection revision;
- creation/update timestamps.

The proof intentionally does not require `farm_id` and does not use a universal farm event enum.

### `atlas.organization_ledger_subjects`

Generic typed relationships from a Ledger entry to source-domain subjects.

Fields mirror the useful generic shape already proven by `atlas.journal_event_subjects`:

- entry;
- subject domain;
- subject kind;
- subject id;
- relation kind;
- provenance;
- metadata.

Subject links do not create ownership or causation merely because they exist.

## Designation

A Ledger movement must be institutionally intelligible without inventing false purpose.

The shared orientation state is:

- `designated` — Atlas can point to the lawful current relationship/state that situates the movement;
- `unresolved` — a required destination/custody/responsibility/reconciliation relationship is not established;
- `conflict` — legitimate evidence/state disagrees;
- `closed` — the relevant lifecycle claim was lawfully discharged/released/closed.

These are projection-level orientation categories only. They do not replace source-domain state machines.

Examples:

- five stems remaining as Ready inventory is sufficiently designated even if no buyer has claimed them;
- seedlings ready with no established destination remain unresolved;
- a payment provider observation may be designated as `payment evidence received` while economic settlement remains unresolved;
- completed Company Work may be closed while its source-domain consequence remains historically inspectable.

## Truth status

V1 proof supports a small projection-safe vocabulary:

- `established`;
- `observed`;
- `inferred`;
- `disputed`;
- `unresolved`.

This does not grant inference authority. It only prevents the Ledger from presenting every line as equally established canonical truth.

## Event identity and replay

Ledger identity must be durable and replay-safe.

V1 proof uses:

`(organization_id, event_key)`

as the stable projection identity and a monotonic `revision` assigned by a sequence whenever the projection entry materially changes.

A later canonical semantic-event contract may provide stronger event IDs/cursors. The Ledger should consume that contract when governed rather than preserving a parallel identity system forever.

## Occurrence time versus establishment time

The projection stores both:

- `occurred_at` — when the source/domain event occurred, if known;
- `established_at` — when Atlas established/admitted the projection statement.

Do not substitute ingestion time for occurrence time merely to simplify ordering.

## Authorization boundary

The proof begins conservatively.

- Direct `anon` / `authenticated` table mutation remains revoked.
- RLS is enabled as defense in depth.
- Internal projection admission is service-side only.
- The first client read API is **owner-only** because current normalized Organization membership roles are only `owner`, `consultant`, and `member`; Atlas does not yet have a generic released manager-authority projection that would justify treating `consultant` or `member` as management.
- Later widening must consume actual Decision Authority / Application Permission / manager-scope contracts rather than role-name guesses.

This is deliberately narrower than final product intent.

## Incremental runtime

The proof read contract supports:

- a bounded occurrence-time window;
- ordered entries;
- a projection revision cursor;
- a `changes after revision` read for reconnect/Realtime reconciliation.

The persistent Atlas runtime should not reread the whole Organization after every movement.

## Legacy Journal adapter

A future adapter may copy qualifying **projection meaning**, not canonical ownership, from `journal_event_index` into Organization Ledger entries.

Important rules:

- the legacy Journal event ID/key remains provenance;
- generic `journal_event_subjects` should be preserved as typed subject links where legitimate;
- farm visibility labels must be translated through explicit authorization policy, not copied as universal Organization roles;
- farm event kinds may become source-domain semantic types without expanding the generic Ledger into a farm enum;
- unresolved designation remains unresolved; the adapter may not invent a goal/custody relation from title text alone.

## First vertical slice — Production → Work → Worker → Production

The current database already proves important pieces but still contains a farm-specific authoring seam.

### Existing source-domain behavior

`atlas.reconcile_production_capacity_work_v1()`:

- detects a transplant-ready production lot;
- consumes confirmed bed-capacity/bed-assignment truth;
- derives bed-preparation work;
- currently resolves the worker through legacy `farm_memberships` / `worker_key='anna'` and authors a legacy planned occurrence/task.

### Existing Company Work convergence

The shared Company Work kernel already establishes:

- `work_requirements`;
- `work_items`;
- requirement links;
- `work_allocations`;
- work relations;
- time contracts;
- planning conflicts.

The current transitional convergence already enforces that Company Work is durable organization truth, Allocation is responsibility truth, and legacy tasks are execution carriers rather than work identity.

### Target slice

The target is:

```text
Production readiness / bed assignment
→ source-owned production requirement
→ Company Work requirement + work item
→ Responsibility / Allocation
→ institutional time contract
→ Worker planning / Worker Day projection
→ worker result
→ Company Work completion/result
→ Production reconciles prerequisite
→ every meaningful transition appears in Organization Ledger
```

The source Production domain should eventually materialize Company Work directly rather than needing a farm-task adoption step.

## Second vertical slice — Harvest → Commerce → Fulfillment → Money

The shared Commerce map already separates:

`Harvest → Ready inventory → Demand/commitment → Sale → fulfillment → money evidence/reconciliation`.

The Organization Ledger must preserve those distinctions.

In particular:

- Harvest result is not Ready inventory;
- Ready inventory is not available/unclaimed supply;
- allocation/custody is not Sale;
- Sale is not fulfillment;
- provider observation is not payment truth;
- payment evidence is not settled economic truth until Money authority establishes it.

## Genericity pressure test

The proof must work against `Atlas Reference Company` without requiring farm-specific fields.

A valid generic fixture can use abstract institutional subjects such as:

- resource lot becomes ready;
- destination prerequisite becomes required;
- work is allocated;
- work result satisfies prerequisite;
- customer commitment reserves resource;
- custody transfers for fulfillment;
- payment observation arrives;
- economic reconciliation closes the obligation.

If the projection kernel requires crop, stem, bed, florist, farm, or farmhand fields, it has failed.

## Promotion gates

Do not materialize a production migration until the rollback proof verifies:

1. no `farm_id` dependency;
2. Organization-scoped replay-safe identity;
3. typed subject links;
4. occurrence and establishment time separation;
5. explicit unresolved/conflict representation;
6. monotonic incremental revision;
7. fail-closed owner-only read contract;
8. direct client writes revoked;
9. RLS enabled;
10. rollback leaves no proof objects behind.

Before production release also require:

- generated repository migration identity through the governed Supabase migration workflow;
- security/advisor review;
- exact legacy Journal adapter/cutover plan;
- first domain adapter contract;
- persistent-runtime read contract;
- Product Map / ICM alignment.
