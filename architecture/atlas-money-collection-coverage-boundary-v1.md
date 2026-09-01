# Atlas Money Collection Coverage Boundary v1

## Purpose

The Money Collection Kernel must distinguish three materially different meanings of “no money obligation exists for this source transaction”:

1. **payment not required** — for example, a zero-dollar Sale or free Registration;
2. **pre-kernel payment truth unknown** — the source transaction predates canonical collection coverage and Atlas has no admissible evidence to classify it as paid or unpaid;
3. **post-cutover invariant failure** — a covered, positive-value source transaction should have produced a money obligation but did not.

Those states must never collapse into one another.

## Production evidence forcing this boundary

Community Registration is still pre-history for payment:

- 1 offering exists;
- the offering has a positive fee;
- 0 registrations exist;
- 0 `community_registration_payments` rows exist.

Flower commerce is different. Production already contains five Flower Sales dated 2026-08-28 with aggregate recorded value of $80:

- two zero-dollar delivery Sales, both fulfilled;
- one $20 wholesale Sale, fulfilled;
- one $25 wholesale Sale, cancelled;
- one $35 Sale in the `other` channel, not cancelled and not fulfilled at census time.

There is no canonical collection/receipt ledger for those Sales.

Therefore none of the positive historical Sales may be automatically classified as:

- unpaid;
- paid;
- refunded;
- written off;
- still collectible.

Fulfillment is not payment evidence. Cancellation is not refund evidence. An uncancelled Sale is not unpaid evidence.

## Canonical coverage marker

The executable kernel should carry a machine-readable source-coverage boundary rather than relying on deploy folklore.

Conceptually, a coverage record answers:

> From what canonical point does Atlas guarantee that this source adapter emits Money Collection obligations for every positive-value receivable transaction?

Minimum identity:

```text
organization_id
+ source_domain
+ source_kind
+ obligation_kind
```

Minimum evidence:

- coverage/activation timestamp;
- adapter contract/version;
- migration/release provenance;
- optional source-specific lower-bound identity if timestamp ordering alone is not sufficient;
- status such as `active` or `retired`;
- metadata explaining the pre-boundary truth limitation.

The exact executable relation/function names belong to migration implementation custody.

## Why a coverage marker is necessary

Without a marker, a read such as:

```text
Flower Sale exists
+ no sale_total money obligation
```

is ambiguous forever.

After this boundary is installed, the effective money read can say exactly:

```text
source value = 0
  -> payment_not_required

source predates money coverage
+ no obligation
  -> payment_truth_unknown_pre_kernel

source is inside money coverage
+ positive value
+ no obligation
  -> invariant_gap

source is inside money coverage
+ obligation exists
  -> derive open/partial/paid/etc. from Money Collection evidence
```

The `invariant_gap` state should be treated as an architecture/custody failure, not displayed as ordinary unpaid receivable truth.

## Community Registration coverage

Because production has zero Registration rows at this boundary, Community Registration can begin with complete v1 coverage.

The Registration adapter release should establish coverage **before or atomically with** enabling the first paid Registration write path.

After activation:

- free offering / zero fee -> `payment_not_required`, no obligation;
- positive fee -> exactly one `participation_fee` obligation;
- positive-fee Registration with no obligation -> `invariant_gap`.

The migration must assert that production still has zero legacy `community_registration_payments` rows and zero registrations requiring reconciliation. If that assertion becomes false before release, the clean-cutover plan must abort.

## Flower Sale coverage

Existing Flower Sales remain outside v1 canonical collection coverage unless separately reconciled from admissible evidence.

The Flower adapter activation point must be explicit.

After activation:

- zero-total Sale -> `payment_not_required`, no receivable obligation required;
- positive noncancelled Sale -> exactly one effective `sale_total` obligation;
- positive Sale missing its obligation -> `invariant_gap`;
- cancellation is handled through the Flower-domain cancellation adapter and Money obligation transition evidence, not by deleting the obligation.

Pre-activation positive Sales with no obligation must return:

```text
payment_truth_unknown_pre_kernel
```

not `unpaid`.

## No heuristic backfill

The following are prohibited as automatic migration rules:

```text
fulfilled -> paid
cancelled -> refunded
uncancelled -> unpaid
old Sale -> paid
cash-looking channel -> paid
wholesale -> invoice outstanding
```

Those may be plausible business narratives, but they are not evidence preserved in Atlas.

A historical Sale can enter canonical Money Collection history only through an explicit reconciliation path that records the evidence basis and the authorized human/system making the determination.

## Historical reconciliation, if later needed

A future reconciliation command may permit an authorized Owner/Manager to classify a pre-kernel source using admissible evidence such as:

- documented cash/check receipt;
- external provider transaction evidence;
- accounting/bank import with established custody;
- explicit receivable confirmation.

That command should create canonical obligation/receipt/reversal evidence as appropriate while preserving metadata that the source was reconciled after the fact.

It must never silently rewrite the original Sale or pretend the evidence existed at Sale time.

No such broad reconciliation UI or workflow is required to launch v1 if historical payment reporting is not yet needed.

## Source-relation invariant versus wrapper invariant

Flower Sale coverage cannot be guaranteed merely by modifying `record_flower_sale_core_v2`.

Current production still contains both:

- `record_flower_sale_core_v2`, used by current governed Sale wrappers including Demand and prospect conversion;
- `record_flower_sale_core_v1`, which can independently insert `flower_sale_orders`.

Therefore the receivable postcondition must be enforced at the canonical Flower Sale domain boundary, not just one app route or one wrapper.

A narrow Flower-domain trigger or equally strong database invariant may call the internal Money obligation core after a canonical positive-value Sale birth row exists.

The trigger is a **source adapter**, not generic polymorphic money creation: it derives organization, source id, amount, and currency from the trusted Sale row and farm custody rather than accepting them from the caller.

This also means Demand -> Sale, direct Ready -> Sale, and prospect -> Sale can share the same money postcondition without changing their distinct lineage rules.

## Zero-dollar transactions

A zero-dollar source transaction is not a zero-dollar receivable that needs collection machinery.

For v1:

- free Registration: no money obligation;
- zero-total Flower Sale: no money obligation;
- effective money projection: `payment_not_required`.

Do not create zero-value collection attempts or receipts merely to make a status machine look complete.

## Read contract

A domain-neutral money-position reader should return coverage explicitly alongside financial position.

Conceptual fields:

```json
{
  "coverageState": "covered | pre_kernel_unknown | payment_not_required | invariant_gap",
  "sourceDomain": "...",
  "sourceKind": "...",
  "sourceId": "...",
  "obligationId": null,
  "effectiveState": null,
  "openAmount": null,
  "truthBoundary": {
    "absenceOfObligationDoesNotMeanUnpaid": true,
    "fulfillmentDoesNotProvePayment": true,
    "cancellationDoesNotProveRefund": true
  }
}
```

Only `covered` obligations may produce ordinary derived states such as open, partially paid, paid, or reversed/refunded.

## Architecture truth catalog

The executable release should add a truth-authority entry for money-collection coverage.

Question:

> Is this source transaction inside canonical Money Collection coverage, and what may Atlas conclude if no obligation exists?

Canonical owner:

- the source-coverage boundary plus the source-specific obligation adapter.

Known competitors to reject:

- assuming every Sale in the historical domain is covered;
- treating missing obligation as unpaid;
- using fulfillment/cancellation status to infer payment history;
- app deployment time stored only in prose.

## Release assertions

The first executable releases should prove:

### Registration

1. no pre-cutover Registrations/payment rows require reconciliation;
2. coverage marker exists before first positive-fee Registration is accepted;
3. every covered positive-fee Registration has exactly one obligation;
4. zero-fee Registrations create none.

### Flower

5. existing five Sales remain explicitly outside canonical money coverage unless reconciled;
6. no historical Sale is backfilled as unpaid or paid without evidence;
7. Flower coverage marker is established at adapter activation;
8. every covered positive Sale has exactly one sale-total obligation;
9. covered zero-total Sales are `payment_not_required`;
10. a post-boundary positive Sale without an obligation fails invariant checks rather than appearing as normal unpaid truth.

## Governing principle

**Coverage is itself truth.**

A system that knows a Sale occurred but does not know its historical payment state must say exactly that. The new Money Collection Kernel begins reliable forward truth at an explicit boundary; it does not manufacture a past to make the database look complete.
