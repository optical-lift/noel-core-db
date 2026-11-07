# Canonical Teaching Course — clean cutover candidate v1

Status: SOURCE PLAN / NO LIVE MIGRATION. Date: 2026-11-07. Cross-domain structural lane: shared_. Repository owning SQL: optical-lift/noel-core-db.

## Binding owner choices

1A: A real Person creates a Course privately; an institution can later operate THAT SAME Course, without a second Course identity.
2D: Delete nine obsolete McMillan Courses, their parent program and exclusively related curriculum/data AFTER a verified backup.
3D: Delete the six other obsolete Titus Courses and exclusively related data AFTER a verified backup.
Preserve SK 101 — The Mechanics of Reality, the same Course UUID, all original manuscript text, author and Unit IDs, all edit requests, author/provenance, timestamps, ordering, and ALL historical revisions. Remove legacy Course tables, old RPCs, views, and permanent adapters after fully verified cutover.

This supersedes the proposed draft-to-institutional-Course bridge and the assumption that Course creation needs a Ledger, a Principal or Teaching activation. See Atlas Reality/Ledger Constitution, domain isolation, solo-owner structural release review, and the Titus one-Course correction in its product constitution.

## Observed live source, read-only

* Titus private author Course drafts: 1 (SK 101); top-level manuscript revisions: 1, 10,228 characters; authored Units: 2 (one lesson, one assignment draft); Unit revisions: 3 (111 characters total). SK 101 author resolves through exactly ONE active Reality Auth-to-Person binding; private workspace owner is confirmed. Current Course UUID is the canonical ID to preserve, subject to clone collision checks.
* Atlas institutional teaching: 0 Courses, 0 Course Versions, 0 Offerings, 0 Enrollments, 0 active Teaching activations. The existing Atlas Course table requires Ledger + Teaching activation + legacy Principal, and its independent creation RPC generates another UUID. Titus private Auth-workspace creation also generates a Course UUID. This is a defective pair of creation pathways, not two real Course originals.
* Old Titus curriculum: 15 Courses (nine attached to one McMillan program, six others), 33 Course slots, 18 program placements, nine Course-teacher links, one Course-lesson placement, one workspace-state pointer. One old program has two curriculum Versions, 15 decisions, 40 findings, 26 canon claims, five canon structures, three Formation units and deeper dependent evidence/relationship rows.
* Substantial further nonzero child data include 73 canon-claim evidence, 46 canon-claim truth links, 59 structure nodes, 63 structure edges, 60 canon-brief items, 30 curriculum-slot placements, 12 Formation questions, 18 Formation sections, 45 Formation inputs, three transfer cases, 49 teacher-source adjudications, 30 adjudication targets, 25 pattern-claim links and 15 term-sense targets. Do NOT blanket-cascade delete them. Confirm exclusive old-program lineage for each.
* Titus teacher_source_units (160) and lesson_packets (16) have independent custody/uses; they are NOT wholesale deletion targets merely because an obsolete Course references them. Other Noel/Song evidence must not be deleted by an unproven legacy curriculum relationship.

## Canonical target (one identity; not a two-Course bridge)

Durable Course table: atlas.teaching_courses. Reuse exactly the live SK 101 private draft course_id. No replacement UUID, mapping table or silent institutional adoption. Author signs in and the source resolves current auth.uid to the unique active reality.auth_person_bindings Person Entity. This Person may establish a private draft Course without an institutional Ledger, Principal, Teaching activation or payment. Author rights/idempotence/revocation are separately governed and source checked, never inferred from browser-supplied IDs.

Root Course is not required to carry ledger_id, capability_activation_id or created_by_principal_id. When an institution legitimately operates an already existing Course, establish separate source-authorized Course-to-operating-Ledger standing, with Teaching activation and legitimate authority checked for those institution-specific acts. Operating a Course NEVER creates a second Course original.

Replace older private-course storage with canonical source records under the same Course ID: proposed atlas.teaching_course_manuscript_revisions (top-level history), atlas.teaching_course_units (ordered Lesson/Homework authored material), atlas.teaching_course_unit_revisions (full Unit revisions), and atlas.teaching_course_operating_standings (optional institutional relation). Preserve every original revision UUID, request ID, original author evidence, exact full text bytes including Unicode/line endings, timestamps and ordering. Do not promote an editorial Homework draft to assigned Work.

Keep atlas.teaching_course_versions as immutable published academic DEFINITION; published full manuscript/encounter revision requires a separately verified source manifest, not an implicit Course-Version equality. Offering, real enrollment, assigned Work, student private note, disclosed submission, feedback and encounter remain distinct original relations, NOT new Courses.

One new signed Person-first Course creation source operation replaces both the Titus customer Course creator and Atlas Ledger-first/activation Course creators. Exact request replay returns same Course original; two different issuer paths cannot mint competing Courses. Canonical auth is Reality Person; legacy Atlas Principal path must not be a required dependency of new core.

## Ordered cutover (coherent phases; no permanent legacy)

M0 Inventory and backup. Source-read-only full list of tables, recursive FK chains, populated descendants, views, functions/RPCs, app callers, unique Person binding and zero target-ID collision. Freeze/source-fence new writes for release. Make full protected database backup AND separate private logical copies of SK 101 originals/revisions and all old-school data selected for deletion. Record source hashes/counts, migration ledger and backup metadata in protected custody, never in public Git. Restore to PG17 production-schema clone. A backup is VERIFIED only after restore plus exact data equality tests.

M1 Canonical schema/authority (protected clone). Refactor the empty Atlas Course root to Person-first: remove mandatory institutional/legacy-Principal dependency, preserve one durable Course ID. Implement canonical Course author source authority and append-only manuscript + Unit storage; signed owner/outsider/revocation/idempotence checks. Add optional governed institutional operating standing. No live DDL and no dual Course writers.

M2 Exact SK 101 adoption in clone. Insert canonical Course using the existing private UUID, not a new one. Copy both Units and all four saved revision originals, preserving every exact ID, source request, author, timestamp, sequence and body. Compare bytes to protected snapshot without publishing text, verify no duplicates or lost revisions, confirm one Person and one Course. Keep Atlas published Course definitions separate from author drafts.

M3 Consumer replacement with no shadow path. Replace Titus private catalog/manuscript/Unit API readers/writers and authoring routes to use this SAME source Course; replace older Atlas root Course creation and relevant institutional readers. No permanent compatibility table, aliases or dual-write. App routes may keep user-facing URLs, but not private duplicate source backends. In a controlled maintenance window stop all old writers before cutover.

M4 Delete owner-retired curricula and legacy storage IN A RESTORED CLONE FIRST. Explicitly remove all 15 old Course shells and one old McMillan program plus descendant rows proven exclusive to them. Resolve the nonzero FK tree including canon/Formation/adjudication/evidence tables. Keep independent teacher source libraries, separate research originals and unrelated lesson packets. Remove obsolete Course/slot/program-centric tables, exposed views, stored RPCs, triggers/constraints, app code and fixtures using reviewed explicit DROP RESTRICT, never CASCADE. Remove Titus customer_course_drafts_v1, customer_course_material_revisions_v1, customer_course_units_v1, customer_course_unit_revisions_v1 and old Course-only customer_workspaces_v1 once their access model is wholly replaced. No old public.titus_customer_* RPC remains.

M5 Protected negative tests and separately authorized production release. Full-schema clone demonstrates one Course ID, exact history, Person-origin creation with no Ledger, optional later institutional operation of the SAME ID, private author/outsider/revocation denials, immutable published definition, no disguised student Work, old tables/RPCs/views absent and zero unrelated data changes. Only then record owner authorization for an exact generated migration, source/target, backup restoration receipt and protected release path. No direct production schema write through ordinary execute_sql. Coordinate app release under old-writer freeze; check production post-release equality and restore plan.

## Mandatory release postconditions

- One SK 101 canonical Course with the SAME old UUID; old 15 Courses not silently imported as canonical Courses.
- One original top-level manuscript revision (10,228 characters at source snapshot), three original Unit revisions and two Units. Their identifiers, original text and full history survive byte-for-byte.
- No required institutional Ledger, Teaching activation, old Principal or private Titus workspace for Person-initiated Course creation. Institutional operating attachment retains SAME Course identity.
- No obsolete private Titus Course tables, duplicate Course registry, legacy McMillan/other old Course shell tables, obsolete reader RPCs or public wrapper views, or permanent adapters; no DROP CASCADE.
- Reusable unrelated source libraries and original research unchanged; each old-program descendant deletion is individually accounted for.
- Signed negative security tests pass, clone backup restore/equality proven, exact owner production approval recorded separately.

## Current source delivery and blockers

This candidate contains an executable READ-ONLY preflight for database introspection and clone checks, plus structural postconditions. These are not schema migrations and do not authorize any deletion. Still open: complete Person-first replacement source writer/schema, source-covered exact copy, ALL affected application consumers, full private backup+restore, protected clone tests and explicit owner approval for the final release. The next coherent structural implementation batch must produce a real reviewed shared_ candidate plus signed test harness; PR does not merge or deploy until those gates pass.


## M1 source implementation now present (HELD; not a tested migration)

The same draft PR includes a guarded, non-generated source candidate at person_first_candidate.sql and read-only person_first_clone_postconditions.sql. This M1 source adapts the **existing empty atlas.teaching_courses root**, creates canonical manuscript/Unit revision tables as facets of that same Course, and defines a first Person-authenticated idempotent Course creator. Its actor is resolved only through exactly one current Reality Auth→Person binding. A supplied Course UUID is never authority. The old mandatory Ledger, activation and Principal columns become nullable in this **staged clone-only candidate**; a separate future reviewed cutover must remove obsolete columns, replace older institutional APIs/guards, add optional institutional operating standing, copy the SK 101 original exactly, and delete all old tables/functions. **M1 does not yet satisfy the no-legacy end-state.**

The M1 candidate refuses to run unless an independently controlled clone transaction sets app.shared_course_clone to approved. It DOES NOT open or commit its own transaction. Static source is not signed security acceptance: the M1 candidate has not passed a protected full-schema clone or independent GoTrue owner/outsider/revoked tests and must never be used as live SQL. Future migrations must be generated under the governed release workflow, not by renaming the candidate.

Additional source: RETIREMENT_MANIFEST.md enumerates the nonzero descendants, ambiguous source libraries, old public views/RPCs, and DROP RESTRICT gates. A deletion set is not approved by table-name similarity; use direct and recursive FK evidence and protected backup restores.

**Next M2 engineering:** source-owned copy/adoption operation using the existing SK 101 Course UUID; exact old/new row equality within protected clone; author/Unit read/write and replay permission APIs; one source-only institutional standing without duplicate Course. Then M3 app source cutover, M4 explicit scoped retirement, M5 full integrated signed tests and owner-controlled production release.
