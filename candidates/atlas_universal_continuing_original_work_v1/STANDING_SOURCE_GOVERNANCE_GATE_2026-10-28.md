# Continuing original Work — source-governed standing authority

**Status:** held source candidate, no production release, no new canonical Work
store, no parallel farm Task/Today writer. Product PR #2362 stays draft,
depending on held universal single-Done PR #2368.

## User's three governing decisions (2026-10-28)

1. **Eligibility:** evaluate the governed rhythm together with *current,
   attributable physical observations*. Elapsed time is never sufficient.
2. **Authority:** the Ledger governor chooses authorization method when
   establishing each rhythm. A later change is an immutable new decision,
   not a silent mutation of the old grant.
3. **Views:** owner and connected Person eligibility projections are
   independently configurable and enforced by native connection, current
   accepted scope, and exact Subject field-disclosure sources.

## Reused Atlas sources

- `atlas.rhythm_rules`, `rhythm_bindings`, `rhythm_state`,
  `rhythm_satisfactions` govern the cycle, timing and latest qualifying Actual.
- `atlas.care_observation_events` and `care_current_state` preserve observed
  reality; an observation from the clock cannot qualify.
- `atlas.company_work_standing_assignment_scopes` and
  `company_work_native_ledger_relevance` govern a *Person's* responsibility.
- `atlas.has_current_subject_disclosure_v1` separately controls identity
  and condition. Legacy raw farm readers never establish permission.
- `atlas.work_items`, allocations, execution plans, Results and the held
  single Work lifecycle remain the only canonical Work path.
- The worker's `connected_person_my_work_self_api_v1` remains the
  authorization-aware Today pathway. Source eligibility is NOT Today.

## Implemented held sources

- `13_governed_standing_source_policy_eligibility_v1.sql`: one append-only
  universal source-governance event stream, scoped to existing organization
  Ledger + source Rhythm + accepted worker scope. Methods:
  `owner_each_cycle`, `standing_source_observed`, `hold`.
  Governor views: `full_eligibility`, `exceptions_only`.
  Worker views: `assigned_work_only`, `eligible_disclosed`.
  Eligibility window: `warning` or `due`, with bounded observation age.
  No default authority when a policy is missing or held.
- `14_signed_standing_physical_observation_v1.sql`: existing connected worker
  with current exact identity+condition grants may record signed, attributable
  physical state under an explicit standing policy. It never inserts Work,
  allocation, dates, or Today.
- `15_standing_source_governance_postconditions_v1.sql`: structural ACL,
  immutability, source disclosure, and no task-creation assertions.

## Source admission is still a separate gate

The method `standing_source_observed` means **governor has preauthorized
the *kind* of next admission**, not that any worker or clock has acquired
governing authority. The existing original-Work constructor intentionally
requires a current native Ledger governor. **No released autonomous admission
runner is wired here.** We must implement the separately reviewed
source-qualified execution seam, preserving the signed governor's standing
decision, current physical evidence, exact one-serving concurrency guards,
current Person connection, source-condition qualification, current disclosure,
and a bounded Person-day admission rule. No silent appointment to Today.

A worker can observe a Need and review the resulting source eligibility
when authorized, but observations do not create an original Work. The owner
may still establish exact Work via the pre-existing governed observed-Need
writer when it is source-qualified. Neither a warning time nor an approved
standing method independently admits a task.

## Protected-clone tests

The existing owner-gated validation route for candidate version
`20261028235811` is extended by the signed source tests in
`scripts/validate-atlas-care-single-done-signed-http.py` (test-only
infrastructure PR #2374). It requires real independent GoTrue HTTP sessions,
wrong-person refusal, owner-selected policy, assigned-only vs eligible-disclosed
views, fresh physical observation, clear vs heavy condition, idempotence,
no premature task, shared Done and no early successor, and immediately
effective governor hold. A passing CI compile is **not** a signed runtime pass.

Use only the canaried disposable production-schema clone. Do not change
RiverSong's retained `noel_schema_clone:55432` or real Elm/Anna records.
