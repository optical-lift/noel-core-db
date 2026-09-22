# Atlas Development Proof — Camps International Washers v1

**Status:** Architecture proof; no executable Development schema authorized  
**Date:** 2026-09-22  
**Domain:** Camps International / Camp Duffel activity development  
**Target:** Washers  
**Primary source basis:** David G. Caldwell, *Washers — Camp Counselor Instructional Script to Campers*, Camps International, Version 1.00, 2026-09-21

## 1. Proof question

Can the proposed Development contracts represent the actual institutional labor required to turn Washers from expert practice/source material into a mobile, inexpensive, newly learned, locally reproducible camp activity without forcing all of that labor into one manual?

## 2. Existing source-backed knowledge

The current source already establishes substantial activity knowledge, including:

- activity identity: Washers;
- friendly competition / throwing;
- supported player counts of 2, 3, 4, or 6 per set of pits;
- approximately 3 minutes per round and approximately 15 minutes per game depending on final score;
- core physical skill: accurately tossing a washer;
- two pits per group of up to six;
- a progressive instructional-script method;
- facilitator and co-facilitator roles;
- safety behavior requiring people at the opposite pit to remain clear while washers are thrown;
- a relationship/teaching purpose beyond merely winning the game;
- Scripture/illustration material.

These are not “unfinished manual prose.”

They are recoverable subject knowledge.

## 3. Important source gaps

The current source does not by itself establish a complete reproducible activity specification for every CI goal.

Material gaps include:

- reliable construction drawing/specification;
- complete bill of materials;
- exact tool list;
- portable vs permanent construction variants;
- build time;
- current real-world cost;
- inspection/acceptance criteria;
- maintenance/storage/replacement rules;
- formal trainer standard for independent leadership;
- exact qualification levels, if any;
- who may recognize the qualification;
- refresh/expiration policy, if any;
- formal site-adaptation rules;
- formally governed difficulty/variation ladder;
- complete follow-up/discipleship projection.

The Development system must preserve these as explicit unresolved institutional questions rather than treating the activity as either “finished” or “missing.”

## 4. Candidate CI Activity Development Standard v1

This Standard is a proof model, not current CI canonical policy.

It could define criterion families such as:

### Identity / purpose

- activity identity/category;
- intended purpose;
- player/group shape;
- age/context applicability.

### Play

- setup;
- simple play;
- full rules;
- duration/capacity;
- variations / difficulty.

### Teaching

- instructional method;
- facilitator/co-facilitator behavior;
- teachable moments;
- illustration/Scripture;
- follow-up.

### Physical reproduction

- materials;
- construction specification;
- tools;
- portable/local-build variants;
- storage;
- maintenance;
- repair.

### Stewardship

- current cost basis;
- funding unit;
- replacement cost where relevant.

### Safety / suitability

- hazards;
- controls;
- site dimensions;
- age adaptations;
- acceptance/inspection criteria.

### Human transfer

- preparation requirements;
- competency standard;
- assessment evidence;
- recognition authority;
- refresher/expiry if applicable.

## 5. Candidate CI release gates

Again, these are CI-domain data, not universal platform enum values.

```text
Playable
Teachable
Buildable
Portable
Fundable
Replicable
Trainer-ready
```

The same Activity Version may satisfy some without satisfying all.

## 6. Development Case

Conceptual Case:

```text
Organization: Camps International
Target: CI Activity / Washers
Standard Version: CI Activity Development Standard v1
Purpose:
  make Washers reproducible as a mobile,
  inexpensive, newly-learned camp activity
State: open
```

This is not an Atlas Implementation Case.

It is CI's own operating work.

## 7. Criterion examples

### 7.1 Player capacity

```text
Criterion:
supported player/group shape

Resolution:
established

Basis:
Washers source v1.00
2 / 3 / 4 / 6 players
```

### 7.2 Instructional method

```text
Criterion:
new facilitator can teach the activity using the intended CI method

Current position:
partially established / evidence-backed

Basis:
source explicitly defines progressive need-to-know instruction
and immediate interaction
```

If CI's Development Standard requires a separate novice field-validation threshold, the Criterion may still need evidence despite the method being documented.

### 7.3 Construction specification

```text
Criterion:
another church can construct a compliant Washers set

Resolution:
unresolved / needs_evidence

Known:
two pits, 25-foot relationship, 4-inch recessed cup are referenced

Missing:
sufficient construction specification / acceptance criteria
```

### 7.4 Current cost

```text
Criterion:
current cost basis is sufficient for donor/build projection

Resolution:
needs_evidence

Handling:
external_evidence_required
```

Lawful next action may be Company Work:

```text
Price exact Washers build materials
```

The person doing this does not need authority to define CI methodology.

### 7.5 Portable design

Possible path:

```text
unresolved
-> prototype A proposed
-> Work: build/test
-> Evidence
-> prototype B proposed
-> Work: build/test
-> Evidence
-> authority_required
-> CI authority chooses released design
-> established
```

This is the exact kind of 30-year development labor the system must make visible and distributable.

### 7.6 Opposite-pit throwing safety

The source already provides a concrete safety behavior.

Depending on CI's Standard, that may resolve one narrow Criterion while a broader formal risk-control Criterion remains unresolved.

Development must not inflate one source sentence into a complete safety system.

## 8. Source recovery before expert questioning

A Development Attention projection should not ask David:

> How many players can play Washers?

That answer already exists.

It should instead say:

```text
Recovered from source:
2 / 3 / 4 / 6 players.
Confirm only if policy requires confirmation.
```

For construction, it might say:

```text
Found:
25-foot throw distance
4-inch cup reference
two pits

Still missing:
buildable pit dimensions/material design
```

This turns expert labor from blank-page authorship into adjudication of exact gaps.

## 9. Work delegation proof

The Development architecture cleanly separates work types.

### Volunteer / purchaser

```text
Work:
obtain current local prices for exact material list
```

### Builder

```text
Work:
construct prototype under candidate build specification
```

### Traveling team

```text
Work:
field-test setup time / portability / participant behavior
```

### Trainer

```text
Work:
observe novice facilitator and record evidence
```

### David / governing authority

```text
Decision Requirement:
choose between sufficiently evidenced design alternatives
or establish the teaching/qualification standard
```

David no longer owns every research task merely because he owns important methodology judgment.

## 10. Inheritance proof

Some future CI rules should be established once and inherited.

Examples of candidate institutional standards might include:

- local sourcing preference;
- portability constraints;
- interaction-first teaching principles;
- storage expectations;
- counselor-group structure;
- safety-timing principles.

Development should not copy such rules into Washers.

A Washers Criterion can resolve as:

```text
inherited
-> exact CI Operating Knowledge version
```

If Washers has a valid exception, that exception becomes subject-specific governed truth.

## 11. Gate reconsideration proof

Suppose:

```text
construction.materials = established
construction.tools = established
construction.specification = established
construction.acceptance = unresolved
```

Then:

```text
Buildable = blocked by construction.acceptance
```

When acceptance criteria become established:

```text
Criterion transition
-> Continuation Candidate for Buildable gate
-> Development resolver recomputes
-> Buildable may become satisfied
```

Replicable may still remain blocked by maintenance or trainer criteria.

This matches current Atlas continuation law.

## 12. Release proof

A valid Development Release might eventually say:

```text
Target:
CI Washers Activity Version 3

Standard:
CI Activity Development Standard v1

Released gates:
Playable
Teachable
Buildable
Portable
Fundable

Not yet released:
Trainer-ready
Replicable

Basis:
exact criterion-resolution snapshot
```

The CI Activity domain owns Activity Version 3.

Development records why it passed those gates.

## 13. Result

The four Development contracts fit CI Washers without requiring:

- a document-as-database model;
- a generic task checklist;
- a new workflow engine;
- AI truth authority;
- David to answer already-documented questions again;
- every missing answer to become David's personal work.

The proof therefore supports Development as an architecture candidate.
