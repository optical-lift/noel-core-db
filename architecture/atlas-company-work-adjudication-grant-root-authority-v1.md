# Atlas Company Work Adjudication Grant Root Authority v1

**Status:** production-live Company Work adjudication grant root authority  
**Date:** 2026-09-22  
**Parent law:** `atlas-company-work-institutional-adjudication-authority-v1.md`  
**Existing root source:** Principal → Ledger `root_governing` authority  
**Universal grant-administration engine:** none

## 1. Purpose

Company Work Result adjudication is now explicit:

```text
Company Work Result
→ explicit adjudication grant
→ exact authority resolver
→ human decision
```

But v1 still leaves one compatibility shortcut upstream:

```text
Organization owner
→ may establish / revoke adjudication grants
```

That must not become constitutional law.

Atlas already has a stronger existing root:

```text
Principal
→ principal_ledger_authorities
→ root_governing
→ governing Ledger
→ Organization governing participation
```

This tranche binds Company Work grant administration to that existing root authority.

## 2. Core law

> **The power to establish or revoke institutional adjudication authority belongs to an actor who holds root-governing authority over the Organization's governing Ledger, not to an Organization role label.**

Therefore:

```text
Organization owner role
!= grant-establishment authority

Principal status
!= grant-establishment authority

root_governing authority over governing Ledger
= grant-establishment authority
```

The relationship, not the title, is authoritative.

## 3. Organization governing Ledger

For this proof, Company Work grant administration requires exactly one active Ledger participation satisfying:

- Organization matches the target Company Work Organization;
- participation is active;
- `participation_kind = governing`;
- `is_compatibility_primary = true`;
- Ledger is active.

If that governing root is missing or ambiguous, grant administration fails closed.

The tranche does not choose an arbitrary Ledger.

## 4. Existing Principal root membrane

Atlas already has:

`atlas.capability_root_authority_context_self_v1(ledger_id)`

That membrane requires:

- authenticated user;
- canonical Person;
- canonical Principal;
- active Principal ↔ Person identity;
- active `principal_ledger_authorities` row;
- `authority_kind = root_governing`;
- positive `principal_has_ledger_authority_v1`.

Company Work must reuse that membrane rather than create a second Principal-authority interpretation.

## 5. Domain-local root context

Introduce internal:

`atlas.company_work_adjudication_grant_root_context_self_v1(organization_id)`

It resolves:

```text
Organization
→ exact active primary governing Ledger
→ capability_root_authority_context_self_v1
→ Person + Principal + PrincipalLedgerAuthority
```

It does not grant Company Work authority.

It proves only who may establish or revoke such a grant.

## 6. Grant provenance

New explicit Company Work adjudication grants preserve the exact root authority that established them.

Add nullable provenance to:

`atlas.company_work_adjudication_authority_grants`

- `granted_by_principal_id`;
- `granted_by_principal_ledger_authority_id`.

Add grant basis:

`explicit_root_governing_grant`.

For that basis, both Principal provenance fields are required and must identify an active `root_governing` authority over the Organization's exact governing Ledger.

Historical bases remain valid:

- `organization_owner_compatibility_cutover`;
- `explicit_owner_grant`.

They remain history. New grant administration no longer creates `explicit_owner_grant`.

## 7. No historical rewrite

The migration does not rewrite existing adjudication grants.

In particular, the live:

`organization_owner_compatibility_cutover`

grant remains explicit compatibility data until root governance deliberately revokes or supersedes it.

History must not be cosmetically relabeled as though it had always been Principal-root authority.

## 8. Grant administration cutover

The existing browser RPC remains:

`atlas.set_company_work_adjudication_authority_self_api_v1(...)`

but its authority membrane changes.

Before:

```text
current Organization owner
→ set / revoke grant
```

After:

```text
exact Organization governing Ledger
→ current Principal has root_governing authority
→ set / revoke grant
```

The caller does not need Organization role `owner`.

An Organization owner with no root-governing Ledger authority is denied.

## 9. Target membership remains institutional

The grant target must still be a present-effective Organization Membership in the scoped Organization.

Root grant authority does not authorize granting Company Work power to arbitrary Persons outside that institution.

## 10. Scope remains domain-local

This tranche preserves the existing Company Work grant scopes:

- Organization;
- exact Work item.

It does not add Organization Unit inheritance, Position inheritance, Responsibility inheritance, or universal authority scope.

## 11. Existing decision authority is unchanged

This tranche does not change:

`atlas.company_work_result_adjudication_authority_v1(...)`

or the fact that a Result decision requires an active explicit Company Work adjudication grant.

It changes who may establish/revoke that grant.

The decision holder does not need to be Principal.

The grant administrator does not automatically gain Result decision authority.

These are distinct dimensions.

## 12. Root authority is not Principal status

The following inference is forbidden:

```text
Person is Principal
→ may administer all Company Work grants
```

The Principal must hold the exact `root_governing` Ledger authority for the Organization's governing Ledger.

A Principal with no such authority is denied.

## 13. Owner compatibility becomes fully downstream

After this tranche:

- owner role is not Result-adjudication authority;
- owner role is not Company Work grant-administration authority;
- the old owner Result-decision RPC remains only a compatibility entry wrapper and still requires an explicit Result-adjudication grant;
- any existing owner compatibility grant is explicit data and may be revoked by root governance.

Owner remains a historical adapter relation, not the constitutional authority source.

## 14. Browser boundary

The grant table remains non-browser-readable.

The root-context helper remains internal.

Authenticated users may call grant administration, but the RPC itself proves root-governing authority before mutation.

No generic root-authority table is introduced.

## 15. Qualification criteria

Production-schema clone proof must establish:

1. a role=`owner` Organization member with no Principal root-governing Ledger authority cannot establish a Company Work adjudication grant;
2. the same owner cannot revoke another member's grant;
3. a Principal whose Organization role is only `member` but who holds exact root-governing authority over the Organization's governing Ledger can establish a grant;
4. Principal status without exact Ledger authority is insufficient;
5. a missing or ambiguous governing Ledger root fails closed;
6. target Membership must remain present-effective in the scoped Organization;
7. a new grant records `explicit_root_governing_grant`;
8. the new grant records the exact Principal;
9. the new grant records the exact Principal Ledger Authority;
10. those provenance fields agree with the Organization's governing Ledger;
11. historical `organization_owner_compatibility_cutover` grants are not rewritten by migration;
12. root governance may deliberately revoke a historical compatibility grant;
13. revoked compatibility does not regenerate from owner role;
14. root governance may establish exact-Work authority for a non-Principal member;
15. that grantee becomes authorized for the exact Result through the existing adjudication resolver;
16. grant revocation removes that Result authority;
17. the grant-administration RPC contains no owner-role / Farm-role shortcut;
18. raw grant table remains unavailable to browser roles;
19. internal root-context helper is unavailable to browser roles;
20. no universal grant engine, generic permission table, or Principal-to-all-domains wildcard is introduced.

## 16. Promotion boundary

This tranche proves one domain's authority-establishment root.

It does not yet establish:

- a universal institutional grant-administration protocol;
- Principal delegation of root-governing authority;
- Organization Unit grant administration;
- generic Position-derived grant power;
- generic Responsibility-derived grant power;
- a second independent `authority_required` reconciliation domain.

Those require their own evidence.

## 17. Resulting architecture

```text
Principal
→ exact root_governing authority over Organization governing Ledger
→ Company Work grant administration
→ explicit bounded adjudication grant
→ Result authority resolver
→ human decision
→ Reconciliation
```

This removes Organization-owner role from the Company Work grant-establishment membrane without inventing a new universal authority model.


## 18. Production receipt — 2026-09-22

Company Work adjudication grant administration crossed production on September 22, 2026.

Canonical lineage:

- architecture/candidate PR #1182 → merge `62787f342af18926f73ade35b6d1a67fcd6f7ba6`;
- first generated package `20260922181844` retired unreleased after the clone fixture safety scanner rejected disposable string labels containing the standalone token `grant`;
- fixture-safety repair PR #1186 → merge `cdc18728ca823148df9057ceb5932be176bd0dec`;
- governed generation request #1187;
- released migration `20260922182354_atlas_company_work_adjudication_grant_root_authority_v1.sql`;
- generated package SHA `d4bba84b26589a062dbff2f71dd838b236a3f8e9`;
- generated package PR #1188 → merge `b3b13077292d710c825a7e99140ab77bde77fe26`;
- Production Schema Clone Validation request #1189 / run `35766967386` → PASS;
- governed production release request #1190;
- protected Production Database Release run `35767980927` → PASS;
- production migration ledger contains version `20260922182354`.

Production now requires the existing Principal/Ledger root-governing relation to administer Company Work adjudication grants:

```text
Organization primary governing Ledger
→ current Principal root_governing authority
→ Company Work grant administration
```

The passing clone proved that Organization role and authority are no longer conflated at this membrane:

```text
role=owner + no root-governing Ledger authority
→ denied

role=member + exact root-governing Ledger authority
→ admitted
```

Direct production verification confirms:

- the internal Company Work grant-root context is not browser-executable;
- the authenticated grant-administration RPC remains callable but proves root authority internally;
- anonymous users cannot execute grant administration;
- authenticated users cannot directly SELECT the Company Work adjudication-grant table;
- one historical active `organization_owner_compatibility_cutover` Result-adjudication grant remains explicit compatibility data;
- no live `explicit_root_governing_grant` exists merely because this migration released.

This completes the upstream authority cutover for the first Company Work human-judgment loop:

```text
Principal/Ledger root governance
→ explicit adjudication grant
→ exact Result authority
→ human judgment
→ canonical consequence
→ Reality Reconciliation
```

It still does not justify a universal grant-administration engine or a universal Decision Requirement system.
