# Atlas Responsibility Offer and Relation Lifecycle v1

## Status

Architecture contract only. No executable schema, migration, RPC, application mutation, or production behavior is introduced by this document.

## Purpose

Define the generic lifecycle beneath employment delegation, household requests, spouse/friend requests, collaborator handoffs, communication-derived requests, and future cross-Atlas responsibility exchange.

The governing distinction is:

> **An offer to carry responsibility is not responsibility.**

A sender may deliver a responsibility-bearing request into another Person's Atlas. Delivery makes the disclosed offer available to the intended receiver; it does not make the receiver responsible. The receiver decides whether to take it on.

The resulting model has two different lifecycles:

```text
Responsibility Offer
    pending
    accepted | declined | withdrawn | expired

accepted + sufficiently resolved effect
                ↓
Responsibility Relation
    current
    completed | released
```

The two lifecycles must not be collapsed into one status machine.

## 1. Responsibility Offer

A Responsibility Offer is a directed proposal asking a canonical Person to take on specified responsibility.

It may originate from:

- another Person;
- a Person acting in an employer/business context;
- a household or collaborator context;
- an Atlas-native governed subject;
- an external communication such as email or messaging;
- another source whose provenance Atlas can preserve.

The offer is not a Person↔Ledger membership, role, assignment, work allocation, authority grant, visibility grant, or claim that the receiver already carries the requested responsibility.

### 1.1 Minimum offer semantics

A future executable offer must be able to preserve, conceptually:

- intended receiver Person;
- originating actor/source provenance;
- disclosed payload or reference;
- requested responsibility effect when known;
- referenced governed subject/Scope when known;
- source Ledger/custody context when known;
- relationship/context such as employer, household, friend, collaborator, vendor, or none;
- time of delivery;
- optional expiry;
- durable response history.

The architecture does not yet prescribe table names or exact columns.

### 1.2 Offer states

The canonical offer lifecycle is:

#### `pending`

The offer has been delivered/addressed and remains open for the intended receiver's decision.

`pending` creates **zero receiver responsibility**.

#### `accepted`

The intended receiver has affirmatively chosen to take on the offered responsibility.

Acceptance is durable provenance. It is not a claim that every bundled factual assertion is true, and it does not automatically:

- grant source-Ledger visibility;
- move custody;
- release another carrier;
- prove completion criteria;
- infer an effect type that the response did not establish.

If the acceptance is clear but the exact responsibility effect or governed target remains ambiguous, Atlas preserves the acceptance and marks the downstream effect resolution as unresolved rather than guessing transfer/delegation/participation/new-work semantics.

#### `declined`

The intended receiver refused the offer.

No responsibility relation is created from that offer.

A decline may have consequences under some other relationship, such as employment, contract, household agreement, or social expectation. Those consequences are separate governed facts; they do not retroactively make the declined responsibility accepted.

#### `withdrawn`

The sender/source withdrew an offer before it produced an accepted responsibility relation.

Withdrawal ends the open request. It does not erase the historical offer or delivery.

A sender cannot use offer withdrawal to cancel an already-established responsibility relation. Once accepted responsibility exists, ending it is a responsibility-lifecycle question.

#### `expired`

The offer's acceptance window elapsed without acceptance.

Expiry creates no responsibility. A later request should be represented as a new/reissued offer with provenance back to the earlier one rather than silently reviving the expired offer.

### 1.3 Offer state is recipient-specific

If a source sends the same request to multiple people, Atlas must not infer that one person's acceptance or decline determines another person's response. A future implementation may fan one source event into multiple recipient-specific offer envelopes, but the architecture does not require a particular storage shape yet.

### 1.4 Supersession

`superseded` is not required as a canonical offer state. A replacement offer can explicitly reference the earlier offer while the earlier offer becomes withdrawn or expires according to what actually happened. This keeps replacement provenance explicit rather than hiding it in a generic status.

## 2. Responsibility Relation

A Responsibility Relation records that a canonical Person currently or historically carried responsibility for bounded governed reality.

It is conceptually:

```text
Person P
    carries
Governed Target T
    under
Responsibility Effect E
    with provenance/basis B
```

The governed target may be an exact canonical subject or a reusable Governed Scope. The architecture must not require a synthetic work item merely to represent responsibility, and it must not require Organization membership as the Person identity carrier.

A relation does not grant visibility or action authority. Those remain independently resolved.

### 2.1 Establishment basis

For externally-originated responsibility crossing a Person's Atlas boundary, delivery alone is never sufficient establishment basis. Receiver acceptance is required.

Other legitimate establishment bases may exist, such as a Person deliberately adopting responsibility for their own reality, but a future implementation must preserve the real basis rather than manufacturing a fake offer.

Employment or another standing relationship may create an expected intake channel, but it must not be treated as proof that every later item was individually accepted unless the governing relationship explicitly establishes a lawful standing acceptance mechanism. That specialization is not settled by this document.

### 2.2 Responsibility relation states

The canonical lifecycle is deliberately small:

#### `current`

Atlas has sufficient governed basis to treat the Person as presently carrying the responsibility.

This state can arise from any of the accepted responsibility effects already established by the cross-Atlas architecture:

- carrier transfer;
- delegated child responsibility;
- shared participation;
- new requested responsibility.

The effect is a separate semantic dimension from lifecycle state.

#### `completed`

Atlas has sufficient governed basis to treat this Person's responsibility as fulfilled.

A Person saying “done” is not enough merely because they said it. A completion report is a claim/observation with provenance. The relation becomes effectively completed only when the governing reality provides sufficient basis for fulfillment under the relevant work/result/reality contract.

Completion of one Person's responsibility does not necessarily mean the entire underlying subject is complete when responsibility is shared, delegated, or bounded.

#### `released`

The Person no longer carries the responsibility, without representing that the responsibility was fulfilled by completion.

Examples may eventually include legitimate transfer release, mutually accepted relinquishment, relationship termination, cancellation of the obligation, or another governed release basis.

This document does **not** settle who can unilaterally release which responsibilities. A Person's statement “I am no longer responsible” or a sender's statement “you are released” is not automatically effective merely because it was asserted. The applicable relationship, action rules, claims, evidence, and adjudication remain relevant.

### 2.3 `disputed` is not a responsibility lifecycle state

A dispute is a claim about reality, not a magic state transition.

Examples:

- “I never accepted this.”
- “That acceptance was for a different responsibility.”
- “I already completed this.”
- “I was released last week.”
- “This responsibility belongs to someone else.”

Such assertions may be true or false. Therefore they enter the claims/evidence/adjudication layer rather than directly rewriting the Responsibility Relation.

Conceptually:

```text
Responsibility Relation
    stored/effective lifecycle evidence
            +
claims supporting or contradicting that relation
            +
evidence/adjudication when required
            ↓
effective responsibility result
```

A future effective-responsibility resolver should be able to return at least:

- established current;
- established not-current;
- indeterminate.

`indeterminate` is a resolver outcome, not necessarily a stored relation state. Downstream behavior that requires certainty must fail closed when the responsibility question is materially unresolved.

## 3. Acceptance effect remains separate from lifecycle

An accepted offer does not mean one universal “assignment.” The previously settled effect taxonomy remains:

### Carrier transfer

The receiver becomes a carrier of the existing governed responsibility. The source subject remains canonical. A previous carrier is released only if the governing transfer terms legitimately establish that release.

### Delegated child responsibility

The broader carrier retains broader responsibility while the receiver accepts a bounded child responsibility. The child's identity/custody follows the governed reality, not the receiver's Atlas boundary.

### Shared participation

The receiver becomes an additional responsible participant on the same governed subject/Scope. Existing carriers remain unless separately released.

### New requested responsibility

Acceptance establishes genuinely new responsibility reality rather than merely adding the receiver to an existing canonical responsibility. New identity does not imply recipient-local custody; custody follows what actually governs the new commitment.

An accepted response whose effect is materially ambiguous must not be silently coerced into one of these four effects.

## 4. Custody remains independent

Responsibility is not custody.

A Person may carry responsibility for reality governed by another Ledger. Their Atlas may project that responsibility without becoming the authoritative custodian of the underlying subject.

Examples:

- Anna accepts Elm Farm work: Elm-governed work remains Elm-governed.
- A spouse accepts household work: household-governed reality remains household-governed if that is the established custody.
- A vendor accepts a distinct deliverable: the vendor and customer may each hold separate governed subjects correlated across Ledgers.
- A friend accepts a brand-new personal favor: the resulting responsibility may be person-governed if the reality actually belongs there.

Acceptance must never be used as an implicit custody-transfer primitive.

## 5. Visibility remains independent

Delivery of an offer intentionally discloses the offer payload to the intended receiver. That disclosure is real visibility to the sent material.

It does not grant live semantic visibility into the source Ledger or every related fact.

Acceptance also does not automatically broaden visibility. Therefore this remains a valid state:

```text
Person P: responsibility = current
Person P: live source visibility = no
Person P: disclosed offer payload = visible
```

Atlas must preserve that distinction rather than auto-healing it.

## 6. Sender responsibility is not silently released

Sending an offer does not transfer responsibility.

Before receiver acceptance:

```text
sender carries X
sender offers X to receiver
receiver has not accepted

=> sender still carries X
=> receiver does not carry X
```

After acceptance, whether the sender continues carrying X depends on the accepted effect and any legitimate release semantics. Shared participation and delegated child responsibility ordinarily preserve existing broader responsibility. Carrier transfer may release a prior carrier only when the governing transfer actually includes that release.

## 7. Event history and provenance

A future executable model should preserve append-only lifecycle events rather than rewrite history.

The historical story should remain answerable:

```text
A sent the offer.
B received it.
B accepted it.
The accepted effect was shared participation.
B carried it from T1.
B reported completion at T2.
Evidence established fulfillment at T3.
The responsibility relation became completed at T3.
```

Or:

```text
A sent the offer.
B declined it.
No responsibility relation was created.
Employment policy later produced a separate escalation/consequence.
```

The offer record and resulting responsibility relation must remain traceably linked when acceptance is their establishment basis.

## 8. Existing substrate audit

Existing Atlas tables provide useful local precedents but do not solve this generic ontology:

- `organization_access_invitations` already demonstrates a separate request lifecycle with issued/accepted/declined/revoked/expired states, but it is employee-access specific.
- `work_allocations` already distinguishes active/released/completed responsibility-like states, but both sender and assignee are constrained to Organization memberships.
- `organization_responsibilities` and `organization_responsibility_scopes` describe organization standing-responsibility vocabulary, not canonical Person responsibility across Atlas boundaries.
- `institutional_conversation_response_events` supports organization-member handoff events, not generic Person consent.
- `work_item_relations` provides organization-local work topology.
- `ledger_correlations` can relate separate cross-Ledger subjects without merging custody.

The architecture may reuse patterns from these substrates. None is promoted wholesale into the generic Responsibility Offer or Responsibility Relation primitive.

## 9. Query semantics

Atlas must not answer all responsibility questions with one undifferentiated list.

At minimum, future projections must distinguish:

- offers awaiting my decision;
- offers I accepted;
- offers I declined;
- responsibilities I currently carry;
- responsibilities I completed;
- responsibilities from which I was released;
- responsibility relations whose effective standing is indeterminate because of unresolved claims/evidence.

Likewise, “what did I send to Anna?” and “what is Anna responsible for?” are different queries.

## 10. Employment specialization

Employment sits above this primitive.

An employee is not a different class of Person. Employment is a compensated relationship in which a particular business/employer can establish an expected channel for responsibility offers and can attach compensation, scheduling, capacity, performance expectations, escalation, and consequences to how responsibility is taken up.

This does not change the base law:

> delivery is not acceptance.

A future employment contract may support standing acceptance or category-level intake semantics, but those semantics must be explicit, bounded, and attributable to the actual employment agreement. They must not be inferred merely from the word `employee`, an Organization membership, a seat, or a position title.

## 11. Deliberately not executable yet

This document creates no:

- Responsibility Offer table;
- Responsibility Offer event table;
- generic Person↔target Responsibility Relation table;
- Responsibility Relation event table;
- generic target-address schema;
- acceptance/decline RPC;
- release/completion RPC;
- standing employment acceptance policy;
- automatic communication-to-offer interpreter;
- visibility grant;
- custody mutation;
- Company Work rewrite;
- Worker Day migration;
- product UI.

## 12. Next unresolved boundary

The next architectural question is the **standing relationship intake contract**, especially employment:

When a Person has already agreed to a compensated relationship whose purpose is to receive responsibility from a business, what can that prior agreement legitimately pre-authorize?

The architecture must distinguish at least:

- merely receiving offers from the employer;
- an expectation to respond;
- category-level or Scope-level standing acceptance;
- an employer's ability to place an item directly into a worker's current responsibility because that exact intake class was already accepted by contract;
- a worker's continuing ability to reject or exit that responsibility under the governing relationship;
- consequences of refusal, which remain separate from falsely recording acceptance.

No standing-acceptance semantics are settled by this document.
