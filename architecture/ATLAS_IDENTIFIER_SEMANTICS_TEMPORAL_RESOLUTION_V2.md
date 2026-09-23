# Atlas Identifier Semantics + Temporal Resolution v2

## Purpose

Identity resolution v1 correctly separated canonical identity from private source custody, but it still treated a matching identifier too much like a matching party. Reality is messier:

- one email/phone can belong to several people;
- one identifier can change owners over time;
- a role inbox identifies an organization/role rather than the current human operator;
- evidence derived from one underlying source can appear as several correlated signals;
- matching evidence may be useful for resolution without being safe to disclose during a future self-claim flow.

v2 makes identifier meaning explicit before Atlas uses a match.

## Identifier semantics

`atlas.identity_identifier_semantics` defines what a signal means.

Initial semantics:

- `exclusive_personal` — intended to identify one person during an overlapping validity interval;
- `shared_household` — legitimately shared among people in a household/family;
- `exclusive_organization` — intended to identify one business/organization during an overlapping interval;
- `organization_contact` — shared contact route for an organization;
- `role_contact` — identifies an organizational role/contact route, not the human currently operating it;
- `unknown_shared` — unresolved cardinality; may assist review but is not safe for automatic resolution or global private-binding teaching.

Each semantic declares:

- cardinality mode: `exclusive`, `shared`, `role`, or `unknown`;
- allowed canonical entity types;
- whether it may participate in resolution;
- whether it may support automatic resolution;
- whether a confirmed private signal may teach Atlas a global opaque match binding;
- the disclosure rule for future claimant/self-claim presentation.

## Party-type constraint

A signal is only allowed to produce candidates whose canonical `entity_type` is compatible with its semantic.

Examples:

```text
exclusive_personal email
    → person candidate
    → not Bob Mechanics LLC

role_contact email
    → organization/business candidate
    → not automatically the employee currently reading the inbox
```

Person↔organization relationships must be represented as relationships, not inferred by collapsing both into one identity.

## Cardinality

A private opaque identifier is no longer globally modeled as exactly one token → one entity.

`local_intel.entity_private_identifier_bindings` permits multiple canonical bindings when the identifier semantic is legitimately shared.

For `exclusive` semantics, overlapping bindings to different canonical entities are treated as conflicts rather than silently reassigned.

For `shared` semantics, multiple current bindings are lawful. The resolver will see multiple candidates and preserve ambiguity unless independent evidence separates them.

## Temporality

Source identity signals and private identifier bindings carry `valid_from` / `valid_until`.

The resolver only uses evidence valid for the evaluation date.

This prevents an old phone number, expired domain, recycled role inbox, or superseded address from remaining timeless identity proof.

Private bindings inherit the validity interval of the confirmed source signal. Reassignment should retire/end the prior binding rather than rewriting history.

## Evidence families

`atlas.identity_resolution_signal_policies.default_evidence_family_key` groups correlated signals.

Examples:

```text
website + domain + contact_url
    → web_presence

phone
    → phone

email
    → email
```

Resolver v2 takes only the strongest matched signal from each evidence family before combining confidence.

Therefore four URLs derived from one website cannot impersonate four independent witnesses.

Connectors may supply a narrower evidence-family key when several extracted signals are known to originate from the same underlying source fact.

## Auto-resolution boundary

A candidate may auto-resolve only when:

1. its score exceeds the configured automatic threshold;
2. it clears the ambiguity margin over the second candidate;
3. at least one matched signal semantic explicitly permits automatic resolution.

`role_contact` and `unknown_shared` evidence may support a human review case without independently authorizing an automatic identity decision.

## Private binding teaching

When a source record is durably resolved to a canonical entity, Atlas may project its private blind signals into the resolver-only binding table only when the signal semantic permits teaching.

For an exclusive semantic:

```text
same opaque identifier
+ overlapping time
+ different canonical entity
    → conflict
    → no silent reassignment
```

For a shared semantic:

```text
same opaque identifier
+ Person A
+ Person B
    → both lawful bindings
    → later resolver sees ambiguity
```

## Disclosure authority

Private resolution signals remain non-disclosable by default.

The semantic carries a `claimant_disclosure_rule`, but v2 does not yet build the signup/self-claim projection.

The future claimant interface must never infer `safe to show Bob` merely from `useful to recognize Bob`.

Shared/public evidence continues to use the Evidence + Disclosure membrane's existing disclosure posture and permitted-use rules.

## Compatibility

Identity Resolution v1 remains present for compatibility. Resolver v2 uses the new semantic/temporal binding model.

Existing private-match tokens may be backfilled conservatively as `unknown_shared`; they do not gain automatic-resolution authority merely because they predate this model.

## Core law

```text
a matching value is evidence
not identity

identifier meaning + party type + time + independent corroboration
determine what the match is allowed to prove
```

## Claimant-safe disclosure succession

Resolver v2 may determine that a signup/claimant probably refers to an existing canonical entity, but resolver evidence is not itself safe to show back to that claimant.

Claimant-facing identity presentation must pass through `architecture/ATLAS_CLAIMANT_SAFE_IDENTITY_DISCLOSURE_V1.md` and `atlas.claimant_safe_identity_projection_service_v1`.

A private blind match, private source record, or private Ledger association may establish recognition while producing only an `anonymous_match` claimant projection. Public names, public contact facts, and public affiliations appear only when they carry separate disclosure authority.

