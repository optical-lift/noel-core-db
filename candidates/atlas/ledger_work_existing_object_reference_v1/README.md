# HELD first source adapter — independent Ledger Work references the original Bed

**Owner decision:** 2026-11-07 — [one real-world Object, multiple independent Ledger Work contexts](https://github.com/optical-lift/atlas/blob/docs/uni-ops-native-canonical-bridge-hold-20261106/docs/integration/SHARED_REAL_WORLD_OBJECT_MULTI_LEDGER_WORK_AUTHORITY_20261107.md).

**Status:** SOURCE DRAFT ONLY. No migration, public RPC, protected signed run, deployment, real permission or UI delivery. Owner-directed replacement for the old *mandatory* Flower offer → Venue accept sequence **solely for reference**. The historical old candidate and its signed successes remain intact, but are not the target product law.

## What is implemented in draft source

- `HELD_source_candidate.sql` adds one private RLS-enabled reference relation `atlas.ledger_work_existing_bed_references_v1`. It stores the **existing canonical Work ID and existing original Bed ID**; it creates neither new Object nor Work.
- `atlas.establish_ledger_work_existing_bed_reference_self_v1(org, ledger, originalWork, existingBed, stableAction)` checks a *real current signed Person*, native connection and seat to the **target** Ledger, active exact Organization/target Ledger participation and existing current native relevance for the original Work.
- Actor must also have an already established **target-Ledger author path**: current exact Ledger root, OR authoring authority from the current `ledger_occurrence_shared_work_actor_self_v1` for this Ledger's genuinely Event-born original Work. A Ledger Seat by itself grants no generic write permission.
- The Bed is verified from `atlas.growing_objects` plus an active Farm in the same Organization. No call to the Flower governor, no Flower custody transfer, no cross-Ledger contract, no cross-Organization disclosure, no hidden Work enumeration. The response returns only the identifiers already submitted and the reference receipt, not Bed condition/crop notes.
- Deterministic replay, action-collision rejection and one reference per exact Ledger/Work/Bed. The original Work must be open to gain a new reference. Result/Done is untouched.
- The new reference does **not** insert into `atlas.work_item_context_links`; the original Flower spatial Work guard and Flower source mutation rights remain in force.

## Signed-test preparation only

- `clone_test_api_DISPOSABLE_ONLY.sql` refuses all but exact local PostgreSQL17/C1 fictional fixture, and installs an isolated PostgREST test transport **only on a disposable clone**. No authenticated source function or table grant.
- `scripts/validate-atlas-independent-ledger-bed-reference-signed-http.py` requires four genuine independent GoTrue sessions, existing original Venue Work relevant to Venue Ledger, and original Flower Bed. It asserts: no Flower offer/accept needed; Venue governor positive; Flower governor/worker/no-seat and wrong-Work/not-real-Bed negative; idempotent replay; action collision; unchanged Bed, original Work, crop custody, physical Work contexts and original Work state; receipt excludes Bed private metadata; reused revoked Venue token denied.
- **Not run yet:** New SQL has NOT been installed on a protected disposable full-schema clone, and the new test has NOT executed. CI source/lint success does not substitute for those facts. Wire this only into an authorized protected runner without changing immutable production source/migration scope.

## Separate remaining contracts

1. This first adapter covers **same-Organization physical Beds**. Other object kinds and cross-Organization references need source-specific identity/privacy adapters, not duplicated Objects or dual-governor Work-authoring ceremonies.
2. Native worker Result/Done for original Venue Work remains a separate source contract; the existing shared Event checklist Done is not an ordinary Person Work completion result.
3. An approved Atlas reader/projection is still needed to present this private reference alongside the same original Work without leaking Bed metadata or bypassing source disclosure.
4. **No live authorization change is claimed.** Source/security owner review, protected full-schema signed execution, exact generated migration, release and browser tests remain independent gates.

## Go/no-go

The first source can advance only if independently signed real target-Ledger authoring succeeds without Flower offer, unauthorized Flower-only/outsider/unseated principals deny, replay remains unique, original Bed and Work counts and crop custody are unchanged, revoked sessions deny, and ACL/RLS/privacy checks pass. If any of these fail, do not widen the institutional root or pretend the existence of a source reference proves permission to alter physical reality.
