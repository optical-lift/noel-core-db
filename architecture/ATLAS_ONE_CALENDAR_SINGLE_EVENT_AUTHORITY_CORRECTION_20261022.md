# Atlas — ONE Calendar / ONE Event Authority, canonical source repair v1

**Owner correction, October 22, 2026.** Supersedes the prior interpretation that October 30 represents two legitimate competing schedules requiring indefinite adjudication. This is a product-level correction to the One Date / Universal Subject build. It does NOT authorize destructive consolidation, direct SQL against production, or hiding an unresolved assertion without correction.

## User's established facts

1. Atlas should have **one calendar**, not two competing calendars or multiple independent ways to change a date.
2. There was one real Elm October 30 public Event, **4–8 p.m. America/Chicago**. Duplicate-looking representations were accidental.
3. The data-rich source currently showing **6–8 p.m.** holds real information. **Preserve that data and canonical identity** rather than delete or replace it with the thinner 4–8 p.m. representation.
4. The goal is universal Event/Date architecture, not a one-off October 30 feature or data-layer hack.

## Verified source topology — the important distinction

The live source currently contains **one** canonical Occurrence for the Harvest Party, not two competing canonical Occurrence IDs:

| Identity | Existing record | Standing after repair |
| --- | --- | --- |
| Canonical Event | `local_intel.occurrences.id = 844ba100-1909-4b6f-ace7-f0c34d548f2f` | **Retain** this ID as the one Event; current title `Elm Farm Harvest Party`, currently 18:00–20:00 Chicago, rich vendor/outreach/operation details. Correct time to 16:00–20:00 Chicago through governed source mutation, preserving prior assertion history. |
| Legacy operational carrier | `atlas.community_events.id = 87c5e95e-5f43-41f0-8229-350deb7091ee` | Retain as a domain **overlay** associated by exact `atlas.organization_occurrence_bindings.id = 6d9c2cf6-59f1-46f4-9ba2-9d844f0b4d58`. Its 16:00–20:00 start/end must become a **projection / backward-compatible state**, not an independent scheduling authority. Keep operational-only fields, metadata and dependent foreign keys. |
| Ledger address | `ledger.occurrence_calendar_bindings.occurrence_id` points to canonical Event | Retain as the single subject address and index key. No new Event ID or duplicate task history. |
| Existing Work | 3 source Work context links and 3 ordinary shared Work action receipts reference the canonical Occurrence | Preserve their exact IDs, actors and result history. |
| Site commitment | 1 confirmed resource claim for 16:00–20:00 Chicago tied to same canonical Occurrence; no booking is attached | Preserve this claim and its 16:00–20:00 site availability. **Public program time and resource occupancy are separate source concepts** even when clocks happen to match. |
| Distinct same-date session | `Arise: Outdoor Movement at Elm`, canonical Occurrence `7cc89ee4-79ed-4ac7-bd5a-9ffeb37c4525` | Remain a separate Event, because the subject/participant/function is genuinely different. |

**Do not execute “merge duplicate occurrence IDs” on these records**; such a merge would fabricate a second identity and risk the rich attached data.

## Single authority rule

- **Calendar is one notebook temporal projection, not another authoritative calendar database.** Date, Day, Week, Month, Event Index and Event detail all address the same canonical Occurrence ID and read the *same settled schedule fact*.
- **Canonical Occurrence owns the public Event's effective start/end** and persistent Event title/status. A legacy `community_events` row may retain operational program configuration and must not remain a second public-date writer.
- An Organization overlay's record, schedule columns, metadata and source history remain inspectable where lawful; but a normal Event/Calendar surface must show **one** Event title and **one** effective schedule. The second record is a source dependency, not a second Event card.
- **One governed edit command** owns each Event-schedule change. It rechecks exact canonical Person/Ledger/Organization/Occurrence authority, authentic signed session, current versions of both source rows, timezone validity, booking/resource constraints and affected published commitments. It writes required source projections in one transaction and records old/new values plus accountable human decision. All writable UI entry points call this **same command**; there is no Calendar-specific writer.
- Existing specialized or legacy writers that can independently mutate effective schedule must be mapped and either routed through the one command or restricted/retired as part of the cutover. Merely making the two clocks equal once does **not** solve duplicate calendar architecture.
- Preexisting status/title differences may have been valid operational vs public terminology; retain as internal provenance/aliases, **not second calendar Events**.
- Distinct legitimate temporal sources (Work deadline, site hold, birthday, school schedule) remain separate source truths even when one Calendar displays them together. “One calendar” does **not** mean losing domain authority or converting everything to `calendar_events`.

## Immediate Elm repair (governed and auditable)

The owner's asserted **4–8 p.m.** is the intended public Event time. After migration safety and signed source-writer permission proof, repair the *existing canonical Occurrence* start from 18:00 to 16:00 Chicago, retain the 20:00 end, update obsolete public-time narrative metadata (currently `publicEventLocalTime='6:00 PM–8:00 PM'`) to 4–8, and preserve the old value and explicit user correction as historical evidence. The linked operational Event is already at 4–8 and needs no re-created identity.

Preserve verbatim the existing rich canonical Event metadata (vendors, outreach, dye-free rules, invitations, fees, partners), including fields whose external-factual standing is “operator reported,” and the operational overlay's metadata as a linked domain overlay. Do not overwrite richer metadata with a smaller `community_events.metadata` object. Do not conclude that prior external invitations said 4 or 6 without inspecting actual source receipts; flag for communication review as needed. No automatic messages.

**No direct production SQL**: use reviewed canonical source candidate, protected clone with synthetic scenario, signed authorization test, exact production-release gate, and *postrelease consistency verification*. A source correction may be executed by one appropriately authorized real person through the released command or through a separately reviewed, properly witnessed operational data-repair migration; never impersonate a Person in an admin SQL session.

## Specific architecture failure to eliminate

The existing `atlas.enforce_community_event_occurrence_binding_org_v1` trigger accepts legacy operational schedule edits. It writes time through to the canonical Occurrence for `network_outreach` and `system_fixture` only. For this real operator-supplied event, operational editing does **not** update canonical. Meanwhile the Ledger Event Index reads canonical 18:00 and the operational screen can read 16:00. That is the dual-edit failure.

Fix by explicit source authority/command and a guarded backward-compatibility projection, not a vague “review competing claims” warning for the human.

## Release sequence (one build with necessary gates)

1. **Carrier/command inventory**: search every Event/date read and write route in Atlas and `noel-core-db`, including Personal Important Dates, `atlas.community_events`, `local_intel.occurrences`, Event Index, existing work/attention, Calendar spread and legacy direct edits. Classify each as a source of new reality, a link/projection or an incompatible alternate schedule writer.
2. **Authoritative Event writer**: exact identity, signer/permission, idempotency, prior-source version CAS, timezone and DST, source history, and no silent changes to domain resource claims/bookings/communications. Its one transaction updates the source schedule plus any required legacy projection. Preserve source objects and all FK dependencies. Make legacy independent schedule edit paths deny or delegate to this writer.
3. **One-calendar read model**: one canonical Occurrence ID, one effective Event time/title/status, one Event notebook. Lens filters cannot duplicate it. Continue showing raw legacy differences in an optional provenance/history inspection, not as a second Event or a second editable schedule.
4. **Repair October 30 using owner's stated time** and preserve all rich data and history. Protect both existing legitimate same-day Events.
5. **Proof**: test two genuine Events same date vs one Event with two source carriers, three separately authenticated People, old/out-of-order versions, cross-Ledger denial, root vs ordinary permissions, missing source, resource 4–8 claim preservation, all Work/action IDs unchanged, metadata preservation, one calendar projection and same value through every entry path. Include a second unrelated Ledger (no farm hardcoding).
6. **Retire the old competing edit/display routes**, not merely hide them. If any independent writer or duplicate date encounter persists, the build is **not complete**.

## Superseded interpretation

Earlier `ATLAS_SUBJECT_DATE_SCHEDULE_RECONCILIATION_CONTRACT_V1` and Issue #1982 correctly require source custody, permission and history but **misframed the user-visible goal** as choosing between standing competing calendars. They are now subordinate to this one-authority contract; the released evidence and preflight readers are diagnostic aids, not the finished product. No further permanently parallel schedule workspace should be built.
