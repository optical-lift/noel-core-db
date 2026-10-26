# H8 Household life-pattern authority — source-only candidate

**Status:** source-only design candidate. This does not authorize applying DDL
to live Supabase. Atlas H8 PR #342 continues to use released reader contracts.

## What this owns
- The Household's explicitly proposed or intentionally established pattern
  of life and allocation of attention; not a Task, compulsory weekly item,
  physical-condition fact, or Person Daily Commitment.
- A required `householdBasisKind` (relationship or responsibility) and
  `householdBasisDescription`, capturing **the Principal's attributed claim
  of why this pattern belongs in the Household**. It is not independent
  verification of that relationship or a grant of responsibility.
- Pattern identity under one verified active Principal Household.
- Named participation modes (undetermined, solo, shared, divided, rotating),
  with optional IDs of actual active members of that SAME Household.
- Provenance: user proposal is not an established norm; an explicit household
  plan may be established by the owning Principal.
- An explicit **inactive** state for a pattern no longer relevant. History
  remains in append-only change events; no backlog or Clock task is generated.

## Write contract
`public.principal_upsert_household_life_pattern_self_api_v1(p_input jsonb)`

New: `stableKey="pattern:<uuid>"`, `sourceActionId=<uuid>`,
`expectedRevision=0`; update/retire uses the last source-read revision.
Required: `title`, `description`, `attentionShape`,
`householdBasisKind`, `householdBasisDescription`, `state`,
`participationMode`, `participantMemberIds` (optional array),
`provenance`; `changeReason` required on inactive transition.

- Only active Principal can operate in their own active Household.
- Membership IDs must refer to active members of that exact Household.
- Named participation captures the household's reported/established *pattern*.
  It neither imposes a task nor transfers individual consent/authority.
- `proposed` + `user_proposal` is allowed; `established` requires
  `explicit_household_plan` from owning Principal, never frequency inference.
- Revision compare-and-swap rejects stale updates. Source action ID prevents
  duplicate writes; same ID/different input rejects.
- Every accepted change emits an attributed prior/current evidence event.
- No recurrence window, done/overdue, automatic Clock readmission, child/family
  score or implicit permanence exists in this object.

## Read contract
`public.principal_household_life_patterns_self_api_v1()` returns a
principal-scoped inventory of proposed/established/inactive patterns and
their revision and provenance. It has no right to expose another Person's
private schedule or claim a requirement is actionable today.

## Separate responsibilities
- `personal_setup_self_api_v1` existing `household_rhythms` rows remain
  the *scheduled work-window* inventory, NOT this pattern object.
- `personal_laundry_kernel_self_api_v1` can expose calibration evidence,
  but does not itself prove normative Household rhythm status.
- `principal_household_care_snapshot_v1` and the physical space care-result
  writer own observed condition/care events; these do not close the pattern.
- Household Responsibility / delegations, consent, recurring work obligations,
  Care/Clock admission, and Person Today require their respective owners.

## Release boundary
- Validate in disposable production-schema clone.
- Generate canonical migration only through owner-authored instruction after
  source committed to canonical noel-core-db main.
- Separate protected production release and verification.
- Until public read + write RPCs are verified, no H8 UI can imply that a person
  established, altered or retired a pattern by editing client-side state.
- Test actor/no Principal, cross-household IDs, stale revision, concurrent
  updates, mismatched action replay, inactive transition, reactivation,
  rejected observation-to-normativity promotion, and no Clock materialization.

**Model contract reviewed against the owner's ten choices of October 21, 2026.**
