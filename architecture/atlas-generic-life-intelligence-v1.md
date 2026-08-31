# Atlas Generic Life Intelligence v1

## Purpose

Atlas should not build a separate reasoning stack for every life domain. Body care, 5K training, dreams, journaling, household care, work, meals, and future domains may have different canonical facts, but they should enter shared Atlas intelligence through common contracts.

The first tranche establishes two reusable seams:

1. Journal events can relate to any number of domain subjects without copying the canonical event.
2. The existing generic Care persistence kernel can hold first-party person-owned condition observations without creating a parallel health database.

This is an additive compatibility tranche. It does not change visible Atlas UI and does not retire existing farm or household behavior.

## Canonical boundary

Domain modules own their facts.

Examples:

- a running domain may own distance, duration, route, pace, or race target facts;
- a dream domain may own the remembered dream record and its raw reported contents;
- a body domain may own body-region vocabulary and user/practitioner observations;
- a sky-research domain may own observed external sky state and source-backed research facts.

Generic Atlas intelligence may receive normalized observations, state, requirements, constraints, and provenance from those domains. It must not silently invent domain semantics.

The target shared flow is:

```text
domain fact
  -> observation
  -> current condition/state
  -> rhythm / goal / state consequence
  -> composition
  -> Clock
  -> result
  -> new observation
```

Only the first two seams are implemented in this tranche.

## Journal subject graph

`atlas.journal_event_index` remains the chronological projection of canonical events. It is not replaced.

`atlas.journal_event_subjects` adds a generic many-to-many relationship graph:

```text
journal event
  -> subject domain
  -> subject kind
  -> subject id
  -> relation kind
```

One event may therefore relate to multiple subjects without duplication. A run may be related to a person, a 5K goal, and a body thread while remaining one canonical event.

A Journal subject link is a relationship assertion only. It does not by itself establish causation, interpretation, diagnosis, or semantic equivalence.

The relationship has its own provenance because the evidence that two records belong in the same conversation can differ from the provenance of either record.

Existing typed Journal pointers (`task_id`, `object_id`, `crop_cycle_id`, `project_id`, `trail_binding_id`) remain intact. They are mirrored into generic links as `legacy_pointer` relationships so new consumers can use the generic graph without breaking inherited application behavior.

Journal link read access inherits the existing parent Journal event read membrane through `atlas.can_read_journal_event_v1`.

## Condition persistence

The existing tables:

- `atlas.care_observation_events`
- `atlas.care_current_state`
- `atlas.care_result_events`

already use `subject_domain`, `subject_kind`, and `subject_id`. They are therefore retained as the persistence kernel for generic condition observations in v1 rather than duplicating them with health-, fitness-, or journal-specific state tables.

The table name `care_*` is inherited implementation vocabulary. It must not be interpreted as permission to force every domain into medical semantics.

### Scope is not subject identity

A subject describes what the observation is about.

A scope describes who or what currently owns custody/access to that observation.

Those are independent axes.

For example:

```text
subject_domain = body
subject_kind   = body_region
subject_id     = left_hip

scope_kind     = person
scope_id       = authenticated user's UUID
```

The authenticated user UUID used by `scope_kind = person` is a first-party custody key in this tranche. It is not declared to be Atlas' final semantic Person identifier.

`care_current_state` is therefore keyed by:

```text
(scope_kind, scope_id, subject_domain, subject_kind, subject_id)
```

rather than by an unscoped subject key.

This permits the same semantic subject vocabulary to exist independently in separate person, household, or farm scopes without one scope overwriting another's current state.

## First-party person custody

`scope_kind = person` is readable only when `scope_id = auth.uid()`.

This tranche intentionally does **not** grant access to:

- practitioners;
- employers;
- household members merely because they share a household;
- other authenticated users;
- organizations merely because the person belongs to them.

Practitioner sharing requires an explicit later relationship/consent membrane. It must not be inferred from role, proximity, organization membership, or the existence of a care relationship elsewhere.

## Generic person condition writer

`atlas.record_person_condition_observation_api_v1(jsonb)` is the first-party writer for generic condition observations.

The caller supplies domain-owned vocabulary:

- `subjectDomain`
- `subjectKind`
- `subjectId`
- `conditionState`
- optional `disposition`
- `sourceKey`
- optional observation time, note, and metadata

Atlas may derive a disposition only when the existing condition registry already supplies one. Otherwise the domain/caller must state whether the condition should be held, reassessed, or intervened upon.

The writer:

- requires authentication;
- fixes custody to the authenticated person's scope;
- namespaces idempotency by owner;
- records provenance-backed observation state;
- preserves `inferred_from_clock = false`;
- does not diagnose;
- does not schedule;
- does not create a task;
- does not grant practitioner access.

## Result boundary deliberately left open

`care_result_events` currently contains result vocabulary developed for Care operations. That vocabulary is not yet proven generic enough for a run, dream, journal reflection, research observation, or every future Atlas domain.

This tranche therefore does **not** create a generic person result writer.

Until a generic Result contract is independently extracted, a domain may record its own canonical result and, when warranted, emit a new normalized condition observation into the shared condition kernel.

This preserves domain truth rather than forcing unrelated outcomes into care-specific result labels.

## Intelligence not yet generalized in this tranche

The following existing Atlas systems are intended for later extraction/adaptation, not rewritten here:

- Rhythm: reusable cadence, warning/due/failure, satisfaction, and recovery logic;
- Goals: desired end plus independently evaluated requirements;
- State Consequences: operation requirement, truth acquisition, repair, and preparation;
- Composition Signals: shared condition-bound composition contract;
- Clock: arbitration among normalized claims, not domain-specific scheduling;
- Threads: multi-event conversation grouping without causal authority;
- Bullet Journal UI: projections over canonical facts and Journal relationships.

## Constitutional constraints

1. Domain facts remain domain-owned.
2. A Journal relationship never replaces a canonical record.
3. A relationship does not prove causation.
4. Current state comes from observation/evidence, never from Clock placement.
5. Scope/access is independent of semantic subject identity.
6. Person-owned observations are private by default.
7. Practitioner access must be explicitly granted later.
8. New domains should add vocabulary and adapters before adding new reasoning machinery.
9. Unknown distinctions remain unknown rather than being filled by convenience.
10. Existing farm and household behavior remains compatible during generalization.
