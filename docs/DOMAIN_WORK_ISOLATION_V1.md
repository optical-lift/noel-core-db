# Domain Work Isolation — Noel, Atlas, Titus, Shared
Status: source implementation validated in PR #1437; effective from its merge to canonical main. No production DDL or data migration is part of this change.
Owner: noel-core-db; project: zirqkouammpwxlqfbsvf.

## Operating decision
**Content changes are data transactions; changes to the machinery are migrations.**
Noel research sessions must not create migrations for ordinary word definitions, anchors, evidence, relationships, or compositions. Atlas transactions and experiments are independent. Titus consumes separately authorized projections, not open access to Noel source.

The production Supabase project is shared physical hosting, not shared domain authorship or permissions. Logical boundaries: Noel research in the existing `draft`, `core`, `intelligence` surfaces; Atlas operations in `atlas` and explicitly owned reality/ledger interfaces; Titus learner/formation work in `titus`; explicit `shared_` migrations for crossing boundaries. Inherited namespaces are not silently reallocated.

## Change classifier — decide before running tools
1. **Data mutation**: Definition, source-token anchor, review note, proposed edge, research decision, verse composition, business contact, Atlas ledger entry, learner response. Use existing authorized table/API in a transaction, preserve provenance. **Do not use `supabase_migrations`, `apply_migration`, a new SQL migration, public fixture, or Git PR to carry data.** No publishing of private bodies.
2. **Schema/algorithm/access change**: New table/column/index/constraint/trigger/function/view/RPC/RLS/policy/grant, or changing their definitions. Use reviewed candidate, canonical source generation, disposable clone verification, the correct release lane, protected manual release. **Never direct-apply a live migration while working on a word or Atlas feature.**
3. **Cross-domain contract/access**: Identity, principal authorization, shared entity graph, Titus publication membrane, interface break, shared infrastructure. Use `shared_` with explicit dependency, privacy and compatibility review, not an arbitrary domain prefix.
4. **Historical custody**: Already-live untracked structural migration. Preserve live execution ledger and source hash; reconcile through privacy-appropriate custody. No replay or fabricated approvals. Protected row-bearing SQL stays out of this public repo. Issue #1435 is the existing bounded legacy problem, not permission for future direct releases.

## Release lanes
- `noel_`: Noel infrastructure/functions only. Independently checked from Atlas, Titus and WNPH; no embedded founder research rows. The Noel lane is **not** a substitute for row writes.
- `atlas_`: Atlas operations/structure only.
- `titus_`: Titus formation/application structure only (its own principal authorization still needed).
- `wnph_`: publishing custody only.
- `shared_`: interface/auth/common structural change, must satisfy global custody and all impacted product contracts.
- **Unknown/unclassified remains blocking** for every target. A foreign-domain existing deficiency is visible in the global incident report but cannot independently veto a clean unrelated domain's release.
- **Global source custody is still blocking on main, scheduled 15-minute audit, and manual checks.** On PRs the same global reconciler runs report-only, with the target domain's scoped checks and static constraints still active. Reporting an issue is not the same as hiding or approving it.

## Noel everyday research
Read `docs/NOEL_RESEARCH_OPERATIONS.md`. The six live Reality Pools tables already exist, so writes to existing columns require zero new schema migrations. Source identity must be proven against the current canonical token spine; edges are evidence scoped; `propagates_realm=false` unless expressly governed otherwise; decisions are append-only; maintain exact founder definition and authority. No automatic promotion from repeated evidence or a Strong's family match. Distinguish lexical headword identity from a research family relationship.

## Atlas everyday development
Atlas business facts/events are ordinary ledger data. Provisional algorithms, table-shape changes, and experimental cross-domain adapters belong in an isolated development/preview environment, not in the common production migration ledger. Only reviewed Atlas migration source goes through the `atlas_` release lane. Atlas data must never be copied into Noel to make a lookup easy.

## Titus read boundary
Titus may develop its UI and local previews independently of Noel research recovery. Private Noel source material crosses into Titus only by an approved read projection with independently verified principal binding and explicit authorization. Possession of a service-role transport secret is **not** an authorization decision. Pending PR #1434 and its identity dependencies remain separate from this change.

## Acceptance criteria
- Add evidence to 20 existing Noel pools using transactions only: **no new entries in `supabase_migrations.schema_migrations`**.
- An existing Noel-only uncustodied structural migration is **reported globally**, but does not veto Atlas or Titus-only review/release lanes.
- Noel-only structural release cannot proceed if **its own** history is uncustodied. Shared/unknown failures stay blocking where dependencies are shared/unknown.
- Public Git holds no protected founder research rows. Confidential source history gets independent protected storage and equality verification before being marked custodied.
- Existing founder definitions, source tokens, authority decisions and Atlas/Titus user permissions are unchanged by this refactor.

## Persistent decision points
- Source: `schemas/OWNERSHIP.md`, `custody/release-lanes-v1.json`, `docs/GOVERNED_MIGRATION_SOURCE_GENERATION.md`, `docs/PRODUCTION_DATABASE_RELEASE.md`.
- Operating instructions: root `AGENTS.md` and `docs/NOEL_RESEARCH_OPERATIONS.md`.
- Historical source: merged PR #1438 sealed eight public-safe live Noel migrations; draft PR #1436 was closed as superseded. Only two private H1847 source bodies remain open in issue #1435. Do **not** close that issue or weaken the global gate until independently verifiable private custody exists.
