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

## Strict connected Person individual Work reader — staged, not deployed

`connected_person_work_read_candidate.sql` and its `connected_person_work_read_postconditions.sql` add a **source-owning read path**, not a new Work engine or new permission table. It reuses native `ledger.seats`, canonical `reality.entities`, the active signed `reality_access_self_api_v1` membrane, original `work_items` and `work_allocations`, `person_has_native_ledger_connection_v1`, and `company_work_native_ledger_relevance` with exact evidence checks. A real allocation is a *necessary but not sufficient* condition; active exact-Ledger Work attribution must also be proven.

- Output is bounded, paginated, and only for **open original Work allocated responsibly to the signed Person under that same active native Ledger**.
- Includes Work identifier, allocation ID, exact Ledger ID, original Work title, Work state and ordinary completion capability. The original Work title is treated as text intentionally communicated by an explicit assignment; **the release must verify Work titles do not contain source fields the governor excluded**.
- No instructions, crop/bed/zone records, source-object UUIDs, historical observations, private metadata, attachments, project descriptions or farm-wide totals. No write operation, no completion event, no new Person, Seat, grant or Work row.
- Separately owns an ACL for a public authenticated bridge. The private `atlas` helper is not directly executable by ordinary authenticated or anonymous roles.
- Explicitly returns `permissionAuditComplete:false`; it **does not** implement the full effective disclosure decision inventory or make all other legacy routes safe.
- A direct Work title/ID read still requires checking the legacy notebook's pre-existing Work readers for bypasses. These must be retired/replaced in the same approved secure cutover; do not claim a new safe RPC protects every old reader.
- The old full-farm home containment would remove legacy farm-hand home task projections before the new notebook is wired. Positive worker experience and source security must ship together.

`scripts/validate-atlas-connected-person-work-signed-http.py` reuses the **existing** C1 synthetic native standing Work fixture `validation/fixtures/20261024231215_shared_native_ledger_standing_work_person_only_v1.sql`, the actual local signed Work proposal/accept/assignment utilities, and adds disposable `personal.atlases` for synthetic People. It checks genuine independent worker/owner/outsider/no-seat sessions; wrong Ledger, unassigned Work, withheld source/title, active native Seat, ended Seat, retained-JWT revoked-session, and absence of employee memberships. The script **refuses nonlocal database URLs**. Source CI only compiles it; it has **not run** against an appropriately staged protected schema clone. Required future clone package must include the source candidate, strict postconditions and fixture; do not report a signed PASS before that run is actually observed.

The active protected clone/release contract uses an exact reviewed migration identity. No replacement version was generated, no candidate was merged and no production access was widened in this iteration.

## Held cutover of the existing public My Work reader (2026-10-26)

The original `public.connected_person_my_work_self_api_v1(integer,uuid)`
is ALREADY callable by `authenticated` via its private
`atlas.connected_person_my_work_self_api_v1` implementation. The live
implementation returns original institutional Work titles and instructions
for active canonical-Person allocations with a native Ledger connection.
It **calculates** `workRelevanceVerified`, but does not require that
exact-Ledger relevance to be true to return the Work. It checks
`auth.uid()`, but does not itself call the live GoTrue-session gate.

- `connected_person_my_work_existing_reader_cutover_hold.sql` stages a
  **same-signature replacement of only the current private implementation**.
  It adds the existing `reality_access_self_api_v1` live-session/Person
  membrane, converts verified Work relevance from a diagnostic flag into
  an actual eligible-row predicate, and retains the original pagination
  and current `connected_person_my_work_v1` output contract. It returns
  `instructions:null` pending a separately source-approved exact-Work
  instruction/details projection. It does **not** modify the existing
  public wrapper or grant more access.
- `connected_person_my_work_existing_reader_cutover_postconditions_hold.sql`
  checks the exact function/bridge ACL, authenticated route, session and
  relevance predicate and NULL instruction projection on a protected clone.
- The existing `scripts/validate-atlas-connected-person-work-signed-http.py`
  now also exercises the **currently shipped public My Work API**.
  After source-authorized synthetic standing assignment, a distinct signed
  worker must see correct Work A (but not unassigned Work B), with no
  unreviewed instructions. After exact relevance is deleted **in the
  disposable fixture only**, the same JWT must not retrieve Work A on
  either the narrow new API or old My Work API. Deleting the underlying
  GoTrue session must deny the original API even with a previously valid
  JWT. This is a real signed test design, but it has **NOT been run**.

**Important positive-parity stop:** This candidate intentionally
sacrifices instructions in the old list until a separately approved
original-Work details/instruction disclosure authority exists. It is
**NOT releasable standalone**: workers still need permitted instructions
to complete the independently linked Bed 3 and Bed 4 Work. Original Work
titles also require disclosure review; exact relevance/assignment is not
blanket authorization to every field embedded in a title.

**Important negative-route stop:** This closes no Event/attention Work
reader, original Today day reader, old farm-atlas GET route, search, media,
notification, historical export or Event notes access by itself. Source
closures and positive worker parity must release together. The only
Supabase branch currently visible for the project is `main`; no
cost-incurring protected branch has been created or used. No production
SQL, grants, real Work, task splits, migration or Vercel deployment
changed from this patch. The earlier owner-reported RiverSong PASS
applies to Atlas PR #442, not this unexecuted Noel clone package.

## Additional held cutover of the existing connected Person Today reader

A new **read-only catalog comparison** showed that shipped
`public.connected_person_company_work_today_self_api_v1(integer)`
still delegates to `atlas.connected_person_company_work_today_self_api_v1`.
The internal reader returns `w.title`, `w.instructions`,
`w.source_object_type`, `w.source_object_id` and a source date to a
canonical Person holding an active Work allocation. Unlike the existing
My Work list, this implementation **does not itself require a current
native Ledger Seat / connection or verified Work-to-Ledger relevance**.
It only checks `auth.uid()` and resolved canonical Person and has no
live GoTrue-session recheck.

- `connected_person_today_existing_reader_cutover_hold.sql` is a
  source-preserving **same-signature** held replacement that adds the
  current signed-session membrane; requires exact active native Ledger
  connection **and** verified original Work relevance via the existing
  `company_work_native_ledger_relevance` and exact-source validator.
  It excludes legacy membership-assigned Work. It preserves the
  original `connected_person_company_work_today_v1` response shape but
  projects `instructions`, `sourceType`, `sourceId`, `sourceDate`
  as NULL rather than revealing unapproved underlying Work metadata.
- `connected_person_today_existing_reader_cutover_postconditions_hold.sql`
  adds protected-clone structural/ACL checks. The existing synthetic
  signed-work script now asserts real Work A remains, irrelevant Work B
  is absent, ended Seat removes visibility, removed Work relevance
  removes visibility, and a removed GoTrue session invalidates the
  retained same JWT. All these tests **remain UNRUN on a clone**.
- Like the My Work candidate, this is **not permission to ship an
  instructions-less notebook**. Implement the approved exact-Work
  instructions/details disclosure source and test positive worker
  task completion before releasing either reader. Work title content
  itself still needs governor disclosure adjudication.

The **dated** `public.connected_person_company_work_day_self_api_v1(date)`
is another existing public route: the internal source enforces a
native Ledger connection but returns `w.instructions`,
`w.metadata` classification, Work result/acceptance fields and dates,
and does not require a verified Work-to-Ledger relevance row or check
the live GoTrue session itself. The separate
`public.company_work_worker_day_self_api_v1(date,integer)` returns
frozen Work instructions and operating snapshots through legacy farm
membership. These two readers are **unclosed alternate exposure routes**
and cannot be ignored or merely hidden by React.

No application, live source, migration, grant, real Work, old
Worker Day implementation or deployed domain was changed by the held
Today candidate. Protected-clone signed positive/negative and rollback
receipts are absent; production remains HOLD.

## Held dated-Work source cutover and coordinated Worker Day retirement

A 2026-10-26 **read-only live SQL function audit** inspected
`atlas.connected_person_company_work_day_self_api_v1(date)` and the
distinct older Worker Day read, refresh and report APIs. The existing
dated Work reader checks signed Person identity, current native Ledger
connection and original allocation, but it does **not** require
verified original Work-to-Ledger relevance, independently check live
GoTrue session status or grant Work instruction and metadata fields.
It also carries **completed original Work** with source results and
acceptance evidence; unlike an all-open-Work list this history cannot be
discarded without separate adjudication.

- `connected_person_dated_work_existing_reader_cutover_hold.sql`
  is a **source-only, same-signature, UNAPPLIED** replacement that
  requires the existing `reality_access_self_api_v1` active session
  and canonical Person check, exact active native Ledger connection,
  and original `company_work_native_ledger_relevance` with attested or
  independently verified exact-source evidence. It retains the
  original Work, allocation, plan, completion/result and acceptance
  identities and JSON contract, but returns NULL for unapproved
  instructions and work-metadata classification pending distinct field
  decisions. Work title and result/acceptance fields still need
  the governor's explicit approved disclosure policy.
- `connected_person_dated_work_existing_reader_cutover_postconditions_hold.sql`
  is a protected-clone structural guard for source predicate, existing
  wrapper ACL, historical completion fields and withheld text.
- The existing genuine-signed local clone script now uses the original
  `connected_person_place_work_self_api_v1` to place an assigned
  synthetic Work A on a real synthetic day, then reads the *original
  dated Work API*. It checks positive Work/plan/allocation identity,
  exclusion of unassigned Work B, NULL instructions/classification,
  outsider denial, ended Seat denial, Work relevance withdrawal denial,
  and revoked same-GoTrue-session JWT denial. **This expanded signed
  script has not been run on a protected clone**. Completed-item
  acceptance/readback still needs its own positive historic case.

Read-only production aggregate evidence (no Personal names or IDs
returned): active Person-native allocations currently include 22
open and 2 completed Work allocations, each with at least one
verified exact native Ledger relevance row. This supports **planning
the historical positive test only**, not general authorization or proof
that all fields can be shown.

The distinct older Worker Day source reads all stored projection
`requiredWork` instructions, the frozen operating instruction snapshot,
delivery payload and related farm membership information for the
legacy farm-hand path. The reachable related public APIs include
`company_work_worker_day_self_api_v1`,
`company_work_worker_day_refresh_self_api_v1`,
`worker_report_company_work_projection_self_api_v1`, and
`company_work_employee_home_self_api_v1`. A UI-hide is not revocation;
only revoking the read would still leave a separate refresh/report or
home carrier. Their historical functionality and valid worker source
results must be carried forward before old paths can retire.

`legacy_worker_day_public_route_retirement_hold.sql` is therefore an
**explicit, coordinated, non-deployable ACL retirement proposal** for
all four public and internal SQL routes. It is intentionally not
released: it will break the older EmployeeAccessClient and original
Worker Day action paths until actual Person-native Work/instruction,
planning and reporting parity is accepted. The matching
`legacy_worker_day_public_route_retirement_postconditions_hold.sql`
checks `authenticated`/`anon` ACL denials on a disposable clone but
cannot certify another definer wrapper, old Vercel GET endpoint,
service-role backend, or stored snapshot route is inaccessible.

A native Ledger Seat is a connection, **not automatically a Work detail
or crop permission**. Current source metadata searches found no
verified universal per-Work field-disclosure grant that can be reused
without review. A source-bound, append-only exact Work-field decision
table is now **staged in this same draft PR**, rather than repurposing
an employee-membership grant. Its live signed authorization,
a positive worker end-to-end read/Done receipt, and complete
alternate-route exposure tests remain mandatory. In particular, a deliberately redacted instructions list
must **never** be treated as production-ready for Anna's distinct
Bed 3 and Bed 4 Work.

**Release sequencing remains coupled:** check original source and
worker-positive parity; review field grants; stage on disposable
full-schema clone; run actual independent signed/governor/worker,
outsider/same-organization different-Ledger, past participant, ended
Seat and revoked-session tests; verify Legacy Farm, Index, Event, Today
and history bypass closure; only then prepare authorized release and
rollback. No production schema, grants, app, Work or user data changed.

## Governor field-review inputs (held; not a permission decision)

The existing `candidate.sql` governor-only
`connected_person_effective_disclosure_review_self_api_v1(uuid,uuid)`
now includes a bounded `preliminaryWorkFieldReview` section *after* its
existing real-session, exact root-governing principal, and canonical
active target Ledger Seat guards. This was added to the original
unfinished Effective Disclosure Review; it is NOT a new authorization
system or a parallel permission API.

It identifies **up to 50** original active or completed Work allocations
for the exact canonical Person and Ledger, and only when the existing
source-relevance record is active and owner/participant attested or
source verified against `company_work_native_ledger_exact_source_v1`.
The governor can inspect exact `titleCandidate` and
`instructionsCandidate` from the Work record and select which fields
still need to be adjudicated. The JSON initially labels each field `not_evaluated` and, once
the held decisions component is installed on a clone, derives
`approved`, `denied`, `expired` or `source_changed` from the
latest source-bound decision. It provides `hasMoreCandidateWork`
when the preview has more than 50 candidates, and marks each candidate
`candidateIsNotAnEffectiveDisclosureGrant:true`. No farm crop/zone/
history/attachment record is joined into this field preview.

This is NOT a list of what the Person currently sees. In particular:
`verificationStatus` remains `verification_incomplete`;
`mayCertifyNonDisclosure` remains false; the governor's preview itself creates no grants or exclusions;
the **separate, unreleased Work-field writer and approved-fields reader**
now exist only as draft SQL candidates; `effectiveExposure.actualReadableFields`
remains NULL. No work title or instruction is newly visible to a live
connected Person.
The governor sees source text as **decision input only**.

The protected-clone `postconditions.sql` and static source validator
now check the role/session guards, original Ledger-relevance filter,
bounded 51-row inspection, and lack of permission certification.
The genuine GoTrue synthetic signed test now places a fictional
private Work instruction into the **disposable clone**, asserts the
root governor's review sees the exact candidate and no false
field approval, and checks independent worker, outsider, wrong
Ledger, missing Seat and revoked-session denial. It separately checks
the current original My Work / Today / dated Work read sources do
not return that instruction. These tests have NOT been executed in
a disposable clone yet; structural GitHub CI is not a signed receipt.

**Next acceptance/integration work still required:** apply and
independently test the *staged* source-owned governor decision and
recipient approved-fields read on a protected clone; connect them
through the real governor and worker notebooks; verify preserved
original Work history and signed ordinary completion before release. The existing legacy `semantic_exposure_envelope_v1`
does use policy and grant structures, but checks old
`organization_memberships`, credential rows and
`audience_kind='organization_member'`. It cannot directly serve a
native `ledger.seats`/canonical-Person recipient without
reintroducing employee/membership identity. Do not silently map
an old organization-member exposure grant to the new
connected-Person authority.

**No production work is changed.** The governor preview is a HOLD
candidate only. Bed 3/4 real Work is still unsplit; worker-approved
instructions and completion parity remain necessary before release.

## Exact governor Work-field decisions and source-backed recipient details (2026-10-26)

A **HELD, clone-only** next-stage authority component is staged in
`connected_person_work_field_decisions_hold.sql`; a matching
`connected_person_work_field_decisions_postconditions_hold.sql`
verifies its schema, private/public RPC boundaries, append-only
event history, live-session source and content-hash enforcement.

This continues the **existing governor-only Effective Disclosure Review**
and original canonical Work engine. It does not introduce an employee
seat, organization-member credentials, blanket Ledger disclosure,
crop-bed data permissions, duplicated Work identity or a second
notebook permission framework.

**Decision source:** `atlas.connected_person_work_field_decision_events_v1`
is an append-only, direct-role-inaccessible, RLS-enabled private
event table. A decision identifies exact native Ledger, original
organization + Work, target canonical Person, **one field**
(`title` or `instructions`), `allow` or `deny`, the root-governor
principal and signed Auth actor, audit reason, a unique request ID,
optional expiry, and a SHA-256 fingerprint of the exact content
approved. `deny` appends a revocation with no content hash. A
monotonic `decision_sequence` establishes latest-wins order under a
per-field advisory lock; older decisions and source Work remain.
A trigger prevents event UPDATE/DELETE, including by future
application code. Existing live data has **no approvals** from this
not-yet-installed table.

**Governor write:** `public.governor_decide_connected_person_work_field_self_api_v1`
requires a genuine current GoTrue session, correct canonical Person,
a current original root-governing principal for the **exact Ledger**,
and the target's exact current original Work allocation + Ledger Seat
+ verified Work-to-Ledger relevance for any approval. It requires
`p_expected_value_sha256` from the governor's viewed candidate; if the
Work text changes before approval, the command **fails closed** rather
than implicitly approving new text. It is idempotent by `request_id`
and will not replay an ID across a different field/scope. Signed
revocation can be recorded even after the Seat or allocation ends,
provided a previous exact decision exists.

**Existing governor review:** `candidate.sql` now projects up to
50 exact active/completed Work field candidates with the original
`titleCandidate`/`instructionsCandidate`, their current SHA-256,
and current last-decision status: `not_evaluated`, `approved`,
`denied`, `expired` or `source_changed`. Decision IDs and the
presence of additional rows are included. A candidate remains only
a governor inspection input. Full effective-disclosure verification
stays incomplete; no permission approval is inferred from the
governor's ability to inspect it.

**Recipient read:** `public.connected_person_work_approved_fields_self_api_v1`
derives the recipient from the **current session**, never a caller-supplied
Person. It requires current exact original Work allocation, native
Ledger connection, relevant original Work evidence, and the
monotonically latest, unexpired `allow` with unchanged source text for
each returned field. It returns **only permitted keys** under
`fields`; if no approved field remains it responds with uniform
`not_found`. It does not expose source UUIDs, full Ledger, crop
records, historical results, or unrelated Work.

**Alternate original Work readers:** the four *held* Work readers
(new narrow Work, existing My Work, original Today, original dated Work)
now all require the same live source-approved **title** decision to
list a Work item, with original My Work/Today/dated Work independently
projecting `instructions` only under that field's own current grant.
Legacy Worker Day farm-hand read/refresh/report/home remain
**separate retirement blockers**, not silently superseded by this grant.

**Important implementation order for a disposable full-schema clone:**
existing original Ledger/Work/schema and synthetic fixtures; then the
new `connected_person_work_field_decisions_hold.sql` authority table
and functions; then `candidate.sql` governor review and the held
same-signature original Work reader cutovers + new narrow reader;
then clone postconditions and independent GoTrue/PostgREST signed tests.
Do **not** install the other source readers before the field helper
exists. This is a test plan, not production migration approval.

The expanded signed fixture now covers zero-permission default,
root-governor-only review, mismatched SHA denial, worker cannot
self-grant, title-only disclosure, separate instructions authorization,
other Ledger/Work/Person denial, newly edited instructions being
withheld, reapproval of the new exact text, field-specific revocation,
original My Work/Today/dated Work parity, immutable decision history,
and ended-Seat/work-relevance/GoTrue-session revocation. **These signed
tests remain UNRUN** on a protected full-schema local clone; static
GitHub CI checks do not establish real signed reachability or
privacy certification.

**Outstanding stop conditions:** govern historical completion/result/
acceptance fields separately; prove real worker Done reporting,
permission-aware Index/Event/old farm read/media/cache exposure,
and all original alternate SQL/HTTP routes. Connect the reviewer
and recipient views into the universal Atlas notebook (not
hardcoded Elm), then split the real Bed 3 and Bed 4 Work preserving
the combined task's original history. Governor approvals themselves
are human decisions, not automatically assigned. Nothing here
was migrated, deployed or granted in production.

## 2026-10-26 production read-only compatibility receipt and machine decision

The owner has explicitly approved **using the existing production project as
a test environment** because no outside users are actively relying on Atlas.
RiverSong is **Intel macOS 11.7.11 (Big Sur), 8 GB RAM, 34 GB free**, with
Homebrew but no Supabase CLI, `psql`, Docker or OrbStack. Current Supabase
native local runtime does not support Intel macOS, and a full containerized
Noel schema is unsuitable on the available machine. No Mac installation or
cloud branch was made.

**Important reality:** production is not disposable simply because there
are no outside consumers. The live read-only census returned:

| Existing production source | Records |
|---|---:|
| `auth.users` | 6 |
| `auth.sessions` | 131 |
| `reality.entities` | 2,188 |
| `ledger.seats` | 10 |
| `atlas.work_items` | 215 |
| `atlas.work_allocations` | 193 |
| `atlas.company_work_native_ledger_relevance` | 61 |

**Source compatibility verified by read-only Supabase SQL:**

- All 21 expected Work, allocation and original Ledger-relevance column
  names and types match the held source candidate.
- All 15 referenced PostgreSQL/Auth/Atlas and legacy public Work helper
  signatures exist, including `sha256(bytea)`,
  `pg_advisory_xact_lock(bigint)`, `reality_access_self_api_v1`,
  `principal_has_ledger_authority_v1`, exact native Ledger connection
  and exact original Work source validator.
- The proposed private field decision table and internal/public
  approved-field APIs remain **absent** from production.
- Original native Person Work allocations grouped by actual source state:
  **22 active/open**, **1 completed/completed**, **1 released/completed**.
  Every group has active native Ledger connections and an active
  original Work-relevance row. The last historic released/completed
  allocation is a **specific positive-history/recipient-access decision
  to adjudicate**; do not erase it or assume revocation means safe
  automatic redisclosure.

The repeatable audit query is
`production_catalog_compatibility_readonly_20261026.sql`, which selects
only catalog fields and aggregate counts (not real people or their Work
text). A basic `BEGIN READ ONLY; SELECT ...; ROLLBACK;` probe succeeded.

**Test restriction encountered:** a further attempt to compile the
staged grant schema in a single production SQL transaction ending in
`ROLLBACK` was **blocked before execution by tool safety controls**.
It produced **NO compile result and NO signed recipient test**.
Do not reinterpret the failed tool invocation as a database error,
as a successful rollback receipt, or authorization to try an
alternate mutating tool to work around the restriction. Continue with
available source-only CI, live read-only catalog/access audits and
separately authorized protected signed release testing when a compatible
environment becomes available.

**Live production changes from this round: NONE.** Neither governor
decisions nor Work-field grants exist in production; no original
record, Auth session, ACL, reader, migration or deployment changed.
Existing Gate 0 Source CI PASS / Database Custody CI PASS are
not permission proofs.
