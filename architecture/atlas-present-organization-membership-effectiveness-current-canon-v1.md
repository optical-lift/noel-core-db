# Atlas Present Organization Membership Effectiveness — Current Canon v1

**Status:** Governing architecture for the Effective-Time cross-cutting tranche
**Established:** September 20, 2026
**Canonical repository:** optical-lift/noel-core-db
**No production mutation:** this contract creates no migration, function, grant, RLS policy, or application behavior.

## 1. Problem

Atlas Organization Membership already contains two different kinds of state:

- administrative row state: active;
- calendar eligibility: eligibility_begins_on and eligibility_ends_on.

Current source does not apply that distinction consistently. Some present-tense authority and read functions treat active=true as meaning the membership is current now, while already-correct institutional responsibility reads also require the eligibility window to contain the evaluation date.

The first inference is false.

## 2. Governing law

**Organization Membership administrative activity and Organization Membership temporal effectiveness are distinct facts. Present knowledge, action, governing, and employee projections must use present-effective membership rather than merely an administratively active row.**

Membership row exists != membership administratively active != membership effective on date D != current Position appointment != current institutional responsibility != current credential/product access != current domain action authority.

No one layer may silently stand in for the others.

## 3. Canonical date-scoped predicate already exists

Current production already has atlas.organization_membership_eligible_on_date_v1(membership, organization, service_date).

Its law is:

- same membership and organization;
- active;
- evaluation date is non-null;
- eligibility_begins_on is null or on/before the evaluation date;
- eligibility_ends_on is null or on/after the evaluation date.

This is the current canonical membership-date predicate. Do not create another slightly different eligibility test merely because a caller asks a present-tense question.

Present-tense membership helpers should compose this law at a governed present institutional evaluation date. Historical or service-date consumers should continue supplying the relevant historical/service date rather than substituting today.

The date-scoped predicate is settled. The source of the generic institutional meaning of "today" is not yet settled.

## 4. Calendar context is a prerequisite for present-time authority

eligibility_begins_on and eligibility_ends_on are SQL date values. A date boundary requires a civil-calendar context when Atlas asks whether it is effective "now."

SQL current_date is derived from the database/session timezone. That is implementation context, not automatically institutional authority.

The September 20 audit found:

- Organization has no canonical timezone column;
- Principal has home_timezone;
- Household and several domain-local objects carry their own timezones;
- farm execution/release configuration carries domain-local timezone;
- Elm Farm domain evidence currently uses America/Chicago;
- at least one active Elm Organization Membership already has eligibility_begins_on populated.

Principal home timezone must not silently become Organization time. A farm execution timezone must not silently become every institution's time. Database/session timezone must not silently become either.

Therefore the generic present-effective Membership repair must first establish a governed source for the institutional calendar date used to evaluate Membership eligibility.

Candidate future realizations may include an Organization calendar timezone or an explicit Membership eligibility-calendar context. This contract deliberately does not choose storage until the authority/custody implications are audited.

Until that context exists, current_date in existing functions is compatibility behavior and a useful exemplar of the eligibility-window formula, not the final universal source law.

## 5. Current-canon positive exemplar

resolve_person_organization_responsibility_current_v1 and effective_person_organization_responsibilities_current_v1 already apply the correct layered semantics:

- Organization Membership: active plus eligibility window contains current date;
- Position Appointment: active plus begins_at <= now and ends_at > now when present.

This is the model other present-tense authority surfaces should converge on. Membership date and appointment timestamp remain separate facts.

## 6. Present-effective Membership helper

current_effective_organization_membership_v1 currently checks Person + Organization + active but ignores both eligibility boundaries.

Its semantic contract should become: current Person + Organization + membership eligible on the governed present institutional evaluation date -> present-effective Membership.

The implementation may call the existing date-scoped predicate or share an equivalent internal predicate. The requirement is one canonical membership law plus one governed institutional-calendar-date source, not duplicated date expressions or hidden timezone assumptions across dozens of functions.

Production enforces one Organization Membership per organization/person, so current resolution does not need a new precedence rule among multiple simultaneous Person Membership rows.

## 7. Owner authority

is_organization_owner and the Organization-Membership branch of is_effective_organization_owner_v1 currently accept an administratively active owner Membership outside its eligibility window.

The Membership-based owner branch must require role=owner plus present-effective Organization Membership.

The Principal Ledger root_governing branch inside is_effective_organization_owner_v1 is a separate authority source and must remain independent of Organization Membership eligibility.

Membership owner authority != Principal Ledger root-governing authority.

## 8. Present knowledge and action surfaces

A future-dated or expired Membership that remains administratively active must not receive present-tense authority merely because a function contains m.active=true.

High-impact caller classes requiring classification include:

- Correspondence / Communication Endpoint knowledge and action;
- Connected Source setup, administration, and custody;
- Organization configuration/governance;
- employee/home projections;
- Company Work planning/management;
- invitations/setup actor flows;
- credentials and employee seats;
- Organization-scoped private reads.

Do not mechanically replace every active check. Historical/admin functions may intentionally inspect administratively active records or a Membership at a supplied service date.

## 9. Employee credentials and seats

An active credential or employee seat does not make an ineligible Membership present-effective.

For a current employee projection: credential current + seat current + Membership present-effective + any required current appointment -> current employee projection.

organization_employee_appointments_by_auth_user_v1 is a concrete counterexample: it correctly checks appointment begins_at/ends_at but only checks Membership active=true.

Seat/billing state remains product-access evidence, not institutional Membership effectiveness.

## 10. Communication and Knowledge-Jurisdiction

The separate Authority Dimensions work removes implicit owner-wide Endpoint knowledge. Effective Time composes underneath that law.

After the owner-knowledge cutover, Endpoint capability resolution should require present-effective Membership plus the exact Endpoint grant under its own lifecycle.

An Endpoint grant must not resurrect authority for a future-dated or expired Membership. Root Organization governance through a Membership likewise requires that Membership to be present-effective.

## 11. Company Work

Exact Company Work responsibility and present Membership eligibility are not identical.

A historical Work allocation may remain valid historical evidence after the Membership is no longer present-effective. Present execution/admission can separately require present eligibility.

Historical responsibility truth != present institutional eligibility != present execution warrant.

## 12. Historical and service-date reads

When a domain has an explicit service/effective date, it should use that date. Do not replace it with current_date.

effective_on_date(D) is the source law. effective_now is a present projection over that date-scoped law.

## 13. Current production risk

At the September 20 audit, production contained four Organization Membership rows total, two administratively active, zero active future-dated rows, zero active rows whose eligibility end was already past, and two active/currently eligible rows.

The defect is therefore latent rather than a known contradictory live authorization. Correcting the law before future-dated onboarding/offboarding becomes common avoids proliferating hidden present-authority errors.

## 14. First executable repair

The first executable work should remain narrow, but it now has a prerequisite.

Phase A — settle institutional calendar context:

1. identify the truthful authority/custody for the civil calendar used by Organization Membership eligibility;
2. do not infer it from Principal home timezone, database/session timezone, or a domain-local farm timezone merely because those values happen to agree today;
3. establish a canonical resolver that can return the evaluation date for a Membership/Organization context or fail closed when bounded eligibility cannot be evaluated.

Phase B — present Membership cutover:

1. make current_effective_organization_membership_v1 eligibility-aware using the governed evaluation date;
2. make the Membership branch of is_effective_organization_owner_v1 eligibility-aware;
3. make is_organization_owner eligibility-aware;
4. correct a small set of high-impact present-tense consumers that independently query Membership;
5. include organization_employee_appointments_by_auth_user_v1 as a concrete projection proof;
6. preserve organization_membership_eligible_on_date_v1 for explicit date-scoped callers;
7. preserve Principal Ledger root-governing authority independently;
8. make no historical Membership or Work rewrite;
9. avoid a universal temporal engine.

## 15. Clone acceptance conditions

A future production-schema clone must prove:

1. active Membership before eligibility_begins_on has no present-effective resolution;
2. active Membership after eligibility_ends_on has no present-effective resolution;
3. active Membership inside the window resolves normally under the governed institutional calendar date;
4. bounded Membership with no resolvable institutional calendar context fails closed rather than falling back silently to database/session or Principal time;
5. null begin/end remains open-ended on that side;
6. future-dated owner Membership does not satisfy owner authority;
7. expired owner Membership does not satisfy owner authority;
8. currently eligible owner behavior remains unchanged;
9. Principal Ledger root-governing authority remains independently valid under its own law;
10. future/expired Membership does not surface as a current employee appointment merely because credential/seat/appointment rows otherwise look current;
11. explicit past/future service-date eligibility still works;
12. historical Work allocations are untouched;
13. administrative/history functions are not blindly converted into present-tense predicates.

## 16. Governing result

active row != effective Membership.

effective Membership today != effective Membership on arbitrary date D.

effective Membership != current appointment != responsibility != product access != action authority.

Present authority that depends on Organization Membership must depend on present-effective Membership evaluated in a governed institutional calendar context.

Database time, Principal time, domain-local time, and institutional eligibility-calendar time remain distinct until explicitly related.
