# Atlas Cross-Boundary Responsibility Acceptance Effects v1

## Status

Architecture contract only. No executable schema, migration, RPC, allocation mutation, UI, or production behavior is created by this document.

## Purpose

Define what happens when one Person sends responsibility-bearing reality across another Person's Atlas boundary and the receiver accepts it.

The governing law established elsewhere remains:

- sending an item is an offer, not an assignment;
- receipt creates zero responsibility for the receiver;
- only receiver acceptance creates receiver responsibility;
- employment, marriage, friendship, collaboration, vendor relationships, and ordinary communication are relationship contexts around the same generic responsibility-offer primitive;
- visibility, responsibility, custody, factual truth, and action authority remain distinct.

This document settles the next question: **what kind of responsibility exists after acceptance?**

## Core correction: acceptance effect and custody are independent

The acceptance effect determines the **responsibility/identity shape** that results.

It does **not** mechanically determine Ledger custody.

Custody continues to follow the reality being governed.

Examples:

- Elm Farm work accepted by Anna remains Elm Farm-governed reality even though Anna sees and carries it through her Atlas aperture.
- A household obligation may remain household-governed reality even when one spouse accepts it.
- A genuinely new personal commitment may be person-governed reality.
- A vendor may accept a responsibility related to an Elm subject while the vendor-side commitment is separately governed and correlated to Elm's source reality.

Therefore:

`receiver accepted` does not imply `receiver owns custody`.

`receiver Atlas projection` does not imply `recipient-local canonical work identity`.

## Four canonical acceptance effects

### 1. Carrier transfer

A carrier transfer means:

> the receiver accepts responsibility for the same governed responsibility that another carrier is relinquishing.

The canonical governed subject remains the same unless independent reality requires otherwise.

The receiving Person gains a responsibility relation to the existing subject.

The prior carrier is released only when the transfer terms legitimately include that release. Sending a transfer offer alone never releases the current carrier. Receiver acceptance can complete a sender-initiated transfer when the sender is the carrier who has offered to relinquish that responsibility; it cannot silently release unrelated third-party carriers.

A transfer:

- does not duplicate the underlying work merely because it crossed Atlas boundaries;
- does not move Ledger custody merely because the carrier changed;
- does not grant visibility beyond separately governed visibility;
- does not establish the truth of factual claims bundled with the work;
- preserves transfer provenance and prior responsibility history.

Conceptually:

`same governed subject + old carrier ends + receiver carrier begins`

subject identity and custody remain independently resolved.

### 2. Delegated child responsibility

A delegated child responsibility means:

> the sender remains responsible for a broader outcome while the receiver accepts a bounded responsibility that contributes to it.

This is not a transfer of the parent responsibility.

The accepted responsibility is a distinct responsibility subject or bounded child relation because the receiver is accountable for a separable outcome.

Examples:

- a farm steward remains responsible for event readiness but asks another Person to reset the tables;
- a spouse remains responsible for filing taxes but asks the other spouse to gather donation receipts;
- a business remains responsible to a customer while an outside vendor accepts a bounded delivery obligation.

The child must preserve an explicit relation back to its source/parent reality.

When both parent and child are governed by the same Ledger, an internal child relation may be sufficient.

When the child is governed in a different Ledger, Atlas should preserve a cross-Ledger correlation rather than pretend the two records are one custody object.

Delegation therefore means:

`parent carrier remains + receiver accepts bounded child responsibility`

not:

`parent responsibility moved`.

### 3. Shared participation

Shared participation means:

> the receiver accepts responsibility to participate in the same governed reality while the existing carrier or carriers remain responsible.

No existing carrier is released merely because another Person joined.

The canonical source subject should normally remain one subject. Atlas may establish another Person-to-subject responsibility relation rather than manufacture another authoritative work item.

Shared participation may have different responsibility semantics from primary carriage, but those semantics must be explicit; Atlas must not infer a hidden rank such as `primary user` versus `secondary user` from the mere existence of multiple carriers.

Examples:

- spouses both take responsibility for preparing for guests;
- two employees agree to jointly carry an event setup outcome;
- a collaborator agrees to participate in a deadline without taking over the whole obligation.

Shared participation:

- changes responsibility relations;
- does not automatically change custody;
- does not automatically broaden visibility;
- does not release existing responsibility;
- preserves who accepted and when.

### 4. New requested responsibility

A new requested responsibility means:

> the sender is asking the receiver to take on a new obligation rather than transfer, subdivide, or join an already-existing responsibility.

Acceptance creates a new governed responsibility identity.

The new identity must still be grounded in the reality that actually governs it.

Examples differ materially:

- An Elm employer asks an employee to perform a newly created farm task. The task may be new, but it is still Elm-governed reality, not employee-personal reality.
- A spouse asks the other spouse to handle a household matter. The resulting responsibility may be household-governed.
- A friend emails, `Would you bring dessert?` and the receiver accepts. That may create a new personal commitment in the receiver's Atlas, with the communication retained as provenance.
- A customer asks a vendor for a new deliverable. The sender-side request and vendor-side accepted commitment may be distinct governed realities correlated across Ledgers.

Thus `new` means new responsibility identity, not automatically recipient-local custody.

## Acceptance never means universal source admission

An accepted responsibility may refer to source reality the receiver does not otherwise see.

The receiver may see the responsibility-offer payload because it was intentionally disclosed.

That does not automatically expose:

- the full source Ledger;
- undisclosed source evidence;
- sibling work;
- upstream correspondence;
- future source changes;
- source-private institutional intelligence.

If accepted work requires additional visibility to be executable, that is a separately governed visibility problem. Atlas must not silently solve it by conflating responsibility with visibility.

## Cross-Ledger representation law

When Atlas-native source work already has a canonical governed identity, the receiving Atlas should prefer a projection/reference to that source identity rather than create a competing authoritative copy.

A new recipient-side governed subject is appropriate only when acceptance itself creates a distinct responsibility reality, such as:

- a delegated child obligation;
- a vendor-side commitment governed separately from the customer's source request;
- a genuinely new personal/household/institutional commitment.

Where two governed subjects represent different sides of one cross-boundary commitment, Atlas should correlate them explicitly. Correlation explains relationship; it does not merge custody.

Existing `atlas.ledger_correlations` provides a useful precedent for this separation but is not by this document declared the complete executable responsibility-offer implementation.

## Existing work machinery is compatibility evidence, not the generic ontology

The current schema contains useful local patterns:

- `atlas.work_allocations` distinguishes `responsible`, `participant`, and `approver`, but both assigner and assignee are constrained to memberships inside the same Organization.
- `atlas.work_item_relations` includes `part_of` and `handoff_to`, but both work items are constrained to the same Organization.
- institutional conversation response events can target another Organization membership and bind a Company Work item.
- `atlas.ledger_correlations` can preserve cross-Ledger subject relationship without transferring custody.

These are useful precedents but none is silently promoted into the generic cross-Atlas responsibility model.

## Required provenance

Every accepted responsibility must be explainable later.

At minimum the conceptual history must preserve:

- who sent the offer;
- who received it;
- what was disclosed in the offer;
- any canonical source subject/reference;
- relationship context when known;
- requested acceptance effect;
- receiver acceptance/decline;
- accepted effect actually established;
- any resulting responsibility identity;
- effective custody of resulting governed subjects;
- any release of prior carrier responsibility;
- correlations/parent links created;
- timestamps and provenance for each transition.

The system must be able to distinguish:

`I sent this to you`

from:

`you accepted this`

from:

`I stopped carrying this`

from:

`a new child responsibility was created`

from:

`we now both carry this`.

## No silent effect inference from relationship type

Employment does not imply that every received item is a transfer.

Marriage does not imply shared responsibility.

Friendship does not imply a new personal task.

Vendor status does not imply delegation.

The responsibility effect must be established from the offer/acceptance semantics and governed context, not guessed from a user type or relationship label.

An employer may have a standing expectation that an employee accepts work sent through a defined channel, but that is a contractual/employment expectation. It is not a substitute for accurately recording whether the employee accepted responsibility.

## Ambiguous effect fails closed

If Atlas cannot determine whether an accepted offer is:

- transfer,
- delegated child responsibility,
- shared participation, or
- new requested responsibility,

it must not silently choose a responsibility/custody mutation.

The acceptance itself may be preserved while the responsibility effect remains unresolved until clarified or adjudicated.

The receiver's act of saying `yes` is real; the system's uncertainty about the legal/institutional shape of that `yes` must also remain real.

## Consequence for Scope triage

Scope rerouting and responsibility exchange remain separate.

A broader participant may reroute an addition for coordination without changing who carries the underlying responsibility.

If they want another Person to carry it, Atlas creates/sends a responsibility offer with a proposed effect. The receiver still decides whether to accept.

A broader aperture therefore allows broader coordination; it does not confer the power to make another Person accept responsibility.

## Deliberately not implemented

This contract does not create:

- a generic responsibility-offer table;
- a Person-to-subject responsibility table;
- transfer/release event schema;
- delegated-child schema;
- cross-Ledger commitment schema;
- acceptance RPC;
- decline RPC;
- automatic visibility grants;
- employment auto-acceptance;
- new work-allocation semantics;
- migration of existing Company Work;
- UI behavior.

The executable model should not be materialized until Person-to-governed-subject responsibility identity and acceptance-state semantics are proven against the existing Ledger/custody system.
