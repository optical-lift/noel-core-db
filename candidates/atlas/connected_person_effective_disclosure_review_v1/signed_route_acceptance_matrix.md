# Gate 0 signed exposure and regression matrix — not an execution receipt

Tracks original Noel #2255, Atlas #437 and held draft PR #2263. Every case below is **UNRUN** until the reviewed SQL is staged in a protected disposable production-schema clone and tested via real independent GoTrue sessions and PostgREST. Database service role, token impersonation and SQL `SET ROLE` are *not* substitutes for signed-person tests.

## Deployed legacy route discovery

The Vercel project `farm-atlas` has a READY **production** deployment `dpl_8F5t2oDX5htfx4DFV8GCWqjhW7yr`, Git commit `7cfe87cfc6f5ea6a7eee161dd6226c5386a7ec5b`, and custom domain `atlas.elmfarm.co` attached. This establishes deployed code identity, not that the domain is receiving traffic or a signed worker has successfully accessed it.

The deployed commit was directly inspected for `zone-registry`, `farm-care`, `farm-snapshot`, `api-access` and `supabase/server`. The former handlers invoke their same-named SQL readers through a cookie-backed Supabase client with the publishable key; `requireAtlasApiAccess()` without `allowedRoles` checks a farm membership, not native Ledger information disclosure.

Current older GitHub main also has these source entrypoints:

| Older app GET route | SQL reader | Caller restriction | Gate status |
| --- | --- | --- | --- |
| `/api/atlas/zone-registry` | `zone_registry_source_v1` | active farm member | SQL source and deployed commit checked |
| `/api/atlas/farm-snapshot` | `farm_snapshot_for_member_v1` | active farm member | SQL source and deployed commit checked |
| `/api/atlas/farm-care` | `farm_care_summary_v1` | active farm member | SQL source and deployed commit checked |
| `/api/atlas/farm-care/zone?zoneKey=...` | `farm_care_zone_v1` | active farm member | SQL source and deployed commit checked |
| `/api/atlas/farm-care/object?objectKey=...` | `farm_care_object_v1` | active farm member | SQL source and deployed commit checked |
| `/api/atlas/objects/[objectKey]` | `object_workbench_v1` | active farm member | SQL source and deployed commit checked |
| `/api/atlas/grow-room` | `grow_room_state_v1` | active farm member | SQL source and deployed commit checked |
| `/api/atlas/task-bed-map?taskId=...` | `object_crop_bed_map_v1` | active farm member + legacy task/object read | SQL source and deployed commit checked |

These are source routes, **not proof of successful Anna GETs**. Full current Data API schema exposure, deployment routing, source aliases, notification/media/cache/search indirect pathways and signed runtime results remain unresolved.

## Mandatory fresh signed accounts

- Synthetic governor: canonical Person, active root-governor exact Flower native Ledger, verified nonanonymous GoTrue session, legacy farm owner where old reader owner-positive test requires it.
- Synthetic connected Person: separate canonical Person and Auth account, active native Flower Seat, legacy farm-hand role, **no crop publication decision**.
- Synthetic outsider: canonical Person unrelated to the Flower Ledger and farm, separate signed session.
- Additional different-Ledger governor/participant: proves cross-Ledger isolation, including same Organization but distinct Ledger.
- For manager compatibility, use a separate principal with a legitimate prior manager path, but no root governor, to confirm planned behavior and avoid conflating previous operational right with native-Ledger disclosure.
- Post-revocation retest the *same JWT* after actual GoTrue session removal, as well as ended Seat, ended authority and expired session.

## Release acceptance table

| Signed principal/action | Required observed outcome |
| --- | --- |
| Anonymous invoking public governor review | Uniform denial/no target identity |
| Connected Person invoking public governor review for their own target Seat | Uniform `not_found`, never a review |
| Different-Ledger governor querying the target Ledger | Uniform `not_found` |
| Root governor querying active native Ledger + canonical Person Seat | Only `verification_incomplete` shell (no target private records or inferred no-access certificate) |
| Root governor querying missing or unauthorized Person ID / ended Seat | Identical `not_found` response shape |
| Revoked signed governor session invoking same public review | Uniform `not_found`; old JWT must not suffice |
| Connected person directly calling each of eight old SQL RPCs | Denied after reviewed containment; no source data, guessed object IDs indistinguishable |
| Synthetic governor/legacy owner calls existing protected owner readers | Existing positive output preserved, subject to exact Ledger release review |
| Connected Person GET on deployed-style legacy farm entrypoints | No undisclosed areas, crops, objects, interventions, totals, histories, exports or private metadata |
| `universal_home_v1` called by connected Person | No full-farm snapshot/totals/last-movement leakage; **must still retain lawful individual Work experience** |
| Manager owner/worker compatibility after proposed narrowing | Explicitly adjudicated; no unexpected break of legitimate non-crop tasks or irreversible dependency |
| Different-Ledger or different-farm IDs passed to any read | Uniform no-disclosure result, no enumeration |
| Search, Index, Today, notification, asset/media, export, cache paths | Exact same subject+field exclusions and historical bounds as direct API |
| Split Bed 3 / Bed 4 Work | Two independent Work records with separate completion; original history/allocations and dependencies preserved; no accidental crop grant |

## Blocked by the currently staged source candidate

The **held** `legacy_farm_reader_body_containment_hold.sql` deliberately filters `universal_home_v1` full-farm entries to legacy farm owners. It can remove farm-hand home entries and legitimate worker task UI, and it does not yet replace them with a source-safe, individual-Work projection. Therefore it **must not deploy by itself**. Complete worker positive parity and cross-domain exposure boundary before owner-controlled migration generation.

The candidate also stages no native Ledger crop custody and no effective field-level permission review. A root governor's positive read access to eight legacy farm functions remains legacy authority, not new native Ledger consent. A complete release requires all reachable old and new routes to be source-enforced; a dashboard preview filter or source ACL alone cannot establish nondiscoverability.

## Verification provenance

- Static source guard CI and database source-custody CI: may pass, but are **not** signed HTTP/clone evidence.
- Protected production-shaped clone: **not run for this package**.
- Genuine signed GoTrue/PostgREST owner/connected/outsider/revoked casework: **not run for this package**.
- Vercel production deployed source inspection: performed, but no signed probe of live worker account performed.
- No production grant, data edit, migration, task decomposition, app release or credential changes authorized by this document.
