# Atlas Outcome Package — Cross-Domain Candidate v1

**Status:** Architecture candidate only; no schema, migration, RPC, permission, workflow engine, or product surface is authorized by this document.  
**Date:** 2026-09-22  
**First intended proof domain:** Camps International / Camp Duffel  
**Related candidate:** Atlas Person Qualification — Cross-Domain Candidate v1

## 1. Purpose

Many Atlas use cases need more than a document, task list, course, campaign, or workflow.

A Person or institution is trying to produce a real outcome that depends on several already-distinct kinds of truth:

- knowledge or instructions;
- People and institutional relationships;
- qualifications;
- Work;
- physical resources;
- money/funding;
- evidence;
- domain-specific state.

The composition itself needs durable identity without stealing authority from those source domains.

This document names that composition an **Outcome Package**.

The governing sentence is:

> **An Outcome Package Definition is a governed, versioned blueprint that composes source-owned requirements toward an outcome. An Outcome Package Instance applies one exact Definition Version to one real subject/context and derives what remains before the outcome may be considered complete.**

“Outcome Package” is unrelated to historical engineering tranche labels such as “Package 5” or “Package 7.”

## 2. Why this is not a digital binder

An Outcome Package is not a folder of PDFs.

It is also not merely:

- a checklist;
- an LMS course;
- a project;
- an email sequence;
- a fundraising campaign;
- a work order;
- an inventory kit.

It may lawfully reference all of those kinds of reality when they exist, while keeping their authority separate.

For example:

```text
Lead Washers Independently
  requires:
    exact activity method
    preparation Work
    supervised practice
    safety evidence
    observed execution
    recognized Qualification
```

The Package tells Atlas what must come together.

It does not become the authority for the activity method, Work, Evidence, or Qualification.

## 3. Definition and Instance

### Outcome Package Definition

A **Definition** is reusable governed composition.

It answers:

- What outcome is intended?
- What source-owned requirements must be satisfied?
- What dependencies/order constraints exist?
- What completion criteria apply?
- Which Definition Version is this?

A materially changed Definition creates a new version once dependent Instances exist.

### Outcome Package Instance

An **Instance** is one real application of one exact Definition Version.

Examples:

- Maria becoming qualified to lead Washers;
- Iglesia Esperanza building its first Washers set;
- a technician completing one installation package;
- a laboratory member qualifying on Instrument X.

The Instance binds to a real subject/context and tracks composition/progress without copying the source-owned truth that satisfies each requirement.

## 4. Source-owned requirement principle

Every Package requirement must point to or be resolvable through an owning domain.

Conceptually:

```text
Package Requirement
  -> source authority
      -> current satisfaction / unresolved / conflict
```

A Package must not fabricate fulfillment locally when the owning domain has not established it.

Examples:

```text
requires Qualification Q
-> Qualification authority answers whether Person currently has Q

requires Work W
-> Company Work / responsibility / result authority answers state

requires $500 funding
-> Money / nonprofit stewardship authority answers funded position

requires 18 washers
-> CI/physical-resource domain answers whether suitable resources exist

requires Activity Method v3
-> CI methodology authority supplies the exact definition
```

## 5. Candidate requirement families

The following families recur across the cross-domain tests.

They are architecture categories, not authorization for one generic EAV table.

### 5.1 Knowledge / method exposure

A Package may require someone to encounter, study, review, or use an exact governed method/content version.

The Package does not become a document store or knowledge authority.

Evidence that a Person actually reviewed or demonstrated understanding belongs to the appropriate Work, Teaching, Evidence, or domain contract.

### 5.2 Qualification

A Package may require an existing Qualification or may culminate in a Qualification recognition process.

The Package does not manufacture Qualification by reaching 100%.

### 5.3 Work / commitment

A Package may require Work to be performed.

The Package may cause source-owned Work to be created through a lawful command, but Package membership itself is not Work responsibility.

### 5.4 Physical resource availability

A Package may specify that certain resources must exist, be available, or be in custody.

The Package does not own inventory.

The cross-domain audit shows that resource lifecycle semantics differ too much to promote one generic Resource/Inventory model merely for Package convenience.

### 5.5 Money / funding

A Package may express a monetary requirement or depend on a source-owned financial state.

Examples:

- construction budget funded;
- fee paid;
- donation designation satisfied;
- approved spending limit available.

The Package does not become the General Ledger, donation ledger, Commercial Order, or bank reconciliation system.

### 5.6 Evidence

A Package may require evidence that a condition occurred.

It consumes existing governed Evidence semantics rather than creating a parallel attachment/checkoff truth system.

### 5.7 Domain state

A Package may require a domain-owned state such as:

- Activity built;
- Course completed;
- camp approved;
- site ready;
- equipment inspection current.

The owning domain defines the meaning.

## 6. Dependencies and “next thing”

A Definition may express dependencies among requirements.

Example:

```text
Read basic Washers method
  -> play it
  -> observe qualified leader
  -> supervised lead
  -> independent demonstration
  -> qualification review
```

This allows Atlas to derive the smallest useful next action.

The Package should answer:

> Given the currently satisfied source-owned requirements, what is the next lawful thing this Person/team can do?

That is different from a generic workflow engine.

A workflow engine owns transitions. An Outcome Package composes and observes domain transitions while issuing commands only through those domains' lawful seams.

## 7. Completion

Package completion must be explainable.

It should derive from the exact Definition Version and its required criteria.

Do not allow:

```text
user checked all boxes
-> outcome is true
```

unless the Definition explicitly defines those acknowledgements as the authoritative completion evidence.

For substantive outcomes, completion typically means every required source-owned condition is satisfied with no blocking conflict.

## 8. Unresolved and blocked states

A Package must preserve uncertainty.

Examples:

- Qualification evidence incomplete;
- resource count unknown;
- donation received but designation ambiguous;
- required Work has no responsible Person;
- safety inspection expired;
- conflicting source evidence.

The Package may present the blockage and route the next lawful action.

It must not guess through the missing state.

## 9. Communication consequence

Communication is cross-cutting.

Package state may lawfully cause communication consequences such as:

```text
Instance created
-> welcome/preparation correspondence

training requirement due soon
-> reminder

requirement satisfied
-> stop reminder

Package blocked
-> notify responsible actor if communication policy says so

Package complete
-> send completion/follow-up correspondence
```

The durable communication remains in Atlas's institutional Communication contracts.

The Package does not own an email sequence.

## 10. Fundraising and volunteer projection

Outcome Packages provide a clean outward-facing bridge without turning fundraising or volunteering into separate shadow systems.

An Instance may expose unmet source-owned requirements such as:

```text
needs $125
needs 18 washers
needs one builder
needs one qualified trainer
needs transportation
```

Different projections may then show:

- donor: fund this requirement;
- volunteer: take this available Work;
- purchaser: acquire these materials;
- trainer: perform this observation;
- director: see blockers.

A donor-facing projection does not create money truth. A volunteer-facing projection does not assign responsibility merely because someone clicked it. Each uptake goes through its owning authority.

## 11. Versioning

Once an Instance depends on a Definition Version, its intended outcome/requirements must remain historically intelligible.

Conceptually:

```text
Definition v1
-> Instance A bound to v1

Definition materially changes
-> publish v2
-> Instance A remains bound to v1 unless a governed migration/rebase occurs
-> future Instance B may use v2
```

No silent rewrite of consequential requirements.

## 12. Package progress is projection

A percentage may be useful presentation, but it is not canonical truth unless the domain explicitly defines a mathematical progress law.

Atlas should prefer explainable progress:

```text
5 of 7 required conditions satisfied
1 blocked
1 awaiting evidence
```

rather than inventing a universal percentage.

## 13. Camp Duffel first proof

The first proof should deliberately stay smaller than “Run a Camp.”

### Definition A: Build a Washers Set

Potential composition:

- exact Washers construction definition;
- materials requirement;
- tools requirement;
- funding requirement if CI/church does not already have materials;
- builder Work;
- construction/inspection evidence;
- resulting CI-domain resource state.

The outcome is not “all tasks checked.”

The outcome is:

> a usable Washers set exists under CI's defined construction/safety criteria.

### Definition B: Lead Washers Independently

Potential composition:

- exact activity method/version;
- required reading/orientation Work;
- play/participation;
- observe qualified leader;
- practice instructional script;
- safety demonstration;
- supervised lead;
- independent lead;
- trainer evidence;
- Person Qualification recognition.

The outcome is:

> the institution recognizes this Person as qualified to lead Washers independently.

### Joined consequence

When a real camp later needs Washers:

```text
Camp implementation
  requires usable Washers set
  requires qualified leader
  requires place/time
  requires exact Work assignment
```

The Package can expose those requirements without owning Camp, Qualification, Inventory, Place, Schedule, or Work.

## 14. Cross-domain comparison

The same composition pattern appears in different domains:

| Domain | Example Outcome Package |
|---|---|
| Camp development | Build Washers / Become Washers leader |
| Skilled trades | Replace water heater |
| Emergency response | Stand up shelter team |
| Healthcare | Implement bounded care workflow |
| Agriculture | Establish a crop/process practice |
| Research | Run assay / qualify on instrument |

The nouns differ. The composition law is similar:

```text
outcome
+ exact definition
+ qualified people
+ work
+ resources
+ money where relevant
+ evidence
+ domain conditions
-> explainable completion
```

This is architectural evidence only until two executable domains prove the same mechanics.

## 15. What must not be generalized for Package convenience

Do not create a universal:

- Resource table;
- Inventory table;
- Knowledge table;
- Rule table;
- Attachment/evidence clone;
- Task clone;
- Payment clone;
- Email sequence table;
- arbitrary JSON/EAV requirement store.

Package composition is not permission to erase existing Atlas domain boundaries.

## 16. Promotion gate for universal executable Package schema

A shared executable Package kernel requires two genuinely different implemented domains.

Before promotion, compare:

1. definition/version identity;
2. instance identity;
3. requirement addressing;
4. requirement dependency mechanics;
5. source-owned satisfaction checks;
6. unresolved/conflict behavior;
7. completion derivation;
8. consequence issuance;
9. provenance/history;
10. authority boundaries.

If those mechanics do not actually match, retain Outcome Package as a reusable architecture pattern rather than a universal runtime.

## 17. First implementation consequence

For CI work now:

- model Build Washers and Lead Washers as the first two **Outcome Package-shaped** implementations;
- keep Activity, construction, physical resources, Work, Money, Evidence, and Qualification separate;
- make the user's next actionable step derivable from real unmet requirements;
- make outward donor/volunteer/trainer projections consume the same Instance rather than duplicate it;
- do not yet create generic `atlas.outcome_packages` tables.

That gives CI one coherent implementation model while preserving Atlas's promotion discipline.
