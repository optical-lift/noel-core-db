# UNI-OPS-01 / U1A — Signed native Ledger-root Rulebook adoption

**Held, source-only.** November 3, 2026. Owner: Noel \`atlas_\` release lane. **Do not apply to production, merge as release, or call signed acceptance complete.**

## Exact bounded outcome

An active signed non-anonymous institutional Ledger root approves a **new immutable version** of one source-linked operating policy for **one existing active \`atlas.work_requirements\` Requirement whose \`source_object_type='reality_entity'\` and canonical Subject actually exist**. The current approved version remains readable after Foundry closes. A current signed root can deliberately revise, pause or retire only by appending another version with an exact expected predecessor. One original source fragment, action UUID and native approved actor are permanently linked. No Work, responsibility, plan, Actual, Clock admission, tasks, physical observations or new Subjects/Needs are generated.

Read-first: [Atlas U0 §11](https://github.com/optical-lift/atlas/blob/docs/unified-operating-handoff-20261103/docs/architecture/ATLAS_UNIFIED_OPERATING_REALITY_HANDOFF_20261103.md) and this repo's [source custody handoff](../../architecture/ATLAS_UNIFIED_OPERATING_REALITY_SOURCE_CUSTODY_20261103.md).

## Files

- \`candidate.sql\` — two private append-only policy/binding tables adapted from recovered October 28 Build 3; signed native root+Subject+Foundry authoring; root-only current policy read; no universal child Work engine.
- \`postconditions.sql\` — disposable-clone assertions for private tables, RLS, ACL, immutable triggers, no initial policy rows and only authenticated Public RPC transport.
- \`../../tests/atlas-u1a-governed-rulebook-source.test.mjs\` — fast structural source checks. These are **not signed tests and do not prove PostgreSQL DDL compiles**.

## Existing source paths reused, not copied

- Actor: \`atlas.foundry_current_signed_principal_v1()\` verifies real signed nonanonymous GoTrue session including \`auth.sessions\`; \`atlas.company_work_native_ledger_owner_self_v1(org,ledger)\` independently demands canonical active native Person+Seat and root authority. Then require the sole active governing primary Ledger participation.
- Need and Subject: only actual active \`atlas.work_requirements\` anchored to canonical \`reality.entities\`, under exact Organization and independent root \`identity\` and \`condition\` Subject disclosure. U1A does **not** establish cross-Ledger identity correlation or convert old farm \`growing_objects\` into canonical Subjects.
- Evidence: only the same Principal's non-suspended \`foundry.workspace_authority_registry_v1\` and original immutable \`foundry_reality_input_v1\` event with an exact quoted \`operating_instruction\` or \`work\` fragment; external reference alone cannot grant authoring authority.
- Version: append-only immutable table + one subject-override binding. Versions for a given Organization/Ledger/rule key are serialized by transactional advisory lock and expected prior UUID; same action UUID only replays exact same input, rechecking current signed authority first. A retired version cannot be silently reactivated. Later paused versions prevent older active versions from winning again.
- Transport: \`public.adopt_governed_rulebook_version_self_api_v1\` and \`public.read_governed_rulebook_current_self_api_v1\` allow authenticated transport, but all authorization happens inside private source functions; private tables and private functions have no direct anon/authenticated/service-role grants.
- The first U1A binding is intentionally limited to **one exact Subject override**. Inherited classes, zone/stage matches, Household custody and mixed Ledger authority need separately reviewed source adapters; this candidate must not masquerade as completed U1 or U2.

## Live boundary / no fabricated launch

Read-only November 3 check found 77 active Work Requirements, **zero** with the recovered evaluator's \`reality_entity\` linkage, and zero saved \`foundry_reality_input_v1\` events. Therefore **there is no eligible live Elm adoption request** and source fixtures must be synthetic and isolated. Do not insert fake live rows, reconstruct old growing objects as canonical Subjects or change disclosure rights just to make this test pass.

## Verification and release gates

1. **Already possible:** review candidate and run \`node --test tests/atlas-u1a-governed-rulebook-source.test.mjs\` for structural source invariants.
2. **Not yet proven:** full production-shaped disposable clone must compile \`candidate.sql\` and pass \`postconditions.sql\` in a single \`BEGIN ... ROLLBACK\`, preserving complete schema and row baseline. No direct production SQL is allowed.
3. **Not yet proven:** genuine signed human root, worker, outsider, revoked/expired seat, denied/wrong Subject, wrong Ledger, absent Source, externally asserted Source, concurrent competing versions, stale expected UUID and same/different payload replay. Test two independent current sessions and verify immutable readback, complete lack of unauthorized data/count leakage, zero Work/Task/Clock/Result/Need changes, and no deleted source history.
4. **Not yet proven:** grammar/eligibility of every policy variant. Recovered Build 2 supports condition-driven rules; owner-standing visits require a lawful separate U2 evaluation path. \`policyExecutable=false\` is explicit in every U1A receipt.
5. **Not authorized:** production migration generation, Protected release, Atlas browser UI, Household adapter, first-work release, generalized inheritance, or legacy queue retirement.

**Next after this held slice:** run the protected schema-shaped rollback test; repair exact source error in this candidate without broadening authority; then real GoTrue-signed multi-person negative/positive test. Only after those proofs consider an approved versioned U1A source release. U2 remains separate.
