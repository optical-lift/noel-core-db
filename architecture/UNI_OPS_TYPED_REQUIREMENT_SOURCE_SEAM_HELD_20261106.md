# UNI-OPS — one Requirement-source contract without a second Requirement/Work engine

**2026-11-06 · HELD SOURCE CONTRACT · for source-owned architecture review, NOT authorization or migration.**

## Grounded existing substrate

- `atlas.work_items` is the **single original Work kernel**. Its `work_items_one_native_custody_v1` CHECK requires exactly one of `organization_id` or `household_id` to be non-null. This is an actual native Household path, not a request to convert Household into Company.
- `atlas.household_need_occurrences_v1` is the original typed Household Need store. It references its original kernel and `care_observation_events`, and has a current original Work pointer. The active native Laundry writer `establish_household_laundry_original_work_self_api_v1` already creates one `atlas.work_items` row with `household_id`, `organization_id=NULL`, `source_object_type='household_need_occurrence'`, `source_object_id=the need`. It then links `need.current_work_item_id` to that Work. Its actual positive result contract and guard are **Laundry-specific**, `household_laundry_begin_cycle_v1`. The existing generic `guard_original_household_work_v1` currently prohibits Household Work using another result contract. Do not widen that by inventing a generic writer.
- `atlas.work_requirements.organization_id` is **NOT NULL**, `atlas.work_requirement_links.organization_id` is **NOT NULL** and their cross-row foreign keys enforce same-Organization links. The held universal common #2555 additionally requires an organization's primary governing Ledger. Neither table is a neutral native Requirement registry.
- `atlas.requirement_boundary_events` is for evaluative state boundaries of a requirement set, not an original Household Need or a canonical Work Requirement; do not repurpose it as one.

## Typed identity, not fake normalization

A *Requirement* is the source-observed unmet condition that may justify Work; its **original source key** belongs to its own jurisdiction. A uniform read-only envelope is allowed to represent different source families without copying, accepting, fulfilling, or creating a new underlying Requirement row:

| Source family | Original source record | Native jurisdiction | Governing source verifier | Shared original Work kernel |
|---|---|---|---|---|
| `household_native_need` | `atlas.household_need_occurrences_v1.id` | `atlas.households.id` + kernel | genuine original Household native #2559 + independently current identity review in U5 | `atlas.work_items` with `household_id` |
| `company_work_requirement` | `atlas.work_requirements.id` | Organization + actual governing Ledger | universal common #2555 + actual Company native Ledger root | `atlas.work_items` with `organization_id` |

### Held source implementation

1. `typed_requirement_source_union_candidate.sql` defines a **private source-only** `atlas.uni_ops_typed_requirement_source_union_internal_v1`. Caller supplies exactly one source family with all required IDs and **no IDs from the other family**. The function invokes the existing family-owned verifier; it does not duplicate governor logic or resolve identities by label.
2. The returned discriminator preserves `sourceFamily`, `jurisdictionKind`, exact original source table/ID and canonical Reality Subject where independently current. The response is **not** a persisted `work_requirements` row, not a new Need and not a policy. All adoption, Work, Clock and successor flags are false. `household_native_need` explicitly reports `canonicalWorkRequirementId=NULL`; that is correct, not a missing created record.
3. `existing_original_work_reference_candidate.sql` reports whether an *already existing* original Laundry Work genuinely corresponds to a source-owned native Need and lives in the same `atlas.work_items` table, with correct Household-only custody/source/contract. It issues **no** Work and does not change the existing Laundry guard. Non-Laundry Household original Work is reported unsupported, not inferred from an ID or title.

## Governing decisions kept separate

The logical cross-domain Requirement interface is a **read contract**, not a release of a generic writer. Later policy issuance requires: independently current typed source + exact Need, current identity/condition disclosures to the actual worker, Foundry source and independent review, domain-specific authorized Rulebook and **one U1A/U1B policy arbiter**, then separately U2's offered and recipient-accepted original Work. The existing Household Laundry writer may operate within its original explicit source contract independently of that future universal authorization; it is **not** evidence that arbitrary native kernels can now issue Work.

A future universally typed issuer should extend the **existing** `atlas.work_items` custody branches only under reviewed source-specific result/Actual rules, not make Household Organization-scoped and not create a second `work_requirements` clone. Any required source-state link must point to the original native Need ID and cannot rewrite that Need or mutate its original observed event. Existing Household Laundry Work should be reused, never duplicated just because a universal policy becomes eligible.

**Nov 4 decision 6A:** Result/Done must never automatically issue the next Work. Neither this source interface nor an observation callback schedules successor Work.

## Deferred, collected acceptance (NOT RUN)

In one eventual disposable source-shaped signed run, include both separate held #2555 and #2559 verifiers and the U5 candidates. Test exact **exclusive family dispatch**, source currentness, signed root denial, absent/wrong primary Ledger, wrong Household, mismatched canonical identity/Need, stale current observation, independent disclosure withdrawal/regrant, revoked review, repeat action and conflicting current identity, original Laundry Work already linked, invalid or unrelated Work pointer, non-Laundry guard hold, zero DML into existing sources, absence of public function grants. Confirm no second source IDs or Work rows, and 6A no successor.

**No collected PostgreSQL/GoTrue or Node tests were run to write this contract.** The typed envelope is draft source, not runtime evidence or permission for Atlas UI/policy/Work.
