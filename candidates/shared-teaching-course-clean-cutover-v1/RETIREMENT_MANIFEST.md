# Legacy Course retirement manifest — scope and exact deletion gates

Status: source inventory only, not permission to execute a DROP. Owner choices 2D and 3D govern deletion of 9 McMillan and 6 other old Course shells and exclusively related data AFTER a verified backup/restore. This document contains COUNTS and OBJECT NAMES ONLY, not research contents or user credentials.

## Private Course writer family — retain DATA, retire TABLES after exact migration

- titus.customer_course_drafts_v1: 1 canonical SK 101 identity to adopt, same UUID.
- titus.customer_course_material_revisions_v1: 1 top-level source manuscript revision (10,228 characters).
- titus.customer_course_units_v1: 2 authored Units (Class and Homework draft).
- titus.customer_course_unit_revisions_v1: 3 unit revisions, 111 combined characters.
- titus.customer_workspaces_v1: 1 old owner scope; must be removed only after replacing Person authority, not by granting old workspace access to everyone.
- Public source RPC family: titus_customer_catalog_self_api_v1, titus_customer_create_course_self_api_v1, titus_customer_start_workspace_self_api_v1, titus_customer_material_read_self_api_v1, titus_customer_material_save_self_api_v1, titus_customer_outline_read_self_api_v1, titus_customer_unit_create_self_api_v1, titus_customer_unit_move_self_api_v1, titus_customer_unit_read_self_api_v1, titus_customer_unit_save_self_api_v1; internal helper titus.customer_owned_course_for_units_v1.
- This family cannot be deleted until the canonical Person-created Course ID, all exact original historical records, idempotence receipts, app callbacks, access denial rules and guarded read/write paths are verified on clone. No old compatibility adapter after the final cutover.

## Old Course and School shells — DELETE data after restore equality

Direct Course family (row counts 2026-11-07):
- titus.courses: 15 Course shell rows (nine attached to the McMillan program, six others).
- titus.course_slots: 33.
- titus.course_teachers: 9.
- titus.course_lesson_placements: 1.
- titus.course_lesson_prerequisites: 0.
- titus.program_course_placements: 18.
- titus.course_slot_activity_log: 0.
- titus.curriculum_slot_placements: 30.
- titus.slot_canon_briefs: 4.
- titus.slot_teacher_source_candidates: 0.
- titus.canon_brief_items: 60.
- titus.slot_song_scopes: 15.
- titus.workspace_state: 1, includes old Course/Program pointers. Retire pointers and the workspace state row only after consumers are replaced.

Direct Program/Formation family:
- titus.programs: 1 retired McMillan program.
- titus.program_teachers: 1.
- titus.curriculum_versions: 2.
- titus.curriculum_decisions: 15.
- titus.curriculum_findings: 40.
- titus.canon_claims: 26, with titus.canon_claim_evidence 73 and titus.canon_claim_truth_links 46.
- titus.canon_structures: 5, with titus.canon_structure_nodes 59 and titus.canon_structure_edges 63.
- titus.formation_units: 3, with titus.formation_questions 12, titus.formation_unit_sections 18, titus.formation_unit_inputs 45, titus.formation_transfer_cases 3, titus.formation_responses 0, titus.formation_transfer_attempts 0, titus.formation_articulations 0.
- titus.teacher_source_adjudications: 49; titus.teacher_source_adjudication_targets: 30; titus.teacher_term_sense_targets: 15; titus.teacher_pattern_claim_links: 25.
- titus.lesson_claim_links: 27; titus.lesson_structure_links: 5; titus.lesson_script_segment_claims: 30; titus.lesson_teacher_source_links: lineage and population must be rechecked.
- Additional nested FK edges listed dynamically by read_only_preflight.sql; migration MUST refuse unexpected third-party dependents.

DO NOT infer every table listed must be globally dropped. Some (Formation, canon evidence, source adjudication) may be legitimate infrastructure for another use, even if currently only this program has rows. Explicitly DELETE the old-program-scoped records; DROP the TABLE itself only if its entire role is obsolete and no other product/source depends on it. The user's ban on leftover legacy Course tables does not authorize deletion of unrelated reusable source families.

## Independently sourced data outside automatic deletion

- titus.teacher_source_units: 160 rows in source catalog at audit.
- titus.lesson_packets: 16 independent lesson packets at audit.
- Noel canonical Song/Scripture source, real Person identities, unrelated Atlas Course/Work, and all private learning data beyond old-program lineage remain protected.
- Some obsolete Course rows reference these; REFERENCE does not imply exclusive custody. Verify no other consumers before deleting ANY such row.

## Named public views and legacy functions to retire after reader cutover

Old view dependencies observed: public.titus_course_prerequisites_v1 and public.titus_course_word_pattern_boards_v1 (the latter exposes independent pattern-board/lesson sources; remove only its obsolete view, not those originals), public.titus_courses_v1, public.titus_course_slots_v1, public.titus_course_path_v1, public.titus_course_preview_path_v1, titus.course_build_board_v1, titus.course_slots_admin_v1, titus.noel_deep_dive_queue_v1, titus.ready_to_promote_queue_v1, titus.v_program_curriculum_map_v2. Re-query pg_views because other views or later changes may depend on these. Drop only with RESTRICT.

Selected old Course-slot functions: public.get_titus_course_preview_packet_by_slug, titus.link_lesson_packet_to_course_slot, titus.mark_course_slot_in_sandbox, titus.mark_course_slot_packet_ready, titus.start_course_slot_deep_dive, titus.get_lesson_packet_template_for_slot. Re-query all functions referencing old tables, and remove their related grants and app entrypoints in a single reviewed cutover.

**Retire every old institution-first Atlas Teaching API, not just Course creation.** Source audit on November 8 found twelve SECURITY DEFINER public-function entrypoints; all twelve have exact SQL signatures and RESTRICT drops in `legacy_institutional_teaching_api_retirement_candidate.sql`. They are: institution Course creators (both variants), Course list/admin/retirement, Version publisher, Offering creator, Offering transition, roster reader, direct learner enrollment, learner withdrawal and enrollment reader. The old Offering and Enrollment **TABLES** remain the canonical operational relations, adapted to one Person-origin Course; the obsolete privileged RPCs do not remain as backward-compatible routes. Their exact signatures and unknown overloads are checked by the final catalog postcondition. A previously documented exception retaining `atlas.create_teaching_course_offering_self_api_v1` has been **superseded**: it is now targeted for removal, while the distinct source-issued governed shared Offering operation is retained.

**Protected source distinction:** Historical old Titus/McMillan Course/Formation rows are data, not API compatibility aliases. Remove exclusively old-root lineage only after private protected backup, successful actual restore, independent Row/UUID/UTF8 byte attestation and all direct consumers replaced. Reusable teacher-source libraries, lesson packets, Song objects and unrelated Person/Work originals must survive unchanged. Do not attempt indiscriminate SQL deletion or DROP CASCADE.

## Ordered deletion approval proof

1. Full protected DB backup AND private logical export of this entire FK closure; restore to a source-equivalent PG17 clone and compare all rows, dependencies and full SK 101 text with protected source manifests. Backup verified means restored, not simply created.
2. Freeze sources. Re-inventory all mutable counts and new FKs; reject drift. Prove which target rows have exclusive old Course/program lineage. Never use DROP CASCADE or DELETE with implicit cascade as substitute for this list.
3. First replace the Course, Unit, author-rights, institution/Version, and application read/write path. Validate exact SK 101 identity/content/history plus outsider/revocation checks.
4. On disposable clone, delete child rows explicitly from deepest edges toward only the old 15 Course shells and one McMillan program; preserve unrelated referenced source originals. Drop obsolete functions/views in exact dependency order, then obsolete tables using DROP ... RESTRICT, then confirm no final aliases or readers.
5. Compare protected before/after table-count differences: only authorized old-program and old-Course descendants were removed, all canonical/private SK 101 data kept, and unrelated tables are identical. Validate every app route and current user auth.
6. Protected source review, exact tested migration SHA, backup receipt, isolated signed tests and explicit owner approval of that particular destructive version/target before production. Postrelease verify, else execute governed recovery.

Do not create a fake duplicate Atlas Teaching Course to satisfy the old Ledger-required schema. SK 101 adopts its existing identity exactly once.
