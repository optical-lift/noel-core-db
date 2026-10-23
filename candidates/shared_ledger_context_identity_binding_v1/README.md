# Shared canonical Ledger context identity — Phase 1 candidate

**Status:** public-safe, source-only reviewed candidate. Do NOT run directly on production.
**Release lane:** `shared_` (Reality/Atlas Ledger identity interface).
**Dependencies:** Phase-0 architecture [noel-core-db PR #2054](https://github.com/optical-lift/noel-core-db/pull/2054); canonical Connection [Atlas PR #364](https://github.com/optical-lift/atlas/pull/364).

## What this implements

Each `ledger.ledgers` row may reference a distinct canonical `reality.entities` row of new kind `ledger_context` via a unique nullable `canonical_context_entity_id` FK. It is NOT the same as `ledger.ledgers.subject_entity_id`, which is the owning business. The context entity's `stable_key` must equal `ledger_context:<exact-ledger-uuid>`; the identity must already be `canonical`. A trigger prevents incorrect source binding, rebinding, or surreptitious Ledger/business replacement after establishment. Another guard protects bound Reality entity kind/stable key from silent mutation. A Reality identity may still be disputed or retired through an explicit governed process; downstream readers must then refuse it as an active canonical endpoint.

**This migration does not create any context entities, backfill existing Ledgers, register `participates_in_ledger` relationship kinds, or establish a relationship.** It does not grant permissions, implement a write API, expose people or health details, or alter existing Ledger seats. Existing production has three Ledgers (two owning business entities) and four Person/business groups appearing across multiple Ledgers, so no business-only backfill is lawful.

## Why one FK rather than another Connections table

The one-to-one column is an identity binding, **not** another relationship store. Reality entities remain the owner of canonical identity; Reality relationships remain the proposed single Connection source after separately governed establishment. The Ledger retains the operational context and compatibility history. Unique FK prevents two Ledgers from using the same context identity. The exact stable key prevents one Ledger receiving another's context entity.

Entity creation/adjudication is deliberately a separate stage; a service may not mint `ledger_context` identities simply because a Ledger exists. A later governed writer must establish the Reality entity under Shared Directory identity rules, using privacy-safe display/metadata, then bind it through an authorized source command and verify immutable receipt, without manufacturing another actor's assent.

## Rollout and safety

1. Review new column and triggers as a **shared** structural contract. Generate a real migration only after source PR passes custody checks.
2. Validate exact SQL on disposable production-schema clone. Test FK, uniqueness, trigger identity-kind and matching-key checks, immutability, absence of backfill, unchanged pre-existing seat counts and no public grant drift.
3. Release schema separately through protected custody; existing 3 Ledgers remain unbound and existing source writers remain authoritative until a later parity-tested cutover. New Ledger creation remains valid with null binding (so current onboarding is not broken).
4. In a separately reviewed identity-establishment build, create/adjudicate canonical `ledger_context` entities, bind exactly once, produce lineage receipts, and reread both Ledger and Reality source. No person–Ledger relationships are migrated in this phase.
5. Only when canonical relationship kinds, creation/contestation authority, and record permissions are proven can a new common Connect/Change/End command author relationships. Then historical Ledger seats become compatibility projections with non-destructive source lineage.

**Never treat `canonical_context_entity_id` presence as permission to see Ledger/client/private medical records.**

## Known proof limitation

The postconditions verify structural invariants, role grants and no actual identity backfill. They are not yet live proof of every negative trigger scenario or a two-actor permission test. Those must run on a disposable clone before promotion; this candidate is not proof of a completed canonical engine.

## Disposable negative-test fixture

`fixture.sql` creates synthetic Reality identities and a temporary Ledger-shape table inside an exception-handled subtransaction. It verifies a correctly keyed identity binds successfully; mismatched Ledger key, invalid kind, disputed identity, context/business alias, rebinding and silent business substitution fail with check violations. The outer subtransaction explicitly rolls back its temporary table and all synthetic Reality records. It **must only run in the disposable production-schema-clone validation**, never the production release. This does not test the bound-Reality-row update guard against actual Ledger backfill (there are no bound rows by design); that acceptance remains held for the separate identity-adjudication build.
