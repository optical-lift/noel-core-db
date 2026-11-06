# UNI-OPS-01 U5 — Household native → Reality identity and disclosure source candidates (HELD)

**Source candidate only.** Noel owns the structural carrier in the shared physical database. This does NOT install SQL on production, certify a Household kernel as a canonical Reality Entity, adopt a Rulebook, authorize information disclosure or issue Work.

## Bounded outcome

The existing first-party signed Household governor may PROPOSE, within a private source function, that one exact existing active native Household kernel refers to one exact existing canonical `reality.entities` candidate. The proposal records source custody and an asserted evidence fingerprint only. It does not create a canonical entity, rewrite the native kernel, or establish a verified identity equivalence. Independent review, revocation and a narrowly private status reader are now **authored as additional held source candidates**, but neither actual human authority issuance, genuine review, runtime verification nor production installation has occurred.

Native identity belongs to `atlas.household_kernel_instances`; canonical Reality entity identity remains in `reality.entities`. `atlas.identity_reconciliation_adjudications` is Organization-scoped; `atlas.person_canonical_entity_bindings` targets `local_intel.entities` (not `reality.entities`); `reality.place_identity_keys` is explicitly place-only. These do NOT provide a valid Household-kernel → Reality entity decision. Do not repurpose them by label, UUID coincidence or metadata.

## Candidate source

**Explicit candidate assembly order (not an approved migration):**

1. `candidate.sql` — native governor source proposal, private append-only ledger of assertions.
2. `household_information_disclosure_candidate.sql` — signed Household governor authorizes or withdraws **identity** and **condition** disclosure separately to a specific canonical Person; self-receiver is derived from the current signed session. No data is returned by the decision action.
3. `independent_review_candidate.sql` — distinct independent signer with a **separately issued** source-specific `reality.responsibility_relations` entry, original evidence record, dual disclosure for approval, immutable signed approval/rejection/revocation events, event-sequence ordering, conflicting identity denial, current native+Reality checks. This source does **not issue** reviewer responsibility and none is presumed to exist.
4. `current_identity_status_candidate.sql` — private governor-only current review status; rechecks original source, evidence, reviewer responsibility, disclosure withdrawal, revocation and ambiguity. No canonical authority beyond its exact status.
5. `private_reviewer_queue_candidate.sql` — at most twenty pending proposals per page, visible only to an independently authorized reviewer with both current Household disclosures; no personal names, evidence contents, total roster or public API.
6. `original_need_source_packet_candidate.sql` — one exact original, still-open native Household Need and originating firsthand observation source receipt, plus a typed **non-admitted** source packet with reviewed Reality candidate. Reuses #2559 and writes no Work Requirement or original Work.
7. `household_source_composition_candidate.sql` — private, read-only conjunction of the **existing separate** [#2559](https://github.com/optical-lift/noel-core-db/pull/2559) native Household verifier with this draft's identity status. It can report source facts but always denies original Requirement/Foundry/Rulebook/Work/Clock/successor. The source verifier in held #2559 must be included by the *future* authorized assembly; no duplicate native source writer is created here.

- `candidate.sql`: private RLS-enabled append-only `atlas.uni_ops_household_reality_identity_proposals_v1`. FK to the actual native kernel, Household, submitting Principal and EXISTING Reality entity. One immutable, idempotent action ID per Household. A new action ID records a new claim rather than overwriting the first claim. Direct DML/SELECT and EXECUTE revoked for `PUBLIC, anon, authenticated, service_role`.
- Private `atlas.uni_ops_propose_household_reality_identity_internal_v1(household_id,kernel_instance_id,candidate_reality_entity_id,source_action_id,claimed_evidence_sha256)`: exact signed first-party Principal; ORIGINAL native `require_household_governor_self_v1`; exact active Household/kernel and current native world-kernel definition; exact existing currently canonical `reality.entities` candidate. Rejects forged actor, wrong Household/kernel, missing candidate and changed payload on idempotent replay.
- `claimed_evidence_sha256` is **only a governor-submitted fingerprint**. It is not a checked original document, an independent reviewer approval, or permission to disclose its contents.
- Return state **`source_identity_proposal_only_not_adjudicated`**, with explicit false evidence-independent/canonical-binding/Need/Foundry/domain/policy/Work/Clock/next-Work flags.
- `postconditions.sql`: scoped disposable-clone-only ACL/RLS/immutability/private-function checks.
- `tests/uni-ops-household-reality-identity-proposal-source.test.mjs`: Node source contract check; no secrets or live database.

## Deferred verification, intentionally NOT executed for this build-first stage

1. Later, run the authored source-only contracts on the exact Git blob; expand them to all source components. Do not treat static review as signed runtime acceptance.
2. When integration is necessary for continued build or release, assemble #2559 and the seven candidates **in the exact source dependency order** above on a disposable current-schema-shaped PostgreSQL/GoTrue/PostgREST clone. Check schema compilation, postconditions, ACL/RLS, privacy and lint delta zero.
3. One collected genuine signed test matrix only when required: original governor proposal; separately signed human recipient identity-only vs condition-only disclosure; identity+condition both; independent authorized reviewer; first-party signer, proposer-as-reviewer, worker, outsider, anon, forged owner metadata, no seat, revoked GoTrue session, wrong source/candidate/evidence denied. Verify conflicting approvals, identical/mismatched idempotency, simultaneous actions, effective withdrawal, revocation/supersession, stale reviewer responsibility and privacy-bounded queue.
4. Verify all permitted writes are restricted to their respective NEW proposal/review/disclosure event tables in the disposable clone. No new Reality Entity, native Need, original Requirement, Foundry decision, Rulebook, Work, Clock, successor, policy or permission issuance; no private data leaks.
5. Stop local services; preserve source SHA and source-contract, signed and custody test receipts. **Do not** merge/release this held code as an executable feature merely because unit or signed tests pass.

Original held U1A #2465, universal common #2555, Household native #2559 and any U1B/U2 path are unchanged. Existing #2559 signed acceptance #42265271242 verifies native governor mechanics only, **not** this new candidate.

## Implemented source vs. independently unsatisfied authority

This source now contains a review writer and revocation pathway **as draft code**. They are not permissions: any attempted positive review fails closed until a suitable, source-issued active Reality responsibility exists with the exact key `uni_ops_native_household_identity_adjudication`, domain `reality.household_native_identity`, operation `household_native_identity.adjudicate` or `household_native_identity.revoke`, and scope `{"nativeSource":"household_kernel_instance","decisionScope":"identity_only"}`. Authorizing that responsibility remains outside this draft. A signed, separately authorized human review is distinct from the Household governor's own claim.

For an approval, the original Household governor must separately permit the reviewer to see **subject_identity** and **subject_condition**. The original `atlas.evidence_records` row must be tied to the exact active native kernel. The current status reader rejects withdrawn permissions, retired source, revoked review, stale reviewer responsibility or conflicting active identities. These controls remain **untested draft assertions** until the collected signed acceptance stage. The original source evidence fingerprint is *not* cryptographically bound to evidence bytes in the current schema; an independent reviewer attestation is not a cryptographic verification.

**Not built:** a real issued reviewer responsibility, a source-approved non-organization common Requirement pathway (the original Need source packet is authored, but **not** a `work_requirements` row), current worker-specific disclosures into Rulebook U1A/U1B, original Foundry review and U2 accepted original Work. Those require independently governed shared-domain decisions and must not be fabricated to make a passing fixture.

## Outstanding next authority

The **actual human grant and issuer** of a Household-specific independent Reality responsibility must be adjudicated, not invented by this branch. Approval/revocation writer, private queue and current-status logic are drafted, not independently verified or installed. A later signed review alone does not admit a native Need as a common Requirement, a Foundry instruction, policy, Work or future successor.

The real Household still has no observed current physical condition or open native Need in the last read-only audit. **No real Household identity, Need or Work may be created to satisfy the tests.** Preserve Nov 4 6A: Result/Done never automatically issues the next Work.

## Source governance

Because this carrier references the existing `reality.entities` canonical namespace from an Atlas-native Household Subject, its eventual **structural release is a cross-domain/shared contract** and requires the reviewed `shared_` migration lane (and its security/privacy checks) under Noel's single physical migration authority. A path under `atlas` does not silently narrow shared-custody review.

No migration number, approved CLI-generated source, public API grant, production project change, live identity review, reviewer-responsibility issuance or deploy in this draft. The independent review **source writer** is staged but not runtime accepted. Structural/source authority for independent review must be adjudicated separately under Noel source ownership and Atlas delegated governance. This candidate must not be combined into or treated as a silent replacement for held U1A, universal common, or U2 code.