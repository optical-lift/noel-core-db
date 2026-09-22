# Atlas Service Settlement Consequence Activation v1

**Status:** source-built candidate; not released  
**Date:** 2026-09-22  
**Parent:** atlas-service-commercial-composition-v1.md  
**Prerequisite:** atlas-service-acquisition-compatibility-adapter-v1 released  
**Scope:** successful Atlas-service Settlement → bounded downstream commercial authority  
**Browser mutation:** none

## 1. Purpose

Commercial Composition now owns the pre-settlement question:

- what Atlas discovered;
- what was proposed;
- what was elected;
- who accepted payer responsibility;
- what was successfully settled.

The missing forward question is:

> What downstream commercial authority may a successful Settlement establish without allowing payment to manufacture unrelated reality?

This tranche builds that membrane.

The authority direction is:

~~~
Commercial Composition
→ elected Composition Item
→ accepted Payer Responsibility
→ successful Settlement
→ Activation Group
→ bounded activation adapter
→ existing downstream commercial authority
~~~

The compatibility adapter remains the opposite, transitional direction for old purchases:

~~~
legacy purchase
→ compatibility binding
→ Commercial Composition representation
~~~

Those two paths must never loop.

## 2. Governing law

> **Payment can activate a commercial right. Payment cannot manufacture non-commercial reality.**

Settlement may create the downstream purchase / entitlement authority that the elected commercial meaning permits.

Settlement may not, merely because money moved:

- create a Person;
- create an Organization;
- decide employment, membership, ownership, or Decision Authority;
- infer a setup sponsor from a payer;
- infer a payer from a setup sponsor;
- create a Principal or Household;
- declare institutional implementation complete.

Therefore:

~~~
settled commercial item
≠ identity establishment
≠ relationship establishment
≠ implementation completion
≠ institutional truth
~~~

## 3. Activation Group

Settlement batching and activation grouping answer different questions.

Settlement asks:

> Which compatible charges moved together for one payer?

Activation asks:

> Which commercial lines jointly establish one downstream commercial consequence?

V1 introduces:

- atlas.atlas_service_activation_groups
- atlas.atlas_service_commercial_composition_items.activation_group_id

Supported V1 activation kinds:

- personal_atlas
- ledger_implementation_first_family

One Settlement may contain lines from multiple Activation Groups. Each group resolves independently.

Pairing may never be inferred from amount, order, adjacency, payer, or provider metadata.

## 4. Forward purchase origin

The old purchase authorities assume Checkout Session origin.

That cannot remain universally true after Commercial Composition becomes the front door.

V1 therefore gives both purchase authorities explicit forward lineage:

- atlas_service_activation_group_id
- atlas_service_settlement_id

Legacy rows retain provider_checkout_session_id.

Forward rows use Activation Group + Settlement and leave provider_checkout_session_id NULL.

Exactly one acquisition origin is valid:

~~~
legacy checkout origin
XOR
Commercial Composition forward origin
~~~

This is not a second purchase model. It is the same purchase authority with a truthful new source.

## 5. Base Atlas consequence

A personal_atlas Activation Group may contain:

- exactly one atlas_base_recurring item;
- zero or one transitional atlas_initial_setup item.

The base recurring item must be active from successful Settlement. A setup item, when present, must be settled.

Activation may create exactly one Personal Atlas Purchase lineage for the already-known authenticated Atlas human.

The payer may be different from that human.

Forward activation:

- derives billing contact from the accepted Settlement payer;
- binds the purchase directly to Commercial Composition auth_user_id;
- may preserve an already-known Principal id;
- creates no Principal;
- creates no Household;
- treats purchaser_email as legacy billing/contact evidence, not identity authority.

The transitional begin_personal_atlas_self_api_v1 lookup is corrected so an already-claimed forward purchase is found by claimed_by_user_id even when payer/billing email differs from authentication email.

## 6. First Ledger consequence

A ledger_implementation_first_family Activation Group must contain exactly:

- one ledger_implementation_first_family item;
- one ledger_recurring item.

V1 requires the implementation/setup line to be successfully settled in the activating Settlement. The recurring Ledger item must already be elected with accepted payer responsibility and carry provider subscription evidence; it may remain settlement-ready until its first governed recurring charge. The implementation item must preserve explicit election evidence.

This preserves the current policy freedom for recurring billing to begin later rather than forcing the first recurring charge into the setup payment.

Activation creates atomically:

~~~
Implementation Purchase
→ Implementation Case
→ baseline Ledger Entitlement
~~~

It preserves:

- exact settled setup amount;
- exact monthly recurring amount;
- recurring start supplied by governed activation evidence;
- provider subscription evidence;
- Commercial Composition / Activation Group / Settlement lineage.

It creates no:

- Organization;
- Organization Unit;
- setup sponsor;
- membership;
- Principal;
- Decision Authority;
- Ledger binding;
- implementation completion.

## 7. Compatibility loop guard

A forward-created purchase must not be treated as an unrelated historical purchase by the Acquisition Compatibility Adapter.

V1 installs a guard on atlas_service_acquisition_compatibility_bindings that rejects Personal or Implementation purchases carrying forward Activation Group lineage.

Historical compatibility bindings remain valid.

## 8. Idempotency

The idempotency key is Activation Group identity, not provider delivery count.

Replay of the same personal_atlas group returns the same Personal Atlas Purchase.

Replay of the same first-Ledger group returns the same:

- Implementation Purchase;
- Implementation Case;
- Ledger Entitlement.

Activation uses a transaction-scoped advisory lock and writes downstream objects + Composition Item lineage in one transaction.

A successful Settlement may therefore be retried without another charge and without duplicate downstream authority.

## 9. V1 service membrane

Service-only functions:

- atlas.open_atlas_service_activation_group_service_v1
- atlas.bind_atlas_service_item_to_activation_group_service_v1
- atlas.activate_atlas_service_activation_group_service_v1

Browser roles receive no direct execute authority.

The activation function reads canonical Settlement, Settlement Lines, Composition Items, payer responsibility, and group identity itself.

A browser cannot submit a claim that Stripe succeeded and thereby cause object creation.

## 10. Explicit V1 limits

This tranche intentionally does not activate:

- additional Ledger scope;
- Connection recurring commercial authority;
- refunds / credits / cancellations;
- partial installment settlement;
- non-Stripe provider settlement.

Unsupported meanings remain blocked rather than guessed.

Those are later consequence families after the first two proofs establish the pattern.

## 11. Qualification

V1 must prove:

1. unrelated Activation Groups can share a Settlement without cross-activation;
2. one Activation Group may span a setup Settlement and a later recurring Settlement without losing identity;
3. grouping is explicit and durable;
4. payer billing email may differ from authenticated Atlas user email;
5. base activation can occur from settled setup + established recurring subscription authority without forcing the first recurring charge into the same Settlement;
6. base activation creates one Personal Atlas Purchase and no Person/Principal/Household/Organization;
7. begin_personal_atlas_self_api_v1 can later establish the Principal from the already-claimed forward purchase even when billing email differs;
8. first-Ledger activation creates one Purchase, one Case, one baseline Entitlement from settled setup + established recurring subscription authority;
9. first-Ledger activation creates no Organization, sponsor, membership, Principal, or Ledger binding;
10. exact commercial amounts and recurring-start policy survive downstream;
11. replay returns the same downstream identities;
12. forward-created purchases cannot be compatibility-imported;
13. browser roles cannot execute activation;
14. service_role can execute activation.

## 12. Governing sentence

> **Commercial Composition decides what was elected. Settlement proves what was successfully settled with the payer. Activation may establish only the downstream commercial authority permitted by that item meaning. Every other reality remains under its own source, relationship, and authority.**
