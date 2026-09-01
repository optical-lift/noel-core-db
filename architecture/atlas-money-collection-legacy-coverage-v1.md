# Atlas Money Collection Legacy Coverage v1

## Purpose

A new money authority must not turn absence of historical payment evidence into a false claim that old transactions are unpaid.

The Money Collection Kernel therefore needs an explicit cutover coverage boundary.

## Production census — 2026-09-01

### Community Registration

The current paid Ultimate offering exists, but canonical production contains:

- 0 registrations for the offering;
- 0 `community_registration_payments` rows.

There is therefore no legacy registration-payment corpus to migrate today.

This is an intake-coverage problem, not evidence that no one registered operationally.

### Flower Sales

Canonical production contains:

- 5 `flower_sale_orders` total;
- 4 active Sales;
- 1 cancelled Sale;
- $80.00 gross recorded Sale value;
- $55.00 active recorded Sale value;
- Sale births beginning 2026-08-28.

Atlas currently has no canonical money-receipt authority for those Sales.

The Sale rows prove commercial commitment/value. They do **not** prove whether money remains unpaid, was paid by cash/check, was collected elsewhere, was waived, or was refunded outside Atlas.

Flower fulfillment evidence also cannot close that gap because:

```text
fulfillment != payment
```

## No-inference rule

At Money Collection Kernel release, pre-kernel source transactions must not be silently backfilled into an `open`/`unpaid` state merely because no receipt exists in a system that did not yet have receipt authority.

Likewise, Atlas must not fabricate receipts from:

- fulfillment;
- a Sale existing;
- a registration being known operationally;
- a bank/provider relationship without transaction evidence;
- a human memory not yet admitted as source-attributed evidence.

Unknown stays unknown.

## Coverage boundary

The first production money release must establish a concrete cutover instant/version.

For transactions created **after** that boundary, the domain adapter must create the canonical money obligation atomically with the commercial transaction whenever an obligation is warranted.

For transactions created **before** that boundary, absence of a money obligation means:

```text
money coverage = pre_kernel_unknown
```

not:

```text
unpaid
paid
no money owed
```

A cross-domain payment-status surface must expose that coverage limitation rather than interpreting missing obligations as zero balance.

## Historical reconstruction

A pre-kernel transaction may enter canonical money truth later only through explicit reconstruction from admissible evidence.

Examples:

- check/cash receipt evidence recorded by an authorized human with source note/date;
- processor transaction evidence imported through an organization-owned connected source;
- accounting/bank evidence admitted through a future governed source;
- explicit source documentation that the transaction created a receivable and remains open.

Reconstruction should preserve:

- the original domain transaction id;
- the evidence source;
- observed/known times separately from reconstruction time;
- uncertainty where exact receipt timing or method is not known;
- idempotent linkage so the same historical fact cannot be admitted twice.

A historical Sale should not be forced through a fake present-day checkout attempt merely to get it into the kernel.

## Flower Sale cutover

`record_flower_sale_core_v2` is the correct future attachment point because it is the shared Sale birth authority used by:

- direct member Sale recording;
- Owner-operator Sale recording;
- Demand -> Sale conversion;
- Prospect -> Sale conversion.

The money adapter should therefore be invoked once inside `record_flower_sale_core_v2` after canonical Sale amount/currency exists and before the transaction returns.

That call must be in the same Postgres transaction so either:

```text
Sale + sale_total obligation
```

both exist, or neither exists.

The idempotent existing-Sale branch also needs to verify/reuse the corresponding obligation for **post-cutover** Sales; otherwise a retry could return a Sale whose obligation was omitted by an interrupted/older path.

Pre-cutover Sales are excluded from that repair unless explicit reconstruction has established their money position.

## Cancellation boundary

For post-cutover Sales:

```text
Sale cancellation
  -> domain cancellation truth
  -> money obligation void/reversal policy adapter
```

If no receipt exists, the adapter may void the open obligation according to Flower-domain rules.

If receipt evidence exists, cancellation must not erase it. Refund/reversal evidence follows the Money Collection Kernel while inventory release remains Flower authority.

For pre-kernel Sales, existing cancellation does not authorize Atlas to invent an obligation or refund history.

## Registration intake boundary

Community Registration has the opposite legacy shape: the public offering exists but canonical registration rows are absent.

Payment integration must therefore wait behind canonical intake proof. A provider checkout may only begin from a canonical registration-derived obligation; it may not serve as the mechanism that retroactively decides whether a registration exists.

## Completeness contract

Until historical reconstruction is intentionally completed, any aggregate money report must distinguish:

- `covered` — source transaction is inside the post-kernel authority window or explicitly reconstructed;
- `pre_kernel_unknown` — source transaction predates coverage and lacks reconstructed money evidence;
- `not_applicable` — source transaction legitimately creates no money obligation.

Only `covered` transactions may be classified as open, partially paid, paid, voided, refunded, or overpaid from the kernel.

This boundary prevents a new collection system from rewriting the past merely because it now has a better schema.