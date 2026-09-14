# Atlas Person↔Institution Relationship Evidence for Governed Effect Uptake v1

## Status

Architecture contract only. No schema, migration, resolver, role hierarchy, permission table, action-class registry, or production behavior is created in this tranche.

This contract operates under:

- `atlas-event-effect-governed-uptake-v1.md`;
- `atlas-institutional-responsibility-source-attribution-v1.md`;
- `atlas-cross-boundary-responsibility-offers-v1.md`;
- `atlas-responsibility-offer-and-relation-lifecycle-v1.md`;
- `atlas-standing-responsibility-intake-agreements-v1.md`;
- the governed Scope and Ledger-aperture contracts in this architecture tranche.

## Purpose

Settle the next boundary in the event → effect → governed uptake model:

> When an event originates from a Person rather than from an institution-custodied endpoint or governed workflow, what durable Person↔institution relationship evidence can be sufficient for a particular proposed consequence to take hold as institutional reality?

The answer must not recreate the superseded architecture in a new vocabulary.

Atlas must not store or infer a hidden matrix of:

```text
Person P may perform Action Class X for Institution I.
```

Instead Atlas asks:

```text
What institutional reality is this Person actually carrying?
What consequence is this event attempting to create?
Does that consequence directly arise inside the exact governed reality the Person carries?
What other assent, custody, evidence, or boundary conditions must independently be satisfied?
```

## Governing law

**A durable Person↔institution relationship is evidence about what institutional reality the Person carries. It is not a list of actions the Person may perform. A proposed consequence may take hold through that relationship only when the effect-specific governing law can show that the consequence is a direct consequence of carrying that same bounded institutional reality.**

Therefore:

```text
relationship describes entrusted reality
        ↓
event proposes a consequence
        ↓
effect resolver identifies affected reality
        ↓
relationship target + Scope are compared with affected reality
        ↓
effect-specific boundary rules are applied
        ↓
consequence takes hold / does not take hold / remains unresolved
```

There is no intermediate universal `permission` conclusion.

## Function is carried; actions are not pre-enumerated

Atlas should represent durable relationships in terms of the function, responsibility, custody, stewardship, or institutional reality entrusted to the Person.

Examples:

```text
Anna carries Elm weekly farm-operations execution.
Marshall carries Elm greenhouse-production direction.
Katie carries Elm florist-route / buyer-relationship work.
A treasurer carries stewardship of a bounded institutional account.
A steward carries coordination of a bounded operating domain.
```

Those relationships answer:

> What is this Person answerable for carrying inside the institution?

They do not answer:

> Which verbs may this Person execute?

A responsibility target may itself be coordination, stewardship, custody, review, production, care, administration, or another real institutional function. Atlas should model that function as the governed thing being carried rather than translating it into an enumerated set of permitted actions.

## Relationship layers remain distinct

Several durable facts may coexist around the same Person and institution. They must not be collapsed.

### Affiliation relationship

Examples:

- employee;
- contractor;
- consultant;
- board member;
- volunteer;
- owner as a legal/commercial relationship;
- collaborator.

Affiliation establishes that a real Person↔institution relationship exists.

By itself it creates no generic institutional consequence.

In particular:

```text
employee != responsibility
employee != visibility
employee != institutional source
employee != authority over other People
employee != resource custody
employee != responsibility intake
```

### Responsibility Relation

A Responsibility Relation establishes that a Person currently carries a bounded governed target.

The target may be a concrete work item, durable institutional function, Scope-bounded operating responsibility, stewardship domain, or other governed responsibility target.

A Responsibility Relation is stronger evidence than mere affiliation because it states what reality the Person actually carries.

It still does not become universal authority.

### Standing responsibility-intake agreement

This is prior receiver assent for bounded classes of future responsibility offers.

It answers whether qualifying responsibility may attach to the receiver without a new manual acceptance event.

It does not make the sender an institutional source.

### Visibility/exposure relationship

This determines what institutional facts the Person may lawfully see in context.

It is independent from responsibility and effect uptake.

### Custody relationship

Custody may establish that a Person or institutional process currently carries a resource, endpoint, account, source, or other governed object.

Custody can be material to effects involving that object, but it does not create generic authority outside the thing held in custody.

### Seat, credential, connection, or entitlement

These are access/commercial/runtime mechanics.

They do not establish institutional responsibility, source, truth, or consequence uptake.

A paid employee connection may make it possible for Anna to enter Elm's Ledger. It does not explain what Elm reality Anna carries once she is inside it.

## Minimum qualities of relationship evidence

A durable Person↔institution relationship may participate in effect uptake only when Atlas can establish, at the relevant historical time:

1. **Person identity** — the actual Person is resolved;
2. **institution identity** — the institution/effective institutional custodian is resolved;
3. **relationship source** — the relationship was established, adopted, or otherwise recognized by the institution or by another governing path that can truthfully establish the relation;
4. **governed target** — Atlas can identify the institutional reality the Person carries;
5. **bounded Scope/context** — the relation is bounded enough to compare with the proposed consequence;
6. **current temporal state** — the relation was current at the event/effect time;
7. **provenance** — Atlas can explain the constituting event/evidence and later supersession/release where applicable;
8. **conflict state** — no unresolved contradiction material to the dependent consequence is being silently ignored.

A title, payroll row, sender string, seat, login, Organization membership, or role label may corroborate this evidence but cannot substitute for it.

## Direct-consequence test

The critical boundary is whether the proposed effect is a **direct consequence of carrying the relationship's governed target** rather than merely something that could be useful to the institution.

An effect may rely on a current Person↔institution relationship only when all applicable tests hold:

```text
1. affected reality is inside the relation's governed target / Scope;
2. the effect does not silently enlarge that target / Scope;
3. the effect expresses, updates, coordinates, preserves, transfers, reports on,
   or otherwise directly operates the same institutional responsibility being carried;
4. any independently required receiver assent still exists;
5. any independently required custody, resource, contractual, legal, or factual
   condition is separately established;
6. no unresolved conflict material to the effect is hidden;
7. historical provenance remains explainable.
```

The relation is not enough merely because:

```text
this would help the institution;
the Person is senior;
the Person is trusted;
the Person is an owner;
the Person can technically do it;
the Person can see the affected facts;
the Person already carries some other responsibility;
the institution usually allows similar behavior.
```

## Self-regarding consequences are different from consequences imposed on others

A Person's own relationship can be sufficient evidence for some consequences concerning that same relationship.

Examples:

```text
accept a responsibility offer addressed to oneself
decline an offer addressed to oneself
report progress on a responsibility one carries
report completion of a responsibility one carries
request release from a responsibility one carries
```

Even here, Atlas preserves the event/effect distinction.

For example:

```text
Anna reports "done"
```

establishes a completion report from the current carrier.

It does not automatically establish that every factual condition required for completion is true.

By contrast, effects that create consequences for another Person, bind institutional resources, change another Person's responsibility, alter institutional custody, or create an external obligation must satisfy the governing relationships for those additional affected realities.

## Cross-Person responsibility offers

Anyone may ask another Person to do something.

That creates, at most, a responsibility-offer effect from the actual source established for that event/effect.

For the offer to be attributable to Institution I through the sender's durable relationship, Atlas must establish more than:

```text
sender works for I
```

or:

```text
sender carries adjacent work for I.
```

The sender's current institution-sourced responsibility must itself carry the institutional function from which the offer directly arises over the affected Scope.

Example:

```text
Marshall carries Elm greenhouse-production direction.
Marshall asks Anna to harvest Greenhouse A tomorrow.
```

If `Greenhouse A harvest` is inside the governed target and the responsibility relation actually carries direction/coordination of that production reality, the relation may be sufficient Person↔Elm evidence for Elm source attribution of the responsibility-offer effect, subject to the other source/custody/conflict rules.

Atlas does not create:

```text
Marshall.permission = ASSIGN_GREENHOUSE_TASK
```

It explains:

```text
Marshall currently carries Elm's greenhouse-production direction;
the offer concerns that same greenhouse-production reality;
the responsibility-offer effect is a direct expression of the carried institutional function.
```

Receiver responsibility still does not exist until acceptance or a matching standing intake agreement takes effect.

## Responsibility alone is not universal source evidence

The existing source-attribution rule remains important:

```text
responsibility alone != universal institutional source
```

A Person carrying one responsibility cannot therefore originate every institutional consequence.

The narrower law is:

> An institution-sourced Responsibility Relation may be sufficient relationship evidence for a consequence only where the governed target of that relation is the institutional function that directly produces the consequence over the same bounded reality.

Thus:

```text
responsible for delivering flowers
```

does not by itself establish:

```text
ability to create Elm payroll obligations
ability to redirect unrelated venue work
ability to commit Elm cash
ability to bind another worker to new responsibility
ability to alter the florist-route Scope
```

unless the carried responsibility itself truthfully includes the relevant institutional function and the other effect-specific boundaries are satisfied.

## Resource commitments and custody

A work responsibility is not automatically a resource-custody relationship.

If an effect would commit money, inventory, property, an account, a contractual position, or another separately governed resource, the relevant resource relationship must independently support the effect.

For example:

```text
Anna carries farm operations
```

does not silently imply:

```text
Anna carries Elm treasury
```

A purchase or payment commitment therefore cannot rely solely on the farm-operations relationship merely because the purchase would help farm operations.

## Claims remain independent

A relationship can support consequence uptake without making bundled factual claims true.

Example:

```text
Marshall:
"The north bed is ready. Harvest it tomorrow."
```

may resolve as:

```text
Elm source of harvest responsibility offer = established
readiness claim = unresolved or false
```

The relationship explains the source/effect consequence. It is not a truth authority.

## Scope changes remain governed by their own settled rule

This contract does not replace the local Scope-addition law already settled in the Scope architecture.

A Person whose independently resolved visibility + responsibility contain the affected reality may produce a local Scope-definition addition under that existing rule.

That consequence takes hold because the Scope effect's governing law is satisfied.

No generic Person action authority is inferred from that fact.

## Later institutional uptake remains available

If the Person's durable relationship is insufficient for the proposed institutional consequence, Atlas preserves the originating event and leaves the institutional effect unresolved or personal as appropriate.

The institution may later take up the consequence through a new event.

Example:

```text
Katie carries Elm florist-route / buyer-relationship work.
Katie asks Anna to prepare the venue.
```

If venue preparation is outside Katie's carried institutional function:

```text
real event: Katie asked Anna
Elm source of responsibility offer: not established
```

Later:

```text
Elm Farm adopts the venue-preparation request.
```

That is a new Elm-originating uptake event/effect.

Atlas never needs to manufacture a hidden earlier permission for Katie.

## Anna / Elm projection example

The future `/anna` projection should be explainable from these independent facts:

```text
Person: Anna
Institution: Elm Farm
Ledger: Elm Farm Ledger
Credential/connection: permits Anna to enter the Ledger
Affiliation: current Elm employment/steward relationship
Visibility: governed Elm exposure policies admit the relevant facts
Current Responsibility Relations: the Elm work Anna actually carries
Pending Responsibility Offers: requests not yet accepted
Standing intake agreements: bounded prior assent for qualifying future Elm offers
Worker activity events: what Anna reports she actually did
```

`/anna` should not be generated from:

```text
employee seat -> role -> permission list -> task list
```

It should be a Person-specific projection over Elm's governed reality:

```text
what Anna carries now
what Elm is validly offering her
what she has already done/reported
what remains executable in her current responsibilities
what shared institutional context her visibility admits
```

A commercial employee seat may fund or enable the connection. It does not become the ontology of the worker's institutional life.

## Ledger connection implication

There remains no need for a Person↔Ledger membership object.

A Person's effective Ledger connection/aperture can be derived from real relationships plus access/entitlement mechanics:

```text
Person identity
+ institution relationship evidence
+ credential/connection state
+ visibility policy admission
+ current responsibilities / offers / other governed relations
-> effective Person-specific Ledger projection
```

The Ledger remains institutional reality. `/anna` is a lens over that reality, not a separate worker database and not a security boundary created by a seat.

## What must not be built

Do not introduce any of the following as the generic solution to this boundary:

- `allowed_actions` on a Person↔institution row;
- `effect_classes_allowed` on a role;
- universal `speaks_for_institution` boolean;
- action-class registry whose entries must be granted to people;
- role → permission matrix;
- title → authority map;
- seniority rank that automatically widens consequence uptake;
- employee/owner shortcuts that bind all institutional effects;
- seat → responsibility inference;
- seat → visibility inference;
- visibility → responsibility inference;
- responsibility → every-source/effect inference.

Effect families may still have explicit governing laws. That is not an action-permission system because the law answers:

> Under what reality conditions does this consequence exist?

rather than:

> Which actors have permission to perform this verb?

## Explainability requirement

Whenever a Person-originating event produces an institutionally effective consequence through durable relationship evidence, Atlas should be able to explain:

```text
originating event
actual actor
institution
effect family
affected governed reality
Person↔institution relationship used as evidence
relationship's governed target / Scope
why the effect is a direct consequence of carrying that target
other assent/custody/evidence conditions satisfied
conflicts considered
historical effective time
later supersession/release/uptake if any
```

If Atlas cannot produce that explanation, it does not yet have sufficient relationship evidence for the dependent consequence.

## Deliberately not included yet

This contract creates no:

- generic Person↔institution relationship table;
- new Responsibility Relation table;
- relationship-kind enum;
- effect-family enum;
- direct-consequence classifier;
- institution-policy engine;
- action-class registry;
- permission matrix;
- owner/employee authority shortcut;
- employment/payroll schema;
- supervisor hierarchy;
- automatic delegation runtime;
- source-attribution resolver;
- effect-uptake resolver;
- Ledger roster API;
- `/anna` migration;
- production access change.

## Resulting law

> Atlas should model what institutional reality a Person actually carries, not a list of actions the Person is allowed to perform. A durable Person↔institution relationship becomes sufficient evidence for a particular consequence only when the effect-specific governing law can show that the consequence directly arises inside that same institution-sourced, bounded, current relationship and every independently affected boundary is also satisfied. Employment, seats, titles, visibility, responsibility, custody, receiver assent, and institutional source remain distinct facts. When the relationship is insufficient, Atlas preserves the event and relies on later governed uptake rather than inventing hidden permission.