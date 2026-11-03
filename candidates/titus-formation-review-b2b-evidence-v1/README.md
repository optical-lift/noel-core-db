# Titus B2B — source evidence for one learner / reviewer / released edition

**Status:** Draft *source-only evidence matching increment*, **not** actual issuance, lawful consent, teacher appointment, access grant, executable feedback writer, or a release.  
**Owner:** Noel core DB Titus Formation custody; [Build B2 issue #2461](https://github.com/optical-lift/noel-core-db/issues/2461).  
**Stacked after:** [B2A candidate #2463](https://github.com/optical-lift/noel-core-db/pull/2463).  
**Reader expectation:** [Titus B1 draft #27](https://github.com/optical-lift/titus/pull/27) requires authorized source history; no Titus UI changes here.

## Bounded result

Three independent, exact-subject **candidate evidence carriers** live in proposed private `titus` source tables:

1. **Edition evidence**: one named Program, existing Curriculum Version, Formation Unit, recipient learner Person, edition fingerprint, *separate* educational review, rights-clearance, and release decision reference IDs, named issuer, effectiveness, expiry and withdrawal. It is not established simply because `curriculum_versions.version_status='frozen'` or because a UUID is present.
2. **Response disclosure evidence**: one exact `formation_response_id`, the recipient learner and exact reviewer Person, learner-asserted consent source reference, expiry and withdrawal. A generic program invitation or historical `teacher_id` cannot serve as consent.
3. **Reviewer mandate evidence**: an exact Program/Unit/learner/reviewer connection through the same release reference, a separately identified issuer/mandate source, one operation `review_learner_response`, expiry and revocation. It is not an Atlas Principal, global `teacher` flag or approval to publish a course.

The internal, SECURITY INVOKER `titus.formation_review_evidence_match_v1(p_formation_response_id uuid)` returns only a boolean **structural match**, no student names/content/roster and no assertion of authorization. It derives the actor exclusively from existing `titus.current_authenticated_person_entity_id_v1()` (the source-owned live-session / Person resolver). All three records must simultaneously fit the actual existing response/Unit/profile/Program, same exact release, same enrolled-in-Formation learner Person and exact reviewer. Frozen/published curriculum status is necessary but not sufficient. Current Unit review/phase, current learner binding and submitted response are also required. A response predating a release cannot be retroactively treated as released.

**Important:** These reference fields do not themselves verify whether their claimed issuer really possessed source rights, whether the indicated person genuinely consented, whether there is an authentic educational review, or whether this version is the exact frozen content closure that the learner encountered. There is **no** currently released canonical issuer/writer for any of these three candidates. Even a positive *fictional* `evidence_match` does not authorize a real response read/write. A future operational reviewer check must independently verify original source-issued receipts, issuer authority, source license, audience/consent, real session, cross-Person disclosure and revocation at the mutation boundary.

## Protected scope and why this is not a permission system

- No Titus Person, Atlas institution, Course, Offering, Enrollment, student account or faculty position is created.
- The tables are **private, RLS-enabled, denied direct `anon` and `authenticated` privileges**. The private function has no public API or browser EXECUTE grant.
- B2A `titus.formation_response_work_authority_gate_v1()` stays **hard false**; no other source gate, JWT claims or authentication service is altered. **No public RPC** is added.
- No original `titus.formation_responses` content is read by the CI fixture from a real database; no `raw_text` value is returned by the proposed function.
- No production migrations or Supabase changes, no GoTrue/REST, no schema release/PR merge, no Atlas/Titus frontend changes, no Vercel Preview/Production.
- The proposed private tables are *not* an endorsed new authority ontology. Their exact physical form needs review against any real issuer/source-license/approval carrier before migration. If a canonical issuer already exists when implementing, point references to it rather than duplicating permissions.
- For B2A, references to a hypothetical `teaching_release_ref` in the event carrier do not create such a release; B2B’s proposed evidence is likewise not self-validating.

## Disposable test

The GitHub Actions workflow runs empty PostgreSQL 16 with fictional Person IDs, a minimalist existing-Formation schema, a **fixture-only stand-in for current authenticated Person**, and B2A’s source-only candidate loaded with its writer gate **false**.

The fixture checks:
- no asserted evidence → false;
- edition only → false;
- edition + learner disclosure without reviewer mandate → false;
- all three exactly matching → **true only as structural matching**;
- different acting Person/learner self-review/no Person → false;
- revoked mandate, withdrawn consent/release, expired entries → false;
- wrong reviewer, wrong response, wrong Formation Unit, different Program/curriculum version, draft version, stale Unit, retired learner binding, unsubmitted response, and original response predating a release → false;
- RLS and no `anon`/`authenticated` data/execution grants; B2A writer gate remains closed.

**Not tested:** actual issuer/consent proof, live signed identity, real tenant isolation, production-shaped schema, authenticated HTTP, historical original attribution, immutable curricular review closure, revocation/concurrency under a writer transaction, any real teacher feedback.

## Next bounded owner work

**B2B-issuance:** Determine whether existing governed Titus/Noel/Atlas carriers can prove (a) exact author-accepted edition, educational review and rights clearance; (b) a responsible issuer/steward with specific reviewer appointment; (c) learner-specific consent for one response. Do not treat the three test table INSERTs as these operations. Explicitly identify issuer, author, source holder, learner and reviewer as potentially distinct Persons and source scopes.

**B2C:** Only after those real receipts exist, design an authenticated response-specific read and teacher review RPC that checks original respondent attribution, current authority and exact last event in the same transaction as the immutable feedback append. Learner revision must save a new `titus.formation_responses` original and its event link atomically; do not promote a mock browser status to canonical truth.

**Release-quality gates:** Production-shaped disposable schema clone, genuine separate local GoTrue/REST signed Person sessions, positive only for lawfully issued test permissions, negative wrong Person/recipient/Unit/edition/revocation/expiry/concurrent replay, source-body non-leak, historical correction/retention policy, actual rights/adjudication review. Keep both PRs draft and production unchanged.


## B2B first-increment source acceptance receipt — November 3, 2026

**Exact tested SQL/workflow source SHA:** `6fe4db32964308895a8c986859ca84ed77025c9c`.

- [Isolated B2B PostgreSQL proof #41676836046](https://github.com/optical-lift/noel-core-db/actions/runs/41676836046): **SUCCESS**, all source-boundary, fictional fixture, three-source match, negative withdrawal/revocation/response-lineage/version/Person checks, and teardown passed.
- [Existing Titus Formation Custody #41676835887](https://github.com/optical-lift/noel-core-db/actions/runs/41676835887): **SUCCESS**.
- [Database Custody CI #41676949387](https://github.com/optical-lift/noel-core-db/actions/runs/41676949387): **SUCCESS** for the draft PR.
- [Noel draft PR #2464](https://github.com/optical-lift/noel-core-db/pull/2464): only five B2B source, fixture, test, workflow and register files; stacked after B2A draft #2463. No migration, merge or browser grant.
- A **separate read-only live `noel-core` schema query** returned all proposed B2A/B2B source tables and functions **absent**. That confirms the changes have not been applied; it does not confer release status.
- The test has a fictional current-Person stub, not real Auth. A UUID-shaped educational review reference, rights clearance reference, consent reference or reviewer mandate source reference **is not proof of authentic issuance**. No live reviewer authority was established.

**Truthful status:** B2B evidence *schema/read-model candidate* complete and verified as source-only. **B2B real source-issued educational approval/rights, recipient consent and reviewer mandate is still unresolved.** B2C authenticated teacher feedback/revision writer and genuine signed isolation test remain **not implemented**. Preserve the existing open owner issue and completion register. Do not use this candidate's boolean as a permission gate.


## Subsequent B2B source-issuance boundary (November 3, 2026)

[Draft PR #2466](https://github.com/optical-lift/noel-core-db/pull/2466), stacked on this B2B draft, adds a **private, deliberately fail-closed source-issuance verifier** in `candidates/titus-formation-b2b-issuance-verification-v1/`. A read-only source inventory inspected historical Titus program/teacher, lesson/curriculum, formation and Person carriers, `draft.reality_source_rights`, study consent, and Atlas institutional teaching/Foundry operations. None has yet been shown to issue **the complete exact-edition rights/review/release + learner response disclosure + reviewer mandate combination**. The new verifier returns `false` for every argument rather than treating UUID-shaped B2B references as permissions.

[Isolated PostgreSQL 16 verification #41704428728](https://github.com/optical-lift/noel-core-db/actions/runs/41704428728) **PASS**; [Database Custody CI #41704428837](https://github.com/optical-lift/noel-core-db/actions/runs/41704428837) **PASS** at exact tested source SHA `0432455a503e41877fc49771020dc74d851ecdb7`. All fixtures remain invented, not GoTrue sessions. The source-authorized issuance operation, actual rights and consent, signed Person review and B2C writer remain **NOT DONE**. The B2A writer gate remains false. No merge, deployment or live permission change is authorized.
