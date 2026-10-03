# Atlas Universal Temporal Field Constitution v1

**Status:** foundational read-model architecture; no new temporal authority established  
**Established:** September 26, 2026  
**Parent laws:**

- `architecture/ATLAS_REALITY_LEDGER_CONSTITUTION_V1.md`
- `architecture/SHARED_DIRECTORY_LEDGER_OVERLAY.md`
- `architecture/ATLAS_REALITY_LEDGER_SCHEDULING_CONSTITUTION_V1.md`
- `architecture/atlas-company-work-kernel-v1.md`
- `architecture/ELM_EVENT_CALENDAR_OPERATING_RECORD.md`

## 1. Constitutional purpose

Atlas already contains several lawful sources of truth that have relationships to time.

They must not be collapsed into one `calendar_event` ontology merely because a human wants to see them together.

The Universal Temporal Field is therefore:

> **an authorized, source-preserving read composition of reality that has lawful temporal standing inside a requested interval.**

It is not:

- a calendar event table;
- a new occurrence identity authority;
- a new booking authority;
- a replacement for Company Work time contracts;
- a replacement for Person Life consequences;
- a replacement for Principal Clock;
- a replacement for Organization purpose contexts;
- a source of external-calendar truth;
- or a mutation surface.

The governing movement is:

```text
source-owned reality
  → source adapter establishes lawful temporal standing
  → authorization / scope / context filtering
  → Temporal Projection envelope
  → Universal Temporal Field
  → Calendar / Week / Day / Agenda / source-specific renderer
  → focused encounter
  → owning source domain performs any lawful mutation
  → Temporal Field re-projects
```

No mutation is made true because it was dragged, resized, colored, grouped, or displayed by a Calendar.

## 2. Root law

> **Time does not erase ontology. Calendar placement is a projection consequence, not a new identity.**

A canonical occurrence remains an occurrence.

A temporal marker remains a meaningful date or range.

An Organization purpose-context membership remains private curation.

A Booking remains a Ledger commitment around an occurrence.

A Resource Claim remains occupancy.

A Work Item remains Work; its time contract remains separate time truth.

A Person Life consequence remains a requirement/consequence whose relevance, carrier, readiness, and Clock admission are separate facts.

A Communication Conversation remains communication identity even when it causes a response or Work consequence with temporal meaning.

Principal Clock remains arbitration of present attention for a Principal.

The Temporal Field is allowed to render all of them together without pretending they are the same kind of thing.

## 3. One Calendar, many source authorities

Atlas should have one general Calendar operation.

That Calendar consumes the Temporal Field.

A source-specific scheduling workbench may render the same interval differently when Resource, Booking, Offering, availability, recurrence, or fulfillment detail is needed.

This does not create a second Calendar authority.

The intended composition is:

```text
                         Principal Clock
                              │
                              │ interpretation / admission
                              ▼
source-owned reality → UNIVERSAL TEMPORAL FIELD ← scheduling kernel
                              │
                              ▼
                         Atlas Calendar
                   ┌──────────┼──────────┐
                   ▼          ▼          ▼
                 Month       Week       Day
                   └──────────┼──────────┘
                              ▼
                         focused encounter
                   ┌──────────┼──────────┐
                   ▼          ▼          ▼
                  Work     Scheduling   Source domain
```

Calendar is spatial presentation.

Source domains remain authority.

## 4. The five independent questions

Every Temporal Field request must keep these questions separate.

### 4.1 Scope

> Whose or what authorized world is being examined?

Examples:

- Personal Atlas;
- an Entity;
- a Ledger;
- an Organization compatibility scope during succession;
- a Resource;
- a Person;
- another lawful subject.

Scope is not a category filter and does not create custody.

### 4.2 Context

> Why has this already-resolved reality been selected for this use?

Organization purpose contexts are the established first proof.

Examples:

- `community_calendar`;
- `educational_events`;
- `occurrence_series`;
- another Organization-owned purpose context.

Context is private curation / use meaning.

Context does not own canonical identity.

### 4.3 Lens

> Which aspects of the authorized temporal field should presentation emphasize?

Examples may include:

- everything;
- work;
- family / household;
- events;
- people;
- bookings;
- resources;
- availability;
- conflicts.

A lens must never manufacture records that are absent from the underlying projection set.

### 4.4 Source

> Which canonical/private authority owns the fact being projected?

Every projection must preserve its source domain, source object kind, and source object identifier.

### 4.5 Encounter

> Where does the human go when they focus or act on this projected thing?

A projection may point to:

- canonical occurrence encounter;
- scheduling encounter;
- Work encounter;
- Person / Entity encounter;
- Communication encounter;
- temporal-marker explanation;
- another governed source-domain encounter.

The encounter target is navigation/action routing, not ownership.

## 5. Temporal standing

The Temporal Field must preserve **why** something has the right to occupy temporal space.

V1 defines the following standing vocabulary as a projection vocabulary, not as persisted source state.

### `historical`

A source fact happened at a known instant or interval.

Examples:

- a communication was received;
- an action occurred;
- a payment event was recorded.

Historical standing does not make the source object schedulable.

### `meaning_bearing`

The date or range itself carries established meaning.

Primary source:

- `local_intel.temporal_markers`.

Examples:

- holiday;
- anniversary;
- fiscal boundary;
- season boundary;
- blackout date.

Meaning-bearing standing is not an occurrence.

### `scheduled`

A real occurrence or commitment is established for a temporal interval.

Examples:

- canonical occurrence;
- Ledger booking around that occurrence;
- explicit Resource occupancy claim.

The adapter must preserve whether time belongs to the occurrence, booking context, or occupancy claim rather than flattening those authorities.

### `contracted`

A source domain has established a lawful time requirement without necessarily creating an occurrence.

Primary first proof:

- `atlas.work_time_contracts`.

Examples:

- earliest lawful start;
- preferred interval;
- latest lawful completion;
- hard finish;
- expected duration.

Contracted standing does not convert Work into an Occurrence.

### `relevant`

A consequence or requirement is lawfully inside a relevance/action window.

Person Life consequence architecture is the first explicit proof of the distinction:

```text
requirement established
!= carrier established
!= execution ready
!= relevant now
!= Clock admitted
```

A deadline by itself must not be interpreted as current relevance when the owning authority requires an explicit relevance start.

### `clock_admitted`

Principal Clock has admitted an eligible candidate into its present arbitration/result.

This standing is Principal-specific.

Clock admission does not rewrite the source object and does not mean the object is a scheduled occurrence.

### `availability`

A source authority says a Person/Entity/Resource may or may not accept commitment over an interval.

Reality/Ledger Resource availability is the first live proof.

Availability is not occupancy.

### `conflict`

Two or more lawful temporal facts cannot presently coexist under the owning planning/scheduling authority.

First proofs include:

- `atlas.work_planning_conflicts`;
- scheduling Resource conflict evaluation.

Conflict truth must remain visible. The Calendar must not make conflict disappear by silently moving, hiding, or dropping one source fact.

## 6. Temporal standing is descriptive, not source authority

A Temporal Projection may carry one primary standing and additional standing evidence.

For example:

```text
Work Item
  source identity: atlas.work_items
  time authority: atlas.work_time_contracts
  temporal standing: contracted
  conflict evidence: atlas.work_planning_conflicts
```

Or:

```text
Occurrence
  source identity: local_intel.occurrences
  temporal standing: scheduled
  Ledger meaning: ledger.occurrence_calendar_bindings
  Resource occupancy: ledger.occurrence_resource_claims
```

The field must not persist `temporal_standing` back into those source rows as a universal state machine.

## 7. Temporal Projection envelope

The first read membrane should normalize transport shape while preserving source authority.

Conceptual V1 envelope:

```text
TemporalProjection {
  projectionId

  sourceRef {
    domain
    objectKind
    objectId
  }

  temporalStanding

  time {
    startDate?
    endDate?
    startsAt?
    endsAt?
    allDay?
    timezoneName?
    precision
  }

  scope {
    kind?
    id?
  }

  context {
    kind?
    id?
    stableKey?
    roleKeys?
  }

  display {
    title
    secondary?
  }

  epistemicState {
    state
    missingFields[]
    partialReasons[]
  }

  custody {
    authorityDomain
    projectionOnly = true
  }

  clock {
    state
    candidateId?
    reason?
  }

  encounter {
    kind
    id
  }

  evidenceRefs[]
}
```

This is a contract shape, not a table definition.

`projectionId` is transport identity for one projection result. It must not become a canonical identity that competes with `sourceRef`.

## 8. Incomplete and uncertain time

The Temporal Field must preserve incomplete truth.

Examples:

- occurrence start known, end unknown;
- marker date known, timezone irrelevant;
- Work latest lawful completion known, no preferred start;
- recurrence expectation exists, occurrence not realized;
- Person Life consequence exists, placement unresolved;
- booking exists but Resource classification remains incomplete.

The membrane must not invent:

- end times;
- all-day semantics;
- placement;
- availability;
- Clock relevance;
- occurrence identity;
- Resource classification.

Presentation may render partiality, but it may not repair it by inference.

## 9. Source family admission contracts

### 9.1 Canonical occurrences

Authority:

- `local_intel.occurrences`.

Rules:

- one real occurrence projects from one canonical occurrence identity;
- Organization or Ledger interest does not create another occurrence;
- cancelled/terminal semantics remain source-owned;
- known start/end are projected without Calendar mutation.

Primary standing:

- `scheduled` when source state admits projection.

### 9.2 Canonical temporal markers

Authority:

- `local_intel.temporal_markers`.

Rules:

- a marker is not converted into an occurrence;
- date/range semantics remain date-based where appropriate;
- recurrence rule remains marker authority;
- Organization-private meaning is added through its temporal binding/context membership.

Primary standing:

- `meaning_bearing`.

### 9.3 Organization-private temporal curation

Authorities:

- `atlas.organization_occurrence_bindings`;
- `atlas.organization_temporal_bindings`;
- `atlas.organization_purpose_contexts`;
- `atlas.organization_purpose_context_memberships`.

Rules:

- context answers why the Organization is using already-resolved reality;
- membership payload remains Organization-private;
- membership does not create canonical identity;
- the same occurrence/marker may lawfully belong to multiple contexts;
- removing one context membership does not remove source reality.

The Elm Calendar is the first complete proof:

```text
canonical occurrence or temporal marker
→ Elm private binding
→ Elm purpose-context membership
→ Elm-private payload
→ calendar projection
```

### 9.4 Reality/Ledger scheduling

Authorities include:

- `ledger.occurrence_calendar_bindings`;
- `ledger.bookings`;
- `ledger.occurrence_resource_claims`;
- Reality availability;
- Ledger booking/request/Offering/policy/recurrence authorities.

Rules:

- Ledger calendar membership is not occurrence identity;
- Booking is not occurrence identity;
- Resource Claim is occupancy and may have a wider interval than visible occurrence time;
- availability is not occupancy;
- request/hold/approval are not confirmed booking truth;
- Offering evaluation is possibility, not commitment.

Primary standings may include:

- `scheduled`;
- `availability`;
- `conflict`.

### 9.5 Company Work

Authorities:

- `atlas.work_items`;
- `atlas.work_time_contracts`;
- `atlas.work_planning_conflicts`.

Rules:

- Work exists before assignment or placement;
- Work lifecycle state is not time truth;
- only lawful time-bearing Work facts enter the Temporal Field;
- planning conflict remains visible and source-owned;
- Calendar movement cannot rewrite the Work contract without a governed Work command.

Primary standings:

- `contracted`;
- `conflict` where present.

### 9.6 Household / Person Life consequences

Authority:

- `atlas.person_life_consequence_instances` plus its accepted source evidence/characterization authorities.

Rules:

- requirement existence is not Clock placement;
- unresolved carrier remains unresolved;
- non-ready consequence is not treated as executable;
- current relevance cannot be inferred from deadline alone when explicit relevance-start law applies;
- Temporal Field may project consequence standing only through the owning consequence/Clock contracts.

Primary standings may include:

- `relevant`;
- `clock_admitted` after Clock admission.

### 9.7 Principal Clock

Live authority:

- `atlas.principal_clock_arbitration_v1`;
- `atlas.principal_clock_api_v1`;
- later governed successors where lawfully promoted.

Rules:

- Clock is arbitration of attention/relevance for a Principal;
- Clock is not the Temporal Field;
- Clock admission is one projection fact about a source candidate;
- Temporal Field may contain scheduled facts that are not Clock-admitted;
- Clock may admit consequences that are not occurrences.

### 9.8 Communication / Correspondence consequences

Canonical communication identity:

- `atlas.communication_conversations`.

Rules:

- sent/received time may be historical standing;
- communication receipt time does not create an appointment;
- a Conversation may create/relate to Response Case or Company Work consequences;
- temporal obligation created by communication must enter through the consequence-owning domain rather than by inventing a Calendar event;
- follow-up intent remains consequence/Work truth until a real occurrence is established.

Primary standing:

- `historical` for communication events themselves;
- downstream consequence standing comes from the owning consequence/Work authority.

## 10. Clock and Temporal Field are constitutionally distinct

This distinction is mandatory.

### Temporal Field asks

> What temporal reality is this requester authorized to see in this interval, and why does each fact have lawful temporal standing?

### Principal Clock asks

> Among eligible Principal-relevant candidates, what deserves present attention under Clock arbitration?

Therefore:

```text
scheduled != clock_admitted
contracted != clock_admitted
relevant != clock_admitted
visible_in_calendar != speaks_now
```

A 3:00 p.m. booking may appear all day in a Calendar even if Clock has no reason to speak about it at 9:00 a.m.

A life consequence may become Clock-relevant without ever becoming a scheduled Occurrence.

## 11. Organization Calendar is a saved context over the Temporal Field

The Elm Calendar establishes the pattern.

An Organization calendar should normally be modeled as:

```text
scope = Organization / related Ledger context
context = Organization purpose context with context_kind = calendar
projection = source reality + Organization-private membership meaning
```

Do not create a universal `calendars` identity table merely to represent:

- Community Calendar;
- Educational Events;
- Board Calendar;
- Marketing Calendar;
- Staff Calendar;
- Donor Calendar;
- another curated Organization view.

A durable purpose context may serve that curation role when its semantics fit.

If a future use requires something purpose contexts cannot truthfully express, that must be proved before introducing another Calendar ontology.

## 12. Ledger Schedule is a scope/depth over the same field

Opening a Ledger Schedule should eventually mean:

```text
Temporal Field
  scope = Ledger
  interval = requested window
  scheduling depth = enabled
```

It may then enrich the projection with:

- bookings;
- Resource claims;
- availability;
- recurrence;
- Offerings;
- requests;
- routing/requirement evaluation.

This is not another universal Calendar.

The current independent Scheduling Workbench window navigation is transitional application structure until the shared Temporal Field read membrane is established.

## 13. Mutation boundary

The first Temporal Field membrane is read-only.

It must never mutate source truth as part of projection.

All writes return to the owning authority:

```text
Occurrence change
→ occurrence authority

Organization curation change
→ Organization purpose-context binding/membership authority

Booking / Resource change
→ Reality/Ledger scheduling services

Work time change
→ Company Work authority

Person consequence change
→ consequence authority

Clock characterization / admission
→ Clock/consequence authority

Communication response/work consequence
→ Communication / consequence authority
```

After the command succeeds, the Temporal Field re-reads source truth.

## 14. No drag-and-drop authority

A visual Calendar may eventually support drag/drop or resizing as command gestures.

The gesture is never itself authoritative.

The renderer must resolve the source projection and dispatch a source-specific governed command.

If the source does not support the requested change, the Calendar must refuse rather than editing local projection state as durable truth.

## 15. Authorization and privacy

Temporal composition does not weaken source authorization.

The membrane must obey the intersection of:

- authenticated Person standing;
- Personal Atlas access;
- Ledger Seat/responsibility/capability;
- Organization-private overlay access;
- source-domain authorization;
- context membership visibility/publication rules;
- Principal-specific Clock privacy;
- external/provider source constraints where later added.

A shared occurrence UUID does not authorize one Organization to see another Organization's context payload.

A shared Entity does not authorize another Ledger's scheduling truth.

A Calendar renderer must not become a broad data-exfiltration endpoint merely because it composes many domains.

## 16. First read membrane contract

The first executable Temporal Field service should accept conceptually:

```text
authenticated Person
interval start/end
optional scope
optional Organization purpose context
optional lens
```

and return:

```text
contract version
requested interval
resolved scope
coverage by source adapter
TemporalProjection[]
diagnostics / partiality
```

The first implementation must not return raw source tables.

Every projection must include source identity and encounter routing.

Every adapter must be allowed to report:

- complete;
- partial;
- unavailable;
- unauthorized;
- unsupported.

One failing adapter must not cause the membrane to invent data for that source.

## 17. First implementation sequence

### Stage A — constitutional read proof

Implement only these three adapters first:

1. canonical Occurrences;
2. canonical Temporal Markers;
3. Organization purpose-context curation over occurrence/temporal bindings.

This reproduces the proven Elm Calendar architecture without introducing scheduling mutation.

Acceptance question:

> Can one interval contain one canonical occurrence and one canonical temporal marker, while an Organization privately curates either/both into a calendar context, without duplicating source identity or leaking another Organization's payload?

### Stage B — scheduling enrichment

Add Reality/Ledger scheduling projection:

- Ledger occurrence membership;
- Booking context;
- Resource occupancy;
- availability/conflict explanation;
- recurrence realization state.

Do not make scheduling the universal Calendar source service.

### Stage C — Company Work

Add Work time contracts and planning conflicts without projecting every open Work Item.

### Stage D — Person consequence / Principal Clock

Add only consequence states lawfully admitted by their governing source/Clock contracts.

Preserve `relevant` versus `clock_admitted`.

### Stage E — Communication consequences

Add historical communication standing only where useful, and route response/deadline consequences through their owning Work/consequence authority.

## 18. First acceptance matrix

Before any CAL-02 runtime conversion, the mixed-source proof must demonstrate all of the following at once:

| Source truth | Temporal standing | Must remain |
| --- | --- | --- |
| canonical occurrence | scheduled | one canonical occurrence identity |
| canonical temporal marker | meaning_bearing | not an occurrence |
| Organization context membership | contextual curation | private overlay, not identity |
| Ledger booking / Resource claim | scheduled / occupancy evidence | Ledger commitment / occupancy authority |
| Company Work time contract | contracted | Work remains Work |
| Company Work planning conflict | conflict | explicit conflict, not disappearance |
| Person Life consequence | relevant when lawfully admitted | consequence remains consequence |
| Principal Clock result | clock_admitted | attention arbitration, not scheduling |
| Communication event/conversation consequence | historical or downstream standing | Conversation remains communication identity |

If any adapter requires copying one of these objects into a generic Calendar record to make the view work, the Temporal Field design has failed.

## 19. Constitutional prohibitions

The Universal Temporal Field must not introduce or authorize:

- `calendar_events` as a new canonical catch-all;
- duplication of `local_intel.occurrences` by scope or Organization;
- conversion of temporal markers into fake occurrences;
- Organization-private payload promotion into shared reality;
- booking state inferred from Calendar presence;
- Resource occupancy inferred from visual overlap;
- Work lifecycle inferred from placement;
- Clock admission inferred from date/time alone;
- communication response obligation inferred merely from message receipt time;
- Person free/busy inferred from Seat eligibility;
- completion inferred from the passage of time;
- source mutation by presentation code.

## 20. Governing test

For every proposed temporal projection, ask:

1. What source object exists independently of Calendar presentation?
2. Which domain owns that object's identity?
3. Which source fact gives it lawful temporal standing?
4. Is that standing historical, meaning-bearing, scheduled, contracted, relevant, clock-admitted, availability, or conflict?
5. What scope is being requested?
6. Is Organization purpose context adding private meaning without replacing identity?
7. Which source authorization controls visibility?
8. What is incomplete or unknown?
9. Which encounter owns deeper inspection?
10. Which governed source command would own any mutation?
11. Would the source truth survive unchanged if the Calendar application disappeared?
12. Could another lawful source object occupy the same time without becoming the same ontology?

If those answers are not explicit, the projection is not ready for the Universal Temporal Field.
