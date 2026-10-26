# Work → growing object: first exact physical-context admission

**State:** Source-only DB candidate. This is the first necessary component of
[Noel #2255](https://github.com/optical-lift/noel-core-db/issues/2255) and
[Atlas #437](https://github.com/optical-lift/atlas/issues/437). It must not be
interpreted as a release or any Person's new access right.

## Audit that drove this candidate

Actual live source inspection on Oct 25 found:

- Anna's canonical Person has active native Flower and Venue seats. The 18
  active Work allocations use 2 canonical Person keys and 16 retained
  institutional memberships; do not duplicate or rewrite that history.
- Her active **Measure + stake/string U-Pick Beds 3 + 4** Work row references a
  valid legacy task, whose broader source is **Beds 1–4**. A previously
  established `company_work_legacy_slice_contract_provenance_v1` record
  verifies that the *narrower* Work row is a legacy-task slice.
- The source task has a real zone reference, **U-Pick Blocks**, and the two
  intended physical beds exist as separate canonical `growing_objects`
  with stable keys `u_pick_bed_3` and `u_pick_bed_4`. The bed-zone relation,
  organization and operating unit all match.
- No `task_objects` or `work_item_context_links` relationship currently
  joins this exact Work to those two objects.
- Beds 3 and 4 have **no established crop cycles**. Recorded plans are **not**
  evidence that those crops have actually been planted. No new crop cycles,
  growing objects, Person records, Work or source tasks are to be minted.
- Existing `work_item_context_links` supports spatial zones and places
  but not growing objects. This candidate extends that existing carrier,
  rather than creating a parallel Work↔bed database.

## Scope of code

1. Admit the **spatial/growing_object** kind in the existing context-link
   constraint. Existing kinds and event Work links remain admissible.
2. Add a guarded internal rule for newly linked growing objects. It checks
   a genuine signed current principal with *exact* native Ledger root
   authority, active Work allocation and state, exact organization/unit/farm,
   original source task/zone, real growing bed, active Ledger↔organization
   participation, and independent legacy-slice provenance where applicable.
3. Require an explicit, signed **farm crop-operations → one native Ledger** custody decision first. The old `zone.metadata` Flower annotation and mere Organization participation are source hints, NOT admissible boundary authorization. Use the new private custody carrier plus governor-only establish/end commands, recording a source-owned attestation; do not auto-bind or assume Flower based on a business name. Ending this crop custody must halt future link admissions. No row is auto-created by this migration.
4. Offer a **signed owner-only** review RPC for the existing candidate beds;
   the governor explicitly attests to the specific Work stable key and bed
   stable key before the idempotent establishment RPC writes the link.
5. The only new worker/physical link functions are a governor-only *preview* and
   *establish context* operation. Neither exposes data to ordinary connected
   People. No user obtains a Flower read/edit grant, Work allocation, or
   crop condition command. The Work context link is evidence for future
   permitted projections, **never itself an access grant**.

No Anna, Elm, U-Pick, Person UUID, farm/zone keys or Ledger IDs are
hardcoded in executable SQL. The two Ledgers share the same Elm Organization; this is why explicit separately established crop-domain Ledger custody is mandatory. The governor deliberately chooses each
source-proven bed. A title match alone is never establishment authority.

## Security stop gates before a usable worker view

- Existing farm `can_read_farm_operations` and `has_operations_membership`
  RLS readers depend on old farm-owner/manager credentials, not native
  Ledger permissions. Direct RLS, privileged RPC, search, index, exports,
  media and cached routes must be audited. A new filtered view does not
  retroactively make older routes safe.
- The parent task's legacy scope is **Beds 1–4** while the active allocation
  is specifically **Beds 3 + 4**. The source-row zone relationship cannot
  authorize the entire U-Pick zone nor Beds 1 and 2.
- Per the owner's overriding privacy decision, withheld records must be
  absent and non-enumerable (including result counts, errors, metadata,
  photos, zone lists and shared task titles), not displayed as restricted.
- Principal-reviewed **Flower-specific** grant/exclusion source and safe
  operational read projection are still missing and belong to the *next
  vertical component* of this same integrated build. Do **not** enable a
  worker-facing crop/bed reader or app button after just this migration.

## Tests and release discipline

Clone-only postconditions verify the crop-domain custody privacy and unsigned denial, canonical spatial admission, guard,
role privileges, unsigned denial, idempotent entry point and absence of
direct canonical grants. These tests are **not** signed principal/Anna/outsider
browser tests. Future signed positive/revoke/non-enumeration proofs remain
required before a governed read release.

Source path must pass custody CI, immutable generated migration, production-
shaped clone, explicit principal production release of an exact version,
then separate UI deployment. No real records should be linked by migration
without a separate authorized establishment decision.
