# Atlas Canonical Person v1

**Status:** Candidate governing architecture
**Date:** 2026-09-12
**Branch:** `feature/atlas-canonical-person-v1`
**Scope:** Establish a canonical Atlas-wide human identity independent of authentication, payment, organization membership, Principal provisioning, and organization-local identity.

## 1. Purpose

Atlas currently has several valid but differently scoped identity carriers:

- `auth.users` — authentication credential/account;
- `atlas.principals` — Personal Atlas / Principal context;
- `atlas.identity_subjects` — institution-local identity subject;
- `atlas.organization_memberships` — relationship between an authenticated user and an organization;
- `atlas.organization_member_credentials` — access credential issued by an organization;
- `atlas.household_members` — household-local human/member record;
- `atlas.user_profiles` — legacy application profile.

None is a canonical Atlas-wide human identity that can exist before login and remain stable across multiple institutions.

The governing correction is:

> **A human exists independently of authentication, Principal provisioning, organization membership, access credentials, payment, and institutional identity. Those objects may refer to the human; none creates the human.**

This contract is the first prerequisite for first-class Ledger identity, multi-Ledger resolution, and domain/site projections such as `feastguild.com`.

## 2. Live audit — 2026-09-12

Production `noel-core` remains materially credential-rooted:

- `atlas.principals.user_id` is `NOT NULL`, unique, and FK → `auth.users(id)` with `ON DELETE CASCADE`.
- `atlas.organization_memberships.user_id` is `NOT NULL`, unique per organization, and FK → `auth.users(id)` with `ON DELETE CASCADE`.
- `atlas.connected_sources.custodian_user_id` is FK → `auth.users(id)` and is one side of the current exclusive user-or-organization custody check.
- `atlas.organization_onboarding_actors.human_user_id`, `atlas.reconstruction_sessions.human_user_id`, and `atlas.implementation_case_participants.human_user_id` are authentication-account references despite representing human participation.
- `atlas.household_members.user_id` is nullable, proving household membership can already exist without login, but no canonical Person object exists to anchor such humans.
- `atlas.identity_subjects` can exist independently of login but is scoped to one organization and therefore cannot serve as the global human root.
- `atlas.organization_member_credentials.auth_user_id` is already correctly modeled as a credential reference and should remain credential-bound.
- no `atlas.people`, `atlas.persons`, or `atlas.parties` canonical identity table exists.

Current row counts at audit time:

- Principals: 1
- Organization Memberships: 4
- Identity Subjects: 140
- Connected Sources: 3
- Organizations: 2
- Organization Onboarding Actors: 0
- Households: 1
- Portfolio Units: 3

These counts make an additive backfill feasible, but the 140 organization-local identity subjects must **not** be auto-collapsed into global people.

## 3. Current application dependency

The current application reinforces the same credential-first ordering:

1. the Personal Atlas public entry enables `shouldCreateUser` only after verified purchase;
2. Personal Atlas setup calls `begin_personal_atlas_self_api_v1` only after access eligibility is established;
3. `begin_personal_atlas_self_api_v1` resolves `auth.uid()`, finds the authenticated email, requires a purchase/setup-sponsor entitlement, then creates `atlas.principals(user_id, ...)`;
4. `atlas_home_identity_self_api_v1` asks whether a Principal exists for `auth.uid()`;
5. `organization_access_self_api_v1` resolves organization access through an active organization-member credential whose `auth_user_id` and membership `user_id` both equal `auth.uid()`;
6. once a Principal exists, the app routes into Personal Atlas before the organization-access branch.

Therefore the migration must preserve existing auth/session behavior while inserting Person beneath it.

## 4. Critical distinction: identity root vs credential/audit evidence

This migration must **not** replace every `*_user_id` foreign key with `person_id`.

Three semantic classes exist.

### 4.1 Human identity / custody roots — migrate toward Person

These columns currently use an auth user where the durable human is the intended referent:

- `principals.user_id` — Principal belongs to a human, not a credential;
- `organization_memberships.user_id` — membership belongs to a human, not a credential;
- personal custody side of `connected_sources.custodian_user_id` — source custody belongs to Person/Principal, not login account;
- `household_members.user_id` where the row represents an actual known person;
- `organization_onboarding_actors.human_user_id`;
- `reconstruction_sessions.human_user_id`;
- `implementation_case_participants.human_user_id`.

These should gain or transition to Person references through staged compatibility work.

### 4.2 Credential/access references — remain auth-bound

These correctly identify the credential used to enter or exercise access:

- `organization_member_credentials.auth_user_id`;
- authentication session resolution through `auth.uid()`;
- invitation acceptance credential evidence;
- login/account-specific commercial claim fields where the field explicitly records the claiming account.

Person does not replace credentials. Credentials bind to Person.

### 4.3 Action/audit provenance — generally remain auth-bound

Columns such as:

- `created_by_user_id`;
- `actor_user_id`;
- `recorded_by_user_id`;
- `adjudicated_by_user_id`;
- `accepted_by_user_id`;
- other explicit authenticated-action provenance;

may correctly preserve which authenticated credential performed an action. They must not be mechanically migrated merely because they reference `auth.users`.

The governing test is:

> **Is this field naming the durable human/entity, or recording the credential/account that performed an authenticated action?**

Only the former belongs to Person identity.

## 5. Canonical Person object

Introduce a first-class canonical human table, provisionally:

```text
atlas.people

id             uuid primary key
stable_key     text unique, generated and immutable
display_name   text
status         text  -- active / retired
metadata       jsonb
created_at     timestamptz
updated_at     timestamptz
```

Rules:

1. `id` is canonical identity.
2. `stable_key` is system-generated; display name is not an identity key.
3. duplicate display names are legal.
4. Person may exist with no auth credential, no Principal, no organization membership, no payment, and no connected source.
5. Person is not deleted merely because a credential, membership, or commercial entitlement ends.
6. retirement preserves identity/history rather than erasing it.

## 6. Credential binding

Introduce a separate binding between Person and authentication account, provisionally:

```text
atlas.person_auth_credentials

id             uuid primary key
person_id      uuid -> atlas.people(id)
auth_user_id   uuid -> auth.users(id)
status         text  -- active / retired
bound_at       timestamptz
retired_at     timestamptz null
provenance     jsonb
created_at     timestamptz
updated_at     timestamptz
```

Required invariants:

- one active `auth_user_id` may resolve to at most one Person;
- one Person may have more than one credential over time;
- credential replacement does not create a new Person;
- credential deletion/revocation must not delete Person;
- application self-RPCs resolve `auth.uid()` → active Person binding before resolving Principal or institution relationships.

A helper such as `atlas.current_person_id_v1()` may provide this resolution after the schema exists.

## 7. Organization-local identity binding

`atlas.identity_subjects` remains institution-local identity truth. It must not be replaced by global Person.

When Atlas has adjudicated that an institutional subject is the same human as a canonical Person, preserve an explicit binding, provisionally:

```text
atlas.person_identity_subject_bindings

person_id             uuid -> atlas.people(id)
identity_subject_id   uuid -> atlas.identity_subjects(id)
organization_id       uuid -> atlas.organizations(id)
status                text
basis                 jsonb
established_at        timestamptz
retired_at            timestamptz null
```

Rules:

- do not infer bindings solely from display name;
- do not collapse organization-local subjects into Person;
- unresolved/candidate identity remains in the existing reconciliation machinery;
- the canonical binding represents an adjudicated relationship, not a fuzzy match;
- a Person may bind to one institutional subject in many organizations.

This allows:

```text
Person: Nathan
  ├── CI identity_subject
  ├── Elm identity_subject
  └── future organization identity_subject
```

without pretending the organizations share one local identity record.

## 8. Principal transition

`atlas.principals` should become Person-owned.

Staged contract:

1. add nullable `person_id` FK → `atlas.people(id)`;
2. backfill every existing Principal through the credential binding created for its current `user_id`;
3. add one-Principal-per-Person uniqueness;
4. update Principal lookup functions to resolve current Person first;
5. keep `user_id` temporarily for compatibility;
6. after all writers/readers use Person, allow `principals.user_id` to become nullable so a Principal can be pre-provisioned before login;
7. ultimately treat `user_id` as legacy credential convenience or retire it after all dependent contracts have moved.

Required proof:

- existing Principal continues to open the same Atlas;
- a Person may exist without Principal;
- a Principal may exist for a Person without an auth credential once the compatibility stage is complete.

## 9. Organization Membership transition

`atlas.organization_memberships` should describe Person ↔ Organization relationship, not credential ↔ Organization relationship.

Staged contract:

1. add nullable `person_id` FK;
2. backfill existing membership rows through current user → Person credential binding;
3. add organization/person uniqueness for active canonical membership;
4. retain `user_id` temporarily for compatibility with existing work-allocation and access paths;
5. update access resolution to use credential → Person → Membership, while `organization_member_credentials` continues to prove the login credential is authorized;
6. later allow organization membership to exist before the person has a credential.

This is necessary for pre-provisioning employees, owners, board members, consultants, and other institution relationships before login.

## 10. Household transition

`household_members.user_id` is already nullable and therefore must not become the Person root.

Add a Person relationship when the household member is a known canonical human. This allows children, spouses, dependents, and other household members to exist as humans without Atlas accounts.

The authenticated account remains optional access evidence rather than household identity.

## 11. Connected-source custody transition

Current `connected_sources` enforces exactly one of:

- `custodian_user_id`; or
- `custodian_organization_id`.

The target distinction is:

- Person-owned source;
- Organization-owned source;
- optionally Organization Unit-owned refinement beneath organization custody.

The personal side should migrate from `custodian_user_id` to `custodian_person_id` (or Principal only if a later custody audit demonstrates Principal, rather than Person, is the true durable owner).

Do not remove the existing constraint until all current source adapters and RLS/read contracts are audited.

## 12. Noncommercial provisioning

Person creation must not require:

- Stripe purchase;
- active subscription;
- organization implementation purchase;
- auth user;
- organization membership.

Commerce grants access/capability to already-existing reality. It does not create the human.

Likewise, organization creation and future Ledger creation must not depend on purchase.

`begin_personal_atlas_self_api_v1` may continue to gate *customer self-provisioning* commercially during compatibility, but the underlying ability to establish Person/Principal must be separable into a noncommercial governed operation so Atlas can preload a human such as Nathan before that human arrives.

## 13. Future credential reconciliation

A pre-provisioned Person must be able to receive a future credential without creating a duplicate Person.

This contract deliberately does **not** authorize silent global email matching.

Future binding may use:

- explicit invitation/prebound identity;
- trusted verified contact evidence;
- controlled reconciliation review when ambiguous;
- explicit practitioner/owner setup authority.

If two candidate people share an email/name or evidence is ambiguous, fail closed into reconciliation rather than auto-merging.

## 14. Compatibility strategy

The first Person migration should be additive.

It should not:

- drop existing `user_id` columns;
- rewrite every auth-user FK;
- change public application routing in the same migration;
- alter payment entitlement semantics;
- activate new organization access;
- auto-link 140 existing organization identity subjects;
- broaden browser privileges;
- change RLS by convenience;
- deploy or change Vercel.

Initial release should establish:

1. Person table;
2. credential binding table;
3. canonical current-person resolver;
4. backfill for existing human accounts needed by current Principal/membership reality;
5. nullable Person links on the narrow identity-root tables selected for tranche 1;
6. consistency guards so legacy `user_id` and new `person_id` cannot contradict one another during dual-write/compatibility;
7. validation proving current behavior still works.

## 15. Backfill rule

Do not create one Person for every row that happens to reference `auth.users`.

For tranche 1, establish one Person for each distinct authenticated human participating in current durable human identity roots, initially derived from the union of current:

- Principals;
- Organization Memberships;
- active Organization Member Credentials where needed to reconcile membership access;
- household self/member rows with authenticated identity where needed;
- setup/implementation human relations if present.

Current production counts are small enough to inspect every created binding during validation.

Backfill uses generated system identity; it must not infer Person identity from display-name uniqueness.

## 16. Required API transition

After the schema seam exists, current self APIs should resolve:

```text
auth.uid()
  ↓
person_auth_credentials
  ↓
Person
  ↓
Principal / Organization Membership / other relationship
```

instead of:

```text
auth.uid()
  ↓
Principal or Membership directly
```

The first target APIs are:

- `atlas_home_identity_self_api_v1`;
- `begin_personal_atlas_self_api_v1`;
- `personal_atlas_access_status_self_api_v1`;
- `current_organization_membership_v1`;
- `organization_access_self_api_v1`;
- organization invitation acceptance/reconciliation;
- onboarding/reconstruction human resolution.

Compatibility may keep their public signatures unchanged while internal resolution changes.

## 17. Acceptance tests

The Person foundation is not complete until all of these pass.

### Existing-user continuity

- current Principal resolves to exactly one Person;
- current Atlas home continues to resolve the same Principal;
- existing organization access remains unchanged;
- no extra user/customer is created.

### Pre-auth Person

- create a Person with no `auth.users` row;
- Person exists validly without Principal, membership, or payment;
- no authentication/account side effect occurs.

### Credential attachment

- attach one authenticated credential to an existing Person through a governed operation;
- repeated attachment is idempotent;
- the same credential cannot bind to two People;
- replacing/retiring a credential does not retire Person.

### Multi-institution human

- one Person can bind to institution-local identity subjects in multiple organizations;
- organization-local identities remain separate records;
- organization membership/access is not created merely by identity binding.

### Collision test

- two People may have the same display name;
- two organizations may have the same display name;
- no suffixing/renaming is needed for identity correctness;
- no fuzzy/display-name match creates a credential or institutional binding.

### Commercial independence

- Person can be established with no purchase;
- commercial access remains separately enforceable;
- ending commercial access does not delete Person.

## 18. Tranche boundary

**Tranche 1 should stop after the canonical Person seam is proven.**

It should not simultaneously introduce:

- first-class Ledger;
- institution-to-institution commercial relationship objects;
- site/domain projection;
- Feast Guild catalogue/order models;
- broad Personal Atlas redesign;
- universal replacement of `auth.users` references.

Those depend on Person, but they are separate authority decisions.

## 19. Next sequence after Person

After Person is released and proven:

1. establish first-class Ledger identity;
2. establish Person ↔ Ledger access/context resolution;
3. establish Organization ↔ Organization relationships;
4. establish domain/site projection;
5. register `feastguild.com` as a Feast Guild Ledger projection;
6. build florist catalogue/order → sourcing reality on those foundations.

## 20. Governing test

Before any field or function is migrated from auth-user identity to Person, ask:

> **Would this fact remain true if the human changed login email, added a passkey, lost an account, or had no login yet?**

If yes, the durable referent is probably Person.

If the fact answers:

> **Which authenticated credential/account performed or authorized this action?**

then the auth-user reference is probably correct and should remain.
