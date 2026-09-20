# Atlas Present Membership Effective-Time Cutover — Current Canon v1

**Status:** Governing cutover plan for Effective Time Phase B  
**Established:** September 20, 2026  
**Canonical repository:** optical-lift/noel-core-db  
**Prerequisites:**  
- `architecture/atlas-present-organization-membership-effectiveness-current-canon-v1.md`  
- `architecture/atlas-organization-membership-calendar-context-current-canon-v1.md`

## 1. Audit result

The September 20 production audit initially identified roughly 138 SECURITY DEFINER Atlas functions that reference Organization Membership administrative activity without directly checking Membership eligibility dates.

That raw count is not the implementation plan.

The candidate set collapses behind a small number of authority/resolution seams. Effective Time must repair those seams first, then inspect only the remaining direct Membership readers that bypass them.

The goal is:

```text
one governed present-Membership law
  -> reused by authority/read/action seams
  -> direct exceptions classified deliberately
```

Do not perform a repository-wide replacement of `m.active=true`.

## 2. Core present-Membership predicate

After Membership Calendar Context exists, introduce one canonical present-time predicate over an exact Organization Membership.

Conceptually:

```text
present_effective_membership(M, O, T)
  = M belongs to O
  + M active
  + if M has no eligibility boundaries -> true
  + otherwise O has active Membership Calendar Context
  + derive civil date D from T in that timezone
  + organization_membership_eligible_on_date_v1(M, O, D)
```

A bounded Membership with no resolvable Membership Calendar Context returns false for present authority.

Explicit date-scoped callers continue using `organization_membership_eligible_on_date_v1(..., D)` directly.

## 3. Root seam 1 — current Membership resolution

### current_effective_organization_membership_v1

This is the canonical present Person -> Organization Membership resolver and must use the present-effective predicate.

Current defect: it resolves any administratively active Membership.

Repairing it directly fixes or strengthens current callers including:

- `is_effective_organization_member_v1`;
- Communication actor context;
- institutional communications home;
- correspondence personal-attention/summary surfaces;
- current owner decision on Company Work results.

### current_organization_membership_v1

Despite the older name, its current downstream uses are present actor operations, not historical Membership inspection.

Current callers include Organization spend/expense reporting writes and worker route reads.

It should become a compatibility alias over the same present-effective resolution law rather than remain a second weaker meaning of “current.”

If a future caller needs administratively-active Membership regardless of effective date, it must use a separately named administrative resolver.

## 4. Root seam 2 — member predicate

### is_organization_member

Current defect: active row == member now.

Target:

```text
is_organization_member(O)
  = current present-effective Membership in O exists
```

This gives one correction point to current reads including:

- external relationship / commercial correspondence history;
- generic email connection status;
- identity party projection;
- flower correspondence/read surfaces;
- company operating knowledge resolution;
- other legacy current-member reads.

Historical inspection must not call this predicate.

## 5. Root seam 3 — owner predicate

### is_organization_owner

Current defect: active owner row == owner now.

Target:

```text
is_organization_owner(O)
  = present-effective Membership in O
  + role=owner
```

This is high leverage. Current callers include:

- generic email transport activation/history/credentials;
- Company Work scheduling and adjudication;
- employee position appointment;
- Organization Work planning/management;
- project/trail ownership actions;
- Organization ledger owner window.

### is_effective_organization_owner_v1

The Membership branch must use the same present-effective owner law.

The Principal Ledger `root_governing` branch remains independent.

Do not convert root-governing authority into Membership authority.

## 6. Root seam 4 — Communication Endpoint capability

The Authority Dimensions cutover already made Endpoint grants exact and removed Organization-owner-as-knowledge.

Current production intentionally contains an interim Effective-Time fence:

```text
om.eligibility_begins_on is null
and om.eligibility_ends_on is null
```

inside `communication_endpoint_membership_has_capability_v1`.

That was correct as a temporary fail-closed rule before an institutional calendar source existed.

After Membership Calendar Context Phase A, replace that temporary “bounded Memberships never qualify” fence with the canonical present-effective Membership predicate.

This single repair composes underneath dozens of Communication surfaces, including:

- inbox/detail/delivery reads;
- Correspondence list/detail/drafts;
- attachment reads and writes;
- email drafts/signatures;
- claim/handoff/collaboration;
- outbound send authorization;
- correspondence identity management;
- Communication-derived Work;
- endpoint dispositions and response-state changes.

Do not separately duplicate date logic in those callers unless a caller independently reads another Membership for a different purpose.

## 7. Root seam 5 — Connected Source authority

### organization_connected_source_authorized_self_v1

Current law:

```text
active owner Membership
OR active setup_actor
```

Target:

```text
present-effective owner Membership
OR active setup_actor
```

The setup-actor branch is a separate onboarding authority source and remains independent of Membership effectiveness.

This seam governs current Organization Connected Source registration, authorization transitions, and sync checkpoint commands.

### connected_sources_self_api_v1

This reader bypasses the helper and currently exposes Organization Connected Sources to any administratively active Membership.

It must independently switch its Organization-membership branch to present-effective Membership while preserving:

- human-custodied source access by the human custodian;
- active onboarding setup_actor access.

## 8. Employee projection proof

`organization_employee_appointments_by_auth_user_v1` remains the first concrete projection proof.

Current behavior correctly requires:

- active credential;
- active employee seat;
- current billing state;
- active Position Appointment inside its timestamp window;

but only requires `m.active=true`.

Target:

```text
credential current
+ employee seat current
+ Membership present-effective
+ Position Appointment current
= current employee appointment
```

Credential/seat/appointment truth cannot resurrect a future-dated or expired Membership.

## 9. Session and Organization-access projections

Current session/access projections are especially important because they teach the application what institutions the person appears to belong to.

Audit these physical compatibility roots, not only their wrappers:

- `current_session_context_physical_compatibility_internal_v1`;
- `organization_access_physical_compatibility_internal_v1`.

If those roots enumerate administratively active Memberships as current access, correcting only the outer custody wrapper is insufficient.

Target behavior:

- future-dated Membership does not appear as current Organization access;
- expired-but-active Membership does not appear as current access;
- historical identity/custody evidence remains preserved elsewhere;
- setup_actor onboarding context may still surface through its own contract.

## 10. Company Work planning

`company_work_planning_actor_membership_v1` currently chooses an administratively active Membership after scheduling authorization succeeds.

It must return a present-effective Membership.

Company Work functions that already take an explicit `p_service_date` must be classified separately:

- if the question is “was this Membership eligible for service date D?”, use explicit-date eligibility;
- if the question is “may this actor act now?”, use present-effective Membership;
- do not substitute one for the other.

Historical Work allocation remains historical truth.

## 11. Invitations and onboarding

Invitation acceptance is not automatically a present-authority read.

Classify invitation functions by what they are doing:

- establishing a future/current Membership;
- checking inviter authority now;
- checking target eligibility on a service date;
- displaying historical invitation evidence.

The inviter's authority is present-time and must be effective-time aware.

The invited Membership may lawfully be future-dated.

Do not reject a future Membership merely because it is not yet present-effective.

Onboarding `setup_actor` remains an independent authority source and must not be forced through Membership merely to reuse a predicate.

## 12. Direct Communication Membership reads

Even after Endpoint capability is repaired, some Communication projections enumerate Organization Membership rows directly, for example recipient/collaborator/handoff candidate lists.

These must be classified by semantic purpose.

A future/expired Membership must not appear as a current handoff or claim candidate merely because the viewer can see the Endpoint.

Historical messages may still display the person/membership that participated in the past.

Current action candidate != historical participant identity.

## 13. Old Owner / farm-root surfaces

The Principal Operating System direction already rejects continued investment in the old selected-farm-first Owner model.

Functions in legacy owner/operator/project surfaces must therefore be triaged:

1. **still reachable authority boundary** — repair present Membership semantics until retired;
2. **compatibility read with active consumers** — repair only the narrow security/read boundary;
3. **dead/deprecated surface** — retire instead of extending.

Do not spend Effective-Time work polishing obsolete Owner prioritization behavior.

Security correctness still applies while a legacy endpoint remains callable.

## 14. First Phase B executable slice

After Calendar Context Phase A is source-merged and clone-proven, the first Phase B migration should remain deliberately small.

Repair:

1. canonical present-effective exact Membership predicate;
2. `current_effective_organization_membership_v1`;
3. `current_organization_membership_v1` as present-compatible alias;
4. `is_organization_member`;
5. `is_organization_owner`;
6. Membership branch of `is_effective_organization_owner_v1`;
7. `communication_endpoint_membership_has_capability_v1`;
8. `organization_connected_source_authorized_self_v1`;
9. `connected_sources_self_api_v1`;
10. `organization_employee_appointments_by_auth_user_v1`;
11. `company_work_planning_actor_membership_v1`;
12. physical roots for current session / Organization access if clone audit confirms they enumerate active Membership directly.

Do not attempt all remaining candidate functions in the first migration.

## 15. Why this first slice is high leverage

The root-seam repairs transitively govern large portions of:

- Correspondence;
- Communication send/claim/handoff;
- Connected Sources;
- Company Work planning;
- employee projections;
- Organization access;
- spend/expense actor resolution;
- commercial/external relationship reads.

This produces broad semantic correction with a small number of source changes.

## 16. Second-pass classification buckets

After the first slice, re-run the original candidate query.

Every remaining direct Membership-active function must be assigned to exactly one bucket:

### A. Present knowledge
Current private read/visibility requires present-effective Membership.

### B. Present action
Current write/command requires present-effective Membership or another explicit authority source.

### C. Present governance
Current owner/manager/configuration authority requires present-effective Membership or independent root governance.

### D. Explicit service-date
Uses the caller/domain's supplied effective date; do not replace with present time.

### E. Historical/admin
Intentionally inspects administrative or historical Membership state; keep direct state semantics and document why.

### F. Transitional/legacy
Still callable but scheduled for retirement; fix only the necessary security boundary.

### G. Non-authoritative integrity carrier
Membership activity is being used for structural data integrity rather than current human authority; adjudicate separately.

No function remains “unclassified active check.”

## 17. Clone acceptance conditions for Phase B slice

A production-schema clone should prove at least:

1. active future-dated Membership does not resolve through either current Membership helper;
2. active expired Membership does not resolve through either current Membership helper;
3. unbounded active Membership remains current without requiring a Calendar Context;
4. bounded currently eligible Membership resolves under its Organization's active Membership Calendar Context;
5. bounded Membership with no calendar context fails present authority closed;
6. future/expired owner Membership fails both owner predicates;
7. Principal Ledger root-governing authority remains valid independently;
8. exact Endpoint grant + future/expired Membership does not authorize Endpoint capability;
9. exact Endpoint grant + currently eligible Membership does authorize under its own grant lifecycle;
10. current Elm bounded Membership no longer hits the interim “bounded always denied” Endpoint rule once Elm's explicit context exists;
11. future/expired Membership cannot list Organization Connected Sources through Membership authority;
12. active setup_actor can still carry lawful onboarding Connected Source work;
13. future/expired Membership does not appear as a current employee appointment;
14. historical/service-date Membership eligibility still answers supplied dates correctly;
15. historical Work allocations are untouched;
16. the first migration introduces no generic timezone fallback and no universal temporal engine.

## 18. Governing result

Effective Time is not 138 local date checks.

It is one present-Membership law composed into the system's real authority seams.

Repair the seam first.

Then classify the exceptions.

Do not let administrative row state, product access, endpoint grants, appointments, responsibility, or a nearby timezone silently substitute for present institutional relationship.
