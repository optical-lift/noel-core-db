# Atlas ONE Calendar — governed source-read transport v1

**Status:** Source candidate only; NOT merged, deployed, or a complete universal Calendar.

## Actual source authority

Reuses the already-live source-owned Temporal Contribution kernels (2026-09-26)
and Ledger scheduling enrichment. Does not introduce another Event store.

- `atlas.ledger_temporal_composer_self_api_v1`: **native Ledger ROOT only**, currently returns canonical occurrences and independently identified resource claims. It must never become broadly seat-readable simply because someone requests a calendar.
- `atlas.organization_context_temporal_composer_self_api_v2`: authenticated and **existing effective Organization membership** only; includes Organization purpose-context and recurrence contribution semantics. It is not proof that a native Ledger Seat has compatible access.
- Public REST wrappers are `SECURITY INVOKER`, `STABLE`, blank search path, explicit `authenticated` EXECUTE only. Underlying private self APIs continue to decide authority. No direct table or service-role exposure.

## Why these two and no universal `calendar_event` RPC

An Event is one `local_intel.occurrences.id`. An Organization's context, an occupancy Resource claim, a recurrence expectation, a Work time contract, a Person obligation and a Clock annotation are different temporal sources. A compositor may report them side by side with source qualified identities; it may not rewrite them or claim missing families are present.

The current private composers already return `coverage.partial` and adapter evidence. Browser consumers must display that partiality and must not normalize Resource claims or recurrence expectations into duplicate Events.

The full Universal Temporal Field needs separately governed Person/Household, Company Work, Clock and Communication adapters before the product promises an “Everything” calendar. It cannot be certified by adding wrappers.

## Release dependency and verification

1. Review and merge only source-approved candidate; generate immutable Atlas migration through `noel-core-db`'s canonical source-generation workflow.
2. Protected production-shaped clone: `validation.sql` and authenticated signed-session root/member/outsider tests. Verify no new security-advisor findings. Never spoof real user identity with admin SQL.
3. Protected manual production migration release and verify catalog/grants. Source availability does not authorize a Vercel release.
4. Atlas browser consumer can then call the released public delegates for an authorized month with exact scope, date range, timezone and bounded limit. Compare one canonical Event across source views, preserving `partial` and typed Resource/recurrence identities.
5. A separate native-seat access contract is required before showing the broad Organization context projection to everyone connected to a Ledger.

## Explicitly not changed

No canonical occurrences, Work, billing, invitations, bookings, resource claims, source time, Org membership, Person access, UI route, Vercel configuration or production database row changed.

October 30 still requires a real signed root-governor correction through the released `set_ledger_occurrence_schedule_self_api_v1`. Its 4–8 p.m. resource hold must remain untouched. The `network_outreach`/`system_fixture` alternate writer retirement remains a separate reviewed database migration.


## Protected signed-session proof now attached

The reviewed source packet includes a DML-only **synthetic** `fixture.sql`
and `validation.sql` catalog + negative role checks. Canonical clone harness
`scripts/validate-production-schema-clone.sh` recognizes only the exact
`*_atlas_one_calendar_source_read_membrane_v1.sql` immutable migration. For
that version it starts local Auth + REST and runs
`scripts/validate-atlas-one-calendar-signed-http.py` using the *disposable*
database URL, requiring local 127.0.0.1 endpoints. Production credentials are
only used by the existing protected workflow for a read-only schema/role dump.

The signed test requires:

- a real GoTrue-signed **root** sees the canonical Occurrence exactly once
  and Resource claim separately through the root-only Ledger composer;
- signed **ordinary Ledger person** and **outsider** cannot read that broad
  Ledger projection; forged editable metadata does not grant root authority;
- Organization member/root can read only the specifically admitted context
  and its one canonical Occurrence; outsider, anonymous and foreign context
  are refused;
- explicit `coverage.partial` survives; loss of native Ledger seat or
  Organization membership is effective for the same already-signed token.

This is a candidate test specification, **not a claim that it has passed yet**.
If clone or signed sessions fail, this migration is on HOLD. The resulting
validation issue/run artifact must be linked before protected manual release.
