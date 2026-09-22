# Atlas Reality Transition Protocol v1

**Status:** architecture contract only  
**Date:** 2026-09-21  
**Scope:** cross-domain Atlas runtime law  
**Executable scope:** none in this tranche

## 1. Purpose

Atlas already contains several strong but locally expressed laws:

- Events preserve what happened.
- Claims preserve what was asserted or observed without making the proposition true.
- Evidence supports, contradicts, or qualifies Claims.
- Proposed effects are distinct from Claims.
- Governed relationships and domain rules determine whether a proposed effect takes hold.
- Consequences/requirements may exist independently from responsibility, execution readiness, and Clock placement.
- Operation Contract projects an already-governed execution situation without owning domain truth or executing effects.
- Actuals preserve what physically or operationally happened.
- Actuals/evidence may resolve or change consequences.
- Repeated actuals may support a learning proposal, but the proposal is not accepted truth.

Those laws are currently distributed across Communication, Company Work, Person Life, Household/Laundry, Money, Production, Scope, Claims/Evidence, and other domain-local structures.

The architectural problem is not that Atlas lacks another generic table.

The problem is that Atlas lacks one explicit **cross-domain transition protocol** saying how those local structures compose.

This contract establishes that protocol.

It deliberately does **not** create a universal event table, effect table, transition table, action registry, process engine, generic workflow engine, or generic state machine.

## 2. Governing statement

> **Atlas preserves what happened, distinguishes what was claimed from what was proposed to change, resolves each proposed consequence under the authority of the reality it would change, projects only established requirements into execution, accepts Actuals as evidence of what became true, and treats learning as a proposal until separately adjudicated.**

The universal architecture is therefore a movement law:

```text
Occurrence/Event
    ↓
Interpretation
    ├─ Claim(s)
    ├─ Proposed Effect(s)
    └─ Actual/Observation when already source-backed
    ↓
Evidence + Custody + Governed Relationships
    ↓
Effect-/Domain-Specific Resolution
    ↓
Effective Consequence / Requirement / Relationship / State
    ↓ when execution is actually required
Operation Contract projection
    ↓
Domain-owned execution / transition
    ↓
Actual / Completion Evidence
    ↓
Consequence resolution / downstream consequence
    ↓
Derived learning proposal
    ↓
separate adjudication / later governed uptake
```

Not every occurrence traverses every stage.

A message may create no executable work.
A physical Actual may close a requirement without a Task.
A Claim may remain unresolved indefinitely.
A consequence may be real but have no current carrier.
A requirement may have a carrier but not be executable.
An executable requirement may still have no right to the Principal Clock floor.
A learning proposal may never be accepted.

Those are valid states, not failures of the protocol.

## 3. The protocol is algebra, not storage

The reusable object is the **transition relation**, not one canonical row shape.

Conceptually:

```text
E → I
```

An event/occurrence `E` may produce one or more interpretations `I`.

```text
(I, evidence, authority, current reality) → resolution
```

Each interpretation resolves independently under the authority appropriate to the affected reality.

For a proposed effect:

```text
F + G(R) → C
```

where:

- `F` = proposed effect;
- `G(R)` = governing relationship/rule over reality `R`;
- `C` = effective consequence, rejected consequence, or unresolved consequence.

For an established executable requirement:

```text
C + carrier + readiness + timing/context → Operation Contract
```

The Operation Contract is a read membrane over those already-governed inputs.

For an Actual:

```text
A + C + resolution law → C'
```

The Actual may resolve, advance, contradict, or otherwise change the consequence under a domain-specific law.

For learning:

```text
A₁ … Aₙ + deterministic learner → P
```

where `P` is a proposal, not accepted truth.

This is the reusable architecture.

## 4. Five reality categories that must never be collapsed

### 4.1 Historical occurrence

Answers:

> What happened?

Examples:

- a message was sent;
- a worker submitted a result;
- a payment event arrived;
- laundry entered washing;
- a Scope-definition event occurred;
- a Person clicked Accept.

The occurrence remains historical reality even when an intended consequence fails.

### 4.2 Proposition

Answers:

> What was asserted, observed, inferred, forecast, or proposed as a description of reality?

This is Claim territory.

A Claim being recorded is real.
Its proposition is not thereby established.

### 4.3 Proposed consequence

Answers:

> What change did an occurrence attempt, request, offer, imply, or propose?

Examples:

- offer Responsibility;
- accept Responsibility;
- create an obligation;
- release an obligation;
- add something to Scope;
- adopt prior work institutionally;
- establish a relationship;
- create a resource commitment.

A proposed consequence is not automatically effective.

### 4.4 Effective governed reality

Answers:

> What may Atlas currently treat as operative truth?

This includes things such as:

- established Responsibility Relation;
- accepted Scope definition;
- open obligation;
- current requirement;
- accepted financial state;
- effective institutional relationship;
- active governing policy.

This is always owned by the relevant domain or governed cross-domain relation.

### 4.5 Execution/result reality

Answers:

> What must become true next, and what actually became true?

Execution reality includes:

- established requirement;
- carrier;
- execution readiness;
- placement/timing;
- Operation Contract;
- Actual;
- completion witness;
- unresolved downstream consequence.

Execution is not a synonym for effective reality.

## 5. The hard separations

The following implications are forbidden unless a separately governed law explicitly establishes them:

```text
event happened
≠ claim is true

claim was made
≠ effect takes hold

actor has title
≠ effect takes hold

transport permission
≠ institutional uptake

visibility
≠ responsibility

responsibility
≠ execution readiness

requirement exists
≠ task exists

requirement exists
≠ carrier is known

carrier is known
≠ execution is ready

execution is ready
≠ Clock placement exists

work reported done
≠ domain result accepted

task terminal
≠ domain Actual exists

Actual exists
≠ every related consequence is resolved

pattern detected
≠ learned proposal is accepted

later uptake
≠ earlier event is retroactively re-authored
```

These separations are not defensive complexity. They are how Atlas avoids manufacturing reality.

## 6. Event and occurrence law

The existing Event/Effect/Uptake architecture remains governing:

> Events happen. Effects are interpreted from events. Governed relationships determine which effects take hold. Later events may adopt, redirect, supersede, reject, or otherwise change consequences without rewriting the originating event.

The Reality Transition Protocol extends that law through execution, Actuals, resolution, and learning.

No generic event validity flag may collapse independent effects.

One event may simultaneously produce:

- a factual Claim;
- an informational disclosure;
- a Responsibility offer;
- a financial promise;
- an institutional-source interpretation.

Those consequences resolve independently.

## 7. Claims and Evidence law

Claims remain propositions.

Evidence remains material bearing on Claims.

Authority does not make a proposition true.

A transition resolver may consume:

- current accepted Claim/Evidence;
- source-backed observation;
- contractual evidence;
- governed policy;
- relationship evidence;
- custody evidence;
- an Actual;
- a prior effective consequence.

But the resolver must preserve the exact basis.

When effective institutional treatment differs from metaphysical certainty, Atlas must say what it is doing:

> Atlas currently treats this proposition as effective for this governed purpose because of this evidence/adjudication.

## 8. Proposed effects and governed uptake

A proposed effect must name the reality it seeks to change strongly enough for Atlas to choose the correct resolver.

The protocol does **not** require one global effect enum.

Instead, domains expose bounded effect families and resolvers.

Examples already represented architecturally include:

- Responsibility offer / acceptance / withdrawal;
- Scope addition / reroute / split / consolidation;
- obligation creation / release;
- institutional adoption of prior consequence;
- Communication consequence creation;
- financial state movement;
- domain-specific state transition.

Later uptake is a new event.

If an institution later adopts a Person-originating request, Atlas records both:

```text
original Person-originating event
later institutional uptake event
```

It does not rewrite the first event as institution-originating.

## 9. Effective consequence law

A consequence is the result of a governed resolution over a specific affected reality.

A consequence may be:

- a relationship;
- a requirement;
- a state;
- an obligation;
- a release;
- a custody change;
- a financial consequence;
- a current institutional treatment;
- another domain-owned effective fact.

There is no requirement that all consequences use one table.

A consequence must be addressable enough for downstream systems to refer to:

```text
consequence kind
canonical consequence reference
effective state
effective time
governing basis / authority
provenance
```

The Manual Reality Candidate architecture already follows this law: a candidate becomes `promoted` only after an owning-domain command produces a canonical consequence kind/reference.

## 10. Requirement axes remain independent

Where a consequence creates a requirement, Atlas must preserve at least these independent axes:

```text
requirement state
carrier state / carrier reference
execution readiness
placement / timing state
```

Laundry currently exposes why this separation matters:

- a Laundry-cycle requirement can be established;
- carrier can remain unresolved;
- execution readiness can remain not evaluated;
- placement can remain unresolved.

Later evidence can establish carrier or readiness without re-owning the requirement itself.

The protocol generalizes that law.

No consequence policy may silently own every axis unless the source domain genuinely has authority over every one.

## 11. Operation Contract law

`atlas.operation_contract_normalize_v1` is the current platform precedent.

Operation Contract is not another source of truth.

It composes supplied governed evidence into a company-neutral execution projection containing:

- subject;
- requirement;
- operation;
- responsibility;
- execution conditions;
- routing;
- result contract;
- continuation;
- provenance;
- execution disposition.

Its existing truth boundary remains correct:

- does not own domain truth;
- does not create requirement;
- does not create execution warrant;
- does not assign responsibility;
- does not arbitrate Clock;
- does not create placement;
- does not execute effects;
- does not interpret result meaning.

The Reality Transition Protocol treats Operation Contract as the standard **execution membrane** after effective reality has already established that execution is meaningful.

It is not the universal transition store.

## 12. Actual law

An Actual records source-backed reality that occurred.

Examples include:

- physical process transition;
- quantity actually observed;
- work result actually submitted;
- payment actually received;
- item actually delivered;
- task carrier actually terminal.

An Actual is not automatically the same as:

- accepted result;
- fulfilled obligation;
- completed domain process;
- resolved consequence.

The owning domain determines which Actual satisfies which consequence.

The Laundry reference architecture expresses the desired shape:

```text
laundry_cycle_needed
    ↓
entered_washing Actual
    ↓ exact domain resolution law
consequence resolved
```

The Actual, not a checkbox, is the authority for the physical state transition.

## 13. Execution carrier terminality versus domain result

The Planned Work terminality reconciliation architecture proves another important separation:

> execution-carrier terminality is not domain-result acceptance.

A Task may be `done` and its occurrence may therefore become terminal.

That does not manufacture:

- a biological result;
- a Harvest result;
- a Sale result;
- a financial result;
- a physical state change.

The Reality Transition Protocol requires downstream domain Actual/result evidence separately where the domain requires it.

## 14. Consequence resolution law

A consequence may be resolved only by a source admitted by its governing resolution law.

The resolver must verify:

- exact consequence identity;
- exact subject/scope;
- source identity;
- source evidence;
- chronology;
- supported transition/result kind;
- any required authority/custody;
- idempotency.

The caller should submit identities/evidence references, not an arbitrary JSON declaration such as `{"done":true}`.

Resolution creates historical evidence and updates/projections through the owning consequence machinery.

It does not require special deletion from downstream projections when those projections are already defined over current open consequences.

## 15. Continuation law

Every consequential transition may expose a continuation contract answering:

> What must be recomputed or reconsidered because this became true?

Examples:

- requirement evaluation;
- execution warrant;
- Clock candidacy;
- remaining obligation;
- downstream custody;
- dependent work eligibility;
- financial balance;
- learning evidence.

Continuation is not a generic side-effect engine.

The source domain still owns the actual downstream transition.

The protocol merely requires that a transition be able to name its lawful continuation dependencies rather than hiding them as accidental triggers.

## 16. Learning law

Learning is downstream of Actuals, not a shortcut around them.

The Laundry learning candidate establishes the correct pattern:

```text
source-backed Actuals
    ↓
deterministic pattern analysis
    ↓
derived Evidence
    ↓
proposed Claim
```

The learner may propose:

- pattern;
- cadence;
- duration expectation;
- probability;
- likely source;
- likely routing;
- another bounded learned hypothesis.

It may not silently:

- create a Rhythm;
- alter Responsibility;
- change Clock Characterization;
- establish policy;
- create a task;
- alter canonical source truth.

Learning proposals require separate adjudication or adoption.

## 17. Correction and supersession

Historical reality is append-oriented.

A later correction must not rewrite what was originally observed, claimed, proposed, or decided.

The protocol therefore distinguishes:

- original occurrence;
- original Claim/effect interpretation;
- later contradictory Evidence;
- later correction Claim;
- later adjudication;
- later superseding consequence;
- later uptake.

Current-state projections may change.

Historical provenance must remain reconstructible.

## 18. Transition Receipt — universal projection, not universal storage

Atlas should standardize one read-only **Reality Transition Receipt** projection contract.

A domain adapter may render a completed or current transition into:

```json
{
  "contractVersion": "reality_transition_receipt_v1",
  "source": {
    "domain": "...",
    "kind": "...",
    "ref": "...",
    "occurredAt": "..."
  },
  "subject": {
    "kind": "...",
    "ref": "...",
    "scope": {}
  },
  "interpretation": {
    "claimRefs": [],
    "proposedEffectRefs": [],
    "actualRefs": []
  },
  "resolution": {
    "state": "effective|rejected|unresolved|not_applicable",
    "resolver": "...",
    "basisRefs": [],
    "effectiveAt": "..."
  },
  "consequence": {
    "kind": "...",
    "ref": "...",
    "state": "..."
  },
  "execution": {
    "requirementState": "...",
    "carrierState": "...",
    "carrierRef": "...",
    "executionReadiness": "...",
    "placementState": "...",
    "operationContractRef": "..."
  },
  "continuation": {
    "reconsider": [],
    "blockers": []
  },
  "provenance": {}
}
```

Fields may be null/absent when that axis does not apply.

This receipt is **read-only composition**.

It must never become the authority that writes the underlying event, Claim, consequence, Actual, result, or learning proposal.

## 19. Why a receipt matters

A common transition receipt gives Atlas a way to:

- explain why something changed;
- render a consistent History/Notebook trail;
- feed Runtime Proof without a fake universal simulator;
- trace manual Reality Sentence promotion;
- show worker/manager/Principal consequences consistently;
- identify which axis is unresolved;
- audit continuation;
- compare domains structurally;
- support future intelligent interpretation without allowing AI to become the database authority.

This is the right level of universality.

## 20. Reference domain mappings

### 20.1 Manual Reality Sentence

```text
operator statement
→ typed Reality Candidate
→ identity/basis resolution
→ owning-domain command
→ canonical consequence ref
→ transition receipt
```

The Candidate is not the consequence.

### 20.2 Communication

```text
Communication Event
→ Claims / proposed effects
→ effect-specific governed resolution
→ possible Company Work / Responsibility / other consequence
→ later uptake may establish a new institutional consequence
```

The message remains real even when one effect fails.

### 20.3 Company Work

```text
institutional obligation/work identity
→ Responsibility / plan / Execution Lease
→ Worker Day projection
→ result event
→ domain/management acceptance where required
→ Ledger consequence
```

Task/result carrier terminality must remain distinct from domain-result truth.

### 20.4 Household Laundry

```text
Household observation Evidence
→ accepted Claim
→ laundry_cycle_needed consequence
→ independent carrier/readiness resolution
→ possible Clock characterization/admission
→ entered_washing Actual
→ consequence resolution
→ repeated Actuals
→ cautious rhythm-pattern proposal
```

This is currently the cleanest end-to-end specimen of the full protocol, though several later tranches remain candidate-only.

### 20.5 Commercial / Money

```text
Demand / commitment / provider event
→ domain interpretation
→ Sale / obligation / payment consequence
→ fulfillment or payment Actual
→ remaining financial state
```

Payment transport events and financial settlement truth remain separable.

### 20.6 Principal escalation

```text
source-domain condition
→ Operational Escalation
→ Decision Packet
→ Principal judgment event
→ owning-domain consequence
```

A Principal decision does not retroactively make the source condition different from what it was.

## 21. Architectural tests for any new Atlas domain

Before creating a new domain-specific flow, answer:

1. What is the historical occurrence or source-backed observation?
2. What Claims are present?
3. What proposed effects are present?
4. What reality would each effect change?
5. Which domain/relationship owns the resolution?
6. What evidence/custody/authority is required?
7. What is the effective consequence if it takes hold?
8. Does it create a requirement?
9. Who/what owns carrier resolution?
10. Who/what owns execution readiness?
11. Who/what owns timing/placement?
12. What Operation Contract adapter, if any, projects execution?
13. What Actual/result proves the next transition?
14. What resolver interprets that Actual?
15. What continuation must be reconsidered?
16. What is historical and therefore immutable?
17. What may be learned?
18. What remains only a proposal until adjudicated?

If a design cannot answer these, it is not ready to become canonical Atlas architecture.

## 22. Anti-patterns prohibited by this protocol

Do not introduce:

- `event.authorized = true/false` as a universal validity switch;
- one generic Action Class permission ontology;
- one universal event table merely for consistency;
- one universal effect enum;
- a generic business-process EAV store;
- a generic state-machine engine that becomes domain truth;
- “AI decided it happened” as a mutation basis;
- Task completion as universal physical truth;
- a Clock placement as proof that a requirement exists;
- a learning model writing accepted policy directly;
- a later uptake event rewriting earlier provenance;
- a transition receipt that becomes a second source of truth.

## 23. Relationship to Runtime Proof

IMP-05 Runtime Proof should consume this protocol.

A proof checkpoint can ask:

- source occurrence exists?
- interpretation supported?
- effect resolved?
- consequence effective?
- requirement/carrier/readiness/placement axes known?
- Operation Contract warranted?
- Actual/completion evidence present?
- downstream consequence resolved?
- continuation accounted for?
- unresolved remainder explicitly contained?

That is much stronger than simulating a fake process.

Runtime Proof becomes a structured walk over real transition receipts/domain readers.

## 24. Relationship to Intelligence

Shared/Atlas Intelligence may help:

- interpret an event;
- propose Claims/effects;
- classify likely transition family;
- suggest evidence;
- detect possible continuation;
- recognize recurring Actual patterns.

It may not:

- establish a Claim as true by inference alone;
- make an effect effective by classification;
- manufacture authority;
- create a canonical consequence outside a governed command;
- accept its own learning proposal.

The protocol therefore gives Intelligence a powerful role without turning the model into root authority.

## 25. Relationship to manual authoring

The Reality Sentence / Implementation Workbench is one ingress path into this protocol.

Manual authoring should eventually be able to say not only:

> establish this fact

but also:

- record this occurrence;
- record this Claim;
- attach this Evidence;
- propose this effect;
- mark this unresolved;
- invoke this governed domain command;
- record this Actual;
- correct/supersede this prior interpretation.

The Workbench remains a membrane into governed transitions, not a privileged backdoor around them.

## 25A. Production qualification census — 2026-09-21

A read-only production census was used to test whether the protocol is merely theoretical.

Current production contains:

- **4,208 Communication Events**;
- **0 Communication Actionability Assessments**;
- **0 Communication Derived Work Links**;
- **17 Work Result Acceptances**;
- **23 Organization Ledger Entries**, including:
  - 17 `company_work_completed`;
  - 6 `bed_preparation_required`;
- **0 Person Life Consequence Instances**.

One recent Company Work specimen has a complete real chain:

```text
Work Item
→ Execution Result: completed
→ Result Acceptance: accepted
→ Work state: completed
→ Organization Ledger Entry:
   semantic_type = company_work_completed
   truth_status  = established
```

The Execution Result, acceptance, Work completion, and Ledger establishment share the same effective timestamp in that specimen, and each remains a distinct persisted object.

This strongly supports the protocol's separation of:

```text
reported result
≠ accepted result
≠ terminal Work state
≠ Ledger consequence
```

The Communication corpus proves a different and equally important point: a large historical Event corpus may exist while no accepted actionability interpretation or derived Work consequence has yet been established.

Therefore:

```text
Event corpus existence
≠ interpreted consequence corpus
```

The Person Life consequence count is still zero, so the Household/Laundry end-to-end chain remains a source-level candidate proof rather than a live production specimen.

### Qualification decision

The protocol now has **two structurally different live end-to-end domains**.

#### Domain 1 — Company Work

Production contains 17 accepted result chains that distinguish:

```text
Work identity
→ Execution Result
→ Result Acceptance
→ terminal Work state
→ established Organization Ledger consequence
```

#### Domain 2 — Commercial / Financial Reality

Production currently contains:

- 7 Commercial Orders;
- 9 Commercial Order Events;
- 2 Commercial Payments;
- 2 Commercial Payment Events;
- 3 Commercial Fulfillment Events.

Two Registration orders have independent `recorded` order events plus successful Payment evidence and derive paid Financial Reality.

A Flower Sale specimen has an independent `recorded` Commercial Order event and later `fulfilled` Fulfillment event while containing no Payment evidence.

The canonical financial view preserves:

```text
commercial commitment
≠ payment evidence
≠ refund/reversal evidence
≠ fulfillment
≠ settlement position
```

and derives the current financial consequence from immutable source-domain and payment-event evidence rather than storing a mutable “paid” truth flag.

This is structurally unlike Company Work:

```text
Company Work:
work identity → result → adjudication → ledger consequence

Commercial:
domain commercial truth → common commercial representation
→ payment/fulfillment events → derived financial consequence
```

The two domains therefore qualify the **read-only Reality Transition Receipt grammar**.

The qualification is for **projection only**.

It does not justify:

- a universal event table;
- a universal effect table;
- a generic transition writer;
- a generic action registry;
- a generic workflow engine;
- a universal consequence store.

The first executable tranche may now introduce a read-only normalization contract plus **domain-specific adapters for Company Work and Commercial Orders**.

Communication remains valuable negative qualification evidence: 4,208 Events exist with zero accepted actionability assessments and zero derived Work links, proving that an Event may legitimately produce no established downstream consequence.

## 26. No migration yet

This contract creates no executable schema.

The first executable tranche should be **read-only composition**:

`reality_transition_receipt_v1`

over two or more already-live, structurally different domains.

A good qualification set is:

1. Communication → derived institutional consequence;
2. Company Work/result → management/Ledger consequence;
3. one Personal/Household consequence path when the required candidate tranches are released.

Only after those prove stable should Atlas consider whether any generic transition index is justified.

## 27. Resulting architecture

Atlas now has a coherent universal movement law:

```text
what happened
→ what it may mean
→ what is supported
→ what may take hold
→ what did take hold
→ what must become true
→ what actually became true
→ what that resolves/changes
→ what may cautiously be learned next
```

The universality lives in the protocol and receipt grammar.

Truth, authority, custody, execution, Actuals, and learning remain with the domain that can legitimately own them.
