# Validation target

Issue: #880

Prerequisite production migration:
- 20260920154717_atlas_organization_membership_calendar_context_v1

Candidate:
- candidates/atlas-present-membership-effective-time-phase-b-v1/candidate.sql

The fixture builds:
- an Elm-shaped Organization with America/Chicago Membership Calendar Context;
- current bounded member;
- current bounded owner;
- future owner who independently carries Principal Ledger root_governing authority;
- expired member;
- active setup_actor;
- exact Endpoint grants;
- an Organization Connected Source;
- current/future employee seat + credential + Position Appointment evidence;
- a Company Work item;
- a completed historical Work allocation;
- a second Organization with no Calendar Context containing both unbounded and bounded Memberships.

The postconditions prove the first Phase B root-seam cutover while preserving explicit service-date and historical Work truth.

Promotion rule: generate a fresh migration identity with the repository-pinned Supabase CLI workflow after this complete candidate packet is merged, then validate the generated immutable SHA through the production-schema clone lane.
