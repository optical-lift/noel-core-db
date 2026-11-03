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

**Status:** 11 source-contract assertions passed in an isolated JavaScript evaluation. The new local script, PostgreSQL compilation, actual RiverSong Node process and genuine signed actors have **not** been run in this session. U1B property/class approval and U2 offered initial Work remain queued; user requires full farm identity audit and second domain before Elm pilot.


### Foundry custody review is a mandatory adoption gate

The installed `atlas.prepare_foundry_workspace_self_api_v1` creates new workspaces with `custody_review_state='pending'` and `subject_identity_state='unresolved'`, even when an authenticated human selects `verified_self`. Its own source labels this preparation *provisional* and not authority to operate on an existing Subject. U1A must not mistake possession of that workspace for reviewed provenance.

The held writer now requires `custody_review_state='reviewed'`, a recorded reviewer Principal, a review timestamp, and at least one custody basis reference, in addition to its existing active real signed session, exact governing Ledger root, current Subject disclosure, and same-human author check. This is true for both `verified_self` and `documented_external` workspaces; an unreviewed workspace must be rejected rather than silently upgraded.

**Required fresh-duplicate signed clone scenarios:** (1) real signed owner creates/captures a provisional workspace and tries adoption before custody review → genuine permission denial and zero Rulebook rows; (2) separately source-authorized custody review completes, with original literal intact → owner can adopt one version after current root/Subject grants; (3) review is revoked or suspended → further adoption and reread must deny; (4) a worker or outsider with Foundry access but without governing native Ledger root must deny; (5) spoofed reviewer IDs/JSON without actual reviewed registry state must deny. Signed HTTP must prove the relevant existing native functions enforce review authority, not inject a row or forged JWT claim.

Source-contract check #13 verifies the exact reviewed-state predicate. This is **static source proof only**. Neither the real signed custody transitions nor PostgreSQL execution have run; approval and production release remain held.
