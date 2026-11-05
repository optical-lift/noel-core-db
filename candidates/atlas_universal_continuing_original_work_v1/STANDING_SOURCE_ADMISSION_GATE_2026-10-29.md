# Source-qualified continuing original Work admission

Status: **draft-only / protected runtime gate active**. Noel PR #2362 depends
on the unmerged single-Done PR #2368. These files never go to production
without separate review and deployment authorization.

## Decisions preserved

1. Rhythm eligibility must be accompanied by a fresh, attributable,
   non-clock-derived physical condition that is still current.
2. Ledger governor selects the method: per-cycle, preauthorized standing
   source, or hold. Standing source does not impersonate the governor.
3. Connected worker and governor projections are separately governed;
   exact identity and condition grants are source-enforced and revocable.

## New native admission

- `16_native_standing_source_authority_extension_v1.sql`: fingerprint-
  guarded extension to existing native exact Ledger source resolver,
  Ledger-evidence check, and Person-responsibility trigger, retaining all
  previous owner and non-standing branches. Recognizes ONE provenance:
  immutable `atlas.continuing_work_source_governance_events_v1` with
  accepted native Ledger connection and worker-signed actor.
- `17_standing_source_qualified_admission_v1.sql`: signed worker requests
  exact subject, client action ID and service date. Source locks overlap
  observation, original Need and canonical Work. Refuses missing current
  standing authority, wrong actor, withdrawn/expired connection, missing
  identity/condition grants, unqualified source, stale observation, a
  future rhythm window, an existing open original, or unresolved legacy
  tasks. Uses `source_verified` with the actual immutable governor event;
  does not manufacture a contemporaneous owner attestation.
- Creates the ONE original in existing `atlas.work_items`, context links,
  exact Ledger relevance, native canonical Person allocation, one explicit
  execution plan and one plan event. Never touches legacy `atlas.tasks`
  or inserts a second Today lane. Service date must be selected by the
  entrusted Person for the current local day through the next 14 days.
- Same action and unchanged authority/date are idempotent; a different
  action cannot mint another open original for the same Need. Completed
  original Work and physical Results remain history.
- `18_standing_native_admission_postconditions_v1.sql`: strict private
  source and authenticated-only public seam, fingerprint, native Ledger
  relevance, guard provenance and no-clock/no-duplicate construction.

## Runtime acceptance

Test-only main harness PR #2376 merged after Database Custody CI. The
protected owner-authored request #2377 exercises genuine GoTrue-signed
worker, governor and outsider bearer HTTP, source evidence from a renewed
Rhythm cycle, native `connected_person_my_work_self_api_v1` display,
exact service-day scheduling, source-verified relevance, replay, duplicate
serving, Bed 4 non-disclosure, and immediate hold.

The first protected attempt stopped on two missing SQL statement terminators
in the copied native function definitions. Those were fixed without changing
authority logic. Its rerun must pass before any acceptance claim.

## Explicit limits

- `standing_source_observed` authorizes **worker-initiated admission after
  source qualification**, not a periodic background clock generator.
- This source gate does **not** autonomously choose a service date, which
  would violate the original Person-day scheduling authority.
- A second bed requires its OWN Rhythm state, current physical observation,
  accepted source authority, and identity/condition disclosure; Bed 3 never
  implies Bed 4. The previous bed's completion does not automatically
  disclose or schedule another one.
- Existing Atlas Today and Notebook UI still require their normal client
  wiring and signed-release verification; a passing database `My Work`
  reader does not demonstrate a mobile screen was updated.
- Changes made to native allocation guards are source-exact and tested only
  against a disposable production-schema clone. Keep all production
  migration, API grants and UI deployment held.
