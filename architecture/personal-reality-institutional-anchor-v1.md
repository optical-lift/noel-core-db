# Personal Reality Institutional Anchor v1

**Status:** source-only candidate; not released
**Date:** 2026-09-22
**Parent authorities:** Personal Reality Capture Membrane v1; Atlas Service Commercial Composition v1
**Browser consequence:** proposal + explicit human confirmation only
**Production mutation:** none until a governed release occurs

## 1. Purpose

Atlas already preserves ordinary testimony before interpretation. The missing seam is the case where a person says something that appears to belong to an institution rather than only to personal or household reality.

Examples:

- “Payroll is Friday.”
- “The church needs the insurance certificate before the event.”
- “Camps International sends teams to receiving churches.”
- “Our bookkeeper closes the month on the fifth.”

The first truthful consequence is **not** an Organization, Ledger, Implementation Case, Commercial Composition Item, purchase, entitlement, responsibility, membership, or task.

The first consequence is a human-confirmable interpretation:

> this testimony appears to concern an institutional body or institutional operating reality.

This tranche names that interpretation an **Institutional Anchor**.

## 2. Governing boundary

```text
exact testimony
→ candidate institutional interpretation
→ explicit human confirmation
→ confirmed institutional anchor ready for downstream resolution
```

A confirmed Institutional Anchor means only:

> the person confirms that this captured testimony belongs with the named institutional context.

It does not answer:

- whether the institution already exists canonically;
- whether a new Organization should be established;
- whether the institution needs a Ledger;
- whether this is the first Ledger in a family or an additional scope;
- who may authorize implementation;
- who will pay;
- what the implementation price is;
- whether a Commercial Composition item should be proposed;
- whether an Implementation Case should be opened.

Those questions remain downstream.

## 3. Why this belongs in Personal Reality

The raw sentence originates in the person’s Atlas and is already preserved by `personal_reality_captures`.

The existing Personal Reality membrane already separates:

```text
testimony
≠ interpretation proposal
≠ human confirmation
≠ downstream application
```

Institutional Anchor uses that existing separation instead of inventing another intake table.

The new `effect_kind` is:

`institutional_anchor`

It remains an interpretation proposal, not institutional truth.

## 4. Proposal shape

Minimum:

```json
{
  "candidateLabel": "Camps International"
}
```

Optional contextual fields:

```json
{
  "candidateLabel": "Camps International",
  "institutionalSignals": ["payroll", "employees", "recurring operations"],
  "relationshipHint": "organization I help operate"
}
```

`candidateLabel` is a human-supplied or human-confirmed label for routing. It is not canonical Organization identity.

`institutionalSignals` explain why an interpreter surfaced the candidate. They are evidence about interpretation, not proof that a Ledger is required.

## 5. Human authority

A self-authenticated proposal is still only a proposal.

Confirmation continues to require the existing trusted-surface decision receipt:

```text
proposal
→ service-issued human decision receipt
→ authenticated confirmation
→ route_state = ready
```

No new confirmation mechanism is introduced.

## 6. Downstream boundary

This tranche intentionally stops at `route_state = ready`.

The existing generic Personal Reality apply function must fail closed for `institutional_anchor` by returning `destination_unavailable` if a caller attempts to apply it before the downstream institutional-resolution membrane exists.

A later tranche may consume a confirmed Institutional Anchor and ask:

1. Does this map to an existing Organization?
2. Does it belong to an existing Ledger / implementation?
3. Is a new institutional scope warranted?
4. If a Ledger proposal is warranted, which exact commercial item kind applies?
5. Which human has authority to elect it?
6. Which payer may accept financial responsibility?

Only then may the Atlas Service Commercial Composition authority create a priced candidate/proposed item.

## 7. Commercial non-authority

This tranche must not call:

- `open_atlas_service_commercial_composition_service_v1`;
- `add_atlas_service_commercial_candidate_item_service_v1`;
- `propose_atlas_service_commercial_item_service_v1`;
- any payer, settlement, purchase, entitlement, Organization-establishment, or Implementation Case creation command.

Reason: recognizing institutional context does not yet establish the commercial topology.

In particular:

```text
institutional anchor
≠ first-family Ledger
≠ additional Ledger scope
```

Therefore the $3,000 / $2,200 choice cannot be made at this membrane.

## 8. Qualification

Source qualification must prove:

1. `institutional_anchor` is an admitted Personal Reality proposal kind.
2. A nonblank candidate label is required.
3. Institutional signals, when present, are a JSON array of nonblank strings.
4. Proposal creation preserves exact capture/evidence custody.
5. A proposal remains `pending / not_ready` before human confirmation.
6. Trusted-surface confirmation moves it only to `confirmed / ready`.
7. No Organization, Commercial Composition, Composition Item, Implementation Case, Ledger Entitlement, purchase, membership, responsibility, or task is created.
8. Generic application fails closed until a downstream institutional-resolution membrane is released.
9. Existing Personal Reality proposal kinds remain unchanged.

## 9. Result

This establishes the missing truthful middle state:

```text
Tell Atlas
→ preserve words
→ “this is about an organization/group”
→ name the candidate institutional context
→ confirm
→ Atlas may now resolve where that institutional reality belongs
```

The person does not have to classify themselves as a business customer, and Atlas does not manufacture an institution merely because it noticed one.
