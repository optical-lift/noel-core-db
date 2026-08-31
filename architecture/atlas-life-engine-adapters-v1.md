# Atlas Life Engine Adapters v1

## Purpose

Atlas should generalize intelligence by adapting domain truth into shared engines, not by cloning those engines per life domain and not by rewriting existing institutional machinery before its exact production custody is available.

This document records the extraction status and required adapter boundaries for:

- Composition;
- Rhythm;
- Goal;
- State Consequence;
- Clock.

It is intentionally strict about what is implemented versus what is only specified.

## Status summary

| Engine | Current source-custody status | Life adapter status | Rule |
| --- | --- | --- | --- |
| Composition | source-custodied on current repo ledger | **implemented** as pure JSON compatibility adapter | life requirements may become active claims; no invented carriers, sequence, causation, or delegation |
| Rhythm | visible source includes farm-specific `rhythm_templates`; generic production foundation is not yet safely source-custodied here | **specified, not persisted** | do not universalize farm schedule-template schema |
| Goal | generic production foundation known architecturally but not safely source-custodied on current ledger | **specified, not persisted** | desired end and requirements remain independent truths |
| State Consequence | farm-specific consequence use is source-visible; generic production foundation is not safely source-custodied on current ledger | **specified, not persisted** | established condition may require operation/truth/repair/preparation; carrier remains separate |
| Clock | existing Atlas arbitration machinery is downstream of established claims | **contract specified; no life-specific Clock write added** | Clock arbitrates truth; it cannot manufacture it |

The source-custody gap is tracked by the existing production-tail convergence work. This branch must not invent table/function signatures merely to make the architecture look complete.

---

## Composition adapter — implemented

Migration:

```text
20260831141900_atlas_life_signal_composition_adapter_v1.sql
```

Functions:

```text
atlas.validate_life_signal_v1(jsonb)
atlas.life_signal_to_composition_signals_v1(jsonb)
```

The adapter targets the already source-custodied `composition_signals_v1` contract used by shared Composition.

### Mapping

```text
Atlas Life Signal
  scope
  subject
  source
  epistemic basis
  state
  timing
  requirements
  constraints
  ambiguities
  relations
        ↓
composition_signals_v1
  subject
  present_state
  active_claims
  explicit_user_end
  composition_delegated = false
  constraints
  ambiguities
  sequence_authority = none from life signal
  provenance
```

Each supplied requirement may become an `active_claim`.

The adapter does not create a carrier when none was established by the source domain. This is important because shared Composition can preserve an active/protected claim without being allowed to fabricate a concrete journey step.

### Authority boundaries

The adapter cannot:

- infer a requirement from raw natural-language state labels;
- turn an observation into a requirement merely because action would be customary;
- invent `carrier_ref`;
- create sequencing authority;
- reuse an earlier Clock placement as truth;
- grant open Composition discretion;
- establish causation through a relation link;
- turn every GoalSignal state field into intended fruit.

Composition delegation remains owned by the existing request-envelope epistemic firewall.

A goal enters Composition as `explicit_user_end` only when the domain adapter has explicitly supplied `state.explicitUserEnd`.

---

## Rhythm adapter — specified, not persisted

### Why no database bridge is added yet

The source-visible `atlas.rhythm_templates` usage is an Elm/farm schedule-template surface. It contains seasonal/public-calendar vocabulary such as farm, season, weekday, work key, zones, and default duration.

That shape is useful for its current domain. It is not sufficient evidence that it is the universal Rhythm identity or state machine Atlas should use for a person's body care, dream capture, household maintenance, study, or training.

The generic Rhythm foundation must therefore be adapted only after its exact production schema/function custody is available in source.

### Required Rhythm input contract

A life Rhythm adapter must accept only an already-authorized RhythmSignal containing enough evidence to establish:

```text
scope
subject
source/provenance
authorization state
qualifying satisfaction definition
timing/cadence boundary
miss semantics, if independently warranted
recovery semantics, if independently warranted
```

### Required distinctions

Rhythm must distinguish:

1. **cadence exists** from **a qualifying satisfaction happened**;
2. **no satisfaction evidence** from **known failure**;
3. **missed boundary** from **moral/productivity debt**;
4. **requirement exists** from **a task/carrier has been selected**;
5. **ordinary cadence** from **condition-triggered reassessment**.

Example: a dream-capture practice may define “record a remembered dream when one is remembered.” A night with no remembered dream cannot be classified as rhythm failure merely because no Journal event exists.

Example: accepted practitioner homework may establish four qualifying satisfactions before a date. Rhythm should count proven satisfactions; it should not manufacture four recurring tasks as the canonical truth of the requirement.

### Future adapter output

The generic Rhythm bridge should produce normalized rhythm state/claims that can later feed Composition/Clock, while retaining the originating Life Subject and source provenance.

It must not require farm identity as a semantic prerequisite. If the existing generic production engine still contains institutional custody columns, those should be crossed through an explicit compatibility adapter rather than silently treating a person as a farm.

---

## Goal adapter — specified, not persisted

### Core contract

A Goal is:

```text
explicit desired end
+
independently warranted requirements
+
current evidence of requirement satisfaction / unresolved state
```

Those are separate truths.

A GoalSignal must never allow Atlas to infer customary domain requirements merely from the goal label.

For example:

```text
Goal: Complete a 5K
```

may establish the desired end because the person explicitly chose it.

It does **not** by itself prove:

- a training frequency;
- a weekly mileage target;
- a pace target;
- a strength plan;
- a diet plan;
- a recovery protocol;
- a race date;
- that any specific training method is required.

Those requirements need their own source/warrant.

### Requirement satisfaction

A result may satisfy a Goal requirement only through a separately established mapping between:

```text
canonical result
→ qualifying requirement condition
```

Temporal proximity, matching words, or membership in the same Journal Thread are not enough.

### Goal -> Composition

An explicit desired end may be supplied as `explicitUserEnd`.

Independently warranted unsatisfied requirements may become active Composition claims.

Unresolved requirement truth remains unresolved. Composition is not allowed to fill missing Goal structure for convenience.

---

## State Consequence adapter — specified, not persisted

### Existing evidence

Source-visible farm migrations already demonstrate consequence classification in specific operational contexts, such as bed-readiness work whose delay keeps downstream planting blocked.

That proves consequence reasoning is useful, but it does not make farm queue fields the universal consequence API.

### Generic consequence roles

The shared Life Signal contract preserves at least these consequence roles:

```text
operation_requirement
truth_acquisition
repair
preparation
```

The role describes what the established state requires next.

It is not the same thing as a task type.

### Required flow

```text
established condition
      ↓
condition-to-consequence rule with provenance
      ↓
required consequence role
      ↓
possibly an operation requirement
      ↓
possibly a carrier selection
      ↓
possibly a Clock claim
```

Every arrow is a separate authority seam.

### Human task is optional

A consequence may be real without a current human task carrier.

Examples:

- `truth_acquisition`: more evidence is required before a run decision, but no exact reassessment carrier/time has been selected;
- `repair`: a body condition requires an independently authorized care operation, but Atlas has not selected who performs it;
- `preparation`: a state requires preparation before an event, while the exact task decomposition remains unresolved;
- `operation_requirement`: a known operation is required, but current capability/jurisdiction may leave it in a hold/handoff pool.

This distinction is essential for existing Atlas capability-hold behavior as well as person/body domains.

### Causation boundary

A state consequence rule needs its own warrant.

Journal linkage, Thread co-occurrence, bodily proximity, date proximity, or external sky state cannot establish the rule by themselves.

---

## Clock adapter — downstream only

Clock should receive established normalized claims. It should not inspect raw life-domain prose and decide what reality must mean.

A future Life Clock adapter may project fields such as:

```text
scope
subject
claim/source reference
window
fixed time, if any
must-begin / must-finish boundary
expected duration
protection strength
interruptibility
delegability
miss/displacement consequence
provenance
```

Clock may decide *where* competing established claims fit.

Clock may not decide:

- that a body condition exists because a recovery block was scheduled;
- that a Goal requirement exists because a training session was placed;
- that a Rhythm failed because nothing was placed;
- that practitioner advice is authorized because it appeared in the calendar;
- that two observations are causally related because they occurred in the same window.

A placement is an output of arbitration, never retroactive evidence for the originating truth.

---

## Cross-engine invariant: requirement != carrier != placement

This is the most important extraction rule in the tranche.

```text
REQUIREMENT
what reality requires

CARRIER
who/what is fit and authorized to perform it

PLACEMENT
when/where Clock chooses to execute it
```

They may eventually all be known, but they must never collapse into one database row merely because a task UI wants a convenient card.

This rule allows Atlas to represent:

- required work waiting for a specialist;
- care requiring person acceptance before scheduling;
- a truth-acquisition need with no selected method yet;
- an obligation whose carrier is unavailable;
- an explicit Goal with requirements still unresolved;
- a valid observation with no operation at all.

---

## Cross-domain fixture expectations

The current life fixtures establish the expected adapter behavior:

### 5K + body observation

- run result and body observation remain separate canonical sources;
- both may join the same Journal conversation;
- the body observation does not automatically cancel or schedule training;
- a later consequence rule may request truth acquisition if independently warranted.

### Practitioner homework

- recommendation and person acceptance remain separate events;
- only accepted/authorized requirement crosses into person Rhythm;
- qualifying satisfactions are counted from evidence;
- exact placement remains downstream of Rhythm/Composition/Clock.

### Dream

- canonical remembered experience may enter Journal;
- no interpretation or operation requirement is mandatory;
- a capture rhythm does not classify absence of remembered content as failure.

### Sky research + person timeline

- external sky state and personal observations may share a research window;
- generic relations remain non-causal;
- no human condition or Clock claim may be derived from sky state without a separate warranted rule.

---

## Implementation order after production custody convergence

Once the exact live generic schemas are source-custodied, implement in this order:

```text
1. LifeSubjectRef compatibility keying
2. RhythmSignal -> existing generic Rhythm adapter
3. GoalSignal -> existing generic Goal adapter
4. Condition/ConsequenceSignal -> existing State Consequence adapter
5. project those established claims into Composition
6. project eligible claims into Clock
7. verify Journal/result observations close the loop without circular inference
```

Do not begin by changing Bullet Journal UI or creating domain-specific task tables. The UI should become a projection over the shared truth graph after the engine seams are proven.
