# Accepted Ledger intake → existing original-Work actions (candidate)

**SOURCE ONLY / DRAFT. NOT A DEPLOYMENT.** Implement under [Noel issue #2434](https://github.com/optical-lift/noel-core-db/issues/2434). Requires exact disposition migration `20261031004257` to have already passed its separate governed release gate. Do not apply this SQL directly on production.

## Intent

Extend the **existing** native original Work editor, initial company Work offer, and accepted standing-scope assignment writer to recognize *one narrowly proven* source: a real Ledger intake already accepted by its exact Ledger root, with a matching final signed decision and the exact original Work. The initial participant-attested evidence row remains intact; it is **not rewritten as owner-attested**. No Work, Person, Principal, allocation, schedule, delivery receipt, or permissions are created in this candidate.

A new `atlas.accepted_ledger_intake_original_evidence_v1(org,ledger,work)` is an **internal non-executable-by-app evidence predicate**. It is never a permission grant. All existing owner, institutional membership, standing-scope, active-native-Ledger and worker-acceptance guards remain on their original writers.

## Boundaries and outstanding blocker

- Owner editor still requires currently signed **both** native Ledger root and governing Organization root and current owner membership. A root who only governs another Ledger is not entitled to all Organization Work.
- Accepted standing-scope writer can assign a native canonical Person with **already accepted matching native Person scope** and no old employee seat; the existing writer continues to enforce exact scope/ledger and already allocated/outstanding offer checks.
- **Important:** `offer_unallocated_company_work_self_api_v1` still requires exactly one **active institutional Organization membership** for its recipient. That legacy-style offer must **not** be used for native-only Katie/Anna-like People. Instead the **already existing native exact-Work path** is source-adapted here: `propose_native_ledger_exact_work_scope_owner_self_api_v1` → independent worker consent via unchanged `respond_native_ledger_standing_scope_self_api_v1` → existing `assign_native_ledger_company_work_under_scope_owner_self_api_v1`. It requires current canonical Person Ledger connection, a separately accepted exact scope and real current owner authority. This is the preferred candidate for native-only recipients; it is **not tested or live**. Do not fabricate membership, silently allocate at review time, or imply that signed recipient Today is already proven.
- A proposed attention date in intake is **not** the native person work-on plan; plan scheduling must be verified only after independently lawful allocation.
- This candidate now contains a **source-only signed author status API** using current exact Ledger admission, bounded keyset pagination and `submitted_by_person_id` source filtering. It returns only the submitter's own original title/Work ID/review status, not root reason, root queue, personnel, or delivery. It has **not** passed signed GoTrue tests, been migrated, or been wired into a user-facing Today view. Ordinary collaboration notes remain a separate unmet requirement.
- Exact Work lifecycle history remains source-owned: not an Event-specific task, not new Work, and not a special farm task engine.

## Required before merge / generated migration

1. Review unchanged live function sources against the candidate; verify this file's three replacements remain byte-for-byte identical except the tight eligibility clauses.
2. Run **protected full production-schema clone** with v2 installed first, source SQL in one rollbackable transaction, and postconditions. Compare Atlas lint baseline; zero newly introduced issues.
3. Real independent signed GoTrue/PostgREST fixtures: two exact roots, native worker with accepted standing scope, member-bound worker offer, native-only Person **denied** by legacy offer (no false success), another-Ledger root, unrelated Person, anonymous, revoked root/session, active/withdrawn Ledger relevance. Require source SQL 42501 (not a transport 404).
4. Before acceptance: `submitted` / `needs_details` must **not** gain editor/offer/exact-scope privilege; after genuine root acceptance: same Work ID is edit-capable for independently authorized owner. Prove native-only Person `propose exact Work scope` → signed independent accept/decline → authorized same-original assignment, and distinct member-bound legacy offer if eligible. Preserve Result/Work history; rejected/cancelled originals never become eligible.
5. Prove author-only submission status: worker sees own submitted, needs_details revision 1, accepted and rejected historical originals with truthful pagination; other authors, unrelated Ledger roots, outsiders and revoked connections get no rows or existence/count leak. Then prove accepted writer, separate native Work date, signed recipient Today and Result readback. Enforce no new Work and at most one active responsible allocation.
6. Prove the already-established **native exact-Work proposal/consent/assignment** journey in signed tests and Atlas controls; it can satisfy native-only recipient assignment without changing the legacy member-bound offer. If any necessary user-facing step is absent, keep the release held and report the actual gap. Do not mark Atlas PR #494 fully accepted based only on schema clone.
7. Generate a new immutable Noel migration through established custody; gain **separate owner-approved** live release. No independent app schema writes or automatic PR merge.

No real Elm or Anna submission has been modified by creating these source files.
