# Original Ledger intake disposition v2 — source only

Reconcile the existing institutional original Work intake, not a new task system. The user's real Venue submission was moved from `submitted` to `needs_details` (revision 1), and v1 root inbox reads only `submitted`, so it became undiscoverable from governor Today. The original Work remains open; no task allocation occurred.

## Source behavior
- New exact-root signed review reader `ledger_work_review_queue_root_self_api_v2` returns both `submitted` and `needs_details` open originals, with revision and last decision reason. A worker/outsider receives genuine `42501` from the current exact-Ledger root function. No private direct table grants.
- New exact-root signed writer `review_ledger_work_intake_root_self_api_v2` makes a CAS-protected final decision with a required reason. `accepted_for_ledger` can edit title/instructions on the **same** `atlas.work_items` original, logs before/after fields and keeps the unassigned Work open. `rejected` cancels that exact previously unassigned Work and preserves submission and decision history.
- The source retains immutable `submitted_title` and updates the original v1 submit function to compare replays against it, preserving source-action idempotency even after a governor edits the current title or rejects Work.
- No allocation or Work-on plan is created by either disposition. Subsequent responsibility or scheduling uses existing governed original Work actions and requires its own authority. No notification is claimed or sent. No root/seat/Person/Principal creation, no new Work table. Both existing v1 endpoints remain available; new functionality uses v2 separate endpoints.
- The UI must **not** show a dangling Today heading when no outstanding queue exists. Rejected and accepted items are out of the root Today pending queue, but their historical originals and decisions remain durable. `needs_details` stays in the root review queue rather than vanishing.
- An existing active Work allocation blocks either final intake disposition; use existing Work management rather than interfering with an assigned person's obligation.

## Release custody
1. Source PR and database custody CI; inspect real API signatures/constraints, no product migration from draft in production.
2. Generate one atomic versioned migration using the guarded migration generator after source review. Use the disposable full-production-schema clone with postconditions and **real independent signed** governor/worker/outsider/ended-authority tests for v2: previous revision 1 follow-up recoverable; accepted edited same Work; rejected canceled historical original; replay yields same original and no additional Work; non-root denied.
3. Separate explicit owner-approved migration target/version release after PASS. Then live signed smoke and Atlas #494 preview. Keep Atlas app draft and production domain untouched until verification.

A v1 `needs_details` submission already exists in production. Do not manufacture synthetic production Work to test this; use a disposable database for fixture assertions, then knowingly finalize the existing Venue original through the signed user session if the owner elects.
