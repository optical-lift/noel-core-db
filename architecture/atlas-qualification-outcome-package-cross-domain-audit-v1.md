# Qualification + Outcome Package — Cross-Domain Qualification Audit v1

**Status:** Cross-domain architecture qualification record  
**Date:** 2026-09-22  
**Scope:** Determine what may be generalized from the Camps International / Camp Duffel digitization problem without violating Atlas's no-speculative-universal rule.

## 1. Domains compared

The audit compares six structurally different settings:

1. Camps International / Camp Duffel;
2. skilled trades / field service;
3. emergency and disaster response;
4. healthcare operations;
5. agriculture / extension / multi-site farm operation;
6. university/research laboratory operation.

The comparison is intentionally broader than six organizations using the same software category.

## 2. Candidate universal concepts tested

The CI design initially surfaced these possible common nouns:

- Actor;
- Knowledge;
- Place/Context;
- Capability;
- Resource;
- Commitment/Work;
- Finance;
- Implementation;
- Evidence;
- Package.

Current Atlas source already owns several of these more precisely.

Therefore this audit asks two questions:

1. Does Atlas already have a canonical authority for this reality?
2. Where it does not, do the six domains demonstrate the same semantic relation strongly enough to reserve a cross-domain candidate?

## 3. Results

### 3.1 Person / Organization / institutional relationship

**Decision:** already universal Atlas territory.

Reuse:

- canonical Person;
- Organization;
- Organization Unit;
- Membership;
- Position/Appointment;
- durable institutional Responsibility.

Do not create CI-local donor/counselor/volunteer user identities when roles/relationships can attach to the same Person.

### 3.2 Work / responsibility / execution

**Decision:** already universal Atlas territory.

Reuse:

- durable institutional responsibility;
- exact Company Work responsibility;
- execution authority/handoff.

A Package may require Work but must not make Package checkoff equal responsibility.

### 3.3 Evidence / claims

**Decision:** already universal Atlas substrate/pattern.

Reuse claims/evidence/provenance rather than creating training-specific attachments whose only job is to prove something occurred.

### 3.4 Communication

**Decision:** already universal Atlas institutional territory.

Use communication events/conversations and provider-neutral transport.

Do not build ConvertKit-like sequence state as the source of who should receive training communication.

### 3.5 Money

**Decision:** Atlas has universal monetary/commercial foundations, but nonprofit stewardship is a separate future domain.

Do not treat a donation as a Commercial Order.

Future nonprofit work likely needs first-class gift/designation/fund/restriction semantics while reusing universal Money/Financial Reality where the mechanics match.

### 3.6 Capability

**Decision:** terminology collision.

Current Atlas `capability_activations` means a software/domain capability is activated in a governed Ledger.

Human ability must not reuse that noun.

Reserve:

- **Competency** = ability that can be demonstrated;
- **Qualification Standard** = governed criteria;
- **Person Qualification** = institutional recognition under the Standard.

### 3.7 Qualification

**Decision:** strongest new cross-domain candidate.

All six domains require a distinction between:

```text
Person participated / was assigned / has access
!=
institution currently recognizes Person as able to perform X to standard Y
```

Shared semantic skeleton:

```text
Person
+ Institution
+ Standard Version
+ Scope / Level
+ Evidence
+ Recognition
-> Qualification
```

The concept is qualified for architecture vocabulary.

It is **not yet qualified for a universal executable schema** because a second genuinely different implementation has not yet proved identical transition mechanics.

### 3.8 Outcome Package

**Decision:** second strong cross-domain candidate.

All six domains need a durable composition answering:

```text
What outcome are we trying to produce?
What must be true?
What must someone know?
What Work must happen?
What qualifications are required?
What resources/money are needed?
What evidence proves completion?
What is the next lawful action?
```

Shared semantic skeleton:

```text
Definition Version
-> Instance
-> source-owned requirements
-> dependency-aware satisfaction
-> explicit blockers/conflicts
-> explainable completion
-> governed consequences
```

Again, this is qualified as architecture vocabulary/pattern, not yet as a universal executable engine.

## 4. Negative results

The audit rejects several tempting generic nouns.

### No universal Resource/Inventory object yet

The lifecycle of:

- metal washers;
- HVAC parts;
- shelter cots;
- medication;
- seed;
- laboratory reagents/instruments

is not equivalent merely because all are “resources.”

Outcome Packages may express requirements for them while source domains retain their own semantics.

### No universal Knowledge object

Activity methodology, clinical procedure, research protocol, farm practice, and commercial policy may share governance principles without sharing one executable truth model.

Use domain nouns and existing Governed Contextual Interpretation law where applicable.

### No universal Rule Engine

The existing Package 7 cross-domain abstraction audit remains governing: conceptual resemblance is insufficient to promote a generic resolver/adjudication engine.

### No universal Email Sequence

Communication should follow governed reality and responsibility.

Sequence membership is not a new institutional truth root.

### No generic EAV Package Requirement store

Package composition must not become a JSON escape hatch that re-encodes all domains in one table.

## 5. First proof selection: Camp Duffel Washers

Washers is a strong first proof because one activity already contains:

- identity and category;
- player capacity;
- setup;
- materials;
- construction implications;
- progressive instruction;
- safety;
- rules;
- teaching/illustration material;
- site variation;
- trainer guidance;
- a natural path from novice to independent leader.

Two separate outcomes should be modeled:

```text
Build a Washers Set
Lead Washers Independently
```

This forces Atlas to preserve the distinction between:

- activity methodology;
- physical equipment existence;
- preparation Work;
- trainer observation;
- Evidence;
- Person Qualification;
- later camp assignment.

If one table/checklist tries to own all of these, the proof fails.

## 6. Second executable proof strategy

### Qualification candidate

Atlas Teaching is the strongest internal second-domain candidate after it gains:

```text
Learning Activity
-> Assessment
-> Submission
-> Evaluation
-> Completion
```

The comparison should test whether teaching-domain evaluation can lawfully feed the same Standard/Evidence/Recognition mechanics as CI activity qualification.

Do not force academic Completion to equal Qualification.

### Outcome Package candidate

A later Teaching or non-CI implementation can test whether a multi-requirement outcome composition has the same:

- exact Definition Version binding;
- source-owned requirement checks;
- dependency law;
- blocker semantics;
- completion derivation.

Until then, CI should implement the shape without creating a universal package engine.

## 7. Fundraising / volunteer / training consequences

The Package pattern explains how these later surfaces can share one source of reality.

Example CI Instance:

```text
Build Washers — Iglesia Esperanza
```

Unmet requirements may project as:

```text
$125 funding required
18 washers required
1 builder Work item unclaimed
construction evidence missing
```

Then:

- donor surface sees the monetary need;
- purchasing surface sees material need;
- volunteer surface sees available Work;
- trainer/director surface sees remaining proof;
- communication follows state changes.

These are projections of the same implementation, not five disconnected campaigns/lists.

## 8. Architecture decision

At this boundary:

**Promote to architecture vocabulary/pattern:**

- Competency;
- Qualification Standard;
- Person Qualification;
- Outcome Package Definition;
- Outcome Package Instance.

**Do not yet promote to universal executable database authority:**

- generic Qualification tables;
- generic Package tables;
- generic Requirement EAV;
- universal Resource/Inventory;
- universal Knowledge;
- universal Rule Engine;
- email-sequence state.

## 9. Next work

The next safe tranche is domain proof, not horizontal schema promotion:

1. recover one canonical CI Activity model from Washers;
2. define CI's Standard for “Lead Washers Independently”;
3. define CI's two first Outcome Package-shaped compositions:
   - Build a Washers Set;
   - Lead Washers Independently;
4. map each requirement to its owning Atlas/domain authority;
5. identify which missing source-owned domains must exist before execution;
6. only then decide the smallest CI executable schema.

This preserves the user's goal — build CI as a transferable operating system — without turning CI's first implementation into speculative Atlas universals.
