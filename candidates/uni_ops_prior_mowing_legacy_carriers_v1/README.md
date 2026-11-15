# HELD UNI-OPS — preexisting mowing Task and occurrence conservation

**Status:** source-only candidate; not independently signed, accepted, installed, or released. This is the next **separate** verification increment after [owner-protected signed history and unrelated first-mowing conservation PASS #43660458376](https://github.com/optical-lift/noel-core-db/actions/runs/43660458376).

## Exactly what is new

The previous signed P3 snapshot preserved Task/occurrence *counts and released identity lists*, but it did not construct a known prior mowing Task/occurrence. Therefore its pass was not proof that genuine nonempty old mowing carriers survive the signed first Result or the unrelated historical cancellation.

This candidate prepares three frozen synthetic physical carriers in the same **disposable** organization and mowing Rhythm State **before** any new governed Rulebook, Person acceptance, Actual or Result:

1. One linked **previously released** legacy `atlas.tasks` mowing Task (open, formerly released) and its `atlas.planned_work_occurrences` row, referencing the exact fictional source state.
2. One separate **planned**, unreleased mowing occurrence referencing the same source. Its absence from the release identity sets is meaningful.
3. A matching native `atlas.work_definitions` and manual `atlas.work_release_policies` relationship, so the physical rows have legitimate foreign keys and no ad hoc stub.

The fixture is explicitly fictional, not a copy of live Task/Person/Work data. It runs only against the exact loopback PostgreSQL `postgres` database, checks prepolicy source conditions, and refuses to create canonical Work, allocations, plans, offers, results, acceptances or principal obligations as a side effect of manufacturing the old carriers. The source does not impersonate an owner, worker or no-seat Person.

## Prepared source (not active in #2784)

- `tests/uniops_preexisting_mowing_carriers_held.py`: fixed transactional SQL fixture, exact read-only physical-row snapshot, pre/post count guard, fail-closed nonempty row preservation.
- `tests/prepare_uniops_preexisting_mowing_signed_held.py`: an additional exact Git-blob-pinned source compositor built on the **unchanged** U2/U4/P3/history preparer. It seeds and captures old carriers before governed actor transitions, checks they survived U2/U4/P3, then checks again after historical retirement, retaining the frozen P3 + historical positive/negative test and comparator.
- `tests/test_uniops_preexisting_mowing_carriers_held.py`: no-network negative tests for missing Task/occurrences, changed links/status/metadata, absent source-owned census identities, invented Work, unreviewed fixture bytes and duplicate/changed insertion anchors.

**Protected:** frozen historical governor, immutable signed companion, prior P3 signed hook/snapshot, receipt rules, real source-owned RPC authorizations, #2784 owner gate and approvals, Production schema/rows/grants/RLS, deployment, existing Atlas completion register. No migrations, credentials, network calls, production writes or feature release are in this candidate.

## Required verification and stopping conditions

1. Run no-network unit tests and source-pin review; verify composer against **exact frozen inputs**. This must be run in CI before a source-only approval claim, rather than relying on syntactic review.
2. Establish a **new, independently owner-approved exact signed test goal**, with its own explicit issue selector or equivalent protected gate. Do **not** reuse the completed owner approval lines in #2784 or loosen the existing protected workflow's selection rules. Review and explicitly authorize any necessary CI / runner changes separately.
3. On an authentic-schema **disposable local PG17 + GoTrue + PostgREST** test, prove frozen U2 accepted-first, U4 physical Actual/Result/Done, P3 no-auto successor, and separate historical cancellation still PASS. Require the physical seeded old Task and BOTH occurrences to have existed before signed operation. Require byte-equivalent row JSON after signed Result and after unrelated historical retirement (except no unavoidable source-managed timestamp normalization may be silently ignored), with P3 existing nonempty counts/release identity sets unchanged.
4. Reject any changed old Task status, source link, released timestamp, occurrence state, unexpected newly released carrier, new Work or obligation, broken actor denial or fixture-generated authority. Preserve all private logs and images only within protected ephemeral custody; report fixed safe classes and test receipts.
5. Verify cleanup and **zero Production mutation**. Update Atlas's existing integration completion register with real run IDs and exact PASS/FAIL; a source-only pass cannot close this signed gate.

**Still not covered even if this passes:** same-source historical cancellation of the mowing original, arbitrary old recurring Task sets, Company reconciliation, P1 Activity, full U1A overlap, universal 6A release, application deployment or outsider end-to-end journey.
