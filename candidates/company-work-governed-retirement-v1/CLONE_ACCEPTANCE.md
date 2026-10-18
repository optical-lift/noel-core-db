# Build 5 governed Work retirement — protected clone test matrix

This is **source candidate only**. Run with fixture data on the protected schema
clone before generating a release. Never use Anna's live account or mutate the
live Beds 1–4 Work from this checklist.

1. **Authorization:** Anon, unrelated Person, non-owner employee and owner of
   another Organization cannot inspect or retire Work. Owner of the selected
   native Ledger can review an Organization-wide Work item but receives
   `nativeLedgerRelevanceProven=false` if no exact Ledger proof exists.
2. **Standalone obsolete Work:** An owner supplies a reason; a source-free open
   Work item is cancelled using the preexisting audited adjudication. It does
   not become completed. Allocations released, adapters retired, plans
   withdrawn; Work history stays queryable behind History.
3. **Legacy task:** An open Work item whose exact `source_object_type` is
   `legacy_task` archives only the verified same-Organization source task.
   Trigger/reconciler retries must **not** re-open or re-materialize the retired
   Work, including after a subsequent Worker Day/queue read.
4. **Dependency:** An active `blocks` / `depends_on` / `completion_bundle_member`
   relation to another open Work returns impacted IDs and a no-write
   `impact_review_required` receipt until explicit owner acknowledgment.
   Acknowledged retirement preserves relation history and returns
   `relatedWorkReconciliationPending=true`. No downstream Work silently becomes
   completed or disappears.
5. **Outstanding worker evidence:** An unresolved worker result must surface
   in preview and require explicit acknowledgment. Reporting history remains
   unchanged, not recast as worker acceptance.
6. **Pending offer:** Cancellation marks a pending individual offer stale;
   the worker cannot accept it afterward. No phantom completion or assignment.
7. **Domain source:** Active Work requirement links or unsupported source
   carriers return `source_reconciliation_required` without altering Work or
   source data.
8. **Concurrency/idempotency:** Concurrent worker offer response and owner
   retirement serialize on Work responsibility lock. Retrying retirement after
   cancellation returns `already_removed_from_active_work` with no duplicate
   done receipt.
9. **Privacy:** Review never reads Personal Atlas; cross-Organization task IDs
   are not exposed. The normal owner view hides cancelled Work when History
   is off, while preserving it when History is enabled.

## Release blockers

- Confirm source-task archive doesn't fail an existing task state trigger.
- Confirm legacy task sync cannot recreate/reopen cancelled Work.
- Confirm the trigger/reconciliation outcome for every Work relation kind.
- Confirm exact schema fields in the protected clone, including source object
  UUID type and work relation primary key.
- If any fail, revise **candidate source**; do not patch the generated migration
  or apply direct production SQL.
