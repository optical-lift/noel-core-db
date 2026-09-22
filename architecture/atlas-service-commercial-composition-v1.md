# Atlas Service Commercial Composition v1

**Status:** production-live commercial composition infrastructure; acquisition adapters not yet cut over  
**Date:** 2026-09-22  
**Product contract:** `optical-lift/atlas/docs/architecture/atlas-commercial-composition-and-deferred-settlement-v1.md`  
**Scope:** Atlas's own SaaS/implementation billing control plane  
**Browser mutation:** none in v1

## 1. Purpose

Atlas currently has two independent acquisition authorities:

- `personal_atlas_purchases`;
- `implementation_purchases` + `ledger_entitlements`.

Those authorities describe already-purchased commercial facts.

They do not own the new pre-settlement question:

> What has Atlas discovered may need to be purchased, what has the customer actually elected, who is responsible to pay for each elected item, and which elected items were settled together?

This tranche establishes that control plane.

## 2. Governing law

> **Commercial discovery is not a purchase. Commercial election is not settlement. Settlement is not entitlement activation.**

The required state separation is:

```text
discovered need
≠ proposed commercial item
≠ elected commercial item
≠ settlement-ready item
≠ settled payment
≠ active entitlement / Ledger / Connection
```

Atlas must preserve each movement explicitly.

## 3. Relationship to the generic Commercial kernel

The existing `commercial_orders`, `commercial_payments`, Offerings, and recurring commitments are Organization-scoped sales/commerce authority.

They remain valid for a canonical selling Organization's commerce.

This control plane sits **before** that downstream settlement/commerce expression because:

- a Commercial Composition may exist before the payer is canonically known;
- a Ledger need may be discovered before anyone elects it;
- a billing contact may exist before Person/Organization truth exists;
- Atlas must not manufacture an Order merely because it recognizes a likely Ledger need.

A later adapter may express an elected/settled Atlas service position into Stripe and/or the generic Commercial kernel where semantically fitting.

## 4. Commercial Composition

Canonical relation:

`atlas.atlas_service_commercial_compositions`

A Composition is the commercial working set for one Atlas-entry / implementation journey.

It may be anchored by:

- authenticated user;
- Principal;
- Implementation Case;

without requiring all three to exist at opening time.

It records:

- lifecycle status;
- currency;
- commercial quiet-period boundary;
- provenance/metadata.

It does not itself establish a Personal Atlas Purchase, Ledger Entitlement, Connection, Organization, or Stripe Subscription.

## 5. Composition Item

Canonical relation:

`atlas.atlas_service_commercial_composition_items`

One item represents one independently meaningful commercial obligation.

V1 item kinds:

- `atlas_base_recurring`;
- `atlas_initial_setup`;
- `ledger_implementation_first_family`;
- `ledger_implementation_additional_scope`;
- `ledger_recurring`;
- `ledger_connection_recurring`;
- `commercial_adjustment`.

Charge kinds:

- `one_time`;
- `recurring`.

Lifecycle:

```text
candidate
→ proposed
→ elected
→ settlement_ready
→ settled      (one-time)
→ active       (recurring)

candidate/proposed/elected
→ withdrawn
```

`adjusted` is reserved for later reconciliation of a previously settled/active item.

V1 does not silently auto-elect a Ledger item.

An unsettled candidate/proposed/elected item may be explicitly withdrawn. Withdrawal preserves the Item and ends any accepted payer responsibility rather than deleting commercial history.

## 6. Explicit-election boundary

Every item has `requires_explicit_election`.

Examples:

- base $7 Atlas item may be created as already consented/elected by the entry contract;
- Ledger implementation must require explicit election;
- additional Ledger scope must require explicit election;
- Connection billing follows its own activation/election policy.

An item that requires explicit election cannot enter `elected` without non-empty election evidence.

Service functions are not user authority.

They only preserve the result of an upstream governed authorization/election membrane.

## 7. Payer Profile

Canonical relation:

`atlas.atlas_service_payer_profiles`

A Payer Profile is billing identity/context.

It may carry:

- billing email;
- provider/customer key;
- optional canonical Person;
- optional canonical Organization;
- display label.

It must not infer canonical Person or Organization merely from billing email/provider identity.

Therefore:

```text
payer profile
≠ authenticated user
≠ Principal
≠ setup sponsor
≠ Organization authority
```

## 8. Payer Responsibility

Canonical relation:

`atlas.atlas_service_item_payer_responsibilities`

This relation answers:

> Which payer has accepted financial responsibility for this exact Composition Item?

One active accepted payer is allowed per item in v1.

A proposed payer does not make an item settlement-ready.

An accepted payer responsibility requires explicit acceptance evidence.

When an elected item gains an accepted payer it becomes `settlement_ready`.

## 9. Settlement

Canonical relations:

- `atlas.atlas_service_settlements`;
- `atlas.atlas_service_settlement_lines`.

A Settlement records one provider/payment event grouping one or more compatible items for one payer.

This is where the Apple/iTunes batching principle becomes durable:

```text
multiple elected items
+ same payer
+ compatible settlement moment
→ one Settlement
→ multiple Settlement Lines
```

Each line preserves the independently meaningful Composition Item.

A successful Settlement:

- moves a one-time item to `settled`;
- moves a recurring item to `active`.

It does not create the underlying Ledger/Connection entitlement.

That requires the owning commercial/entitlement adapter.

## 10. Settlement integrity

V1 settlement requires:

- all lines belong to the same Composition;
- all lines have the same accepted Payer Profile as the Settlement;
- each item is `settlement_ready`;
- line amounts are non-negative;
- Settlement amount equals line sum;
- provider settlement key is idempotent when supplied.

Failed/pending payment-state observation is outside this first mutation contract.

V1 records successful settlement only.

Later provider event observation may add pending/failed lifecycle without weakening this proof.

## 11. Legacy-source links

Composition Items may optionally identify the already-existing authorities they reconcile with:

- `personal_atlas_purchase_id`;
- `implementation_purchase_id`;
- `ledger_entitlement_id`.

Those are lineage links.

The Composition does not rewrite their historical purchase facts.

This allows the migration path:

```text
old purchase authority
→ linked Composition Item
→ future unified commercial read
```

without deleting or falsifying existing purchases.

## 12. Service-only mutation membrane

V1 exposes only service-internal commands:

- open Composition;
- add candidate Item;
- propose Item;
- elect/withdraw Item;
- establish Payer Profile;
- propose Payer Responsibility;
- accept Payer Responsibility;
- withdraw an unsettled Item;
- record successful Settlement.

Browser roles receive no direct table access and no execute grant on these mutation functions.

Later application APIs must prove:

- authenticated identity;
- item-specific commercial authority;
- explicit Ledger-election consent where required;
- payer authorization.

## 13. Quiet period

`quiet_period_ends_at` is a commercial scheduling fact, not entitlement truth.

It allows Atlas to say:

> start now; settle the base relationship after a bounded discovery window.

V1 does not hard-code seven days.

Pricing/product policy supplies the timestamp.

The kernel only preserves it.

## 14. No hidden enterprise classification

The Composition never stores a customer plan class such as:

- personal;
- business;
- enterprise;
- mother;
- company size tier.

Price follows elected item meaning.

A wealthy individual may have only `atlas_base_recurring`.

A tiny nonprofit may legitimately elect a Ledger.

## 15. Qualification criteria

Production-schema clone must prove:

1. Composition can exist with authenticated-user anchor before Principal exists;
2. Composition does not create Personal Atlas Purchase, Implementation Purchase, Ledger Entitlement, Organization, or Connection;
3. candidate item is not billable;
4. candidate can become proposed without becoming elected;
5. explicit-election-required item cannot be elected without election evidence;
6. elected item with no accepted payer is not settlement-ready;
7. billing email does not create Person/Principal truth;
8. proposed payer responsibility does not make item settlement-ready;
9. accepted payer responsibility requires acceptance evidence;
10. elected item + accepted payer becomes settlement-ready;
11. one Settlement may contain multiple compatible items;
12. Settlement total must equal line sum;
13. Settlement cannot mix payer responsibility;
14. Settlement cannot consume candidate/proposed items;
15. successful settlement moves one-time item to settled;
16. successful settlement moves recurring item to active;
17. Settlement does not create Ledger Entitlement or Personal Atlas Purchase;
18. duplicate provider settlement key is idempotent;
19. browser roles cannot read/write Composition tables;
20. browser roles cannot execute service mutation RPCs;
21. existing Personal/Implementation purchase rows remain untouched;
22. no generic Order is created merely by Composition discovery/election.

## 16. Promotion boundary

V1 does not yet:

- replace current Personal checkout;
- replace current Ledger implementation checkout;
- create Stripe SetupIntent/Subscription code;
- decide the base quiet-period duration;
- retire the $39.95 setup fee;
- create a browser Commercial Review surface;
- infer institutional need from Reality Discovery;
- route Tell Atlas testimony to a Ledger;
- create generic Commercial Orders.

Those are subsequent tranches over this kernel.

## 17. Resulting architecture

```text
Atlas entry / discovery
→ Commercial Composition
→ candidate Item
→ proposal
→ explicit election where required
→ accepted payer responsibility
→ settlement-ready
→ batched Settlement
→ purchase / entitlement / subscription adapters
→ active Atlas / Ledger / Connection commercial reality
```

The commercial control plane now matches the product claim: one Atlas can discover very different worlds without requiring the customer to choose a different product before Atlas knows what they are carrying.


## 18. Production receipt — 2026-09-22

Atlas Service Commercial Composition v1 crossed its first production boundary on September 22, 2026.

Canonical lineage:

- architecture/candidate PR #1192 → merge `b63c1a4577090dc4ef35a0073e8ef90fa2dafb99`;
- governed generation request #1193;
- generated migration `20260922194953_atlas_service_commercial_composition_v1.sql`;
- generated package SHA `a2b5b64973cdc7e03f68002fa783995aa051f1dd`;
- generated package PR #1194 → merge `20fd5b60c8e7b5bb381f4b2293da9e5f483869b3`;
- Production Schema Clone Validation request #1195 / run `35776381104` → PASS;
- governed production release request #1197;
- protected Production Database Release run `35777131183` → PASS;
- production migration ledger contains version `20260922194953`.

The passing production-schema clone proved the full control-plane distinction:

```text
authenticated journey anchor
→ Commercial Composition before Principal exists
→ candidate base + Ledger items
→ proposal without election
→ explicit-election Ledger item cannot elect without evidence
→ billing identity remains separate from Person/Principal truth
→ accepted payer responsibility
→ settlement-ready
→ multiple independently meaningful items
→ one successful batched Settlement
→ one-time item settled
→ recurring items active
```

The same proof confirmed that this movement creates none of the downstream truths merely by composing/settling:

- no Personal Atlas Purchase;
- no Implementation Purchase;
- no Ledger Entitlement;
- no Organization;
- no Connection;
- no generic Commercial Order.

Direct production verification confirms:

- all six commercial-control-plane relations are live;
- `authenticated` has no direct SELECT access to Composition, Item, Payer, or Settlement tables;
- `authenticated` cannot execute the service-only Composition opener;
- `anon` cannot execute the Settlement recorder;
- `service_role` can execute the intended service mutation membrane;
- provider-backed batching therefore remains server-owned.

The three registered architecture-truth authorities remain `incomplete` deliberately:

- `atlas_service_commercial_composition`;
- `atlas_service_payer_responsibility`;
- `atlas_service_settlement`.

They remain incomplete because the current Personal Atlas checkout and Ledger implementation checkout still write their existing purchase authorities directly. The new control plane is production-live infrastructure but is not yet the sole product acquisition path.

The next promotion boundary is therefore an adapter/cutover tranche, not more Commercial Composition ontology.
