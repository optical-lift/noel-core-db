# Atlas ONE Calendar — Live alternate Event-writer inventory (22 October 2026)

**Status:** read-only source/database audit. Not an authorized cutover, migration,
or repair of production data.

## Governing result

The released `atlas.set_ledger_occurrence_schedule_self_api_v1` is real.
It is deliberately a bounded `farm_shared` canonical Occurrence + operational
carrier writer under a signed root-governing native Ledger actor. The released
`aa_block_unowned_operational_event_retime_v1` prevents an operational row from
independently retiming ordinary operator-supplied Events. This does NOT yet
constitute a universal one-writer cutover.

## Confirmed live alternate carrier

`atlas.enforce_community_event_occurrence_binding_org_v1` is an enabled
`BEFORE INSERT OR UPDATE` trigger on `atlas.community_events`. On INSERT,
it can create/rebind one canonical `local_intel.occurrences` source for two
special provenance lanes:

- `network_outreach` (gated to the existing Elm-farm source path);
- `system_fixture` (when both farm and Event metadata assert fixture state).

On UPDATE it copies the operational title, status and local wall-clock time
back onto the canonical Occurrence for those two lanes, and advances the
canonical `updated_at` **even for unrelated updates**. Those special
writers remain exempt from the new ordinary operator-supplied retime guard
and are excluded by the new root-governed Event schedule command.

**Consequences:** A permitted special-lane operational update can still
change public canonical time without the same Event schedule decision receipt,
version check and affected-commitment preflight as the new command. A mere
visual Calendar deduplication cannot correct this authority split.

Current read-only census: 48 canonical occurrences are joined to
`atlas.community_events` through active Organization bindings; none of those
48 currently carries `metadata.atlasWriterAuthority` set to
`network_outreach` or `system_fixture`. This is not proof those paths
cannot create new data in the future; the live trigger is enabled.

## Additional triggers requiring effect analysis

Enabled on `atlas.community_events`:

- `sync_community_thursday_venue_cycle_v1`: after changed event kind,
  date, status or local times.
- `sync_elm_local_calendar_from_atlas_v1`: after insert/update/delete.
- `zz_sync_community_event_worker_identity_v1`: after changed relevant
  fields for the two established Thursday Event kinds.
- `enforce_community_event_occurrence_binding_org_v1`: pre-insert/update.
- `aa_block_unowned_operational_event_retime_v1`: pre-update of clocks.

Do not remove or disable any of these solely to make Calendar look unified.
Their dependent source effects, existing write callers and historic behavior
must be proven before the governing cutover.

## Next bounded writer-cutover proof

1. Trace the actual producer/caller and permitted principal for each
   special-lane INSERT, UPDATE, and independent canonical Occurrence write.
2. Separate Event-establishment authority from time-correction authority.
   An initial network-sourced Event may need a lawful canonicalization path
   without granting all future schedule edits to its original carrier.
3. Introduce typed source-lawful correction routing for those lanes, with
   signed actor/Source proof, CAS versions, timezone fold/gap rejection,
   immutable evidence, booking/resource dependencies, and idempotency.
   Do not force special lanes into the `farm_shared` root command until the
   actor/custody policy is established.
4. Make non-time operational changes leave canonical time/version untouched;
   a competing operational-time change without an authorized receipt must
   fail closed.
5. Protected clone tests must show all three writer families (ordinary
   operator, network outreach, system fixture), both INSERT and UPDATE,
   old/new source receipt/history, independent no-op updates, concurrent
   correction, exact Ledger root/member/outsider, another Organization,
   other Resource/Booking commitments and unchanged Event/Work IDs.
6. Release through canonical `noel-core-db` generation/clone/manual lane.
   Only after protected production readback may another reader or writer be
   retired.

**October 30:** the canonical Harvest Party time still requires
the already-authorized root source correction from 6–8 p.m. to 4–8 p.m.,
with the richer canonical record and separate confirmed 4–8 site claim
preserved. This audit does not change either row.
