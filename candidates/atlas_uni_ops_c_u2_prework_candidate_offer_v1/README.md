# UNI-OPS-01 Option C — U2 pre-original candidate → signed acceptance → held root-finalized Work

**Authored source only. Not compiled in PostgreSQL; not signed GoTrue-tested; not a migration or release.**

Stack: [U1A #2465](https://github.com/optical-lift/noel-core-db/pull/2465) → [U1B #2481](https://github.com/optical-lift/noel-core-db/pull/2481) → [U2 #2482](https://github.com/optical-lift/noel-core-db/pull/2482). Atlas consumer [draft #535](https://github.com/optical-lift/atlas/pull/535). Existing R01/R02 original writer remains a **separate held source dependency**; it is not copied into this candidate.

## Actual draft artifacts

- `candidate.sql` — private, RLS-protected **candidate offer without any original Work**; root read and current exact source checks, independent accepted native Person scope and Subject disclosure; one source-selected standing candidate, explicit service day, campaign boundary, ISO days and source timezone, conservative three-open-original capacity check, old native/legacy Work collision, one outstanding offer per Person. Its initial adapter is **mowing standing stewardship only**, not corrective weeding or every rhythm.
- `property_rule_version_id` and effective `rule_version_id` are both pinned. Even an active parent revision invalidates the prior offer; a property pause blocks all child offers. Worker response rechecks current source, scope, disclosure, Work collision, timezone/day and capacity.
- `respond_governed_prework_candidate_self_api_v1` — genuine signed current recipient accepts/declines only the known offer, with exact response action replay. An acceptance is **willingness**, not responsibility, original Work or permission.
- `read_governed_prework_candidate_inbox_self_api_v1` — exposes only source-current admitted offers and the already permitted rule/Subject labels. No roster, neighboring Work or complete inbox claim.
- `native_existing_rule_review_readers_held.sql` — a root sees previously recorded native rule labels/cadences/class keys and separately permitted exact Subjects, paged; no re-interview and no bulk approval. The labels alone cannot supply missing policy semantics.
- `native_rule_scope_current_read_held.sql` — root reads one exact property/class/Subject policy version without fallback.
- `native_governor_queue_read_held.sql` — the original root sees one bounded pending/accepted source queue with current admissibility, not a Work roster.
- `finalize_accepted_source_bridge_held.sql` — signed **current native Ledger root** verifies a worker previously accepted, rechecks frozen policy and owner/recipient/capacity/source, invokes R02/R01's authentic canonical source writer with the original offer UUID as its stable action, then requires a newly created Work with the same native Ledger, candidate, recipient and service-day plan. In the same transaction it marks the offer fulfilled. Refuses existing/colliding Work rather than adopting someone else's original.
- `postconditions.sql` and `finalize_postconditions_held.sql` — structural ACL/syntax gates only; neither is a run record. Never apply outside a disposable clone.

## Unfinished and protected

1. **Not autonomous yet.** An authorized Ledger root must explicitly finalize after worker acceptance. A future background evaluator needs independent source-owned authority and an exact durable actor; it cannot impersonate a remembered human session.
2. **Direct R02 bypass remains.** The old `governor_approve_rhythm_opportunity_self_api_v1` can still create Work without this new acceptance. This draft is therefore **not a releasable enforcement of accept-first policy**. Source retirement/routing must be coordinated.
3. **Separate policy families unresolved.** The U1A Foundry exact-Subject Rulebook and U1B legacy native-rhythm policy records need one canonical authority/Need relation; do not create competing executors.
4. **Worker ≤3 open originals:** this path checks current active responsible native and legacy membership allocations, but full concurrency against all other independent Work writers is not yet proved.
5. **Corrective evidence and seasons:** weeding/restorative maintenance must not use this standing-only adapter without sourced current observed physical conditions. Named season membership is not yet qualified, so this first offer path refuses such scopes rather than guessing.
6. **Real pilot and release:** no U1A signed acceptance, native clone build, U1B/U2 SQL compilation, worker and root negative matrix, race tests, Household U5 or Event U6, current farm-wide canonical identity audit, human Atlas iPhone/desktop proof, or U7 production release has occurred.

**Increment status:** SOURCE-AUTHORED / BROWSER-ADAPTER-AUTHORED / ISOLATED PURE-CONTRACT SMOKE PASSED (15 checks in V8) / PG-SIGNED-INTEGRATION-HUMAN-RELEASE NOT VERIFIED. No production SQL/data, grants, originals, or Work result changed.
