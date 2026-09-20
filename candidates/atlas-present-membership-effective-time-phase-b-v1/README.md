# Present Organization Membership Effective Time Phase B candidate

Candidate source for issue #880.

This candidate depends on Phase A Organization Membership Calendar Context and must not be promoted or released before that migration is live and verified.

## Core change

One exact predicate becomes the present-time Membership law:

`organization_membership_present_effective_at_v1(Membership, Organization, instant)`

It preserves:

- unbounded active Membership as current without a calendar row;
- bounded Membership only when the Organization's governed Membership Calendar Context resolves the instant to an eligible civil date;
- fail-closed bounded Membership when calendar context is unresolved;
- explicit service-date eligibility as a separate law.

## Root seams cut over

- current Membership resolution;
- member and owner predicates;
- effective owner Membership branch while preserving Principal Ledger root governance;
- Endpoint exact capability reads;
- Endpoint grant write guard;
- Endpoint owner-compatibility lifecycle;
- Endpoint grant/configuration owner commands;
- Connected Source management owner authority;
- Connected Source read visibility for ordinary present-effective members;
- employee appointment projection;
- Company Work planning actor Membership;
- current session Organization Membership projection;
- Organization employee-access projection.

## Important separation

Connected Source read visibility remains broader than management authority:

- present-effective ordinary member may see that an Organization source exists;
- only present-effective owner or active setup_actor may manage Organization sources.

## Endpoint compatibility continuity

Owner compatibility grants no longer reject bounded Memberships categorically.

They remain usable only while owner Membership is present-effective. A Membership update that crosses from a non-effective state back into an effective state revokes any surviving compatibility grant rather than silently reviving it after a temporal gap.

## Validation packet

`fixture.sql` and `postconditions.sql` now prove the Phase B root seams against a disposable production-schema clone, including future/expired/current bounded Membership behavior, unbounded no-context behavior, bounded no-context fail-closed behavior, independent Principal Ledger root governance, Endpoint authority, Connected Sources, employee/access projections, Company Work, explicit service-date semantics, and historical Work preservation.

Promotion must use the governed Supabase CLI generator and the immutable production-schema clone validation lane.
