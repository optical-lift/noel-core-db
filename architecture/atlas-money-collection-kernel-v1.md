# Atlas Money Collection Kernel v1

## Purpose

Atlas needs one reusable authority for **money that is owed, attempts to collect it, money actually received, and the application of received money back to what was owed**.

This is not a generic finance ledger and it is not a Stripe schema.

Commercial and operational domains keep authority over **why** money is owed and **how much their own committed transaction is worth**. The Money Collection Kernel begins only when a domain says that a durable monetary obligation exists.

```text
canonical domain transaction
  -> explicit monetary obligation
  -> optional provider-backed collection attempt
  -> provider evidence / manual receipt evidence
  -> durable receipt
  -> receipt allocation to obligation
  -> effective money position
  -> domain projection may react to paid / partially paid / unpaid truth
```

The kernel must work for Community Registration, Flower Sales, and later domains without making any of them depend on Stripe vocabulary.

## Current Atlas reality

The production schema currently contains three materially different kinds of monetary truth.

### 1. Planning and valuation truth

Examples include:

- `atlas.capital_requests.amount`
- `atlas.house_position_line_items.amount`
- flower price-book and demand-pricing rows

These are not collection truth and remain outside this kernel.

### 2. Domain commercial truth

Community Registration owns an offering fee through:

- `atlas.community_registration_offerings.fee_amount`
- `atlas.community_registration_offerings.fee_currency`

Flower commerce owns committed Sale value through:

- `atlas.flower_sale_orders.subtotal_amount`
- `atlas.flower_sale_orders.tax_amount`
- `atlas.flower_sale_orders.tip_amount`
- `atlas.flower_sale_orders.total_amount`
- `atlas.flower_sale_orders.currency`

Those values remain domain-owned. The kernel must not become the price authority for registrations or flower products.

### 3. Collection truth

Only Community Registration currently has a domain-local payment table:

`atlas.community_registration_payments`

It combines several concerns in one row:

- amount and currency;
- a mutable payment `status`;
- processor identity;
- external payment identity;
- paid/refunded timestamps;
- beneficiary metadata.

`submit_public_household_registration_v1` currently creates one pending row directly when the offering fee is positive. No reusable provider-agnostic collection authority exists around that row.

Flower Sale truth has no corresponding collection authority at all.

That asymmetry is the architectural gap this kernel closes.

## Existing authority to reuse: `connected_sources`

Atlas already has the correct custody root for external provider connections.

`atlas.connected_sources` supports exactly one custodian:

- a human user; or
- an organization.

It already preserves:

- provider key;
- provider account key;
- authorization state;
- granted scopes;
- capabilities;
- revocation state;
- provider/account uniqueness within the custodian.

Money providers therefore **must bind through an organization-owned `connected_sources` row**. A payment kernel must not introduce `stripe_accounts`, `square_accounts`, or equivalent parallel connection tables.

For money collection, the expected capability is conceptually:

```json
{
  "moneyCollection": true
}
```

Provider-specific capabilities may exist beneath that boundary, but the kernel depends only on the generic capability and organization custody.

## Constitutional separation

The following truths are independent and must remain independent:

```text
price / fee
!= monetary obligation
!= collection attempt
!= provider authorization
!= receipt
!= receipt allocation
!= fulfillment
!= domain completion
!= bank settlement
```

Examples:

- A Flower Sale can exist before payment is collected.
- A registration can be submitted before payment succeeds.
- A Stripe Checkout Session can exist without proving money was received.
- A provider event saying a payment succeeded does not itself alter the registration or Flower Sale row.
- A receipt can exist before all of it is allocated if a future domain permits split application.
- Fulfillment does not imply payment.
- Payment does not imply fulfillment.
- Provider capture does not claim that funds have settled to the organization's bank account.

## Canonical objects

Names below describe the intended authority shape. Exact migration names and final SQL signatures belong to implementation custody.

### 1. Money obligation

A **money obligation** says that a canonical source transaction has created an amount receivable by an organization.

Required identity:

```text
organization_id
+ source_domain
+ source_kind
+ source_id
+ obligation_kind
```

Representative source identities:

```text
community_registration / registration / <registration-id> / participation_fee
flower_commerce / flower_sale_order / <sale-id> / sale_total
```

An obligation stores the monetary snapshot needed to collect the claim:

- amount;
- currency;
- optional due date/time;
- organization custody;
- canonical source identity;
- idempotency identity;
- provenance metadata.

It does **not** own the source domain's product pricing logic.

The source transaction may be worth more than one obligation in future domains, so the source identity plus obligation kind—not source id alone—is the durable logical key.

### 2. Obligation transition evidence

The birth row is not a mutable current-state record.

If an obligation is voided, adjusted, written off, or otherwise advanced, Atlas records append-only transition evidence. Consumers read a canonical effective-position projection rather than re-reading the birth amount/state as current truth.

This follows the same system rule being established for other event-advanced Atlas records: **birth facts are history; effective position is current authority**.

Version 1 only needs transitions required by the first two proofs. Do not invent a full accounting vocabulary before a real domain needs it.

### 3. Collection attempt

A **collection attempt** is an attempt to satisfy one or more obligations.

It is not money received.

A provider-backed attempt references:

- the organization;
- the organization-owned `connected_sources.id` used for collection;
- provider-neutral attempt identity;
- requested amount/currency;
- idempotency key;
- source obligation linkage.

Provider-specific external identifiers are evidence attached to the attempt, not the attempt's canonical identity.

A collection attempt may progress through append-only provider/collection events such as requested, provider-created, authorized, failed, expired, cancelled, or succeeded. Exact event vocabulary is adapter-owned where the provider semantics differ.

### 4. Provider event custody

Webhook/API callbacks are external evidence. They do not become Atlas truth merely because a JSON payload was received.

A provider event admission must preserve at minimum:

- organization-owned connected source;
- provider event key;
- relevant provider object keys;
- event kind;
- provider occurrence timestamp where available;
- Atlas receipt timestamp;
- cryptographic/raw-payload digest or equivalent custody evidence;
- normalized evidence required by the adapter;
- idempotent uniqueness within the connected source/provider event namespace.

The application edge verifies the provider signature before invoking the governed database admission command.

The database then verifies that the event belongs to the expected organization-owned connected source and a known collection attempt or recoverable provider reference.

### 5. Money receipt

A **money receipt** is Atlas's durable statement that money was received according to admissible evidence.

A receipt may arise from:

- a verified provider event;
- an authorized manual cash/check recording path;
- a future imported accounting/bank source with its own custody rules.

Receipt identity must be idempotent against its evidence source.

A provider's `payment_intent`, `checkout_session`, transaction id, charge id, or equivalent must never serve as the only Atlas receipt identity without organization/source custody.

Receipt truth records:

- organization;
- amount;
- currency;
- received/captured time;
- evidence kind;
- optional connected source;
- provider/manual evidence reference;
- recorder where manual;
- provenance and idempotency.

A receipt is not bank settlement truth. Settlement can become a separate authority later if Atlas needs it.

### 6. Receipt allocation

A **receipt allocation** applies some amount of a receipt to a money obligation.

This is payment allocation, not inventory allocation.

The system must support:

- one receipt fully satisfying one obligation;
- partial payment;
- multiple receipts satisfying one obligation;
- future split-tender or one receipt covering multiple obligations without redesigning the kernel.

For the first two proof domains, the normal path will be one obligation and one receipt, but the schema must not encode that coincidence as a universal law.

Allocation invariants:

- currency must match unless an explicit future conversion authority exists;
- allocated amount cannot exceed the receipt's effective available amount;
- allocated amount cannot exceed the obligation's effective open amount unless the domain explicitly permits credit/overpayment;
- every allocation has durable source provenance;
- duplicate provider delivery cannot double-allocate money.

### 7. Reversal / refund evidence

Refunds must not mutate a historical receipt into 'never received'.

A refund or reversal is append-only evidence against a receipt and, where needed, its allocation. The effective money position derives net received/applied/open amounts from the original receipt plus reversal evidence.

This preserves the historical fact that money was received and later returned.

Version 1 needs only the smallest reversal vocabulary required to replace the existing Community Registration `refunded` / `partially_refunded` semantics honestly.

## Canonical effective-position authority

The kernel requires one canonical read authority—conceptually `money_obligation_position_v1`—that answers for each obligation:

- original obligated amount;
- effective obligated amount;
- gross received amount;
- reversed/refunded amount;
- net received amount;
- allocated amount;
- open amount;
- effective state.

Representative effective states are derived, not written as a competing mutable clock:

```text
open
partially_paid
paid
voided
refunded_or_reopened   # only if the real evidence requires this distinction
```

Do not freeze this enum prematurely. What matters constitutionally is that the state is derived from canonical obligation, receipt, allocation, and reversal evidence.

All domain adapters and app surfaces must read this effective authority rather than provider status or an immutable birth row.

## Domain integration contract

### Domain owns

The source domain owns:

- whether a commercial transaction exists;
- its products/services/participants;
- quantity;
- price calculation;
- tax/tip semantics where applicable;
- commercial cancellation rules;
- fulfillment;
- its own source completion semantics.

### Money kernel owns

The Money Collection Kernel owns:

- receivable obligation identity and amount snapshot;
- collection attempts;
- provider-event custody for collection;
- receipts;
- receipt allocation;
- refund/reversal evidence;
- effective paid/open position.

### Provider adapter owns

A Stripe/Square/etc. adapter owns:

- OAuth/account authorization mechanics;
- provider API requests;
- checkout/session creation;
- signature verification;
- translating provider events into the provider-neutral admission command.

It does not own:

- registration truth;
- Flower Sale truth;
- whether an obligation exists;
- whether fulfillment occurred;
- canonical paid/open state.

## First proof: Community Registration

Community Registration is the migration proof because it already contains a domain-local payment concept.

Current behavior:

```text
positive offering fee
  -> registration status = payment_pending
  -> direct community_registration_payments row(status='pending')
```

Target behavior:

```text
positive offering fee
  -> registration source truth
  -> money obligation(participation_fee)
  -> optional collection attempt
  -> receipt + allocation
  -> money obligation position = paid
  -> registration projection/transition may become confirmed
```

Critical constraints:

1. `community_registration_offerings` remains fee authority.
2. A free offering creates no money obligation and may still confirm immediately under registration rules.
3. A paid offering creates exactly one idempotent participation-fee obligation for the registration in v1.
4. Registration submission does not fabricate a successful payment.
5. Provider status is not copied into a second mutable domain-local payment clock.
6. Existing `community_registration_payments` data must be migrated or projected deliberately; it must not silently coexist as an equal current authority after cutover.
7. Registration confirmation after payment must come from canonical money position, not from a Stripe webhook directly updating the registration.

## Second proof: dynamically priced Flower Sale

Flower commerce is the required foreign-shape proof.

It is materially different from Community Registration:

| Dimension | Community Registration | Flower Sale |
| --- | --- | --- |
| Source price | offering fee | computed Sale total |
| Price shape | usually one fixed fee | buyer/product/dynamic line prices + tax/tip |
| Source object | registration | committed Sale |
| Fulfillment | participation/attendance domain | physical flower fulfillment |
| Typical collection | public checkout | checkout, invoice-like pay-later, cash/check possible |
| Domain completion | registration confirmed | Sale remains separate from fulfillment |

Target path:

```text
canonical flower_sale_order
  -> sale_total obligation
  -> collection attempt when appropriate
  -> receipt
  -> receipt allocation
  -> paid position
```

The obligation amount comes from the committed `flower_sale_orders.total_amount` / currency. The kernel never recalculates flower pricing.

This proof is mandatory before calling the abstraction reusable. If the schema needs Flower-specific columns to make the second proof work, the kernel boundary is wrong.

## Stripe binding

Stripe is the first provider adapter, not the kernel.

Expected custody:

```text
Atlas organization
  -> organization-owned connected_sources row
       provider_key = stripe
       authorization_state = connected
       capability.moneyCollection = true
  -> governed collection attempt
  -> Stripe Checkout / PaymentIntent reference
  -> signed Stripe webhook
  -> provider-event admission
  -> receipt / allocation
```

No registration or Flower table should contain a Stripe foreign key.

Provider references may live on provider-event/attempt evidence because they are evidence identifiers, not domain identity.

### Checkout creation

Checkout creation is an external side effect and cannot be made truly atomic with Postgres.

Therefore the safe sequence is:

1. create/reuse an idempotent Atlas collection attempt;
2. call Stripe with Atlas attempt/obligation identifiers in provider metadata and a deterministic idempotency key;
3. record/bind the returned provider reference idempotently;
4. allow the signed webhook to reconcile the attempt even if step 3 failed after Stripe succeeded.

This prevents an application crash between provider creation and database binding from creating an orphan payment that Atlas cannot recover.

### Webhook admission

The public webhook route must:

1. read the raw request body;
2. verify the Stripe signature using the correct organization/provider binding;
3. reject unverified payloads before state mutation;
4. invoke a service-role/internal governed provider-event admission command;
5. deduplicate on the Stripe event id within the connected-source custody root;
6. let database authority derive receipt/allocation truth.

A webhook handler must not directly set `community_registrations.status='confirmed'` or write Flower fulfillment truth.

## Manual money

The kernel must not make Stripe mandatory for cash/check/manual receipts.

A manual receipt command must require explicit organization-role authority and recorder identity. It creates receipt evidence directly, with no fake `connected_sources` provider required.

Manual receipt recording still allocates through the same canonical receipt-allocation rail, so cash, check, and Stripe converge before domain projections react.

## Beneficiary and organization custody

The current registration payment row includes `beneficiary_type` and `beneficiary_reference`. That should not become a free-form payment-provider routing primitive.

Version 1 should collect for the organization that owns the source transaction and the connected payment source. If a source domain needs revenue attribution to another internal beneficiary, preserve that as provenance/allocation metadata or a separate governed revenue-distribution authority—not by letting arbitrary beneficiary strings choose where Stripe money is routed.

Cross-organization marketplace payouts are explicitly out of scope for v1.

## Idempotency rules

Idempotency is required at every external/retry boundary:

- source transaction -> obligation;
- obligation -> collection attempt;
- attempt -> provider checkout/payment object binding;
- provider event admission;
- provider success -> receipt;
- receipt -> obligation allocation;
- refund/reversal event admission.

The same provider event delivered repeatedly must converge on the same effective money position.

A second application request with the same logical collection idempotency key must not create a second payable provider object.

## Cancellation interactions

Domain cancellation and payment cancellation are separate.

Before receipt:

- a domain cancellation may void/cancel the open money obligation according to the domain adapter;
- an outstanding collection attempt may be cancelled/expired where the provider supports it.

After receipt:

- domain cancellation does not erase the receipt;
- refund policy determines whether reversal/refund evidence is created;
- the source domain may move to its cancelled/refunded state only from its own governed transition based on canonical money evidence.

Flower inventory release/cancellation remains flower-domain authority. Money reversal must never silently return inventory.

## Access and security boundary

Canonical money tables should remain private to direct anonymous/authenticated table access unless a narrowly justified RLS design is introduced.

Authenticated application surfaces should use governed RPC/API seams that:

- derive user identity from `auth.uid()`;
- verify active organization/farm role where required;
- verify organization custody of the source transaction;
- verify organization custody and authorization of any connected source;
- prevent arbitrary source-domain/source-id injection from becoming a receivable;
- keep provider webhook mutation behind service/internal authority after signature verification.

`service_role` must never be exposed to the browser.

## Machine-readable truth authority

When the executable schema is added, the architecture truth-authority catalog should gain entries for at least:

### money_obligation_position

Question:

> What amount is currently owed for this canonical monetary obligation after valid adjustments, receipts, allocations, and reversals?

Canonical owner:

- the kernel's effective obligation-position projection/function.

Known competitors to reject:

- domain-local mutable payment status;
- provider checkout/payment status treated as Atlas paid truth;
- immutable obligation birth amount treated as current amount after later events.

### money_provider_custody

Question:

> Which external payment account is authorized to collect for this organization?

Canonical owner:

- organization-owned `atlas.connected_sources` with the money-collection capability and valid authorization state.

Known competitors to reject:

- Stripe account ids stored directly on registration/Sale/domain rows;
- environment-global Stripe account identity masquerading as organization custody.

## Migration / compatibility strategy

Do not big-bang every money-looking table.

Implementation order:

1. Add the provider-agnostic money obligation / collection attempt / provider evidence / receipt / allocation / reversal rails and effective-position authority.
2. Add organization-owned payment-provider binding through `connected_sources`.
3. Add Stripe authorization + checkout + signed webhook adapter without Stripe vocabulary entering domain schemas.
4. Adapt Community Registration:
   - new paid registrations use the kernel;
   - deliberately reconcile existing `community_registration_payments` rows;
   - retire that table as current authority or convert it to compatibility/history only.
5. Prove the same kernel with a dynamically priced Flower Sale.
6. Only after both proofs, promote shared APIs and wider domain adoption.

## Explicit non-goals for v1

Do not add, merely because payment work is underway:

- a general ledger;
- bank reconciliation;
- settlement/payout accounting;
- tax filing logic;
- invoicing/accounts-receivable aging beyond what a real proof requires;
- subscription billing;
- marketplace split payouts;
- foreign exchange;
- arbitrary revenue beneficiaries;
- inventory allocation changes;
- fulfillment automation;
- Worker tasks;
- Stripe-specific columns on domain tables.

## Acceptance tests for the architecture

The implementation is not complete until the following are proven.

### Community Registration proof

A paid registration can move through:

```text
registration submitted
-> obligation open
-> Stripe collection attempt
-> duplicate-safe signed webhook admission
-> receipt
-> allocation
-> money position paid
-> registration confirmation through its domain adapter
```

while no Stripe identifier becomes registration identity and duplicate webhook delivery does not duplicate receipts or allocations.

### Flower Sale proof

A dynamically priced Flower Sale can move through:

```text
Sale total established
-> sale-total obligation open
-> provider-backed or manual collection
-> receipt
-> allocation
-> money position paid
```

without changing:

- Sale pricing authority;
- Demand -> Sale lineage;
- inventory reservation authority;
- fulfillment authority.

### Failure proofs

The test suite must also prove:

- creating a checkout does not mark an obligation paid;
- unsigned/invalid webhooks cannot mutate money truth;
- a connected source belonging to another organization cannot collect the obligation;
- duplicate provider events are idempotent;
- partial receipts remain partially paid;
- refunds preserve original receipt history and reduce effective paid position;
- domain cancellation does not erase receipt history;
- a registration and Flower Sale can use the same kernel without source-specific columns in the kernel core.

## Governing principle

Atlas should be able to answer four questions independently and exactly:

1. **Why is money owed?** — canonical source domain.
2. **How much is owed now?** — Money Obligation effective position.
3. **What money was actually received or returned?** — Receipt and reversal evidence.
4. **Which obligation did that money satisfy?** — Receipt allocation.

The payment provider is evidence and transport around those questions, never the owner of them.
