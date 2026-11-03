# Titus B2B — authentic source-issuance verification boundary

**Status:** SOURCE-ONLY, fail-closed, not a real issuer or permission grant.  
**Owns:** Titus Formation custody in `optical-lift/noel-core-db`.  
**Issue:** [#2461](https://github.com/optical-lift/noel-core-db/issues/2461).  
**Stacked on:** [B2B fictional evidence matching PR #2464](https://github.com/optical-lift/noel-core-db/pull/2464), which is stacked on [B2A event carrier PR #2463](https://github.com/optical-lift/noel-core-db/pull/2463).

## One bounded outcome

Provide a **separate internal verification seam** that will never mistake a structurally matching edition/consent/mandate reference for *genuine source-issued authorization*. Until independently auditable current issuing sources exist, `titus.formation_review_source_issuance_verified_v1(uuid)` returns **false for every argument and caller**, including a fictional structurally matched response. It has no browser execute grant and cannot open the hard-false B2A writer.

This is a deliberate **denial boundary**, not implementation of actual issuance and not a release. The prior `formation_review_evidence_match_v1` continues to describe *only structural consistency*. Future B2C review/read/feedback operations must require *both* that check and independently verified source issuance and revocation under their own transactional authority; neither alone suffices. The source-issuance verifier cannot be loosened merely by inserting records into any of the three proposed B2B evidence tables.

## Read-only source-carrier audit — November 3, 2026

| Inspected source | What it can establish | Why it does **not** issue the requested permission |
| --- | --- | --- |
| `titus.programs`, `program_teachers` | Historical Program and teacher profile relation | `teacher_id` is not a current reviewer Person with an operation-specific mandate. |
| `titus.teacher_person_bindings` and `current_authenticated_person_entity_id_v1()` | Active historical teacher self-binding; separately, signed-current-session canonical Person resolution | Identity/self-access is not reviewer appointment, review permission or consent by another learner. |
| `titus.curriculum_versions`, `formation_units` | Program/Version status, Unit phase and review state | Frozen/published version and current Unit are not signed edition fingerprint, author agreement, rights clearance and recipient release. |
| `titus.lesson_reviews` | Historical lesson review carrier, currently no rows in inspected live table | Text reviewer and lesson status do not establish source-owned educational approval or reviewer Person mandate. |
| `draft.reality_source_rights` | Source-key rights classification for research use (46 inspected; 20 unknown) | No verified, particular Formation edition / private recipient / exact reuse authorization. A source-rights row is not a teaching-release issuance. |
| `draft.human_expression_participant_consents` | Consent for a distinct research study | Cannot substitute for this learner's disclosure of one Formation response to one reviewer. |
| `atlas.teaching_courses`, `teaching_course_versions`, `teaching_course_offerings`, `teaching_enrollments` | Canonical institutional Course/Version/Offering/Enrollment | Institutional enrollment alone neither issues private Titus source license nor authorizes review of one response. No fictional institutional course is created. |
| Atlas Foundry source-custody review functions and delegated agent authorizations | Distinct custody/reviewer and delegated execution operations | Source-custody technical review or delegated agent execution does not create learner consent or author/publisher rights. |
| `titus.song_object_public_release_gate_v1` | Song-object publication candidate read-model | Not a rights-cleared private teaching edition with named recipient/reviewer. |

**Conclusion:** This inspected inventory does not demonstrate a canonical issuer with live, independently verifiable, scoped receipts for *each* of educational review, source rights, one named-learner teaching release, exact-response learner consent, and reviewer mandate. An absent verified issuer is a hard stop, not an invitation to create fictional approval rows.

## Sources, protected scope and acceptance

- **Owning source:** Noel's canonical `titus` Formation custody, under `schemas/OWNERSHIP.md`, `architecture/TITUS_FORMATION_CUSTODY_V1.md` and `docs/DOMAIN_WORK_ISOLATION_V1.md`.
- **Dependencies:** existing B2A (closed append-only carrier), B2B (unissued evidence matching), current source Person/session resolver; actual future teaching edition/consent/mandate issuer remains unresolved.
- **Protected:** live DB, auth, original learner text, private teacher-source content, Atlas ledger and Course/Offering/Enrollment, application UI, publication, GitHub merges and deployment.
- **Acceptance:** on disposable PostgreSQL 16 with invented records only: B2B structural coherence can return true; separate issuance verification must stay false even after valid-shaped source references are substituted; NULL, wrong Person, no Person and wrong response also deny; `anon`/`authenticated` have no execute rights; `SECURITY INVOKER`; B2A writer gate remains false; learner originals unchanged.

Fixture success is NOT a signed GoTrue/PostgREST positive authorization test. The disposable schema is intentionally a minimal synthetic stand-in, not a production-shaped clone.

## Completion register — source increment

| Requirement | Result |
| --- | --- |
| Read existing issue #2461 and PR #2464 | Confirmed open/draft, B2B head `e20232bee1d154656afb4622c5758e07e000208b` |
| Compare Titus, Noel/research and Atlas source carriers | Inspected live metadata and current Person resolver; no full authentic issuer demonstrated |
| Preserve original B2A/B2B draft implementations | No edits to the older candidate SQL or hard-false writer |
| Stage one closed issuer-verification operation | **Source staged** in `candidate.sql`; all callers always denied |
| Demonstrate fake positive cannot issue permission | **Test staged** in `postconditions.sql`; see CI receipt below |
| Real source-issued edition, rights, consent, reviewer mandate | **NOT established / no grants made** |
| Signed separate current-Person test, immutable original policy, production clone | **NOT done** |
| B2C feedback/revision writer and university release | **NOT done** |

### CI and release evidence

The isolated source workflow is `.github/workflows/titus-b2b-source-issuance-closed.yml`, using the existing B2A/B2B disposable fictional fixtures and a separate final negative-only gate proof. **Verification is pending until the exact GitHub run is inspected.** No live Supabase DDL is executed by this workflow.

Read-only live PostgreSQL catalog confirmation on November 3 found all five proposed B2A/B2B tables/functions checked **absent** from deployment. No production data or permissions were written.

### Next unfinished source operation

Before enabling a reviewer read or writer: identify and authorize the **real issuing source**, its stewardship Person, exact signed/versioned edition fingerprint and rights-covered source inputs; separate author approval, rights-holder clearance, educational review, named learner release, response-specific learner disclosure, and reviewer appointment (including revocation and expiry). Reuse an established carrier if it actually governs each operation; otherwise specify only the smallest missing source-owned issuance/acceptance operation, then test with independent current Persons on a production-shaped disposable clone. Do **not** turn the existing UUID-shaped references into actual approvals, and do not open the B2A gate.

Keep [issue #2461](https://github.com/optical-lift/noel-core-db/issues/2461) open; Build B2C and Builds C–E remain separately queued.
