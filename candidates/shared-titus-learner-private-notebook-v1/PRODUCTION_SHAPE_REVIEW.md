# Production-shaped learner notebook source audit — HELD

**Status: BLOCKED until an independently reviewed source-shaped, signed clone.**

## Existing proof

Noel PR #2580 has passing isolated PostgreSQL 17 SQL/ACL and local genuine GoTrue OAuth/PKCE/PostgREST tests. The candidate SQL remains unchanged at Git blob d1a00f02b8673e8b016ab8ef124a52dbe40c8101. These tests use fictional simplified Teaching tables, not the actual Atlas Teaching schema. They do not establish real learner access, consent, or release.

## Live read-only catalog evidence (2026-11-06)

Production Teaching requires additional NOT NULL, no-default columns which the signed-local fixture omits:

- atlas.teaching_courses: course_key, name, created_by_person_id, created_by_principal_id
- atlas.teaching_course_versions: version_no, title, published_by_person_id, published_by_principal_id
- atlas.teaching_course_offerings: delivery_mode, created_by_person_id, created_by_principal_id
- atlas.teaching_enrollments: enrolled_by_person_id, enrolled_by_principal_id
- reality.entities: stable_key, display_name

The released foreign-key graph additionally requires atlas.ledgers, atlas.principals, atlas.capability_activations and atlas.capability_definitions. The real atlas.teaching_activation_active_v1 uses governed source, active Ledgers and capability definitions. Its checks cannot be replaced by the signed-local fixture's atlas.synthetic_capability Boolean.

The existing candidates/atlas-teaching-academic-kernel-v1/fixture.sql contains a better source-shaped fictional Ledger, principal and Teaching-definition example, but generates fake Auth users. Any production-shaped clone must instead obtain *real local signed* GoTrue OAuth sessions and write only fictional Atlas/Reality records linked to those synthetic local identities. No real Person, student or Course data is permitted in validation.

## Scratch package rehearsal

The companion scripts/stage-held-titus-learner-clone-source.sh generates a disposable shared_ migration using the pinned Supabase CLI, copies the original candidate SQL unchanged, checks its Git blob and source path, and deletes the scratch directory. It never moves SQL into this repository's supabase/migrations and cannot trigger a protected workflow.

This is **not** the canonical production-shaped test. Noel main's .github/workflows/production-schema-clone-validation.yml only accepts a separately approved owner issue and a separately reviewed, official numbered shared_ candidate package, with production environment approval before read-only role/schema dump. It does not automatically run our private notebook signed negative-access matrix.

## Remaining release holds

1. Source-review and build the production-schema-compatible **data-only** fictional fixture using genuine local GoTrue sessions and real constraints.
2. Integrate this candidate's exact signed learner/outsider/concurrency/withdrawal tests into the source-governed disposable clone harness without modifying production or lowering its authentication checks.
3. Independently review scratch packaging, immutable candidate SHA, generated version, read-only snapshot safeguards and no-PII diagnostic artifacts.
4. Only then may the real GitHub OWNER create a distinct exact-title production schema validation issue and separately approve the protected environment run.
5. Review the resulting clone evidence before any separately authorized migration, academic Offering, Enrollment or Titus UI release.

[Review-only issue #2591](https://github.com/optical-lift/noel-core-db/issues/2591) intentionally does not trigger protected production access. Both Noel PR #2580 and Titus PR #72 remain drafts.
