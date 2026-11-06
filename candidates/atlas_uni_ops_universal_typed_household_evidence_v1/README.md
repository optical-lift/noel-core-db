# UNI-OPS-01 — typed Household native Subject evidence adapter (HELD)

**Noel source owner. November 6, 2026. Source candidate only; not installed, adopted, migrated, or authorized for production.**

This is the first nonfarm native evidence adapter alongside the separate universal prerequisite in [Noel common #2555](https://github.com/optical-lift/noel-core-db/pull/2555). It does **not** pretend the native Household governor is an Organization's primary Ledger root, nor create a second Work kernel. A source adapter establishes *what the native evidence actually supports*; **only a future independently source-approved composition** may then determine canonical Reality identity and a Rulebook. Native proof by itself never grants policy/Work authority.

## Existing owner/source rather than new machinery

The authoritative native Household source already has `atlas.households`, `household_kernel_instances`, `world_kernel_definitions`, `care_current_state`, `care_observation_events`, `household_need_occurrences_v1`, and `atlas.require_household_governor_self_v1()`. This adapter does not create, rewrite, migrate or replicate any of them. Any future domain other than Household must add **its own typed source verifier** under the same universal common rules; Household permission must never spill into it.

The **exact current first-party signed principal** is verified with `atlas.foundry_current_signed_principal_v1()` and `atlas.current_principal_id_v1()`. Household governor authority is verified by the *existing* source-owned `atlas.require_household_governor_self_v1(p_household_id)`, not an Atlas corporate native Ledger seat. The exact kernel must belong to that active Household, be an active instance, and have a currently active native world-kernel definition of matching key/version. A worker who belongs to the Household but is not its governor cannot invoke the adapter.

## Truthful states / no new Work

A verified native Subject returns `native_subject_only_not_canonical` with `nativeSubjectVerified=true`. A current physical condition is **not** assumed from a schedule, a kernel's configuration or the existence of a rhythm. `currentObservationSourceVerified=true` is possible only if the current state references a matching original, non-clock-inferred, firsthand-sourced observation in the exact Household and kernel. `openNeedSourceVerified=true` additionally requires an existing open native Need whose origin is that exact observation; this adapter never creates a Need.

Even when source-positive, it does **not** establish an independently reviewed Reality Entity crosswalk, a canonical Work Requirement, a Foundry original or policy adoption. The response holds **nine explicit false authority flags**: canonical Reality binding, common Requirement, independent Foundry review, domain admission, adoptable/executable policy, created Work, Clock, successor Work. Its function is **private** and deliberately has **no public wrapper or grants**. The one synthetic wrapper in the signed clone test is disposable fixture-only, never an installed API.

**Important generalization limit:** This candidate is a correct typed *native* source boundary, not a ready universal Rulebook admission for Household. The existing common U1A prerequisite currently requires Organization primary Ledger + canonical Reality-linked Work Requirement, and cannot simply be called with a Household ID; any later composition needs an independently approved custody/jurisdiction-specific authority resolver. Avoid copying the corporate root to make Household appear eligible.

## Read-only live source preflight (aggregates, November 6)

Four active Households, one active Household native kernel, 21 Household rhythms, **zero** native Household care observations (including kernel observations), **zero** current Household care state and **zero** open native Household Need occurrences. Thus native recorded subject and governance structures are present, but **no source-positive current physical condition or open Need has been demonstrated**. No observed condition, canonical Reality identity or Work Requirement may be invented to create a green live test.

## Exact acceptance boundary

- Source-only Node tests and Database Custody CI must pass.
- Fresh production-schema-shaped PostgreSQL clone: source must compile; postconditions check private function and absence of public grants.
- **Genuine signed** first-party synthetic Household governor must read exactly the existing native C1 Household/instance, even when Household has no active Company Ledger. Separately signed worker (who is a real member, not governor), outsider, no-seat, anonymous, wrong Household/instance and deleted-session requests must deny with native authorization; neither a spoofed metadata owner flag nor a service-role route grants authority.
- The C1 fixture may be used to prove *mechanics* only; this does NOT constitute a real independently observed Household condition or live nonfarm Rulebook. No original Work, Need, source event, new Reality Entity or policy is issued by the adapter.
- U1A exact existing spatial Result/Rulebook authority, universal common #2555, one U1A/U1B Rulebook arbiter, U2 accepted first Work, and P3 no automatic successor remain separate held gates.

**No real Household/Elm Person or property data, roles, grants or production SQL changed by this source draft.**
