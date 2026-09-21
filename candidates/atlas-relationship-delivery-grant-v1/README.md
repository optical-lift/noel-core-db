# Relationship Delivery Grant v1

Status: **inert candidate; not migration-identified, not clone-validated, not released**.

This candidate implements only the durable grant primitive selected by Atlas Product Map `PMD-024`.

## What it adds

- `atlas.relationship_delivery_grants`
- `atlas.relationship_delivery_grant_contracts`

The grant binds one canonical `atlas.people` Person to:

- an issuer source address;
- a source-owned relationship address;
- a validity/revocation window;
- named versioned projection and response contracts.

## What it deliberately does not add

- no employee-specific FK;
- no household-specific FK;
- no `auth.users` dependency;
- no credential or bearer secret;
- no session;
- no Worker Day reader;
- no generic completion writer;
- no browser RPC;
- no production data.

The source relationship still owns whether the relationship is real and effective. A later issuance adapter must validate that source relationship before writing a grant, and every delivery adapter must revalidate it when the grant is exercised.

## Cross-domain proof

Disposable-clone postconditions create:

1. one institutional-shaped grant:
   - relationship `organization / organization_membership`;
   - projection `institution.worker_day.today v1`;
   - response `institution.company_work.result v1`;

2. one household-shaped grant:
   - relationship `household / household_member`;
   - projection `household.grocery.current v1`;
   - response `household.grocery.result v1`.

Both use the same canonical Person and same tables.

The postconditions also fail if the universal grant table contains organization-, employee-, household-, or auth-specific identity columns.

## Security

Both tables:

- enable RLS;
- revoke direct `PUBLIC`, `anon`, and `authenticated` access;
- expose no executable browser function in this tranche.

This matches the current Supabase security rule that server-owned privileged data must not rely on browser-side service credentials or implicit function/table grants.

## Generation

If the candidate is accepted:

1. merge the inert candidate source;
2. use the governed Migration Source Generation workflow;
3. independently run Production Schema Clone Validation on the generated migration;
4. merge generated source only after the clone gate passes.

No production release is authorized by this candidate.
