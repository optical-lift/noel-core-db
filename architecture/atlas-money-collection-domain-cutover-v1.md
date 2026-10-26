# Atlas Money Collection Domain Cutover v1

## Purpose

This document pins the source-domain cutover around the Money Collection Kernel before executable schema work begins.

The important result of the production census is that **Community Registration has not yet accumulated live payment history**. Atlas can therefore replace its provisional domain-local payment clock before that clock becomes historical authority.

## Production census at the cutover boundary

At the time this contract was written, production contains:

- 1 Community Registration offering;
- 1 offering with a positive fee;
- 0 Community Registrations;
- 0 `community_registration_payments` rows.

The only Atlas function that currently reads/writes `community_registration_payments` as business truth is `submit_public_household_registration_v1`. The only trigger on that table is the generic `updated_at` trigger.

Therefore there is no historical paid/refunded/failed payment corpus that needs semantic reconstruction.

This is a **pre-history cutover**, not a legacy-data migration.

## Consequence

The first executable Money Collection Kernel release should not preserve `community_registration_payments` as a compatibility authority merely because the table already exists.

The preferred cutover is:

```text
old provisional path
positive offering fee
  -> community_registration_payments(status='pending')

becomes

canonical path
positive offering fee
  -> registration
  -> participation_fee money obligation
```

before any production Registration creates a domain-local payment row.

After the cutover, `community_registration_payments` must either:

1. be removed, if source/dependency checks prove nothing still requires it; or
2. be explicitly retired as non-current compatibility/history with no write path and no consumer treating it as effective payment truth.

It must not coexist indefinitely as an equal payment authority.

## Organization custody resolver

Both first-proof domains already resolve cleanly to the organization that owns the receivable.

```text
community_registration
  -> community_registration_offerings.farm_id
  -> farms.organization_id

flower_sale_order
  -> flower_sale_orders.farm_id
  -> farms.organization_id
```

`atlas.farms.organization_id` is foreign-keyed to `atlas.organizations`, and current farms all have organization and organization-unit custody established.

The Money Collection Kernel therefore does not need a new generic source-owner table for these proofs.

The source-domain adapter must resolve organization custody from the canonical source transaction and reject caller-supplied organization identity that does not match it.

## Community Registration source adapter

### Birth transaction

`submit_public_household_registration_v1` remains Registration-domain authority for:

- offering eligibility/open window;
- terms acceptance;
- registrant identity/contact fields;
- participant creation;
- duplicate registration rules;
- free-vs-paid registration semantics.

For a free offering:

```text
registration
  -> confirmed under existing registration rules
  -> no money obligation
```

For a paid offering:

```text
registration
  -> payment_pending registration state
  -> participation_fee obligation
```

The obligation amount/currency are copied as a durable receivable snapshot from the offering fee at the moment the Registration is accepted.

That snapshot is not permission for the Money kernel to later recalculate Registration price.

### Atomicity boundary

Registration creation and obligation creation are both Atlas/Postgres truth and should be one governed database transaction.

A paid Registration must not be left in this state:

```text
registration exists
+ fee > 0
+ no participation_fee obligation
```

Likewise retrying Registration submission must not create a second obligation.

The transaction should create/reuse the logical obligation keyed by:

```text
organization
+ community_registration
+ registration
+ registration_id
+ participation_fee
```

Provider checkout creation is deliberately outside this transaction because it is an external side effect.

### Confirmation transition

A provider webhook does not confirm Registration.

The Registration domain needs one governed, idempotent transition whose prerequisite is canonical money position:

```text
participation_fee obligation effective open amount = 0
+ obligation not voided/reopened by reversal evidence
-> Registration may transition payment_pending -> confirmed
```

The exact Registration transition command remains Registration-owned.

Its only money prerequisite is the provider-neutral effective obligation position.

If a receipt later reverses/refunds, Atlas must not silently decide Registration cancellation policy inside the Money kernel. The Registration adapter decides what its source state should become based on canonical money evidence and Registration policy.

## Flower Sale source adapter

Flower Sale is the foreign-shape proof and must remain structurally separate from Registration.

### Obligation creation point

The Sale total is already canonical commercial truth on `flower_sale_orders`.

The money obligation should therefore be created only after the canonical Sale exists, keyed by:

```text
organization
+ flower_commerce
+ flower_sale_order
+ sale_order_id
+ sale_total
```

Amount/currency come from:

- `flower_sale_orders.total_amount`
- `flower_sale_orders.currency`

The Money kernel does not inspect demand price history, buyer price books, Sale lines, tax calculation, or tip calculation to recreate the total.

### Sale creation transaction

Where the canonical Sale command is the source of a receivable, Sale creation and the sale-total obligation should become one governed Postgres transaction or one canonical postcondition that cannot silently omit the obligation.

This applies to both canonical Sale entry paths:

- Demand -> Sale conversion;
- legitimate direct Ready inventory -> Sale.

It does **not** mean changing Demand, reservation, or Harvest authorities.

The shared requirement is simply:

> every non-cancelled monetary Flower Sale that is meant to be receivable has exactly one effective sale-total obligation.

### Payment and fulfillment remain independent

Flower fulfillment must not become contingent on a generic Money-kernel mutation unless Flower-domain policy explicitly requires prepayment for that Sale/channel.

Likewise:

- fulfilled does not mean paid;
- paid does not mean fulfilled;
- Sale cancellation does not erase receipt history;
- refund/reversal does not return inventory;
- inventory release does not create a refund.

## Domain event hooks vs generic polymorphism

The first implementation should use narrow governed source adapters rather than a generic function that accepts arbitrary `source_domain`, `source_kind`, `source_id`, amount, and organization from the caller.

A generic caller-supplied obligation constructor would allow application code to fabricate receivables disconnected from canonical domain truth.

Safer pattern:

```text
Registration-owned command
  -> internal money-obligation core with verified source facts

Flower-Sale-owned command
  -> internal money-obligation core with verified source facts
```

The shared core owns the generic obligation invariants, while each adapter proves that the source transaction is real and resolves its own amount/currency/organization.

Only after multiple domains prove a safe registry/adapter pattern should Atlas expose a more generic source-binding API.

## Connected-source payment custody

For provider-backed collection, the obligation's organization and the selected `connected_sources.custodian_organization_id` must match.

Required provider source state:

```text
custodian_organization_id = obligation.organization_id
authorization_state = connected
revoked_at is null
capabilities prove money collection
```

The caller cannot override this by supplying another organization id.

This rule prevents one Atlas company's Stripe/Square/etc. connection from collecting another company's receivable.

## No global default payment account as authority

An application environment variable may identify credentials used to talk to a provider, but it must not become the business-level answer to:

> Whose payment account is this?

Organization custody lives in `connected_sources`.

A provider adapter may use deployment secrets beneath that seam, but provider-account identity and authorization must reconcile to the connected source before collection authority exists.

## Clean-cutover acceptance tests

Before the first paid Registration is allowed through the new path, tests must prove:

1. paid Registration atomically creates exactly one participation-fee obligation;
2. free Registration creates no obligation;
3. retry does not create a duplicate Registration obligation;
4. the old `community_registration_payments` write is absent;
5. no current consumer reads `community_registration_payments.status` as payment truth;
6. checkout creation cannot confirm Registration;
7. receipt+allocation yielding zero open balance can satisfy the Registration-owned confirmation prerequisite;
8. refund/reversal cannot directly cancel or mutate Registration without its domain transition;
9. caller-supplied organization/provider custody cannot cross organization boundaries.

Before the Money Collection Kernel is called reusable, Flower proof tests must additionally prove:

10. Demand -> Sale creates/reuses one sale-total obligation without changing Demand/Allocation lineage;
11. direct canonical Ready -> Sale creates/reuses the same kind of Sale obligation;
12. Flower price is copied from canonical Sale total, never recomputed by Money core;
13. manual and provider-backed receipts converge on the same paid/open position;
14. Flower fulfillment and payment remain independently observable;
15. refund/reversal changes money position without returning inventory or rewriting Sale provenance.

## Release gate

Because production has zero Registration/payment rows at this boundary, the safest release order is:

```text
1. install Money kernel schema + source adapters
2. cut submit_public_household_registration_v1 to obligation creation
3. prove no community_registration_payments rows were created in the interval
4. retire/remove old payment-table authority
5. add provider adapter/checkout/webhook
6. enable first paid public Registration
7. prove Flower Sale as second domain
```

If production acquires a `community_registration_payments` row before this cutover lands, this pre-history assumption becomes false and the migration must stop for explicit reconciliation rather than guessing.

That condition should be an executable migration assertion, not a comment.
