# Atlas Person-First Resolution v1

**Status:** Candidate implementation contract
**Date:** 2026-09-13
**Prerequisite:** Canonical Person v1 live as `20260913134242_atlas_canonical_person_v1`

## 1. Purpose

Cut the first live identity-resolution membrane from credential-rooted durable-human lookup to canonical Person without changing public application signatures, commercial claim semantics, or authenticated-action provenance.

Target resolution:

```text
auth.uid()
  ↓
person_auth_credentials
  ↓
Person
  ↓
Principal / Organization Membership
```

Credential objects remain credential-bound. Person does not replace audit evidence or access credentials.

## 2. Current production audit

Canonical Person v1 is live and currently proves:

- `atlas.people` exists;
- `atlas.person_auth_credentials` exists;
- all current Principal rows with credentials have matching `person_id`;
- all current Organization Membership rows with credentials have matching `person_id`;
- all current authenticated Household Member rows have matching `person_id`;
- authenticated clients have no direct table read authority over Person tables.

The current application still has a credential-rooted identity membrane in several foundational functions.

The first cut is intentionally small. It does not mechanically rewrite every function that happens to reference `auth.uid()`.

## 3. Governing distinction

For every current `auth.uid()` use, ask:

> Is this naming the durable human/relationship, or recording/proving the credential that currently has access or performed an action?

Only durable-human/relationship lookup moves to Person in this tranche.

Credential/access facts stay credential-bound.

## 4. Functions in scope

### `atlas.current_principal_id_v1()`

Current meaning:

```text
auth.uid() → principals.user_id
```

Target meaning:

```text
auth.uid()
→ current_person_id_v1()
→ principals.person_id
```

Public signature and return type remain unchanged.

### `atlas.current_organization_membership_v1(uuid)`

Current meaning:

```text
auth.uid() → organization_memberships.user_id
```

Target meaning:

```text
auth.uid()
→ current_person_id_v1()
→ organization_memberships.person_id
```

Existing role-order preference remains unchanged.

### `atlas.is_organization_member(uuid)` / `atlas.is_organization_owner(uuid)`

Membership/ownership truth becomes Person-based.

These functions must not treat an auth credential as the durable membership identity.

### `atlas.atlas_home_identity_self_api_v1()`

`hasPrincipal` and `principalName` resolve through the current Principal helper rather than direct `principals.user_id = auth.uid()` lookup.

The response contract remains unchanged.

### `atlas.organization_access_self_api_v1()`

This function contains both credential evidence and durable membership identity.

Keep credential evidence:

```text
organization_member_credentials.auth_user_id = auth.uid()
credential_kind = auth_user
credential active / unexpired
```

Change durable relationship proof:

```text
membership.person_id = current Person
```

Do not use `membership.user_id = auth.uid()` as the relationship root after cutover.

### `atlas.personal_atlas_access_status_self_api_v1()`

Only Principal lookup moves to `current_principal_id_v1()`.

Keep purchase and implementation commercial/access claim evidence credential-bound in this tranche:

- `claimed_by_user_id`;
- purchaser-email claim path;
- setup-sponsor `human_user_id` compatibility path.

Those are separately governed transitions.

### `atlas.principal_self_context_api_v1()`

Resolve the current Principal using `current_principal_id_v1()` and then read the Principal by canonical ID.

Everything downstream of the resolved Principal remains unchanged.

## 5. Explicit non-scope

This tranche does **not**:

- make `principals.user_id` nullable;
- make `organization_memberships.user_id` nullable;
- migrate every direct `auth.uid()` lookup in every domain function;
- change invitation acceptance semantics;
- change `organization_member_credentials` away from auth identity;
- migrate action/audit provenance columns;
- migrate connected-source personal custody;
- create first-class Ledger;
- create Person ↔ institution-local identity-subject bindings;
- create pre-auth Organization Memberships yet;
- change Stripe/purchase eligibility;
- change Vercel or application UI.

## 6. Compatibility law

During this tranche, both legacy `user_id` and canonical `person_id` continue to exist on Principal and Organization Membership.

The Canonical Person compatibility triggers remain responsible for preventing contradiction.

The new read membrane uses `person_id` for durable identity while existing legacy writers may continue supplying `user_id`.

## 7. Required data proof

Before release, the production-shaped clone must prove:

1. every current credential-rooted Principal resolves to the same row through Person as through legacy `user_id`;
2. every current active credential-rooted Organization Membership resolves to the same row through Person as through legacy `user_id`;
3. every active Organization Member Credential points to a Membership whose canonical Person matches the credential's canonical Person;
4. no current Principal/Membership compatibility contradiction exists;
5. Person tables remain direct-browser inaccessible.

## 8. Required function proof

The canonical postconditions must prove:

- `current_principal_id_v1()` calls/depends on canonical Person and no longer resolves Principal through direct `p.user_id = auth.uid()`;
- `current_organization_membership_v1()` resolves Membership through `person_id`;
- `is_organization_member()` resolves Membership through `person_id`;
- `is_organization_owner()` resolves Membership through `person_id`;
- `atlas_home_identity_self_api_v1()` uses the Person-first Principal resolver;
- `organization_access_self_api_v1()` still verifies the auth-bound member credential while also requiring Membership Person consistency;
- `personal_atlas_access_status_self_api_v1()` resolves Principal through the Person-first helper but retains credential-bound commercial claim evidence;
- `principal_self_context_api_v1()` resolves the current Principal through the helper;
- public function signatures and existing grants are unchanged;
- `current_person_id_v1()` itself remains non-browser-callable.

## 9. Failure semantics

If an authenticated credential has no active canonical Person binding:

- Principal resolution returns no Principal;
- Organization Membership resolution returns no Membership;
- organization access returns no organization items;
- no fallback should silently re-root durable identity through raw `user_id`.

This fail-closed behavior is intentional.

## 10. Why this tranche precedes Ledger

First-class Ledger authority will need to resolve:

```text
credential → Person → Principal / Membership → Ledger authority
```

If Ledger is introduced while Principal and Membership are still semantically credential-rooted, Atlas would preserve the very single-login/single-root assumption the Ledger work is intended to remove.

Therefore this tranche is the immediate prerequisite for first-class Ledger identity.
