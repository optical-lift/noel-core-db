# Candidate: Ledger-owned Event shared Work v1

**Status:** Candidate DDL and RPC source only. Not a canonical migration. No application deployment, task data write, or production SQL application.  
**Owner:** Atlas kernel; physical source authority: `optical-lift/noel-core-db`.  
**Dependency:** Existing source-backed native Ledger participation, active Ledger seats and exact Occurrence bindings.

## Why

The physical `atlas.work_item_context_links` source constraint currently admits only spatial and identity subjects. Ordinary Company Work is therefore unable to belong to an exact Event without a new subject association. The existing Company Work actions also commonly require an assignee/accepted scope even when the activity is an unassigned shared checklist item.

User's governing decision: **The Ledger owns Work and an assignment points the Person to it. Any human with authorized Event workspace access can mark its ordinary shared Work done; that operation identifies the marker, not necessarily the physical performer.**

## Reality artery and selected implementation

1. **Ledger and Event remain canonical:** `ledger.ledgers`, `ledger.occurrence_calendar_bindings`, `atlas.organization_occurrence_bindings`, `local_intel.occurrences`.
2. **One Company Work item:** `atlas.work_items`. Its actual source Contract and exact native Ledger are recorded, but there is no required `work_allocations` row, employee seat, Worker Day plan, or personal copy.
3. **Exact source relations:** active `atlas.company_work_native_ledger_relevance` plus `atlas.work_item_context_links(subject_domain='temporal',subject_kind='occurrence')`. The existing internal context helper is extended to verify an active Organization/Occurrence binding; it retains the previous spatial/identity behavior.
4. **Authorization:** the self-only gate verifies current `auth.uid()` → canonical Person, active Personal Atlas identity access, exact native Ledger Person connection, Organization participation, and both the Ledger and Organization bindings to the requested Occurrence. **It authorizes only this minimal Event-work list and ordinary checklist actions**, not general Ledger history, financial sources, or other correspondence.
5. **Creation:** exact sentence + stable per-action idempotency creates one source Work record, its Ledger relevance and its Event relation, atomically.
6. **Completion:** separate authenticated actor can check it off regardless of assignment; creates a `work_execution_results` record with **null** responsible allocation and explicit `performedByPersonId: null`, plus accepted result evidence. Existing completion guard permits the transition only after evidence. Projected history consequently has a real result receipt.
7. **Read:** exact source-linked Work list only; excludes cancelled and superseded items from active view, includes completed items for continuity.

## Boundaries

- **No changes** to employee or assigned Work completion routes: special physical execution, managed acceptance, money/safety and older Work classifications remain controlled by their own laws.
- Mark Done in this first candidate is only for Work specifically born from this new ordinary shared-Event command. A separately controlled link/migration contract is needed before it can complete arbitrary pre-existing Company Work.
- Work designation to a Person/Today is a later attention relation, not Work custody.
- The full Event page and correspondence linking remain later product/communication packets; no false sending evidence.
- Removing mistaken Work and Reopen/Blocked remain held for their separately reviewed semantics.
- An Event link existing in one Ledger never proves access to that Event through a different Ledger.
- Read does not return arbitrary Work metadata, private source fields, recipient data or generic organization history.
- No hardcoded organization/Person/Event UUIDs in production source.

## Expected signed-in proof (blocked until protected clone and released test environment)

1. Owner creates `Book music` with no worker. Exact Event reader shows it once.
2. A second connected Person on the same Ledger opens the exact Event and marks it done; Work becomes `completed` with **that** Person in action evidence and physical performer unclaimed.
3. A third connected Person sees the same Work as done, not a copy. No assignment/offer/worker-day row was created.
4. Two parallel create retries with the same source action ID return one Work; repeat done action returns identical result receipt; reusing action ID with another Work is rejected.
5. Different Occurrence, Ledger, Organization, inactive bind, revoked Seat, unauthenticated caller, and no canonical identity all fail closed.
6. Work of another source Contract, optional Responsibility, specialized accepted result, another Event, or a cancelled/superseded Work cannot be completed through this command.
7. Existing spatial/identity context links still create and read normally; no affected contract silently broadens.
8. Only the authorized exact Event work titles are returned to a connected participant; private finance/correspondence stays hidden.

## Release steps

1. Review candidate and postconditions on a separate branch, resolve collision with current Company Work changes.
2. Merge reviewed source to canonical main **without deploying it**.
3. Use governed `Migration generation request: Atlas atlas_ledger_occurrence_shared_work_v1`; generate canonical migration, confirm exact source bytes.
4. Run protected schema-only production clone validation and authenticated Owner/second Person/third Person/outsider negative tests in a disposable environment.
5. Review Supabase security advisors and migration custody, then explicit protected production release.
6. Only after operation readback proof, wire the notebook Event page to released RPCs. Do not show write affordances before source authorization is live.

See `validation.sql` for non-row-bearing schema postconditions. Test fixtures must be synthetic and cannot embed production Person data.
