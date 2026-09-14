# Atlas Cross-Boundary Responsibility Offers v1

**Status:** Architecture contract only  
**Date:** 2026-09-14  
**Executable scope:** None

## 1. Governing decision

Atlas must support responsibility-bearing items crossing from one person's or institution's reality into another person's Atlas without treating receipt as assignment.

The governing law is:

> **A sender may offer responsibility. Only the receiver's acceptance establishes responsibility for the receiver.**

This law applies whether the relationship is employer/employee, spouse/spouse, friend/friend, collaborator/collaborator, customer/vendor, or no prior Atlas relationship at all.

A message, email, shared item, routed Scope addition, or other delivery mechanism may carry a request such as:

```text
"Please take care of this."
```

but delivery alone creates no responsibility relationship.

## 2. Responsibility offer is distinct from responsibility

Atlas must distinguish at least these concepts:

```text
source information / source work
        ↓
responsibility offer
        ↓
receiver may inspect the disclosed offer
        ↓
accept / decline / ignore / return / counter
        ↓
accepted responsibility, if any
```

A pending offer may be visible in the recipient's Atlas even though the recipient carries none of the offered responsibility yet.

The sender cannot create a canonical `responsible` relationship merely by naming another Person as the target.

## 3. Cross-Atlas boundary crossing is delivery, not custody transfer

When an item crosses into another Person's Atlas, Atlas must preserve the origin of the offered reality.

The crossing itself does not:

- move Ledger custody;
- move Organization custody;
- create a Person↔Ledger membership relation;
- create responsibility;
- prove the sender's factual claims;
- grant ongoing visibility to the sender's underlying Ledger reality;
- erase the sender's existing responsibility;
- create employment or another relationship.

The receiver gets an incoming offer with provenance.

If the source is Atlas-native, the offer may point back to an existing governed subject/work identity. If the source is external communication with no canonical Atlas work object, acceptance may later create local governed work with the message/source event retained as provenance.

## 4. The disclosed envelope is not the source Ledger

Anyone may send someone information through ordinary communication, subject to the sender's own ability to disclose it.

Therefore the recipient may legitimately see the content intentionally disclosed inside the offer envelope even when the recipient has no general visibility into the sender's Ledger.

Atlas must distinguish:

```text
visible because this content was sent to me
```

from:

```text
visible because I have live semantic visibility into the originating Ledger/Scope
```

The first permits the recipient to read the disclosed message, snapshot, attachment, or explicit offer payload.

It does **not** automatically provide continuing access to the underlying live subject, neighboring records, future updates, or source-Ledger context.

If execution requires live source context, that context must cross a separate visibility membrane or be explicitly disclosed as additional offer material.

Acceptance of responsibility does not auto-heal missing visibility.

## 5. Receiver acceptance is the responsibility boundary

A responsibility offer has no effect on the receiver's responsibility dimension until acceptance is established.

Conceptually:

```text
pending_offer
accepted
declined
withdrawn
expired
```

These are architectural lifecycle concepts, not a final enum.

Acceptance must preserve:

- who/what sent the offer;
- who accepted it;
- source relationship context, if any;
- originating subject/work identity, if any;
- disclosed payload/evidence;
- intended responsibility effect;
- acceptance time;
- any source and destination Ledger/custody context;
- provenance.

Decline likewise remains provenance. A declined offer is not transformed into accepted responsibility merely because the source was an employer.

## 6. Employment is a relationship around the generic offer primitive

An employee is not a different species of Atlas user or a special assignment ontology.

Employment means, at minimum, that a specific institution/business and Person have a relationship in which the Person is compensated to receive and ordinarily take on responsibility sent through an agreed source/scope.

That relationship may govern:

- compensation;
- which institution is the employer source;
- which Scopes/kinds of responsibility fall inside the employment arrangement;
- delivery surfaces;
- expected response times;
- scheduling/availability;
- escalation when work is declined or cannot be carried;
- capacity and workload expectations;
- employer coordination/triage visibility where independently admitted.

Employment does **not** mean:

```text
employer sent item -> employee is now responsible
```

The semantic chain remains:

```text
employer sends responsibility offer
        ↓
employee receives it through the employment channel
        ↓
employee accepts or does not accept
        ↓
responsibility exists only when acceptance is established
```

A refusal may violate an employment expectation or create a separate personnel/coordination consequence. Atlas must not solve that consequence by falsifying the responsibility state.

A Person may have multiple employment relationships, each with a different institutional source and Scope.

## 7. Spouse, friend, and informal relationships use the same primitive

A husband may send his wife a responsibility offer.

A wife may send her husband one.

A friend may send another friend something that person could choose to take up.

No employment or organization membership is needed for the offer to exist.

Relationship context may affect product behavior such as:

- which inbox or Notebook surface receives the offer;
- notification priority;
- default categorization;
- shared household/project context;
- trust/spam handling;
- expected response conventions.

But the underlying law remains receiver acceptance.

## 8. External email can be a responsibility-offer transport

Atlas must be able to interpret incoming email or another communication as a *candidate* responsibility offer without converting the communication directly into accepted responsibility.

Example:

```text
Email:
"Can you pick up the kids at 4?"
```

Atlas may surface:

```text
Responsibility requested by Person A
Pick up the kids at 4
[Accept] [Decline]
```

The communication itself remains source evidence.

If the recipient accepts, Atlas may establish local responsibility with the source message preserved as provenance.

If Atlas cannot determine whether a message actually requests responsibility, it may present an interpretation/candidate rather than asserting that a responsibility offer unquestionably exists.

## 9. Atlas-native offer versus external-source offer

Two source cases must remain distinguishable.

### 9.1 Atlas-native source

An originating governed work/subject already exists.

The offer should reference that canonical source rather than manufacture a second authoritative copy merely because another Person receives it.

After acceptance, the receiver's Atlas may project the accepted foreign responsibility into the receiver's own work surfaces while preserving the originating identity/custody.

Existing `work_allocations` cannot represent this generic future case because they require assignee and assigner to be organization memberships inside the same Organization. That is a compatibility responsibility carrier, not the complete cross-Atlas Person responsibility model.

### 9.2 External/non-Atlas source

No canonical Atlas work identity exists at receipt time.

The incoming communication/offer may become provenance for a new local work identity if the recipient accepts it.

Atlas must not pretend there was an upstream canonical Company Work object when there was only an email, message, phone note, or other external request.

## 10. Sending does not release the sender

If the sender already carries responsibility for the offered reality, merely offering it to another Person does not release the sender.

The sender's responsibility may change only when the intended handoff effect and accepted response justify that change.

Therefore:

```text
A carries X
A offers X to B
B has not accepted
```

must still resolve as:

```text
A carries X
B does not carry X
```

If B declines, A's prior responsibility remains unless another independent fact changes it.

This prevents the common but false inference:

```text
"I emailed it to you, so it is your problem now."
```

## 11. Accepted offers may have different intended responsibility effects

Not every accepted request means the same thing.

The offer must preserve the intended responsibility effect rather than forcing one universal handoff interpretation.

Conceptually, accepted effects may include patterns such as:

- **transfer** — responsibility is intended to move from sender/current carrier to receiver after acceptance;
- **delegated child responsibility** — sender retains broader/parent responsibility while receiver accepts a bounded portion;
- **new requested responsibility** — receiver accepts a responsibility the sender did not necessarily carry personally;
- **shared/participating responsibility** — the receiver joins without becoming the sole responsible Person.

These are architectural patterns, not final executable modes.

Atlas must not infer the intended effect merely from relationship type.

## 12. Relationship context does not change factual truth

An employer can make a false claim in an offer.

A spouse can make a false claim.

A friend can misunderstand the situation.

Acceptance means the receiver agreed to carry the requested responsibility under the accepted terms. It does not make every factual statement bundled into the request true.

Claims and evidence remain governed through the separate claim/evidence/adjudication architecture.

## 13. Visibility and responsibility remain independent after acceptance

Acceptance may establish responsibility while visibility remains narrower than what successful execution requires.

Atlas must preserve states such as:

```text
Person B accepted responsibility for X
Person B can see only the explicitly disclosed offer payload
Person B lacks live visibility to required source context Y
```

That should surface as a real execution/context problem, not trigger an automatic visibility grant.

The sender or another legitimate source may then disclose additional context or establish a separate governed visibility admission.

## 14. Responsibility intake should be a generic Atlas surface

Because responsibility offers can come from many relationship types, the recipient needs a generic personal intake concept rather than an employee-only queue.

Conceptually, the recipient's Atlas should be able to distinguish:

```text
Incoming information
Incoming responsibility offer
Accepted responsibility
Declined/returned responsibility offer
```

Relationship context may create filtered views such as:

- Work from Elm Farm;
- Household requests;
- Things shared by spouse;
- Requests from collaborators;
- External requests from email;
- Unknown/untrusted responsibility requests.

Those are projections over one responsibility-intake primitive, not separate ontologies.

## 15. Existing Atlas substrates are precedents, not the generic solution

Current Atlas already contains useful pieces:

- `institutional_conversation_response_events` supports organization-local `handed_off` events, target memberships, and links to Company Work;
- `communication_derived_work_links` preserves exact-message → Company Work provenance;
- `organization_access_invitations` preserves issued/accepted/declined lifecycle semantics;
- `work_allocations` separates current Company Work responsibility from work identity;
- `task_problem_handoffs` and `workflow_handoffs` preserve domain-local handoff patterns.

None of these should be silently generalized as the cross-Atlas responsibility-offer ontology because they are organization-, farm-, task-, or workflow-shaped.

The future generic contract must be Person-addressable and able to cross institutional boundaries.

## 16. Addressability requirement

A responsibility offer needs a targetable recipient even when the recipient is not already a member of the sender's Organization or Ledger.

Possible transports include:

- canonical Atlas Person identity;
- a verified Atlas address/contact endpoint;
- email;
- phone/messaging endpoint;
- future external collaboration endpoint.

Transport identity is not responsibility identity.

If an offer is sent to an external endpoint that later resolves to an Atlas Person, reconciliation must preserve the original send provenance rather than pretending the Person identity was known earlier.

## 17. No implicit roster or membership creation

Sending, receiving, accepting, or declining a responsibility offer does not create a generic membership relation between Person and originating Ledger.

If B accepts one Elm-originated responsibility item, Atlas may truthfully derive that B currently carries that Elm reality.

It must not silently add:

```text
B member_of Elm Ledger
```

The earlier no-Person↔Ledger-membership law remains intact.

## 18. Coordination after acceptance

Once accepted responsibility exists, the normal aperture/Scope laws apply.

People with the appropriate overlapping/broader visibility and responsibility may observe and triage within their valid aperture.

But the original incoming offer remains provenance for how the responsibility entered the recipient's Atlas.

A later reroute does not rewrite the acceptance history.

## 19. Fail-closed conditions

Atlas must not establish receiver responsibility when:

- an offer was merely delivered;
- an email parser inferred a request but the receiver did not accept it;
- a sender claims to be an employer without governed relationship evidence;
- an organization membership exists but no acceptance exists;
- a sender has broader visibility/responsibility than the receiver;
- the receiver viewed or opened the message;
- the receiver acknowledged receipt only;
- the receiver was copied on a communication;
- an existing compatibility assignment field names the receiver but the future acceptance contract is required;
- identity reconciliation of the target is unresolved.

## 20. Explicit non-scope

This document does **not**:

- create a responsibility-offer table;
- create a generic cross-Atlas responsibility relation;
- create a new Person addressing table;
- define executable acceptance/decline enums;
- define a transport protocol;
- define standing pre-acceptance rules;
- define employment compensation schema;
- define HR discipline or employment-law consequences;
- replace `work_allocations` yet;
- change current Worker Day responsibility behavior;
- change organization invitation behavior;
- change correspondence parsing behavior;
- migrate any production data.

## 21. Next unresolved boundary

The cross-boundary law is now settled:

> **Anyone may send a responsibility offer across another Person's Atlas boundary; only the receiver's acceptance creates responsibility for the receiver. Employment is a compensated relationship/channel around that generic primitive, not a separate responsibility ontology.**

The next architectural boundary is the **accepted responsibility effect**:

> When the receiver accepts an Atlas-native offer, should the recipient carry the original cross-Ledger work identity directly, should Atlas create a recipient-local derived work identity linked to the source, or should the choice depend on whether the sender intended transfer, delegation, or a new requested responsibility?

That identity/custody law must be settled before creating a generic responsibility-offer schema.