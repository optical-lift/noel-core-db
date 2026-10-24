# Atlas universal Person and Ledger authority cutover — current production audit

**Status: source-only, first runtime cutover staged; not deployed or globally retired.**
**Architectural decision:** There is only one Person, independent of authentication, billing, work relationship, employer, household or organizational status. A Person's connection to a Ledger is a canonical relationship, not a user subtype; exact bounded Ledger authority determines information visibility and actions. Person identity and their historical evidence must not be deleted to simplify the permissions graph.

## Verified 2026-10-24 production reality

- Anna Donovan, Katie Langenberg and Marshall Mitchell all already have active canonical `atlas.people` identity, active `atlas.principals` bound to real nonanonymous Auth users, and active native `ledger.seats` relationships to **both** Elm Farm Flower and Venue Ledgers.
- Marshall also has an active native Optical Lift Ledger connection and two direct governing `atlas.principal_ledger_authorities` entries. Katie and Anna lack that *governing authority*, which is not a defect in their Person identity or Ledger participation.
- Anna's *separate* `atlas.organization_memberships` row is active as `member`; Katie's is inactive as `consultant`; Marshall has no row. This unrepresentative table caused Foundry's signed reviewer list to return only Anna. All three qualify as canonical Elm Ledger-connected Persons.
- The production registry has 10 native Ledger Person-seat rows (all active), 4 active Principals, 5 `atlas.people` records, and 5 legacy organization membership rows (3 active). The physical `atlas.organization_employee_seats` table is already absent.
- **192 SQL functions still reference `atlas.organization_memberships`**. This is a current dependency count, not 192 separate Person types; there are extensive foreign keys from correspondence, communications, work and institution event history to membership IDs. Removing the table without replacing their dependent reads and preserving evidence would be destructive.
- `atlas.native_connected_ledger_access_self_api_v1` and `atlas.person_has_native_ledger_connection_v1` already implement the correct core separation: Person identity -> active exact native Ledger connection, with explicit disclaimers that a connection does not establish management, task responsibility, billing or unrestricted information access.
- A previous Build 5 source contract explicitly designated `ledger.seats` as the universal native Person/Ledger relationship and retired the **physical employee-subscription seat** as an admission mechanism. Its historical membership/billing tables were not made into new Person identities.

## One universal graph (no duplicate admission paths)

```text
canonical Person (reality.entities / atlas.people)
    |
    +-- optional verified auth credential --> Atlas sign-in
    |
    +-- optional Principal --> action/decision actor linked to same Person
    |
    +-- active native Person <-> Ledger connection
           |
           +-- separately established Ledger-scoped visibility
           +-- separately established bounded responsibility / task assignment
           +-- separately established governance / financial approval
```

- *Employee*, *consultant*, *member*, *volunteer*, *relative* and *contractor* may remain historical or descriptive relationship words, NEVER different Person registrations, access gates, entitlement classes or parallel role-based authorization APIs.
- Product payments and subscriptions may remain accounting/entitlement evidence only. They **do not create a Person, authenticate a user or independently authorize a Ledger read**.
- A person can exist, be connected to a Ledger and have work assigned **without an Atlas login**. Authentication is required only when that human personally opens the notebook or performs an authenticated approval. Do not create another Person when they claim credentials.
- An active Ledger connection does **not** expose private financial, medical or Personal Atlas material, grant ownership, give universal Ledger management power, or automatically authorize AI source access. Those require exact separately governed scope grants. A Ledger only determines a permission *when that particular operation's bounded authority is proven*.

## First functional correction in this candidate

Replace the two private Foundry source-review functions' legacy `organization_memberships` joins with a common **canonical Person / active native Ledger** relationship predicate, retaining exact signed GoTrue identity, separate reviewer and source-case ownership checks. The reviewer list reports canonical Person ID as additional context without creating or changing a Person. The request writer RECHECKS the native relationship; modifying browser payloads or historic `role='consultant'` does not help.

This is a **shared-Ledger reviewer-discovery pilot**, not the final universal personal People chooser: a *pre-Ledger* owner may eventually need to invite a Person they know who does not already share a Ledger. That must use the existing governed Person/relationship Index with a separately authorized case invitation, not a world-readable account directory or a new seat type. Do not promote shared-Ledger connectivity into permanent sole admission for every Foundry review.

## Safe removal program (complete each before DROP)

1. **Authority freeze:** no new auth/read/task/identity code may use `organization_memberships.role`, a subscription or a historic employee seat to determine who is a Person or who has general Ledger access. Inventory 192 SQL functions and all FK references. Keep existing historical operation evidence intact.
2. **Identity and Ledger resolver:** standardize `auth credential -> canonical Person -> Principal -> active exact Ledger connection -> exact scope permission`; casework can designate accountless People without assigning a new Person identity.
3. **Consumer cutover:** migrate communication, Today/work, owner/institution, billing UI, invite flows and shared-source readers to that central resolver with one owner, one participant, one disconnected, one accountless and one previously labeled consultant fixture. Preserve existing legitimate assignments and signed authority checks.
4. **Archive old evidence and retire writes:** maintain immutable historical membership/correspondence foreign keys or migrate them with exact provenance. Stop new membership/employee/consultant registrations and disable alternative admission endpoints.
5. **Physical cleanup:** only then remove obsolete tables/columns with `RESTRICT`, never `CASCADE`, after a production-shaped schema clone proves no dependent function, FK, data or account continuity is lost.
6. **UI convergence:** users always enter through their own Atlas notebook. Ledgers control bounded views; names of old business relationships can be descriptive only. Source-custody reviewer picker must never become a special business-membership or employee-seat chooser again.

**No production row/table/function was removed by this source-only first cutover. No billing or consent was changed.**
