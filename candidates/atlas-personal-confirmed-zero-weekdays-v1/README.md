# Explicitly known zero-capacity weekdays
**Source-only, not released.** The existing Person-owned `atlas.principal_capacity_policies` is canonical compatibility storage. Its native writer, self-reader and daily capacity projection are extended to distinguish `confirmed_unavailable` days (known zero) from absent source facts (unknown) without inventing a positive time window.

## Minimal source changes
- Paired nullable `local_start/local_end` with an invariant that NULL+NULL is valid **only** when both planning-minute values are exactly zero. Every positive interval remains real, same-day and ordered.
- Native writer accepts `availabilityState='confirmed_unavailable'` and *no* start or end time; defaults to existing confirmed-positive behavior otherwise. Explicit zero rejects any provided time, nonzero minutes or conflict with a separate effective positive policy for the same weekday. Existing owner/Person/Atlas authorization, stable-key retry and metadata history are kept.
- Native Person reader exposes `availabilityState`; day-state returns `capacityKnown=true`, `discretionaryCapacityMinutes=0` with no temporal interval, rather than fabricating zero as a 24-hour protected block.
- A separate existing positive 08:00–18:00 policy still computes source-adjusted minutes normally.
- Weekly fit read-only API from released migration `20261016205755` must rank a seven-day week with Mon–Fri positive and weekends known zero. It must refuse placement while Sat/Sun still unknown.
- The test uses two separate **synthetic** canonical native Person/Household/Personal Atlas identities via the released enrollment path, and verifies no cross-Person disclosure, idempotency and bad inputs.

The Product Foundry must ask whether each day is available, unavailable, or not established without claiming a missing answer means unavailable. Application PR #292 is **draft** and must not overwrite existing capacity records. No independent task, Clock or scheduling store. Future source corrections must use this same native policy boundary.

**Release process:** source custody CI → canonical generation fresh migration version → disposable production-schema behavioral clone → protected production release request. No direct DDL to production, no promotion of an untested guess. This work is a follow-up to issue #1649.
