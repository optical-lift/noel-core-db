# Atlas Production / Source Reconciliation — 2026-09-28

**Status:** documentation-only continuity checkpoint  
**Branch:** `docs/atlas-production-source-reconciliation-2026-09-28`  
**Base:** stale repository `main` at `d3b528b56d7630abf9d6fc67ee92c4475b8fa4ab`  
**Important:** this branch must not be interpreted as a migration release branch.

## Why this exists

Production advanced substantially during September 25–28 while `noel-core-db/main` remained at a September 24 checkpoint.

A read-only production audit on 2026-09-28 found **90 migration-history entries** with versions between:

- first: `20260925000557`
- latest: `20260928004006`

Therefore:

```text
main migration files
!= complete record of currently applied production schema history
```

until a deliberate source reconciliation is completed.

Do **not** replay or re-apply a production migration merely because it is absent from `main`.

## Current production families observed

The 90 migration-history entries include these major Atlas families.

### Smart Contacts / Shared Intelligence — September 25

Production includes the Smart Contacts person-candidate, selection-packet, saved-search, watch, and cleanup train through:

`20260925005250_remove_feast_guild_smart_contact_saved_searches_v1`

Recovered source branch:

`architecture/atlas-smart-contacts-v1`

### Reality / Ledger constitutional core — September 25

Production includes:

- `20260925014915_atlas_reality_ledger_core_v1`
- `20260925015101_atlas_reality_ledger_core_hardening_v1`
- Lex + Elm legacy migration/cutover/edge retirement
- authenticated access cutover
- Reality responsibility authority
- Personal Atlas self-capacity and portfolio-office cutovers
- correspondence / institutional communication cutovers
- Company Work receiver/collaboration uptake
- external Entity bridge

Recovered source/architecture branch:

`architecture/reality-ledger-core-v1`

### Scheduling / booking / recurrence — September 25–26

Production includes:

- universal booking resource calendar;
- booking calendar access/write membrane;
- universal Ledger occurrence calendar binding;
- Elm venue resource reconciliation;
- atomic booking resource commit;
- availability booking policy;
- universal Ledger recurrence;
- schedule responsibility capabilities;
- booking request approval;
- offering requirements routing;
- universal temporal adapter protocol;
- recurrence expectation lifecycle;
- temporal enrichment occupancy.

Recovered source branch families include:

- `architecture/reality-ledger-scheduling-custody-v1`
- `architecture/reality-ledger-booking-request-approval-v1`
- `architecture/reality-ledger-booking-offering-requirements-routing-v1`
- `architecture/reality-ledger-temporal-enrichment-occupancy-v1`

### Booking selection / agreement / public commitment — September 27

Production includes:

- `20260927212442_add_booking_request_selection_capture_v1`
- `20260927212858_add_booking_agreement_commitment_gate_v1`
- Foundry store v0.1
- booking payment schedule/confirmation gate
- governed venue payment rule/calculator
- public commitment membrane schema / identity / booking selection
- Elm public venue commitment surface
- public commitment booking materialization
- gateway service-role execution support.

Recovered source branches include public-commitment and booking branches in `noel-core-db` plus paired Atlas application branches.

### Delegated Agent Command Gateway — September 28

Production includes the command-kernel migration train:

- `20260928002435_atlas_delegated_agent_command_kernel_v1`
- `20260928002742_atlas_execution_class_rank_v1`
- `20260928002750_atlas_agent_command_event_immutability_v1`
- `20260928002836_atlas_evaluate_delegated_agent_command_authority_v1`
- `20260928002847_atlas_resolve_delegated_agent_credential_v1`
- `20260928002906_atlas_begin_delegated_agent_command_v1`
- `20260928002920_atlas_confirm_delegated_agent_command_v1`
- `20260928002943_atlas_agent_command_execution_lifecycle_v1`
- `20260928002952_atlas_agent_command_invocation_read_v1`
- `20260928003006_atlas_delegated_agent_carrier_credential_service_v1`
- `20260928003036_atlas_delegated_agent_explicit_allowlist_v1`
- `20260928003114_atlas_delegated_agent_target_scope_v1`
- `20260928003141_atlas_agent_command_target_recheck_v1`
- `20260928003211_atlas_delegated_agent_authorization_self_api_v1`
- `20260928003222_atlas_delegated_agent_table_permissions_v1`
- `20260928003236_atlas_delegated_agent_service_permissions_v1`
- `20260928003244_atlas_delegated_agent_self_permissions_v1`
- `20260928003333_atlas_delegated_agent_command_catalog_v1`
- `20260928003952_atlas_delegated_agent_target_contract_v1`
- `20260928004006_atlas_delegated_agent_principal_decision_queue_v1`

Recovered source branch:

`feat/atlas-delegated-agent-command-gateway-v1`

At audit time production had zero delegated-agent carriers, zero active authorizations, and zero command invocations.

## Branch-only / unreleased work that must not be assumed production-live

### Governed subject observation / applicability

Branch:

`governed-subject-observation-applicability-v1`

Head at continuity audit:

`f89051d6929bc022bdccbac6afdc92a3832a094b`

Contains:

- resource-observation source membrane;
- Responsibility→resource applicability;
- privilege tightening;
- rollback-only proofs;
- Elm Grounds fixture.

This source branch was **not** present in the production migration history during the audit.

Next step is isolated database validation, not production application.

### Implementation Workbench / Foundry Admission receiving structures

Recovered architecture and implementation exist on:

`architecture/reality-ledger-core-v1`

but production inspection during the audit found the Workbench/Foundry Admission receiving structures expected by the latest branch absent.

Do not assume the Workbench's database router is production-live merely because its architecture is validated on a branch.

### Reality appellations

Branch:

`work/reality-entity-appellations-v1`

Semantic law is adopted by current onboarding architecture:

```text
name is evidence about identity
name equality never silently merges canonical Entities
```

The SQL remains branch-only until reconciled/released.

### Reality Entity / relationship / responsibility promotion

Branch:

`work/reality-entity-relationship-promotion-v1`

Contains Workbench-oriented establishment previews/promotions.

Treat as salvageable implementation semantics, not automatically current release source.

### Reality Observation / browser source authority

Branch:

`architecture/reality-observation-source-authority-v1`

Production inspection found existing Connected Sources but not the proposed provider-connection session / source-observation preparation membranes from this branch.

Reconcile with the newer governed-subject observation architecture before release.

## Reconciliation classes

Every September 25–28 source item should be assigned exactly one current disposition:

### A. Production-applied / source-found

Migration exists in production history and an exact source branch/commit is recoverable.

Action:

Preserve both histories and later canonicalize source without replaying the migration.

### B. Production-applied / source-needs-canonicalization

Migration exists in production but source is scattered across branches or not yet in the intended permanent source line.

Action:

Recover exact SQL/commit provenance and create an additive/canonical source reconciliation path. Do not fabricate a new migration history.

### C. Branch-only / unreleased

Source exists, migration is not in production.

Action:

Validate normally before release.

### D. Superseded / historical

Older architecture or branch has been replaced by a later constitutional boundary.

Action:

Preserve for provenance; do not merge wholesale.

## Mandatory rules for reconciliation

1. Query production migration history before planning any migration release.
2. Never infer “not deployed” solely from absence on `main`.
3. Never infer “deployed” solely from branch existence.
4. Do not rewrite or delete production migration history to make repository history look cleaner.
5. Do not rerun already-applied schema mutations under new filenames merely to catch `main` up.
6. Preserve branch and commit provenance for every recovered production migration.
7. Prefer additive source reconciliation and explicit succession.
8. Validate the resulting source line against a production-schema clone before further release.
9. Keep current GitHub Actions quota constraints in mind; do not recreate automatic PR churn as part of reconciliation.
10. Record the eventual canonical source checkpoint explicitly once this repair is complete.

## Cross-repo architecture pointer

The current cross-domain Atlas architecture checkpoint lives in:

`optical-lift/atlas`

branch:

`architecture/atlas-continuity-consolidation-2026-09-28`

Start with:

- `docs/architecture/ATLAS_CURRENT_ARCHITECTURE_CHECKPOINT.md`
- `docs/architecture/ATLAS_INTEGRATED_OPERATING_ARCHITECTURE_V2.md`
- `docs/architecture/ATLAS_ONBOARDING_ARCHITECTURE_V1.md`
- `docs/architecture/ATLAS_PRINCIPAL_ATTENTION_ARBITRATION_V1.md`
- `docs/architecture/ATLAS_CONTINUITY_SOURCE_RECONCILIATION_2026-09-28.md`

That branch is based on the recovered 43-commit governed-reality checkpoint rather than stale Atlas `main`.

## Next source-repo action

Do **not** merge this documentation branch as though it repairs source history.

The next actual source-reconciliation tranche should:

```text
production migration ledger
→ exact migration-to-branch/commit mapping
→ disposition table
→ reconstructed canonical source line
→ production-schema clone validation
→ explicit review/release decision
```

Until that work is done, this file is the warning label and continuity map that prevents accidental replay or rediscovery.
