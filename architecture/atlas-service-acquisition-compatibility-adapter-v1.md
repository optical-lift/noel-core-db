# Atlas Service Acquisition Compatibility Adapter v1

**Status:** architecture contract + executable qualification target  
**Date:** 2026-09-22  
**Parent:** `atlas-service-commercial-composition-v1.md`  
**Depends on:** production-live Commercial Composition v1 and released Atlas service commercial price policy v1

## 1. Purpose

Atlas currently has two already-live acquisition histories:

```text
Personal Atlas Checkout
→ Personal Atlas Purchase
→ Principal / household bootstrap
```

and

```text
Organization Checkout
→ Implementation Purchase
→ Implementation Case
→ baseline Ledger Entitlement
```

Commercial Composition is now the forward commercial control plane, but existing purchase evidence must remain truthful while the application checkout paths are migrated.

This tranche therefore creates a bounded compatibility adapter:

```text
already-authoritative legacy purchase
→ idempotent compatibility binding
→ Commercial Composition representation
```

It does **not** reverse the authority direction of historical purchases and does not charge again.

## 2. Governing law

> **Compatibility reconciliation may reflect already-established commercial truth into Commercial Composition. It may not manufacture, reinterpret, re-settle, or duplicate the purchase that established that truth.**

The adapter is transitional. It exists so the current checkout paths and the new Commercial Composition control plane can coexist without maintaining two unrelated commercial worlds.

## 3. Canonical boundary

The adapter adds one narrow relation:

`atlas.atlas_service_acquisition_compatibility_bindings`

A binding says that one already-existing acquisition record has been represented by one Commercial Composition for migration continuity.

Supported source kinds:

- `personal_atlas_purchase`;
- `implementation_purchase`.

The binding is not a new purchase authority.

## 4. Personal Atlas purchase reconciliation

`atlas.reconcile_personal_atlas_purchase_to_composition_service_v1(uuid,jsonb)`

The Personal purchase must already:

- exist;
- be `active`;
- be claimed by an authenticated Atlas human.

The adapter may then:

1. create one Commercial Composition anchored to the already-claimed auth user / Principal;
2. resolve the historical effective Atlas setup and base-monthly price policies at the purchase date;
3. represent the already-completed legacy setup line as `settled`;
4. represent the already-active base Atlas subscription line as `active`;
5. link both items to the existing `personal_atlas_purchases` row;
6. establish a Payer Profile from the purchase's billing email;
7. treat the existing completed purchase as evidence of accepted payer responsibility for those already-purchased items.

It may not:

- create another Personal Atlas Purchase;
- create a Principal or Household;
- create a new Stripe object;
- create a synthetic Settlement row;
- change current subscription/access state;
- infer a Person identity merely from billing email.

The historical purchase remains the authority for the already-made purchase and current subscription state until the forward acquisition cutover is separately released.

## 5. Implementation purchase reconciliation

`atlas.reconcile_implementation_purchase_to_composition_service_v1(uuid,jsonb)`

The Implementation purchase must already:

- exist;
- be `active`;
- own exactly one Implementation Case;
- own the baseline Ledger Entitlement being represented.

The adapter may:

1. create one Commercial Composition anchored to the existing Implementation Case;
2. represent the setup contract and Ledger recurring obligation using the exact amount snapshots already stored on `implementation_purchases`;
3. link both items to the existing Implementation Purchase and baseline Ledger Entitlement;
4. preserve the direct-purchase record itself as explicit commercial-election evidence.

The adapter deliberately does **not** reconstruct historical payer identity from:

- setup sponsor;
- starting label;
- Organization;
- billing guesses;
- provider metadata that was not canonically stored.

The current Implementation Purchase schema does not canonically carry billing email or payer identity. That absence stays explicit.

## 6. State interpretation

This is a compatibility import, not a replay of historical provider events through the new state machine.

For Personal Atlas:

- legacy one-time setup line → `settled`;
- active base subscription line → `active`.

For Implementation:

- purchased setup contract → `active`;
- purchased Ledger recurring obligation → `active`.

The Implementation adapter records that historical settlement detail was **not reconstructed**. `active` here means the legacy commercial obligation is already in force under the existing purchase authority; it does not fabricate a new Settlement.

## 7. No synthetic settlement

The adapter must not insert rows into:

- `atlas.atlas_service_settlements`;
- `atlas.atlas_service_settlement_lines`.

Those tables are for Commercial Composition settlement events actually established under the new control plane.

Historical checkout evidence remains linked through purchase lineage instead.

## 8. Idempotency

Each supported source purchase may bind to at most one compatibility Composition.

Replay must:

- return the same Composition;
- return the same item identities;
- create no duplicate Payer Profile responsibility;
- create no duplicate purchase or entitlement;
- create no Settlement.

## 9. Authority and browser boundary

Both reconciliation functions are service-only.

Browser roles receive:

- no direct table access;
- no execution authority on the reconciliation functions.

A later Atlas application cutover may invoke these through trusted server orchestration while old acquisition paths remain live.

## 10. Qualification criteria

Production-schema clone must prove:

1. Commercial Composition parent authority is present.
2. Price Policy v1 is present before Personal reconciliation.
3. An active claimed Personal purchase reconciles once.
4. Replay returns the same Personal Composition and item identities.
5. Personal setup/base items link to the same existing purchase.
6. Personal payer responsibility comes from completed purchase evidence, not email inference.
7. Personal reconciliation creates no new Personal Purchase, Principal, Household, or Settlement.
8. An active Implementation purchase reconciles once.
9. Implementation items preserve exact stored purchase amount snapshots.
10. Implementation items link to the same existing purchase and baseline Ledger Entitlement.
11. Implementation payer identity remains unreconstructed.
12. Implementation reconciliation creates no new Implementation Purchase, Case, Entitlement, Organization, or Settlement.
13. Browser roles cannot execute either adapter.
14. Service role may execute both.
15. Architecture truth authority and RPC registry identify the compatibility boundary as transitional.

## 11. Retirement target

This adapter should be retired from the active acquisition path after:

```text
one Atlas entrance
→ Commercial Composition first
→ explicit election / payer responsibility
→ Settlement
→ downstream Personal Purchase / Implementation Purchase / Entitlement adapters
```

is released and existing compatibility-bound purchases no longer require bridge reconciliation.

Historical bindings may remain as provenance after retirement.
