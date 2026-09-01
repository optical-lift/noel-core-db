# Atlas Community Registration Lifecycle v1

## Purpose

Community Registration needs its own governed lifecycle authority before payment satisfaction can lawfully change a registration.

The Money Collection Kernel may establish that a monetary obligation is paid. It must not own whether a registration is confirmed, cancelled, refunded, or otherwise complete.

The governing sequence is:

```text
registration source truth
  -> registration lifecycle authority
  -> effective registration position

money position
  -> registration-domain payment-satisfaction adapter
  -> registration lifecycle authority
```

A payment provider never mutates registration state directly.

## Current production reality — 2026-09-01

Production currently contains:

- one open paid offering for `elm_family_ultimate_fall_2026`;
- offering fee `60.00 USD`;
- zero canonical registrations for that offering;
- zero `community_registration_payments` rows.

The only production function that currently references `atlas.community_registrations` is:

```text
atlas.submit_public_household_registration_v1(...)
```

That function creates the registration and participants. It writes the registration birth state directly as either:

- `confirmed` for a free offering; or
- `payment_pending` for a paid offering.

No governed function currently owns later transitions to:

- `confirmed` after payment;
- `cancelled`;
- `refunded`.

The table has mutable lifecycle columns (`status`, `confirmed_at`, `cancelled_at`), but there is no canonical command membrane around those mutations.

This is a domain-authority gap independent of Stripe and independent of the Money Collection Kernel.

## Lifecycle rule

Registration lifecycle truth must be domain-owned and event-advanced.

The birth registration row remains source evidence for what was accepted at submission. Later lifecycle advancement should be append-only rather than arbitrary direct updates.

Conceptually:

```text
community_registrations birth
+ registration lifecycle events
        |
        v
community registration effective position
```

Consumers must read effective position once lifecycle events exist; the birth `status` field must not become a competing current-state clock.

## Birth states

Version 1 preserves the existing legitimate birth distinction.

### Free offering

A free offering may be born `confirmed` when the registration command has already satisfied every registration-domain prerequisite.

No money obligation is created.

### Paid offering

A paid offering is born `payment_pending`.

Submission proves only:

- an accepted registration request;
- participant identity supplied to the registration domain;
- terms acceptance under the offering contract;
- a registration-derived monetary obligation is warranted.

It does not prove payment and it does not create confirmation.

## Canonical lifecycle transitions

Version 1 needs only transitions exercised by real current semantics.

### Payment-pending -> confirmed

This transition requires canonical Money Collection Kernel evidence that the registration's participation-fee obligation is effectively paid.

The registration command must verify that evidence itself through the governed money-position authority.

It must not accept caller-supplied `paid=true` or provider status as sufficient evidence.

The idempotent transition preserves at minimum:

- registration id;
- from/to lifecycle state;
- authority basis (`money_obligation_position` plus obligation id);
- effective time;
- source event/reference where useful;
- idempotency key;
- metadata/provenance.

### Open registration -> cancelled

Cancellation remains a registration-domain choice/authority.

Cancelling a paid registration does not erase receipt history. It may separately invoke or warrant a money refund/void policy adapter, but money reversal is not registration lifecycle truth.

### Confirmed -> refunded

If current product semantics require `refunded` as a registration state, that transition must require canonical refund/reversal evidence from the Money Collection Kernel plus whatever registration-domain policy is required.

A provider webhook cannot set this state directly.

Do not invent further lifecycle vocabulary until another real registration shape requires it.

## Effective position

The registration domain needs one effective-position read authority exposing at least:

- registration id;
- offering id;
- birth status as historical evidence;
- effective status;
- submitted time;
- effective confirmed time;
- effective cancelled/refunded time where applicable;
- lifecycle event/provenance responsible for current position;
- registration/money coverage indicators needed by downstream surfaces.

Once this exists, downstream registration readers must not reconstruct current state from `community_registrations.status` alone.

This is an instance of Atlas's broader effective-position rule:

```text
birth/source evidence != effective current position
```

## Money boundary

The Money Collection Kernel owns:

- participation-fee obligation;
- collection attempts;
- provider evidence;
- receipts;
- receipt allocation;
- refund/reversal evidence;
- effective paid/open position.

Community Registration owns:

- whether a registration exists;
- participant membership in that registration;
- terms acceptance;
- registration lifecycle;
- whether canonical payment satisfaction is sufficient to confirm;
- cancellation/refund registration semantics.

The adapter between them is narrow:

```text
registration participation-fee obligation position = paid
  -> governed registration confirmation command
```

That adapter should be idempotent and safe to invoke repeatedly after provider webhook retries.

## Intake boundary

The public intake path must be proven separately.

A signup received through email, an external form, screenshot, or other source does not become a canonical registration merely because an offering exists in Atlas.

If historical/operational signups need recovery, use a source-attributed reconstruction/intake command that preserves:

- where the signup evidence came from;
- when the signup was originally observed if known;
- when Atlas reconstructed it;
- terms evidence actually available;
- uncertainty rather than fabricated facts.

Do not claim that `submit_public_household_registration_v1` was used historically when it was not.

## Public submission adaptation

When the Money Collection Kernel is installed, the governed public submission command should atomically create:

```text
paid offering:
  registration birth(payment_pending)
  + participants
  + participation_fee money obligation

free offering:
  registration birth(confirmed)
  + participants
  + no money obligation
```

It should stop creating `community_registration_payments` rows.

The response may report the canonical registration position and amount due, but it must not expose provider-specific status as registration truth.

## Cancellation and money interaction

Before payment:

```text
registration cancellation
  -> registration lifecycle cancellation event
  -> money adapter may void the open participation-fee obligation
```

After payment:

```text
registration cancellation policy
  -> registration lifecycle event
  -> separate refund/reversal command when warranted
  -> money position changes from receipt/reversal evidence
  -> registration refunded transition only if domain policy/evidence warrants it
```

The order matters because the registration decision and the movement of money are separate facts.

## Access boundary

Lifecycle source/event tables should not become direct anonymous/authenticated mutation APIs.

Public callers may submit a registration through the narrow governed submission RPC.

Later lifecycle commands must derive or verify their own authority:

- payment-confirmation transition verifies canonical money position;
- human cancellation verifies the authorized organization/farm role or other explicit cancellation authority;
- refund transition verifies canonical reversal evidence and registration policy.

## Verification contract

Implementation is incomplete unless it proves:

1. free registration may be born confirmed with no money obligation;
2. paid registration is born payment-pending with exactly one participation-fee obligation;
3. submission alone cannot confirm a paid registration;
4. provider status cannot confirm a registration;
5. canonical paid money position can drive one idempotent confirmation transition;
6. repeated payment/webhook reconciliation cannot duplicate lifecycle events;
7. cancellation remains registration-owned;
8. cancellation does not erase money receipts;
9. refund/reversal evidence remains money-owned;
10. effective registration position, not the birth status, is the current read authority after transitions exist;
11. public intake creates canonical registration truth before checkout begins;
12. no lifecycle transition creates Flower, Worker, fulfillment, or unrelated domain truth.

## Foreign-shape discipline

This lifecycle contract is intentionally Community Registration-specific. It should not be generalized into a universal status engine merely because the Money Collection Kernel is generic.

The reusable layer is money collection. Registration lifecycle remains a domain adapter with its own lawful vocabulary.