# CI Washers — Outcome Package / Qualification First Proof v1

**Status:** Domain proof architecture only; no schema, migration, RPC, permission, or production mutation is authorized by this document.  
**Date:** 2026-09-22  
**Source:** David G. Caldwell, *Washers — Camp Counselor Instructional Script to Campers*, Camps International, Version 1.00, 2026-09-21.  
**Purpose:** Pressure-test Atlas Person Qualification and Outcome Package candidates against one real CI activity before any universal executable schema is promoted.

## 1. Why Washers is the first proof

Washers is small enough to reason about as one activity but deep enough to expose CI's actual methodology.

The source contains:

- a named activity and category;
- player capacity;
- equipment/setup;
- estimated run time;
- physical skill;
- Scripture/illustration use;
- facilitator and co-facilitator roles;
- a progressive instructional script;
- teaching technique;
- safety behavior;
- scoring/rules;
- relationship purpose.

It therefore lets Atlas test whether one canonical activity can support multiple projections, training, equipment/build work, qualification, assignment, and follow-up without turning the source PDF itself into the runtime.

## 2. Source-supported activity facts

The Version 1.00 source supports the following current facts.

### Identity

```text
Activity: Washers
Category: Friendly competition — throwing
Source arranger: David G. Caldwell
Source version: 1.00
Source date: 2026-09-21
```

### Synopsis / physical setup

The source describes players standing inside a pit boundary and throwing large washers approximately 25 feet toward a 4-inch recessed cup in the opposing pit.

### Player capacity

One set of pits supports:

```text
2, 3, 4, or 6 players
```

The source defines different team/movement behavior for each supported count.

### Time

The source estimates:

```text
~3 minutes per round
~15 minutes per game depending on a final score of 15 or 21
```

### Core physical skill

```text
Accurately tossing a washer
```

The script teaches a controlled throw intended to land the washer flat, using coordinated body/arm/wrist movement.

### Equipment named by the source

For one group of up to six players:

```text
2 pits
1, 2, or 3 washers for everyone at one pit
```

The script later uses 18 washers arranged in three distinguishable sets as its instructional example.

A pit may be permanent or outlined with a lime line according to the source.

### Roles

The source distinguishes at least:

**Facilitator** — usually the cabin counselor; instructs/directs the group and manages the presentation.

**Co-facilitator** — assists, affirms, supports, checks camper understanding, helps individuals, distributes/collects materials, and coaches when the group spreads across the full court.

It also deliberately uses camper participation roles such as random/chosen camper, volunteering camper, and everyone/unison response.

### Instructional method

The source explicitly defines an **instructional script** as a need-to-know information corridor:

```text
small instruction slice
-> immediate camper interaction
-> next instruction slice
-> progressive assembly
-> full game
```

The intended result is to minimize long front-loaded explanation and maximize actual engagement.

This is not incidental formatting. It is part of the CI activity-teaching method.

### Facilitator preparation

The source explicitly directs facilitators to:

- study, practice, rehearse;
- play Washers before teaching Washers;
- know more about illustrations than they expect to share;
- prepare while expecting real circumstances to require adjustment;
- use teachable moments intentionally;
- stay connected to campers through eye contact/presence;
- give campers processing time and coach them toward successful participation.

### Safety behavior explicitly supported by source

During throwing practice/play, people at the opposite pit are instructed to stay out and away from their pit so they are not struck by a flying washer.

The source also notes that, for some children, introducing the washer into each camper's hand only at the moment of use may provide more control.

This is source-supported safety behavior.

The source does **not** provide a complete formal safety standard or risk-assessment system.

### Illustration / teaching use

The source connects Washers to 1 Corinthians 9:24–27 and uses competition/scoring as an illustration around intentional preparation and competing to win.

It also incorporates optional wider educational content such as history, patriotism, language, math, science, religion, and character development.

### Relationship purpose

Near the end, the source states that activities provide a context for building relationships, may illustrate larger principles/character values, and that the activity is an excuse to teach something greater.

It names relationship as the grand goal.

That principle belongs in the activity's purpose/teaching projection, not merely in an introductory manual.

## 3. One canonical CI Activity, many projections

The source proves David's proposed “views” should not be separate documents.

A single canonical **CI Activity** should be able to project at least:

| Projection | Washers example |
|---|---|
| Simple | Washers; friendly competition/throwing; 2/3/4/6 players |
| Annotated | Same activity with facilitator notes and teaching rationale |
| Scripted instruction | Progressive need-to-know counselor script |
| Variations / difficulty | Any governed variants established by CI |
| Complete rules | Scoring and full play rules |
| Site implementation | Washers at Los Domos or another site |
| Construction | How to create the required pit/equipment |
| Funding | Materials, construction cost, replacement cost |
| Illustration / purpose | Scripture, quotes, stories, teachable moments |
| Safety | Throwing zone and other established controls |
| Benefits | Physical/social/academic/etc. benefits when established |
| Follow-up | How the shared experience can be used later in discipleship |

The source already strongly supports several of these.

Others are gaps that CI must still establish.

## 4. Critical source gaps exposed by the proof

### 4.1 Construction is not yet sufficiently specified

The current Washers source says:

- two pits;
- permanent or lime-outlined;
- 25 feet;
- 4-inch recessed cup.

It does **not** establish enough construction detail to produce a reliable build blueprint.

Missing or not established in this source include items such as:

- pit dimensions beyond the referenced cup/distance;
- base/material specification;
- exact cup installation;
- portable vs permanent build design;
- tolerances;
- weather/durability requirements;
- tool list;
- inspection/acceptance criteria.

Therefore **Build a Washers Set** is currently blocked as a complete Outcome Package Definition.

Atlas must preserve that gap instead of inventing a build specification.

### 4.2 Funding/cost is not established

The current source does not provide:

- bill of materials with quantities/specifications sufficient for purchasing;
- unit cost;
- total construction cost;
- replacement cost;
- local-vs-travel sourcing rule.

Therefore no donor-facing “$X builds Washers” statement should be generated from this source alone.

### 4.3 Formal qualification criteria are not established

The source tells facilitators how to prepare and teach.

It does **not** define a formal institutional assessment that says:

> when these exact criteria are demonstrated, CI recognizes this Person as independently qualified to lead Washers.

That means **Lead Washers Independently** can be modeled as an Outcome Package candidate, but the final Qualification Standard still requires CI to establish its recognition criteria.

### 4.4 Difficulty/variation ladder is not formally defined

The source progressively introduces the game, but a reusable beginner/intermediate/advanced variation ladder is not clearly established as such.

Do not infer one merely from instructional order.

### 4.5 Benefits taxonomy is incomplete

The source clearly supports:

- physical skill/coordination themes;
- learning/educational opportunities;
- relational purpose;
- character/spiritual illustration.

It does not provide a formal health/social/academic benefits taxonomy with evidence level.

That later view should distinguish CI-established purpose from externally researched benefit claims.

## 5. CI Activity domain shape suggested by the proof

This is a **domain model**, not authorization for universal Atlas tables.

A CI Activity needs durable identity separate from any PDF.

Conceptually:

```text
CI Activity
  identity
  category
  intended group shape / player constraints
  purpose
  source provenance
  exact released versions

CI Activity Version
  synopsis
  rules
  instructional method/script
  materials/setup requirements
  safety guidance
  teaching/illustration material
  variations established by CI
  follow-up guidance established by CI
```

Site-specific implementation must remain separate:

```text
CI Activity Version
-> Site Activity Implementation
     Los Domos
     Church A
     Camp B
```

A local implementation may adapt space, materials, language, or procedure where CI allows it without rewriting the canonical Activity Version.

## 6. Outcome Package Proof A — Build a Washers Set

### Intended outcome

> A usable Washers set exists under CI's established construction and safety criteria.

### Current requirement map

| Requirement | Authority | Current state from source |
|---|---|---|
| Exact CI Washers activity/version | CI Activity domain | supported |
| Required player/use geometry | CI Activity domain | partially supported |
| Build specification | CI construction/build domain | **missing/incomplete** |
| Materials specification | CI build/resource domain | **partial only** |
| Tools | CI build domain | **missing** |
| Money required | nonprofit stewardship / Money | **missing** |
| Builder Work | Company Work | can exist once build definition exists |
| Inspection evidence | Evidence + CI acceptance rule | **acceptance rule missing** |
| Resulting equipment existence/custody | CI physical-resource domain | domain not yet established |

### Conclusion

Do **not** build an executable Package for this yet.

The correct Atlas result today is:

```text
Build Washers
status: definition incomplete
blocking gaps:
  construction standard
  bill of materials
  tools
  acceptance/inspection rule
  funding/cost basis
  physical-resource custody model
```

That is useful institutional knowledge.

It tells David exactly what his current scavenger hunt must recover.

## 7. Outcome Package Proof B — Lead Washers Independently

### Intended outcome

> CI recognizes this Person as qualified to lead Washers independently under an exact CI Standard Version.

### Source-supported preparation components

The source directly supports requirements around:

- playing Washers before teaching it;
- studying/practicing/rehearsing;
- understanding the materials and basic play;
- using the progressive instructional-script method;
- engaging campers quickly;
- demonstrating the physical throwing method;
- teaching scoring;
- maintaining throwing-zone safety;
- using facilitator/co-facilitator roles appropriately;
- understanding the activity's larger teaching/relationship purpose.

### Candidate progression

The following progression is a **candidate Outcome Package composition**, not a source-established formal qualification ladder:

```text
1. Review exact Washers Activity Version
2. Play Washers
3. Study/practice/rehearse instructional method
4. Observe a competent/qualified leader
5. Practice instruction with feedback
6. Lead under supervision
7. Produce observation evidence
8. CI recognition decision
9. Person Qualification established if Standard is satisfied
```

Steps 4–9 require explicit CI policy that the current activity source does not itself establish.

### What must be established before executable Qualification

CI needs to answer:

- What exact competency is being recognized?
- What levels exist, if any?
- Which behaviors are mandatory?
- Which safety failures are disqualifying?
- What may be coached during assessment?
- Who may recognize the Qualification?
- Is one observed lead enough?
- Does it expire or require refresh?
- Does qualification vary by camper age/site/language?
- What evidence must be retained?

Until those are governed, Atlas may track preparation Work/evidence but must not pretend an institutional Qualification exists.

## 8. Authority map

The first proof produces this authority map:

```text
CI Activity truth
  -> CI Activity domain

source documents / versions
  -> source provenance / artifact custody

Person identity
  -> canonical Atlas Person

preparation assignments
  -> Company Work / responsibility

trainer observation
  -> Claim / Evidence

institution recognition
  -> Person Qualification candidate domain

camp-specific assignment
  -> Company Work responsibility + execution authority

Washers equipment
  -> future CI physical-resource domain

funding / gifts / cost
  -> nonprofit stewardship + Atlas Money

messages/reminders
  -> institutional Communication

Outcome Package
  -> composition/projection only
```

No one object should absorb the others.

## 9. Distribution consequence

Once the CI Activity is structured, different people can receive different projections from the same canonical source.

### Camper-facing / novice leader

Only the immediate instruction slice needed now.

### Counselor

Progressive instructional runtime plus safety and teaching notes.

### Trainer

Full method plus observation/qualification criteria once CI establishes them.

### Builder

Construction projection once build specification exists.

### Donor

Funding requirement once cost/material authority exists.

### Director

Capacity, duration, location, leader qualification, equipment availability, and assignment state.

### Receiving church

Local implementation guidance plus what the church can build/own locally.

This is the operational reason to digitize CI methodology as domain truth rather than as a document library.

## 10. Usage consequence

The key runtime should not open on “Washers.pdf.”

It should be able to answer:

```text
You have 6 campers.
You are the facilitator.
This site has a usable Washers set.
Your co-facilitator is present.
You are qualified for this activity.

Start here:
  form the group
  introduce the material
  get them interacting
  progress when the group demonstrates readiness
```

That runtime is a projection of the exact Activity Version plus current implementation context.

It does not rewrite the source methodology.

## 11. First executable schema decision

This proof does **not** justify generic Qualification or Outcome Package tables yet.

It does justify beginning a CI-specific executable domain with a small, truthful Activity/version foundation once CI is ready to provision its Ledger/Organization context.

The smallest likely CI domain sequence is:

```text
CI Activity
-> immutable Activity Version
-> site/local Activity Implementation
-> later construction/resource model
-> later CI Qualification Standard/recognition proof
-> later Outcome Package promotion test
```

Before executable work, the CI Activity contract should be written field-by-field from the source corpus, not just Washers.

## 12. Immediate content-recovery checklist for David/Nathan

The architecture now tells us exactly what missing information matters most for Washers:

1. construction drawing/specification;
2. bill of materials;
3. tool list;
4. portable vs permanent variants;
5. expected build time;
6. current real-world cost;
7. inspection/acceptance criteria;
8. maintenance/storage/replacement rules;
9. formal trainer standard for independent leadership;
10. qualification levels, if any;
11. who may recognize a leader;
12. refresher/expiration policy, if any;
13. site adaptation rules;
14. formally supported difficulty variants;
15. follow-up/disciple-use guidance.

Those are not arbitrary database fields. They are the gaps between CI knowing how to do Washers and CI being able to reproduce that capability reliably through other people and churches.

## 13. Result

The first proof passes the architectural test:

- one Activity can serve many projections;
- Package composition makes creation/distribution/use more coherent;
- Person Qualification is distinct from content completion and assignment;
- missing information remains visible rather than guessed;
- existing Atlas Person, Work, Evidence, Communication, and Money authority can be reused;
- physical resources and CI methodology remain real domain-specific truth;
- no speculative universal runtime is required yet.

The next architecture task is to recover the **CI Activity contract** across several different activities, so the Activity schema is not accidentally Washers-specific.
