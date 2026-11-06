# P3 / U1A–U2C held source build, dependency and deferred acceptance

**Date:** November 6, 2026. **Status:** Authored source, **NOT compiled, NOT signed-tested, NOT migrated, NOT merged, NOT released**. The user's direction is build-first; collected runtime tests only when necessary to connect safely or approve release.

## Bounded result

The November 4 Dropbox governing amendment decision **6A** supersedes the earlier October 28/November 3 **automatic Result/Done → successor Work** behavior. In a result-driven evaluator, an accepted Actual may change current observed source state, qualify satisfaction and record the next *eligible window*, but must not offer, create, schedule or assign any new original/legacy task as a side effect. A separately authorized U1/U2 policy may later consider the next *independent* first offer. Retrospective nonassigned work (P2) is a **separate future** source path, not silently recognized by P1.

### Source-owned files in this draft

1. `01_result_only_rhythm_evaluator_held.sql`: exact **current deployed** `atlas.evaluate_rhythm_binding_v1(uuid,timestamptz,text)` function snapshot, read on Nov 6 via production **SELECT only**, baseline `md5(pg_get_functiondef)=774ad5c6728a615ada5bf4ea823c5498`. Changes exactly one source expression: the previous `v_task_result := atlas.ensure_rhythm_task_v1(...)` inside crossed due/failure boundary. `workflow_precheck`, `workflow_result`, `game_master_precheck`, `game_master_satisfaction` now return null task/occurrence and `qualified_evaluation_no_successor`; the same boundary transition, satisfaction, lease, due time and state update continue. **Ordinary non-result `clock` path is deliberately unchanged**, because silently disabling legacy scheduled tasks without a paired U2 cutover would be an unauthorized standalone migration. This is a held **source replacement**, not a versioned migration.
2. `02_accepted_first_original_readiness_held.sql`: private read-only original source receipt for **one already accepted unfulfilled** U2A offer. It checks the real signed current Ledger root, calls the existing U2C accept-first source helper, checks current single U1A/U1B Subject arbiter and frozen exact parent/strongest scoped Rulebook versions, and returns no Work/Clock/offer/campaign issuance. **Not** a public API or alternate writer, and this preflight cannot reserve capacity or replace atomic U2C finalization.
3. `verify_source_delta.mjs`: authored source-only code to reverse the one P3 code change and verify the byte/MD5 identity of the current live function. **Not run** this round.
4. `deferred_postconditions.sql`: read-only isolated-clone structural/ACL check, **not run**.

### Exact separate owner sources; do not copy history to make a green combined branch

| Component | Owner/held source | Source status and contract |
|---|---|---|
| Native first-party root, Foundry original, exact Rulebook | Noel U1A [#2465](https://github.com/optical-lift/noel-core-db/pull/2465) head `f9c372d3487ea6af4d29a4ee3b22579b9d94c5ae` | **Signed genuine clone PASSED** #42247086407 for exact U1A; no production release |
| Native property/class/Subject source history | Noel U1B [#2481](https://github.com/optical-lift/noel-core-db/pull/2481) head `18be5996faaa0f7a0def1d07c262f53b39e73605` | **Source drafted, uncompiled**; exact source-local precedence, disclosure and revision |
| One native standing candidate + separate worker accept/decline, held finalize | Noel U2A/B [#2482](https://github.com/optical-lift/noel-core-db/pull/2482) head `2be045d7fa51b83416a57c76b1a5508e815b8445` | **Source drafted, uncompiled**; no Work at offer/consent |
| One effective Rulebook arbiter, accepted-first existing Work writer guard, direct-API bypass cutover | Noel U2C [#2485](https://github.com/optical-lift/noel-core-db/pull/2485) head `1fd28856ff8d3fd99997fc0ae1fcf8714407a407` | **Source drafted, uncompiled**; no worker acceptance bypass |
| Separately delegated nonhuman issuer + 120-day single-original campaign | Noel U2E [#2486](https://github.com/optical-lift/noel-core-db/pull/2486) head `8f9f03d203f1a84c13f1c81ba86acdae49a83ef6` | **HELD: carrier UNBOUND**, no cron, issuer or auto-repeat; cannot infer any issuer from service_role or old root |
| Native original Work, physical Actual/one Done | Noel R01 #2362, R02 #2460, native completion-only [#2522](https://github.com/optical-lift/noel-core-db/pull/2522) | Mixed historical/held source versions; **only pinned signed cohorts** are accepted, no blanket SQL assembly. #2522 exact signed current-source/one Done #42236494993 |
| Manual activity → existing assigned original → accepted physical Actual | Noel P1 [#2487](https://github.com/optical-lift/noel-core-db/pull/2487) | Separate **noncampaign** signed composition #42236842501; inherited U1/U2 stack not thereby tested |
| Household native identity/disclosure/Need typed source | Noel U5 [#2564](https://github.com/optical-lift/noel-core-db/pull/2564) | Keep held; **no** fake Organization Ledger or unsafely generalized Household Work |
| Atlas original human encounter and U1/U2 default-off client | Atlas [#535](https://github.com/optical-lift/atlas/pull/535) | Held presentation; must consume the one existing Noel U2C writer and reuse one original Work, not copy sources |

### Two NO-SUCCESSOR boundaries, not a false single proof

- **Direct Result processing:** the held P3 source explicitly skips the legacy task issuer for result- and satisfaction-driven `evaluate_rhythm_binding_v1` invocation. The existing continuing-care Actual writer already returns `noNewWorkCreated=true` and `noClockAdmission=true`. It only qualifies Need/state.
- **Later independent clock/campaign evaluation:** this P3 file **does not disable** the pre-existing generic clock→legacy task path. Before any unified operating-path release, the separate U2C acceptance-only issuance cutover MUST reconcile all old task generators, scheduled ticks, direct APIs and replay. No one may interpret next eligibility as permission to bypass worker acceptance or owner campaign. One carried worker campaign limit ≤120 days and one original only; no renewal on Done.
- **Separate retrospective P2:** preserve testimony and true execution/report/ratification/original times; no fabricated preexisting acceptance, original or authorization. No P2 source actor is installed by this PR.

### Collected tests (deliberately DEFERRED)

On ONE isolated current-schema RiverSong PG17/GoTrue/PostgREST test assembly after source-owner reconciliation, run: exact source snapshot/SQL compilation; full 6A Result/workflow precheck, result, game-master satisfaction, same-state replay, partial/blocked/full and due/failure events preserving Need/current state but **zero new tasks/occurrences/Work/Clock/offers/campaigns**; separately triggered clock comparison; correct U1A exact Foundry root, U1B property/class/Subject precedence, U2A accepted recipient, current U2C root and no bypass through direct R01/R02, capacity (≤3) and duplicate/collision checks; concurrent offers/finalization and revoke/withdraw, old lineage no false equivalence; P1 assigned actual with no next offer; canonical Result/one Done; all ordinary Event/Household source regression; privacy/alternate readers. Verify exact-role RLS/ACL, auth denial, no unsafe public caller path, and zero introduced schema lint. Later human signed actor browser acceptance, separate migration/release approval. **Not performed this round.**

### Completion register / next step

This is a bounded **build source**, not end-to-end completion. The next build should reconcile the clock-side legacy issuer and U2C **single accepted-first Work cutover** under one source-owner decision. Do not create a new adapter, Foundry, Work store, cadence engine, task table, agent grant, service-role impersonator or migration. Keep Atlas completion register, November 4 P2/P3 decision, native nonfarm U5 hold and legacy private Event disclosure obligations open.
