# Atlas Person Qualification — Cross-Domain Candidate v1

**Status:** Architecture candidate only; no schema, migration, RPC, permission, or product surface is authorized by this document.  
**Date:** 2026-09-22  
**First intended proof domain:** Camps International / Camp Duffel  
**Likely second executable comparison domain:** Atlas Teaching after learner evaluation/completion exists

## 1. Purpose

Atlas needs to distinguish between:

- a Person having access to a system;
- a Person belonging to an institution;
- a Person carrying responsibility;
- a Person being assigned exact Work;
- a Person having encountered or completed training material;
- and an institution currently recognizing that the Person can perform something to an accepted standard.

The last relation is not yet represented by a canonical Atlas-wide noun.

This document names that relation **Person Qualification**.

The governing sentence is:

> **Institution I currently recognizes Person P as qualified to perform Competency C at Level L within Scope S under exact Qualification Standard Version V, on the basis of preserved Evidence E and a governed recognition act.**

This document does not yet promote a universal executable Qualification kernel. Atlas governance requires a second genuinely different executable domain before a shared runtime/schema is promoted.

## 2. Vocabulary

### Competency

A **Competency** is an ability that can be demonstrated.

Examples:

- lead the Washers activity;
- construct a Washers set correctly;
- operate a particular laboratory instrument;
- perform a bounded field-service procedure;
- direct a shelter intake function;
- operate a farm process.

Competency is not a Person state by itself. It names the ability being considered.

### Qualification Standard

A **Qualification Standard** is the governed definition of what an institution requires before it will recognize someone as qualified.

A standard may define:

- competency identity;
- level or stage;
- applicable scope;
- prerequisite qualifications;
- required knowledge exposure;
- required demonstrations;
- required observations or assessments;
- required evidence;
- expiration/review policy;
- recognition authority;
- safety constraints;
- version.

A Standard is definition/specification truth. It is not evidence that a Person satisfies it.

### Person Qualification

A **Person Qualification** is the institution's current recognition that one Person satisfies one exact Standard Version within the recorded scope.

Qualification is therefore relational and provenance-bearing:

```text
Person
+ Institution / governing Ledger
+ exact Standard Version
+ scope
+ evidence
+ governed recognition
-> current Qualification
```

## 3. Existing Atlas concepts that Qualification must not replace

### Canonical Person

`atlas.people` remains the human identity root.

Qualification belongs to a Person. It does not create the Person.

### Authentication credentials

`atlas.person_auth_credentials` proves credential binding.

Login access is not Qualification. Qualification remains meaningful if the Person changes credentials or has no login.

### Organization Membership

Membership proves institutional affiliation.

```text
Person belongs to Organization
!=
Person is qualified to perform Competency
```

### Position / durable institutional responsibility

Position and Responsibility establish institutional placement and durable carriage.

They may require a Qualification, but they do not prove one merely by appointment.

### Exact Company Work responsibility

`atlas.work_allocations` answers who currently carries one exact Work item.

Assignment is not Qualification.

A Person may be qualified but unassigned; assigned Work must not manufacture Qualification merely because the assignment exists.

### Capability activation

`atlas.capability_activations` means a governed Atlas software/domain capability is available in a Ledger and attached to a governed subject.

That concept must not be overloaded to mean human skill.

Therefore:

```text
Teaching capability active in Ledger
!=
Person qualified to teach
```

### Claim / Evidence

Claims and evidence may bear on a Qualification.

Evidence does not silently create Qualification. The recognition act remains explicit where the institution requires one.

### Academic Enrollment / Completion

Enrollment is participation in an academic Offering.

Future Teaching completion/evaluation may supply evidence toward a Qualification or credential, but completion is not automatically the same semantic relation as institution-recognized Qualification.

## 4. Qualification is not truth magic

Atlas's Claims/Evidence constitution applies.

A trainer may report:

```text
Maria led Washers safely and independently.
```

That report is evidence/claim material.

A Qualification exists only after the governing qualification law recognizes the Person under the exact Standard Version.

The institution may later:

- discover contradictory evidence;
- suspend the recognition;
- let it expire;
- revoke it;
- supersede the Standard;
- require reassessment.

History must remain explainable.

## 5. Qualification does not itself grant action authority

Qualification may be consumed as one prerequisite for an action.

It does not mean:

```text
qualified
-> automatically authorized to act anywhere
```

A qualified Person may still lack:

- responsibility for this event;
- assignment to this Work;
- jurisdiction over this place;
- required organizational relationship;
- an active execution warrant;
- current safety clearance;
- required resource custody.

The consuming domain decides whether Qualification is required and what consequence follows.

## 6. Levels

Many real qualification systems are progressive.

Camp Duffel gives a useful example:

```text
observed
-> practiced
-> supervised leader
-> independent leader
-> trainer
```

The architecture must not assume that every Standard has the same level ladder.

A level belongs to the Standard/domain definition, not a universal hard-coded ladder.

The universal candidate semantics require only that the exact recognized level be explicit where levels exist.

## 7. Scope

Qualification must be bounded.

Examples:

- lead canonical Washers;
- lead Washers only under supervision;
- operate Instrument X in Laboratory Y;
- operate a process for a particular equipment class;
- perform a procedure for a defined age/site/program context.

A qualification that is materially scope-bound must not be widened by presentation code.

## 8. Standard versioning

Once a Person Qualification depends on a Standard Version, the meaning of that Standard Version must not be silently rewritten.

Conceptually:

```text
Standard v1
-> Person qualified under v1

Standard changes materially
-> publish v2
-> existing v1 qualification remains historically intelligible
-> consuming domain decides whether v1 remains acceptable
```

This follows existing Atlas law around immutable consequential definitions.

## 9. Evidence and demonstration

Qualification evidence may include, depending on domain:

- observed performance;
- supervised practice;
- assessment/evaluation;
- completion of required preparation;
- source records from another institution;
- physical evidence;
- existing recognized external credential;
- documented prior experience;
- repeated successful execution.

The Qualification layer must preserve links to the evidence rather than flattening evidence into a boolean.

## 10. Recognition lifecycle candidate

A future executable domain may need states such as:

- proposed / awaiting review;
- recognized;
- suspended;
- expired;
- revoked;
- superseded.

These are candidate semantics only.

The first executable domain must prove the actual state machine before any universal enum/runtime is created.

## 11. Camp Duffel first proof

A useful first proof is:

**Qualification Standard:** Lead Washers Independently, version 1.

Possible Standard requirements, sourced from the CI activity methodology, include:

- understand the activity's purpose and basic rules;
- demonstrate correct setup;
- demonstrate safety boundaries;
- use the progressive instructional method;
- get campers into interaction quickly rather than front-loading a long lecture;
- lead a supervised round;
- demonstrate scoring/rule control;
- preserve the intended teaching/relationship method;
- complete an observed independent lead.

Possible evidence:

- trainer observation;
- witnessed activity execution;
- structured assessment notes;
- completion of specific preparation Work;
- resulting trainer recognition.

The Person Qualification would answer:

> CI currently recognizes this Person as able to lead Washers independently under this Standard Version and scope.

It would not assign that Person to a particular camp.

## 12. Cross-domain comparison

The same semantic relation appears in genuinely different domains:

| Domain | Competency | Qualification meaning |
|---|---|---|
| Camp development | Lead Washers | Institution recognizes Person can lead the activity to the defined level |
| Skilled trade | Perform bounded installation procedure | Company recognizes technician meets its standard |
| Emergency response | Lead a shelter function | Response organization recognizes responder meets standard |
| Healthcare | Perform bounded procedure/workflow | Institution recognizes practitioner/staff competency under its policy |
| Agriculture | Operate a defined process/equipment | Farm/institution recognizes operator competency |
| Research | Operate Instrument X | Laboratory recognizes Person can operate it at the defined level |

This is strong architectural evidence, but not yet sufficient executable proof under Atlas's no-speculative-universal rule.

## 13. Likely second proof: Atlas Teaching

The released Teaching academic kernel currently stops at:

```text
Course
-> Course Version
-> Course Offering
-> Enrollment
```

Its governing architecture explicitly leaves Assessment, Submission, Evaluation, Completion, and credentials to later gates.

That later Teaching work is a strong candidate for the second executable comparison because it can test whether:

```text
evaluated learning evidence
-> institution recognition under Standard
```

has the same mechanics as CI's observed activity qualification.

Do not force Teaching completion into Qualification merely to prove this architecture. The comparison must be made after both real domain mechanics exist.

## 14. Promotion gate for a universal executable Qualification kernel

Do not create generic `atlas.qualifications` tables merely from this document.

Promotion requires at least two genuinely different executable domains and a field-by-field / transition-by-transition audit proving the same mechanics.

The audit must answer:

1. Is there an exact governed Standard Version in both domains?
2. Is recognition about an existing Person?
3. Is evidence distinct from recognition?
4. Is recognition scoped?
5. Is recognition lifecycle/history preserved?
6. Does Qualification remain distinct from responsibility/assignment/access?
7. Can the same transition law represent both domains without deleting domain meaning?
8. Can downstream domains consume Qualification without Qualification itself taking over their authority?

If those answers hold, a shared kernel may be promoted.

## 15. First implementation consequence

For CI work now:

- use **Qualification** as the architecture vocabulary;
- do not call human competence an Atlas `capability_activation`;
- structure the first CI activity/training model so Standard, evidence, recognition, scope, and level remain separable;
- do not yet create a universal cross-domain Qualification table.

That preserves a clean path to promotion when the second executable domain proves it.
