# Atlas Money Collection Cutover v1

## Purpose

This note converts the Money Collection Kernel contract into a production cutover order without allowing Community Registration, a payment provider, or a legacy payment row to become a second money authority.

The governing principle is:

```text
canonical domain transaction
  -> canonical money obligation
  -> collection evidence
  -> receipt + allocation
  -> canonical money position
  -> domain-owned reaction
```

No provider callback may skip that chain.

## Production census — 2026-09-01

The current `noel-core` production schema establishes a narrow migration surface.

### Community Registration

`atlas.community_registration_offerings` contains the open paid offering:

```text
stable_key: elm_family_ultimate_fall_2026
fee: 60.00 USD
status: open
created: 2026-08-13
```

Its metadata still says the payment integration is not configured.

The canonical registration tables currently contain **zero registrations** for that offering.

The current submission authority is:

```text
atlas.submit_public_household_registration_v1(...)
```

It is executable by `anon`, `authenticated`, and `service_role` through its governed `SECURITY DEFINER` seam. For a positive offering fee it currently:

1. creates `community_registrations` with `status='payment_pending'`;
2. creates participants;
3. inserts one `community_registration_payments` row with `status='pending'`.

### Legacy payment table

`atlas.community_registration_payments` currently has:

- **zero rows**;
- no views depending on it;
- no RLS policies;
- RLS enabled;
- direct table privileges only for `postgres` and `service_role`;
- one generic `updated_at` trigger;
- one known business writer: `submit_public_household_registration_v1`.

No production function other than that submission function currently references the table.

This means there is no historical payment corpus to translate at cutover today.

It does **not** mean registration intake is complete. Operationally received registrations that are absent from `community_registrations` are outside the canonical registration rail and must be admitted separately from source evidence. Payment implementation must not paper over that intake gap.

## Cutover invariant

After the cutover begins, there must never be two writable current-money clocks.

In particular:

```text
community_registration_payments.status
```

must not coexist as an equal current authority beside the Money Collection Kernel.

Provider state is evidence.
Legacy payment state is legacy evidence.
Canonical paid/open truth comes only from the Money Collection Kernel effective-position authority.

## Gate 0 — canonicalize intake before payment automation

Before Stripe or any provider-backed checkout is attached to Community Registration, the public registration path must be proven to enter the canonical registration command.

Required proof:

```text
public registration submission
  -> submit_public_household_registration_v1 (or governed successor)
  -> community_registrations row
  -> participant rows
  -> exactly one participation-fee money obligation when fee > 0
```

An offering existing in the database is not proof that the public form uses it.

A signup arriving in email, a form provider, a screenshot, or another external source is evidence of a registration, not a canonical registration row. If Atlas needs to recover such records, use an explicit source-attributed intake/reconstruction command. Do not fabricate that the canonical public RPC was used historically.

Payment checkout must be created from a canonical obligation, never directly from raw form fields.

## Gate 1 — install the provider-agnostic money authority

The first executable migration should add only the smallest shared authority required by the two proof domains:

- money obligation birth;
- obligation transition evidence required by cancellation/voiding;
- collection attempt;
- connected-source/provider reference binding;
- provider event custody;
- money receipt;
- receipt allocation;
- refund/reversal evidence;
- effective obligation position.

The migration must reuse organization-owned `atlas.connected_sources` for provider custody.

No Stripe-specific foreign key belongs on registration or Flower Sale tables.

## Gate 2 — adapt Community Registration atomically

The paid-registration transaction must become:

```text
offering fee authority
  -> registration birth
  -> participation-fee obligation birth
```

in one database transaction.

For a free offering:

```text
registration birth
  -> no money obligation
  -> existing free-registration confirmation rule may apply
```

For a paid offering:

```text
registration birth(status = payment_pending under current domain vocabulary)
  -> exactly one obligation
  -> no fabricated receipt
  -> no fabricated provider attempt
```

The source identity should be deterministic enough to make retries converge on the same logical obligation:

```text
organization
+ community_registration
+ registration
+ registration_id
+ participation_fee
```

The amount/currency snapshot comes from the offering at registration creation. The Money Collection Kernel does not recalculate the offering fee later.

## Gate 3 — stop legacy payment writes

Once Gate 2 is live, `submit_public_household_registration_v1` must stop inserting new `community_registration_payments` rows.

Because the table is empty as of this census, the safest initial retirement is:

1. leave the table physically present for rollback/forensics;
2. remove it from every write path;
3. keep direct authenticated/anonymous access absent;
4. mark it deprecated in source custody;
5. add a guard if needed to prevent accidental new service-role writes;
6. do not create a compatibility projection unless a real reader is discovered.

Do not manufacture legacy rows from new obligations merely to preserve the old shape. That would recreate dual authority.

If a future pre-cutover legacy row appears before deployment, the release must stop and rerun the census. Non-empty legacy data requires an evidence-preserving translation plan before retirement.

## Gate 4 — provider collection

A provider-backed payment starts from a canonical obligation:

```text
money obligation
  -> idempotent collection attempt
  -> organization-owned connected_sources binding
  -> provider checkout/payment object
  -> signed provider event
  -> provider-event custody
  -> receipt
  -> receipt allocation
  -> effective obligation position
```

The public checkout edge does not choose the amount from request input. It loads the canonical obligation and provider custody, then asks the provider to collect that amount.

The provider object should carry opaque Atlas identifiers sufficient for crash recovery and webhook reconciliation, but those identifiers remain metadata/evidence at the provider boundary.

## Gate 5 — domain reaction, not webhook mutation

Community Registration may react when its obligation reaches canonical `paid` position.

The reaction must be a governed registration-domain command or adapter, for example conceptually:

```text
money position becomes paid
  -> registration payment-satisfaction adapter
  -> idempotent registration confirmation transition
```

The provider webhook must not directly set:

```text
community_registrations.status = confirmed
```

The registration domain owns whether payment satisfaction is sufficient for confirmation and preserves its own transition semantics.

Likewise, refund/reversal evidence may make the money position reopen or reverse, but the registration domain decides its resulting domain state through a governed reaction.

## Gate 6 — foreign-shape proof: Flower Sale

Do not call the kernel reusable after Community Registration alone.

The second proof is a dynamically priced canonical Flower Sale:

```text
flower_sale_orders.total_amount + currency
  -> sale_total money obligation
  -> optional provider/manual collection
  -> receipt + allocation
  -> effective paid/open position
```

The Flower adapter must not need registration vocabulary or Flower-specific columns in the shared kernel.

Flower fulfillment remains independent. A paid Flower Sale is not automatically fulfilled, and fulfillment does not imply paid.

Sale cancellation does not erase a historical receipt. Any refund/reversal follows money authority, while inventory release remains Flower authority.

## Gate 7 — only then bind Stripe broadly

Stripe is the first provider proof, not the reason the kernel exists.

The Stripe application layer may own:

- organization authorization/connection flow;
- Checkout/PaymentIntent API calls;
- Stripe idempotency keys;
- raw-body signature verification;
- provider event normalization.

It may not own:

- registration fee truth;
- Flower Sale amount truth;
- paid/open truth;
- registration confirmation;
- Flower fulfillment.

## Release-stop conditions

A release must stop rather than guess if any of these become true before deployment:

1. `community_registration_payments` is no longer empty and those rows cannot be reconciled from source evidence.
2. A new function/view/app surface begins treating the legacy payment row as current authority.
3. The public registration path cannot be proven to create canonical registrations.
4. A provider account cannot be bound to the same organization that owns the source transaction.
5. Checkout amount can be supplied independently of the canonical obligation.
6. A webhook path directly mutates registration or Flower commercial/fulfillment truth.
7. The Flower Sale proof requires shared-kernel Flower columns.

## Release order

The intended governed order is:

```text
1. prove/fix canonical registration intake
2. merge provider-agnostic money schema + commands
3. release money migration to production
4. adapt Community Registration to obligation birth; stop legacy writes
5. prove canonical paid -> registration-domain reaction
6. bind Stripe through organization-owned connected_sources
7. prove signed webhook -> receipt/allocation -> paid position
8. prove manual receipt through the same allocation rail
9. add dynamically priced Flower Sale obligation adapter
10. prove Flower collection without changing shared money schema
11. only then treat the collection abstraction as reusable
```

This ordering prevents Stripe from becoming architecture and prevents the empty legacy table from becoming a permanent compatibility burden.