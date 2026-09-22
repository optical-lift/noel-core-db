# Atlas Service Commercial Payer Proposal v1

**Status:** architecture contract + executable qualification target  
**Date:** 2026-09-22  
**Parent:** `atlas-service-commercial-composition-v1.md`  
**Live parent migration:** `20260922194953_atlas_service_commercial_composition_v1`

## 1. Purpose

Commercial Composition v1 is already production-live.

It distinguishes:

```text
discovery
→ proposal
→ election
→ payer responsibility
→ settlement
```

The remaining gap is inside payer responsibility itself.

Current production can establish a Payer Profile and then accept that payer's financial responsibility. It lacks a governed state for:

> this payer/billing contact is being proposed for this item, but has not accepted responsibility.

That distinction matters for one-Atlas acquisition because:

```text
billing email known
!=
payer accepted
```

## 2. Governing law

> **A proposed payer relationship is commercial context only. It does not authorize settlement and does not make an item settlement-ready.**

The payer movement becomes:

```text
payer profile exists
→ payer responsibility proposed
→ payer responsibility accepted
→ elected item may become settlement_ready
```

A proposed payer remains nonbillable.

## 3. Canonical relation

No new table is needed.

Use the existing:

`atlas.atlas_service_item_payer_responsibilities`

with its already-live states:

- `proposed`;
- `accepted`;
- `ended`.

This tranche adds the missing service mutation membrane for the `proposed` state.

## 4. New service operation

`atlas.propose_atlas_service_item_payer_service_v1(uuid,uuid,jsonb)`

It may:

- identify an active Payer Profile in the same Commercial Composition;
- establish one proposed responsibility relation for that payer/item;
- preserve proposal evidence.

It may not:

- accept payer responsibility;
- elect a commercial item;
- move an item to `settlement_ready`;
- create a Settlement;
- create Person/Principal/Organization identity;
- create Personal Atlas Purchase, Implementation Purchase, Ledger Entitlement, Connection, or generic Commercial Order.

## 5. Continuity with accepted payer authority

The existing:

`atlas.accept_atlas_service_item_payer_service_v1(...)`

remains authoritative for accepted financial responsibility.

The accepted-payer movement still requires explicit acceptance evidence.

A payer proposal is not automatically upgraded.

## 6. Browser boundary

This is service-internal infrastructure.

Browser roles cannot execute the payer-proposal mutation directly.

A future application surface must separately prove who is authorized to suggest or accept payer responsibility.

## 7. Qualification criteria

Production-schema clone must prove:

1. parent Commercial Composition v1 is already present before this migration;
2. proposed payer can be established for an active same-Composition Payer Profile;
3. proposal preserves payer/item identity and proposal evidence;
4. proposed payer leaves an elected item in `elected` state;
5. proposed payer does not create accepted responsibility;
6. proposed payer does not create settlement-ready state;
7. existing payer-acceptance operation can subsequently accept the same payer;
8. accepted payer then moves the elected item to `settlement_ready`;
9. proposal does not create downstream purchase/entitlement/order truth;
10. browser roles cannot execute the new service mutation;
11. architecture-truth authority and RPC registry both recognize the new function.

## 8. Resulting commercial state

```text
institutional need discovered
→ Ledger item proposed
→ customer elects Ledger
→ billing/payer candidate identified
→ payer responsibility proposed
→ payer accepts responsibility
→ settlement_ready
→ batched Settlement
```

This keeps Atlas's “almost free at first” acquisition experience commercially truthful: Atlas can learn enough to assemble who might pay without treating that information as consent to charge them.
