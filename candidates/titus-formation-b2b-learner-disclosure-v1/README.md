# Titus Build B2B — source-issued learner disclosure decision (candidate)

**Status:** source-only draft. No real Person consent recorded, no authorized teaching edition, no reviewer read, no write permission issued and no migration/deployment.  
**Ownership:** Noel post-fence `titus` Formation custody, source of versioned learner declaration events.  
**Owning issue:** [Noel #2461](https://github.com/optical-lift/noel-core-db/issues/2461).  
**Previous stack:** B2A [#2463](https://github.com/optical-lift/noel-core-db/pull/2463), B2B structural evidence [#2464](https://github.com/optical-lift/noel-core-db/pull/2464), closed authentic-issuance boundary [#2466](https://github.com/optical-lift/noel-core-db/pull/2466).

## Bounded outcome (before writing)

Preserve **one signed learner-origin declaration** to permit, or withdraw permission for, **one named canonical reviewer to see one exact Formation response**. The learner must take an explicit action: the system does not issue consent for them. A new decision cannot be backdated, rewritten, deleted, extended arbitrarily or replayed against a different reviewer/response.

The source operation `titus.record_formation_review_disclosure_intent_self_v1(response_id, reviewer_person_id, decision_kind, request_id)` is **private / SECURITY INVOKER / not granted**. Its real implementation (if separately released) resolves the actor only from `titus.current_authenticated_person_entity_id_v1()` and records the verified `auth.uid()` and session ID as an issuer audit receipt. The only accepted decision kinds are `consent` and `withdraw`; one actor may consent to one canonical Person for a specific response, then withdraw without deleting history. Consent expires after 30 days. A withdrawal can be recorded even when the Unit goes stale or the old learner binding has since been retired, provided the previous decision belongs to the same current Person.

**Critically, this captures a learner's *stated disclosure decision* only. It does not prove the original response was first authored by that Person, prove the response was unmodified since the encounter, release a teaching edition, appoint a reviewer or grant any cross-Person read.** This distinction is intentional. No automatic promotion from recorded intent to B2B `consent_source_ref` or from the event to the hard-false `formation_review_source_issuance_verified_v1` is allowed. Future source authorization must verify this event AND the original authorship/version chain, edition rights/release, reviewer mandate and contemporaneous revocation, before reading response content or writing review.

## One source operation and its constraints

- Input: existing response ID, known canonical reviewer Person ID, explicit `consent` or `withdraw`, caller-selected UUID request key (for safe retry).
- Actor: current canonical Person resolved by the already-existing live GoTrue/session-checking Titus helper; there is **no** `p_learner_person_id` client argument.
- Consent requires current binding of that Person to the response's historical source Teacher profile, submitted response, current Unit review and viable formation phase. This proves permitted current private workspace action, **not** historic authorship.
- Withdrawal requires a preceding consent by the same Person for the same response and reviewer, but need not assume the old Unit remains ready or source binding remains active.
- Custody: `titus.formation_review_disclosure_decisions_v1`, private, RLS, no direct browser grants; every transition appends a new source row with issuer, session, predecessor, sequence and issuer-controlled effective time. Trigger forbids update/delete and stale predecessor. The root response is locked to serialize competing declaration attempts.
- Receipt: only an ID, state and `effectiveDisclosure=false`. No learner text/roster, teaching source, reviewer name, or content is returned. No public RPC was created.
- Idempotence: exact request key replay returns the original receipt; conflicting replay and repeated state transition fail without a second event.
- No existing `titus.formation_responses` row or unrelated Formation Unit is modified; even in the fixture, deliberate retirement changes are restored by the test.
- There is no permission for `anon` or `authenticated` to execute the private operation. Any future RPC, if warranted, requires a separate independently reviewed source-authorized, signed access seam. Possession of a service key is not consent.

## Protected and outstanding

1. **Protected** — current production DB, canonical learner texts, Auth/GoTrue, all Atlas institutions and enrollments, any real Person/consent creation, existing closed B2A writer and B2B issuance gate, Song/Noel research and Titus UI/preview/production.
2. **Known limitation** — `formation_responses` records historical `teacher_id` but not an independently durable original `author_person_entity_id` or sealed original-response hash/version. The current authenticated binding does not reconstruct that missing history. No proof of authentic original respondent is claimed.
3. **Not yet issued** — exact rights-cleared frozen instructional edition, educational review, author/rightsholder acceptance, named learner release, governing reviewer appointment. The B2B three-reference tables contain unverified UUID references, not real signed authorizations.
4. **Not done** — source release and role grants, real network-authenticated learner consent, separately authorized reviewer disclosure, read/review/feedback writer, immutable historical response evidence, B2C signed two-Person positive and negative matrix.

## Test proof and acceptance boundaries

The source workflow `.github/workflows/titus-b2b-learner-disclosure-source.yml` uses empty PostgreSQL 16 and existing B2A/B2B invented fixtures. It adds **explicitly fake** `auth.uid()` / `auth.jwt()` identity stubs **only in the disposable container**, not real GoTrue sessions. It expects:
- no/other Person, wrong response/Unit/reviewer, malformed or missing fake session → no decision;
- explicit positive fictional learner consent → one limited receipt only, never actual reviewer permission;
- identical request key → same receipt; conflicting replay/new duplicate → no new event;
- other Person cannot withdraw; the original Person can still withdraw after Unit/binding retirement;
- re-consent requires a new explicit decision after withdrawal; chain remains append-only and issuer-stamped;
- no original raw-text mutation, no browser privileges, no SECURITY DEFINER, and BOTH older authority gates still false.

**CI status:** pending proof at exact implementation SHA. A passing fictional source test does not establish signed live Person, source license, rights acceptance or real consent. Do not merge/deploy on this evidence.

## Completion register / next required step

| Field | State |
| --- | --- |
| One bounded source-owned decision carrier and operation | Candidate staged |
| Explicit actor, response, reviewer, decision and idempotence | Candidate staged |
| Durable append-only revocation/withdrawal and private ACL | Candidate staged |
| False issuer gate and feedback writer protected | Candidate unchanged |
| Disposable test outcomes | Pending CI |
| Real signed Person issuance and original authorship | Missing |
| Rights-cleared release, educational review, reviewer appointment | Missing |
| Review, learner revision, real signed end-to-end integration | Missing |

**Next unfinished increment:** establish immutable/authored original-response provenance at the *existing* self-response writer, with exact current Person, session and content-version closure recorded transactionally at original submission. Until this exists, a learner's decision to disclose a historical `formation_responses` row may be recorded as a private declaration but cannot automatically authorize cross-Person visibility. Then source-verify the issuance receipt, exact edition rights, original author and reviewer mandate together. Keep [#2461](https://github.com/optical-lift/noel-core-db/issues/2461) open and all drafts unmerged.
