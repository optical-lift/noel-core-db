# Atlas Company Work Receiver Uptake v1

Status: governing implementation architecture  
Date: 2026-09-25

## Core law

A Person may offer exact Company Work responsibility to another Person. They may not assign that responsibility to the receiver.

~~~text
current exact responsible Person
→ transfer offer
→ responsibility unchanged
→ target Reality Person accepts
→ source allocation releases
→ target self-adopts exact Work
~~~

Therefore:

~~~text
offer != assignment
handoff request != transfer
target visibility != responsibility
sender authority != receiver consent
~~~

## Canonical identities

The offer is between Reality Persons. The source and target Organization Membership UUIDs are retained only as compatibility carriers for the current Company Work storage kernel.

The transfer target must already be a canonical Reality Person. Receiver uptake does not silently promote a legacy Person into Reality.

## Offer authority

Only the current exact active responsible allocation carrier may create a transfer offer for that Work.

Creating an offer changes no Work responsibility. The source allocation remains active until receiver acceptance.

Only one unresolved offer may exist for an exact Work item at a time.

## Acceptance

Only the target Reality Person may accept or decline.

Acceptance is a governed receiver-side self_adoption whose exact source is company_work_responsibility_transfer_offer and the exact offer ID.

The acceptance transaction locks the Work responsibility, verifies that the offered source allocation is still current, releases that source allocation, establishes the receiver's active responsible allocation, and resolves the offer as accepted.

If the Work or source responsibility changed first, the offer becomes stale and no transfer occurs.

## Decline and withdrawal

Decline is target-controlled and changes no responsibility.

Withdrawal is offerer-controlled and changes no responsibility.

Resolved offers are terminal.

## Communication adapter

Institutional communication handoff now terminates at this generic Company Work primitive.

The existing handoff command no longer assigns a target membership. It resolves the target membership only as a compatibility route to its canonical Reality Person and creates a responsibility-transfer offer.

The target's independent acceptance is still required.

Thus communication does not own Work transfer semantics.

## Collaboration boundary

This tranche covers exact responsible-transfer uptake only. Participant/approver collaboration remains fail-closed because that is a different kind of Work participation and should get its own receiver-uptake contract rather than borrowing responsibility-transfer semantics.

## Browser/data boundary

The raw transfer-offer table is RLS-enabled and has no direct SELECT or mutation grants for anon, authenticated, or service_role.

Authenticated access is RPC-only through offer, read-self, respond, and withdraw commands.

## Acceptance criteria

1. An offer can be created only by the exact current responsible Person.
2. The target is a canonical Reality Person.
3. Offer creation leaves the current allocation active.
4. The target can read the outstanding incoming offer.
5. Only the target can accept or decline.
6. Acceptance releases the exact offered allocation and creates receiver self_adoption.
7. The new allocation basis identifies the exact transfer offer.
8. A stale source allocation cannot be transferred.
9. Decline and withdrawal do not alter responsibility.
10. Communication handoff creates an offer rather than an assignment.
11. Endpoint handoff capability is not transfer authority.
12. The receiver may subsequently exercise exact Work responsibility, including completing communication response Work.
13. No legacy Person is permanently promoted merely to satisfy validation.

## Production receipt — 2026-09-25

Production migrations:

- 20260925161751_atlas_company_work_receiver_uptake_v1.sql
- 20260925162013_atlas_company_work_receiver_uptake_fk_indexes_v1.sql

Production rollback proof temporarily promoted the second Elm legacy Person into Reality only inside a transaction. Lex claimed a real unclaimed communication response case and created a transfer offer. The offer left Lex's active responsibility unchanged. The target Reality Person read and accepted the offer, which released Lex's exact allocation and established the target's self_adoption allocation sourced from the exact transfer offer. The target then completed the same response Work. The transaction rolled back completely.

Post-rollback production confirms no temporary Reality Person, auth binding, transfer offer, proof Work, or proof response binding persisted, and the proof response case remains unclaimed.

Direct raw table access remains denied to authenticated and service_role. The four receiver-uptake self RPCs are authenticated-only and service_role is denied direct execute.
