# Atlas Development Domain v1

**Status:** Architecture candidate; no production schema, migration, RPC, permission, or UI authority is created by this document.  
**Date:** 2026-09-22  
**Purpose:** Define Development as a native Atlas operating domain for turning incomplete expert practice into reproducible, governed specifications without collapsing research, evidence, work, institutional judgment, or released domain truth into one generic workflow.

## 1. Governing problem

Many institutions possess valuable practical knowledge that is not yet reproducible.

The institution may know how to do something because one or two experienced people can do it, while still lacking some combination of:

- exact specifications;
- acceptable ranges;
- materials;
- cost;
- safety boundaries;
- quality criteria;
- local adaptation rules;
- training requirements;
- test evidence;
- completion semantics;
- maintenance;
- release/version discipline.

The hard institutional work is not document formatting. It is making, testing, preserving, revising, and governing the decisions required so another person can reproduce the result.

Atlas needs a native operation for this motion:

```text
tacit / fragmented practice
-> explicit unresolved criteria
-> source recovery
-> research / prototype / field work
-> evidence
-> institutional decision
-> criterion resolution
-> maturity / release-gate reconsideration
-> released domain specification
-> later evidence and revision
```

This document calls that operation **Development**.

## 2. Development is not Implementation

Atlas Implementation Case already has a locked meaning:

> one paid assisted Atlas implementation engagement.

That meaning must remain intact.

A client may have an Implementation Case while Optical Lift helps establish their Atlas.

After activation, the client's ordinary institutional work may include:

- developing a camp activity;
- developing a manufacturing procedure;
- developing a farm production practice;
- developing a shelter method;
- developing a training standard.

Those are not Atlas implementation engagements.

Therefore Development reuses proven implementation **mechanisms and constitutional distinctions** without reusing `implementation_cases` as the permanent container.

## 3. Development is not a generic workflow engine

Development does not own every transition needed to produce an outcome.

It composes and observes source-owned reality.

Examples:

- Company Work owns research/prototype/test work;
- Claims/Evidence owns observations and support/contradiction;
- Company Operating Knowledge owns established institutional standards/procedures where applicable;
- Money owns financial truth;
- Communication owns correspondence;
- the target domain owns its released specification;
- Qualification may later own institutional recognition of human competency.

Development owns only the durable **development problem**, the governing **development standard**, the explicit **criterion-resolution state**, and the **release accounting** that proves why a target-domain version was accepted.

## 4. Existing Atlas mechanisms reused

### 4.1 Ledger Capability Activation

The selected Ledger capability architecture is the eventual activation seam.

When capability activation becomes executable, Development should be activated as:

```text
governing Ledger
+ capability definition: development
+ governed subject
-> Development available
```

Do not create a Development-local owner/admin/seat system.

### 4.2 Company Operating Knowledge

Company Operating Knowledge already provides:

- candidate / established / disputed / superseded / retired states;
- standards, procedures, quality requirements, completion semantics, policy and other knowledge kinds;
- evidence;
- append-only adjudication;
- immutable established semantics;
- exact versioning;
- scope matching;
- specificity and precedence;
- explicit conflict instead of silent tie-breaking.

Development should use established Operating Knowledge as **inherited criterion basis** where the institution has already governed a reusable rule.

Development does not copy those rules into every Case.

### 4.3 Claims and Evidence

Claims/Evidence already separates:

```text
what was observed/reported
!=
what the institution concludes it means
```

Development uses this for:

- prototype measurements;
- field observations;
- photos;
- costs/receipts;
- test results;
- source testimony;
- contradictions;
- corrections;
- later evidence against an existing decision.

A Criterion may be unresolved despite abundant Evidence.

### 4.4 Reality Discovery mechanics

Personal Reality Discovery has already proved a useful deterministic pattern:

```text
existing evidence
+ prerequisites
+ consequence value
+ information gain
- friction
+ contextual boosts/suppression
-> next useful unresolved question
```

Development should reuse this **ranking law/pattern**, not the Personal Reality Discovery tables.

A Development attention projection should ask:

> Which unresolved criterion is worth institutional attention next?

It should prefer recovering existing evidence before asking a human to recreate it.

### 4.5 Artifact interpretation

Implementation artifact interpretation has already proved:

```text
source artifact
-> derivative transcript/extraction
-> exact evidence excerpt
-> candidate finding/question
-> human review
```

with no machine truth authority.

Development should promote this pattern into a source-admission adapter so old manuals, photographs, field notes, receipts, voice notes, videos, and other records can reduce expert re-entry labor.

### 4.6 Reality Sentence / Reality Candidate

Atlas's Reality Authoring contract already establishes:

> a sentence is a human interface to governed commands, not a truth store.

Development should support statements such as:

```text
This design still needs field evidence.
This criterion is intentionally local.
CI accepts this construction specification.
The prior cost basis is superseded.
```

Where a lawful Development command exists, the sentence may resolve to it.

Where no command exists, the proposal remains durable and unresolved.

### 4.7 Company Work

Company Work already provides:

```text
Requirement
-> Work
-> responsibility
-> dependencies
-> time
-> execution/result
```

An unresolved Development Criterion is not itself Work.

It may create or justify a Work Requirement.

Examples:

```text
Criterion: actual materials cost is unknown
-> Work: price the exact materials

Criterion: portable design not validated
-> Work: build prototype
-> Work: field-test prototype

Criterion: safety behavior uncertain
-> Work: observe/test under controlled conditions
```

Work Result returns evidence. It does not automatically resolve the Criterion.

### 4.8 Commitment Ledger

A deliberate Development campaign may use Commitment Plans.

Example:

```text
Spring campaign: make 20 activities Buildable
```

The Commitment Ledger preserves what Atlas committed to people and how that plan changed.

Development does not need a second campaign/task planner.

### 4.9 Communication

Requests, reminders, assignments, evidence requests, and decision notices should use institutional Communication.

Communication follows Development reality.

An email sequence is not Development state.

### 4.10 Reality Transition, Continuation, Reconciliation

These platform laws are central.

A Criterion resolution is a consequential transition.

That transition may cause dependent Development gates to be reconsidered.

A continuation may classify into:

- automatic domain reconcile;
- authority required;
- external evidence required;
- invariant repair required;
- settled;
- not applicable.

Development must not build a competing workflow state machine.

### 4.11 Decision Requirements

When a Development continuation requires human judgment, Atlas should surface an exact domain-local Decision Requirement to an actor with the exact authority required to decide it.

Example:

```text
two prototype designs have sufficient evidence
-> CI must choose canonical portable design
-> authority_required
-> exact Development Decision Requirement
-> authorized human establishes resolution
```

The requirement is a projection, not a queue truth root.

### 4.12 Semantic Interaction Runtime

The selected future runtime provides the correct interaction model.

A visible Criterion can become a SemanticTarget.

Its lawful actions depend on state:

```text
needs evidence
-> add evidence / request evidence / create investigation Work

authority required
-> inspect evidence / decide / keep unresolved

inherited
-> inspect governing standard

deferred
-> inspect deferral basis / reopen when authorized
```

The UI does not invent those actions.

## 5. Four canonical Development contracts

Development introduces exactly four architecture roots.

1. **Development Standard Version**
2. **Development Case**
3. **Development Criterion Resolution**
4. **Development Release**

Supporting criterion definitions and release gates are children of an exact Standard Version, not additional institutional truth roots.

These contracts are defined in the companion contract document.

## 6. Development Standard Version

A Standard Version defines what the institution must resolve before a subject can satisfy one or more development/release classes.

It may define:

- criterion keys;
- human-readable questions;
- rationale;
- dependencies;
- applicability conditions;
- evidence expectations;
- allowable resolution kinds;
- attention-ranking metadata;
- named release/maturity gates;
- which criteria block each gate.

The Standard does **not** provide the answers for a Case.

Example CI release gates may include:

- Playable;
- Teachable;
- Buildable;
- Portable;
- Fundable;
- Replicable;
- Trainer-ready.

Those names are CI data.

Development must not hard-code them universally.

## 7. Development Case

A Case binds:

```text
Organization / Ledger custody
+ exact target subject address
+ exact Development Standard Version
+ development purpose
-> durable Development Case
```

The Case survives changes in understanding.

It does not copy or convert the subject.

Examples:

```text
CI Activity: Washers
-> Develop as a reproducible mobile/inexpensive/newly-learned camp activity

Elm production practice: cut-flower bunch preparation
-> Develop as an executable/delegable operating procedure
```

## 8. Development Criterion Resolution

Each exact Case + Standard Criterion has an explainable current position.

The universal architecture must be able to represent at least:

- unresolved;
- established specifically for this subject;
- inherited from governed Operating Knowledge or another lawful source;
- intentionally local/context-owned;
- not applicable;
- needs evidence;
- deferred;
- conflicted.

These labels may later be normalized into a smaller executable state machine.

The critical law is:

> A Criterion is not resolved because someone checked a box.

Every resolved position must identify its basis.

Examples:

```text
inherited
-> exact Operating Knowledge version/ref

established
-> exact decision + evidence + target-domain specification ref

needs evidence
-> exact missing evidence class / investigation need

local
-> exact statement that the decision belongs to local implementation rather than canonical specification

not applicable
-> exact applicability basis
```

## 9. Development Release

A Development Release records:

> Under Standard Version S, the institution accepted target-domain specification/version V as satisfying release class/gate G on basis B.

The Release does not own the specification.

The target domain does.

Examples:

```text
Development Release
-> CI Activity Version 3 is Buildable + Teachable

Development Release
-> Elm Bunch Preparation Procedure v2 is Delegable
```

Release history is immutable.

Later evidence creates revision pressure and a later target-domain version / Development Release.

## 10. Development attention projection

Development should have a read-only **Attention Candidate** projection.

It is not a fifth canonical root.

The projection should rank unresolved criteria using factors such as:

- gate consequence / number of blocked release classes;
- information gain;
- prerequisites satisfied;
- reusable impact on other Cases;
- available source coverage;
- human friction;
- evidence freshness;
- authority availability;
- whether another subject may already have solved the same class of question.

The key product sentence is:

> **Ask the smallest useful question or commission the smallest useful work that removes the largest amount of unresolved institutional remembering.**

The engine should be able to say:

```text
Do not ask David yet:
three source artifacts may already contain the answer.
```

or:

```text
Give this to a volunteer:
current hardware-store pricing is missing.
```

or:

```text
David's judgment is required:
two sufficiently tested alternatives remain.
```

## 11. Inheritance

Development inheritance is a resolution source, not class inheritance in application code.

Conceptually:

```text
subject-specific established specification
  > family-scoped established Operating Knowledge
  > institution-wide established Operating Knowledge
```

Exact precedence is owned by the applicable Operating Knowledge resolver/domain.

If two equally authoritative established rules conflict, Development receives conflict.

It must not silently choose.

## 12. Development maturity is categorical, not percentage

Do not show:

```text
Washers 83% complete
```

A useful projection is:

```text
Playable        satisfied
Teachable       satisfied
Buildable       blocked by 2 criteria
Portable        needs field evidence
Fundable        current cost basis missing
Replicable      blocked by 4 criteria
Trainer-ready   qualification standard unresolved
```

A Case can be extremely valuable before every gate is satisfied.

## 13. Release-gate reconsideration

When any Criterion Resolution changes:

```text
Criterion transition
-> Reality Transition Receipt
-> Development continuation discovery
-> affected gate resolvers reconsider
-> gate becomes satisfied / remains blocked / conflicts / not applicable
```

One resolved Criterion does not imply Case completion.

One gate satisfying does not imply all gates satisfy.

## 14. Revision after release

Released reality is not frozen from learning.

Later Evidence may challenge it.

Correct motion:

```text
new evidence
-> Claim / Evidence
-> development reconsideration
-> current release may remain valid, become disputed, or require revision
-> new target-domain version
-> new Development Release
```

Do not rewrite the old release/specification in place.

## 15. Authority

Development authority is institutional.

Different operations may require different authority:

- contributing evidence;
- creating Work;
- adjudicating a Criterion;
- declaring a criterion local/not-applicable;
- releasing a specification;
- retiring/superseding a Standard.

Do not infer these from technical access.

No new generic Development admin role is authorized here.

## 16. What Development must not become

Do not create:

- a generic EAV “development facts” table;
- a generic Resource table;
- a generic Knowledge table;
- a new workflow engine;
- a second Company Work system;
- a second Claims/Evidence system;
- a shadow Communication sequence system;
- a generic AI truth authority;
- a fake completion percentage;
- an Implementation Case renamed for ordinary organizational R&D.

## 17. Promotion discipline

This architecture should be proved against at least two genuinely different domains before a universal executable Development schema is promoted.

The first selected comparisons are:

1. Camps International — develop Washers as a reproducible camp activity.
2. Elm Farm — develop an operating procedure from established flower-preparation/bunching knowledge.

The companion proof documents perform that audit.

Until the mechanics survive both, this document is architecture, not production authority.
