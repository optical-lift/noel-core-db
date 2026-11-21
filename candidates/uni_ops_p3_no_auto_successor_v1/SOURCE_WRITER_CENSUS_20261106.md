# P3 / U2C bounded current-source writer census — November 6, 2026

**Basis:** read-only `pg_proc.prosrc`, `pg_get_functiondef`, `pg_trigger`, `pg_attribute` queries against the live Noel database. **No DML, user/task row reads or migrations.** Detailed repeatable read-only SQL: `08_readonly_writer_and_trigger_census.sql`. This is a **source-code text census**, not a claim to have enumerated every dynamic SQL writer, third-party service, imported branch, external REST operation, or every indirect call-graph path.

## 15 distinct live direct `atlas.work_items` INSERT source functions

1. `claim_institutional_conversation_self_api_v1`
2. `connected_ledger_direct_assign_self_api_v1`
3. `connected_ledger_respond_self_api_v1`
4. `create_communication_derived_work_self_api_v1`
5. `create_ledger_occurrence_shared_work_self_api_v1`
6. `decide_company_work_legacy_backlog_owner_self_api_v1`
7. `ensure_outbound_conversation_responsibility_service_v1`
8. `ensure_weekly_harvest_company_work_v1`
9. `establish_household_laundry_original_work_self_api_v1`
10. `materialize_production_bed_preparation_company_work_v1`
11. `owner_create_native_ledger_today_work_self_api_v1`
12. `promote_personal_dated_task_to_company_work_self_api_v1`
13. `split_original_canonical_work_owner_self_api_v1`
14. `submit_ledger_work_self_api_v1`
15. `sync_explicit_worker_task_company_work_v2`

The census also saw **26 source functions with direct `UPDATE atlas.work_items`** (41 total direct insert/update or searched callers). These are not all new-work issuers; they include original Work Result, accepted Person, old-task synchronization and change/edit. No live original R01 continuing farm writer is installed. The proposed U2C writer remains on held branches. A blanket work-items trigger demanding U2 acceptance for every row would violate existing Household/Event/Company sources; use **source-specific** scope.

**New held `04`**: applies only to an original Organization `rhythm_state` covered by actual U1A exact canonical Subject or U1B native farm Rulebook decision history. Verifies exact native Need, R01 source/Result/stable key, signed actor, true U2A accepted offer, current root and the single U2C arbiter through the pre-existing source guard. Holds attempts to create governed Work through a different writer without independent worker acceptance. **Existing ungoverned historical Work writers are untouched; not an all-tables writer shutdown.**

**New held `06`**: a DEFERRABLE INITIALLY DEFERRED constraint trigger for governed canonical original INSERT. At transaction end verifies exact offer was fulfilled *to that one Work ID*, original Need/Subject and current Rulebook versions remain consistent, current accepted Person responsibility in `work_allocations`, real active `company_work_native_ledger_relevance`, and same-day `work_execution_plans`. If not, the INSERT transaction rolls back. It does not issue, complete or assign Work; original U2B remains the only protected signer/finalizer. This does not authorize a scheduler.

## Other confirmed existing legacy successor paths

Live legacy `atlas.tasks` has many status, queue, checklist and dependency triggers. Selected source-backed Done terminal successor effects:

| Live source | Exact old MD5 | Current old effect | Held 6A source treatment |
|---|---|---|---|
| `advance_anna_weeding_serial_queue_v1` | `3e19f0db48bb781ee09c28b120e39bf9` | applies Anna queue release after predecessor Done | Preserve requirement boundary, omit effect; mark independent issuance |
| `advance_gentle_pressure_wash_serial_queue_v1` | `a1e91245470dc25a831f4cdd36f37ae6` | completes queue item and automatically releases next pressure wash | Preserve actual completion, set `completion_gate_advanced=false` and independent issuance required |
| `advance_owner_completion_gated_queue_v1` | `2d4c93888e82f00f3a1af150827d1bcc` | completion-boundary release of owner queues | Preserve boundary, omit effect |
| `advance_pot_up_serial_queue_v1` | `b9e2f2f8c3fb494d5cea9325b182eefc` | completion-boundary release of pot-up serial Work | Preserve boundary, omit effect |
| `release_after_task_terminal_v1` | `4223cee690c2fde4f033c45dbca74815` | after terminal task, runs farm-wide `release_eligible_work_v1` | Keep old task terminal/occurrence closure; remove unsolicited release sweep |
| `activate_deferred_rhythm_bindings_after_task_v1` | `75bf26dccb2153bfa3be050428d56c71` | activates rhymic prerequisites, calls evaluator with `activation_prerequisite_completed` | P3 source `01` preserves activation/qualified evaluation, skips legacy Work issuance |
| `advance_task_dependency_clocks_v1` | `eedb5dee063b8fab613d22564b5f4326` | separate delayed clock triggers legacy release | Held `07` preserves ready clock and pending count, omits auto release |
| `apply_workflow_event_v1` | `883c522e765bb3039511f172ccb1f69a` | prerequisite event marks occurrence eligible, releases Work, also reschedules existing legacy target | Held `07` preserves source prerequisite satisfaction while withholding both automatic Work release and unapproved rescheduling |

All SQL patches in `05` and `07` are **uncompiled, untested source snapshots**, and original stored Work/task/event evidence is never rewritten by this candidate. These legacy effects are **not** evidence of approved canonical Rulebook/Need→Work; older open queue entries require separate review, not unconsented automatic movement.

## Limits and stop conditions

- Eighteen live functions directly reference `release_eligible_work_v1`, queue release effects or `signal_work_occurrence_v1`; the eight named paths above are only one traced subset. E.g. `ensure_flower_preparation_task_v1`, `sync_seed_inventory_dependency_tasks_v1`, `release_next_task_in_queue_v1`, `release_goal_task_v1`, `release_all_farms_v1`, and independent task release APIs require **separate admission classification**, not automatic removal. Names and actions alone are insufficient to infer an issuer is a Result side effect. A current independent authorized issuer may later evaluate future eligibility—but **only** through source-authorized policy, carrier, worker choice and capacity.
- Legacy task lifecycle can record its own Done independently of the new canonical Result acceptance. Its closure is historical evidence, not a blanket canonical care Actual, and P2 honest retrospective recognition is not implemented.
- Existing U1A and U1B immutable policy histories may conflict. Arbiter holds both until their owner source resolves the conflict; no fallback to a legacy auto task.
- Source file `01` now covers **five** actual Result/Done-triggered evaluator paths: `workflow_precheck`, `workflow_result`, `game_master_precheck`, `game_master_satisfaction`, and `activation_prerequisite_completed`. Non-Result clock source is separately handled by `03` only for source-governed originals.
- No type/permission changes and no private information emitted. A release must prove genuine U2C first-original issuance, U2B atomic finalization, nil next Work/Clock, RLS and non-governed Event/Household/Company regressions.

**Verdict:** important source bypasses are now **authored as held candidates**, NOT compiled/signed tested, not installed, and not a complete proof of every emitter. Next bounded stage is inventory and adjudicate remaining independent old release callers and the correct canonical P2 retrospective witness/ratification path; then the collected current-source PG17/GoTrue/RiverSong and real actor suite at the integration/release boundary.
