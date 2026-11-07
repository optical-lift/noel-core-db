# Universal Program participation — source candidate 1
**Date:** November 1, 2026 · **Custody lane:** shared Atlas Person / Atlas Program / Titus Curriculum
**State:** SOURCE-STAGED; unexecuted and unreleased; no writer, no issued invitation or grant.

## One bounded result
Introduce **one original invitation** and **a separate, explicitly accepted participation** tied to an existing immutable approved Atlas authored-Program version **or** a named Titus curriculum version. Neither table copies a course, classroom, lesson or Work object. It is the shared relationship substrate requested in the October 26 Atlas universal Program participation handoff and Universal Titus decisions 2C/3D/4D/9C.

The two tables are not intended to substitute for the rest of the Atlas Program participation project. This is the **invitation/consent custody slice only**. Request/approval and self-start entry remain permitted design paths, but have **not** been implemented. Module-scoped teaching, authoring, source review, historical disclosure, activity/Work, and coaching remain explicitly independent.

## Owning source / relationships
- `atlas.personal_training_programs` + `atlas.personal_training_program_versions` own approved Atlas personal Program source and version.
- `titus.programs` + `titus.curriculum_versions` own native Titus curriculum and version.
- `atlas.people` owns the participating Person representation; sign-in must resolve through current active canonical Reality identity and Atlas credential binding.
- `atlas.universal_program_invitations_v1` is an offered relationship, **NOT enrolled status**. One exact original/version, invitee, purported issuer, timestamp and proof artifact digest. Actual issuance requires the *future* source-governed governor/delegate writer that verifies current subject authority. Stored proof bytes are NOT themselves authority.
- `atlas.universal_program_participations_v1` can only refer to an accepted invitation for that same Person. Consent is distinct from invitation issuance and is still NOT a role grant.
- The first SQL package intentionally exposes no REST/public APIs, authenticated table reads, DML or RLS policies; tables force RLS and privileges are revoked. No source text or learner response is stored here.

## Source safety / exact protections
1. An invitation must have **exactly one** source family and valid source version. The trigger checks the version belongs to that original; an Atlas authored Program version must be approved. A Titus version reference is checked for program membership but **not** a license or release. The future issuance writer must separately verify Titus curriculum review/release authority.
2. Repeated concurrently pending invitations for the same Person+original are rejected by partial uniqueness; request keys are idempotency inputs, not proof of permission.
3. State `pending_acceptance` never supplies a `learner`/ `teacher`/`author` role. Nothing auto-populates the existing Titus `subjects` array. A pending invitation preview is allowed only when a **future** signed source reader verifies exact invitee + session + invitation currentness and preview disclosure scope.
4. Participation requires a corresponding `accepted` invitation and direct consent evidence; the first source writer must atomically enforce current invitation status/expiry, actor identity, version, replay and historical event custody before live acceptance is possible. **There is deliberately no writer in this PR.**
5. No general teacher title, historical Marlene profile, Auth email, Constellation viewer grant, owner-principal authorship or arbitrary UUID is sufficient to issue an invitation, study a lesson or delegate.
6. All learner notes, source excerpts and song candidates retain their separate Titus/Noel source and disclosure gates; this package contains none.

## Acceptance tests and unfulfilled dependencies
`structural_postconditions.sql` is intended for a **disposable production-shaped database clone** after applying `source_candidate.sql`. It asserts FORCE RLS, denial to anon/authenticated/service_role table access, no PUBLIC DML and exact source triggers/constraints. This script is written but has not been executed.

Before any real issuance or acceptance:
- Add and independently review the current-Person, governor/delegate, exact subject-version **issuance writer**, with signed wrong-issuer/expired/revoked evidence and clear authority provenance.
- Add governed `accept invitation` writer: requires verified live session, exact invited Person, explicit affirmative consent, current invitation, idempotent request; creates one original participation. Deny foreign Person, replay, expired invite and source withdrawal.
- Add append-only state change/retention history before transitions; no silent rewrite of approved Program, prior consent or source version.
- Add a signed **invitation-only** reader returning bounded title/status, **not** lessons/roles. Extend the existing source-authorized Titus home reader only after approved source.
- Independent signed tests with synthetic clone identities then real principal-selected Person and another authorized Person; Atlas/Titus UI and alternate readers/Index/search/cache denial; exact source-rights review for historical Marlene writing.
- Preserve the 30 universal Atlas Program decisions and 32 Titus/Discovery University decisions. No testing identities, consent, enrollment or source release is created by this development PR.

## Completion accounting
- **Done:** source candidate for two separate, version-bound private relationship originals, structural postcondition source.
- **Not done:** apply source to clone/live, signed tests, issuer and consent writers, revision events, authority grants, real study access, real PR approval, Preview or Production. No release authority inferred.
- **Next bounded gate:** source-authorized issuer validation and accepted-participation atomic writer in an isolated production-shaped clone, with event history and signed denial; do not expand this PR's scope if governance requires separately reviewed increment.

## Source receipt — November 1, 2026
- Draft [PR #2439](https://github.com/optical-lift/noel-core-db/pull/2439) at commit `094100dbb20bc502ca68e454c82ed1cd765d6431` passed **Database Custody CI run [#41373247912](https://github.com/optical-lift/noel-core-db/actions/runs/41373247912)**. This is repository source-custody validation, not database execution.
- The shared Titus authorized-home reader candidate at [PR #2438](https://github.com/optical-lift/noel-core-db/pull/2438), commit `6a5679ae3be74792a3632621586cdf64a0a0c71f`, passed its separate **Database Custody CI run [#41373341349](https://github.com/optical-lift/noel-core-db/actions/runs/41373341349)**.
- Eleven read-only source-invariant checks were inspected against the actual GitHub candidate: separate invitation and participation tables, Atlas/Titus original version FKs, exclusive source shape, accepted-invite Person match, no inferred capability, both FORCE RLS, no public writer, no direct grant, immutable original identifiers/consent, and no private research bodies. All passed as **static source checks only**.
- No disposable PG clone or signed negative/positive HTTP tests have been run. No new live relations, issuer permissions, invitations, acceptances, author rights, teacher rights, course releases, keys, PR merges or deployments were created.

## Source correction after first CI receipt
Candidate trigger code was tightened at commit `68da8a317de42dce06c9bbb7b8ba47df61550f11` to reference PostgreSQL `OLD` row fields **only inside an UPDATE branch**, never during INSERT. Eleven new read-only source invariants passed at this exact code revision, including immutability, source FKs, required acceptance and no general grants. The prior Database Custody CI receipt applies to its stated earlier SHA, not automatically to this new one. A fresh CI run is required before considering the exact current source green. No SQL was executed or released.
