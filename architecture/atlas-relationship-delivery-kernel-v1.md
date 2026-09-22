# Atlas Relationship Delivery Kernel v1

## Status

Executable source contract. This architecture is implemented by:

- `supabase/migrations/20260921154500_atlas_relationship_delivery_kernel_v1.sql`;
- `validation/migrations/20260921154500_atlas_relationship_delivery_kernel_v1.sql`.

It operates under Atlas Product decision `PMD-024`.

## Governing law

> **Source domains own reality. A governed relationship identifies the recipient. Relationship Delivery carries only bounded projection/response contracts through revocable possession.**

Relationship Delivery is not a task ontology and does not collapse institutional and household reality.

The kernel separates:

`Person ≠ source relationship ≠ delivery grant ≠ bootstrap credential ≠ session ≠ projection contract ≠ response contract ≠ source consequence`.

## Universal kernel

The source-independent primitives are:

- `atlas.relationship_delivery_grants`;
- `atlas.relationship_delivery_bootstrap_credentials`;
- `atlas.relationship_delivery_sessions`.

A grant identifies one canonical `Person`, a validity window, named/versioned projection adapters, named/versioned response adapters, and issuance/revocation provenance.

The contract arrays are adapter admission, not an action-permission vocabulary. A source adapter must still prove that the requested read/write is lawful under its own canonical reality.

Bootstrap and session tables persist only cryptographic hashes. Raw possession secrets are returned once through service-only functions and must remain server-side except for the recipient's bearer/session carrier.

## Typed relationship adapters

The universal grant does not use a free-form polymorphic `relationship_type + relationship_id` pointer.

V1 provides:

`atlas.relationship_delivery_institution_bindings`

which has a real foreign key to one `Institutional Person Record`.

This preserves:

`grant.recipient_person_id = institutional_person_record.person_id`.

A future Household delivery tranche should add a separately typed Household binding over the same universal grant/session kernel. It must not turn Household Member into an Institutional Person Record or route household responses through Company Work.

## Institutional issuance

`atlas.issue_institutional_relationship_delivery_service_v1(...)` is service-internal infrastructure.

It assumes an upstream Organization/source authority has already decided that the named Institutional Person Record may receive the requested delivery adapters. The function itself is not a manager permission model.

It:

1. requires an active Institutional Person Record and active canonical Person;
2. normalizes bounded projection/response contract names;
3. creates the grant and typed institutional binding;
4. generates one cryptographically random bootstrap secret;
5. stores only its SHA-256 hash;
6. returns the raw bootstrap secret once.

No `auth.users` row, Organization Membership, Personal Atlas, responsibility, Position, Company Work allocation, or permission is created by issuance.

## Redemption and session

`atlas.redeem_relationship_delivery_bootstrap_service_v1(...)` consumes the bootstrap exactly once.

Before issuing a session it revalidates:

- bootstrap state and expiry;
- grant lifecycle/window;
- supported typed relationship;
- active Institutional Person Record;
- active canonical Person.

The returned session token is random and only its hash is stored.

`atlas.relationship_delivery_session_context_service_v1(...)` resolves possession server-side and revalidates all of those boundaries again. Relationship retirement therefore closes future reads/writes even when a session row has not yet been explicitly revoked.

## Source adapters

Source-domain delivery functions must call the internal session/contract resolver and then continue through their own truth authority.

Institutional example:

`session → admitted company_work.worker_day.v1 projection → Company Work/Worker Day source read`.

Response example:

`session → admitted company_work.result_report.v1 response → canonical Company Work result command → result acceptance/completion consequence`.

There is no generic `done` mutation in this kernel.

Household example later:

`session → admitted household grocery projection → Household source truth`.

The shared code stops at delivery admission.

## Revocation

`atlas.revoke_relationship_delivery_grant_service_v1(...)` prospectively closes the delivery grant and active possession carriers.

It deliberately does not retire the Person, relationship, Position, responsibility, source Work, household requirement, or result history.

Delivery lifecycle is therefore independently revocable.

## Security

- all kernel tables have RLS enabled;
- direct table grants are revoked from `anon`, `authenticated`, and `service_role`;
- public/authenticated clients execute none of the service functions;
- service functions are `SECURITY DEFINER` with pinned search paths;
- service role is only a server-side caller;
- browser/app code must never receive a Supabase service secret;
- friendly URLs such as `/anna` are locators, not credentials.

A fresh Atlas route should exchange a bootstrap secret server-side, place only the resulting delivery session in an HttpOnly/Secure/SameSite cookie, remove bearer material from the visible URL, and call typed source adapters thereafter.

## Scale

The primitive does not change with organization size.

A household may have a handful of grants; Elm may have several; a large enterprise may have hundreds of thousands. Scale should be handled by policy-driven/set-based issuance and source projections, not route-specific code or per-recipient ontology.

## Current first adapter

The first typed relationship is institutional because Anna is the first production proof.

That does not make the kernel an employee system.

The universal proof remains incomplete until a non-account Household Member can receive and respond to Household-owned reality through the same grant/credential/session kernel with a Household-specific binding and source adapters.

## Transitional boundaries

Current Company Work exact responsibility remains membership-bound at its existing writer. This migration does not reinterpret “manager selected Person” as canonical responsibility.

Current authenticated Worker Day/result APIs remain valid.

The Anna-specific pilot capability remains transitional evidence and is not reused as this kernel.

The next institutional delivery tranche should adapt existing Company Work reads/results to an admitted Institutional Person Record while reusing canonical source result/completion logic instead of duplicating it.

## Resulting law

> Atlas can securely hand a bounded piece of governed reality to a real human who owns no Personal Atlas and has no ordinary Atlas login. Possession proves access to the delivery grant only. The typed relationship remains source-owned, the source domain remains canonical, and every consequential response must still satisfy the source domain's own law.
