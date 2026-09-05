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

The executable kernel should carry a machine-readable **source-adapter activation boundary** rather than relying on deploy folklore.

Coverage answers:

> From what canonical point does this shared source adapter guarantee Money Collection obligations for every positive-value receivable transaction of this source kind?

Because Atlas installs the source adapter in the shared database for all organizations at once, v1 coverage is **global to the adapter contract**, not repeated per organization.

Minimum logical identity:

```text
source_domain
+ source_kind
+ obligation_kind
+ adapter_contract/version
```

Minimum evidence:

- activation timestamp;
- adapter contract/version;
- migration/release provenance;
- optional source-specific lower-bound identity if timestamp ordering alone is insufficient;
- status such as `active` or `retired`;
- metadata explaining the pre-boundary truth limitation.

The source transaction still resolves its own organization custody. A global coverage row does not make money cross organizations and does not replace organization identity on obligations, receipts, collection attempts, or connected sources.

### Why coverage is not per organization in v1

A per-organization activation record would create a false setup obligation for every future company even though the same canonical Registration or Flower adapter is already installed globally.

New organizations should inherit reliable forward money truth automatically when they use an already-active source adapter.

If Atlas later introduces a genuinely organization-specific adapter rollout, that is a different scope model and should be represented explicitly rather than overloading v1’s global activation record.

Provider connection status is also unrelated to source coverage. An organization can be inside Money Collection coverage without Stripe connected because obligations may exist before collection and manual receipts are allowed.

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

source predates source-adapter activation
+ no obligation
  -> payment_truth_unknown_pre_kernel

source is inside source-adapter coverage
+ positive value
+ no obligation
  -> invariant_gap

source is inside source-adapter coverage
+ obligation exists
  -> derive open/partial/paid/etc. from Money Collection evidence
```

The `invariant_gap` state is an architecture/custody failure, not ordinary unpaid receivable truth.

## Community Registration coverage

Because production has zero Registration rows at this boundary, Community Registration can begin with complete v1 coverage.

The Registration adapter release should establish global coverage **before or atomically with** enabling the first paid Registration write path.

After activation, for every organization using that adapter:

- free offering / zero fee -> `payment_not_required`, no obligation;
- positive fee -> exactly one `participation_fee` obligation;
- positive-fee Registration with no obligation -> `invariant_gap`.

The release must assert that production still has no legacy Registration/payment rows requiring reconciliation. If that assertion becomes false before release, the clean-cutover plan must abort.

The separately governed Community Registration lifecycle authority remains responsible for confirmation/cancellation/refund state. Coverage proves only that the money adapter is in force.

## Flower Sale coverage

Existing Flower Sales remain outside v1 canonical collection coverage unless separately reconciled from admissible evidence.

The Flower adapter activation point must be explicit and atomic with the current Sale-writer fence.

After activation:

- zero-total Sale -> `payment_not_required`, no receivable obligation required;
- positive Sale -> exactly one effective `sale_total` obligation at canonical Sale birth;
- positive covered Sale missing its obligation -> `invariant_gap`;
- cancellation is handled through the Flower-domain cancellation adapter and Money obligation transition evidence, not by deleting the obligation.

Pre-activation positive Sales with no obligation return:

```text
payment_truth_unknown_pre_kernel
```

not `unpaid`.

The current Flower design further requires `record_flower_sale_core_v1` to be fenced/retired so `record_flower_sale_core_v2` is the sole current Sale birth core carrying this postcondition.

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

No broad reconciliation UI or workflow is required to launch v1 if historical payment reporting is not yet needed.

## Source-domain invariant

Coverage cannot be guaranteed by an application route.

The postcondition belongs at the canonical domain command boundary:

```text
Community Registration birth command
  -> participation_fee obligation postcondition

Flower Sale current birth core (v2)
  -> sale_total obligation postcondition
```

The shared Money core remains provider-neutral. The domain adapter derives organization, source identity, amount, and currency from trusted source rows rather than accepting them from callers.

The Flower release must fence the obsolete service-role v1 Sale writer rather than introduce a generic trigger solely to preserve dual cores.

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

Only a source transaction inside coverage with a canonical obligation may produce ordinary derived states such as open, partially paid, paid, or reversed/refunded.

## Architecture truth catalog

The executable release should add a truth-authority entry for money-collection coverage.

Question:

> Is this source transaction inside canonical Money Collection coverage, and what may Atlas conclude if no obligation exists?

Canonical owner:

- global source-adapter activation evidence plus the source-specific obligation adapter.

Known competitors to reject:

- assuming every historical Sale/Registration is covered;
- treating missing obligation as unpaid;
- using fulfillment/cancellation status to infer payment history;
- tying coverage to whether a provider account is connected;
- app deployment time stored only in prose;
- per-organization setup flags for a globally installed adapter.

## Release assertions

The first executable releases should prove:

### Registration

1. no pre-cutover Registrations/payment rows require reconciliation;
2. global Registration adapter coverage exists before first positive-fee Registration is accepted;
3. every covered positive-fee Registration has exactly one obligation;
4. zero-fee Registrations create none;
5. a newly onboarded organization automatically receives the same source-adapter coverage without a per-company activation write.

### Flower

6. existing five Sales remain explicitly outside canonical money coverage unless reconciled;
7. no historical Sale is backfilled as unpaid or paid without evidence;
8. global Flower Sale adapter coverage is established atomically with the v1-writer fence/v2 obligation postcondition;
9. every covered positive Sale has exactly one sale-total obligation;
10. covered zero-total Sales are `payment_not_required`;
11. a post-boundary positive Sale without an obligation fails invariant checks rather than appearing as normal unpaid truth.

## Governing principle

**Coverage is itself truth.**

A system that knows a Sale occurred but does not know its historical payment state must say exactly that. The new Money Collection Kernel begins reliable forward truth at an explicit shared adapter boundary; it does not manufacture a past or require every company to re-enable an adapter that is already canonical.