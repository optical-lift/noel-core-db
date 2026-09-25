# Atlas Institutional Communication Response Work v1

Status: governing implementation architecture  
Date: 2026-09-25

## Core law

Institutional communication authority and Company Work responsibility meet at one narrow membrane.

A communication endpoint may reveal that a response consequence exists. It does not assign that consequence to a Person.

The lawful first transition is:

~~~text
Reality Person
→ institutional communication response-work responsibility
→ exact institutional response case
→ Company Work created for that case
→ same Person explicitly self-claims
→ exact Work responsibility governs from there
~~~

## Response-work intake responsibility

The institutional responsibility key is institutional_communication_response_work.

V1 grants one operation: response_work.claim_self.

It is scoped to the exact institution and exact communication endpoint.

This operation may recognize an exact unresolved response case as Company Work, create the one Work item bound to that case if none exists, and establish responsibility only for the signed-in Person themselves.

It may not assign the Work to another Person, transfer an existing responsibility, add a collaborator to somebody else's Work, complete another Person's Work, or cancel another Person's Work.

## Why claim may create Work

The Work is not invented by claiming. The response case already records an unresolved institutional communication consequence. Claim converts that exact consequence into the Company Work kernel and preserves source identity.

The Work source is institutional_conversation_response_case, source identity is the exact response case, and the result contract is institutional_communication_response_v1. The responsibility-establishment basis is self_claim.

This separates two truths: the institution has an unresolved response consequence; and this Person has taken responsibility for it.

## Authority handoff

Authority changes at claim.

Before claim, institutional response-work responsibility governs whether the Person may convert the response case into Work and self-adopt it.

After claim, the exact active Work responsibility allocation governs response-state changes, completion, and responsible classification as informational.

Endpoint close, handoff, or generic Organization role cannot override exact Work custody.

## Completion

Completion requires the actor to be the current exact responsible allocation carrier.

The communication domain adapter may record the completion Result and accept that domain Result because it is the terminal effect of the exact response Work contract. It does not use endpoint close authority.

## Informational classification

Once a Person has self-claimed the response Work, that exact responsible Person may classify it informational. This releases their exact responsible allocation and cancels the bound Work with explicit provenance.

An unclaimed response case cannot be marked informational through this v1 membrane. A separate institutional response-adjudication authority would be required if Atlas later needs a Person to declare, before claim, that no Work exists.

## Handoff and collaboration

Direct handoff is fail-closed.

~~~text
sender says "you own this now"
!=
receiver carries Work responsibility
~~~

The old endpoint handoff capability is not promoted into Company Work transfer authority.

Likewise, direct participant/approver allocation is fail-closed. Adding a collaborator is still the creation of another Person's Company Work participation and requires a receiver-uptake contract.

The next lawful transfer shape is:

~~~text
current responsible Person
→ proposes transfer / participation
→ target Reality Person receives exact offer
→ target accepts
→ receiver-side establishment basis
→ old responsibility releases
→ new responsibility activates
~~~

V1 deliberately does not invent that receiver-uptake table or relation.

## Elm cutover

Lex receives one bounded legacy-adjudicated responsibility for Elm Farm: jurisdiction Elm Farm Reality Entity; endpoint hello@elmfarm.co; operation response_work.claim_self.

The old explicit endpoint claim carrier is preserved only as compatibility evidence/carrier constraint. Existing handoff and close carrier grants are not promoted to response-work authority.

## Acceptance

Accepted only when conversation claim resolves through Reality Person plus the bounded response-work responsibility; claim creates Work only from the exact response case; claim establishes only self_claim responsibility for the caller; the created Work uses institutional_communication_response_v1; response-state mutation after claim requires the exact active responsible allocation; completion verifies actor equals exact responsible allocation; endpoint close authority cannot complete or cancel another Person's Work; direct handoff is fail-closed; direct collaborator assignment is fail-closed; and rollback proof can claim, transition, and complete a real unclaimed response case without persisting proof state.

## Receiver uptake now implemented

Response-work handoff no longer remains merely fail-closed. The compatibility handoff command now creates a generic Company Work responsibility-transfer offer.

The current responsible Person remains responsible after the offer. The target Reality Person must independently accept the offer before the source allocation releases and the target self-adopts the Work.

Collaboration uptake remains separate and still fail-closed.
