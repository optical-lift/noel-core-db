# Atlas Actions-Outage Database Custody Audit — 2026-10-02

**Status:** preservation/reconciliation audit; no migration or release authorization  
**Audit branch:** `recovery/actions-outage-custody-audit-2026-10-02`  
**Repository main:** `d3b528b56d7630abf9d6fc67ee92c4475b8fa4ab` (September 24 source checkpoint)  
**Live project inspected:** `noel-core` / `zirqkouammpwxlqfbsvf`  

## 1. Critical finding

`noel-core-db/main` did not advance with the system after September 24. Live production migrations and branch work continued through October 2.

Therefore repository `main` is **not presently a complete source reconstruction of production**.

No cleanup, branch deletion, or database rebuild may assume otherwise.

## 2. Census

The complete branch listing was inspected across nine pages: **805 surviving branches**.

Live `supabase_migrations.schema_migrations` was read for versions beginning September 20 and shows continued production evolution through October 2.

The custody problem is bidirectional:

- some branch work is absent from production and must remain recoverable;
- some production-live migrations are absent from `main` and must regain canonical source custody.

## 3. Production-live cumulative topology / scheduling / geography / spatial trunk

A major source line can be collapsed by verified ancestry as follows:

`architecture/reality-ledger-booking-offering-requirements-routing-v1`
→ `architecture/reality-ledger-temporal-enrichment-occupancy-v1`
→ `architecture/atlas-ledger-target-intelligence-v1`
→ `architecture/reality-relationship-substrate-v1`
→ `architecture/reality-entity-topology-v1`
→ `architecture/reality-organization-topology-v1`
→ `architecture/geographic-substrate-v1`
→ `architecture/spatial-operating-kernel-v1`
→ `architecture/spatial-intake-v1`

Terminal verified tip:

- branch: `architecture/spatial-intake-v1`
- SHA: `0bc768cac28f902f2a2d5794507d6c4ea2c5c212`

The similarly named `architecture/spatial-intake-source-v1` is one commit behind the terminal branch and is not the terminal tip.

This line includes, cumulatively:

- Reality Ledger core and Elm cutover;
- authenticated Reality access;
- Reality responsibility authority;
- Personal Atlas capacity and portfolio-office cutovers;
- Correspondence identity / Institutional Communication context, safe operations, outbound context, and response work;
- Company Work receiver/collaboration uptake;
- external entity bridge;
- universal booking/calendar/availability/recurrence/request/approval/offering routing;
- universal temporal adapter / recurrence expectation / temporal occupancy;
- Ledger Target Intelligence and obligation relevance;
- Reality relationship substrate;
- entity topology;
- place context and organization topology/unit bridge/shared operating roots;
- paired operating presence/geography and contact-set geography dispatch;
- geographic substrate / Census TIGER loading / convergence / privilege hardening;
- spatial operating kernel and adapters;
- Principal Clock spatial product cutover;
- governed spatial Implementation intake and public API.

The corresponding migrations are present in live production. 

**Disposition:** `production_live_source_not_main`. This line must be brought back under canonical source custody before `noel-core-db/main` can be treated as a production-reconstructable repository.

## 4. October 1–2 household / consequence / realization line

Terminal verified tip:

- branch: `architecture/institutional-communication-realization-provider-v1`
- SHA: `8dc3637d60550f1330327bc3227d6ef79aa741a9`

Verified ancestry contains:

- Household Rhythm shadow state self API;
- Household Rhythm shadow observation custody;
- governed consequence authority;
- governed realization authority;
- Institutional Communication realization-provider read;
- realization-provider read hardening.

These migrations are live in production.

**Disposition:** `production_live_source_not_main`.

## 5. Delegated-agent execution kernel

Branch source exists at:

- `feat/atlas-delegated-agent-command-gateway-v1`

It is ahead of September 24 `main` and contains command-gateway/refinement/decision-control migrations. Live production later contains a substantially expanded delegated-agent sequence: kernel, execution ranking/events, command custody, credentials, begin/confirm lifecycle, reads, carrier/allowlist/target controls, authority recheck, self API, permissions/catalog, target contract, and Principal decision queue.

**Disposition:** `production_live_needs_source_lineage_reconciliation`.

Do not assume the early branch is sufficient source custody for the full live delegated-agent kernel.

## 6. Public commitment / booking / Foundry state

A surviving source branch exists for the public commitment membrane:

- `feat/atlas-public-commitment-membrane-v1`
- migration `20260927230200_atlas_public_commitment_membrane_v1.sql`

The live production ledger also shows later booking selection/agreement/payment/public-commitment/Foundry-store migrations.

Literal branch-name search did not identify a branch named `foundry`, and a corresponding canonical source line has not yet been proven.

**Disposition:** `production_live_unresolved_source_mapping` for Foundry/late booking commitment work.

No branch deletion is allowed until migration-to-commit provenance is established.

## 7. Finance / accounting / evidence line — branch-only custody

Terminal verified branch:

- `work/atlas-financial-obligation-settlement-v1`
- SHA: `20257b660543649fb97a6f8ed7fb87f93fddcbf2`

This line contains or descends from accounting-ledger work and includes Financial Obligation Settlement plus Financial Evidence Resolution and related source/review/funding/accounting structures.

The September 26–27 finance migrations from this line were not observed in the inspected live migration history.

**Disposition:** `branch_only_preserve_replay_review`. Do not infer rejection from non-deployment.

## 8. Implementation Reality / Reality Sentence / promotion source forest

The repository contains many post-main branches for:

- Implementation Reality candidate custody;
- identity resolution;
- initial scope admission;
- Institutional Person promotion;
- semantic payload v2;
- Organization Unit / Position / Responsibility promotions and commands;
- promotion previews;
- observation gates;
- Reality transition receipts/continuation/reconciliation;
- later governed subject observation/applicability and Reality Sentence history work.

Many early portions are live in production; later branch-only portions require current-contract reconciliation.

Examples that must remain preserved include:

- `architecture/atlas-implementation-reality-organization-unit-command-v1-current`
- generated/dated promotion branches;
- `architecture/reality-sentence-governed-history-v1`
- governed subject observation/applicability work.

**Disposition:** `mixed_live_and_branch_only_current_contract_reconciliation`.

This is the database-side dependency for the next Atlas Implementation Reality / Reality Sentence replay train.

## 9. Production / Work actuals and other branch-only architecture

Known outage-era source branches include additional work that was intentionally held from release at the time, including:

- Production Bed Preparation source actual;
- Reality-first Work derivation / allocation history;
- governed subject observation and responsibility-resource applicability;
- other architectural candidates whose release status must be determined from live migration history rather than branch age.

**Disposition:** `preserve_until_migration_reconciled`.

## 10. Institutional email custody is older and divergent

Relevant branches include:

- `recovery/institutional-email-runtime-v1` — SHA `6dbbcbcc66c4fac56d3f15bb6a094a5212e0b616`;
- `work/institutional-email-relay-v1`;
- `work/institutional-email-outbound-v1`.

The recovery branch does **not** contain every unique commit from the relay/outbound branches; comparisons show each old work line retains unique history relative to the recovery branch.

Later Institutional Communication work also exists on the post-Sept-24 Reality Ledger trunk.

**Disposition:** `preserve_three_way_semantic_reconciliation`. Do not delete the older outbound/relay branches merely because the recovery branch exists.

## 11. Transcript Core / speech / performance migrations

Live production contains an isolated Transcript Core base/API/grants/type-fix sequence and later speech/performance recording work. Meanwhile the standalone `optical-lift/transcript-core` repository has implementation branches not merged into its own `main`.

**Disposition:** `cross_repository_source_custody_required`.

The live Noel migrations, standalone Transcript Core terminal branches, Atlas Transcript Workbench, and Newsroom transcript implementation must be reconciled together before selecting a canonical ownership boundary.

## 12. Newsroom migrations

Live production includes October 1–2 Newsroom transcript and newsroom/evidence/reporting migrations. The `optical-lift/newsroom` repository has current `main` plus a divergent `build/transcripts-current-newsroom` commit.

**Disposition:** `semantic_reconciliation_required`.

A migration being live does not prove the exact Git branch is canonical; a divergent branch does not prove its behavior is missing from current Newsroom.

## 13. Required source-custody states

Every post-Sept-24 migration/work family must end in exactly one of these states:

- `main_contains_source_and_matches_live`
- `production_live_source_custody_to_restore`
- `branch_only_preserve_for_replay`
- `superseded_but_preserved_with_successor`
- `historical_do_not_revive`
- `explicitly_rejected_with_reason`
- `unresolved_never_delete`

## 14. Hard preservation fence

Until this database audit is closed:

- do not delete any post-Sept-24 branch;
- do not squash the 805-branch forest by assumption;
- do not treat `main` as sufficient to rebuild production;
- do not rerun or release migrations merely to make Git resemble production;
- do not reverse-engineer live schema into source without preserving original migration provenance;
- do not merge the largest cumulative branch wholesale as a shortcut;
- do not erase branch-only experiments that may still contain current architectural work.

## 15. Next reconciliation steps

1. Map every live migration after `d3b528b...` to a repository commit/branch or mark it `source_unresolved`.
2. Collapse cumulative ancestry into terminal custody tips.
3. Preserve divergent side tips separately.
4. Resolve Foundry / late booking-commitment migration provenance.
5. Reconcile delegated-agent live source with the early command-gateway branch.
6. Reconcile Implementation Reality / promotion / governed-history branches against the live contract.
7. Reconcile Transcript Core / Atlas / Newsroom ownership.
8. Only after this ledger is closed should canonical-source restoration to `noel-core-db/main` be proposed.

No production mutation is authorized by this document.