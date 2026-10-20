# Atlas Build 5 — canonical Person–Ledger standing assignment validation

This candidate is source-only. Do not apply to production from an ad hoc SQL editor.
Use the governed migration generator, disposable schema clone and protected release.

## Baseline evidence to preserve

- The Flower Ledger already has Anna and Marshall represented by active `ledger.seats` links.
- No standing scopes existed when this work was prepared.
- Anna's legacy paid employee-seat record and organizational credential **must remain untouched in this Phase A release**. The credential currently has an ON DELETE CASCADE reference to the employee seat.
- The existing connected-Person offer/acceptance path must continue to work.

## Expected sequence and positive assertions

1. Confirm proposed scope can be created by a signed-in native Ledger owner for **any canonical Person with exactly one active connection**, regardless of whether that Person is an employee, family member, contractor, owner, or accountless.
2. Confirm a proposed scope creates **no Work allocation** and cannot authorize one.
3. As the actual recipient's authenticated canonical Person, accept the scope once. Confirm accepted_by_person_id is the recipient and worker_ledger_seat_id matches the native Ledger connection.
4. Assign existing **source-established, open** Ledger Work under the accepted scope. Confirm exactly one responsible allocation; its assignee_canonical_person_id equals the Person ID, assignee_membership_id is NULL, and establishment_basis_kind is delegated_under_standing_scope.
5. Confirm an ordinary Work item appears in the recipient's Today / self-responsibilities projections; a recipient can report the actual result, and the owner can record a separately attributed witnessed result.
6. Confirm the owner accountability read identifies the same responsible Person. No employee seat, farm membership, or synthesized Worker Day is required.
7. Confirm existing person_connection_receiver_uptake offers, result reporting and historical membership allocations still work unchanged.

## Negative assertions

- Wrong Ledger, foreign organization, unresolved Person ID, inactive/duplicate connection, expired/declined/unaccepted/revoked scope: refuse.
- Manager without active owner authority: refuse.
- Work without verified/owner-attested exact native Ledger relevance: refuse.
- Existing active responsibility or outstanding initial offer: refuse.
- Direct insertion of Person-native allocation without accepted exact scope and owner evidence: trigger refuses.
- Completed Work or source-specific completion policy: never bypass the established result contract.
- Revocation prevents new assignments but does not falsify already assigned historical responsibility.

## Physical legacy removal gate (Phase B — separate migration)

The user requires actual deletion of employee-seat structures. Before dropping `atlas.organization_employee_seats` and its one historical Anna row, first rehome or remove the cascading `atlas.organization_member_credentials.employee_seat_id` dependency **without deleting Anna's live login or access**. Audit and rewrite every runtime reader, writer, access guard, grants, FK, subscription/billing field and app entrypoint. Then prove employee seat references are zero across SQL source, database catalog, and shipped app. Only then submit a separately reviewed destructive migration using the protected release lane. Archiving or simply marking the table obsolete is not completion.
