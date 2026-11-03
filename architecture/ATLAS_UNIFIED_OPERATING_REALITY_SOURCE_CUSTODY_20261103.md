# Atlas Unified Operating Reality — Noel Source Custody & Next Release Gates

**November 3, 2026 — documentation reconciliation only.** No migrations, grants, RLS, SQL candidates, production Work or signed-user actions are changed by this document. The overarching [Atlas U0–U7 unified handoff](https://github.com/optical-lift/atlas/blob/docs/unified-operating-handoff-20261103/docs/architecture/ATLAS_UNIFIED_OPERATING_REALITY_HANDOFF_20261103.md) is the sole active cross-repository finish-train baton `UNI-OPS-01`. It is an implementation/acceptance handoff, **not** a new authority layer above Noel's source custody and protected release process.

## Canonical responsibility

- **Noel:** source truth, Person/Household/Organization/Ledger custody; persisted versioned Rulebook/Need and Subject linkage; exact root adoption, native accepted responsibility, independent Subject disclosure; Work/Result/Clock contracts; authorization, idempotency, negative acceptance and migrations.
- **Atlas app:** authorized notebook/Foundry proposals, governor approval encounter, Worker Day / My Work / Today / Work Focus, display of permitted current/historical context and verified source receipts. An application build does not create DB authority.
- **ICM System Map:** only source-verified live nouns and movements; must not mark an unreleased Rulebook or R02 operator as live.
- **Product Map:** human journeys and failure/uncertainty states; must not infer source implementation or invent a second task/recurrence engine.

## Grounded November 3 read-only baseline

| Current Noel reality | Verified | Caution |
| --- | --- | --- |
| `atlas.rhythm_rules`, `rhythm_bindings` | 107 active Rules; 117 active bindings | Historically governed source records, not installed universal Rulebook |
| `atlas.rhythm_state` | 98 weed-stewardship + 5 mowing states; none has `current_task_id`; no direct `work_items` source join for these states in the read-only check | Existing historic/legacy Work may be present under other sources; no bulk correction |
| `atlas.governed_rulebook_versions_v1`, `atlas.governed_rulebook_bindings_v1` | Both **absent** (`to_regclass` null) | October 28 handoff records 50 rollback-only tests in three builds, **not** a live migration |
| Household | 21 active rhythms; 0 `household_need_occurrences_v1`; 0 `household_spaces` | No current real Household subject-to-original Work/Actual/renewal proof |
| Event original/dependencies | 0 Work context links to approved Dec 19 Christmas occurrence, 0 active `depends_on` Work relations, 0 prerequisite events | Ten owner-approved Work definitions are documentary, not live original Work |
| Generic owner approval, care Actual/successor | `public.governor_review_rhythm_opportunities_self_api_v1`, `public.governor_approve_rhythm_opportunity_self_api_v1`, `public.owner_establish_standing_continuing_care_work_self_api_v1` and `public.record_continuing_care_actual_self_api_v1` **not in live checked function catalog** | Held clone proof is not prod source installation |

**Signed held evidence:** [R01 full original→Actual→next signed clone #41578056067](https://github.com/optical-lift/noel-core-db/actions/runs/41578056067) PASS; [R02 universal governor review/approve clone #41660483209](https://github.com/optical-lift/noel-core-db/actions/runs/41660483209) PASS with zero new Atlas lint errors. R02 includes one source adapter (`continuing_care_actual_v1`), not universally supported Household/Event domains. Test-only merged PRs [#2456](https://github.com/optical-lift/noel-core-db/pull/2456), [#2458](https://github.com/optical-lift/noel-core-db/pull/2458) do **not** install domain SQL.

**Held source ancestry:** [#2362](https://github.com/optical-lift/noel-core-db/pull/2362) original care, [#2364](https://github.com/optical-lift/noel-core-db/pull/2364) standing governor source, [#2368](https://github.com/optical-lift/noel-core-db/pull/2368) one Done, [#2385](https://github.com/optical-lift/noel-core-db/pull/2385) disclosed rhythm reader, [#2460](https://github.com/optical-lift/noel-core-db/pull/2460) R02 generic mandate. App held [#531](https://github.com/optical-lift/atlas/pull/531), and preceding R01 care UI branch. At audit, Noel R02 held branch diverged markedly from current main (ahead 140, behind 67); do **not** merge its historical tree indiscriminately or misstate branch source PASS as production migration acceptance. Rebase/reconcile by owning invariants and precise source diffs.

## Exact uncompleted chain — source-owner handoff

| Increment | Noel source evidence to recover | Missing acceptance / release |
| --- | --- | --- |
| U0 — source reconciliation | October 28 Build 1 classifier / Build 2 rule resolver / Build 3 persisted Rulebook (10+22+18 rollback-only tests), existing `atlas.rhythm_rules`, R01/R02 held SQL, native Person scope, Household Need, old farm queue & crop sources | Find exact candidate files/SHAs and compare against current main; map who can execute every read/write; mark competing source variants as keep/supersede with reasons, **no DDL** |
| U1 — approved Rulebook | Existing Foundry source capture, private Rulebook proposal, native Ledger root/Person/Subject | Signed immutable version, class/exception/season & rule-author/subject binding, root approve/revise/pause/retire, source-linked proposal/evidence/readback and outsider denial; authorized migration only later |
| U2 — first bounded Work | Existing `atlas.work_items`, `work_allocations`, `work_execution_plans`, requirement/Need, Rule/Binding/State, accepted Person scope | Source-independent **initial** eligible Work admission, class exceptions and season, capacity/order/timezone/workday selection, collision/legacy cohabitation; not one UI-selected campaign per Subject or 103 precreated tasks |
| U3 — live Subject context | Existing Subject/zone/crop/placement and Household source relations, historical Weed Card reference | Bounded source-authorized current/cited historical Context read. Verify withheld related Subject through alternate zone/map/old readers, no stale equipment instructions silently issued |
| U4 — accepted Actual → next | R01 source positive, R02 registered adapter and common mandate, native Done | Negative withdrawn scope, withdrawn Subject disclosure, blocked/partial/winter-ready, campaign end, concurrent creators and Results, replay, seasonal consequence; one original and one next, without source weakening |
| U5 — second non-farm proof | Household `household_rhythms`, `household_need_occurrences_v1`, Household Laundry World Kernel/Result and cleaning room truth | Calibration cannot create Principal-protected obligation without adoption; `wash_started` affects only beginning cycle; one original/Need/Actual/next across Household without fake Company Ledger; separate cleaning zone evaluation |
| U6 — Event prerequisite | Native Event disclosure policy, `work_item_relations`, Event Work writer/result contracts | Actual prerequisite satisfaction gates release, not merely a relation row; resolve shared-checklist vs worker-attestation constructor; independently typed Event access and all reader paths; only then original approved December 19 work |
| U7 — production | Approved exact Noel migration and app source, protected runner, migration ledger, source postconditions | Explicit production approval, signed governor/worker/outsider/withdrawn and real desktop/mobile accepted readback, then exact production version/receipt and controlled retirement |

**Critical correction:** Signed R02 negative-case tests are part of U4 release safety; they are not the only remaining build. The first Rulebook adoption and automatic initial Work release are upstream missing operations. Do not expand source API capability beyond what an accepted Rulebook permits, and never mistake a cadence expiry for a physical observation or worker unfinished Work for Principal attention.

## U0 source custody matrix — required next deliverable

The next bounded round is *read-only reconciliation*: collect exact source files/SHAs, their owning domain and current release status; enumerate canonical Subjects/Need/Rule, Work/Result and calendar/attention identities; trace signed root/worker/Household/outsider authorization; compare planned vs installed functions, accepted and competing candidates, release/candidate migration receipts and current Product Map consumers. Produce one table:

`source + revision | original identity | actor | read membrane | write membrane | policy/Need version | result qualification | projection | data migration coexistence | winning generation | proof | gap`

Exit U0 only when the 50 earlier rollback-test sources are actually located and reconciliation identifies the **next single bounded coding outcome**, accepted gate and protected scope. If unrecoverable, record that as missing source; do not reconstruct it from a handoff claim.

No arbitrary DDL, open public grants, production SQL, live Person/Work changes, fabricated crop data, bulk legacy backfill, RiverSong provider changes or Vercel deployment are authorized by this handoff.

## Reuse and independent release obligations

- Atlas [Completion Register](https://github.com/optical-lift/atlas/blob/docs/unified-operating-handoff-20261103/docs/integration/ATLAS_INTEGRATION_COMPLETION_REGISTER.md) retains CARE-01/02/03, HOUSEHOLD-01, WORK-01, ACCESS-01, EVENT-01, WEEK-01, IN/PROGRAM/COLLAB/UX and earlier release debt. The new document is a **pointer**, not a deletion of that backlog.
- Historical conflicting directions in [October 28 Foundry handoff](https://www.dropbox.com/scl/fi/es7ggactau9c7o0jjng0o) are clarified, not revoked: preserve every source result, rule exception, truthful physical distinction and season.
- Repository [AGENTS.md](../AGENTS.md), [Domain Isolation](../docs/DOMAIN_WORK_ISOLATION_V1.md), [Production Schema Clone Validation](../docs/PRODUCTION_SCHEMA_CLONE_VALIDATION.md) and governed release sources control writes. PRs are reviewed independently; an unchanged clone receipt does not license migration.


## U0 exact-package recovery status — November 3 (partial)

The October 28 original conversation identifies RiverSong local downloaded `atlas_universal_intelligence_source_v1/v2/v3` packages (final Build 3 `atlas_universal_intelligence_source_v3_archive_rollback_fix.zip`) with `01_governed_need_signal_classifier.sql`, `02_rollback_acceptance.sql`, `03_resolve_governed_subject_rule.sql`, `04_rule_resolution_rollback_acceptance.sql`, `05_native_rulebook_and_existing_sources.sql`, and `06_native_sources_rollback_acceptance.sql`. The reporter confirmed 10 + 22 + 18 rollback-only tests PASS with the unchanged local clone. These six source bytes, hashes, complete raw run outputs and exact canonical Git source revision **are not recovered** in the current connected Dropbox/GitHub session; do not call this verified source custody or infer that any tested SQL is installed. Live November 3 catalog still has historic farm `rhythm_rules`, native `work_items` and transitional `task_release_queue_items`, but no governed version/binding tables. The exact U0 evidence/disposition matrix lives in the [Atlas handoff §11](https://github.com/optical-lift/atlas/blob/docs/unified-operating-handoff-20261103/docs/architecture/ATLAS_UNIFIED_OPERATING_REALITY_HANDOFF_20261103.md). **U0 remains open** until protected recovery, checksum, exact current-main/held-R01/R02 read/write/actor conflict reconciliation, and a selected source-owner U1 contract. No code, migration, release, grant or production change follows from this documentation entry.
