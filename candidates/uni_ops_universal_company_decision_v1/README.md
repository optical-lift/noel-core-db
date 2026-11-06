# UNI-OPS-01 — source/authority-neutral Company Decision kernel, held

**2026-11-06.** This is a **NEW, separate, uncompiled, source-only DRAFT** in Noel, deliberately **not a refactor or merge** of the farm-led P3 #2565 or historical testimony P2 #2566. Its purpose is to keep the universal mechanism independent of the Elm Farm pilot while preserving every farm source, worker acceptance and Result distinction. It DOES NOT implement universal original Work issuance or claim existing companies can use the new tables today.

## Universal mechanism — the same across any Company

```text
First-party domain evidence (reality; no manufactured state)
  -> source-owned adapter: exact source + Subject/jurisdiction/disclosure
  -> escalation eligibility (operator fact? manager review? principal floor?)
  -> immutable source case (Organization, governing Ledger, source revision)
  -> separate signed governing Person decision, with true current authority
     [request admission | request principal arbitration | hold | decline]
  -> independently governed canonical Requirement/Need/Rulebook
  -> separately offered and genuinely accepted recipient
  -> exactly one original Work under the existing issuer
  -> truthful physical/organizational Result + qualified Done
  -> next Work NEVER follows automatically from Result/Done
```

The kernel's **company-scoped common interface** is `organization_id`, `governing_ledger_id`, `source_domain`, `source_kind`, `source_key`, `source_revision_key`, source observation and registration times, source adapter, an exact attestation digest, plus append-only governing decision. There is **no farm_id, Harvest, seed, Rhythm, Task, worker allocation, Clock or crop-specific authority in the kernel**.

The **governing Company Ledger** is a real Noel existing jurisdiction/Company model; its governing Person is a real signed principal, never inferred from `service_role`, technical credentials, a job title or a farm/worker seat. For this first private root-only source pilot, the function rechecks `atlas.company_work_native_ledger_owner_self_v1` and active `atlas.ledger_organization_participations` on each decision. A manager with a genuinely bounded signed mandate is future separate source/issuer work, **not implicit root equivalence**. Household & Family require their own protected source; never invent a Company Ledger to make this schema universal there.

## Authored held source

1. **01 `01_domain_neutral_source_and_decision_records_held.sql`**: two append-only RLS/FORCE-RLS private tables and a no-rewrite trigger. One stable source revision per exact Company Ledger/source locator. No raw Subject names, arbitrary worker metadata or private narrative in the case. `source_admission_state='held_pending_source_admission'` by default; `source_verified_by_adapter` may only be asserted by a separately audited real domain source adapter, **not by any generic public writer**. There is NO admission API/grant in this source. Decision history has signed Person and user, previous event referential integrity within the same case, exact action ID, reason, and false-checked flags for auto Work, consent, Actual and Clock.
2. **02 `02_private_company_governor_decision_writer_held.sql`**: one current signed governing Company Ledger root records a bounded case decision after actual source adapter admission, latest source revision comparison, same-case latest-decision compare-and-set, exact replay. Four outcomes: `request_independent_work_admission`, `request_principal_arbitration`, `hold_for_more_source`, `decline_new_action_at_present`. All explicitly have **zero** Work/Clock/assignment/Result effect. **No direct public or service_role EXECUTE**. Domain source **currentness at decision time remains adapter-owned and unproven until signed source wrappers are assembled**; this private writer is not operational permission to act merely because a status string says verified.
3. **03 `03_private_current_governor_case_receipt_held.sql`**: one exact known case to current signed governor, latest decision/source-revision facts only. It never returns Subject narrative, source locator/key, private worker data or a roster. No assumption that "owner attention" gets Principal Clock floor. No issue/offer/Work writer.
4. **`DEFERRED_ACCEPTANCE.md`** and **`deferred_postconditions.sql`**: collected future human/RLS/ACL/actor/Subject/source/race/Company tenancy gates and structural checks. **Not executed.**

## Source-provider adapters (NOT built in this PR)

Examples of different company sources using the SAME mechanism after their *own* source policies:

| Company / source | True evidence | Domain-specific escalation (not kernel) |
|---|---|---|
| Manufacturer | Verified quality exception on specific production lot | A stop/rework choice crosses documented financial or safety authority |
| Marketing agency | Client deliverable blocked by missing approved assets | Contract deadline/commitment threatened; routine creative revisions remain delegated |
| Nonprofit | Verified grant-restricted funds not covering approved obligation | Restricted-fund governing choice is required, not automatic payroll Work |
| Retail distributor | First-party confirmed unavailable inventory against actual orders | Buying/reallocation exceeds independently approved operator mandate |
| Flower farm | Real Harvest batch or trusted seed shortfall | Source-specific owner preparation/purchase decision, not an automatic Principal Clock claim |

**Admission is an engineering security boundary, not a status flag shortcut.** Each separate adapter must prove actual source event/current revision, first-party source, unambiguous native Subject, separate disclosures, real Organization/Ledger custody, governing policy, an explicit escalation threshold, source revocation, idempotent event and race lock *before* it can register a `source_verified_by_adapter` case. Never let generic client IDs or untrusted JSON claim that verification. A verified case is NOT a verified Need, accepted Result or accepted new Work; those have their own source.

## Audit of existing work: retain as adapters, not universal law

- [P3 #2565](https://github.com/optical-lift/noel-core-db/pull/2565) files 10/14/15/16/17 know farm, Harvest, seed inventory, Journal and their owner review. They are **farm operating adapters**, **NOT** the universal case schema or Principal Clock. This audit added explicit `operationalOwnerReviewOnly=true`, `principalEscalationQualified=false`, and `principalClockCandidateCreated=false` response/payload flags where appropriate, without changing source of already recorded observations or fabricating a principal escalation threshold. Existing P3 owner Journal may still be too broad if every routine bucket creates attention; that is an **open Farm-adapter escalation/cadence and owner usability gate**, not universal law.
- [P2 #2566](https://github.com/optical-lift/noel-core-db/pull/2566) is a **first-party farm manual-log retrospective evidence adapter**. It is not a generic retrospective physical Actual solution for every company.
- [U2A #2482](https://github.com/optical-lift/noel-core-db/pull/2482) accepted-first offer is explicitly native `rhythm_state` and **mowing stewardship only**. It cannot create Harvest, seed, a client approval task or a payroll Work merely because a principal requested admission.
- [U2C #2485](https://github.com/optical-lift/noel-core-db/pull/2485) one effective Rulebook and one accepted-first original remain governing for their current source scope; no source adapter bypass or competing generic original writer is introduced here.
- The November 4 **6A no-automatic-successor rule is genuinely universal**. Completion or Result may update observed condition and indicate a new eligibility window, but cannot issue the next Work/offer/schedule/assignment by itself.
- The Atlas **Principal Operating System** architecture (August 15 governing direction) explicitly separates operating Worker Day, management/escalation and Principal arbitration. Ordinary misses or physical output do not automatically get the Principal's floor. The generic case and `request_principal_arbitration` do **not** issue a `ClockCandidate` or preempt Household, fixed human obligations, strategic H2/H3 windows or money.
- `Atlas Delegated Agent Governance` keeps the source Principal, bounded carrier, operation, jurisdiction and outcome distinct. No autonomous carrier was registered or granted.

## Release boundaries

No public admission transport or new source adapter, no generic all-company Need/Subject Rulebook, no generic employer-specific accepted-first issuer, no Principal Clock promotion, no legal/HR/clinical source disclosure, no U2E nonhuman carrier, no Household false-Company bridge, and no retiming historic Work/Actual. **This is deliberately a universal kernel draft with zero production users, not a released universal product.**

**Still open:** formal company-neutral source adapter registry/authority attestation, company/non-rhythm Rulebook admission, independent Person offers/consent and one canonical Work writer per source, genuine current Result/one Done, source freshness at action time, Principal escalation contract/ClockCandidate, P3 farm adapter emission thresholds and UI. The user's governing authority must decide issuer mode if not already recorded; do not choose agent/worker impersonation. Old P3 and P2 PRs remain separately held, and no mainline changes are implied.

**No PostgreSQL parser/compile, full-schema migration, real signed GoTrue/PostgREST actor tests, RiverSong or CI, production SQL, ACL/RLS permission change, schema deployment, branch merge, Work/Result/Clock/schedule/Person operation was performed by authoring this held candidate.**


## No competing decision histories — explicit source assembly stop

The existing farm P3 #2565 file 17 separately creates `uni_ops_p3_owner_attention_decision_events_v1`. That farm-local table and `uni_ops_governed_case_decision_events_v1` MUST NOT operate as two independent governor authorities. **The universal schema file 01 now refuses compilation/installation if the farm-local decision table already exists; P3 file 17 symmetrically refuses installation if the universal decision table exists.** In either order, a direct accidental stacked deployment fails closed.

This is a **migration constraint**, not a recommendation to erase P3 data. The next approved implementation must retain each farm source attestation, preserve existing immutable farm decision events at their real times and authors, and replace the P3 17 writer with ONE authenticated source-bound adapter to the canonical company decision history. Until that mapping and its same-event replay semantics pass signed actor/negative/race tests, both drafts remain HELD and **cannot be released together**. There is no data migration authored or approved by this PR.

## First bounded source adapter — true Harvest/Seed evidence, same Company kernel, no duplicate governor

**04 `04_verified_farm_source_to_company_case_adapter_held.sql`** is an actual **source-specific candidate**, not a generic registry for any user-provided text. A current authenticated governing Company Ledger root supplies one exact existing owner-only Farm Journal attention ID and current true U1B Farm→Ledger custody. The adapter independently verifies the real **nonweekly** `flower_harvest_bucket_observations` underlying that Journal, exact source/batch/Task/farm/member and its original recorded timestamp, and absence of an already recorded owner `flower_preparation_directives`. For Seed it verifies the real `seed_inventory_events` event ID referenced by the Journal is still the actual **latest** `seed_inventory_position_v1.source_event_id`, that the count is **trusted**, and that current `seed_allocation_coverage_v1` exceeds projected on-hand by a positive amount. It rejects historical shortages that were corrected by a later count and labels without firsthand source evidence. **Weekly Harvest P3 10 is deliberately not included**—its Done/transition proof is a different source requiring its own adapter.

The adapter requires **two independently signed information-type disclosures** to the current governing Person for exact `farm_operations/flower_harvest_batch` or `farm_operations/seed_lot`: `identity` and `condition`. It computes an attestation digest over actual native source data, an exact source revision (underlying event ID + fingerprint), and creates one immutable original `uni_ops_governed_source_cases_v1` plus one immutable `uni_ops_farm_company_source_links_v1` link (idempotent replay; conflicting history denied). **This is only operational governor review**, never Principal Clock/Work/worker consent/physical Result. It never writes a P3 farm-local governing decision table.

**Important live-schema dependency caught during the build:** production `atlas.subject_disclosure_decision_events_v1` currently **does not support** `farm_operations/flower_harvest_batch` or `farm_operations/seed_lot`. Its `subject_disclosure_supported_subject_v1` CHECK only accepts `spatial/growing_object` identity+condition, `event/occurrence` identity, or `spatial/farm` current_inventory. The old `governor_set_subject_disclosure_self_api_v1` additionally validates its older original Subjects. Calling `has_current_subject_disclosure_v1` with an invented new kind CANNOT produce a valid grant until the genuine source is extended. **Do not remove the gate or grant by metadata.**

**06 `06_bounded_existing_subject_disclosure_extension_held.sql`** is that explicit, separately reviewable **HELD source**: original constraint is MD5 pinned to actual read-only current definition `d485d918b633c4ba51ea013f99e12e53`; preserve all previous allowed kinds and append only two new exact Farm type/class combinations. Never rewrite older disclosure events or broaden existing general writer. New **private** `uni_ops_governor_decide_farm_attention_disclosure_held_v1` rechecks the same genuine source Journal, source-native batch or latest trusted shortage, active actual Farm→Company Ledger custody, signed governing root, exact connected target Person, then appends to the **same** canonical `subject_disclosure_decision_events_v1`, using exactly the existing per-Subject/class and action advisory locks. It records separate `grant` or `withhold`, reason and actor; RLS/API roles have no new execute grant. No Subject disclosure becomes automatically granted through Farm ownership or the CHECK expansion. If genuine grant actions are absent, 04 still refuses admission.

**05 `05_farm_to_one_company_governor_decision_wrapper_held.sql`** is a **separate current-source-rechecking decision wrapper**, not a second decision history. It checks actual physically current underlying source and exact immutable case/source-link/source revision fingerprint under the same Journal-row transaction lock, and then calls **one** private canonical Company `uni_ops_company_governor_decide_source_case_self_held_v1`. The farm source may request separate Work admission, hold for more source or decline present action. It cannot request direct Principal arbitration without independently proved escalation, cannot issue an original/Person/Clock or replace U2 worker consent. The farm-local P3 17 table remains incompatible with universal schema 01 by reciprocal explicit fail-closed guards. Prior farm decisions are source history to preserve in an approved future migration, not permission to install two writers.

**Correct future disposable source order:** true production-shaped native schema, original bounded U1/U2 custody authority and existing Subject decision table → held P3 14/15 evidence/Journal sources (**without** the independent P3 17 decision table or dependent P3 16 old reader) → universal **01, 02, 03** → **06** disclosure CHECK + private bounded signed disclosure writer → individually signed explicit disclosure `grant` to a current governing Person → **04** verified native source→neutral case/link → **05** same-source private governor decision wrapper. The signed grant steps are **not performed by a migration or cron**. Existing farm P3 historical decision rows, if any, require a separately approved preservation plan before this order can be used. No general company source admission/Work issuer/Principal escalation is built.

**Status:** all added 04/05/06 held source, not SQL-parsed/compiled/executed, no signed person grants, no owner approval for broad permission, no merged PR, no production records/Work/Clock/ACL or UI changes. A farm adapter proves only that this one domain can *potentially* use the common case/decision structure after separate genuine grants and tests; it does **not** make all companies' evidence sources available or create a generic Work writer.
