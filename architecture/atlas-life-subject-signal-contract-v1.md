# Atlas Life Subject + Signal Contract v1

## Purpose

Atlas life domains may use different vocabularies without receiving different reasoning engines.

This contract defines the minimum envelope required for a domain fact to travel into shared Atlas intelligence without surrendering domain truth, provenance, custody, or uncertainty.

The Life Signal is now an implemented normalization contract used by Composition and by extracted pure Goal, State Consequence, and lease-Rhythm evaluators. It does not require person-owned facts to be persisted into farm-bound engine tables.

## Four independent identities

Every cross-domain fact must keep four questions separate.

### 1. Scope — who owns custody/access?

```text
scope_kind
scope_id
```

Examples:
- person + authenticated first-party custody id
- household + household id
- organization + organization id
- farm + farm id

Scope is an authorization/custody boundary. It is not the semantic identity of the thing being discussed.

### 2. Subject — what is this fact about?

```text
subject_domain
subject_kind
subject_id
```

Examples:
- body / body_region / left_hip
- training / training_goal / springfield_5k
- dream / dream_record / <canonical dream id>
- sky_research / observation_window / <canonical research id>

Subject vocabulary is domain-owned. Shared Atlas engines may route a subject but must not reinterpret its vocabulary without a domain adapter or separately warranted adjudication.

### 3. Source — what canonical record warrants the fact?

```text
source_domain
source_kind
source_id
source_event
source_observed_at
source_provenance
```

The source is the canonical record or evidence event from which the normalized signal was derived.

A source may be:
- a person-authored observation;
- a practitioner-authored recommendation within granted custody;
- a canonical training result;
- a remembered dream record;
- an independently recorded external sky observation;
- a task/result/event already canonical elsewhere in Atlas.

The generic layer may not replace the source record with its normalized projection.

### 4. Relation — why may this fact travel with another subject/event?

```text
relation_kind
relation_basis
relation_provenance
relation_confidence
relation_status
```

A relation may mean:
- about
- evidence_for
- result_of
- participant
- supports
- constrains
- occurs_during
- explicitly_linked_by_user
- candidate_related

A relation is not automatically causal.

`candidate_related` or temporal co-occurrence must never be promoted to cause, diagnosis, interpretation, prediction, or moral meaning merely because records travel together in a Thread or notebook spread.

## Normalized signal envelope

A domain adapter may emit a shared signal only after preserving its canonical source.

Conceptual shape:

```json
{
  "contractVersion": "atlas_life_signal_v1",
  "scope": {
    "kind": "person",
    "id": "<custody-id>"
  },
  "subject": {
    "domain": "training",
    "kind": "training_goal",
    "id": "springfield_5k"
  },
  "signalKind": "observation",
  "state": {},
  "timing": {},
  "requirements": [],
  "constraints": [],
  "ambiguities": [],
  "relations": [],
  "source": {
    "domain": "training",
    "kind": "run_result",
    "id": "<canonical-id>",
    "event": "completed",
    "observedAt": "<timestamp>",
    "provenance": {}
  },
  "epistemic": {
    "factClass": "observed",
    "confidence": "direct",
    "interpretationAuthority": "none"
  }
}
```

Fields may be null or empty when not warranted. Missing information remains missing.

## Signal kinds

### ObservationSignal

Reports something that was actually observed, recorded, received, or measured.

It may update an independently defined current state when the domain has a warranted state reducer.

It does not automatically create work.

Event-triggered capture remains Observation logic unless a separate cadence is independently defined. For example, “record a dream when one is remembered” does not become Rhythm merely because dreams may recur.

### ConditionSignal

Reports a present condition already supported by evidence.

It may carry:
- current state;
- trend;
- relevant functional capacity;
- known timing boundary;
- explicit uncertainty.

Clock placement may never originate a ConditionSignal.

### RhythmSignal

States that an already-authorized recurring condition has a specifically established cadence/renewal strategy.

A RhythmSignal must identify its strategy explicitly. v1 supports:

```text
rhythmModel = lease
```

The extracted lease model means:

```text
qualifying satisfaction
  -> validity interval
  -> optional warning boundary
  -> due boundary
  -> optional grace/failure boundary
```

No prior qualifying satisfaction means `uninitialized`, not failed.

A RhythmSignal should express:
- what constitutes a qualifying satisfaction;
- its explicit rhythm model;
- validity interval or recurrence boundary;
- warning/due/failure behavior only where warranted;
- recovery behavior if separately established.

A bounded quota is not automatically Rhythm. “Do this four times before Friday” is a finite requirement/Goal structure unless an independent ongoing cadence is also established.

### GoalSignal

States an explicit desired end and any independently warranted requirements for reaching it.

A GoalSignal does not let Atlas invent requirements simply because they are customary for a domain.

Requirement provider results remain separate inputs. Missing result evidence remains unknown rather than being silently classified unmet.

### ConsequenceSignal

States what an established condition now requires.

The shared consequence-role vocabulary preserves the existing Atlas distinction among at least:
- `operation_requirement`
- `truth_acquisition`
- `repair`
- `preparation`

A consequence may have no human task carrier.

A consequence role must be warranted by explicit domain evidence or an explicit condition-to-consequence policy; mere Thread co-occurrence is insufficient.

### CompositionSignal

Translates current normalized domain truth into the existing cross-domain composition contract.

It may carry:
- present state;
- active claims;
- explicit user end;
- constraints;
- ambiguities;
- candidate evidence;
- delegated composition authority only when separately granted by the existing Composition request membrane.

The Composition core chooses among warranted operations and bounded discretion. It does not infer new domain semantics from natural-language labels.

### ClockClaim

A Clock claim is downstream of established truth.

It may express:
- relevant window;
- fixed time;
- must-begin or must-finish boundary;
- expected duration;
- protection level;
- interruptibility;
- delegability;
- consequence of displacement;
- provenance/source.

Clock may arbitrate among claims. Clock may not make the originating condition true.

## Domain adapter responsibilities

Every domain adapter must:

1. preserve its canonical source record;
2. emit only facts the domain can warrant;
3. distinguish direct observations from derived state;
4. preserve null/unknown distinctions;
5. preserve source/custody identity;
6. expose timing only when independently supported;
7. label inferred or proposed relationships as such;
8. avoid causal or interpretive promotion without a separate warrant;
9. translate only into shared contracts whose semantics actually fit;
10. leave unsupported downstream fields empty rather than manufacturing completeness;
11. choose the correct engine by semantics rather than by the fact that something repeats or has a date.

## Shared engine responsibilities

Shared Atlas engines must:

1. reason over normalized contracts rather than raw domain prose when committing state or requirements;
2. preserve the domain source and epistemic basis;
3. never overwrite canonical source facts;
4. never convert a Journal/Thread relationship into causality by itself;
5. never convert a Clock placement into evidence that a condition exists;
6. preserve tie/null/unresolved outcomes;
7. preserve the difference between requirement, carrier, execution readiness, and placement;
8. route protected/private scopes through explicit authorization membranes;
9. fail open in presentation where appropriate without fabricating domain truth;
10. allow a later domain adapter or adjudication to refine a signal without rewriting historical evidence;
11. avoid forcing generic person subjects through farm/organization persistence identities merely to reuse an evaluator.

## One observation may support several conversations

A canonical event may be linked to multiple subjects while remaining one event.

Example:

```text
run result #417
  -> training / training_goal / springfield_5k
  -> body / body_region / left_hip
  -> journal / collection / september_training
```

Those links say the event is relevant to each conversation. They do not say the 5K caused the hip state or that the hip state caused any later dream.

## Threads and spreads remain projections

A Thread is a bounded conversation over related canonical facts.

A spread is a requested notebook projection over those facts.

Neither is automatically a source of truth.

A human may explicitly create a relationship while looking at a spread. Atlas may suggest a candidate relationship. Both must be stored with relation provenance and status rather than silently changing the underlying evidence.

## Privacy boundary

Person-owned life signals default to first-party custody.

Future practitioner access must be implemented as an explicit relationship/consent membrane defining:
- which subjects/relations are shared;
- read/write authority;
- effective dates;
- revocation;
- provenance of practitioner-authored facts.

Role names such as practitioner, employer, family member, or organization member never grant access by themselves.

## Current compatibility direction

The extraction is adapter-first:

```text
LifeSubjectRef / LifeSignal
        |
        +--> Composition compatibility adapter
        |
        +--> Goal packet --> generic Goal reducer
        |
        +--> Consequence snapshot/policies --> generic State Consequence matcher
        |
        +--> Rhythm packet (explicit strategy)
                 +--> lease Rhythm reducer (v1)
        |
        +--> eligible established claims --> future Clock adapter
```

Existing farm engines remain intact as domain-specific persistence/provider adapters.

Live inspection confirms that current Rhythm, Goal, and State Consequence persistence still contains institutional identity such as non-null `farm_id`, `organization_id`, or UUID-only subjects. Those tables should not be repurposed as generic person identity by inserting fake institutional records.

Shared reasoning is extracted first. Person-owned persistence/custody can then be added deliberately without rewriting the validated farm behavior.
