# Personal Institutional Anchor Resolver v1

**Status:** source-only candidate; not released  
**Date:** 2026-09-22  
**Parent:** Personal Reality Institutional Anchor v1  
**Mutation authority:** none

## Purpose

A confirmed Institutional Anchor says:

> this captured testimony belongs with this named institutional context.

It still does not say where that context already exists in Atlas.

This resolver answers only the next read question:

> Does Atlas already know a governed institutional destination that plausibly matches the human-confirmed label?

The resolver must look only inside reality the signed-in human is already authorized to see.

## Read fields

The resolver compares the confirmed candidate label against:

1. the Principal's already-governed Ledgers;
2. Organizations already visible through the person's Organization access projection;
3. open Implementation Cases in which the signed-in human is an active, verified participant.

It does not search every Organization in Atlas.

## Match semantics

V1 reports:

- exact normalized label match;
- contained-label match.

These are retrieval aids, not identity establishment.

A match means only:

> this existing governed object is label-compatible with the confirmed anchor and is already visible to this human.

It does not mean Atlas has proven canonical identity equivalence.

## Result shape

The read projection returns separate collections:

- `existingLedgers`;
- `accessibleOrganizations`;
- `implementationCases`.

The result is `existing_reality_found` when at least one collection contains a match, otherwise `unresolved`.

The resolver does not rank one candidate as the authoritative winner.

## Hard non-authority

This function must not:

- create or update an Organization;
- create a Ledger;
- create an Implementation Case;
- create a Commercial Composition or item;
- infer first-family vs additional Ledger scope;
- elect commercial scope;
- establish payer responsibility;
- create membership/responsibility;
- mutate the Institutional Anchor proposal.

A no-match result is not permission to establish a new institution.

## Next membrane

A later **institutional anchor adjudication / destination command** may let the human choose among:

- an existing Ledger;
- an existing Organization;
- an existing Implementation Case;
- unresolved / none of these.

Only after that adjudication may a separate commercial/implementation membrane determine whether new governed institutional scope is warranted.
