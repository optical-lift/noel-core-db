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

## Additional signed cutover gate — existing My Work bypass

The existing `public.connected_person_my_work_self_api_v1` is a
separate authenticated read from the new held exact-Ledger Work API. Its
live source returns `w.instructions` and Work titles even when
`workRelevanceVerified=false` on an otherwise eligible allocation.
`connected_person_my_work_existing_reader_cutover_hold.sql` is a
**held** replacement, not an applied patch.

| Independent signed case on disposable clone | Required actual result |
| --- | --- |
| True responsible allocation + exact verified Ledger relevance | Current My Work still returns the original Work A, its existing schedule and IDs; no invented personal Work |
| Active allocation but withdrawn exact Work-to-Ledger relevance | Current My Work and strict new reader both hide Work A **completely** (not merely disabling its action or labelling it unverified) |
| Worker with unassigned Work B under same Ledger | Both routes omit Work B title and source identity |
| Unapproved source instructions in original institutional Work | My Work does not return them; it preserves a nullable `instructions` slot until an approved Work-details source exists |
| Authentic active worker, same JWT after native Seat ends | No Work rows through either reader; still test the actual legacy Today/Worker Day alternate APIs |
| Authentic active worker, same JWT after real GoTrue session deletion | Both routes deny; old JWT signature by itself is insufficient |
| Governor positively approves exact Work details and instructions | **Held source candidate staged, not deployed**: signed source-value SHA-256 decision and separate approved-fields reader exist in PR #2263. Real worker-browser acceptance and full privacy audit remain UNRUN and mandatory BEFORE any cutover |
| Connected Person opens Index/Today/Event/legacy farm-atlas | **NOT YET PROVEN**. No route may return withheld source, Work or historical data by another path |

The work signed script now includes the original My Work public route,
synthetic active relevance deletion and GoTrue same-JWT revocation.
**Execution receipt: NOT RUN**. Clone-only files and scripts are test
assets, not a claim that live production security changed. Do not
silently reinterpret a new narrow reader's pass as complete route closure.

## Existing Person Today, dated Work and Worker Day alternate routes

The original native Person work entry points are not interchangeable.
Closing `connected_person_my_work_self_api_v1` does **not** close
these separately callable source-read functions.

| Existing public API | Verified current source-level carrier | Gate |
| --- | --- | --- |
| `connected_person_company_work_today_self_api_v1(integer)` | Original Work title, **instructions**, source type, original source UUID/date from active canonical Person allocation, but **without an explicit current Ledger connection or verified relevance filter** | `connected_person_today_existing_reader_cutover_hold.sql` and postconditions staged. Real signed current-Ledger and withdrawn-relevance tests UNRUN |
| `connected_person_company_work_day_self_api_v1(date)` | Original Work title, **instructions**, `taskClassification` from Work metadata, historical result/acceptance fields; filters by native connection but not verified Work relevance | Not fixed. Requires source-enforced exact relevance and separately approved details/history/identity fields without hiding lawfully completed Work |
| `company_work_worker_day_self_api_v1(date,integer)` | Legacy farm-hand membership and worker projection; **requiredWork instructions**, operating snapshot and other farm/delivery fields in result | Not fixed. Govern old farm source/dependencies with Worker Day positive-parity proof before narrowing or revoking access |

**Source findings are not proof of actual signed Anna HTTP reads.**
Run independent GoTrue owner, connected Person, same-organization
different-Ledger, outsider, ended-Seat and revoked-session scenarios
on a protected disposable clone. Test both current and historical
Work, original Work details, employer-era positive access and
interacting Index/Today routes. Confirm the source-owned writer can
show approved instructions, and any private Work/source fields are
unavailable through all these paths. New feature/permission controls
must not be released while the dated and Worker Day readers are
unclosed.

## Active and completed dated Work, legacy Worker Day cutover

These are signed tests and release conditions, **not test receipts**.
The native Person Day original reader is distinct from My Work's
all-date list and from the older farm-hand Worker Day.

| Source case | Acceptance outcome | Current evidence |
| --- | --- | --- |
| Current Person has a genuine signed standing Work A allocation, native Seat, source-proven Ledger relevance and an active plan | Dated Work returns that exact original Work, allocation ID, plan ID, exposure and execution dates; no Work B | New signed-clone script; UNRUN |
| Same User Date API, different signed outsider or same-organization unrelated Ledger | Work A entirely absent, no metadata, no title or UUID | New signed-clone script outsider; cross-Ledger separately UNRUN |
| Revoked native Seat with original GoTrue JWT retained | Original dated Work absent even if plan still exists | New signed-clone script; UNRUN |
| Exact source Work relevance removed, Work row/allocation/plan preserved | Original dated Work absent even if original plan remains | New signed-clone script; UNRUN |
| GoTrue session deleted with same signed JWT | Dated Work request denied despite unexpired JWT | New signed-clone script; UNRUN |
| Original Work completed with independently recorded result and accepted/declined source decision | Historical original Work, allocation, plan, result/acceptance **if and only if permitted by source field policy**; no false actor claim; no history erasure | **Not implemented yet**; live aggregate includes completed allocations but no signed receipt |
| Legacy farm-hand original Worker Day reads | New source-owned Worker Day/Person replacement retains all permitted task instructions and lawful results **before** old route is revoked | **Not implemented yet**; original source is still callable in production |
| Legacy Worker Day read, refresh, report and employee home after authorized cutover | All four old public routes deny authenticated/anon; indirect farm/definer routes independently tested | Held revoke/clone ACL files only, NOT DEPLOYED or SIGNED |
| Bed 3 and Bed 4 real-world acceptance | Independently assigned, instructed, completable Work; composite history preserved; no withheld crop, bed or other farm data in any path | NOT IMPLEMENTED OR VERIFIED |

Do **not** apply the held Worker Day revoke while the current worker
notebook still uses `EmployeeAccessClient`, nor apply the three
redacting source readers without a governor-authorized instructions
route. Static source CI does not prove field disclosure or practical
worker usability. Source row-count checks do not replace actual
signed-person result inspection.

## Governor-only preliminary exact Work field-review acceptance

This extends the *existing* root governor review candidate without
new user-facing permission or production scope.

| Synthetic signed principal / source | Required result |
| --- | --- |
| Root governor of Ledger A reviews canonical active target Person's Ledger A Seat after true native assignment of Work A | `preliminaryWorkFieldReview.items` shows Work A original ID and exact fictional `titleCandidate`/`instructionsCandidate` for adjudication; statuses `not_evaluated`, never implied granted |
| Same governor targets unrelated Work B not assigned to reviewed Person | No Work B in preliminary Work field-review candidates |
| Root governor targets Ledger B, for which they hold no root-governing authority | Uniform `not_found`; no other Ledger Work text |
| Governor targets unrelated canonical Person with no active Seat | Uniform `not_found` without Person existence confirmation |
| Connected Person reviews their own Seat | Uniform `not_found` even if they have Work A allocation |
| Independent outsider reviews the target Seat | Uniform `not_found` |
| Connected Person reads their ordinary My Work/Today/dated Work before governor field decision | Fictional private Work A title/instructions absent; after an exact title grant, title-only is visible; a separate current instructions grant is required to show those bytes |
| Governor reviews more than 50 verified original Work allocations | Capped first 50, `hasMoreCandidateWork=true`; source reviews remain incomplete |
| GoTrue session revoked while JWT unchanged | Governor review denied, no cached credential promotion |
| Existing source fields are unadjudicated, or any older reader is still reachable | `verification_incomplete` and `mayCertifyNonDisclosure=false`, no production permission release |

All above are **unrun** until a protected production-shaped
local clone exists. Source-only CI does not exercise PostgREST,
application routes or real independent signed sessions.

## Exact Work-field governor decision and revocation

All checks are designed for an isolated disposable full-schema
PostgREST + genuine GoTrue session test. **No signed run receipt exists.**

| Source condition | Expected signed result |
| --- | --- |
| Canonical Person with current Work assignment + native Seat + verified original relevance, but no field decision | No Work title through any of the four held Work readers; exact approved-fields reader responds `not_found`; original Work/assignment preserved |
| Root governor previews the assigned original Work | Candidate content plus exact SHA-256 for each source field, with `not_evaluated`; no false overall disclosure certification |
| Person/outsider invokes governor decision | `not_found`; no new permission event |
| Governor submits expected SHA-256 differing from current source | Fail closed; no new approval |
| Governor authorizes only Work title | Exact original Work becomes visible to signed worker; instructions absent from My Work, Today, dated Work, and exact approved-fields response |
| Governor separately authorizes instructions | Only original approved title/instructions available on exact Person + Work + Ledger; unrelated work/another Ledger/outsider receive no content |
| Work instructions edited after approval | Exact approved instruction stops appearing everywhere, `source_changed` in governor review; new SHA-256 approval required |
| Duplicate identical approval request ID | Original receipt is idempotent, no new event; reusing request ID for another field is denied |
| Governor revokes instructions but not title | Title remains, instructions stop appearing through every approved Work reader; event is appended |
| Governor revokes title after instructions revoked | Work entirely absent from listed Work readers; exact Work-field read `not_found`; no Work erased |
| Governor reapproves original title | Original Work returns; previous signed deny/allow events remain immutable |
| Seat ends, exact Work relevance withdrawn, or GoTrue session revoked with JWT retained | Entire Work content inaccessible on all four Work routes and exact approved-fields endpoint, without clearing original Work data |
| Historic completed Work with permitted result/acceptance fields | Original result and acceptance identity preserved; additional history-field authorizations not yet implemented or proven |
| Farm readers, old Worker Day, Index, Event, caches and media | Held until separately signed and source-audited; no reliance on application-hidden components |

The original `connected_person_work_field_decision_events_v1`
is **not a global permission table**: one Person, one original Work,
one native Ledger, one field, one governor-reviewed content hash,
independent last signed decision and automatic source invalidation.
