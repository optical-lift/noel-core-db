# R02 — Universal Rhythm Offering: source-governed governor mandate

Status: **HELD, SOURCE-ONLY** (November 3, 2026). This is NOT a
migration or an approval to access production data. R01 is its parent.

## Owner and boundary

Noel owns source eligibility, source adapter registration, accepted native
Person responsibility, disclosure, physical Actual qualification, the
original Work and universal one-Done lifecycle.

Atlas owns a single domain-neutral governor review/approval interface
embedded in the existing source-verified Ledger Person Work lens.

Every rhythm is a source. A rhythm is not a task merely because a cadence
exists or a date approaches. A governor review can select one source-qualified
opportunity, a current accepted Person scope, a deliberate first workday,
an explicit set of ISO weekdays, a bounded end date and an explicit reason.
This mandate does NOT declare physical condition, alter a rhythm Rule,
manufacture a generic task, bypass worker disclosures or assign a Person
without a currently accepted source scope.

## Generic transport

- `public.governor_review_rhythm_opportunities_self_api_v1`:
  source-gated keyset page of candidateId, adapterKey, rhythmKind,
  rhythmLabel, subjectLabel, sourceRuleId, cadenceSeconds, sourceDueAt,
  canOffer, blockingReason. Owner-only; exact organization, Ledger,
  connected Person scope. No mutation. Scope-owned subject details only.
- `public.governor_approve_rhythm_opportunity_self_api_v1`:
  source-selected adapter + exact candidate, scope, reason, first workday,
  campaign end date, sorted approved ISO weekdays and durable action UUID.
  The adapter must independently reauthorize at the write boundary;
  the common wrapper does not insert into Work, allocation, plan, rhythm
  or task tables. A confirmed receipt identifies precisely one original
  Work, and distinguishes new, same-action repeat and existing open Work.
- Both common wrappers have an authenticated membrane, but all access
  control happens again in private Noel functions. All private adapter
  and common source functions revoke PUBLIC/anon/authenticated EXECUTE.
  No client can choose an unregistered source adapter.

Registered adapter today: `continuing_care_actual_v1`, using the already
held R01 care source. It is intentionally housed behind
`atlas.governor_rhythm_care_opportunities_adapter_v1`. It maps
authoritative farm-based rhythm Subject+Rule inputs to the **same generic
contract**; only this adapter contains farm/weed/mow logic. It reuses the
existing R01 owner writer and its signed Person/Subject/date/Work guards.

This is a **universal interface**, but NOT a claim of total coverage:
`coverage=registered_source_adapters_only`,
`notAnAllRhythmsCensus=true`. Laundry, cleaning, life, Event, program,
calendar and other rhythms each need an independently authorized adapter;
no other rhythm is silently promoted into the current care source.

## Proof and release gates

- [Atlas held R02 draft #531](https://github.com/optical-lift/atlas/pull/531):
  universal Workbench, source reader and mandate, replay, client contract
  tests. [RiverSong #41658246897](https://github.com/optical-lift/atlas/actions/runs/41658246897)
  PASS unit, TypeScript and full Next build.
- [Noel R02 source-only RiverSong #41658854734](https://github.com/optical-lift/atlas/actions/runs/41658854734):
  4/4 source contracts PASS; not database proof.
- [Noel test-only #2458](https://github.com/optical-lift/noel-core-db/pull/2458):
  mandatory signed generic preview / owner approval / outsider denial /
  unknown adapter / day rejection / same original Work, conditional on
  R02 RPCs in disposable canary. Merged to main; no product DDL.
- [Noel protected candidate issue #2459](https://github.com/optical-lift/noel-core-db/issues/2459):
  exact held canary SHA `ccc27b4384231e7aed2ac4a0af661022df0c4020`.
  [Run #41660483209](https://github.com/optical-lift/noel-core-db/actions/runs/41660483209)
  **PASS, genuine signed R02 acceptance verified in artifact #13241558932**.
  Signed log explicitly reports "PASS R02 universal signed governor preview,
  source adapter denial, same original Work, replay and downstream Actual/Today".
  It separately records 42501 worker/outsider preview and approval denials,
  unregistered adapter/weekday source rejection, exact owner action replay,
  full physical Actual → one Done → one next original in My Work/Today.
  SQL compiled, all source postconditions passed, baseline lint 14 /
  candidate lint 14, newly introduced 0. Only the **registered care adapter**
  passed, not a claim about all future adapters or live Elm/Anna execution.
  The current R02 held canary was restored byte-for-byte to the tested file
  blob `a1accfec49da8114878ad7eb920833b56b0c9088`; no untested
  post-test source change is included in this acceptance.
- Remain HOLD until signed review/approval passes; production migration
  is separately reviewed and approved; mixed-domain expansions require
  their own source qualification and disclosure; real governor and worker
  actions are accepted on actual desktop and iPhone.
- Preserve full negative matrix: disallowed worker/outsider reads/writes,
  unknown adapter, invalid date, withdrawn Person scope, withdrawn Subject
  disclosure, duplicate source, active old legacy task, physical blocked,
  campaign end, competing originals and replay. None is silently waived.
