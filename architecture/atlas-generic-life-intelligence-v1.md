# Atlas Generic Life Intelligence v1

## Purpose

Atlas should not build a separate reasoning stack for every life domain. Body care, 5K training, dreams, journaling, household care, work, meals, and future domains may have different canonical facts, but they should enter shared Atlas intelligence through common contracts.

This tranche now establishes five reusable seams:

1. Journal events can relate to any number of domain subjects without copying the canonical event.
2. The existing generic Care persistence kernel can hold first-party person-owned condition observations without creating a parallel health database.
3. Life Signals can enter shared Composition without inventing carrier, sequence, causation, or delegation.
4. Reusable Goal and State Consequence state reducers are extracted from farm-bound persistence into pure JSON evaluators.
5. The existing Rhythm engine's reusable **lease/cadence** state machine is extracted as a pure strategy-specific evaluator without task creation or Clock placement.

This remains an additive compatibility tranche. It does not change visible Atlas UI and does not retire existing farm or household behavior.

## Canonical boundary

Domain modules own their facts.

Examples:

- a running domain may own distance, duration, route, pace, or race target facts;
- a dream domain may own the remembered dream record and its raw reported contents;
- a body domain may own body-region vocabulary and user/practitioner observations;
- a sky-research domain may own observed external sky state and source-backed research facts.

Generic Atlas intelligence may receive normalized observations, state, requirements, constraints, and provenance from those domains. It must not silently invent domain semantics.

Shared engines are selected by meaning, not by surface similarity:

```text
domain fact
  -> canonical observation / result
  -> optional current condition/state
  -> whichever shared engine is actually warranted:
       Goal
       Rhythm
       State Consequence
       Composition
  -> eligible normalized claim(s)
  -> Clock arbitration when temporal placement is warranted
  -> canonical result
  -> new observation
```

A fact does not have to pass through every engine.

Examples:

- a remembered dream can remain an Observation and Journal event with no Goal, Rhythm, Consequence, or Clock claim;
- “four accepted exercises before Friday” is a finite Goal requirement, not automatically Rhythm;
- a recurring weekly review may use the lease Rhythm strategy because each qualifying satisfaction renews a bounded validity interval;
- a body condition may remain only an observation unless an explicit consequence rule establishes a next requirement.

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

## Extracted shared reasoning cores

### Composition

`atlas.life_signal_to_composition_signals_v1(jsonb)` projects validated Life Signals into the shared Composition contract while preserving the existing epistemic firewall.

It does not invent carrier, sequence, causation, or open composition delegation.

### Goal

`atlas.evaluate_life_goal_state_v1(jsonb,jsonb)` accepts an explicit Goal packet plus independently evaluated requirement results.

It derives shared Goal state without querying farms/tasks, inventing requirements, selecting next work, or converting missing evidence to failure.

### State Consequence

`atlas.evaluate_life_state_consequence_policies_v1(jsonb,jsonb)` matches an explicit state snapshot against explicit consequence policies.

It may establish shared consequence roles such as truth acquisition, repair, preparation, or operation requirement, but does not create a task, select a carrier unless explicitly supplied, evaluate execution readiness, or place Clock work.

### Rhythm

`atlas.evaluate_life_lease_rhythm_v1(jsonb,timestamptz,timestamptz)` extracts one coherent strategy from live Rhythm: qualifying satisfaction renews a bounded validity lease.

The generic states are:

```text
uninitialized
resting
coming_due
due
fallen_out_of_rhythm
```

No prior satisfaction means `uninitialized`, not failed.

The generic lease reducer creates no task, transition history, or Clock placement.

Other Rhythm strategies must be separately established; v1 does not call every repeated behavior a Rhythm.

## Shared reasoning does not imply shared persistence identity

Live production inspection confirms that current Rhythm, Goal, and State Consequence storage envelopes still contain institutional identity requirements such as `farm_id`, `organization_id`, and UUID-only subject keys.

Those storage contracts remain valid for existing farm behavior.

They are **not** used as generic person identity by pretending a person or body region is a farm.

The extracted pure reducers allow Atlas to reuse intelligence first. Person-owned persistence/custody can be designed explicitly afterward.

## Result boundary deliberately left open

`care_result_events` currently contains result vocabulary developed for Care operations. That vocabulary is not yet proven generic enough for a run, dream, journal reflection, research observation, or every future Atlas domain.

This tranche therefore does **not** create a generic person result writer.

Until a generic Result contract is independently extracted, a domain may record its own canonical result and, when warranted, emit a new normalized condition observation into the shared condition kernel.

This preserves domain truth rather than forcing unrelated outcomes into care-specific result labels.

## Remaining work

The following are intentionally still downstream:

- person-owned persistence/custody adapters for Goal, Rhythm, and State Consequence outputs;
- generic Result contract extraction;
- practitioner sharing/consent membrane;
- Life claim -> Clock compatibility writer;
- Thread policy beyond neutral relation storage;
- Bullet Journal UI projections over the shared truth graph.

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
10. Requirement, carrier, execution readiness, and Clock placement remain separate authorities.
11. Shared reasoning does not require fake shared persistence identity.
12. Existing farm and household behavior remains compatible during generalization.
