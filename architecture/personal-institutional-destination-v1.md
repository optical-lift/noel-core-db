# Personal Institutional Destination v1

**Status:** source-only candidate; not released  
**Date:** 2026-09-22  
**Parents:** Personal Reality Institutional Anchor v1; Personal Institutional Anchor Resolver v1

## Purpose

The resolver may return several label-compatible existing destinations. Atlas must not choose among them merely because one string is similar.

The person's next action is another explicit semantic judgment:

> this testimony belongs with this existing Ledger / Organization / Implementation Case

or:

> none of these; keep the institutional context unresolved.

That judgment is represented as another Personal Reality effect proposal:

`institutional_destination`

It receives its own trusted human confirmation receipt before application.

## Proposal shape

```json
{
  "sourceInstitutionalAnchorProposalId": "<uuid>",
  "destinationKind": "implementation_case",
  "destinationId": "<uuid>",
  "destinationLabel": "Camps International"
}
```

Allowed destination kinds:

- `principal_ledger`;
- `organization_access`;
- `implementation_case`;
- `unresolved`.

`unresolved` carries no destination id.

## Application law

Application does not create or modify the selected destination.

For an existing destination, application re-runs the read-only Institutional Anchor resolver and requires the chosen id to remain visible to the signed-in human.

Only then may the Personal Reality proposal record:

- `route_state = applied`;
- the selected destination kind;
- the selected destination id.

If the human chooses unresolved, the proposal records `institutional_unresolved` without creating anything.

## Correction

A later Institutional Destination proposal may supersede an earlier one. Since this tranche creates no downstream institutional/commercial object, correction only revokes/supersedes the prior routing proposal.

## Non-authority

Institutional Destination does not:

- establish Organization identity;
- establish Ledger scope;
- create an Implementation Case;
- create an Implementation Reality Candidate;
- create Commercial Composition items;
- choose first-family vs additional Ledger price class;
- elect a charge;
- establish payer responsibility.

## Next membrane

If the chosen destination is an existing Implementation Case, the exact captured testimony may be handed into that case's **participant conversation** with provenance.

That handoff must not impersonate the assigned practitioner or create a practitioner-authored Reality Candidate.

If the destination remains unresolved or points only to an existing Ledger/Organization without an implementation case, commercial/institutional scope adjudication remains separate.
