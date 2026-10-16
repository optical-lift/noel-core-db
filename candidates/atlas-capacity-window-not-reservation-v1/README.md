# Atlas Principal Capacity: attention window is not time reserved

**Source candidate only (October 16, 2026). Not merged, validated, or deployed.**

## Verified fault

The live `atlas.households` after-insert trigger calls `atlas.ensure_household_care_policy_v1`, which creates five zone-attention rhythms. Each describes 15 minutes of protected attention in a one-week `next_window_start/end` opportunity, with `metadata.policyKey=atlas_household_five_zone_attention`, `releaseKind=protected_attention`, `executionGenerated=false`, and `blocks_capacity=true`.

The current `atlas.principal_capacity_blocks_v1` exposes each active week's entire span as a time reservation. A real capacity policy of 08:00–18:00 and 120 discretionary minutes can therefore incorrectly resolve to zero free minutes, and `atlas.principal_claim_position_v1` can report an entire week as reserved when no physical execution was scheduled. This was reproduced in the *isolated* Atlas weekly-fit migration validation run #38949701522. A live read-only aggregate found 10 such active rows, each spanning 168–169 hours.

## Narrow correction

Keep all five source rhythms, five zones, attention ownership, Clock visibility, and due-state unchanged. Revise only `atlas.principal_capacity_blocks_v1` so that the specifically identified `protected_attention` five-zone source with `executionGenerated=false` does not masquerade as a *fixed reserved interval*. Ordinary `principal_capacity_blocks`, `household_events`, and all other previously admitted rhythm view rows remain unchanged. Do not rewrite the old `blocks_capacity` column or delete historical records. The security-invoker view and existing grants remain intact.

**This is not a general statement that a Household requirement consumes no effort.** The 15-minute requirement is still due, but it cannot be subtracted from a particular 08:00–18:00 interval until an authorized placement/temporal contribution establishes which time it occupies. Do not silently assume it is completed or free.

## Disposable-clone proof

- Seed a synthetic authenticated Principal + Household using the real after-insert trigger. Require five real automatic care rhythms.
- Seed a seven-day 08:00–18:00 policy allowing 120 discretionary minutes. The known day must have 600 elapsed available and 0 blocked, not 0 available due to rotating zone attention.
- Seed a 09:00–10:00 *actual fixed Household event*: exactly 60 minutes is blocked.
- Seed a separate 11:00–12:00 Principal capacity block: exactly 120 minutes total is blocked.
- Retain the view's `security_invoker`, deny anonymous selection, preserve original source identities and types. Everything is synthetic; no real production rows and no schedule/Task writes.

## Separate follow-ups

The existing weekly-fit reader remains held in draft database PR #1628. A future source-regenerated version must exclude *past days* and pass its own native-Person privacy/behavioral tests, and the actual acceptance-to-Clock lifecycle is not yet implemented. Separately audit any non-zone Household rhythm whose due window may have been interpreted as a reservation; do not generalize this narrow fix to an unreviewed source contract.

**Release:** candidate review on `noel-core-db` → canonical generation → disposable production-schema clone → explicit protected manual production release. No automatic deployment or paid Supabase branch.
