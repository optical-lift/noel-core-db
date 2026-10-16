# Public Person-owned Principal Capacity RPCs

**Candidate only**. Not deployed and not a new capacity domain.

Atlas's signed-in notebook `atlasBrowserClient` addresses the exposed `public` RPC namespace. Native Personal capacity reader `atlas.personal_capacity_policies_self_api_v1()` and writer `atlas.personal_set_capacity_policy_self_api_v1(jsonb)` currently exist only inside `atlas` and cannot be used from the ordinary browser client. These existing functions already enforce canonical Person / active native Personal Atlas / unique compatibility Principal, explicit capacity-policy input, and source-stable identity.

This candidate delegates narrowly through two **authenticated-only** read/write `public` RPC proxies without inventing a new source store or permission model. The underlying Person and capacity authority is unchanged; no new mutable table and no alternate frontend identity resolver. The read function is `STABLE`; the writer is not.

**Validation**: disposable production-schema clone seeds two synthetic independent identities and Households, verifies anonymous EXECUTE grants denied and authenticated grants present, confirms owner A policy read/save/read-back and stable retry, ensures owner B cannot read owner A's policy, verifies anonymous source read fails, rejects illegal weekday, and checks registry. Genuine schedule work, approved availability and calendar coverage are not inferred from generic Discovery orientation.

## Product dependency
Atlas issue #1633 describes the actual one-question Foundry encounter, human explicit capacity declaration, and rerun of the read-only week fit. Do not author a page-local shadow policy store, assume every weekday available, or let generic `life.weekday_anchor` fill capacity. Existing Atlas PR #292 must consume only released proxies. Production release is a separate protected/manual operation after source generation, clone validation, review and decision.

## Explicit boundaries
This candidate is independent of (but conceptually complements) the capacity week-window reservation repair #1636 and future-only Personal week-fit source #1638. Neither this read/write proxy nor its tests activates a kernel, changes an accepted Household recurrence, admits a Clock task or marks a physical result as complete.
