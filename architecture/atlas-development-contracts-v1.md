# Atlas Development Contracts — Standard, Case, Criterion Resolution, Release v1

**Status:** Architecture candidate only  
**Date:** 2026-09-22  
**Parent:** `architecture/atlas-development-domain-v1.md`  
**Executable authority:** none

## 1. Purpose

Define the four canonical contracts required for Development without prematurely selecting physical tables.

The contracts are semantic.

A later executable design may use normalized tables, append-only event history, current projections, or domain adapters as required.

## 2. Contract A — Development Standard Version

### 2.1 Meaning

A Development Standard Version is an immutable definition of the questions/criteria an institution uses to judge whether a class of subjects is sufficiently developed for named release outcomes.

Governing sentence:

> **Institution I defines Standard Version S for subject class C, containing exact criterion definitions and exact release-gate rules that must remain historically reconstructible once used by a Case or Release.**

### 2.2 Identity

Conceptual address:

```text
custody organization / ledger
+ stable standard key
+ version
```

A Version may begin as draft.

Once a Case depends on it, materially changing criterion semantics should create a later version rather than silently rewriting history.

### 2.3 Standard Version content

Minimum conceptual content:

```text
standard identity
title / purpose
eligible subject kinds
version state
criterion definitions[]
release gates[]
provenance
created / established authority
effective window if applicable
supersession relation
```

### 2.4 Criterion Definition

A criterion definition belongs to one exact Standard Version.

Minimum conceptual shape:

```json
{
  "criterionKey": "construction.materials",
  "question": "Are the exact materials required to reproduce this subject established?",
  "rationale": "Another party cannot build it reliably without this.",
  "applicability": {},
  "dependencies": [],
  "allowedResolutionKinds": [],
  "attention": {
    "baseScore": 0,
    "consequenceValue": 0,
    "informationGain": 0,
    "expectedFriction": 0
  }
}
```

Criterion definitions are not answers.

### 2.5 Release Gate

A release gate belongs to one exact Standard Version.

Conceptual shape:

```json
{
  "gateKey": "buildable",
  "label": "Buildable",
  "requiredCriteria": [
    "construction.specification",
    "construction.materials",
    "construction.tools",
    "construction.acceptance"
  ],
  "policyVersion": "..."
}
```

The gate name and criterion membership are domain data.

No universal CI maturity terms belong in platform code.

### 2.6 Standard evidence

The Standard itself may be supported by:

- policy;
- industry guidance;
- institutional experience;
- expert decision;
- prior versions;
- research.

The eventual executable model should preserve provenance.

### 2.7 Standard change

Correct motion:

```text
Standard v1 used by active/historical Cases
+ material criterion/gate change
-> Standard v2
```

The institution may decide whether an existing Case remains bound to v1 or is deliberately rebased/migrated.

No automatic reinterpretation of historical releases.

## 3. Contract B — Development Case

### 3.1 Meaning

A Development Case is the durable institutional container for developing one exact target subject under one exact Standard Version.

Governing sentence:

> **Organization O is developing Subject X under Standard Version S for stated purpose P.**

### 3.2 Target address

A Case must point to an independently real subject or an explicitly proposed subject address.

Conceptually:

```json
{
  "domain": "ci_activity",
  "kind": "activity",
  "ref": "...",
  "versionRef": null
}
```

or:

```json
{
  "domain": "flower_preparation",
  "kind": "procedure_family",
  "ref": "..."
}
```

Development does not create generic copies of the target.

### 3.3 Case state

Candidate lifecycle:

- open;
- paused;
- release_ready;
- released;
- closed;
- cancelled.

This is not final executable schema.

A Case may remain open after one release if the institution intentionally continues development toward additional gates.

### 3.4 Case is not completion

A Case state does not imply every criterion is resolved.

A released Case may have:

- one release gate satisfied;
- other gates still blocked;
- deferred criteria explicitly outside the released class.

### 3.5 Case context

A Case may contain or reference:

- target domain;
- exact Standard Version;
- intended release gates;
- operating context;
- source corpus;
- responsible institutional actors;
- related Development Cases;
- current blockers;
- Work Requirements;
- evidence/claims;
- decisions;
- releases.

These references must not duplicate source-domain authority.

## 4. Contract C — Development Criterion Resolution

### 4.1 Meaning

A Criterion Resolution records the institution's current accounted position for one exact Case criterion.

Governing sentence:

> **For Case C and Criterion K under Standard Version S, the institution currently accounts for K with Resolution R on exact basis B.**

### 4.2 Required identity

```text
Development Case
+ exact Standard Version
+ criterion key
```

A Case must not resolve criteria from an unstated different Standard Version.

### 4.3 Resolution kinds

The architecture must preserve at least these distinctions:

#### established

A subject-specific answer has been institutionally established.

Example:

```text
Washers standard court distance is 25 feet.
```

This resolution should point to the target-domain specification or governed decision that actually owns that answer.

#### inherited

The criterion is satisfied by an already-governed reusable rule.

Example:

```text
CI-wide portable-activity storage rule applies.
```

Basis should point to exact Company Operating Knowledge or other governing rule version.

#### local

The institution deliberately declares this decision belongs to local implementation rather than the canonical specification.

This is an answer about authority/scope, not “unknown.”

#### not_applicable

The Standard criterion does not apply to this subject on an explicit basis.

#### needs_evidence

A plausible answer/candidate may exist, but evidence required by policy is missing or insufficient.

#### deferred

The institution consciously postpones the criterion.

Deferral is not resolution for gates that require the criterion unless the exact gate policy allows deferral.

#### unresolved

No sufficient answer/basis currently exists.

#### conflicted

Material evidence or governing rules conflict such that Atlas must not select a resolution silently.

### 4.4 Resolution history

A Resolution must be historically reconstructible.

Correct patterns include:

```text
unresolved
-> needs_evidence
-> established
```

```text
inherited from Rule v1
-> Rule v1 superseded
-> reconsider
-> inherited from Rule v2
```

```text
established
-> contradictory field evidence
-> conflicted
-> later established by new subject version
```

Do not mutate away the evidence/decision trail.

### 4.5 Resolution basis

A Resolution may reference:

- Operating Knowledge;
- Claims/Evidence;
- Work Result;
- human adjudication;
- source artifact;
- target-domain canonical record;
- external standard;
- another governed resolver result.

The basis is explainable and provenance-bearing.

### 4.6 Handling is separate from resolution kind

The Reconciliation layer may determine that an unresolved Criterion currently requires:

- automatic domain reconcile;
- authority required;
- external evidence required;
- invariant repair required.

Do not encode those handling modes as if they were the Criterion answer itself.

Example:

```text
criterion resolution = needs_evidence
reconciliation handling = external_evidence_required
```

or:

```text
criterion resolution = unresolved
reconciliation handling = authority_required
```

### 4.7 Work relation

A Criterion may justify a Work Requirement.

Conceptually:

```text
Criterion Resolution
-> Development need
-> atlas.work_requirements
-> atlas.work_items
-> results/evidence
-> Criterion reconsideration
```

Work completion alone does not automatically equal Criterion resolution.

## 5. Contract D — Development Release

### 5.1 Meaning

A Development Release is the institution's immutable accounting that an exact target-domain version satisfied one or more exact release gates under one exact Development Standard Version.

Governing sentence:

> **Under Standard Version S, Release Authority A accepted Target Version V as satisfying Gate(s) G on the recorded Criterion Resolution set R.**

### 5.2 Release points outward

The Release must point to the target domain's immutable/versioned output.

Examples:

```text
CI Activity Version 3
Elm Flower Preparation Procedure v2
Manufacturing Work Instruction v6
```

Development is not the specification store.

### 5.3 Release basis snapshot

A release must preserve enough identity to reconstruct:

- Development Case;
- Standard Version;
- target version;
- release gates satisfied;
- exact criterion-resolution identities/states relied upon;
- blockers waived only if the exact gate policy lawfully allows that;
- release authority;
- timestamp;
- provenance.

### 5.4 Release is not “100%”

A Release may satisfy one gate while others remain unsatisfied.

Example:

```text
Washers Activity v2:
  Playable       released
  Teachable      released
  Buildable      not released
  Fundable       not released
```

No global percentage is required.

### 5.5 Revision

Later evidence does not rewrite a prior Release.

Correct motion:

```text
later Evidence
-> Criterion reconsideration
-> new target-domain version if required
-> later Development Release
```

## 6. Derived projections

The following are useful but are not additional canonical roots.

### 6.1 Development Gate Position

Derived per Case/gate:

- satisfied;
- blocked;
- conflicted;
- not applicable.

Includes blocker criterion refs.

### 6.2 Development Attention Candidate

Derived ranking of what deserves attention next.

Possible attributes:

- criterion;
- why now;
- blockers;
- likely handling mode;
- source coverage;
- reusable impact;
- suggested lawful next action family.

### 6.3 Development Decision Requirement

Domain-local projection when Reconciliation says `authority_required`.

It must identify:

- exact Case;
- exact Criterion;
- exact unresolved choice;
- evidence set;
- exact current authority membrane;
- exact command;
- post-decision convergence test.

### 6.4 Development Source Coverage

A read projection saying source material may contain useful evidence for a Criterion.

Coverage does not resolve the Criterion.

## 7. Transition map

### Source admitted

```text
artifact / observation / testimony
-> Evidence
-> candidate Claim / candidate Development interpretation
-> affected Criterion reconsideration
```

### Research commissioned

```text
needs_evidence
-> Work Requirement
-> Work
-> Result
-> Evidence
-> Criterion reconsideration
```

### Expert decision

```text
authority_required
-> Development Decision Requirement
-> human decision
-> Development domain command
-> Criterion Resolution transition
```

### Reusable rule established

```text
Operating Knowledge version established
-> affected Development Cases detect potential inherited basis
-> Criterion reconsideration
```

### Criterion resolves

```text
Criterion Resolution transition
-> Reality Transition Receipt
-> dependent gate Continuation Candidates
-> Development gate resolver
-> satisfied / blocked / conflicted
```

### Release

```text
requested gates satisfied
+ release authority valid
+ exact target-domain version exists
-> Development Release
```

### Later contradiction

```text
new contradictory Evidence
-> Claims/Evidence
-> Criterion reconsideration
-> current position may remain / conflict / require revision
-> no historical release deletion
```

## 8. Promotion gate for executable schema

Do not create universal `atlas.development_*` tables from semantics alone.

A shared executable schema is qualified only after at least two genuinely different Development proofs show the same mechanics for:

1. immutable Standard Version;
2. Case-to-target binding;
3. criterion identity;
4. resolution kinds/basis;
5. evidence/work/decision separation;
6. gate computation;
7. transition/continuation;
8. release accounting;
9. version revision/history;
10. authority separation.

The CI and Elm proof documents perform the first architecture comparison.
