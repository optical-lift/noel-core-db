# UNI-OPS-01 / U1A — Signed native Ledger-root Rulebook adoption

**Held, source-only.** November 3, 2026. Owner: Noel `atlas_` release lane. **Do not apply to production, merge as release, or call signed acceptance complete.**

## Exact bounded outcome

An active signed non-anonymous institutional Ledger root approves a **new immutable version** of one source-linked operating policy for **one existing active `atlas.work_requirements` Requirement whose `source_object_type='reality_entity'` and canonical Subject actually exist**. The current approved version remains readable after Foundry closes. A current signed root can deliberately revise, pause or retire only by appending another version with an exact expected predecessor. One original source fragment, action UUID and native approved actor are permanently linked. No Work, responsibility, plan, Actual, Clock admission, tasks, physical observations or new Subjects/Needs are generated.

Read-first: [Atlas U0 §11](https://github.com/optical-lift/atlas/blob/docs/unified-operating-handoff-20261103/docs/architecture/ATLAS_UNIFIED_OPERATING_REALITY_HANDOFF_20261103.md) and this repo's [source custody handoff](../../architecture/ATLAS_UNIFIED_OPERATING_REALITY_SOURCE_CUSTODY_20261103.md).

## Files

- `candidate.sql` — two private append-only policy/binding tables adapted from recovered October 28 Build 3; signed native root+Subject+Foundry authoring; root-only current policy read; no universal child Work engine.
- `postconditions.sql` — disposable-clone assertions for private tables, RLS, ACL, immutable triggers, no initial policy rows and only authenticated Public RPC transport.
- `../../tests/atlas-u1a-governed-rulebook-source.test.mjs` — fast structural source checks. These are **not signed tests and do not prove PostgreSQL DDL compiles**.

## Existing source paths reused, not copied

- Actor: `atlas.foundry_current_signed_principal_v1()` verifies real signed nonanonymous GoTrue session including `auth.sessions`; `atlas.company_work_native_ledger_owner_self_v1(org,ledger)` independently demands canonical active native Person+Seat and root authority. Then require the sole active governing primary Ledger participation.
- Need and Subject: only actual active `atlas.work_requirements` anchored to canonical `reality.entities`, under exact Organization and independent root `identity` and `condition` Subject disclosure. U1A does **not** establish cross-Ledger identity correlation or convert old farm `growing_objects` into canonical Subjects.
- Evidence: only the same Principal's non-suspended `foundry.workspace_authority_registry_v1` and original immutable `foundry_reality_input_v1` event with an exact quoted `operating_instruction` or `work` fragment; external reference alone cannot grant authoring authority.
- Version: append-only immutable table + one subject-override binding. Versions for a given Organization/Ledger/rule key are serialized by transactional advisory lock and expected prior UUID; same action UUID only replays exact same input, rechecking current signed authority first. A retired version cannot be silently reactivated. Later paused versions prevent older active versions from winning again.
- Transport: `public.adopt_governed_rulebook_version_self_api_v1` and `public.read_governed_rulebook_current_self_api_v1` allow authenticated transport, but all authorization happens inside private source functions; private tables and private functions have no direct anon/authenticated/service-role grants.
- The first U1A binding is intentionally limited to **one exact Subject override**. Inherited classes, zone/stage matches, Household custody and mixed Ledger authority need separately reviewed source adapters; this candidate must not masquerade as completed U1 or U2.

## Live boundary / no fabricated launch

Read-only November 3 check found 77 active Work Requirements, **zero** with the recovered evaluator's `reality_entity` linkage, and zero saved `foundry_reality_input_v1` events. Therefore **there is no eligible live Elm adoption request** and source fixtures must be synthetic and isolated. Do not insert fake live rows, reconstruct old growing objects as canonical Subjects or change disclosure rights just to make this test pass.

## Verification and release gates

1. **Already possible:** review candidate and run `node --test tests/atlas-u1a-governed-rulebook-source.test.mjs` for structural source invariants.
2. **Not yet proven:** full production-shaped disposable clone must compile `candidate.sql` and pass `postconditions.sql` in a single `BEGIN ... ROLLBACK`, preserving complete schema and row baseline. No direct production SQL is allowed.
3. **Not yet proven:** genuine signed human root, worker, outsider, revoked/expired seat, denied/wrong Subject, wrong Ledger, absent Source, externally asserted Source, concurrent competing versions, stale expected UUID and same/different payload replay. Test two independent current sessions and verify immutable readback, complete lack of unauthorized data/count leakage, zero Work/Task/Clock/Result/Need changes, and no deleted source history.
4. **Not yet proven:** grammar/eligibility of every policy variant. Recovered Build 2 supports condition-driven rules; owner-standing visits require a lawful separate U2 evaluation path. `policyExecutable=false` is explicit in every U1A receipt.
5. **Not authorized:** production migration generation, Protected release, Atlas browser UI, Household adapter, first-work release, generalized inheritance, or legacy queue retirement.

**Next after this held slice:** run the protected schema-shaped rollback test; repair exact source error in this candidate without broadening authority; then real GoTrue-signed multi-person negative/positive test. Only after those proofs consider an approved versioned U1A source release. U2 remains separate.


## Owner decisions and current U1A limit (November 3)

Exact decisions: **1D, 2C, 3B, 4C, 5C, 6B, 7C, 8C, 9C, 10C**. They control U1B/U2 and release; they do not turn this source candidate into a deployable product.

- **1D/2C/10C:** use an isolated fictional nonproduction Subject for the first clone proof. Before any Elm production pilot, complete the farm-wide canonical Subject identity audit AND the genuine Household/non-farm typed Actual/next-Work proof. No fake live Source, Subject, Need, Work, or scope grant.
- **3B/4C/6B:** present existing recorded rules individually for root approval with citations and explicit unknowns; the eventual seasonal property-wide umbrella contains separately adopted class-wide rules and separately adopted Subject exceptions. Do not interview anew to reproduce existing sourced rules. This held U1A writer still demands one new Foundry Event and one exact Subject: it is NOT yet the chosen property/class approval writer. Queue separate U1B source and authorization design, preserve all old farm Rule data and avoid legacy queue reactivation.
- **5C/7C/8C/9C:** eventual Elm weeding/restorative care must use physical evidence; Anna is limited to three open originals with manual weekly workdays, and she must accept/decline each offered candidate before the sole canonical original Work writer releases it under a fresh authorized capacity and disclosure recheck. Acceptance is not owner approval and the offer is not original Work.

### Next single gate

Source fixes on this PR corrected malformed JavaScript test quote escapes and changed the Foundry event row read to select its real columns. A policy-key allowlist now rejects client-invented property/class scope or auto-release fields rather than granting them through this exact-Subject U1A. The held structural postconditions include an unsigned read/write default-denial smoke without creating a fixture. Nine static source-contract tests were executed against the candidate in an isolated JavaScript assertion harness; these do not establish Node execution on RiverSong, PostgreSQL compilation, signed positive and negative actors, concurrent approval, or production acceptance.

Do not merge or install before disposable full-schema rollback, actual signed principal and independent Subject denial tests, source owner approval and separate exact protected release. U1B and U2 remain queued, not included here.


## RiverSong rollback gate (prepared, not executed)

The held source includes [run_riversong_rollback.sh](run_riversong_rollback.sh), a local-only, fail-closed PostgreSQL 17 runner. It executes the Node source-contract test, checks the exact RiverSong Unix socket, noel_schema_clone:55432 and existing isolated PG data directory, and refuses an arbitrary remote URL, server startup or restoration.

It requires currently installed copies of the real native Ledger, Requirement, Person/Subject, Foundry, auth.sessions and signed source functions. If the October 28 retained clone lacks atlas.work_requirements or any other dependency, it **stops before any SQL mutation**. Do not repair this clone piecemeal or connect to production. A fresh full-schema protected disposable clone is the proper next environment.

Only after all prerequisites does it send one psql transaction: BEGIN, short local timeouts, source candidate, structural/unsigned postconditions, ROLLBACK. First SQL error aborts and rolls back. Afterwards it compares original schema-function-trigger-policy/data-count fingerprints and confirms both U1A tables are absent. It does not run authentic signed GoTrue actors.

On RiverSong only, after an authenticated checkout of the existing U1A draft branch and verification of its exact head SHA, invoke:

    bash candidates/atlas_governed_rulebook_u1a_v1/run_riversong_rollback.sh

Do not paste credentials into chat, checkout into a production deployment, or interpret this documented command as an already executed test. It may refuse the old retained clone without changing it.

**Separate signed acceptance still required:** a fresh protected schema-only local GoTrue environment with fictional Subject, Requirement and human principals; current root approval and reread, worker/outsider/revoked/withdrawn/wrong-Ledger/wrong-Subject and missing-evidence denial, same- and different-payload replay, competing revisions, immutable source, and zero native Work/Result/Clock/Need effects. Use the existing R01 protected fresh-clone signed-care harness as a method reference; never copy its farm-specific writer authority into U1A. The retained RiverSong clone is not the signed-HTTP test environment.

**Status:** 21 static source-contract assertions passed in an isolated JavaScript evaluation. The new local script, PostgreSQL compilation, actual RiverSong Node process and genuine signed actors have **not** been run in this session. U1B property/class approval and U2 offered initial Work remain queued; user requires full farm identity audit and second domain before Elm pilot.


### Exact independent Foundry custody review — current source contract

Read-only Noel source inspection confirms:

- `atlas.prepare_foundry_workspace_self_api_v1` creates a **pending, provisional** workspace. This never grants authority to adopt a Rulebook.
- `atlas.request_foundry_source_custody_review_self_api_v1` requires a **different active human Principal connected to the same native Ledger** as independent reviewer, with bounded source references and permitted operations. It does not permit the owner to self-review.
- `atlas.decide_foundry_source_custody_review_self_api_v1` changes a review **case** to `approved` following a signed independent decision. It deliberately leaves `workspaceCustodyState='pending'`; there is no automatic promotion of the workspace record or Subject.
- `atlas.revoke_foundry_source_custody_review_self_api_v1` can mark an approved case `revoked`. Review may also expire. Existing Source review only permits limited human operations including `analyze`; Ledger-root authority and current Subject disclosure are *separate* approval gates for Rulebook establishment.

**U1A guard:** a real signed Ledger root, previously authorized original Foundry Event, exact canonical Requirement and independently disclosed Subject remain mandatory. Before initial adoption or same-action replay, the writer takes the **native Foundry workspace advisory transaction lock**, then verifies an independently `approved`, nonrevoked, unexpired source-custody review case for the exact `entryId`. The review must occur **after the original Event was saved**, refer to that Event in `source_refs`, and authorize `analyze`. An arbitrary `pending` workspace or review of an unrelated entry is never sufficient. The immutable Rulebook receipt stores the exact approved review-case ID and timestamp.

**U1A root historical reader:** policy versions remain available to a currently authorized governing root even after Foundry closes, because history must not disappear. The reader independently evaluates the exact review case and returns `sourceReviewCurrent=false` when that source review is revoked, expired, or its workspace is disabled. It never declares that historical policy executable (`policyExecutable=false`), and must not silently fall back to an older active version.

**Signed tests still required on a FRESH disposable clone:** (1) genuine owner + independently signed reviewer + disconnected worker/outsider; (2) captured Event in pending workspace without approved review **denies** adoption with zero Rulebook rows; (3) approved review for an unrelated Event or without `analyze` **denies**; (4) an exact, after-Event, current independently approved review plus root and Subject grants establishes one immutable version; (5) same-action replay is idempotent and changed-payload replay denies; (6) revoked or expired case denies *new* adoption while historical root read returns `sourceReviewCurrent=false`; (7) competing approvals, revoked Seat/root/Subject grants, wrong Ledger and outsider deny without source/count disclosure; (8) no Work, Need, Actual, Clock or legacy task effects. Do not fabricate positive approvals by direct SQL insertion into the review table or by forging JWTs.

**Status:** 21 U1A static source-contract assertions passed in an isolated JavaScript evaluation. Neither PostgreSQL compilation, native RiverSong script execution, nor genuine signed GoTrue tests have been performed. U1B property/class policy and U2 offered Work remain separately held.


### Current review-case readback and deterministic replay

The current U1A source records the approved independent source-review case identifier and its UTC-normalized review timestamp in an immutable `source_basis` receipt. Replays must match this exact evidence; a different current review cannot silently re-authorize an old action ID. The writer locks the workspace's native review/revocation advisory key before inspecting the case. The current root-only historical reader returns `sourceReviewCurrent` according to the linked exact case's latest unrevoked/unexpired status and workspace availability, without removing historical approved versions. All paths continue to report `policyExecutable=false` and cannot establish original Work.

Source-only checks for these invariants are included in 16/16 local JavaScript assertions. **A native PostgreSQL execution and independently signed two-person review/adoption/revocation race have not occurred.** The actual authorized review and fresh GoTrue source acceptance must be proved before this held draft can move toward release.


## Signed source-proof package — isolated C1 Subject and reviewer

Owner choice **1D** requires the first proof to use a fictional nonproduction Subject. Noel's current `atlas.governor_set_subject_disclosure_self_api_v1` only authorizes original `spatial/growing_object` and `event/occurrence` Subjects; it does **not** authorize arbitrary `reality.entities` merely because an entity is canonical. This held U1A writer now explicitly requires a **same-ID canonical spatial growing_object linked to an existing `atlas.growing_objects` in the exact Organization's farm**. No nonfarm or property/class adapter is implied. The full farm Subject audit and second domain proof remain U1B/U5 prerequisites before Elm production.

### Owner-selected Option D: fresh RiverSong Supabase + GoTrue + REST test

The current held draft uses a **separate, randomly ported, disposable Supabase project**, not the old 55432 clone and not the developer's normal 54322 project. The earlier fixed-host-port controller instructions are **superseded**. PostgreSQL inside Docker normally reports port 5432, regardless of the host mapping; treating it as host port 54322 was incorrect and is removed. PostgreSQL booleans explicitly cast to text read `true`/`false`, rather than `t`/`f`; both clone and signed preflights now enforce the correct representation.

The five added source-only components are:

- `run_riversong_option_d_isolated.sh`: one-command macOS RiverSong preflight, **unique local Supabase project ID**, wildcard-bind-checked random API/DB host ports, pinned Supabase CLI, original C1 fixtures, local-only Auth/REST/PG, named source dependency checks, exact source-function fingerprint checks, and always-attempted `supabase stop --no-backup` cleanup confined to its own temporary project. No production connection string, migration push or update of the old clone.
- `native_source_fingerprints_20261103.tsv`: **nine current, read-only Noel native authority/Foundry function definition MD5s**, captured from the governing source on November 3, 2026. They contain no credentials or personal data. A local migration snapshot with missing/changed permission semantics must **STOP** rather than offer a forged substitute.
- `signed_u1a_fictional_fixture_v1.sql`: only the C1 fictional original Bed 3 canonical twin and one explicit native Requirement plus reviewer Principal, allowed after a session-local disposable-clone guard; no fabricated approval or Work.
- `run_signed_u1a_on_fresh_clone_v1.py`: exact local environment and project-ID gate; verified unique host port from the temporary config; original native C1 prerequisite; candidate and postconditions in disposable local SQL, followed by fictional fixture and signed tests.
- `validate_signed_u1a_local_clone_v1.py`: genuine GoTrue owner + independent connected reviewer + worker/outsider/anonymous sessions, pending custody denial, exact source review, current Subject grants, immutable versioning, idempotency and conflicting replay, competing version approvals, pause/retire, same-workspace unrelated source denial, source-review revocation, session withdrawal and no canonical Work/Need effects.

The branch also contains [a dedicated held U1A workflow](../../.github/workflows/u1a-riversong-isolated-signed-proof.yml), restricted to **draft Noel PR #2465**, the exact source branch, and a genuine self-hosted machine named RiverSong. It has only repository read permission and **no production environment or secrets**. A separate GitHub-hosted source syntax job must pass before RiverSong is eligible. This is **not** the main production-schema validation workflow.

**How to invoke manually on RiverSong, if the dedicated workflow cannot find an eligible Noel runner:** check out the clean held branch with current head SHA, then run:

```bash
bash candidates/atlas_governed_rulebook_u1a_v1/run_riversong_option_d_isolated.sh
```

The script takes no arguments and cannot be pointed to production, to 55432, or to persistent 54322. It does **not** install Docker, Node, PostgreSQL or the pinned Supabase CLI onto RiverSong, and it never uses production schema dumps. The versioned local migrations must recreate the actual native definitions and match all nine pinned fingerprints; if they do not, U1A remains blocked pending a separate source-authorized schema-parity solution, not dummy permissions.

**Current evidence:** 23 of 23 non-subprocess source-contract assertions have passed in an isolated JavaScript evaluation. The actual Node subprocess checks for Python AST and Bash syntax are defined but not yet independently executed. The new GitHub workflow has been created and is pending; source CI is separate. No complete fresh local database installation, genuine signed test, concurrency result or disposable teardown can yet be claimed. U1A remains **draft and held**. U1B property/class existing-rule adoption, U2 worker offer/acceptance, the separate nonfarm domain proof and the full Elm Subject identity audit remain queued.

### Signed-probe negative cases staged after fixture

The signed Python test also verifies that an independently reviewed Source Event does **not** authorize a second, unreviewed Event in the same workspace; two simultaneous approvals against one expected version cannot both win; and the root's revoked `auth.sessions` row causes a real signed historical read to fail. These tests use the *same existing local GoTrue/C1* identities, not fabricated JWTs. Concurrent writers and withdrawn-session tests have **not been executed**.

The latest source-contract check in an isolated JavaScript environment passed **21/21 executable static assertions**; the additional Python AST syntax test is defined for the real `node --test` execution but is **still unrun**. Consequently, no PostgreSQL compilation, genuine GoTrue test, disposal receipt or production release may be claimed.
