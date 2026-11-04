# Shared Smart Contacts — vendor qualification safeguard (held)

## Scope
A source-only, additive change to the existing `atlas.smart_contacts_search_service_v1` return payload's `researchGaps` array. No new table, role, grant, permission, Work, outreach authorization, or canonical entity ID. The signed wrapper remains unchanged.

## Bounded acceptance
* Directory-only mobile-food claims add `mobile_service_third_party_only_verify` until independently backed by first-party or owner-verified current evidence.
* A source-backed stale location superseded by a conflicting later public location adds `reported_service_area_conflict_verify`.
* An official event-appearance policy adds `appearance_terms_require_direct_confirmation` (not an assertion of event availability).
* Genuine first-party food-truck evidence prevents the false conclusion that a retailer/caterer cannot also operate a food truck.
* Historic evidence is not deleted; stale location can be requested with `includeHistoricalSignals`.
* Empty/no-query and regular contacts preserve the existing JSON fields and original source permissions.
* Tests must prove signed membership access remains scoped, the reader has no writer side effects, the three positive gaps work, the first-party exception works, and a missing source cannot create a booking.

## Why
November 4 Elm Farm Christmas contact research confused business identity, food-truck capability, current operating geography, and suitability/availability for one event. A 417 Food Trucks third-party report was treated as equivalent to first-party booking terms. Dated source corrections were made in Shared Intelligence public research rows; this candidate is the separately reviewed future-reader guard.

## Release custody
Use the canonical owner-approved migration-source generation pipeline after candidate review and merge to main; run disposable clone + signed negative tests, publish only via protected manual release. No production function change or migration is authorized by this candidate alone. The fixed live public research rows are a distinct **data transaction**, not a migration.
