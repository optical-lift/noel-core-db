# Gate 0 / Gate 1 — Connected-Person Effective Disclosure (source review only)

**Current execution:** Noel #2255; Atlas #437. Existing owner decisions and exact native Ledger/Person identity are preserved. No duplicate permission authority, no new Seat, no production release.

## Current verified production check — 2026-10-25 (America/Chicago)

- Noel main: `d988ea816293b4b9a98a816679afefcbe6d732b6`. Atlas main: `7d9e4c61937a3455ab843cb3b25f96bc3343d724`.
- Source migration `20261026010327` is merged and **absent** from the live production migration ledger. Read-only native activation preflight `20261025234426` is present.
- `atlas.zone_registry_source_v1(uuid)`, `atlas.object_crop_bed_map_v1(uuid)`, and `atlas.farm_care_zone_v1(uuid,text,integer)` are postgres-owned SECURITY DEFINER with `authenticated EXECUTE=true`, `anon EXECUTE=false`. `authenticated` has USAGE on schema `atlas`.
- `zone_registry_source_v1`: active farm membership authorizes return of ALL zones (including metadata), growing objects and state, object contents, active crop-cycle registry, activity events for the farm. No exact Ledger/crop/work subject filtering.
- `object_crop_bed_map_v1`: an object ID can resolve ANY farm object; role `farm_hand` or `manager` (and farm owner) passes the access check; return includes physical geometry and all active crop placements for that object. No assigned-Work constraint.
- `farm_care_zone_v1`: farm-member-only gate; returns the named zone's care cards, object groups, released/planned intervention lists and bounded history. The limit is a row count, not an approved-history-permission boundary.
- No public-schema wrapper calling any of these three was found in the production `pg_proc` function-body reference search. This DOES NOT prove nonreachability via PostgREST exposed schemas, non-SQL callers or service connections. PostgreSQL's `pgrst.db_schemas` runtime setting and per-role settings did not establish API configuration.
- Secondary candidates include `farm_care_summary_v1`, `farm_care_object_v1`, `farm_snapshot_for_member_v1`, `object_workbench_v1`, `grow_room_state_v1`, farm continuity and crop-cycle state readers. Existing inventory is incomplete; not safe to report three-function remediation as complete.
- Production catalog: `atlas` has 986 SECURITY DEFINER functions with authenticated SQL EXECUTE; that count is an inventory bound, NOT 986 confirmed vulnerabilities. Specific reachability and scope must be tested by path.
- Original combined U-Pick Work still OPEN, with one active and one released allocation; zero `work_item_context_links` for that Work. Its source legacy task has one prerequisite execution component and no corresponding `work_execution_relations`. Both physical bed objects exist separately. No crop cycle may be inferred from task title.

## Gate 0 classification

| Route | Source-level scope | Actual signed Anna API reachability | Assessment |
| --- | --- | --- | --- |
| `zone_registry_source_v1` | Farm-wide; active member | Not tested | **overbroad if reachable; unverified exposure** |
| `object_crop_bed_map_v1` | Any object ID in qualifying farm; farm_hand permitted | Not tested | **overbroad if reachable; unverified exposure** |
| `farm_care_zone_v1` | Any farm zone by stable key; member permitted | Not tested | **overbroad if reachable; unverified exposure** |
| Additional definer farm readers | Source-specific, mixed farm-member/role gates | Not tested | **requires comprehensive inventory** |
| Direct RLS on native crop/zone source tables | Historical owner/manager guards documented in #2255 | Not independently signed here | **unverified signed deny** |
| Atlas notebook/Today/Index, server, search, exports, images/EXIF, cache, notifications | Multiple carriers | Not independently traced or tested | **unknown / no green** |

## Required source-enforced correction and stop boundary

1. Inventory all routable farm membership-era elevated SQL reads and writes, public/atlas RPCs, views, storage policies and application/server callers. Confirm PostgREST exposed schema configuration and direct URL reachability with genuine signed sessions.
2. Replace broad farm-member eligibility for connected-Person reads with exact native Ledger custody, canonical Person, approved source/local operation+subject/field scope, current Work/responsibility and governor exclusions. Do not map shared Organization membership to Flower crop information or Venue information.
3. Retire/revoke old directly callable farm-wide RPCs **in the same authorized release that preserves legitimate owner access through new scoped source readers**. A standalone revoke before examining callers could break valid operations; a UI-only filter would fail security. Parent SECURITY DEFINER functions may still call private helpers, so ACL changes alone are not proof.
4. Test independent signed governor, connected Person, outsider, revoked Session/Seat and a second unrelated Ledger. Forbidden and nonexistent must be indistinguishable; test UUID guessing, search, histories, media metadata and stale cache.
5. Hold crop/Work migration `20261026010327`, individual physical links, new data grants, real Work split and app cutover until their separate source/custody/security and explicit release gates are satisfied.

## Gate 1 candidate in this folder

`candidate.sql` is the minimal **read-only root-governor / active target Seat access-review membrane**. It proves no actual field grant. It explicitly returns `verification_incomplete` and `mayCertifyNonDisclosure=false`, exposing neither hidden target data to the connected Person nor an invented “no access” conclusion. No role or Seat is permitted to generate information authority.

`postconditions.sql` checks the internal-vs-public API execution envelope only. The candidate is **not** a full current effective access inventory, permission writer, or preview service. That requires the Gate 0 source mapping and real signed evidence before activation. No release of this candidate is authorized.

## Source protections

Never embed actual Person data, production user identities, private notes or test credentials in public SQL. Never simulate signed independent proof through a service role. This source branch is not a deployment or a signed-acceptance receipt.

## Coupled source-reader containment (held, not releasable by itself)

`legacy_farm_reader_body_containment_hold.sql` stages exact current source bodies for the original three readers, the inherited `farm_snapshot_for_member_v1`, and `universal_home_v1`. The contained readers replace farm-member/farm-hand-wide gates with transitional farm-owner-only checks, give missing and unauthorized bed IDs the same error class, and revoke direct browser SQL execution of the four named read helpers. `universal_home_v1` must filter its farm loop to owners in the same candidate so an ordinary farm-hand home does not call the newly guarded snapshot and fail. The legacy home remains SQL-executable only for compatibility and is NOT claimed to be exact-Ledger scoped.

This is a **temporary source risk containment proposal only**, not a completed crop/Work entitlement model: a legacy farm owner is not equivalent to the root governor for a specific native Ledger; `universal_home_v1` may still disclose organization or project information via other source paths; other farm-care/grow-room/continuity readers and write operations remain broader than needed. Worker home disappearance/replacement and legitimate owner path parity must be independently tested before release. SQL signature preservation and replacement-body comparison are required. `legacy_farm_reader_postconditions_hold.sql` provides structural checks, not signed-user proof. The earlier redundant direct-only candidate was withdrawn from this branch to maintain a single containment proposal.

**Observed alternate SQL caller:** `atlas.universal_home_v1` invokes `atlas.farm_snapshot_for_member_v1` from its active membership loop; this is a proven indirect SQL path, not proof of signed Anna API/browser invocation. Farm-wide `totalBeds`, `growingBeds`, `activeSqft`, sowings, stems and farm activity could reveal withheld operational existence, even as aggregates. No matching requests to the named RPC paths appeared in the accessible 24-hour edge-log aggregate; that is not proof of no reachable path.


## Source-preserving two-subject Work decomposition inspection

- `atlas.work_execution_components` and `work_execution_relations` are anchored to legacy `tasks` or `planned_work_occurrences`, **not** independently completable canonical Work items. The relevant old U-Pick task has one prerequisite component and no relation rows; neither table alone solves Bed 3 / Bed 4 independent completion.
- Reuse canonical `atlas.work_item_relations` with established `part_of` semantics (child Work → original composite Work) for multiple distinct children. `work_items.superseded_by_work_item_id` points to **only one** successor and cannot by itself preserve a one-to-two split. Do not mark original composite complete or drop its allocations/results.
- `work_item_context_links` on live production currently checks spatial subjects `zone` or `place`, not `growing_object`. Unreleased `20261026010327` supplies the guarded `growing_object` relation. It still does not create either child Work or establish crop custody. Therefore real per-bed Work decomposition remains gated, not implemented by adding UI subrows.
- The eventual source governor command must verify original Work open and source-proven task slice, exact Ledger crop custody, exact distinct existing bed IDs in the source zone, current allocation and prerequisites; create two independent canonical Work identities/results idempotently; preserve old Work via two `part_of` links; and require separate signed authority for assignments and any bed-read grant. Test repeat, mismatch, concurrent split, outsider, revoked and cross-Ledger denial on a protected clone before executing against real records.

## Reproducible live SQL inventory — additional checkpoint

`gate0_reader_inventory_readonly.sql` was checked by executing its two SELECT queries on the real database without changing state. It returned **106** definer functions matching the focused syntax/call patterns, **65** with authenticated SQL EXECUTE and **zero** with anonymous SQL EXECUTE within that subset. These numbers classify *audit candidates*, not vulnerable functions or exposed API paths. SQL metadata does not establish actual HTTP reachability or source-safe result fields. The current Supabase security advisor separately flags five named functions above as authenticated SECURITY DEFINER executable; this advisor is likewise not a signed-Anna end-to-end proof.

The seven inspected farm read tables `zones`, `growing_objects`, `crop_cycles`, `crop_observations`, `object_contents`, `object_activity_events`, and `care_state_history` have enabled RLS and authenticated SELECT granted; their actual SELECT policies all use `atlas.can_read_farm_operations(farm_id)`, which checks legacy farm role `owner` or `manager` only. This does **not** establish a per-Ledger or per-Work information limit for owners/managers. It does mean an ordinary farm hand does not obtain a direct RLS SELECT on those tables from their role alone. Definer functions are a separate, potentially broader data route.

**One confirmed SQL indirect pathway** is `atlas.universal_home_v1` → `atlas.farm_snapshot_for_member_v1`. The snapshot reads all farm growing-object/content/activity counts and quantities under a farm-membership gate. One connected Person's authorized subset cannot be determined from those totals. The held source-body candidate couples the home and snapshot changes to avoid raising a failure on ordinary farm-hand home loads. More indirect work/home calls and actual app routes remain unclassified.

### No certification criteria met by the held containment candidate

It does not establish current native-Ledger grants/exclusions; farm owner is still legacy authority; it does not close every `farm_care_summary`, `farm_care_object`, `grow_room_state`, continuity or task-context operation; does not prove signed Anna HTTP visibility or denial; does not replace worker home with authorized Work/bed source projections; and does not run through a disposable production-schema clone. **No green flag, migration generation, source merge, release or app handoff may be inferred** from source-custody CI alone.
