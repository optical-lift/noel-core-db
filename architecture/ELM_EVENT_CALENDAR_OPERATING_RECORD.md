# Elm Event Calendar — Operating Record

**Status:** Current direction as of 2026-09-23  
**Organization:** Elm Farm  
**Atlas purpose:** This document records both the event-calendar operating model and the October–November 2026 calendar facts supplied by the operator. It is intentionally written so future Atlas work can recover the calendar without recreating the architecture or treating Elm-specific names as universal database structures.

---

## 1. What the calendar is

Elm's event calendar is **not an event-identity table**.

A real-world event exists once as a canonical Shared Intelligence occurrence:

```text
local_intel.occurrences
```

Elm then binds that occurrence into its own Ledger:

```text
atlas.organization_occurrence_bindings
```

Elm can use the same occurrence in one or more Organization-private purpose contexts:

```text
atlas.organization_purpose_contexts
atlas.organization_purpose_context_memberships
```

The resulting model is:

```text
one real occurrence
        ↓
one canonical Shared Intelligence identity
        ↓
one Elm Organization binding
        ↓
many lawful Elm uses
        ├── community_calendar
        ├── educational_events
        ├── local_resources
        ├── occurrence_series
        └── future contexts
```

The context answers **why Elm is using the occurrence**. It does not create another event.

---

## 2. Reusable Atlas contexts

The stable keys are functional and reusable across Atlas Organizations. Elm appears only in display titles and Organization-owned content.

### `community_calendar`

**Display title:** Elm Community Calendar  
**Kind:** `calendar`

Used for occurrences Elm chooses to surface in its community calendar.

### `educational_events`

**Display title:** Elm Educational Events  
**Kind:** `calendar`

Used for hands-on learning, workshops, demonstrations, skill-building events, and similar educational programming.

### `local_resources`

**Display title:** Elm Local Resources  
**Kind:** `resource_guide`

Used for businesses, organizations, places, and occurrences Elm chooses to surface as useful local resources.

This context currently has no active occurrence memberships.

### `occurrence_series`

Recurring or grouped events are represented as ordinary Organization purpose contexts with `context_kind='occurrence_series'`.

Examples currently created from the old Elm series system include:

- `arise`
- `family_ultimate`
- `community_flower_mornings`
- `carrie_the_musical_marshfield_2026`
- `marshfield_preschool_storytime`
- `christmas_market_417_2026`
- `marshfield_blue_jays_football_2026`
- `marshfield_saddle_club_monthly_meeting`

Series membership is now explicit. Regex rules are legacy recovery information, not ongoing authority.

---

## 3. Canonical/public projection contract

The public compatibility table is:

```text
public.elm_local_calendar_events_v1
```

It is **not canonical event storage**.

Every row now carries a required unique:

```text
occurrence_id → local_intel.occurrences.id
```

The public projection is composed from:

```text
canonical local_intel occurrence
        +
optional Elm community_events operational overlay
        +
optional Elm purpose-context curation / series
        ↓
public.elm_local_calendar_events_v1
```

Legacy `source_system` and `source_stable_key` remain only for backward compatibility and provenance. They no longer choose event authority.

For Elm-owned events, `atlas.community_events` may still hold legitimate Elm operational facts such as program membership, registration/participation, visibility, capacity, prep, and internal status. It cannot own a second event identity.

---

## 4. How a new event enters the calendar

For any new event:

1. **Resolve canonical occurrence first.** Search `local_intel.occurrences` before creating anything.
2. If the real occurrence does not exist, establish it once in Shared Intelligence.
3. Resolve the canonical host/organizer/venue through `local_intel.entities` where applicable.
4. Bind the occurrence to the requesting Atlas Organization through `organization_occurrence_bindings`.
5. Add the binding to one or more purpose contexts.
6. Put use-specific facts in membership payload, not in canonical identity.
7. If Elm operates the event, attach any private operational state through the Elm `community_events` overlay.
8. Let projections build the calendar or other views.

**Do not create an Elm event identity simply because Elm hosts, promotes, attends, sells tickets to, or publishes an event.**

---

## 5. Current routed October–November 2026 calendar state

The following occurrences are currently active in Elm's real `community_calendar` context.

### October 2026

| Date | Time | Event | Venue | Other routed context |
|---|---|---|---|---|
| Oct. 1 | 9:30–11:30 a.m. | Come Flower Farm With Us | Elm Farm | `educational_events` |
| Oct. 8 | 6:30–8:30 p.m. | Knot + Grow: Macramé Plant Hanger Workshop | Elm Farm | `educational_events` |
| Oct. 10 | 7:00 a.m.–noon | Marshfield Saddle Club Last Swap Meet | Marshfield Saddle Club | — |
| Oct. 13 | 5:00–8:00 p.m. | 2026 Marshfield Area Chamber of Commerce Annual Meeting | Shook Elementary School – Safe Room | — |
| Oct. 15 | 9:30–11:30 a.m. | Come Flower Farm With Us | Elm Farm | `educational_events` |
| Oct. 22 | 6:30–8:30 p.m. | Clay + Color: Handmade Clay Jewelry Workshop | Elm Farm | `educational_events` |

### November 2026

| Date | Time | Event | Venue | Other routed context |
|---|---|---|---|---|
| Nov. 5 | 9:30–11:30 a.m. | Come Flower Farm With Us | Elm Farm | `educational_events` |
| Nov. 12 | 6:30–8:30 p.m. | Thursdays at Elm Seasonal Evening | Elm Farm | — |
| Nov. 19 | 9:30–11:30 a.m. | Come Flower Farm With Us | Elm Farm | `educational_events` |

Current routed counts for this Oct.–Nov. window:

- `community_calendar`: 24 active occurrence memberships
- `educational_events`: 8 active occurrence memberships
- `local_resources`: 0 active occurrence memberships

---

## 6. Operator-supplied October–November 2026 calendar specification

This is the fuller calendar supplied by the operator. It is the calendar specification to reconcile against canonical Atlas reality; **not every item below has yet been established/routed in the database**.

### October 2026

- **Oct. 1** — Thursdays at Elm, 9:30–11:30 a.m., Elm Farm
- **Oct. 2** — Elm Farm First Friday, 3:00–8:00 p.m., Elm Farm
- **Oct. 3** — Spook-tacular Pop-Up, 10:00 a.m.–3:00 p.m., 3M Marketplace
- **Oct. 6** — Webster Title Night + Family Jay Night, 5:30–7:30 p.m., Webster Elementary
- **Oct. 8** — Thursdays at Elm, 6:30–8:30 p.m., Elm Farm
- **Oct. 8** — Board of Aldermen, 6:30–8:30 p.m., Marshfield City Hall
- **Oct. 10** — Dexter Breeders Fall Classic, 9:00 a.m., Webster County Fairgrounds
- **Oct. 10** — Swap Meet, 7:00 a.m.–noon, Marshfield Saddle Club
- **Oct. 13** — Chamber Annual Meeting, 5:00–8:00 p.m., Shook Elementary Safe Room
- **Oct. 15** — Thursdays at Elm, 9:30–11:30 a.m., Elm Farm
- **Oct. 17** — Soap Making with Katie Langenberg, 10:00 a.m., Elm Farm
- **Oct. 17** — Trunk or Treat, 4:00–8:00 p.m., Marshfield Fitness & Tanning
- **Oct. 22** — Thursdays at Elm, 6:30–8:30 p.m., Elm Farm
- **Oct. 24** — 65706 Not-So-Spooky Mini Sampler, 9:00 a.m.–noon, The Wild Honey Boutique
- **Oct. 24** — Fall Family Photos, 3:00 p.m., Southside Acres
- **Oct. 25** — Fall Family Photos, 7:00 p.m., Southside Acres
- **Oct. 30** — Trunk or Treat + Bonfire, 4:00–8:00 p.m., Elm Farm
- **Oct. 31** — Halloween — represented as a canonical temporal marker, not an occurrence

### November 2026

- **Nov. 5** — Thursdays at Elm, 9:30–11:30 a.m., Elm Farm
- **Nov. 5** — Paint Your Own Masterpiece, 6:15–8:15 p.m., Ellis O. Jackson Park Safe Room
- **Nov. 6** — Elm Farm First Friday, 3:00–8:00 p.m., Elm Farm
- **Nov. 7** — Winter Jam, 10:00 a.m.–3:00 p.m., 3M Marketplace
- **Nov. 12** — Thursdays at Elm, 6:30–8:30 p.m., Elm Farm
- **Nov. 19** — Thursdays at Elm, 9:30–11:30 a.m., Elm Farm
- **Nov. 26** — Thanksgiving — canonical temporal marker; Elm calendar payload records **No Thursday at Elm**
- **Nov. 28** — Gobble Wobble, 7:30 a.m., R.A. Barr Stadium

Future note:

- **Dec. 21** — Winter solstice evening, details TBD
- **Dec. 25** — Christmas — canonical temporal marker, not an occurrence
- First Friday continues into winter, details TBD

---

## 7. Reconciliation status

The known existing-record conflicts were reconciled on 2026-09-23 without creating duplicate occurrences.

### Completed

- Oct. 1, Oct. 15, Nov. 5, and Nov. 19 Elm community mornings now end at **11:30 a.m.** in both canonical occurrence time and the Elm operational overlay.
- The Nov. 26 Thursdays-at-Elm seasonal evening is now **cancelled** in both canonical occurrence state and the Elm operational overlay, preserving the operator instruction: **Thanksgiving — No Thursday at Elm.**
- The cancelled Nov. 26 event no longer projects into the public Elm calendar.

### Newly established from the operator calendar specification

The following previously missing events were established as canonical occurrences and routed into `community_calendar` on 2026-09-23, reusing already-canonical host/venue identities:

- Oct. 2 — Elm Farm First Friday
- Oct. 3 — Spook-tacular Pop-Up at 3M Marketplace
- Oct. 6 — Webster Title Night + Family Jay Night at Daniel Webster Elementary
- Oct. 17 — Soap Making with Katie Langenberg at Elm Farm
- Oct. 17 — Trunk or Treat at Marshfield Fitness & Tanning
- Oct. 24 — 65706 Not-So-Spooky Mini Sampler at The Wild Honey Boutique
- Oct. 24 — Fall Family Photos at Southside Acres
- Oct. 25 — Fall Family Photos at Southside Acres
- Oct. 30 — Trunk or Treat + Bonfire at Elm Farm
- Nov. 5 — Paint Your Own Masterpiece at Ellis O. Jackson Park Safe Room
- Nov. 6 — Elm Farm First Friday
- Nov. 7 — Winter Jam at 3M Marketplace

Soap Making with Katie Langenberg and Paint Your Own Masterpiece were also routed into `educational_events`.

Elm First Friday (Oct. 2 and Nov. 6) and Trunk or Treat + Bonfire (Oct. 30) have Elm operational `community_events` overlays because both start and end times are known. The soap-making class has a canonical exact start time but no supplied end time, so no end time was invented merely to satisfy an operational overlay.

### Additional venue/event reconciliation completed

On 2026-09-23, the remaining named venue identities were resolved without creating duplicate places:

- **Board of Aldermen, Oct. 8:** the official City of Marshfield calendar places this meeting at the **City of Marshfield Annex, 915 S Marshall**, not City Hall. The City of Marshfield remains the canonical event entity; the Annex is a separately resolved canonical place.
- **Dexter Breeders Fall Classic, Oct. 10:** **Webster County Fairgrounds** was resolved as an official name variant of the already-canonical **Ellis O. Jackson Park**, 614 N Marshall St. No second fairgrounds entity was created.
- **Gobble Wobble, Nov. 28:** **R.A. Barr Stadium** was established as a canonical place using the Marshfield R-I Schools GPS listing at 540 N Elm St.

The Board of Aldermen meeting and 2026 Missouri Dexter Breeders Fall Classic were independently verified from official/current sources and routed into `community_calendar`.

The Nov. 28 Gobble Wobble remains routed in `community_calendar` with occurrence status `needs_verification`: its 7:30 a.m. 2026 date/time came from the operator calendar specification, while the stadium identity/location is independently verified.

### Temporal-marker reconciliation completed

Halloween, Thanksgiving, and Christmas are not treated as event occurrences merely because they belong on the calendar.

Atlas now has canonical date-native temporal markers for:

- **Halloween 2026 — Oct. 31** (`observance`)
- **Thanksgiving 2026 — Nov. 26** (`holiday`)
- **Christmas 2026 — Dec. 25** (`holiday`)

Elm binds those markers into `community_calendar` through `atlas.organization_temporal_bindings`.

Thanksgiving's Elm-private membership payload records:

- `programmingClosure = true`
- `calendarNote = "No Thursday at Elm"`

The previously existing Nov. 26 Thursdays-at-Elm occurrence remains a cancelled historical/operational occurrence. It is not the Thanksgiving holiday identity.

Halloween has **no manufactured occurrence**. Its presence on the calendar comes entirely from temporal reality.

Do not invent event coordinates merely to make a meaningful date look like an occurrence.

---

## 8. Current canonical venue/entity examples

Already-resolved canonical entities include:

- Elm Farm
- 3M Marketplace
- Ellis O. Jackson Park
- Marshfield Fitness & Tanning
- Marshfield Saddle Club
- Shook Elementary
- Southside Acres
- The Wild Honey Boutique
- Daniel Webster Elementary

These canonical identities may be reused by any Atlas Organization. Elm-specific relevance belongs in the Elm Ledger overlay/context.

---

## 9. Curation

Calendar inclusion and featured state belong to the Organization-private membership.

Example membership payload responsibilities:

```json
{
  "included": true,
  "featured": true,
  "featureRank": 10,
  "featureNote": "Organization-specific reason for featuring this occurrence."
}
```

The old Shared Intelligence tables:

```text
local_intel.elm_local_event_curations_v1
local_intel.elm_local_event_series_rules_v1
```

are legacy read-only compatibility tables and must not receive new Elm-private state.

---

## 10. Core rule to preserve

The event-calendar architecture is an instance of the wider Atlas rule:

> **One reality → one canonical identity → one Organization binding → many Organization-owned uses.**

A calendar, educational-events view, resource guide, registration list, attendance view, or event series is a **projection/use of reality**, not another reality table.

For future Atlas Ledger businesses, the same reusable context keys and occurrence-routing method can be used independently inside each Organization. Elm is an implementation of the pattern, not the schema template.

## 11. Date-native temporal reality

The calendar now spans two canonical time-bearing reality classes:

```text
local_intel.occurrences
    = something happens in time

local_intel.temporal_markers
    = a date or date range itself carries meaning
```

Organizations bind date meaning through:

```text
atlas.organization_temporal_bindings
```

and purpose-context membership now accepts:

```text
external_relationship
occurrence_binding
temporal_binding
```

This allows a single calendar context to contain both events and meaningful dates without collapsing them into one ontology.

See `architecture/ATLAS_TEMPORAL_MARKER_ROUTING_V1.md` for the governing temporal model.

## 12. Recurrence and single-date exceptions

Calendar recurrence is now explicit Organization schedule reality rather than implicit JSON or duplicated event rows.

Atlas uses:

```text
atlas.organization_recurrence_rules
atlas.organization_recurrence_exceptions
atlas.organization_recurrence_instances
```

For Thursdays at Elm, recurrence authority is now:

- `thursdays_community_mornings` — first and third Thursday, 9:30–11:30 a.m.
- `thursdays_seasonal_evenings` — second and fourth Thursday, 6:30–8:30 p.m.

The old `community_programs.cadence` remains only as a compatibility description.

The Nov. 26, 2026 evening recurrence instance is generated from the normal fourth-Thursday rule, then modified by a `skip` exception linked to the canonical Thanksgiving temporal binding. Its attached canonical occurrence remains cancelled historical/operational reality.

This produces the correct distinction:

```text
recurrence rule
    says: fourth Thursday evening is normally expected

Thanksgiving temporal marker
    says: Nov. 26 carries holiday meaning

recurrence exception
    says: skip this Organization schedule instance

cancelled canonical occurrence
    says: an event record had existed and was cancelled
```

Changing or moving one recurrence instance does not silently rewrite canonical occurrence reality. Atlas marks schedule/reality disagreement as a recurrence realization `conflict` until reconciled.

See `architecture/ATLAS_ORGANIZATION_RECURRENCE_EXCEPTIONS_V1.md`.

## 13. Combined temporal calendar projection

Elm's `community_calendar` can now be read through:

```text
atlas.organization_context_temporal_projection_service_v1
```

The projection returns one chronological typed stream across:

- `occurrence`
- `temporal_marker`
- `recurrence_instance`

For Oct.–Nov. 2026, the current combined projection returns:

- 17 standalone occurrence items
- 8 recurrence-instance items
- 2 temporal-marker items (Halloween and Thanksgiving)

The seven cleanly realized Thursdays-at-Elm instances are represented by their recurrence instances with the canonical occurrences nested inside them, preventing duplicate calendar cards.

Thanksgiving renders as two distinct realities on Nov. 26:

1. a `temporal_marker` for Thanksgiving;
2. a `recurrence_instance` for the normal fourth-Thursday evening, marked `skipped`, linked to the Thanksgiving exception, with the cancelled canonical occurrence preserved inside it.

If a recurrence instance is moved or otherwise disagrees with its attached canonical occurrence, Atlas does not choose one silently. The recurrence item is returned with `realizationState='conflict'`, and the canonical occurrence is also returned as its own `occurrence` item at its actual coordinate.

See `architecture/ATLAS_COMBINED_TEMPORAL_PROJECTION_V1.md`.

