# Native Person completion-only release packet — HELD / no production approval

**Scope owner:** Noel `#2505`; Atlas-owned SQL structural release lane `atlas_`. **Owner choice on 2026-11-05:** release completion separately and keep historical cancellation source 16–22 held. This packet packages **only existing universal original Work lifecycle and three existing original Work writer cutovers**, not a new Work engine or the standing farm-care source.

## Immutable assembly and source provenance

The unversioned [candidate.sql](candidate.sql) is 1,314 SQL lines before final newline; `Git blob 2ee49072aee9e6d7ab9180c21ce8463f7e713994` (66,571 bytes). It is reproduced exactly by `verify_release_packet.mjs --check` using the following reviewed owner-source Git blobs, in order:

| Order | Existing source | Git blob |
| --- | --- | --- |
| 1 | Current #2517 native-only `01_shadow_event_native_person_completion_only_held.sql` | `62e114eb2c2371450cca1a1ca851a9f2518b75f7` |
| 2 | #2368 `02_baseline_and_shadow_observers.sql` | `0ca69e0a604f43cf3eee442cb1edeb4ae6c1672b` |
| 3 | #2368 `03_shadow_projection_and_observers.sql` | `4113d95c1d8ae3b1161ca5a43e344100b6120c1b` |
| 4 | Current #2517 native-only `06_single_transition_native_person_completion_only_held.sql` | `3178e11863f1c6de89e07724c3b209923fd825d3` |
| 5 | The current native connected-Person reporter compatibility derivative `10_connected_person_result_writer_single_done_receipt_compat_held.sql` (from #2368 `10`); preserves `resultId`/`resultKind` and embeds the one lifecycle Done receipt | `8ef030b100e983f36fb7c59217a193876527a720` |
| 6 | #2368 `12_self_adopted_original_writer_single_done_cutover_candidate.sql` | `e6f6dd4367ad84b57ff0fb65915a9b8785e941b7` |
| 7 | #2368 `14_event_shared_original_writer_single_done_cutover_candidate.sql` | `8f24ee85ffa841b8d1ab91da2289365d1713bec3` |

The #2368 original held sources retain all their prior commits and have *not* been overwritten. This packet stores immutable copies of five exact source files under `source_snapshot/`, and references the two native-only L1/L2 source files already staged under `../atlas_native_person_completion_only_v1/`. **Do not merge the history-bearing #2368 L2 instead.**

The #2368 original 10 writer remains byte-verbatim under `source_snapshot/10_connected_person_result_writer_single_done_cutover_candidate.sql`; the new **derived** `10_connected_person_result_writer_single_done_receipt_compat_held.sql` changes only its completed, same-action replay and pre-cutover accepted-history return projections. Both successful and replayed current completions return the pre-existing public `connected_person_company_work_result_v1` fields including `resultId` and `resultKind`, plus a nested `oneLifecycleDone` receipt from the **same** private one-event lifecycle writer. Historical accepted source returns `historicalRecordedCompletion=true`, `newTransitionApplied=false`, without inventing a new Done. Underlying Work/Result/Acceptance/Person authority SQL remains unchanged. **This correction is NOT yet independently signed-tested or production-approved.**

A source-locked, non-client `BEGIN;` to `COMMIT;` candidate follows the same order as the successful complete-only test for L1/02/03/L2. It takes SHARE ROW EXCLUSIVE locks across the five canonical original Work source tables, seeds **historical observations** of preexisting Work/Result/Acceptance/plan rows (not new Done or fabricated Actual), installs the original observer triggers and view, installs the private Person-only transition, and redirects current native Person work and shared Event writers through that same transition. The old self-adopted membership writer becomes a fail-closed compatibility function. Neither the public RPC signatures nor new permissions are broadened.

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
- Clean original packet before compatibility adjustment: current-schema structural [run #42137397979](https://github.com/optical-lift/noel-core-db/actions/runs/42137397979) **PASS**, with **0 seeded Work rows**, 14 baseline/14 candidate/0 new lint and clean shutdown. This is NOT evidence for this newly modified compatibility-pinned version.
- This compatibility-pinned packet’s standalone writer cutover/runtime matrix: **NOT YET TESTED**.
- Atlas end-to-end Rulebook→original→Person/Today→Actual→one Done→later Need and P2–P5: **HELD**. No production release.

**Next bounded outcome:** validate unversioned source in full current-schema isolated clone and then genuine signed *existing writer* acceptance. Keep #2517 and this packet in draft pending those receipts. Governed release approval remains separate.
