# Native Person completion-only release packet — HELD / no production approval

**Scope owner:** Noel `#2505`; Atlas-owned SQL structural release lane `atlas_`. **Owner choice on 2026-11-05:** release completion separately and keep historical cancellation source 16–22 held. This packet packages **only existing universal original Work lifecycle and three existing original Work writer cutovers**, not a new Work engine or the standing farm-care source.

## Immutable assembly and source provenance

The unversioned [candidate.sql](candidate.sql) is a source-locked SQL packet; `Git blob 49eab6550a001726faaadd8f8123c0b278ba8867` (66,562 bytes). It is reproduced exactly by `verify_release_packet.mjs --check` using the following reviewed owner-source Git blobs, in order:

| Order | Existing source | Git blob |
| --- | --- | --- |
| 1 | Current #2517 native-only `01_shadow_event_native_person_completion_only_held.sql` | `62e114eb2c2371450cca1a1ca851a9f2518b75f7` |
| 2 | #2368 `02_baseline_and_shadow_observers.sql` | `0ca69e0a604f43cf3eee442cb1edeb4ae6c1672b` |
| 3 | #2368 `03_shadow_projection_and_observers.sql` | `4113d95c1d8ae3b1161ca5a43e344100b6120c1b` |
| 4 | Current #2517 native-only `06_single_transition_native_person_completion_only_held.sql` | `3178e11863f1c6de89e07724c3b209923fd825d3` |
| 5 | derived `05_connected_person_compatibility_cutover.sql` | `b7b3cd83347d9aa1ec52d392d5983bc9345ab1cd` |
| 6 | #2368 `12_self_adopted_original_writer_single_done_cutover_candidate.sql` | `e6f6dd4367ad84b57ff0fb65915a9b8785e941b7` |
| 7 | derived `07_event_shared_response_compatibility_cutover.sql` | `7ea2a6acc4dde99c556b51e787614ba9b1073b51` |

The #2368 original held sources retain all their prior commits and have *not* been overwritten. This packet retains immutable copies of five original source files under `source_snapshot/` and derives the existing connected-Person and Event checklist writers' response projections in separate source files, and references the two native-only L1/L2 source files already staged under `../atlas_native_person_completion_only_v1/`. **Do not merge the history-bearing #2368 L2 instead.**

A source-locked, non-client `BEGIN;` to `COMMIT;` candidate follows the same order as the successful complete-only test for L1/02/03/L2. It takes SHARE ROW EXCLUSIVE locks across the five canonical original Work source tables, seeds **historical observations** of preexisting Work/Result/Acceptance/plan rows (not new Done or fabricated Actual), installs the original observer triggers and view, installs the private Person-only transition, and redirects current native Person work and shared Event writers through that same transition. The old self-adopted membership writer becomes a fail-closed compatibility function. Neither the public RPC signatures nor new permissions are broadened. The signed Event shared checklist response also preserves existing `resultId`, `acceptanceId`, `markedByPersonId` and `physicalPerformerAsserted:false`, from the SAME universal event, not a new Done. The signed connected-Person completed Result response continues to expose the existing `connected_person_company_work_result_v1` fields, including `resultId`, `resultKind`, `acceptanceDecision` and `reportMode`, while carrying the same `universal_work_lifecycle_transition_v1` receipt under `lifecycleReceipt`. Historical replay is labeled historical; this projection is not a second Done writer.

## What it explicitly excludes

- No test-only `auth.users`, fake farm Subject/Bed, source DML fixtures, 61 clone ACL-parity statements, or test canary. The new packet is **not** the 5,448-line signed diagnostic.
- No `atlas.historical_self_adoption_review_events_v1` table/admission, cancellation transition, governor historical retirement/preflight API, or historical replay of fabricated physical Results. All history 16–22 remains held in the original #2368 draft.
- No `record_continuing_care_actual_self_api_v1`, P1 manual Activity recognition bridge, standing Rhythm policy/admission, new original Work or automatic successor. Those require separately authorized source dependencies and release; their earlier full-composite signed P1 proof is **not evidence this narrower packet's three cutovers pass.**
- No canonical migration filename/version, changes in `supabase/migrations`, production SQL/roles/ACL/data, app UI changes, new employee membership, or source PR merge.

## Required release gates (still open until separately evidenced)

1. Static exact byte source/custody assertions plus PostgreSQL SQL grammar of `candidate.sql` and [postconditions.sql](postconditions.sql); **the structural postconditions are not signed authentication tests**.
2. Current production-schema/role **read-only** snapshot into **fresh disposable PG17/GoTrue/PostgREST**, the EXACT unversioned `candidate.sql` with no synthetic canary, no alternate production writer, and [postconditions.sql](postconditions.sql) (including seed parity/forced RLS/revoked direct EXECUTE/no historical cancellation). Record source bytes, lint baseline/candidate delta, cleanup and no real content exported.
3. Separate real signed owner/worker/outsider/no-seat/revoked actor matrix on **existing current native Work** (including partial/blocked and idempotent replay) and **shared Event** (no claimed performer), expressly forbidden legacy self-adoption Done; race behavior and root/subject disclosure, permission withdrawal. This is the **new proof not covered by the P1 manual-care signed PASS #42133589485**. Avoid creating a new public Done or bypassing existing writer authority.
4. Independently source-review the actual candidate migration and baseline lock/time cost; inspect the currently live existing writer signatures/trigger grants and return contract. Review any old writer incompatibilities before release; **do not resolve by revoking protections or silently dropping existing Work/history**. Verify rollback/repair separately.
5. After *all* gates, obtain explicit owner source approval to merge unversioned candidate onto canonical `main`; then use governed `Migration generation request: Atlas atlas_...` to generate a true versioned CLI migration, inspect generated file and protected schema-clone validation, and obtain a **distinct exact version/target production release authorization** through the protected workflow. **No such production authorization exists yet.**

## Evidence ledger

- Native-only L1/L2 signed disposable P1: [#42133589485](https://github.com/optical-lift/noel-core-db/actions/runs/42133589485) **PASS**, with frozen source #2517 head `5624beccdc1b60df4eb137431a6866e3ba88a56e`, baseline/candidate schema lint 14/14 (zero new), RLS, no historical review/retirement installed and clean shutdown.
- Existing complete+historical cancellation signed clone [#42126255334](https://github.com/optical-lift/noel-core-db/actions/runs/42126255334) is **not** acceptance of this packet.
- Original 64,057-byte packet [current-schema run #42137397979](https://github.com/optical-lift/noel-core-db/actions/runs/42137397979) **STRUCTURAL PASS only**, lint 14/14/0 introduced and cleanup confirmed. **It is immutable evidence for the previous packet blob, not for this newer compatibility-adjusted 66,562-byte packet.**
- An intervening 65,916-byte Person-only + original Result response candidate was pinned in [signed request #2526](https://github.com/optical-lift/noel-core-db/issues/2526); that immutable test does NOT include the newer shared Event compatibility projection in this 66,562-byte packet. Its evidence must not be relabeled.
- This updated packet's exact schema and genuine signed existing Work + separately signed Event checklist Done/denial/replay matrix: **NOT YET TESTED**.
- Atlas end-to-end Rulebook→original→Person/Today→Actual→one Done→later Need and P2–P5: **HELD**. No production release.

**Next bounded outcome:** validate unversioned source in full current-schema isolated clone and then genuine signed *existing writer* acceptance. Keep #2517 and this packet in draft pending those receipts. Governed release approval remains separate.
