# Atlas Person-First Organization and Ledger Establishment v1

**Status:** Governing architecture candidate
**Date:** 2026-09-13
**Depends on:** Atlas Canonical Person v1
**Immediate proving case:** Feast Guild

## 1. Purpose

Define the canonical path by which a real organization becomes governable in Atlas without making authentication, payment, one legacy root organization, or a storefront-specific account model the source of institutional reality.

The governing order is:

```text
Person
  ↓
Principal authority
  ↓
Organization
  ↓
Ledger
  ↓
relationships / authority / access
  ↓
operating reality
```

The central law is:

> **A canonical Person exercising Principal authority establishes an Organization and its governing Ledger. Authentication proves access to that authority; it does not create the person, the authority, the organization, or the Ledger.**

## 2. Why this is required now

Current production has mature organization primitives but still resolves durable human and organization access directly from `auth.uid()` in important paths.

Examples include:

- `current_principal_id_v1()` → `principals.user_id = auth.uid()`;
- `current_organization_membership_v1(...)` → `organization_memberships.user_id = auth.uid()`;
- `establish_organization_self_api_v1(...)` → authenticated credential creates Organization + owner Membership;
- `begin_organization_onboarding_self_api_v1(...)` → authenticated credential creates Organization + setup actor + reconstruction session.

Current production also contains organization-scoped Ledger projections (`organization_ledger_entries`, `organization_ledger_subjects`, owner read APIs), but does not yet have a general first-class Ledger identity that is independently addressable from Organization.

That means Atlas currently approximates:

```text
Organization ≈ Ledger namespace
```

The intended architecture is:

```text
Person
  ↓
Principal
  ├── Organization A → Ledger A
  └── Organization B → Ledger B
```

Canonical Person is therefore a prerequisite for first-class Ledger identity and multi-Ledger resolution, not a parallel concern.

## 3. Canonical Person prerequisite

This architecture adopts the Canonical Person law:

> **A human exists independently of authentication, Principal provisioning, organization membership, access credentials, payment, and institutional identity. Those objects may refer to the human; none creates the human.**

Consequences:

1. Organization establishment must ultimately resolve the acting human through credential → Person.
2. Principal authority belongs to Person, not to a login credential.
3. Organization Membership belongs to Person, not to a login credential.
4. People may exist before login, invitation acceptance, payment, or organization onboarding.
5. Credential replacement must not create a new human.
6. Ending access must not erase the Person or institutional relationship history.

## 4. Person, Principal, Organization, and Ledger are distinct

### Person
The durable human identity.

### Principal
The Person's root ownership/governance authority in Atlas.

Principal is not synonymous with one organization.

### Organization
The institution itself.

Organization answers:

> What institution is this?

### Ledger
The canonical institutional address for that organization's governed reality.

Ledger answers:

> What canonical institutional reality belongs here?

An Organization may exist before substantial operating reality exists. Its Ledger may therefore initially be almost empty and still be valid.

## 5. First-class Ledger root

Introduce a canonical Ledger identity rather than continuing to infer Ledger scope from `organization_id` everywhere.

Conceptual minimum:

```text
atlas.ledgers

id                uuid primary key
stable_key        text unique
organization_id   uuid -> atlas.organizations(id)
ledger_kind       text
status            text
metadata          jsonb
created_at        timestamptz
updated_at        timestamptz
```

Initial governing rules:

- one primary governing Ledger per ordinary Organization in v1;
- Ledger identity is durable and independently addressable;
- Ledger creation is noncommercial;
- Ledger retirement preserves institutional history;
- organization-scoped legacy contracts may continue through compatibility views/functions while consumers migrate to `ledger_id`;
- `organization_id` remains meaningful as institutional identity and must not be mechanically replaced everywhere by `ledger_id`.

## 6. Principal authority must become multi-organization

Legacy `principals.organization_id` or equivalent single-root assumptions must not remain the semantic answer to "which institution belongs to this Principal?"

Target relationship:

```text
Person
  ↓
Principal
  ↓ authority over
Ledger(s)
```

A Principal may govern:

- Elm Farm Ledger;
- Feast Guild Ledger;
- Atlas/Optical Lift Ledger;
- future organizations.

Authority should be represented explicitly rather than inferred from whichever organization row currently contains the Principal.

## 7. Authentication is access evidence

The compatibility resolution path should become:

```text
auth.uid()
  ↓
person_auth_credentials
  ↓
Person
  ↓
Principal / Organization Membership / delegated authority
  ↓
Ledger
```

instead of:

```text
auth.uid()
  ↓
Principal or Membership directly
```

Public API signatures may remain compatible while internal resolution changes.

First compatibility targets after Canonical Person:

- `current_principal_id_v1()`;
- `current_organization_membership_v1(...)`;
- `organization_access_self_api_v1()`;
- `atlas_home_identity_self_api_v1()`;
- `begin_personal_atlas_self_api_v1()`;
- organization invitation acceptance/reconciliation;
- organization onboarding human resolution.

## 8. Organization establishment is noncommercial

Organization and Ledger birth must not depend on purchase.

Separate two events:

```text
establish institutional reality
```

from:

```text
grant paid Atlas capability / entitlement
```

Stripe or another payment system may grant access/capability to an already-existing Organization or Ledger. It must not be the ontology event that causes the institution to exist.

Therefore a Person with lawful Principal authority must be able to establish an Organization + Ledger without a payment transaction.

Commercial acquisition flows may remain as product-entry workflows, but they must call the same noncommercial institutional establishment contract rather than owning Organization birth.

## 9. Organization establishment contract

Target governing operation:

```text
establish_organization_ledger(...)
```

Conceptual transaction:

1. resolve authenticated credential to canonical Person when a credential is present;
2. resolve lawful Principal authority for that Person;
3. create Organization;
4. create its governing Ledger atomically;
5. establish Principal → Ledger root authority;
6. optionally establish the creating Person's Organization Membership if the institutional model requires one;
7. establish onboarding/setup actor as Person-based participation;
8. create any required clean-room reconstruction/onboarding session;
9. return Organization + Ledger + authority identities.

Failure must not leave an Organization without its governing Ledger or a Ledger without an Organization.

## 10. Pre-auth and pre-login humans

Organization onboarding must allow real people to exist before they have Atlas credentials.

Example:

```text
Person: Nathan
Organization relationship: Feast Guild
Responsibility: purchasing
Credential: none yet
```

Later:

```text
verified credential arrives
  ↓
governed reconciliation
  ↓
bind credential to existing Person
```

Do not create a second Person because login happened later.

## 11. Organization Membership is Person ↔ Organization

Target meaning:

```text
Person
  ↔
Organization Membership
  ↔
Organization
```

Credentials prove access to that relationship; they are not the relationship itself.

Compatibility columns such as `organization_memberships.user_id` may remain during staged migration, but durable membership identity moves toward `person_id`.

## 12. Institutional identity remains local

Canonical Person does not replace organization-local `identity_subjects`.

Target model:

```text
Canonical Person: Anna
  ├── Elm identity_subject
  └── another organization's identity_subject
```

A future binding must be explicit and adjudicated.

Do not globally bind Person ↔ institutional subject from display name or loose email similarity.

Ambiguity fails closed into reconciliation.

## 13. Onboarding actors become Person-based

Rows representing a human participant in onboarding, reconstruction, implementation, or setup should migrate toward Person identity.

Distinguish:

```text
human participant → Person
```

from:

```text
authenticated action provenance → credential/auth user evidence
```

The human who participated and the credential that performed a specific action are separate facts.

## 14. Connected-source custody

Durable source custody should eventually distinguish:

```text
Person-custodied source
Organization-custodied source
```

Personal custody should move away from raw auth-user identity toward Person (or a narrower Principal relationship only if a separate custody audit proves Principal is the correct owner).

Organization sources remain organization-custodied.

This is downstream of Canonical Person tranche 1 and need not block first Ledger creation unless the establishment flow directly depends on source custody.

## 15. Onboarding sequence

A new organization's lifecycle should become:

```text
Canonical Person exists
  ↓
Principal authority resolves
  ↓
Establish Organization
  ↓
Establish governing Ledger atomically
  ↓
Establish root Principal authority
  ↓
Establish organization infrastructure
  ↓
Pre-provision / connect people
  ↓
Establish responsibilities
  ↓
Establish delegated authority
  ↓
Connect existing institutional sources
  ↓
Establish external relationships
  ↓
Generate initial Company Work
  ↓
Show live Ledger
  ↓
Normal operation
```

The flow must not require a complete org chart, all integrations, all contacts, or every business field before the institution becomes usable.

## 16. Onboarding completion means governability

Do not define onboarding completion as profile completion.

An Organization/Ledger is operationally onboarded when Atlas can answer enough of the following to govern real activity:

- What institution is this?
- What Ledger owns its institutional reality?
- Which Person/Principal ultimately governs it?
- Which People are related to it?
- Who is responsible for known work?
- What delegated authority exists?
- What existing systems/sources contain relevant reality?
- What relationships exist with outside organizations/people?
- What Company Work currently needs to happen?
- Where does a decision go when normal delegated authority ends?

Unknown information may be learned during normal operation.

## 17. Feast Guild proving case

Feast Guild should prove the architecture without requiring the flower-commerce kernel to be implemented first.

Target initial state:

```text
Person
  ↓
Principal
  ↓
Feast Guild Organization
  ↓
Feast Guild Ledger
```

A valid first Ledger may contain only:

- institutional identity;
- Principal/root authority;
- domain relationship for `feastguild.com`;
- initial institutional communication endpoint when established;
- first Organization relationships;
- first Company Work.

It does not need flower inventory, admitted supply, catalogue, pricing, procurement, cooler, or delivery modules to be a legitimate institution.

Those domain capabilities attach later to the Feast Guild Ledger.

## 18. Legacy Feast Guild / Elm separation rule

Current production historically used a Feast Guild organization row as a container for some Elm/Farm reality.

Do not clean that history by delete/recreate or by inventing a second canonical Feast Guild identity without adjudication.

The safe sequence is:

1. establish Canonical Person;
2. establish first-class Ledger identity and multi-Ledger Principal authority;
3. inventory all institutional records currently scoped to the existing Feast Guild organization;
4. classify each record as Elm, Feast Guild, portfolio/shared, unresolved, or historical compatibility evidence;
5. migrate institutional custody to the correct Ledger while preserving original IDs/evidence where technically possible and preserving explicit migration provenance otherwise;
6. only after that adjudication may the existing Feast Guild organization become the clean Feast Guild institution.

No organization-scope cleanup should be justified merely by names.

## 19. Implementation tranches

### Tranche A — Canonical Person
Release and prove Canonical Person tranche 1 without changing public routing.

### Tranche B — Person-first resolution
Move internal Principal/Membership resolution to credential → Person while preserving public compatibility signatures.

### Tranche C — first-class Ledger
Add canonical Ledger identity, Organization → Ledger relation, and root Principal → Ledger authority.

### Tranche D — organization establishment v2
Introduce atomic noncommercial Organization + Ledger establishment using Person-first authority.

### Tranche E — onboarding participants and invitations
Allow pre-auth People, Person-based Organization Membership, setup actors, and governed future credential reconciliation.

### Tranche F — institutional separation
Adjudicate and migrate the historical Elm / Feast Guild organization-scope overlap into distinct Ledgers.

### Tranche G — Feast Guild operation
Begin ordinary Feast Guild work in the clean Ledger before adding custom flower-domain machinery.

## 20. Acceptance criteria

This architecture is not complete until the system can prove all of the following:

1. one Person may exist with no credential;
2. one credential resolves to at most one Person;
3. one Person/Principal can govern multiple Organization Ledgers;
4. an Organization and governing Ledger can be established without payment;
5. Organization + Ledger birth is atomic;
6. a Person may have an Organization relationship before login;
7. a later credential can be reconciled to that Person without creating a duplicate;
8. institutional identity subjects remain organization-local;
9. ending credential/commercial access does not erase Person or institutional history;
10. existing authenticated users continue to reach the same current Atlas through compatibility paths;
11. Feast Guild can exist as a clean Ledger even when no commerce-domain records exist;
12. Elm reality can be separated from Feast Guild without deleting or fabricating historical evidence.

## 21. Non-goals of the first Ledger tranche

Do not combine the first-class Ledger migration with:

- Feast Guild catalogue;
- flower product identity;
- supply admission;
- procurement;
- cooler inventory;
- broad source-custody migration;
- universal replacement of auth-user audit references;
- wholesale cleanup of historical organization data;
- UI redesign unrelated to Organization/Ledger establishment.

The first Ledger tranche should establish identity, addressability, authority, compatibility, and proof only.

## 22. Immediate implementation order

The current implementation order is:

```text
Canonical Person tranche 1
  ↓
Person-first Principal/Membership resolution
  ↓
first-class Ledger identity
  ↓
Principal ↔ Ledger authority
  ↓
noncommercial Organization + Ledger establishment
  ↓
Feast Guild institutional separation/onboarding
  ↓
Feast Guild commerce capabilities
```

Do not skip Canonical Person or create a separate Feast Guild application identity to get ahead of this sequence.
