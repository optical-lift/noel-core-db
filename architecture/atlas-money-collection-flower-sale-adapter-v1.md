# Atlas Money Collection — Flower Sale Adapter v1

## Purpose

This note resolves the remaining Flower-specific attachment question for the Money Collection Kernel.

The shared money kernel must not know Flower vocabulary, but the Flower domain needs exactly one lawful point where a committed positive-value Sale becomes a receivable.

## Current Sale writers

Production still contains two internal Sale-core versions:

```text
atlas.record_flower_sale_core_v1
atlas.record_flower_sale_core_v2
```

Both currently retain `service_role` execute privilege.

However, the live database dependency audit found **no production function that calls `record_flower_sale_core_v1`**.

Current governed Sale paths converge on v2:

```text
record_flower_sale_for_member_v1
owner_operator_record_flower_sale_v1
record_flower_sale_from_demand_core_v1
record_flower_sale_from_prospect_core_v1
        |
        v
record_flower_sale_core_v2
        |
        v
flower_sale_orders + flower_sale_order_lines
```

The current `farm-atlas` Flower Commerce API calls the governed member/Owner-operator wrappers rather than either core directly.

Therefore `record_flower_sale_core_v1` is a legacy internal writer, not a second business path that should be preserved forever.

## Decision: fence the legacy writer, do not normalize around it

The Money Collection release should make v2 the only lawful current Flower Sale birth core.

Preferred release action:

1. source/dependency audit again immediately before migration;
2. assert no governed function/app contract depends on `record_flower_sale_core_v1`;
3. revoke `service_role` execution on v1 or drop v1 if the release-custody audit proves deletion safe;
4. register v1 as retired/deprecated authority where Atlas architecture custody tracks it;
5. make the positive-Sale receivable postcondition part of v2.

Do **not** add a generic table trigger merely to keep an obsolete writer alive.

A trigger underneath `flower_sale_orders` would make money behavior harder to see, would fire for any future low-level writer whether lawful or not, and would weaken the rule that source-domain adapters deliberately invoke the shared money core.

If a legitimate current consumer of v1 is discovered before release, stop and reconcile that consumer onto v2 rather than shipping dual Sale cores.

## Canonical postcondition

For post-coverage Sale births, `record_flower_sale_core_v2` must leave one of two lawful results.

### Zero-total Sale

```text
flower_sale_order.total_amount = 0
  -> no money obligation
  -> coverage projection = payment_not_required
```

### Positive Sale

```text
flower_sale_order.total_amount > 0
  -> exactly one sale_total money obligation
```

The obligation identity is derived internally from canonical source truth:

```text
organization_id = farms.organization_id for sale.farm_id
source_domain = flower_commerce
source_kind = flower_sale_order
source_id = sale.id
obligation_kind = sale_total
amount = sale.total_amount
currency = sale.currency
```

No caller supplies or overrides these values.

## Transaction boundary

Sale birth and obligation birth are both Postgres truth and must share the same transaction.

The v2 transaction therefore becomes conceptually:

```text
validate farm/member/inventory/buyer/fulfillment
  -> lock/check Ready inventory
  -> create flower_sale_order
  -> create flower_sale_order_lines
  -> create/reuse sale_total money obligation when total > 0
  -> create immediate fulfillment or future fulfillment work under Flower authority
  -> return Sale result
```

If obligation creation fails, the Sale transaction rolls back. Atlas must never create a covered positive Sale that silently lacks its required receivable.

The money call itself should be a narrow internal adapter/core invocation, not a generic public function accepting arbitrary domain/source/amount values.

## Idempotent existing-Sale branch

`record_flower_sale_core_v2` already deduplicates by Sale idempotency key.

After Money Collection activation, the existing-Sale branch must also enforce the receivable postcondition for Sales inside canonical money coverage:

- covered zero-total Sale: no obligation required;
- covered positive Sale: find/reuse exactly one matching `sale_total` obligation;
- covered positive Sale with missing obligation: repair only if the source Sale itself is proven to be post-activation and the repair is the canonical idempotent obligation creation; otherwise raise an invariant error;
- pre-kernel Sale: do not backfill or classify payment state from absence of an obligation.

The coverage boundary, not the mere existence of a Sale, decides whether a missing obligation is repairable invariant drift or historical unknown.

## Demand and Prospect lineage remain untouched

Demand -> Sale and Prospect -> Sale already have their own provenance authority.

The money adapter attaches **after canonical Sale birth** and therefore does not alter:

- Demand commitment;
- Demand reservation/coverage;
- allocation release;
- Demand -> Sale lineage;
- Prospect route custody/release;
- Prospect -> Sale lineage;
- Ready inventory claims.

All those paths receive the same money postcondition only because they converge on the same Sale birth core.

## Fulfillment boundary

`record_flower_sale_core_v2` may create immediate fulfillment in the same domain transaction. That does not make fulfillment payment evidence.

A positive immediate-handoff Sale may therefore be:

```text
fulfilled = true
money position = open
```

until an admissible receipt is recorded.

If cash/check was actually received during handoff, a governed manual receipt command may record and allocate it, potentially in the same higher-level application flow, but fulfillment itself never fabricates that receipt.

## Cancellation boundary

Flower Sale cancellation stays Flower-domain authority.

For a covered positive Sale:

```text
Sale cancellation
  -> Flower cancellation truth
  -> Flower-to-money adapter evaluates obligation consequence
```

Before receipt, the money obligation may be voided when Flower cancellation policy warrants it.

After receipt, the receipt remains historical truth. Any refund/reversal uses Money Collection authority; Flower cancellation does not rewrite receipt history.

Money reversal never returns inventory. Flower cancellation/inventory release never fabricates a refund.

## Pre-kernel Sales

The existing five production Flower Sales remain outside canonical payment coverage unless separately reconstructed from admissible evidence.

Fencing v1 does not change their historical status and does not backfill obligations.

The global Flower Sale money-coverage activation boundary begins reliable forward truth only after the v2 adapter and legacy-writer fence are live atomically.

## Verification contract

The executable release is incomplete unless it proves:

1. no current governed consumer invokes `record_flower_sale_core_v1`;
2. v1 cannot create new production Sales after the cutover;
3. every v2 positive Sale after coverage activation has exactly one `sale_total` obligation;
4. every v2 zero-total Sale after activation is explicitly `payment_not_required` and has no obligation;
5. direct member/Owner sales receive the postcondition through v2;
6. Demand -> Sale receives it through v2 without changing Demand lineage;
7. Prospect -> Sale receives it through v2 without changing Prospect lineage;
8. retries do not duplicate obligations;
9. pre-kernel Sales are not inferred paid or unpaid;
10. fulfillment remains independent from money position;
11. Sale cancellation and money reversal remain independent authorities.

## Governing principle

A reusable kernel should sit behind **one current source-domain authority**, not compensate forever for obsolete writers.

For Flower commerce that source authority is `record_flower_sale_core_v2` once v1 is explicitly fenced.