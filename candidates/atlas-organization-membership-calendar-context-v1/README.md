# Organization Membership Calendar Context v1 candidate

Effective Time Phase A candidate packet for issue #874.

This directory is intentionally **not** a migration. The repository's Supabase CLI must generate the eventual migration identity; only then should `candidate.sql` be promoted into `supabase/migrations/<generated>_atlas_organization_membership_calendar_context_v1.sql`.

## Scope

The candidate adds only the missing institutional civil-calendar source for Organization Membership eligibility:

- append-preserving Membership Calendar Context;
- one active context per Organization;
- exact timezone validation against PostgreSQL timezone names;
- setup-actor / Principal root-governing provenance;
- internal exact current-context and civil-date resolvers;
- governed establish/supersede command;
- one explicit Elm Farm `America/Chicago` compatibility adjudication.

It does **not** change present Membership, owner, Endpoint, Connected Source, employee, invitation, or Work authority.

## Validation order

On a disposable production-schema clone:

1. restore production role + user-schema graph;
2. apply `fixture.sql`;
3. apply `candidate.sql`;
4. run `postconditions.sql`;
5. compare baseline vs candidate Atlas lint/advisor findings.

No candidate SQL should be executed against production to validate it.
