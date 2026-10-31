# Accepted Ledger intake → existing original-Work actions (candidate)

**SOURCE ONLY / DRAFT. NOT A DEPLOYMENT.** Implement under [Noel issue #2434](https://github.com/optical-lift/noel-core-db/issues/2434). Requires exact disposition migration `20261031004257` to have already passed its separate governed release gate. Do not apply this SQL directly on production.

## Intent

Extend the **existing** native original Work editor, initial company Work offer, and accepted standing-scope assignment writer to recognize *one narrowly proven* source: a real Ledger intake already accepted by its exact Ledger root, with a matching final signed decision and the exact original Work. The initial participant-attested evidence row remains intact; it is **not rewritten as owner-attested**. No Work, Person, Principal, allocation, schedule, delivery receipt, or permissions are created in this candidate.

A new `atlas.accepted_ledger_intake_original_evidence_v1(org,ledger,work)` is an **internal non-executable-by-app evidence predicate**. It is never a permission grant. All existing owner, institutional membership, standing-scope, active-native-Ledger and worker-acceptance guards remain on their original writers.

## Boundaries and outstanding blocker

- Owner editor still requires currently signed **both** native Ledger root and governing Organization root and current owner membership. A root who only governs another Ledger is not entitled to all Organization Work.
- Accepted standing-scope writer can assign a native canonical Person with **already accepted matching native Person scope** and no old employee seat; the existing writer continues to enforce exact scope/ledger and already allocated/outstanding offer checks.
- **Important:** `offer_unallocated_company_work_self_api_v1` still requires exactly one **active institutional Organization membership** for the target Person. It cannot implement canonical-native-only Katie/Anna-like first offers. This candidate does not bypass that guard. A separate, explicitly source-governed canonical Person offer/uptake compatibility repair is required to reach the universal acceptance goal; do not fabricate membership, silently allocate at review time, or claim that this candidate is the complete handoff.
- A proposed attention date in intake is **not** the native person work-on plan; plan scheduling must be verified only after independently lawful allocation.
- The submitter's own bounded status read and ordinary collaboration notes remain separate unmet requirements. The root review queue is not a notification delivery claim.
- Exact Work lifecycle history remains source-owned: not an Event-specific task, not new Work, and not a special farm task engine.

## Required before merge / generated migration

1. Review unchanged live function sources against the candidate; verify this file's three replacements remain byte-for-byte identical except the tight eligibility clauses.
2. Run **protected full production-schema clone** with v2 installed first, source SQL in one rollbackable transaction, and postconditions. Compare Atlas lint baseline; zero newly introduced issues.
3. Real independent signed GoTrue/PostgREST fixtures: two exact roots, native worker with accepted standing scope, member-bound worker offer, native-only Person **denied** by legacy offer (no false success), another-Ledger root, unrelated Person, anonymous, revoked root/session, active/withdrawn Ledger relevance. Require source SQL 42501 (not a transport 404).
4. Before acceptance: `submitted` / `needs_details` must **not** gain editor/offer/scope privilege; after genuine root acceptance: same Work ID is edit-capable for independently authorized owner, eligible under a lawful accepted standing scope, and preserves Result/Work history; rejected/cancelled originals never become eligible.
5. Prove accepted writer, separate native Work date, signed recipient Today and Result readback. Enforce no new Work and at most one active responsible allocation.
6. Fix the native-only first-offer gap or formally defer with truthful UI. Do not mark Atlas PR #494 fully accepted based only on schema clone.
7. Generate a new immutable Noel migration through established custody; gain **separate owner-approved** live release. No independent app schema writes or automatic PR merge.

No real Elm or Anna submission has been modified by creating these source files.
