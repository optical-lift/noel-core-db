# Atlas Organization Membership Calendar Context — Current Canon v1

**Status:** Governing architecture for Effective Time Phase A  
**Established:** September 20, 2026  
**Canonical repository:** optical-lift/noel-core-db  
**Parent contract:** `architecture/atlas-present-organization-membership-effectiveness-current-canon-v1.md`  
**Production behavior:** this document alone mutates nothing.

## 1. Decision

Organization Membership eligibility dates require an institutional civil-calendar context.

Atlas will **not** satisfy that requirement by treating any of the following as the Organization's Membership calendar:

- PostgreSQL/session `current_date`;
- Principal `home_timezone`;
- Household timezone;
- farm task-release timezone;
- event/program timezone;
- notification/device timezone;
- the timezone of the person currently using Atlas;
- the physical timezone of one operating unit.

Those are separate facts with separate owners.

The Membership calendar is its own Organization-governed context because it gives meaning to that Organization's Membership `eligibility_begins_on` and `eligibility_ends_on` date boundaries.

## 2. Narrow name, narrow jurisdiction

Do not add a generic `organizations.timezone` or `organizations.calendar_timezone` and allow unrelated domains to adopt it.

The governed concept is:

**Organization Membership Calendar Context**

Its only initial authority is:

> Which civil date applies when Atlas asks whether this Organization Membership is effective at an instant?

It does not govern event time, Worker Day, farm release, Household rhythm, Principal day, notification delivery, payroll, public opening hours, or any future domain merely because that domain also needs time.

Shared word != shared authority.

## 3. Persistence shape

Use a first-class append-preserving relation rather than a mutable generic Organization field.

Initial conceptual shape:

```text
organization_membership_calendar_contexts
  id
  organization_id
  timezone_name
  context_state
  basis_kind
  established_by_person_id
  established_at
  superseded_at
  metadata
```

Rules:

- at most one active context per Organization;
- `timezone_name` must resolve through PostgreSQL's timezone catalog;
- an active context is never edited into a different timezone or basis;
- change is revoke/supersede + append;
- provenance is preserved;
- a missing context is a real unresolved state, not permission to infer one.

The relation is not a universal temporal engine. It is a bounded authority carrier for Membership date semantics.

## 4. Why append-preserving

Changing a timezone can move the instant at which a civil date begins or ends.

A mutable field would make later inspection unable to distinguish:

- the context under which authority was evaluated yesterday;
- the context under which it is evaluated now;
- who established the context;
- why it changed.

Atlas already treats authority-bearing origins as durable evidence. Membership calendar context must follow the same rule.

Current-time evaluation may use only the one active context. Historical date-scoped Membership reads continue to use the explicit supplied date and do not require reconstruction from this table.

## 5. Date-scoped law remains canonical

`atlas.organization_membership_eligible_on_date_v1(membership, organization, service_date)` remains the canonical explicit-date predicate.

No timezone is needed when the caller already supplies the civil date whose institutional meaning is authoritative for that question.

Therefore:

```text
effective_on_date(D)
  = active Membership
  + begins_on <= D when present
  + ends_on >= D when present
```

The Membership Calendar Context exists to derive **D** when the question begins from an instant such as “now.”

## 6. Present evaluation law

For an instant `T`:

```text
Organization Membership Calendar Context
  -> timezone_name
  -> civil date D at T in that timezone
  -> organization_membership_eligible_on_date_v1(..., D)
```

A future executable helper may expose this as a bounded resolver such as:

```text
organization_membership_calendar_date_at_v1(organization_id, as_of)
```

The exact function name is implementation detail. The semantic contract is not.

## 7. Unbounded Memberships do not need a calendar

If an active Membership has both:

- `eligibility_begins_on is null`; and
- `eligibility_ends_on is null`;

then no civil-date boundary is being interpreted.

Such a Membership may remain present-effective without a Membership Calendar Context, subject to all other authority rules.

This prevents a missing calendar context from disabling legacy/unbounded institutional relationships for no semantic reason.

## 8. Bounded Memberships fail closed without context

If either Membership eligibility boundary is present, Atlas must not silently choose a civil date from database time or another domain.

For a bounded Membership:

```text
no active Membership Calendar Context
  -> present effectiveness unresolved
  -> present authority = false / denied
```

Read/projection surfaces may expose the unresolved reason separately, but authority must fail closed.

Missing context must never become UTC-by-default, Principal-time-by-default, farm-time-by-default, or browser-time-by-default.

## 9. Bootstrap authority

The first Membership Calendar Context cannot always be established by relying on present-effective Membership, because the calendar may be needed to determine whether a bounded Membership is present-effective.

Bootstrap authority therefore remains separate from Membership authority.

Initial lawful establishment paths:

1. an active Organization onboarding `setup_actor`, while setup authority remains active;
2. Principal Ledger `root_governing` authority for the Organization;
3. repository-governed one-time compatibility adjudication during a canonical migration.

After a context exists and Effective Time Phase B is live, a present-effective Organization owner may also govern future context changes through a bounded Organization command.

A future-dated or expired owner Membership must never gain bootstrap authority merely because its row is administratively active.

## 10. Change authorization uses the pre-change context

When an existing context is changed, the actor's authority is evaluated under the context that is active **before** the change.

The write must not use the proposed new timezone to retroactively make the actor authorized to perform the write.

Sequence:

```text
current context
  -> current actor authority
  -> authorized change
  -> supersede current context
  -> append new context
```

The new context becomes authoritative only after the governed write succeeds.

## 11. Setup input is declaration, not device inference

A browser/device timezone may be used as a UX suggestion during Organization setup.

It is not authoritative merely because JavaScript can detect it.

The setup actor must be treated as declaring or confirming the Organization Membership calendar context. A person may be traveling, remote, or configuring an institution in another jurisdiction.

Device context may propose. Institution/setup authority establishes.

## 12. Current production adjudication

September 20 production contains:

- three Organizations;
- four Organization Membership rows;
- two administratively active Memberships;
- one active bounded Membership, under Elm Farm;
- one active unbounded Elm owner Membership.

Atlas also contains several independent current timezone carriers around Elm Farm, including farm task-release configuration and the Principal/Household context, and those current durable carriers agree on `America/Chicago`.

That agreement must **not** become a generic resolution rule.

For compatibility, the first executable migration may explicitly establish Elm Farm's Membership Calendar Context as `America/Chicago` with a basis identifying it as a one-time current-state compatibility adjudication.

This is an explicit canonical decision recorded once. It is not “inherit farm timezone,” “inherit Principal timezone,” or a continuing fallback.

Organizations without bounded Memberships need no invented calendar row merely to make the table complete.

## 13. Relationship to Authority Dimensions

Effective Time composes underneath the already-governed Authority Dimensions work.

For example:

```text
Endpoint capability
  = present-effective Membership
  + exact active Endpoint grant
  + grant-basis lifecycle
```

An exact Endpoint grant cannot resurrect a future-dated or expired Membership.

Likewise:

```text
Organization-owner Membership authority
  = role owner
  + present-effective Membership
```

Principal Ledger root-governing authority remains a separate source and is not converted into Membership authority.

## 14. Relationship to Work

Historical Work responsibility remains durable evidence even after Membership ceases to be present-effective.

Membership Calendar Context does not rewrite:

- historical Work allocations;
- responsibility establishment provenance;
- service-date eligibility history;
- completed execution evidence.

Present execution/admission may require present-effective Membership separately.

Historical responsibility != present Membership eligibility.

## 15. First executable tranche

Phase A implementation should be limited to:

1. add the append-preserving Membership Calendar Context relation;
2. enforce one active context per Organization;
3. validate timezone names;
4. add a database-internal context resolver / civil-date resolver;
5. add a governed internal append/supersede command with explicit basis and actor provenance;
6. establish the one current Elm Farm compatibility context;
7. prove no other Organization receives an inferred context;
8. do **not** yet change the 138 candidate Membership callers;
9. do **not** yet alter current Endpoint, owner, employee, Work, invitation, or Connected Source authorization behavior.

Phase A creates the missing time source. Phase B consumes it.

## 16. Phase B immediately after Phase A

Once Phase A is proven:

1. make `current_effective_organization_membership_v1` use the governed present Membership law;
2. make the Membership branch of `is_effective_organization_owner_v1` use it;
3. make `is_organization_owner` use it;
4. repair a deliberately small first set of high-impact present-tense consumers;
5. include `organization_employee_appointments_by_auth_user_v1` as the first known projection counterexample;
6. then classify the remaining candidate functions instead of globally replacing `active=true`.

## 17. Phase A clone acceptance conditions

A production-schema clone must prove:

1. timezone names outside PostgreSQL's recognized timezone catalog are rejected;
2. at most one active Membership Calendar Context exists per Organization;
3. a superseded context cannot silently become active again;
4. changing context preserves the prior row and appends a new row;
5. current civil date is derived from the active context timezone, not database/session timezone;
6. an Organization with no context stays unresolved rather than receiving an inferred fallback;
7. Elm Farm receives exactly one explicit `America/Chicago` compatibility context;
8. Atlas Reference Company and Feast Guild receive no invented context merely because other timezone-bearing objects exist;
9. explicit date-scoped Membership eligibility behavior is unchanged;
10. no current authority helper is changed in Phase A;
11. no historical Membership or Work row is rewritten;
12. no Principal, Household, farm, event, or notification timezone is repurposed.

## 18. Governing result

Institutional date authority is not ambient.

```text
database time != Principal time != Household time != farm time
!= device time != Organization Membership calendar time
```

A Membership date boundary becomes present authority only through its Organization's governed Membership Calendar Context.

Unbounded relationships do not require invented time context.

Bounded relationships without time context fail closed.

Calendar context is established, preserved, and inspectable rather than inferred from whichever timezone happens to be nearby.
