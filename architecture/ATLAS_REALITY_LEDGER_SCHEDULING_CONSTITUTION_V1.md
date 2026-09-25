# Atlas Reality / Ledger Scheduling Constitution v1

**Status:** recovered live kernel under architectural adjudication  
**Established:** September 25, 2026  
**Parent constitution:** `architecture/ATLAS_REALITY_LEDGER_CONSTITUTION_V1.md`  
**Occurrence authority:** `architecture/SHARED_DIRECTORY_LEDGER_OVERLAY.md`

## 1. Purpose

Atlas needs to represent time-bound commitments without creating a second reality model beside Reality / Ledger.

The scheduling field includes real-world occurrences, reservable resources, availability, occupancy, bookings, recurrence, and calendar projections. These concepts are related, but they are not interchangeable.

This constitution governs the scheduling kernel already present in production and restores its source custody to `optical-lift/noel-core-db`.

It does **not** open a new Atlas package. It completes custody and constitutional placement of an already-live extension of the Reality / Ledger artery.

The governing movement is:

```text
canonical Reality
  → canonical occurrence
  → one Ledger's lawful scheduling context
  → availability / policy evaluation
  → booking or other commitment where applicable
  → explicit resource occupancy claim
  → calendar / schedule projection
```

Money, Sale, Registration, Company Work, attendance, communication, and provider systems may relate to this movement without becoming its source authority.

## 2. Root law

> **Reality owns the real thing. Canonical occurrence identity owns the event that happens. A Ledger owns its institutional commitment and scheduling meaning around that occurrence. Explicit resource claims own occupancy. A calendar projects those truths; it does not create them.**

The scheduling kernel must remain subordinate to the Reality / Ledger Constitution:

- a Resource does not become an Entity merely because it can be booked;
- a Ledger does not own the Reality Entity that is its subject;
- a booking does not create a second occurrence;
- a calendar row does not establish occupancy;
- a payment does not establish booking truth;
- an external scheduler does not become Atlas source authority merely because it successfully accepted a reservation.

## 3. Canonical nouns and custody

### 3.1 Reality Entity

`reality.entities` remains the canonical identity root.

A business, institution, Person, place, household, or other real-world thing exists independently of Atlas.

Scheduling must not create duplicate Entity identity merely because the same real-world party appears as:

- customer;
- organizer;
- host;
- attendee;
- provider;
- venue owner;
- resource owner;
- payer;
- requester;
- approver;
- or calendar participant.

Those are relations or contextual roles, not replacement identities.

### 3.2 Resource

`reality.resources` represents a real capacity-bearing thing owned by a canonical Reality Entity.

A Resource may be a:

- building;
- room;
- zone;
- station;
- equipment item;
- vehicle;
- capacity pool;
- site;
- or another concrete reservable institutional thing.

A Resource is not a Ledger.

A Resource is not a booking.

A Resource is not a calendar.

A Resource is not automatically a canonical Entity. When a thing requires independent identity, relationships, claims, or standing beyond resource custody, that is a separate Reality adjudication rather than an automatic consequence of being reservable.

Resources may form a hierarchy beneath one owner Entity. Parent / child structure exists to model real containment and availability interaction, not organizational authority.

### 3.3 Canonical occurrence

`local_intel.occurrences` remains canonical real-world occurrence identity under the Shared Directory / Ledger Overlay contract.

A real event happens once in reality.

The same occurrence may matter to many Ledgers without being duplicated.

A Ledger therefore binds to the canonical occurrence rather than minting a Ledger-local event identity.

### 3.4 Ledger calendar binding

`ledger.occurrence_calendar_bindings` means:

> this canonical occurrence belongs in this Ledger's scheduling field.

It is a Ledger overlay.

It does not mean:

- the Ledger owns the occurrence;
- a booking exists;
- a resource is occupied;
- the occurrence is public;
- every member may see it;
- money has been collected;
- attendance is established;
- or the occurrence blocks time.

Calendar membership may exist before a customer, booking, resource classification, or complete occupancy window is known.

### 3.5 Booking

`ledger.bookings` represents a Ledger-owned scheduling commitment around one canonical occurrence.

A booking may identify a customer Entity and may carry external or commercial references, but it does not own the customer's identity, the canonical occurrence, payment truth, Sale truth, or provider truth.

Current booking states are:

- `hold`;
- `confirmed`;
- `cancelled`;
- `completed`;
- `no_show`.

`ledger.booking_events` preserves append-only booking transition history.

### 3.6 Booking reference

`ledger.booking_references` relates a booking to another system or domain without transferring authority.

Examples include:

- commercial order;
- payment;
- invoice;
- Stripe object;
- Amelia reservation;
- external scheduler identifier;
- registration record.

A reference is evidence of relationship between systems. It is not permission to collapse their lifecycle truth.

### 3.7 Resource claim

`ledger.occurrence_resource_claims` is the authoritative carrier for time-bounded occupancy claimed by a Ledger occurrence.

A resource claim answers:

> what real resource is being consumed, over what interval, under what occupancy semantics?

Current claim kinds are:

- `exclusive`;
- `shared`;
- `capacity`.

Current active states are represented separately from released / cancelled states.

A resource claim may be attached to a booking, but occupancy does not require every occurrence to be commercial.

Setup, teardown, preparation, cleanup, travel, or other lawful occupancy may extend beyond the visible occurrence window when that is the real operational interval.

### 3.8 Availability profile

`reality.availability_profiles`, `reality.availability_rules`, and `reality.availability_exceptions` describe when a Reality Entity or Resource is ordinarily available or unavailable.

Availability is source-side schedule fitness.

Availability is not occupancy.

A thing can be ordinarily available and still be occupied.

A thing can be unoccupied and still be unavailable.

### 3.9 Booking policy

`ledger.booking_policies` describes Ledger-specific policy governing whether or how a booking may be established.

Examples already represented include duration, booking-window, start-increment, buffer, recurring-booking, and approval requirements.

Policy is not Reality availability and is not occupancy.

### 3.10 Recurrence

`ledger.recurrence_series`, `ledger.recurrence_exceptions`, and `ledger.recurrence_instances` represent Ledger-owned recurring scheduling intent and its expected instances.

A recurrence series is not a collection of already-existing canonical occurrences.

An expected recurrence instance becomes linked to canonical occurrence reality only when the occurrence is materialized / attached through the governed seam.

This preserves:

```text
schedule expectation
!=
realized occurrence
```

## 4. Non-collapse laws

The following distinctions are constitutional.

### 4.1 Entity != Resource

A Resource belongs to a canonical Entity. Reservability alone does not make the Resource an independent Entity.

### 4.2 Resource != occurrence

The place, room, vehicle, equipment item, or capacity pool is not the event that consumes it.

### 4.3 Occurrence != Ledger calendar binding

The occurrence exists canonically whether zero, one, or many Ledgers choose to include it in their calendars.

### 4.4 Calendar binding != occupancy

Calendar relevance is not proof that a resource is occupied.

Occupancy requires an explicit resource claim.

### 4.5 Availability != occupancy

Recurring open hours, closures, and availability exceptions describe fitness of a subject for scheduling. Existing claims describe actual committed consumption.

Both must be evaluated.

### 4.6 Booking != occurrence

A booking is a Ledger commitment around an occurrence.

Cancelling a booking does not erase the fact that the occurrence identity may still exist.

### 4.7 Booking != payment

A confirmed payment does not independently establish booking state.

A confirmed booking does not independently establish payment state.

Commercial Financial Reality remains the owner of economic truth.

### 4.8 Booking != external reservation provider

Stripe, Amelia, Google, Microsoft, CalDAV, another scheduler, or another provider may be a carrier or witness. Provider success is not Atlas source authority.

### 4.9 Recurrence != realized occurrence

A recurrence rule describes expected repeated timing. Each real occurrence remains canonically identifiable.

### 4.10 Participant role != customer != payer != responsibility

The person who attends, organizes, hosts, serves, pays, requests, approves, or is responsible may be different people.

Current V1 booking customer identity must not be stretched to mean every scheduling role.

First-class participant / scheduling-role semantics remain a future extension.

### 4.11 Visibility != free/busy effect

An occurrence may be visible without blocking time.

An occurrence may block time while exposing little or no detail to a viewer.

Current V1 does not yet model this distinction completely. Future free/busy/transparency work must preserve knowledge jurisdiction rather than using visibility as a proxy for occupancy.

### 4.12 Calendar view != calendar truth store

Day, week, month, agenda, resource lane, personal calendar, Organization calendar, public calendar, and named calendar collections are projections / lenses.

They must not duplicate occurrence or occupancy truth merely to produce another visual grouping.

## 5. Authority map

| Question | Canonical authority |
| --- | --- |
| What real Entity is this? | `reality.entities` |
| What real occurrence is this? | `local_intel.occurrences` |
| What reservable thing belongs to this Entity? | `reality.resources` |
| When is an Entity / Resource ordinarily schedulable? | Reality availability profile / rule / exception |
| Why does this occurrence belong in this Ledger's scheduling field? | Ledger occurrence calendar binding / authorized context |
| What booking commitment has this Ledger made? | `ledger.bookings` + append-only booking events |
| What resource is actually claimed and when? | `ledger.occurrence_resource_claims` |
| What booking rules apply in this Ledger? | `ledger.booking_policies` |
| What repeated schedule does this Ledger intend? | Ledger recurrence series / exception / instance |
| Who may perform a scheduling operation? | Ledger Seat responsibility / capability / authenticated membrane |
| What money moved? | Commercial / Financial Reality authority, not booking |
| What is shown on a screen/calendar? | Projection assembled from the authorities above |

## 6. Resource hierarchy and conflict domain

Resource hierarchy participates in availability because real containment matters.

Examples:

```text
Facility
  ├── Room A
  └── Room B
```

An exclusive claim on the Facility may block Room A and Room B.

An exclusive claim on Room A may make an exclusive whole-Facility request unavailable.

Room A and Room B may coexist when no parent-level exclusive claim blocks them.

Sibling relationship alone does not create conflict.

Quantity-governed resources use numeric capacity rather than room-style exclusivity.

The conflict engine must therefore operate on real resource relationships and capacity semantics, not string matching against event titles.

## 7. Incomplete truth must remain visible

Atlas must not invent a room, resource, customer, end time, participant, or booking state merely to make a calendar look complete.

When the canonical occurrence is known but resource classification is not known, the calendar may remain present while occupancy remains explicitly unclassified.

When an occurrence start is known but no reliable end/resource is known, Atlas may show the occurrence without asserting an occupancy claim it cannot support.

Unknown is a governed state, not a rendering defect.

## 8. Authorization

Scheduling authority follows Reality / Ledger law.

Possession of an Auth session does not authorize scheduling operations.

Possession of a Seat does not establish every scheduling responsibility.

The authenticated Atlas membrane must resolve the relevant Ledger, Seat, capability, and responsibility required by the operation being attempted.

The current live membrane includes scheduling/resource capabilities added by `atlas_schedule_responsibility_capabilities_v2`.

Application code must use authenticated self APIs rather than direct table mutation.

Database `SECURITY DEFINER` services remain privileged carriers and must not be treated as authority merely because they can technically perform writes.

## 9. Current governed service surface

The recovered live kernel includes internal services such as:

- `reality.upsert_resource_service_v1`;
- `reality.subject_schedule_availability_v1`;
- `reality.upsert_availability_profile_service_v1`;
- `reality.upsert_availability_rule_service_v1`;
- `reality.upsert_availability_exception_service_v1`;
- `ledger.bind_occurrence_to_calendar_service_v1`;
- `ledger.establish_booking_service_v1`;
- `ledger.transition_booking_state_service_v1`;
- `ledger.add_booking_reference_service_v1`;
- `ledger.establish_occurrence_resource_claim_service_v1`;
- `ledger.resource_claim_availability_v1`;
- `ledger.resource_conflict_domain_v1`;
- `ledger.lock_resource_conflict_domains_v1`;
- `ledger.establish_booking_bundle_service_v1`;
- `ledger.upsert_booking_policy_service_v1`;
- `ledger.evaluate_booking_policies_v1`;
- `ledger.upsert_recurrence_series_service_v1`;
- `ledger.set_recurrence_exception_service_v1`;
- `ledger.refresh_recurrence_instances_service_v1`;
- `ledger.materialize_recurrence_instance_service_v1`;
- `ledger.materialize_recurrence_range_service_v1`;
- `ledger.recurrence_schedule_service_v1`.

Authenticated Atlas wrappers include the corresponding Ledger resource, calendar, availability, booking, booking-bundle, policy, and recurrence self APIs.

These services are transport / mutation membranes around the authority model above. Their existence does not change which layer owns which truth.

## 10. Atomic establishment

A booking and the resource claims it requires must not be allowed to partially establish when the intended operation is one commitment.

`ledger.establish_booking_bundle_service_v1` provides the current atomic seam.

The service must evaluate:

1. applicable availability;
2. applicable booking policy;
3. resource conflicts / capacity;
4. authority;
5. booking establishment;
6. associated resource claims;
7. calendar membership consequences.

Failure must leave no partial booking / occupancy commitment.

## 11. Calendar projections

The current Ledger resource-calendar projection may compose:

- canonical occurrence identity and timing;
- Ledger calendar membership;
- booking state where present;
- resource claims;
- unclassified occupancy state;
- resource identity and hierarchy;
- recurrence linkage;
- availability / conflict explanations;
- typed commercial / external references.

A projection may enrich presentation with authorized snapshots.

It must not turn a snapshot into source authority.

For example, a payment snapshot shown beside a booking remains a view of Commercial Financial Reality; the calendar does not become the money ledger.

## 12. External calendar and scheduler boundary

Durable integration with Google Calendar, Microsoft 365, CalDAV, iCalendar, JSCalendar, Amelia, or another scheduler must preserve:

```text
external object identity / revision
→ source mapping
→ admitted observation or command
→ canonical Atlas occurrence / Ledger scheduling consequence
```

Future sync work should carry the external object's native UID, sequence/revision, ETag or equivalent version marker, sync token / cursor where applicable, source-of-truth direction, and tombstone semantics.

Import/export is not permission to duplicate occurrence identity.

## 13. Proof posture

### 13.1 What is proved

The production kernel is not hypothetical.

Elm Farm Venue is the first real adopter and proves:

- canonical Reality-owned resource hierarchy;
- independent Ledger booking state;
- resource claims separated from occurrence identity;
- parent/child conflict behavior;
- sibling-resource coexistence;
- booking linkage to existing commercial references without moving money authority into booking;
- calendar presence for incomplete/unclassified resource truth.

### 13.2 What is not yet proved

The schema is structurally neutral enough to describe quantity capacity and non-room resources, and a transaction-only quantity-capacity validation succeeded.

That is **not** the same as a second genuinely different live domain proving every scheduling abstraction.

Therefore:

- do not claim that venue proof alone establishes every industry scheduling model;
- do not add domain-specific universal vocabulary merely because the schema can express it;
- preserve the generic primitives already justified by their real function;
- require another genuinely different live domain before promoting additional cross-industry abstractions that are not already necessary to preserve the current kernel's invariants.

The word `universal` in the existing migration names describes domain-neutral carrier design. It does not waive Atlas's second-domain proof rule.

## 14. Elm resource adoption

Elm is an adopter, not the ontology.

The recovered Elm venue migrations establish / reconcile the first resource hierarchy and preserve legacy provenance.

Elm-specific resource names, booking offerings, Coffee Bar decisions, venue rules, or event programming must not become generic Atlas types.

No new scheduling kernel table may be keyed by farm identity, venue identity, or Elm-specific vocabulary.

## 15. Source custody recovery

The live scheduling kernel was applied to production on September 25, 2026 before its canonical source was present in `optical-lift/noel-core-db`.

That violated the database source-custody direction even though the live database state itself was coherent.

The recovery rule is:

> Production bytes are evidence of what actually became canonical state. Recovery must preserve those bytes exactly rather than reconstructing equivalent SQL from a noncanonical repository.

The following production migrations have now been recovered byte-for-byte on the canonical scheduling custody branch:

1. `20260925215931_atlas_universal_booking_resource_calendar_v1`
2. `20260925220232_atlas_universal_booking_calendar_access_v1`
3. `20260925220342_atlas_universal_booking_calendar_fk_indexes_v1`
4. `20260925220559_atlas_universal_booking_calendar_write_membrane_v1`
5. `20260925220713_atlas_universal_ledger_occurrence_calendar_binding_v1`
6. `20260925221900_elm_venue_legacy_space_resource_cutover_v1`
7. `20260925222335_elm_venue_resource_hierarchy_reconciliation_v2`
8. `20260925222903_elm_venue_coffee_bar_resource_simplification_v3`
9. `20260925224117_atlas_atomic_booking_resource_commit_v1`
10. `20260925224756_atlas_universal_availability_booking_policy_v1`
11. `20260925225300_atlas_universal_ledger_recurrence_v1`
12. `20260925225412_atlas_schedule_responsibility_capabilities_v2`
13. `20260925225442_atlas_schedule_kernel_fk_indexes_v1`

Each recovered repository blob has been compared with the production custody packet's `gitBlobSha1` and matches exactly.

`optical-lift/farm-atlas` is not the source of authority for this recovery. Any corresponding files there are historical quarry only.

## 16. Current limitations / next structural questions

The current kernel is sufficient for governed Resource, occurrence-calendar, booking, availability, occupancy, policy, and recurrence work.

The next scheduling concepts must not be smuggled into existing columns merely to make a UI easier.

The highest-value unresolved primitives are:

- first-class occurrence participants and scheduling roles;
- explicit free/busy and transparency semantics;
- named Ledger calendar collections / views that do not duplicate occurrence truth;
- full booking-request / approval / delegation / rejection history beyond a policy flag saying approval is required;
- resource capabilities and occurrence/resource requirements;
- quotas / allowances and cancellation / reschedule policy where real domains prove them;
- durable external calendar synchronization identity and revision state.

These are candidate tranches, not retroactively assumed properties of V1.

## 17. Application boundary

`optical-lift/atlas` may present and invoke the released scheduling contracts.

It may not:

- create another booking store;
- write scheduling tables directly from UI code;
- use local component state as durable booking truth;
- infer occupancy from occurrence title or venue prose;
- treat calendar visibility as free/busy;
- infer payment from booking state;
- duplicate canonical occurrences for each calendar;
- copy `farm-atlas` scheduling code merely because it already exists.

Application dependency remains:

```text
notebook encounter
→ application scheduling adapter
→ authenticated Atlas self API
→ governed scheduling service
→ canonical Reality / Ledger truth
```

## 18. Governing tests

Before a scheduling change is accepted, ask:

1. What real thing or occurrence exists independently of the calendar?
2. Which layer owns its identity?
3. Is this a Reality fact, Ledger overlay, commitment, occupancy claim, policy, recurrence expectation, or projection?
4. Does the change duplicate an occurrence or Entity because another view needs it?
5. Is availability being confused with occupancy?
6. Is visibility being confused with blocking?
7. Is a booking being confused with payment, registration, attendance, or provider state?
8. Which exact responsibility / capability authorizes the action?
9. Does incomplete truth remain explicit rather than guessed?
10. Is a proposed abstraction proven outside the first adopter?
11. Does the Atlas app consume a governed membrane instead of rebuilding source truth?
12. Will the result remain truthful if a provider or presentation layer disappears?

If those questions do not have clear answers, the scheduling change is not yet governed.
