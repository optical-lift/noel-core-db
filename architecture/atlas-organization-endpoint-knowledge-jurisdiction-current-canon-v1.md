# Atlas Organization Endpoint Knowledge-Jurisdiction — Current Canon v1

**Status:** Governing architecture for the next Authority Dimensions slice
**Established:** September 20, 2026
**Canonical repository:** optical-lift/noel-core-db
**No production mutation:** this contract creates no migration or grant.

## 1. Problem

Current Organization Communication Endpoint capability resolution still contains one deliberate compatibility shortcut: an active Organization owner implicitly satisfies every Endpoint capability.

That collapses two different authorities:

- root Organization governance: may establish/revoke who has Endpoint authority;
- Endpoint knowledge/action: may view, send, claim, handoff, close, or administer this Endpoint.

For future private, legal, HR, financial, executive, or ethical-wall correspondence, Organization ownership cannot permanently imply knowledge of every message or permission to act through every Endpoint.

## 2. Governing law

**Root Organization governance may govern Endpoint authority without itself constituting Endpoint knowledge or action authority.**

Organization owner != Endpoint viewer != Endpoint sender != response claimant != response handoff authority != Endpoint configuration administrator.

Knowledge and action require explicit Endpoint grants once the compatibility cutover is complete.

## 3. Existing grant carrier remains canonical

atlas.communication_endpoint_member_grants already carries exact capabilities:

- view
- send
- claim
- handoff
- close
- admin

Do not create a second Endpoint permission table.

The repair should add lifecycle meaning to this existing carrier rather than invent another ontology.

## 4. First-class grant basis

Add a first-class grant_basis_kind to future Endpoint grants.

Initial admitted basis kinds:

1. organization_owner_compatibility_cutover
   - one-time materialization of behavior that existed before this cutover;
   - resolves only while the membership remains a present-effective Organization owner;
   - exists so current product behavior is preserved without keeping a permanent owner wildcard.

2. endpoint_creator_initial_grant
   - created atomically when an owner deliberately creates a new Endpoint;
   - explicit Endpoint authority rather than role inference;
   - remains valid while membership is otherwise effective and the grant is active, even if the Person later ceases to be Organization owner.

3. explicit_owner_grant
   - created through the Organization root-governance grant command;
   - remains valid while membership is otherwise effective and grant active until revoked.

Unknown basis kinds fail closed.

## 5. Grant origin is historical evidence

grant_basis_kind is origin/lifecycle evidence and must not be casually rewritten.

If an owner explicitly enables a capability that currently exists only through organization_owner_compatibility_cutover, Atlas should not mutate that row into an explicit grant.

Instead:

1. revoke the active compatibility row;
2. append a new active explicit_owner_grant row;
3. preserve revocation reason and actor;
4. allow the existing active-row uniqueness index to continue enforcing one current capability row.

This preserves the historical distinction:

authority existed because old owner compatibility was being preserved

versus

authority exists because a governing actor explicitly granted it.

## 6. One-time compatibility materialization

Before removing the owner wildcard, the migration should materialize view/send/claim/handoff/close/admin grants for every presently effective owner of every active Organization Endpoint.

Use set-based current data. Do not hardcode the one live production Endpoint or current owner.

Only present-effective Organization owner memberships should be materialized. An administratively active but future-dated or expired owner Membership must not receive current Endpoint authority.

The migration must not materialize Principal-owned Endpoints into Organization Membership grants.

## 7. Compatibility grants must not resurrect

organization_owner_compatibility_cutover is a one-way migration bridge, not a standing rule that can reactivate whenever the same Membership later happens to be an owner again.

If a compatibility-grant Membership undergoes a change that ends the continuity under which old owner behavior was preserved, the compatibility grants must be revoked rather than left dormant for future resurrection.

Relevant continuity-ending changes include:

- role changes away from owner;
- Membership becomes inactive;
- eligibility is explicitly changed so the Membership is no longer present-effective.

Natural passage beyond an eligibility end date makes the grant non-resolving immediately through the capability resolver. If eligibility is later extended/reactivated through an update, that update must not revive the old compatibility basis; the old grant should be revoked and any renewed Endpoint authority must be explicit.

Therefore:

old owner compatibility -> materialized bridge -> continuity ends -> bridge revoked

Later ownership or renewed eligibility -> no automatic Endpoint authority -> explicit grant required.

This preserves the target law that becoming an Organization owner later does not itself create Endpoint knowledge.

## 8. Capability resolution after cutover

After cutover, the membership capability helper should require:

- active Endpoint;
- target membership belongs to the Endpoint Organization;
- Membership is present-effective;
- active grant for the exact requested capability;
- grant basis is recognized;
- compatibility-cutover grant additionally requires current role=owner.

No admin-as-wildcard behavior returns.

No Organization-owner wildcard remains.

The authenticated self helper must compose the same law.

## 9. Root grant governance stays separate

set_communication_endpoint_member_capability_self_api_v1 is currently Organization-owner governed. The cutover may preserve that root-governance rule while removing owner content/action implication.

A Person can therefore be able to administer who gets access without automatically being able to read the Endpoint themselves.

This is the first concrete Atlas proof that governance can exist without knowledge.

## 10. Cross-Organization integrity

communication_endpoint_member_grants currently has independent foreign keys to Endpoint and Membership but no structural same-Organization foreign key.

Current readers happen to join Membership through Endpoint Organization, so a cross-Organization grant row does not authorize access. The writer can nevertheless create a semantically invalid row unless it validates the target.

The grant command must fail closed unless:

- target Membership is active/present-effective in the Endpoint Organization;
- governing actor is authorized for that same Organization;
- capability is admitted.

Do not duplicate organization_id onto the grant table merely to solve this unless clone evidence proves a stronger structural invariant is needed.

## 11. New Endpoint creation

upsert_communication_endpoint_self_api_v1 currently has create and update behavior in one command.

The repaired behavior must distinguish them.

When the Endpoint is newly inserted:

- actor must be a present-effective Organization owner;
- atomically insert initial view/send/claim/handoff/close/admin grants for that creating owner;
- basis = endpoint_creator_initial_grant.

When an existing Endpoint is updated:

- do not silently add any grant;
- updating display name/metadata/state must not become a knowledge-grant side effect.

A Person who later becomes Organization owner gains root grant-governance authority under its own law, but no Endpoint knowledge/action until explicitly granted.

## 12. Revocation

Revocation remains append-preserving state change on the grant row.

Revoking a capability affects that exact grant/capability. It must not imply Membership termination, Position change, Work responsibility release, or Connected Source custody change.

## 13. Configuration without content knowledge

Where an Organization owner needs to govern Endpoint grants or bounded Endpoint configuration, product projections should expose the minimum configuration facts needed for governance without requiring message/body visibility.

Configuration administration != content knowledge.

The first database cutover need not build a new UI, but it must not make content visibility a prerequisite for root grant governance.

## 14. Effective-Time composition

This contract composes with the separate present Organization Membership effectiveness law.

An explicit Endpoint grant must not resurrect authority for:

- future-dated Membership;
- expired Membership;
- inactive Membership.

For compatibility-cutover grants, current owner role is additionally required.

## 15. First executable slice

The first migration should:

1. add immutable grant_basis_kind semantics to communication_endpoint_member_grants;
2. materialize exact compatibility grants for presently effective existing owners on active Organization Endpoints;
3. remove owner wildcard from both capability resolvers;
4. keep capabilities exact; admin is not a wildcard;
5. update new Endpoint creation to issue explicit initial grants only on insert;
6. update grant/revoke command to validate target same-Organization Membership;
7. make explicit enable over a compatibility grant revoke-and-append rather than rewrite grant origin;
8. preserve root owner grant-governance authority separately;
9. preserve Principal Endpoint behavior;
10. make no application deployment or production release as part of source merge.

## 16. Clone acceptance conditions

A future production-schema clone must prove:

1. pre-cutover current owner behavior is preserved through materialized exact grants;
2. ordinary Organization owner with no Endpoint grant cannot view/send/claim/handoff/close/admin;
3. owner can explicitly grant a capability without holding that capability themselves;
4. exact grant does not leak sibling capabilities;
5. admin grant does not imply view/send/claim/handoff/close;
6. compatibility-cutover grant stops resolving if membership ceases to be owner and is revoked on continuity-ending Membership changes so it cannot later resurrect;
7. later restoration of owner role or eligibility does not reactivate old compatibility access;
8. endpoint_creator_initial_grant and explicit_owner_grant remain valid after owner-role change while membership is otherwise present-effective, until revoked;
9. explicit enable over compatibility grant preserves old row as revoked and creates a new explicit grant;
10. new Endpoint creation atomically gives creator explicit initial grants;
11. updating an existing Endpoint does not auto-grant the editing owner;
12. cross-Organization target grant is rejected;
13. inactive/future/expired Membership cannot resolve Endpoint authority;
14. revocation works without rewriting unrelated authority/responsibility;
15. current Correspondence response-responsibility law remains intact.

## 17. Governing result

Organization governance != Endpoint knowledge.

Owner role != implicit content access.

Endpoint administration != sibling action capability.

Grant origin is durable authority evidence.

Explicit exact grant + effective Membership + grant lifecycle = Endpoint capability.
