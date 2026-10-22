# Atlas schedule correction preflight (source-specific adapter, v1)

**Status:** Source-only candidate for review. NOT deployed and not a schedule writer.

## Why this exists

The read-only One Date / Subject evidence reader is now live and the Event notebook visibly preserves the Elm October 30 disagreement. There is no general authorized correction writer.

In production, the linked October 30 Harvest Party has:
- Canonical `local_intel.occurrences`: 18:00 America/Chicago, `scheduled`, shared Occurrence UUID.
- `atlas.community_events`: 16:00–20:00 America/Chicago, `planned`, different title.
- A **confirmed `ledger.occurrence_resource_claims` shared claim covering 16:00–20:00 Chicago**, without an attached `ledger.bookings` record. That is resource occupancy evidence, *not* proof the public program starts at 16:00.
- No other active Ledger calendar binding to that exact Occurrence at audit time.
- Operational Event triggers only write through to the Shared Intelligence Occurrence for specifically admitted source authorities (`network_outreach` / `system_fixture`); the Harvest Party is not one of them. Blindly editing one source will not reconcile both.

**This candidate does not pick the winning schedule or mutate source values.**

## Function

`public.ledger_occurrence_schedule_correction_preflight_self_api_v1(organization_id, ledger_id, occurrence_id, proposed_starts_at?, proposed_ends_at?)` delegates to a narrowly scoped `atlas` SECURITY DEFINER function.

1. Authenticates the current Person, active native Ledger relation and exact Organization / Occurrence binding using the already shipped source-specific Event actor guard.
2. Selects exactly one `farm_shared` operational assertion of this source class. Multiple or missing assertions fail closed; the appropriate other source adapter must be built instead of guessing.
3. Compares canonical vs operational title/status/date/clock and source versions; **unequal fields are review candidates, not necessarily mistakes**.
4. Accepts optional absolute-instant proposed window, with finite / ordered interval verification. A proposed time is not itself authority to change anything. The actual source-correction command will separately establish civil-time/DST interpretation and approval.
5. Tests canonical Principal / root Ledger governance independently from ordinary Ledger participation. A root connection is only a *candidate* to request source correction, not automatic authorization to rewrite Shared Intelligence or existing bookings.
6. If Ledger-root-governing, reports counts of active source Resource claims, noncancelled Ledger Bookings, and cross-Ledger reuse. It does not expose booking customers, exact Resource identity, price, or owner-only event notes. For ordinary Ledger participants, dependent source quantities are **not evaluated** and `null`, never `0`.
7. Returns explicit blockers: source writer not released, communication/publication impacts unverified, booking conflict preflight unfinished, potential active claims, missing proposal/permission/timezone. `approvedToCommit` is **always false** in this version.
8. **No persistence, no new calendar identity, no direct event or booking writes, and no claims of full Date field coverage**.

The adapter is universal in its Ledger/Organization/Occurrence authority model; the `community_events` source adapter is specifically for that verified operational source class. Other organization event domains must supply their own adapters through the governing Temporal Field contract, not be forced into a farm-specific table.

## SQL fixture and acceptance gates

- Reuses the **already proven synthetic** three-occurrence / two-person / one-organization Event fixture from the prior read-only date reader. Contains one private owner-only assertion to prove no disclosure.
- Source-only postconditions: SECURITY DEFINER internal and invoker public wrapper, authenticated execute only, no catch-all mutable calendar table.
- Simulated Auth JWT-style role tests: exact canonical identity and source discrepancy; same date not same subject; date drift and unknown end; valid and invalid proposed windows; root-only resource-count privacy; foreign Organization and unconnected Person rejection (including forged user metadata).
- This fixture does **not** establish the eventual root writer or full booking conflict enforcement. A separate local signed GoTrue/PostgREST negative matrix, root-capability fixture, and code review are required before production release.
- This read-only adapter is safe to review independently of the future correction writer; it cannot mark any preflight `approvedToCommit=true`.

## Next writer gate

The follow-on source writer (separate candidate and independently protected release) must:
- Require explicit authorized human choice of exact civil date/time, timezone, source standing and reason.
- Version-lock both source assertions; confirm identity and all permission boundaries again within the write transaction; no optimistic trust of preflight.
- Examine all resource claims, setup/teardown and booking conflicts, published communication and external commitment evidence under their owning source permissions. Never infer no activity from incomplete coverage.
- Keep decision/old values as immutable source-qualified history. Maintain idempotency and return partial outcomes if some source writers are nontransactional.
- Write only through lawfully owned source commands and re-read post-state; forbid a generic root user from overwriting another Ledger or Shared Intelligence source without its authority.
- Block only the actual dependent operations while unresolved, not shared Work, notes or unrelated correspondence.

**No production DDL, data, message, resource claim, or October 30 schedule correction is authorized by this candidate.**
