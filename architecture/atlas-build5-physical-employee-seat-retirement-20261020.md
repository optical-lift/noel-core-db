# Atlas Build 5 — Physical employee-seat retirement

This is a physical removal of the obsolete **organization employee subscription seat** as an authority, identity and billing gate. It is **not** retirement of a canonical Person, authenticated credential, native Ledger connection, Organization Membership, recorded Position, historic Work allocation, service-day record or audit trail.

## Before retirement

- The canonical Person / native Ledger relationship is already the basis for offering Work and standing responsibility. Its source, API wrappers and production releases are complete.
- The legacy subscription table still has one seat and the live credential references it using `ON DELETE CASCADE`. Deleting the seat directly would destroy the credential.
- Fourteen executable Atlas functions still contain seat dependencies (one additional obsolete trigger guard belongs only to the table). Existing membership-based Work is real history and stays.
- Identity, credential and Position are distinct. A native Ledger connection alone must never grant institution management, farm execution, special exposure, or Position authority.

## Migration

1. Abort if any original seat has no credential to receive its evidence, if historic standing/exposure rows still refer to seat IDs, or if a live pilot session / issued invitation could be disrupted.
2. Archive exact pre-retirement seat rows into **existing** credential provenance, including prior billing state, without fabricating any new Work or Position.
3. Move legacy verified-institution access and farm execution from paid seats to **current exact authenticated credential + active matching membership + institutional Person identity**, retaining separately required farm membership, Position appointment, unit, date and policy checks. Native Person-to-Ledger scope remains independent.
4. Revise legacy invitation acceptance so it issues only a verified identity/credential, never creates a billed seat.
5. Remove three unused seat FK columns, drop original seat table with **RESTRICT** (no CASCADE), then remove the otherwise-unused seat-bridge trigger function.
6. Assert table/fields absent, live credential and canonical Principal intact, historical Work allocations and Position appointments retained, and no SQL function references the physical table.

A few legacy return payloads retain **null** `employeeSeatId` and legacy `accessClass` discriminants temporarily so existing shipped notebook code can still route old credential-bearing accounts. Those are compatibility vocabulary, **not fabricated employee seats** and cannot establish financial or management authority. Their eventual renaming is an application presentation cleanup independent of physical retirement.

## Release boundary

The candidate is source-only until repository custody CI, production schema-clone validation, immutable generated migration review, and explicit protected database release pass. A production release is not implied by merge. Run source-preservation and negative-permission checks before claiming completion. Failure must leave production untouched.
