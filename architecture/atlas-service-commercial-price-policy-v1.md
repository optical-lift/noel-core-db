# Atlas Service Commercial Price Policy v1

**Status:** architecture contract + executable qualification target  
**Date:** 2026-09-22  
**Parent:** `architecture/atlas-service-commercial-composition-v1.md`

## 1. Purpose

Atlas service pricing is currently split across several carriers:

- Personal Atlas UI copy;
- Stripe Personal price IDs;
- Organization acquisition constants in `optical-lift/atlas/lib/commercial-entry.ts`;
- persisted implementation purchase amount snapshots;
- persisted Ledger Entitlement price snapshots.

That is acceptable as historical evidence but not as the future authority for one-Atlas commercial composition.

This tranche establishes an effective-dated server-owned price policy for Atlas's own commercial items.

## 2. Governing law

> **Price policy establishes what an Atlas service commercial item costs. It does not establish that the item applies, has been elected, has a payer, or has been settled.**

Therefore:

```text
price policy
≠ discovered need
≠ commercial election
≠ payer responsibility
≠ settlement
≠ entitlement
```

## 3. Canonical relation

`atlas.atlas_service_commercial_price_policies`

Each row owns the effective price for one Composition `item_kind`.

V1 carries:

- item kind;
- charge kind;
- amount in cents;
- currency;
- recurring interval where applicable;
- whether explicit commercial election is normally required;
- effective date range;
- policy status;
- source note/provenance.

## 4. Current V1 price positions

The initial source-backed positions are:

| Item kind | Amount | Charge | Election | Status |
|---|---:|---|---|---|
| `atlas_initial_setup` | $39.95 | one-time | no | transitional |
| `atlas_base_recurring` | $7.00 | monthly | no | active |
| `ledger_implementation_first_family` | $3,000 | one-time | yes | active |
| `ledger_implementation_additional_scope` | $2,200 | one-time | yes | active |
| `ledger_recurring` | $400 | monthly | yes | active |
| `ledger_connection_recurring` | $7.00 | monthly | yes | active |

The $39.95 row is deliberately **transitional**.

It exists so the current Personal checkout can be reconciled truthfully while the new one-Atlas entry model is built.

Its presence does not decide that future one-Atlas acquisition will retain the setup fee.

## 5. Effective dating

Active/transitional price positions for the same item kind may not overlap.

A price change creates a new effective-dated row rather than rewriting historical rows.

Historical settled Composition Items retain the amount they carried when elected/settled.

## 6. Resolver

Internal/service read:

`atlas.atlas_service_commercial_price_policy_v1(item_kind, at_date)`

The resolver returns exactly one effective active/transitional policy or fails closed.

It does not create a Composition Item.

## 7. Relationship to Stripe

Stripe remains settlement/payment infrastructure.

Stripe price IDs may map to these policies later, but Stripe IDs are not the semantic price authority.

The Atlas service policy owns:

> what should this commercial item cost under Atlas policy?

Stripe owns:

> what provider object was used to collect/settle it?

## 8. Relationship to current purchase snapshots

`implementation_purchases` and `ledger_entitlements` already preserve amount snapshots.

Those snapshots remain historical purchase truth.

This policy is the standing effective price source used when future Commercial Composition Items are proposed/elected.

It must not rewrite old purchase amounts.

## 9. Browser boundary

V1 is service/internal only.

The browser receives no direct table access and no direct price-policy RPC.

A later commercial-review API may expose selected price projections safely.

## 10. Qualification criteria

Production-schema clone must prove:

1. all six current item kinds resolve to the intended price;
2. Personal setup is marked transitional;
3. Atlas base monthly is $7;
4. first Ledger setup is $3,000;
5. additional Ledger setup is $2,200;
6. Ledger recurring is $400/month;
7. Connection recurring is $7/month;
8. recurring policies require a billing interval;
9. one-time policies reject a billing interval;
10. overlapping effective policies for one item kind are rejected;
11. resolver fails closed when no policy exists;
12. price lookup creates no Composition Item, purchase, entitlement, settlement, or Order;
13. browser roles cannot read/write the policy table;
14. browser roles cannot execute the resolver;
15. service role may execute the resolver.

## 11. Promotion boundary

This tranche does not yet:

- change what checkout charges;
- retire the $39.95 fee;
- establish a seven-day quiet period;
- create Stripe SetupIntent behavior;
- expose pricing UI;
- create Commercial Composition Items automatically.

The next adapter tranche consumes this policy while reconciling existing purchase paths.

## 12. Resulting architecture

```text
effective Atlas service price policy
→ Composition Item amount/election policy
→ proposal/election/payer responsibility
→ Settlement
→ downstream purchase/subscription/entitlement adapters
```
