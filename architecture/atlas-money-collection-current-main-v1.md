# Atlas Money Collection — current-main foundation v1

## Status

Package 5 executable database candidate built from exact `noel-core-db/main` base `d10b7efed09e3bd24d10a96ce650249a74a06dee`.

Canonical migration identity was minted with pinned Supabase CLI v2.116.0:

`20260915215140_atlas_money_collection_current_main_v1.sql`

This candidate has not been merged or released to production.

## Purpose

Establish the smallest current-main Money authority Atlas can support truthfully after the Person/Ledger reconstruction, institutional-custody cutover, universal commerce work, Employee Atlas, Mailroom, and Package 4 Flower commercial runtime.

The governing sequence is:

```text
source transaction
  -> monetary obligation
  -> received-money evidence
  -> Money receipt
  -> receipt allocation
  -> effective paid/open position
```

The critical separations remain:

```text
price / fee
!= monetary obligation
!= collection attempt
!= receipt
!= receipt allocation
!= refund / reversal
!= fulfillment
!= bank settlement
```

This tranche does not introduce a generic accounting ledger, Stripe schema, bank-settlement model, collection-attempt/provider-event rail, or reporting layer. Those belong to later Package 5 slices.

## Relationship to superseded PR #304

PR #304 established the right constitutional boundary but was built against September 1 schema and cannot be replayed wholesale.

The reusable decisions retained here are:

- source domains own transaction existence and price;
- Money owns obligations, receipts, allocations, reversals, and derived paid/open position;
- provider evidence does not become canonical Money merely by existing;
- fulfillment and payment are independent;
- refunds preserve the historical fact that money was received;
- idempotency is required at source/evidence boundaries.

The following old implementation assumptions are explicitly superseded:

- Community Registration is no longer an empty clean-cutover domain;
- existing Registration payment evidence must be reconciled, not rejected;
- current Flower Sale v2 already exists for Ready/concurrency hardening and must not be overwritten by the old Money wrapper of the same name;
- universal commerce was backfilled after #304, but current Flower/Registration writers do not universally maintain those extension rows;
- current Atlas has first-class Ledger identity and effective institutional custody;
- Waiting Room is explicit archived/test custody and must never become real Money merely because a Sale row exists.

## Ledger custody

Canonical Money is Ledger-custodied.

Every Money obligation and receipt records:

- `ledger_id` — the governing institutional reality boundary;
- `organization_id` — the participating institution in whose context the source transaction exists.

For the current farm-scoped proof domains, `money_source_farm_custody_v1` resolves:

```text
farm physical Organization
  -> effective institutional custody
  -> canonical Organization
  -> explicit effective Ledger when adjudicated
     or active compatibility-primary Ledger for the canonical Organization
```

Archived or unresolved source custody does not establish a canonical Money address.

This is deliberate. A real source event may exist while a proposed Money consequence fails to take hold because the governing custody cannot be established.

## Test evidence boundary

The Package 4 Waiting Room proof exposed why Money cannot depend on downstream `testMode` metadata alone: the proof Sale is clearly test-scoped by its farm/custody and idempotency evidence, but the final Sale metadata does not itself carry `testMode=true`.

Waiting Room Farm and its Organization Unit are already adjudicated `archived` with basis `waiting_room_test_scope` and no canonical Organization/Ledger target.

Therefore the stronger rule is:

> A source transaction may establish canonical Money only when its source reality resolves to current canonical Ledger custody.

The production-shaped validation fixture proves an archived `$12.34` Flower Sale creates zero Money obligations while an otherwise comparable canonical Sale does create one.

## Canonical objects

### Money obligation

`atlas.money_obligations`

An immutable receivable snapshot produced by a source transaction.

Identity:

```text
Ledger
+ source domain
+ source kind
+ source id
+ obligation kind
```

The obligation stores amount/currency only as the collection snapshot. It does not become the source domain's pricing authority.

### Obligation void event

`atlas.money_obligation_void_events`

Append-only evidence that an unpaid obligation no longer applies. A paid or partially paid obligation cannot be erased by voiding it; receipt/reversal history must resolve that situation.

### Money receipt

`atlas.money_receipts`

An immutable statement that money was received according to admitted evidence.

A receipt is not provider authorization, fulfillment, or bank settlement.

The first executable source adapter admits already-observed Community Registration payment evidence. Provider-connected ingestion remains a later tranche.

### Receipt allocation

`atlas.money_receipt_allocations`

Applies some or all of a receipt to an obligation. This is distinct from Flower inventory allocation.

### Receipt reversal

`atlas.money_receipt_reversals`

Preserves refund/reversal evidence without rewriting the original receipt. An optional allocation link identifies which obligation position reopens.

### Derived position

`atlas.money_receipt_position_v1`

and

`atlas.money_obligation_position_v1`

These views derive current position from immutable history. Mutable birth rows do not become a competing state clock.

Representative obligation states in this tranche are:

- `open`
- `partially_paid`
- `paid`
- `reopened`
- `voided`

## Flower integration

Current Flower Sale truth remains authoritative in `atlas.flower_sale_orders` and current `record_flower_sale_core_v2` remains untouched.

A new AFTER INSERT adapter observes the committed Sale and establishes a `sale_total` obligation when:

- Sale total is positive; and
- the Sale's farm resolves to canonical Organization/Ledger custody.

This means all current Sale writers—including direct Sale and Demand→Sale—share the same Money consequence without a second Flower writer transition.

Zero-dollar complimentary Sales create no receivable.

Archived/noncanonical test Sales create no canonical Money obligation.

Flower cancellation may void only an unpaid obligation. Cancellation after receipt does not erase Money history and does not itself create a refund.

## Community Registration integration

Community Registration is no longer a clean slate.

Current production contains Registration rows and historical payment evidence, plus universal commercial backfill links.

The Registration adapter therefore:

1. prefers an existing immutable universal commercial-order snapshot when one already exists;
2. otherwise snapshots the offering fee/currency at Registration birth;
3. creates no obligation for free Registration;
4. preserves the existing Registration writer rather than replacing it.

The obligation itself is the Money collection snapshot, so this tranche does not create a second Registration fee-snapshot subsystem.

### Existing Registration payment evidence

Current Registration payment rows already contain admitted historical evidence, including provider identifiers. Some were later bridged into append-only `commercial_payments`, but no live Stripe Connected Source exists for those historical observations.

The migration therefore does **not** invent retroactive provider connection custody.

For a paid Registration payment row:

```text
Registration payment evidence
  -> Money receipt
  -> receipt allocation
  -> paid Money position
```

Provider/commercial-payment identifiers remain provenance metadata.

A full legacy refund may create reversal evidence. If append-only universal commercial payment events contain explicit negative refund/chargeback/adjustment amounts, those amounts are stronger evidence. A `partially_refunded` label alone is not enough to invent a refund amount.

## Universal commerce boundary

Universal commerce is useful evidence, but it is not treated as the universal forward writer in this tranche.

The September universal-commerce migration backfilled existing Flower Sales and Registrations. Later Package 4 Flower Sales are not automatically mirrored into `commercial_orders` by the current writer path.

Therefore source adapters read the strongest current source truth per domain:

- Flower: governed Flower Sale + farm custody;
- Registration: Registration + existing commercial-order snapshot when available, otherwise offering fee at Registration birth.

A later convergence tranche may make universal commerce a maintained forward projection, but Package 5 does not fabricate that condition retroactively.

## Provider boundary

This migration deliberately exposes **no browser or service-role Money mutation API**.

Canonical Money tables are RLS-enabled and direct access is revoked from `anon`, `authenticated`, and `service_role`.

Internal mutation functions are likewise non-executable by those roles. They exist for database-owned source adapters and disposable validation only.

The only browser surface added here is an authenticated read:

`public.money_positions_self_api_v1(ledger_id)`

It delegates to an internal read that requires current Principal root authority over the requested Ledger.

Future provider work must add an explicit governed command membrane after Financial Reality/provider custody is reconciled. It must not open these internal cores directly.

## Backfill semantics

The migration installs source adapters first, then backfills existing source truth idempotently.

Expected production consequences from the current audit are:

- positive canonical Elm Flower Sales become open Money obligations;
- zero-dollar complimentary Flower Sales do not;
- the archived Waiting Room Package 4 test Sale does not;
- the two existing paid Registrations become obligations plus receipts/allocations;
- no historical provider connection is manufactured.

The production-schema clone fixture independently proves the same shape with synthetic records before any production release is considered.

## Security boundary

- no direct browser reads of canonical Money tables;
- no direct service-role mutation of Money tables;
- no browser/service execution of internal mutation cores;
- append-only mutation guards reject UPDATE/DELETE;
- browser read requires signed-in current Principal + Ledger authority;
- source-domain writers remain source-domain authority;
- Package 4 Flower v2 is explicitly verified to remain unchanged.

## Validation requirements

The exact candidate must prove on a disposable production-schema clone:

1. canonical positive Flower Sale -> one open Money obligation;
2. archived test Flower Sale -> zero Money obligations;
3. paid Registration -> one obligation + one receipt + one allocation -> `paid` position;
4. source replay is idempotent;
5. append-only rows reject mutation;
6. reversal reopens the paid position without erasing receipt history;
7. a receipt-bearing obligation cannot be voided;
8. current Flower Sale v2 remains the Package 4 availability/concurrency writer;
9. internal Money mutation remains unavailable to authenticated/service roles;
10. authenticated browser read is available while anonymous read is denied;
11. source-to-Money triggers exist on Flower Sale, Registration, and Registration payment paths;
12. schema lint/advisors introduce no unreviewed blocker.

## Deferred Package 5 slices

This tranche does not yet complete Package 5.

Still required:

- provider-neutral collection attempts;
- provider object/event admission through current Connected Sources;
- Financial Reality / Economic Event reconciliation from #312 semantics replayed against current main;
- organization-owned Spend from #464 semantics replayed against current main;
- reporting contract from #466 semantics;
- provider adapters such as Stripe/bank/accounting evidence;
- Atlas Money/Spend notebook surfaces beyond the first position read;
- production human proof and retirement of superseded Package 5 branches.

## Release boundary

Do not merge or release merely because source exists.

Required order:

```text
current-main candidate
-> Database Custody CI
-> production-schema clone validation + advisors
-> exact-source review
-> merge to canonical main
-> separately governed production database release
-> production verification
```

No production DDL is authorized by this architecture document.
