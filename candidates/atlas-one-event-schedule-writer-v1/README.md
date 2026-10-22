# Atlas — One Canonical Event Schedule Writer v1

**Status:** REVIEW SOURCE CANDIDATE. Not deployed, not authorized for production direct execution. Implements one narrow *operator-supplied* canonical Occurrence + community-event carrier adapter. It is not yet the full universal Day/Date/Month Calendar composer.

**Owner-directed acceptance:** the October 30 Harvest Party is one Event, **4–8 p.m. America/Chicago**. Its richer canonical Occurrence is retained; linked `atlas.community_events` remains a domain-specific operational carrier, not an alternative date writer. The canonical public time and stale metadata label will be corrected only after source authority, protected clone and manual release; the current code contains no hardcoded Elm IDs or production data repair.

## One source command

`public.set_ledger_occurrence_schedule_self_api_v1` delegates to `atlas.set_ledger_occurrence_schedule_self_api_v1`.

It requires a real signed-person source access path and **active root_governing authority on the exact native Ledger**; specific Organization, Ledger and Occurrence bindings; exactly one `farm_shared` operational Event carrier; explicit UTC instants, stale-source timestamps, a meaningful reason, and a stable source action key.

It locks the one canonical Event identity, rejects ambiguous Organization participation and unauthorized source families, enforces canonical + operational optimistic versions, rejects invalid or ambiguous civil-time round trips, and checks existing bookings, booking requests, other Ledgers, and confirmed site/space coverage. It never moves a Resource claim, books capacity or sends a notification. It preserves all canonical title, status, location, richer metadata and prior subject/work links.

The writer corrects canonical Event start/end, updates only `metadata.publicEventLocalTime` **if present**, synchronizes legacy operational wall-clock columns only if necessary, and appends an immutable actor- and source-qualified `atlas.evidence_records` decision receipt capturing previous values and reason. Replaying the same source action returns that exact receipt; changing a reused action key is rejected. Existing outward contact is merely marked `communicationImpactRequiresHumanReview`; a send/notification must be separately confirmed at its own source.

A new BEFORE UPDATE guard blocks attempts to independently retime operator-supplied `atlas.community_events` against the canonical Occurrence. It intentionally **does not replace the special `network_outreach` and `system_fixture` source writers yet**, whose existing live provenance-based bridge must receive a separately reviewed cutover. This is a candid remaining universal-authority gap, not approval to keep two calendars.

## Immutable generated migration and validation

- Source candidate: `candidate.sql`
- Disposable synthetic fixture: `fixture.sql`, reusing the reviewed signed root/member/outsider Ledger, three distinct same-date Occurrences, shared Event and confirmed 4–8 site hold, plus richer `publicEventLocalTime` and unrelated metadata.
- Protected clone postconditions: `validation.sql`, proving read-only source privilege seam, independent legacy editor denial, exact single Event ID, non-root and outsider denial, root source write, unchanged resource claim, preserved rich metadata, historical old/new schedule, no duplicate receipt on replay, stale-version rejection, and separate morning Event untouched.
- `scripts/validate-atlas-one-event-schedule-writer-signed-http.py` and protected clone harness extend that proof through three genuine disposable signed GoTrue users, forged metadata denial, root write, replay, stale version, seat/session revocation and historical data checks. **No remote endpoints**.

## Remaining release dependencies

1. Source custody check then source merge, governed generation to immutable SQL version and protected clone/signed HTTP authorization. Fix clone proof failures in candidate/fixture first; never edit generated migration package in place.
2. Manual production database release through protected GitHub workflow only after genuine green clone/security gate, with production verification.
3. A *real* authorized Ledger governor invokes the installed schedule command with the currently observed exact source versions. For October 30, proposed instants are `2026-10-30T21:00:00Z` to `2026-10-31T01:00:00Z`, corresponding to **4–8 p.m. CDT**. Do NOT fabricate a signed user from service-role SQL. Existing commitment remains 4–8 and is not altered.
4. Notebook UI must implement that authenticated command in one shared Event/Date flow, keeping source versions exact and showing remaining outreach review. Draft [atlas#355](https://github.com/optical-lift/atlas/pull/355) cannot be deployed while canonical record still incorrectly starts at 6.
5. Inventory and redirect remaining `network_outreach`, `system_fixture` and any other alternate Schedule mutation routes before calling the universal single-calendar cutover finished. Build the actual common temporal read/projection for Day/Month and Event, not a second Calendar backend. Continue other three acceptance contracts for outcome Work, communications and personal attention.

**No production Event or resource claim is changed by this source candidate.**
