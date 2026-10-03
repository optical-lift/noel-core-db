# Atlas Temporal Contribution Protocol v1

**Status:** live read kernel; adapter-first composition proven against Elm `community_calendar`  
**Established:** September 26, 2026  
**Live migration:** `20260926165031_atlas_universal_temporal_adapter_protocol_v1.sql`  
**Parent law:** `architecture/ATLAS_UNIVERSAL_TEMPORAL_FIELD_CONSTITUTION_V1.md`

## 1. Purpose

The Universal Temporal Field is not a database subsystem that owns everyone else's time-bearing truth.

It is the transient composition produced when independent source authorities speak one Temporal Contribution protocol.

The dependency direction is:

```text
source authority
  -> source-owned temporal adapter
  -> Temporal Contribution
  -> tiny composer
  -> Calendar / Week / Day / Agenda / source encounter
```

No adapter transfers source authority to the composer.

No composer result becomes a new canonical identity.

No `calendar_events` table is introduced.

## 2. Governing law

> **Sources decide what is true. Adapters state how that truth lawfully occupies temporal space. The composer only combines authorized contributions.**

An Occurrence remains an Occurrence.

A Temporal Marker remains a Temporal Marker.

A Company Work Time Contract remains Work timing truth.

A Person Life consequence remains a consequence.

A Booking remains a Ledger commitment.

Principal Clock remains the arbiter of present attention.

The Temporal Contribution envelope is a read contract, not a replacement ontology.

## 3. Temporal Contribution envelope

Every source adapter must return the same conceptual envelope:

```text
TemporalContribution
  projectionKey

  sourceRef
    authority
    kind
    id

  standing

  coordinate
    dateKey
    startsAt / endsAt
    startDate / endDate
    precision
    timezoneName when relevant

  display
    title
    secondary when source lawfully supplies it

  epistemic
    state
    sourceStatus
    lastVerifiedAt when present

  encounter
    kind
    id

  sourceSnapshot
    authorized source-owned read snapshot

  contexts[]
    Organization-private overlays attached by the composer
```

The envelope may grow additively, but adapters may not repurpose fields to mean source-specific lifecycle state.

## 4. Projection identity

`projectionKey` is deterministic read identity only.

For the first adapters:

```text
canonical_occurrence:<occurrence UUID>
canonical_temporal_marker:<temporal marker UUID>
```

It is not persisted and is not an alternate canonical identity.

## 5. Temporal standing

The adapter uses the constitutional Temporal Standing vocabulary.

The first mappings are:

```text
canonical occurrence
  -> scheduled

canonical temporal marker
  -> meaning_bearing
```

Later adapters may contribute `contracted`, `relevant`, `clock_admitted`, `availability`, `conflict`, or `historical` only when their source law establishes that standing.

Standing is not inferred by the composer from timestamps or titles.

## 6. Coordinate law

An adapter must preserve the temporal semantics of its source.

### Occurrence

A canonical Occurrence carries instant/interval truth:

```text
startsAt
endsAt when known
```

Its local `dateKey` is a projection aid resolved through the requested civil timezone.

The timezone does not rewrite the canonical timestamp.

### Temporal Marker

A Temporal Marker carries civil-date meaning:

```text
startDate
endDate when present
```

It must not be converted into an invented midnight occurrence.

## 7. Epistemic law

The protocol must preserve whether the source truth is established, partial, expected, unresolved, cancelled, or otherwise source-qualified.

V1 source adapters use:

```text
state = established
```

for source rows admitted by their source authority, while retaining source lifecycle/status separately under `sourceStatus`.

The composer does not promote source uncertainty.

## 8. Encounter law

A contribution tells the application where deeper interaction belongs.

V1:

```text
canonical occurrence
  -> encounter.kind = canonical_occurrence

canonical temporal marker
  -> encounter.kind = temporal_marker
```

Future source adapters point to their own governed encounters.

The Calendar therefore never needs to acquire source mutation logic.

## 9. Context overlays are not temporal identities

Organization Purpose Context is the first overlay adapter.

It answers:

> Why has this Organization selected this already-canonical temporal reality, and what private meaning has it attached to that use?

It returns memberships such as:

```text
Organization
context
membership
roleKeys
payload
provenance
-> canonical source reference
```

It does not emit a second occurrence or temporal marker.

The composer attaches the overlay to the canonical contribution under `contexts[]`.

Therefore:

```text
Thanksgiving
  source = canonical temporal marker
  contexts[Elm/community_calendar]
    programmingClosure = true
    calendarNote = "No Thursday at Elm"
```

not:

```text
Thanksgiving canonical marker
+
Elm Thanksgiving calendar event
```

## 10. First three adapters

### 10.1 Organization Context overlay adapter

Reads:

- `atlas.organization_purpose_contexts`
- `atlas.organization_purpose_context_memberships`
- `atlas.organization_occurrence_bindings`
- `atlas.organization_temporal_bindings`

Returns active Organization-private references to canonical source identity plus context-local payload.

It does not read canonical occurrence/marker presentation details beyond the IDs required to identify the referent.

### 10.2 Canonical Occurrence adapter

Reads:

- `local_intel.occurrences`
- authorized canonical host identity where already part of the established occurrence projection contract

It receives the canonical occurrence IDs admitted by the context adapter and the requested interval/timezone.

It returns only matching canonical occurrences.

It does not read Elm/private context tables.

### 10.3 Canonical Temporal Marker adapter

Reads:

- `local_intel.temporal_markers`

It receives the canonical marker IDs admitted by the context adapter and the requested civil-date interval.

It returns only matching active canonical markers.

It does not read Elm/private context tables.

## 11. Tiny composer

The first composer is Organization-context scoped.

Conceptually:

```text
authorized Organization + Purpose Context
  -> Context overlay adapter
  -> collect canonical source refs
  -> Occurrence adapter
  -> Temporal Marker adapter
  -> attach matching private overlays by sourceRef
  -> sort by temporal coordinate
  -> return contributions + coverage
```

The composer may know adapter names and the common envelope.

It must not know source-domain business rules.

## 12. Authorization

The authenticated self API preserves the already-proven Organization access boundary:

```text
auth.uid()
+
atlas.current_effective_organization_membership_v1(organization)
```

Internal adapters and the internal composer are service-only.

`anon` and `authenticated` must not execute them directly.

Authenticated callers receive only the self API.

This prevents a caller from passing arbitrary canonical UUIDs directly to an internal adapter to bypass the Organization context that admitted them.

## 13. Coverage / partiality

The first composer is intentionally partial.

It understands only context memberships whose member kinds are:

```text
occurrence_binding
temporal_binding
```

If the selected context also contains:

```text
recurrence_rule
external_relationship
```

or another unsupported kind, the response must report that coverage explicitly.

Unsupported membership must never silently disappear while the contract claims completeness.

V1 returns coverage counts and `partial = true` when unsupported active memberships exist.

The overlay adapter also reports whether its supported membership set was truncated by the requested limit. Truncation itself makes the composed result partial.

## 14. Recurrence boundary

The existing Elm combined projection may substitute `recurrence_instance` rows for canonical occurrences that realize a recurrence rule.

The adapter-first V1 does not yet admit recurrence expectation as a Temporal Contribution source.

For a real occurrence that also has an active direct occurrence membership in the selected context, the Occurrence adapter emits the canonical Occurrence even when an Organization recurrence rule helped materialize it.

A real occurrence reachable **only** through an unsupported recurrence-rule membership is intentionally absent from V1 and must be explained by partial coverage rather than silently reconstructed through recurrence logic.

Later recurrence support must contribute **expectation/series truth** without replacing canonical occurrence identity.

## 15. Elm regression oracle

For Elm Farm `community_calendar`, October 1 through November 30, 2026, the established combined projection returns:

```text
17 occurrence items
8 recurrence_instance items with canonical occurrence links
2 temporal_marker items
```

Those rows represent 25 canonical occurrence referents plus 2 canonical temporal-marker referents.

However, one of those 25 occurrences — the cancelled November 26 `Thursdays at Elm Seasonal Evening` — no longer has an active direct `community_calendar` occurrence membership. It remains visible in the old projection only through the active recurrence rule as a skipped/cancelled recurrence realization.

Because recurrence is deliberately outside V1 adapter coverage, the adapter-first proof returns the directly admitted source referents as:

```text
24 canonical occurrence contributions
2 canonical temporal marker contributions
```

and simultaneously reports:

```text
partial = true
unsupported recurrence_rule memberships = 2
truncated = false
```

The missing cancelled November 26 occurrence is therefore **explained partiality**, not data loss.

The other recurrence-backed real events that still have active direct occurrence memberships remain canonical Occurrence contributions rather than `recurrence_instance` projection identities.

This is the intended v1 behavior and is live-proven.

## 16. Non-collapse rules

### Contribution != source object

The envelope is disposable read shape.

### Context overlay != contribution identity

Elm-private curation enriches a canonical source contribution.

### Composer != source authority

It cannot decide event status, marker status, Work readiness, booking state, or Clock admission.

### Calendar != composer

CAL-02 is a renderer/interaction surface that may consume composed contributions.

### Adapter != permission escalation

Source adapters are internal. Authorization happens through the governed composer/self seam.

### Recurrence expectation != occurrence

Future recurrence adapter work must preserve this distinction.

## 17. Next adapters after the Elm proof

The Elm proof exposed one immediate source gap: recurrence is already part of the selected Organization context, so a recurrence adapter should be completed before the old Elm projection is retired or CAL-02 claims complete context coverage.

After recurrence, add source adapters independently in this order:

1. Reality/Ledger scheduling enrichment and occupancy;
2. Company Work time contracts and planning conflicts;
3. Person Life consequence temporal standing;
4. Principal Clock admission/arbitration annotation;
5. Communication consequence timing;
6. external temporal evidence where governed.

Each adapter must pass its own source-authority acceptance before the tiny composer admits it.

## 18. Acceptance questions

Before admitting any adapter, ask:

1. What existing source authority owns the fact?
2. Why is it lawful for this fact to occupy temporal space?
3. What Temporal Standing does the source itself establish?
4. Does the adapter preserve canonical source identity?
5. Does context/private meaning remain an overlay rather than another identity?
6. Can the adapter be called only through an authorized composition seam?
7. Does unsupported source truth remain visible as partial coverage?
8. If the adapter disappeared, would source truth remain completely intact?

If any answer is unclear, the adapter is not ready.

## 19. Live implementation checkpoint — September 26, 2026

Migration `20260926165031_atlas_universal_temporal_adapter_protocol_v1.sql` established five read functions:

```text
organization_context_temporal_overlay_adapter_v1
canonical_occurrence_temporal_adapter_v1
canonical_temporal_marker_temporal_adapter_v1
organization_context_temporal_composer_service_v1
organization_context_temporal_composer_self_api_v1
```

The first four are internal/service-only. The self API is the only authenticated execution surface and reuses the existing effective Organization membership gate.

All five are `SECURITY DEFINER` with explicit constrained `search_path` values. The source adapters and internal composer are not executable by `anon` or `authenticated`; the authenticated role receives only the self API.

No Temporal Field table, Temporal Contribution table, or canonical `calendar_events` table was created.

Live acceptance against Elm Farm `community_calendar` for October 1 through November 30, 2026 passed with:

```text
24 directly admitted canonical Occurrences
2 canonical Temporal Markers
2 unsupported recurrence_rule memberships
1 explained old-only skipped/cancelled recurrence realization
0 invented canonical referents
partial = true
truncated = false
```

The failed first proof was retained conceptually as a useful architecture discovery: `17 direct occurrence rows + 8 recurrence-instance rows` did not imply 25 directly context-admitted Occurrences. One cancelled Thanksgiving occurrence was reachable only through recurrence. The corrected acceptance treats that as source-boundary evidence rather than hiding it.

The post-DDL security advisor reported no finding introduced by this read kernel. Performance advisors contain existing project-wide findings; this tranche creates no table, foreign key, index, RLS policy, or persisted row and therefore introduced no new index/RLS surface.
