# UNI-OPS-01 U5 — Household native → canonical Reality identity PROPOSAL (HELD)

**Source candidate only.** Noel owns the structural carrier in the shared physical database. This does NOT install SQL on production, certify a Household kernel as a canonical Reality Entity, adopt a Rulebook, authorize information disclosure or issue Work.

## Bounded outcome

The existing first-party signed Household governor may PROPOSE, within a private source function, that one exact existing active native Household kernel refers to one exact existing canonical `reality.entities` candidate. The proposal records source custody and an asserted evidence fingerprint only. It does not create a canonical entity, rewrite the native kernel, or establish a verified identity equivalence. The independently reviewed identity decision and revocation/supersession are **not implemented** here.

Native identity belongs to `atlas.household_kernel_instances`; canonical Reality entity identity remains in `reality.entities`. `atlas.identity_reconciliation_adjudications` is Organization-scoped; `atlas.person_canonical_entity_bindings` targets `local_intel.entities` (not `reality.entities`); `reality.place_identity_keys` is explicitly place-only. These do NOT provide a valid Household-kernel → Reality entity decision. Do not repurpose them by label, UUID coincidence or metadata.

## Candidate source

- `candidate.sql`: private RLS-enabled append-only `atlas.uni_ops_household_reality_identity_proposals_v1`. FK to the actual native kernel, Household, submitting Principal and EXISTING Reality entity. One immutable, idempotent action ID per Household. A new action ID records a new claim rather than overwriting the first claim. Direct DML/SELECT and EXECUTE revoked for `PUBLIC, anon, authenticated, service_role`.
- Private `atlas.uni_ops_propose_household_reality_identity_internal_v1(household_id,kernel_instance_id,candidate_reality_entity_id,source_action_id,claimed_evidence_sha256)`: exact signed first-party Principal; ORIGINAL native `require_household_governor_self_v1`; exact active Household/kernel and current native world-kernel definition; exact existing currently canonical `reality.entities` candidate. Rejects forged actor, wrong Household/kernel, missing candidate and changed payload on idempotent replay.
- `claimed_evidence_sha256` is **only a governor-submitted fingerprint**. It is not a checked original document, an independent reviewer approval, or permission to disclose its contents.
- Return state **`source_identity_proposal_only_not_adjudicated`**, with explicit false evidence-independent/canonical-binding/Need/Foundry/domain/policy/Work/Clock/next-Work flags.
- `postconditions.sql`: scoped disposable-clone-only ACL/RLS/immutability/private-function checks.
- `tests/uni-ops-household-reality-identity-proposal-source.test.mjs`: Node source contract check; no secrets or live database.

## Exact verification order (not yet all complete)

1. Run Node source-contract checks on the exact Git blob (can run without database).
2. Compile the candidate on a fresh disposable current-schema-shaped PostgreSQL/GoTrue/PostgREST clone. Check postconditions and schema lint delta zero.
3. With a disposable authenticated wrapper **only in the clone**, run the true signed original Household governor positive proposal and identical idempotent replay; changed action payload must deny. Independently signed member-worker with forged owner metadata, outsider, no-seat, anon, wrong Household/kernel, noncanonical candidate and deleted GoTrue session must deny. Concurrent same-action attempts create exactly one proposal, not two. Direct public API access stays closed.
4. Verify the source's single permitted DML only affects the NEW proposal table in the disposable clone. No new Reality Entity, no canonical binding approval, no Need, Foundry decision, Rulebook, Work, Clock or successor.
5. Stop local services; preserve source SHA and source-contract, signed and custody test receipts. **Do not** merge/release this held code as an executable feature merely because unit or signed tests pass.

Original held U1A #2465, universal common #2555, Household native #2559 and any U1B/U2 path are unchanged. Existing #2559 signed acceptance #42265271242 verifies native governor mechanics only, **not** this new candidate.

## Outstanding next authority

An independent current identity-review authority with explicit *Household native kernel ↔ canonical Reality* jurisdiction must be source-approved. Its decision contract needs original source evidence, governor proposal, distinct independent reviewer, conflict adjudication, immutable decision and supersession/revocation history, current identity/condition disclosure and replay/concurrency denial. Only a separately verified ACTIVE decision may qualify as canonical identity; even then it does not imply an observed Need, Foundry source review, Rulebook, Work or future successor.

The real Household still has no observed current physical condition or open native Need in the last read-only audit. **No real Household identity, Need or Work may be created to satisfy the tests.** Preserve Nov 4 6A: Result/Done never automatically issues the next Work.

## Source governance

No migration number, approved CLI-generated source, public API grant, production project change, identity-review writer or deploy in this draft. Structural/source authority for independent review must be adjudicated separately under Noel source ownership and Atlas delegated governance. This candidate must not be combined into or treated as a silent replacement for held U1A, universal common, or U2 code.