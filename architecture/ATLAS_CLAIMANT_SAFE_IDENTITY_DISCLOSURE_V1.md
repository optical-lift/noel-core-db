# Atlas Claimant-Safe Identity Disclosure Membrane v1

## Purpose

Atlas may know that a signup/claimant probably matches an existing canonical person without being allowed to reveal why it knows.

This membrane separates:

```text
safe to use for identity resolution
        ≠
safe to show back to the claimant
```

A private Ledger fact may help Atlas recognize Bob. It must not become visible merely because Bob appears to be Bob.

## Claimant-safe identity projection

`atlas.claimant_safe_identity_projection_service_v1(entity_id)` produces only claimant-safe Shared Intelligence facts.

It does not read:

- Ledger source records;
- Ledger source payloads;
- private blind tokens or bindings;
- resolution match summaries;
- another Ledger's notes, relationships, interactions, or contexts.

It may return public/shared facts only when an `entity_evidence_claim` is current, permits `directory_display`, has posture `public_directory` or `public_contactable`, and is not actively suppressed.

Canonical columns such as `local_intel.entities.name`, `email`, `phone`, `city`, or address are **not themselves disclosure authority**. A legacy canonical name with no qualifying public evidence therefore remains hidden from the claimant projection.

## Reveal levels

The service returns:

- `anonymous_match` — Atlas has a canonical identity internally, but no facts are currently safe to show;
- `public_identity` — at least one claimant-safe public fact exists;
- `public_identity_with_affiliations` — public facts plus one or more explicitly approved public affiliations exist.

`anonymous_match` allows signup UX such as:

> We found an existing identity that may be yours.

without exposing a private name/company association.

## Public affiliations

Person↔organization relationships require a separate disclosure decision.

`local_intel.entity_relationship_claimant_disclosures` records whether one canonical relationship is safe to show to the person claiming the subject identity.

Default is effectively hidden: absence of a disclosure row means the relationship does not appear.

v1 supports `public_source` promotion only. A relationship can be marked claimant-visible from public source evidence only when:

- the relationship has a source;
- the source has an Evidence + Disclosure source class;
- that source class allows `directory_display`;
- its maximum disclosure posture is at least `public_directory`;
- the relationship is current and not conflicted.

This permits a future claimant screen to say:

> Are you Bob Jones of Bob Mechanics?

only when the Bob↔Bob Mechanics relationship has independent public disclosure authority.

If that association exists only because another Ledger privately typed it, Atlas may use it internally for resolution but must not surface it.

## No provenance leakage

The claimant projection may identify that a fact is `public_shared`, but it does not reveal:

- which Ledger first supplied the party;
- how many Ledgers know the party;
- which private identifier matched;
- whether a private identifier matched at all;
- another user's notes, ratings, purchase history, or relationship state.

## Relationship verification

Claimant disclosure is narrower than relationship truth.

A relationship can be accepted/current Shared Intelligence and still remain claimant-hidden until an explicit disclosure basis exists.

Future self-verified/controller-verified relationship promotion can be added without weakening the public-source rule.

## Signup use

The expected future flow is:

```text
verified signup identifier
        ↓
identity resolver
        ↓
canonical candidate
        ↓
claimant-safe projection
        ↓
anonymous/public candidate UI
        ↓
identity claim / verification
```

The signup UI must consume this membrane rather than raw canonical entity rows or resolver evidence.

## Core law

```text
recognition may be private
disclosure must have its own authority
```
