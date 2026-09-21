# Reality Sentence Establishment v1 — validation contract

**Status:** source validation plan; no production mutation  
**Candidate branch:** `feature/reality-sentence-establishment-v1`  
**Prerequisite:** Institutional Person Record migration must be released before canonicalization.

The future canonical migration must prove the following against a disposable production-shaped clone.

## Candidate custody

- existing `implementation_establishment_items` rows survive unchanged;
- `reality_sentence` is additive;
- direct browser table writes remain denied;
- generic `save_implementation_establishment_item_self_api_v1` still cannot create a Reality Sentence because its own accepted category list remains narrower;
- all new public browser functions are unavailable to `anon`;
- all substantive authorization is rechecked inside Atlas functions.

## Candidate before truth

Create an assigned practitioner + open Implementation Case + root Ledger binding.

Create:

`Anna occupies Farm Steward.`

as a `manual_structured` Reality Sentence candidate.

Before promotion prove:

- one new Implementation establishment item exists;
- zero new Person rows;
- zero new Institutional Person Records;
- zero new Organization Units;
- zero new Positions;
- zero new Responsibilities;
- zero new Position↔Responsibility rows;
- zero new Position Appointments;
- candidate status is `proposed`;
- no canonical consequence receipt exists.

## Identity proof

### Explicit new Person

Preview:

`Sarah is known to Example Organization.`

with:

```json
{
  "organizationId": "<example-org>",
  "identityMode": "new_person",
  "displayName": "Sarah"
}
```

Prove preview says `ready` and creates nothing.

Promote and prove exactly:

- one Canonical Person is created;
- one Institutional Person Record is created;
- zero `auth.users`;
- zero Person Auth Credentials;
- zero Organization Memberships;
- zero employee seats;
- zero Personal Atlas grants;
- zero Positions;
- zero Responsibilities.

### Existing Person

Create a second organization and reuse the same explicit `personId`.

Prove a second Institutional Person Record can be established without creating a second Person.

### Same-name ambiguity

Create two unrelated canonical people both named `Jordan`.

Prove a Reality Sentence with `identityMode='existing_person'` requires an explicit Person id.

Prove `identityMode='new_person'` creates a third Person named Jordan rather than silently merging by display name.

## Organization Unit proof

Establish:

`Example Organization has Production.`

Prove:

- exact Organization custody;
- explicit Unit kind;
- parent, when supplied, must be active in the same Organization;
- identical stable-key + identical semantics is idempotent;
- stable-key collision with different name or kind fails closed;
- no Position or Responsibility is created as a side effect.

## Position proof

Establish:

`Farm Steward exists in Production.`

Prove:

- Position requires an active exact Organization Unit;
- title is data, not a platform type;
- same stable-key + same semantics is idempotent;
- stable-key collision with different title/kind fails closed;
- no occupant, authority, seat, permission, or Company Work allocation is created.

Repeat with an unrelated title such as `Executive Director` to prove no farm vocabulary dependency.

## Responsibility proof

Establish:

`Production stewardship is a responsibility of Example Organization.`

Prove:

- same stable-key + same semantics is idempotent;
- stable-key collision with different semantics fails closed;
- no Person assignment or Company Work is created.

## Position ↔ Responsibility proof

Establish:

`Farm Steward carries Production stewardship.`

Prove:

- both canonical records belong to the same Organization;
- identical relation is idempotent;
- conflicting relationship kind fails closed;
- relation creates no Position Appointment and no Company Work allocation.

## Appointment proof

Establish:

`Sarah occupies Farm Steward.`

using the accountless Sarah Institutional Person Record.

Prove:

- no auth user exists for Sarah;
- no Organization Membership is required;
- no employee seat is required;
- no Personal Atlas is created;
- active Position + active Institutional Person Record must share Organization;
- same active relation/kind is idempotent;
- cross-Organization Person/Position mixing fails closed.

## Implementation scope proof

Create two Organizations and two Ledgers.

Bind the test Implementation Case only to Organization A's root Ledger scope.

As the assigned practitioner prove:

- Organization A candidate preview may become `ready`;
- Organization B candidate preview returns `outside_implementation_scope`;
- no Organization B domain mutation is possible;
- an unbound Implementation Case cannot establish either Organization's structure;
- a non-assigned practitioner cannot preview or promote the candidate.

## Organization birth boundary

Create an `organization.establish.v1` candidate.

Prove practitioner preview returns:

`requires_principal_self_establishment`

and does not call `establish_organization_ledger_self_api_v1` on behalf of the customer.

This proves implementation commerce/practitioner assignment does not manufacture Principal authority.

## Canonical receipt proof

Promote each supported practitioner operation.

For every established item prove:

- `status='established'`;
- `resolution_state='established'`;
- `canonical_consequence` is non-empty;
- `established_by_user_id` is the practitioner;
- `established_at` is populated;
- command receipt names the operation key and canonical consequence kind.

Attempt to mark a Reality Sentence established without a receipt and prove the guard rejects it.

Attempt to rewrite an established operation/bindings/receipt and prove the guard rejects it.

## Canonical rerender proof

After establishing:

`Sarah occupies Farm Steward.`

change canonical Position title through a separately governed test-only setup step to:

`Operations Steward`.

Prove the established Reality Entry rerenders:

`Sarah occupies Operations Steward.`

while the original authored sentence remains preserved as provenance.

This proves the Workbench is not a shadow text database.

## Machine/manual convergence proof

Create two candidates for the same operation:

1. `manual_structured`;
2. `machine_proposed` from an accepted `implementation_finding`.

Prove both reach the same preview/establishment command path.

Prove a rejected/unaccepted finding cannot be used as `source_finding_id`.

## No-side-effect audit

After the complete synthetic proof, assert no unexpected delta in:

- `auth.users`;
- `atlas.person_auth_credentials`;
- `atlas.organization_memberships`;
- `atlas.organization_employee_seats`;
- `atlas.personal_atlas_access_grants`;
- `atlas.work_items`;
- `atlas.work_allocations`;
- generic task tables.

Only the exact canonical reality named by the accepted Reality Sentences may change.

## Security/lint

Run the repository's production-schema-clone validator and compare baseline/post-candidate lint.

Candidate must introduce no new security or performance errors.

Review every new `SECURITY DEFINER` function for:

- fixed search path;
- no `anon` execution;
- exact practitioner/case/scope checks for browser mutations;
- no browser-supplied Organization id trusted without independent scope verification.

## Rollback

All behavioral validation writes run in a transaction and finish with:

`ROLLBACK;`

The production release gate remains separate from source merge and validation.
