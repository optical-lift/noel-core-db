# Atlas Organization Ledger — promotion plan

## Current state

As of September 5, 2026:

- Product Map `PMD-018` has selected Organization Ledger as the primary active Organization encounter.
- `OPS-01` is deeply mapped as the Organization Ledger projection.
- Generic Organization Ledger storage/read/projection authority is live in Supabase through `20260905223627_atlas_organization_ledger_v1`.
- Production → Company Work → Ledger integration and reconciliation migrations are live.
- The real Elm Production bed assignments have materialized six open Company Work obligations without guessing a worker.
- Responsibility, manager scheduling, Worker-Day exposure, execution authorization, worker result, result acceptance, Company Work completion, Production reconciliation, and Ledger closure have been proved as separate facts through rollback-only human-path tests.
- The real six bed-preparation Work items remain unassigned and unscheduled after the proof; no worker results/acceptances were left behind.
- The nine-migration manager/worker UX proof slice is live in Supabase and mirrored on PR #371.
- No UI runtime has been pointed at unreleased authority by this branch work.
- PR #371 remains draft/open and must not be merged until final release review is complete.

## Governing placement in Atlas

Organization Ledger is institutional operating infrastructure. It does not replace the Principal Operating System or turn Organization work into the Principal Clock.

The governing separation remains:

```text
source-domain reality
→ institutional Work / Responsibility / management
→ worker execution
→ accepted institutional result
→ source-domain reconciliation
→ Organization Ledger projection
→ escalation only when Principal authority is genuinely required
```

Ordinary delegated work remains contained inside the Organization. A worker miss, Blocked result, or `needs_replan` state may require management attention without automatically becoming Principal work.

## Why promotion remains staged

The legacy farm Journal is already live and valuable, but it is not the generic Ledger contract. Atlas therefore uses Succession + Continuity rather than an in-place rename/generalization:

`legacy farm Journal continues`
+ `Organization Ledger projection lives beside it`
→ `meaningful legacy events adapted into the new projection`
→ `new source domains publish governed consequences directly`
→ `readers migrate`
→ `legacy Journal retires only when continuity is proven`.

The Ledger remains a projection/read model. It must never become the writer that manufactures Production, Work, Money, or Personal truth.

## Promotion 1 — generic projection storage + read contract — LIVE

Live authority includes:

- `atlas.organization_ledger_entries`;
- `atlas.organization_ledger_subjects`;
- monotonic projection revision/cursor behavior;
- internal projection admission;
- typed subject links;
- conservative Organization-owner read API;
- RLS + revoked direct client mutation path.

Current persisted audit after the human-path proof shows six Ledger entries and thirty subject links. Those persisted rows describe the real open Production/Company Work state; rollback-only worker completion tests did not leave closure rows behind.

Still prohibited:

- making Ledger a generic canonical semantic-event writer;
- direct authenticated client mutation;
- inferring universal manager authority from UI labels;
- suppressing unresolved state;
- leaking private Person/Household facts into Organization chronology.

## Promotion 2 — legacy Journal adapter — NEXT CONTINUITY WORK

Add or finish an internal idempotent adapter that can project qualifying `journal_event_index` rows into Organization Ledger without changing Journal ownership.

Rules:

- preserve source event identity/provenance/correlation;
- preserve `occurred_at`;
- use `source_domain='legacy_journal'` unless a more precise mapping is actually warranted;
- translate visibility through explicit Organization authorization rather than copying farm-era labels as universal roles;
- do not infer purpose/designation from title text;
- use unresolved state when legacy evidence is insufficient;
- exact replay must not duplicate Ledger history.

Backfill should be incremental and compared with the legacy Journal before reader migration.

## Promotion 3 — Production direct Company Work — LIVE / PROVED

The promoted source path is:

```text
production_bed_assignment
→ source-owned requirement
→ Company Work
→ source-owned time contract
```

Production does not resolve `worker_key='anna'` or any familiar person. If no separate Responsibility authority has acted, Work stays open/unassigned.

The source-derived Work stable key does not change when assignee, planned day, exposure day, or compatibility execution carrier changes.

Six real Elm `production_bed_preparation_v1` Work items currently demonstrate that persisted boundary.

## Promotion 4 — first Ledger consequence adapters — LIVE FOR THIS SLICE

The Production/Company Work seam now projects meaningful institutional consequences while preserving source authority.

The required chronology for this slice is:

- Production requirement/source relationship established;
- Company Work established;
- Responsibility established separately when management acts;
- manager plan established separately;
- worker result reported;
- result accepted under the Work contract;
- Company Work completion established;
- Production reconciled;
- Ledger projects the resulting institutional state.

Every projection must preserve durable event identity, source domain/type, occurrence time, subjects, truth/designation state, and provenance/correlation.

## Promotion 5 — Worker result closure — PROVED

The governing lifecycle is now:

```text
Production reality
→ Company Work
→ Responsibility
→ manager plan
→ Worker-Day exposure
→ execution authority
→ worker result
→ result acceptance
→ Company Work completion
→ Production reconciliation
→ Organization Ledger closure
```

The proof establishes these invariants:

- Work remains true independently of worker assignment or planned day.
- Responsibility does not imply schedule.
- Schedule does not imply worker exposure.
- Worker-Day placement does not imply execution authority.
- Future Organization and farm execution eligibility are checked for the service date.
- Future-week management planning is not exposed wholesale to the worker.
- Unfinished Work can roll forward while preserving the original planned date.
- Valid prerequisite operations may exist in parallel with unresolved downstream Production readiness.
- Done is a worker report, not automatically truth.
- `production_bed_preparation_v1` permits one-tap worker attestation without a second popup.
- Structured-result Work cannot bypass required evidence with ordinary Done.
- Blocked leaves Work open and creates a management exception.
- Governed Company Work cannot be marked completed without accepted result evidence.
- Manager-scheduled Company Work completion is isolated from the unrelated legacy farm-wide release sweep.

### Live migration history for this UX proof

1. `20260906002837_atlas_company_work_planning_v1.sql`
2. `20260906003115_atlas_company_work_worker_day_bridge_v1.sql`
3. `20260906003432_atlas_company_work_execution_eligibility_fix_v1.sql`
4. `20260906003549_atlas_company_work_result_acceptance_v1.sql`
5. `20260906003713_atlas_company_work_execution_membership_uuid_fix_v1.sql`
6. `20260906003814_atlas_company_work_clock_provenance_bridge_v1.sql`
7. `20260906004144_atlas_company_work_operation_warrant_bridge_v1.sql`
8. `20260906004231_atlas_company_work_terminal_release_isolation_v1.sql`
9. `20260906004430_atlas_company_work_planning_queue_ambiguity_fix_v1.sql`

Preserve this history. The fix migrations document real failures discovered by the proof and should not be rewritten into a fictional perfect first attempt.

## Promotion 6 — management + Worker Day product wiring — NEXT UX WORK

The next UI/runtime step is to consume the proved contracts rather than invent another task model.

Management needs to be able to:

- see unassigned Company Work;
- establish Responsibility;
- plan a week without exposing the whole future week to the worker;
- distinguish original planned date from effective exposure date;
- see `needs_replan` when future eligibility or other plan validity changes;
- see Blocked/unable results as management exceptions;
- inspect required result contracts before assuming Done is sufficient.

Worker Day needs to:

- expose only the current service-day placement;
- keep its familiar quiet Done interaction where the result contract permits worker attestation;
- capture structured evidence only where the contract requires it;
- obtain current execution authority rather than treating placement as permission;
- return Blocked without falsely closing Work.

Do not expose management's entire planning surface in a personal Worker Day. If the worker later has Personal Atlas, Organization-owned Work may project into that person's Atlas while remaining institution-owned and governed by the Organization contract.

## Promotion 7 — Harvest / Commerce adapters

Existing Flower Commerce can be projected before broad generalization because its source-domain lifecycle is already explicit.

Attach meaningful Ledger movements for:

- Harvest result;
- Ready inventory establishment/change;
- Demand created/committed/cancelled;
- allocation/release/coverage consequence;
- Sale established/cancelled;
- fulfillment custody/result;
- buyer-history consequence where governed.

Availability remains derived:

`Ready supply − active allocation/custody − other unavailability`.

Do not write availability as independent canonical truth merely to populate Ledger/UI.

## Promotion 8 — fulfillment Work convergence

Where Flower fulfillment still depends on a legacy Task, converge it onto the same Company Work grammar:

```text
Sale / fulfillment requirement
→ Company Work
→ Responsibility
→ manager/execution plan where needed
→ optional legacy execution adapter
→ worker/custody result
→ source reconciliation
```

A runner/buyer-facing worker is a legitimate Responsibility target only through governed institutional identity, not because Commerce knows a hard-coded person key.

## Promotion 9 — Stripe/provider evidence

Map provider evidence first:

```text
Stripe provider event
→ Connected Source / Provider Operation
→ Source Observation
→ Evidence
→ Organization Ledger line with truth_status='observed'
→ designation unresolved until matched
```

The Ledger may state that Stripe reported a receipt. It may not manufacture canonical `Sale paid` state merely from provider evidence.

## Promotion 10 — common Money Collection authority

Before provider evidence can close economic state, release the reusable Money contract for:

- source-owned obligation basis;
- provider/manual payment observations;
- receipt-to-obligation matching;
- partial payments;
- reversals/refunds/chargebacks;
- multi-obligation ambiguity/conflict;
- derived paid/open balance;
- provenance and reconciliation history.

Only Money authority establishes the canonical economic consequence consumed by Ledger.

## Promotion 11 — persistent Organization runtime + OPS-01

After product wiring is pointed only at released backend authority:

- load Organization orientation once;
- load the current Ledger window with revision/cursor;
- maintain it incrementally;
- open source-domain detail without reconstructing the institution;
- keep private Person/Household data out of institutional projection;
- expose People, Production, Inventory, Sales, Money, Integrations, and similar lenses over one governed institution rather than disconnected apps.

## Release gates

Do not merge/release this tranche if any are true:

- repository migration history does not match live Supabase history;
- security/performance advisor review is incomplete or unexplained;
- direct clients can mutate Ledger or result evidence outside intended authority;
- replay duplicates events;
- unresolved states are suppressed;
- Organization chronology can leak private Personal Atlas facts;
- Production can still create this Work by finding Anna directly;
- Responsibility and schedule are collapsed into one fact;
- rollover rewrites original planning history;
- Worker-Day placement alone can grant execution permission;
- worker Done can manufacture governed completion without accepted evidence;
- structured-result Work can bypass its result contract;
- Blocked falsely closes Work or Production;
- legacy terminal-task release can collide with manager-scheduled Company Work;
- Stripe observation can manufacture `paid` state;
- the reference-company pressure test requires farm-only fields.

## Immediate next executable step

The previous “prove Worker Day + result return” gate is complete.

Before PR #371 may leave draft status:

1. complete the final live-state audit;
2. review Supabase security and performance advisors and distinguish pre-existing project findings from tranche-introduced findings;
3. verify repository migration parity against live `supabase_migrations.schema_migrations`;
4. update the PR description with the actual rollback proof and persisted-state boundary;
5. leave the PR unmerged until that release review is explicit.
