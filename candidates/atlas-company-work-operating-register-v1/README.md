# Atlas native-Ledger operating requirement register — Slice C1

Source-only candidate for a governed Atlas-lane migration. It does not change production, generate Work, schedule a day, or allocate a worker.

## Canonical alignment

- One established register entry points to exactly one real **atlas.work_requirements** row. The canonical requirement carries the organization's need; there is no second Work root.
- Revision rows record required outcome, instructions, prerequisites, resources, reporting and escalation, an optional existing accountable Position, and an optional existing active organization recurrence rule. The fields are history, not appointments or grants.
- The first creation operation establishes a canonical requirement with an exact native Ledger provenance and returns its ID. It creates **zero** work_items, work_allocations, schedules, or recurrence instances.
- The read operation displays registered requirements and their canonical linked Work items, with separate factual indicators for an active appointment window and responsible allocation. An appointment window alone is not proof of effective membership or eligibility. It also lists otherwise unregistered legacy requirements ONLY when linked Work has exact, currently valid native Ledger evidence. No legacy Work is re-created or silently attached.
- A paused provisioning policy does not cancel or satisfy the canonical requirement and does not alter previously generated Work. No unrestricted retirement command is published in this slice; that requires the existing dependency-aware reconciliation semantics.

## Owner and security boundary

All API entrypoints demand current **native and institutional root owner** authority over the exact Organization/Ledger pair by reusing the released company_work_native_ledger_owner_self_v1 guard. Direct anon/authenticated table grants are revoked, RLS is enabled, and revision rows are append-only. The author and effective time persist with each change. Optimistic revision control prevents lost updates.

This candidate has no worker-scoped reader and conveys no seat or standing-assignment authority. It does not make any eligibility or availability assertion. Those are separate constrained facts.

## Deliberate sequencing

The existing organization recurrence rule can be linked as definition provenance, but **no materialization adapter is implemented**. Before enabling recurring farm Work, a separate reviewed adapter must link each canonical recurrence instance to at most one canonical Work item by a unique source key, and prove edit/retry/replacement idempotency.

Do not automatically seed the illustrative chicken, bedding, flower-bed or U-Pick requirements. Elm's existing rules, countdowns, legacy task identity and U-Pick retirement reconciliation must be reviewed with the owner first.

Use the repository's governed migration-source-generation and protected schema-clone-validation flow after review; never apply candidate SQL to the production database directly.
