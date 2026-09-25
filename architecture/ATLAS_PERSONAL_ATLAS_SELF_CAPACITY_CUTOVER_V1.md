# Atlas Personal Atlas Self-Capacity Cutover v1

Status: governing implementation architecture  
Date: 2026-09-25

## Purpose

Not every consequential write is an institutional authority question.

A Person recording the boundary of their own available time or the protected rhythm of their own household is establishing personal state. Atlas must not require an Organization owner role, a Ledger Seat, or an institutional responsibility merely to let the signed-in Person establish that state.

The canonical chain for this class is:

```text
Auth
→ Reality Person
→ native Personal Atlas
→ self-authored personal / household state
```

This differs from an institutional mutation:

```text
Auth
→ Reality Person
→ explicit Responsibility
→ jurisdiction
→ permitted operation
→ institutional mutation
```

## Compatibility storage

The existing capacity policy and household rhythm tables still depend on legacy Principal storage.

For the current migration window, `atlas.personal_atlas_compatibility_principal_id_v1(uuid)` maps a canonical Reality Person with an active native Personal Atlas to exactly one active legacy Principal whose `person_id` is that same Reality Person UUID.

The Principal row is therefore a **storage carrier only**.

It does not establish:

- identity;
- authentication;
- ownership;
- institutional authority;
- Ledger access;
- permission to act for Elm Farm or any other Entity.

If zero or more than one active Principal carrier exists for the Person, the bridge fails closed.

## First cutover

The active Personal/Principal capacity authoring surface moves to:

- `atlas.personal_capacity_policies_self_api_v1()`;
- `atlas.personal_set_capacity_policy_self_api_v1(jsonb)`;
- `atlas.personal_upsert_household_rhythm_local_self_api_v1(jsonb)`.

All three establish the caller through Reality Person + native Personal Atlas.

The old `principal_*` APIs remain temporarily because undeployed and older product surfaces may still call them. Their continued existence does not make them canonical identity or authority.

## Capacity policy

A personal capacity policy says how much of the Person's own time Atlas may consider allocatable.

It is not:

- an employer work schedule;
- a productivity quota;
- a farm authorization;
- a Company Work assignment;
- a grant of authority over another Person.

The new writer continues to use `atlas.principal_capacity_policies` only because that table has not yet been physically migrated.

## Household rhythm

A household rhythm is likewise personal/household state.

The legacy `household_rhythms.principal_required` field remains set for downstream compatibility, but the new contract explicitly records that this field is a legacy storage condition rather than a source of authority.

Household self-governance does not require an Organization owner role.

## Acceptance

This cutover is accepted only when:

1. the active capacity page is admitted by Reality Person + Personal Atlas;
2. its POST route contains no Organization owner gate;
3. the capacity-policy read uses the Personal Atlas RPC;
4. the capacity-policy write uses the Personal Atlas RPC;
5. the household-rhythm write uses the Personal Atlas RPC;
6. the new database APIs contain no `current_principal_id_v1`, `organization_memberships`, or `is_farm_owner` authority dependency;
7. the compatibility bridge resolves exactly one Principal storage carrier and fails closed otherwise;
8. existing household rhythms are not rewritten merely by introducing the new access seam.

## Boundary

This tranche does **not** claim that every old `principal_*` table is personal state.

Financial custody, institutional Company Work, cross-Entity adjudication, and other external-effect mutations must be classified separately. Function name is not authority semantics.


## Complete-unavailability blocks and partial-capacity adjustments

The same personal-state rule applies to self-authored capacity blocks and adjustments.

A complete-unavailability block says the Person has explicitly established that an interval is unavailable.

A partial-capacity adjustment says the Person has explicitly established that an interval has less-than-full but greater-than-zero availability.

Neither fact is an institutional authorization.

The Reality-rooted endpoints are:

- `personal_capacity_blocks_self_api_v1`;
- `personal_capacity_adjustments_self_api_v1`;
- `record_personal_capacity_block_self_api_v1`;
- `record_personal_capacity_adjustment_self_api_v1`;
- `transition_personal_capacity_block_self_api_v1`;
- `transition_personal_capacity_adjustment_self_api_v1`.

The old Principal-named self-capacity endpoints are retained only as compatibility aliases to these Reality-rooted functions. This protects older callers from recreating Principal-as-identity even before every caller has been renamed.

### Evidence identity correction

The old self-capacity writers checked `evidence_records.scope_kind='person'` against the Auth user UUID.

The new writers check the same `person` scope against the canonical Reality Person UUID.

At the time of cutover there were zero Person-scoped evidence rows and zero saved capacity blocks or adjustments, so this correction required no historical row rewrite.
