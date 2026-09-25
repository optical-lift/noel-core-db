# Atlas Company Work Collaboration Receiver Uptake v1

Status: governing implementation architecture  
Date: 2026-09-25

## Core law

Company Work collaboration is receiver-established participation.

```text
current exact responsible Person
→ offers participant / approver participation
→ no collaboration allocation yet
→ target Reality Person accepts
→ receiver-established participant / approver allocation becomes active
```

Responsibility does not move.

```text
offer != participation
participation != responsibility
source visibility != participation
sender choice != receiver consent
```

## Offer authority

Only the current exact active responsible allocation carrier may offer participant or approver participation on open Work.

The offer names the exact responsible allocation from which it arose. If that source responsibility changes before acceptance, the offer becomes stale.

A Person may not use this primitive to offer themselves a second collaboration role on Work for which they already carry exact responsibility.

## Target identity

The target is a canonical Reality Person.

Legacy Organization Membership UUIDs remain only compatibility carriers for the current Company Work storage kernel. The offer is semantically Person-to-Person.

Receiver uptake never silently promotes a legacy Person into Reality.

## Acceptance

Only the target Reality Person may accept or decline.

Acceptance creates an active `participant` or `approver` Work allocation with:

- `establishment_basis_kind = receiver_acceptance`;
- source kind `company_work_participation_offer`;
- the exact offer ID;
- actor membership equal to the receiver's own compatibility carrier;
- immutable establishment provenance.

The receiver therefore establishes their own participation. The offering Person never assigns the target.

## Distinction from responsibility transfer

Responsibility transfer and collaboration uptake are siblings, not aliases.

Responsibility transfer releases the prior exact responsible allocation and establishes receiver `self_adoption` responsibility.

Collaboration uptake leaves the current exact responsible allocation untouched and creates a separate participant/approver allocation.

## Decline, withdrawal, and release

Decline is target-controlled and creates no allocation.

Withdrawal is offerer-controlled and creates no allocation.

After acceptance, the collaborator may self-release. The exact responsible Person may also release that collaboration through the existing governed removal path.

Releasing collaboration does not release or transfer exact responsibility.

## Communication adapter

Institutional communication collaboration now terminates at the generic Company Work participation-offer primitive.

The communication adapter adds one domain-specific carrier constraint: the target must already be able to view the source Communication Endpoint.

That visibility check does not create Work authority. It only ensures a Person offered communication-response collaboration can inspect the source correspondence.

The generic Company Work collaboration primitive does not mint communication visibility and does not depend on communication endpoint authority.

```text
source visibility may constrain a communication collaboration offer
but
source visibility does not create Work participation
and
Work participation does not create source visibility
```

## Work allocation provenance

`work_allocations.establishment_basis_kind` / `establishment_basis` now support both exact responsibility establishment and collaboration establishment.

Responsibility retains its existing governed basis kinds. Participant/approver allocations may become active only through the new `receiver_acceptance` basis.

There were zero participant/approver allocations in production at cutover, so this rule required no historical rewrite.

## Browser/data boundary

The raw participation-offer table is RLS-enabled and has no direct SELECT grant for anon, authenticated, or service_role.

The offer, read-self, respond, and withdraw membranes are authenticated-only `SECURITY DEFINER` RPCs. Service role direct execute is denied.

## Production receipt — 2026-09-25

Production migration:

- `20260925192731_atlas_company_work_collaboration_receiver_uptake_v1.sql`

Rollback proof used a real unclaimed institutional response case and temporarily promoted the second Elm legacy Person into Reality only inside the transaction.

The proof established:

1. communication collaboration to that target was refused because the target lacked source-endpoint visibility;
2. Lex self-claimed the exact response Work;
3. Lex created a generic participant offer;
4. the offer created no participant allocation and left Lex exactly responsible;
5. the target Reality Person read and accepted the offer;
6. acceptance created a receiver-established participant allocation sourced from the exact offer;
7. Lex remained the exact responsible Person;
8. the participant self-released;
9. participant release did not affect Lex's responsibility;
10. the entire proof rolled back.

Post-rollback production confirms:

- no temporary Reality Person persisted;
- no temporary Auth binding persisted;
- zero participation offers persisted;
- zero active participant/approver allocations persisted;
- the proof response case remains `unclaimed`;
- no proof response Work binding persisted.

## Acceptance criteria

1. Direct participant/approver assignment remains impossible.
2. Only the exact responsible Person may offer participation.
3. Offer creation creates no Work allocation.
4. Target is a canonical Reality Person.
5. Only target may accept or decline.
6. Acceptance creates receiver-established participant/approver participation.
7. Exact responsibility remains unchanged.
8. Establishment provenance identifies the exact offer.
9. Stale source responsibility prevents later uptake.
10. Collaboration release does not release responsibility.
11. Communication visibility is a separate carrier constraint.
12. Communication visibility cannot itself create Work participation.
