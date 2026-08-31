# Atlas Life Engine Adapters v1

## Purpose

Atlas should generalize intelligence by adapting domain truth into shared engines, not by cloning those engines per life domain and not by forcing person-owned reality through farm-shaped persistence merely to reuse existing code.

This document records the extracted shared cores and the remaining persistence boundaries for:

- Composition;
- Rhythm;
- Goal;
- State Consequence;
- Clock.

The constitutional rule remains:

```text
requirement != carrier != placement
```

A second rule is now explicit:

```text
shared reasoning != shared persistence identity
```

The live production catalog confirms that several existing engines contain reusable state logic while their current storage envelopes still require institutional identity such as `farm_id` and `organization_id`. Atlas must extract the reasoning without making a person masquerade as a farm.

---

## Status summary

| Engine | Live/source finding | Generic Life status | Persistence status |
| --- | --- | --- | --- |
| Composition | shared Composition runtime is source-custodied and already accepts normalized signals | **implemented** | no new domain persistence needed |
| Rhythm | live engine has versioned rules, bindings, satisfactions, state, transitions, and Clock resolution, but current storage is organization/farm-bound | **lease strategy extracted** | person persistence adapter not implemented |
| Goal | live Goal state logic is reusable, but current `goals` / evaluations are farm-bound and requirement providers are domain-specific | **generic reducer extracted** | person persistence adapter not implemented |
| State Consequence | live policy/reconciliation logic is reusable, but instances/events require farm identity | **generic matcher extracted** | person persistence adapter not implemented |
| Clock | existing Atlas Clock/arbitration machinery is downstream of established claims | **contract specified** | no life-specific Clock writer added |

No generic Life migration on this branch inserts person-owned state into farm-bound engine tables.

---

## Engine-routing rule

Not every repeated or time-adjacent fact is a Rhythm.

Use the smallest engine whose semantics are actually established:

| Reality | Primary engine |
| --- | --- |
| something happened / was remembered / was observed | Observation / Journal |
| a bounded outcome is desired | Goal |
| a finite quota must be satisfied before a boundary | Goal requirement |
| a qualifying satisfaction renews validity for a recurring interval | Rhythm (`lease` strategy in v1) |
| an established state warrants truth acquisition, preparation, repair, or another operation | State Consequence |
| multiple established claims need temporal arbitration | Clock |

Examples:

- “Complete this accepted exercise four times before Friday” is a finite requirement. It is not automatically Rhythm.
- “Record a dream if one is remembered” is event-triggered Observation capture. A night with no remembered dream is not Rhythm failure.
- “Perform a weekly household review; each completed review renews the cadence for seven days” is a lease Rhythm.

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

Each supplied requirement may become an active claim. The adapter cannot invent a carrier when none was established by the source domain.

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

A Goal enters Composition as `explicit_user_end` only when the domain explicitly supplies `state.explicitUserEnd`.

---

## Rhythm — lease strategy extracted

Migrations:

```text
20260831144000_atlas_life_engine_packets_v1.sql
20260831152000_atlas_life_rhythm_lease_core_v1.sql
```

Functions:

```text
atlas.life_signal_to_rhythm_packet_v1(jsonb)
atlas.evaluate_life_lease_rhythm_v1(jsonb, timestamptz, timestamptz)
```

### What live Atlas Rhythm actually does

The live engine is not merely a recurring-task table. It has:

- versioned Rhythm rules;
- bindings to subjects;
- qualifying satisfactions;
- state and transition history;
- warning, due, and failure boundaries;
- Clock-time resolution;
- legacy task creation at due/failure boundaries.

The reusable state-machine center is a **lease** model:

```text
qualifying satisfaction
        ↓
validity interval begins / renews
        ↓
resting
        ↓ warning boundary
coming_due
        ↓ due boundary
due
        ↓ grace/failure boundary
fallen_out_of_rhythm
```

If no qualifying satisfaction has ever been established, the generic state is:

```text
uninitialized
```

—not failure.

### Generic extraction

`atlas.evaluate_life_lease_rhythm_v1` reproduces only the state reduction. It deliberately removes:

- task creation;
- planned occurrence creation;
- transition persistence;
- farm membership assumptions;
- Clock arbitration.

The packet must explicitly declare:

```json
{"rhythmModel":"lease"}
```

v1 does not guess a Rhythm strategy from words such as “weekly,” “practice,” or “routine.”

### Current persistence boundary

The live Rhythm storage envelope requires institutional columns including non-null `organization_id` and `farm_id`, and current state identity expects UUID subjects. Those are not faithful generic identities for person-owned Life Subjects such as:

```text
body/body_region/left_hip
journal/practice/weekly_review
```

Therefore this branch does not persist person Rhythm into live farm Rhythm tables.

---

## Goal — generic reducer extracted

Migrations:

```text
20260831144000_atlas_life_engine_packets_v1.sql
20260831150000_atlas_life_goal_consequence_core_v1.sql
```

Functions:

```text
atlas.life_signal_to_goal_packet_v1(jsonb)
atlas.evaluate_life_goal_state_v1(jsonb, jsonb)
```

### Core contract

A Goal is:

```text
explicit desired end
+
independently warranted requirements
+
independently evaluated requirement results
```

Those are separate truths.

For example:

```text
Goal: Complete a 5K
```

may establish the desired end because the person explicitly chose it. It does not by itself prove:

- training frequency;
- weekly mileage;
- pace target;
- strength plan;
- diet plan;
- recovery protocol;
- race date;
- any specific training method.

### Generic state reducer

The extracted reducer consumes requirement results supplied by domain-owned providers and derives:

```text
defined
locked
tracking
playable
in_production
realized
```

Requirement phases remain:

```text
gate
progress
realize
```

Missing provider evidence becomes:

```text
unknown
```

—not unmet.

The generic reducer does not query farms or tasks, apply Elm-specific near-threshold display policy, select a next task, release work, or arbitrate Clock.

### Current persistence boundary

Live Goal storage requires non-null `farm_id`, and live requirement providers include farm/task/crop/resource-specific predicates. Those providers may remain valid farm adapters. Person-owned goals need a separate custody adapter into the generic reducer rather than fake farm identity.

---

## State Consequence — generic matcher extracted

Migrations:

```text
20260831144000_atlas_life_engine_packets_v1.sql
20260831150000_atlas_life_goal_consequence_core_v1.sql
```

Functions:

```text
atlas.life_signal_to_consequence_packet_v1(jsonb)
atlas.evaluate_life_state_consequence_policies_v1(jsonb, jsonb)
```

### Generic consequence roles

v1 preserves these shared roles:

```text
operation_requirement
truth_acquisition
repair
preparation
```

The role describes what an established state requires next. It is not a task type.

### Required flow

```text
established condition
      ↓
explicit condition-to-consequence policy
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

The generic matcher uses explicit JSON snapshot containment against explicit policy predicates. It creates no consequence instance, task, carrier, execution warrant, or Clock placement.

A carrier survives only when the policy explicitly supplies one.

### Current persistence boundary

Live State Consequence policies can be broader than one farm, but live consequence instances/events still require non-null `farm_id`. Person-owned consequences therefore remain generic evaluator output on this branch rather than farm-bound persisted instances.

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

Clock may decide where competing established claims fit.

Clock may not decide:

- that a body condition exists because a recovery block was scheduled;
- that a Goal requirement exists because a training session was placed;
- that a Rhythm failed because nothing was placed;
- that practitioner advice is authorized because it appeared in a calendar;
- that two observations are causally related because they occurred in the same window.

A placement is an output of arbitration, never retroactive evidence for originating truth.

---

## Cross-engine invariant: requirement != carrier != placement

```text
REQUIREMENT
what reality requires

CARRIER
who/what is fit and authorized to perform it

PLACEMENT
when/where Clock chooses to execute it
```

They may eventually all be known, but they must never collapse into one row merely because a UI wants a convenient task card.

This allows Atlas to represent:

- required work waiting for a specialist;
- care requiring person acceptance before scheduling;
- a truth-acquisition need with no selected method yet;
- an obligation whose carrier is unavailable;
- an explicit Goal with requirements still unresolved;
- a valid observation with no operation at all.

---

## Cross-domain fixture expectations

### 5K + body observation

- run result and body observation remain separate canonical sources;
- both may join the same Journal conversation;
- body observation does not automatically cancel or schedule training;
- a later explicit consequence policy may request truth acquisition if independently warranted.

### Practitioner homework

- recommendation and person acceptance remain separate events;
- accepted “four times before Friday” work is modeled as a bounded Goal requirement, not automatically Rhythm;
- qualifying evidence may satisfy the requirement without manufacturing four task rows;
- exact placement remains downstream of Goal / Composition / Clock.

### Dream

- canonical remembered experience may enter Journal;
- no interpretation or operation requirement is mandatory;
- “record when remembered” is event-triggered Observation capture, not a Rhythm failure model;
- a separate explicit cadence could be added later if the person actually defines one.

### Lease Rhythm

- an explicit recurring cadence declares `rhythmModel=lease`;
- no prior satisfaction remains `uninitialized`;
- after satisfaction, state moves through resting / coming_due / due / fallen_out_of_rhythm according to explicit interval parameters;
- the generic evaluator creates no task and no Clock placement.

### Sky research + person timeline

- external sky state and personal observations may share a research window;
- generic relations remain non-causal;
- no human condition or Clock claim may be derived from sky state without a separate warranted rule.

---

## Next implementation order

```text
1. finish fixture coverage for extracted Rhythm / Goal / Consequence cores
2. keep farm providers and persistence unchanged
3. define person-owned persistence/custody envelopes without fake farm identity
4. adapt person Goal/Rhythm/Consequence state into the shared reducers
5. project eligible established claims into Composition
6. project eligible claims into Clock
7. verify Journal/result observations close the loop without circular inference
8. only then project the shared truth graph into Bullet Journal UI
```

Do not create domain-specific task engines for health, fitness, dreams, household care, or study. The product surface should remain a projection over shared Life Subjects, evidence, requirements, reducers, and Clock arbitration.
