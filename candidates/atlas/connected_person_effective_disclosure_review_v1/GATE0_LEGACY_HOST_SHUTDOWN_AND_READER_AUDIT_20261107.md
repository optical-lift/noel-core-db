# Gate 0 — legacy hosting retired; current callable reader audit (2026-11-07)

**Owner scope:** Noel #2255, Atlas #437, **existing held PR #2263**. This is a source and metadata checkpoint only. It does not grant information access, alter a table, revoke any current route, represent a signed-account proof, approve a migration, or authorize an Atlas deployment.

## Verified external carrier change

The owner intentionally deleted the **old Vercel `farm-atlas` project**, which had served `atlas.elmfarm.co`. The Vercel project lookup for exact project `prj_ppP8y06TilUlHOtTLhQjM7hSedh6` now returns **404 not_found** and the same team's project search `farm-atlas` returns **zero projects**. No further old-app Vercel project or deployment URL should be considered an active service. This verifies project deletion, not outside DNS propagation or every prior cache/third-party copy.

The **different, current** Vercel project `atlas` (project `prj_wrdlBPKApkT9R4D3MfO0MYEcQFIz`) still exists with the user-accepted protected production deployment `dpl_DuLksPX6Ue3V2CzjhiSD86Rw16b8`, source `da568fa1b58deee048390b909664ccfe14a347d2`, and domain **`atlas.opticallift.com`**. The old GitHub `optical-lift/farm-atlas` source repository remains for provenance and historical route review; the owner did not request source deletion. It must not be deployed again casually.

The historical `signed_route_acceptance_matrix.md` and earlier README sections accurately record what was deployed **at their own dates**. Their claim that the older host was READY is **superseded for current hosting**, not evidence that it still serves. Do not rewrite history.

## The database is separate from Vercel

Independent **read-only** production Supabase catalog checks on project `zirqkouammpwxlqfbsvf` confirmed:

| Source family | Current native/API facts | What this does **not** prove |
| --- | --- | --- |
| Eight old Farm-source readers: zone registry, object/Bed map, farm-care zone/summary/object, Farm snapshot, object workbench, grow-room state | Named `atlas` SECURITY DEFINER functions still exist and have `authenticated` SQL EXECUTE and schema USAGE privileges | Direct PostgREST exposure, actual caller reachability, safe field scope, or actual signed Farm-hand reads |
| `atlas.universal_home_v1` | Still an authenticated-EXECUTE SECURITY DEFINER function with legacy membership selection; prior source evidence shows it calls Farm snapshot | That any given signed Person can retrieve full-Farm data today |
| Current native Person My Work, Today, dated Work | The three `public` endpoints are still SQL-executable as authenticated. Their `atlas` implementations mention instructions, but current exact native-Ledger relevance checks vary; the held cutovers in PR #2263 are **not installed** | That the `public` wrapper has permitted an unauthorized field to a specific signed Person |
| Legacy Company Worker Day and its refresh, employee home, worker result/report | Corresponding `public` endpoints remain authenticated SQL-executable. Their internal `atlas` implementations remain tied in varying degrees to older farm membership and/or Work projection | That breaking these endpoints is safe without first preserving actual worker Work, reporting and historical result behavior |
| New narrow Work-field approval decisions | `atlas.connected_person_work_field_decision_events_v1` and the approved-fields/governor-decision public endpoints are **absent** from production | That a visible UI checkbox or a current Work allocation is an approved private-field grant |
| Current Farm custody and Work→Bed | Released migration `20261026010327` **present**; the owner-confirmed Elm Flower custody and two real U-Pick physical `acts_on` associations were separately verified by the prior bounded app release | That connected workers now have crop access or that two Bed contexts are two independently completable Work items |

The repeatable focused query `production_alternate_reader_catalog_readonly_20261107.sql` returns only function names, signatures, privilege flags, coarse **textual marker** booleans, RLS/ACL, candidate installation and aggregate Work counts. It intentionally does not output private Work text, real identities, tokens, sessions or source field values. A keyword marker such as `mentions_exact_work_source=false` is **not** a proof that other called helpers fail to enforce it; an `authenticated_execute=true` privilege is **not** a signed HTTP result.

The old HTTP app retirement and the continued **SQL-level** callable reader inventory are two different statuses. Do not declare Gate 0 disclosure closed merely because the old app disappeared.

## Current audit decision and nearest gate

**Completed now:** Legacy Vercel project absence; current Atlas still serving; source and privilege census of named alternate readers; known released custody migration; one read-only reproducible SQL audit; recognition that prior `farm-atlas` route GETs are no longer hosted by that Vercel project.

**Held now:** Cross-caller reachability, PostgREST exposed schemas, old SQL definer chaining, current Atlas Index/Today/Event paths, storage/media/cache/export/search, and the actual result sets for independent signed owner, connected Person, unrelated Ledger, outsider, ended Seat, revoked JWT, and authorized positive worker scenarios. Neither `SET ROLE`, service-role impersonation, SQL `EXECUTE` grants, nor a no-network static check substitutes for these.

**Next bounded implementation:** Reuse the held native Work-field and My Work/Today/dated-reader source candidates under **the same PR #2263**, and obtain a **protected production-schema disposable clone with real local GoTrue/PostgREST signed sessions** before considering source cutover. Include the remaining old Worker Day and `universal_home_v1` carriers and positive existing worker functionality in that clone. Retire/replace callable legacy routes only **together** with a proven source-safe replacement; do not simply revoke them and break lawful worker Work.

The following are **explicitly excluded from this audit increment**: creating employees or permissions, granting crop/zone/Work private fields, direct SQL migration or privilege edits, production data mutations, additional app releases, new Work assignment, splitting U-Pick Bed 3 and Bed 4 into new Work, or equating their already-established two physical associations with independent Work completion.

### Evidence ledger (source provenance)

- Exact former Vercel project `prj_ppP8y06TilUlHOtTLhQjM7hSedh6`: project GET 404, team search count 0 after owner deletion.
- Exact current Vercel project `prj_wrdlBPKApkT9R4D3MfO0MYEcQFIz`: successful project GET, current production deployment and `atlas.opticallift.com` unchanged.
- Source historical former hosting: `optical-lift/farm-atlas` deployment commit `7cfe87cfc6f5ea6a7eee161dd6226c5386a7ec5b`, eight inspected `app/api/atlas/**` GET routes invoked native SQL through membership-gated server client; **no longer a current Vercel serving claim**.
- Source current access review: `optical-lift/noel-core-db` draft PR #2263, fixed initial exact candidate `44170ea848810a165f1f9e8d2ddd3be1f9349314`, prior Gate 0 source checks only; no signed full-schema clone receipt for this candidate.
- Query: `production_alternate_reader_catalog_readonly_20261107.sql` and corresponding live read-only catalog census, observed on 2026-11-07. Do not mistake query text for a signed execution trace.
