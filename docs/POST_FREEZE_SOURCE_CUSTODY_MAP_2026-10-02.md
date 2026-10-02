# Noel Core Post-Freeze Source Custody Map — 2026-10-02

**Status:** read-only recovery accounting; no migration, merge, or release authorization  
**Frozen repository main:** `d3b528b56d7630abf9d6fc67ee92c4475b8fa4ab`  
**Live project:** `noel-core` (`zirqkouammpwxlqfbsvf`)

## Accounting correction

The earlier conservative preservation denominator counted **170** live migration records dated September 24 through October 2. Comparing against the actual frozen-main state shows that **162 migrations are truly post-freeze** and require post-main source-custody accounting. The other eight September 24 migrations were already represented by the final canonical `main` checkpoint.

The 162 post-freeze migrations collapse into ten coherent families:

| Family | Count | Live range | Current source-custody state |
|---|---:|---|---|
| Shared Intelligence / Smart Contacts | 19 | `20260924230219`–`20260925005250` | **source located and pinned** |
| Reality Ledger / Correspondence / Company Work | 20 | `20260925014915`–`20260925195307` | **source located on spatial trunk** |
| Booking / Temporal | 24 | `20260925215931`–`20260926182344` | **source located on spatial trunk** |
| Booking Commitment / Foundry / Public Gateway | 14 | `20260927212442`–`20260927231727` | **mixed; partially unresolved** |
| Delegated Agent Kernel | 20 | `20260928002435`–`20260928004006` | **consolidated source branch located; semantic equivalence still required** |
| Transcript / Speech / Performance | 9 | `20260928200320`–`20260928224413` | **cross-repository source reconciliation required** |
| Target Intelligence / Relationship / Topology / Geography / Spatial | 39 | `20260930180434`–`20261001001646` | **source located on spatial trunk** |
| Household Rhythm Shadow | 2 | `20261001172830`–`20261001183521` | **source located and pinned** |
| Newsroom Transcript / Reporting | 11 | `20261001210053`–`20261002161934` | **Newsroom cross-repository reconciliation required** |
| Governed Consequence / Realization / Provider | 4 | `20261002181837`–`20261002195337` | **source located and pinned** |

Total: **162**.

## 1. Shared Intelligence / Smart Contacts — source solved

Source branch:

- `architecture/atlas-smart-contacts-v1`
- tip `9cee0d821772b30e836fbb1e78d7ca946b70d2c5`
- preservation ref `checkpoint/outage-smart-contacts-db-2026-09-25`

Direct comparison against frozen `main` proves this two-commit branch contains all 19 live migrations in the family, beginning with:

- `20260924230219_shared_intelligence_outreach_custody_foundation_v1.sql`

and ending with:

- `20260925005250_remove_feast_guild_smart_contact_saved_searches_v1.sql`

It also preserves architecture and validation material.

**Disposition:** `production_live_source_located_separate_fork`.

This branch is not an ancestor of the later spatial trunk; it must be composed into canonical source separately.

## 2. Reality Ledger / Correspondence / Company Work + Booking / Temporal + Target/Topology/Geography/Spatial — source solved as one cumulative trunk

Terminal source branch:

- `architecture/spatial-intake-v1`
- tip `0bc768cac28f902f2a2d5794507d6c4ea2c5c212`
- preservation ref `checkpoint/outage-spatial-intake-2026-10-01`

This trunk contains the live source for:

- Reality Ledger core and Elm cutover;
- authenticated Reality access;
- Reality responsibility authority;
- Personal Atlas capacity / portfolio-office cutovers;
- Correspondence identity and Institutional Communication context/safe operations/response work;
- Company Work receiver/collaboration uptake;
- external entity bridge;
- universal booking/calendar/availability/recurrence/request/approval/offering routing;
- temporal adapter / recurrence expectation lifecycle;
- Ledger Target Intelligence;
- Reality relationship substrate;
- entity and organization topology;
- place context and organization-unit bridge;
- paired operating presence / geography;
- geographic substrate;
- spatial operating kernel;
- governed spatial Implementation intake and public API.

**Disposition:** `production_live_source_located_cumulative_trunk`.

Important: this trunk does **not** contain the separate Smart Contacts, Public Commitment, or Delegated Agent forks.

## 3. Booking Commitment / Foundry / Public Gateway — mixed source custody

The 14 live migrations are:

1. `20260927212442 add_booking_request_selection_capture_v1`
2. `20260927212858 add_booking_agreement_commitment_gate_v1`
3. `20260927213513 create_foundry_store_v0_1`
4. `20260927213719 booking_payment_schedule_and_confirmation_gate_v1`
5. `20260927214203 govern_private_venue_payment_rule_v1`
6. `20260927214247 venue_payment_rule_calculator_v1`
7. `20260927214304 restrict_direct_booking_payment_schedule_writes_v1`
8. `20260927214324 validate_commitment_booking_policy_config_v1`
9. `20260927220258 public_commitment_membrane_schema_v1`
10. `20260927220341 public_commitment_membrane_identity_surface_v1`
11. `20260927220440 public_commitment_booking_selection_v1`
12. `20260927220502 elm_public_venue_commitment_surface_v1`
13. `20260927220539 public_commitment_booking_materialization_v1`
14. `20260927231727 atlas_public_commitment_gateway_service_role_execute_v1`

A preserved consolidated source branch exists for the Public Commitment membrane:

- `feat/atlas-public-commitment-membrane-v1`
- tip `c98ea7e4a40adab7ca1f5bb269b31ba48aeb2acb`
- preservation ref `checkpoint/outage-public-commitment-db-2026-09-27`
- source file `20260927230200_atlas_public_commitment_membrane_v1.sql`

That branch is one commit directly off frozen `main`. It is **not** the source of the earlier live Foundry store, booking-selection, payment-schedule, or private venue payment-rule migrations.

Literal branch and commit-name searches have not yet located canonical Git source for those earlier live migrations.

**Disposition:** `production_live_partial_source_custody_unresolved`.

The Foundry / booking commitment lineage remains `unresolved_never_delete` until original source provenance is recovered or a faithful source reconstruction is written with explicit provenance.

## 4. Delegated Agent Kernel — consolidated source located, equivalence not yet proven

Preserved source branch:

- `feat/atlas-delegated-agent-command-gateway-v1`
- tip `09889fefc5a2f7cc76ae0046ee6c9245f2a509b1`
- preservation ref `checkpoint/outage-delegated-agent-db-2026-09-28`

The branch is four commits ahead of frozen `main` and preserves:

- delegated-agent command gateway;
- gateway refinement;
- decision controls;
- architecture documentation.

Production contains a 20-migration delegated-agent sequence. The source branch uses larger consolidated migrations with different version identifiers.

**Disposition:** `production_live_consolidated_source_needs_semantic_equivalence_receipt`.

Do not treat filename mismatch as source loss, but do not declare source custody restored until the consolidated migrations are compared semantically with the live 20-step schema/function state.

## 5. Transcript / Speech / Performance — cross-repository custody

No Noel branch named for the speech/performance live sequence was found. Live production contains nine migrations in this family, while implementation work also exists in:

- `optical-lift/transcript-core` terminal branches;
- Atlas Transcript Workbench / evidence-binding branches;
- later Newsroom transcript work.

**Disposition:** `cross_repository_source_reconciliation_required`.

The live Noel migrations must be mapped to the owning source repository or reconstructed into a clearly owned canonical source history without erasing their production provenance.

## 6. Household Rhythm + Governed Consequence / Realization / Provider — source solved as separate fork

Terminal branch:

- `architecture/institutional-communication-realization-provider-v1`
- tip `8dc3637d60550f1330327bc3227d6ef79aa741a9`
- preservation ref `checkpoint/outage-realization-provider-2026-10-02`

It contains exactly the six relevant production migrations:

- Household Rhythm shadow state self API;
- Household Rhythm shadow observation custody;
- governed consequence authority;
- governed realization authority;
- Institutional Communication realization-provider read;
- realization-provider read hardening.

This branch diverges directly from frozen `main`; it is **not** a descendant of the 75-commit spatial trunk.

**Disposition:** `production_live_source_located_separate_fork`.

## 7. Newsroom Transcript / Reporting — cross-repository reconciliation

Live production contains eleven Newsroom/transcript/reporting migrations from October 1–2. The `optical-lift/newsroom` repository has a current `main` plus a divergent `build/transcripts-current-newsroom` commit that retains unique transcript implementation history.

**Disposition:** `cross_repository_semantic_reconciliation_required`.

A live migration does not by itself prove current Newsroom source contains the exact production behavior, and branch divergence does not prove it is missing. Compare behavior and schema before assigning canonical ownership.

## 8. Branch-only work remains outside this 162-migration production map

The source-custody restoration must not become a production-only recovery. Confirmed branch-only work still requiring later replay/review includes:

- Financial Obligation Settlement / Financial Evidence Resolution;
- Reality-first Work derivation;
- Production Bed Preparation source actual and evidence guard;
- governed-subject observation/applicability;
- Reality Sentence governed history;
- other preserved promotion / Implementation Reality branches.

These are real work products even though they are not in the 162 live migrations.

## 9. Restoration rule

Canonical DB source restoration must be built by **semantic composition**, not wholesale branch merge.

Each family clears custody only when one of the following is recorded:

- canonical `main` successor commit contains source equivalent to live production;
- consolidated source is proven semantically equivalent to live production;
- cross-repository ownership is explicitly assigned and reproducible;
- branch-only work receives a current-contract successor;
- work is deliberately retained as historical/do-not-revive with a reason.

No production mutation is authorized by this map.