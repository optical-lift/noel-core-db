# Titus first-draft original Formation response provenance

**Status: SOURCE ONLY.** Existing [Noel owner issue #2461](https://github.com/optical-lift/noel-core-db/issues/2461). Stacked after draft [#2467](https://github.com/optical-lift/noel-core-db/pull/2467). No production migration, real user response, release permission, learner consent, or teacher review.

## First draft: one small outcome

Make the **existing** `public.titus_submit_formation_response_self_api_v1` durable about who submitted a new answer, without rewriting that already-signed and teacher-bound API.

The live API already obtains the **current authenticated canonical Person**, checks an active `teacher_person_bindings` relation to the requested Formation Unit, and inserts a `titus.formation_responses` row. This proposed **BEFORE INSERT trigger** follows the existing insert transaction. It stamps four nullable fields onto the same original row:

- `submitted_by_person_entity_id`: current canonical Person (from the existing Titus verified current-Person resolver);
- `submitted_by_auth_user_id` and `submitted_in_session_id`: auth user and JWT session at submission;
- `original_text_sha256`: SHA-256 of `raw_text` as originally inserted.

All four are source-controlled, not accepted from input columns. An incomplete signed context is refused; a complete absence of signed context (an unrelated privileged administrative import) remains explicitly **unverified** rather than fabricated. Only newly inserted responses receive this provenance. Existing historic `teacher_id` responses remain **NULL** in the new fields, and are not retroactively attributed to Marlene or anyone else.

On UPDATE, the trigger protects raw original text, original Unit/teacher/question and the provenance fields. Normal metadata (for example `response_status`) can still be updated. DELETE of an original is blocked. No separate text copy or version table is needed for this first draft; revisions remain **new original response rows** linked under the earlier B2A history.

**No API rewrite, new role, grant, review reader, consent backfill or permission is implemented.** The B2B source-issuance verifier is still hard false and the B2A feedback writer remains hard false. Hash + current actor do not themselves prove source rights, exact edition release, learner consent to a reviewer, or a reviewer mandate. A database owner can administratively alter DDL; this is ordinary transaction custody, not a notarized cryptographic historical proof.

## Bounded scope and test

- **Source owner:** Noel's private `titus` Formation custody. Shared Auth/Person resolver is **reused, not changed**.
- **Protected:** Atlas institutional Course/Offering/Enrollment, Marlene content, original learner text, auth/bindings, all production DB, draft prior sources, review permission, UI and deployment.
- **Acceptance:** isolated PostgreSQL 16 invented identities prove new same-transaction Person/user/session/digest, rejected forged field inputs, wrong Person or incomplete signed context, unverified imports and all legacy rows not backfilled, update/delete blocked on original fields, ordinary response status still mutable, and both existing review gates closed.
- **Test limitations:** mock GoTrue claims are not real signed two-Person sessions; the fixture does **not** reimplement the full live public self-submission RPC. This is a minimum first-draft source proof; no rollout is authorized by fixture success.

## Completion register

| Outcome | Status |
| --- | --- |
| Found the existing signed learner submission writer | Done: read-only Supabase source inspection |
| Choose narrow owner and acceptance / preserve previous work | Done: only `titus.formation_responses` attribution + trigger |
| Capture fresh original author and original text on submission | Source staged |
| Keep historical unknowns and originals unchanged | Source staged; test below |
| Protect writer and B2B consent/review boundaries | No prior source modifications |
| First-draft fictional source proof | Pending CI |
| Signed actual user end-to-end test and production-shape review | Open |
| Real edition/rights clearance, explicit response consent, reviewer mandate | Open |
| Release/merge/deploy and teacher–student B2C review | Not done |

### Next bounded increment

When deciding to use Titus privately with a real learner, test the **actual existing signed self-submission RPC** in a disposable production-shaped Auth/PostgREST environment, then verify one newly written original carries the verified real Person, its hash matches the preserved text, and the proposed learner disclosure decision is genuinely attributed to that same Person. Only after that should a separate source-authorized reviewer read be opened, subject to teaching-edition clearance and real appointment. **For first-draft classroom prototype UX, use synthetic/demo content without falsely issuing real consent.**
