# Atlas Institutional Action Representation Mandates v1

## Status

Architecture contract only. No executable generic representation-mandate schema or runtime exists in this tranche.

## Purpose

Define the bounded governed relationship by which a Person or governed system actor may perform a specific class of institutional action **for** an institution over a specific Scope/context and time window.

This contract exists to answer questions such as:

> What makes Marshall legitimately able to send an Elm Farm production responsibility offer as Elm Farm rather than merely as Marshall?

> What makes one employee able to approve a purchase but not sign a lease?

> What makes a workflow able to emit routine Elm responsibility offers without impersonating a human?

The answer must not collapse representation into truth, responsibility, visibility, title, employment, transport permission, or generic rank.

## Governing principle

An institutional action representation mandate is a bounded institutional fact of the form:

```text
represented institution: I
actor: P or governed system actor
permitted action class: A
governed boundary: Scope/context X
effective window: T
basis/provenance: B
```

Conceptually:

```text
Mandate M(I, actor, action class, boundary, time)
```

means:

> The institution currently recognizes this actor as able to perform this bounded class of constitutive institutional action on its behalf in this context.

It does **not** mean:

- the actor's descriptive statements are true;
- the actor may perform every institutional action;
- the actor owns the institution;
- the actor has higher ontological rank;
- the actor has visibility into all affected reality;
- the actor is responsible for all affected reality;
- the actor may delegate the mandate onward;
- the actor may use every institutional communication endpoint;
- the actor may move Ledger custody.

## Descriptive claims versus constitutive institutional acts

Atlas must preserve a crucial distinction.

A statement such as:

> "The north bed is ready."

is a descriptive claim about reality. It may be true or false regardless of who says it.

An action such as:

> "Elm Farm appoints P to issue routine production responsibility offers over Scope S through September 30."

can be a **constitutive institutional act** if it is performed through a valid governing path. The action changes institutional governance reality because the institution validly performed the act, not because the proposition is magically true by authority.

A person without sufficient action standing can utter the same words. In that case Atlas records at most a purported grant/claim; no effective representation mandate is created.

Thus:

```text
claiming a mandate exists
!=
validly establishing a mandate
```

and:

```text
valid mandate
!=
truth authority
```

## Minimum semantic dimensions

A future executable mandate must be able to preserve at least:

- **represented institution** — the institution on whose behalf the actor may act;
- **actor identity** — Person or governed system/workflow actor;
- **action class** — what kind of institutional act may be performed;
- **governed boundary** — Governed Scope, exact subject set, Ledger intersection, workflow family, relationship context, or another sufficiently bounded semantic domain;
- **effective time** — when the mandate begins and ends;
- **establishment basis** — the governed act, constitutional/root basis, prior mandate, workflow rule, or adjudicated evidence establishing it;
- **status/lifecycle** — enough to distinguish current, suspended, revoked, expired, or superseded standing without rewriting history;
- **provenance** — who/what established, changed, suspended, or revoked it and through which institutional path;
- **delegation capability, if any** — explicit permission to establish narrower mandates, never inferred merely from breadth.

These are architectural requirements, not a commitment to one table shape or enum.

## Action classes are explicit

Representation is action-local.

Conceptually distinct action classes include, for example:

- issue routine responsibility offer;
- create institutional work;
- reroute institutional responsibility;
- establish/revoke representation mandate;
- send informational correspondence;
- approve expenditure;
- commit purchase;
- sign contract;
- establish customer promise;
- approve policy;
- accept vendor obligation;
- close institutional response case.

The exact executable action taxonomy is deliberately deferred, but Atlas must never substitute a generic `represents institution = true` boolean.

Thus:

```text
may issue Elm production responsibility offers
!=
may approve Elm purchases
!=
may sign Elm contracts
```

## Representation is independent from visibility and responsibility

A representation mandate is action standing, not semantic exposure and not work responsibility.

Atlas may validly have:

```text
Person P may perform action A for institution I
P has limited or no visibility beyond the minimum disclosed action context
P is not personally responsible for the underlying operational outcome
```

or:

```text
P carries broad responsibility
P has broad visibility
P has no representation mandate for action A
```

No dimension silently creates another.

This preserves the already-settled law:

```text
visibility != responsibility != action authority/representation != product delivery
```

## Representation is independent from transport permission

A communication endpoint capability such as `send` means the Person may use that transport under the endpoint runtime.

It does not by itself establish that the Person may perform every institutional action carried through that endpoint.

For example:

```text
P may send email from hello@elmfarm.co
```

is not enough to prove:

```text
P may issue employee responsibility offers for Elm Farm
```

A responsibility offer carried through an institutional endpoint therefore needs both:

1. a valid institutional source/transport path; and
2. sufficient action-local representation for the `responsibility_offer` class, unless the endpoint/workflow itself is explicitly governed as an institutional emitter of that action class.

This prevents generic mailbox access from becoming hidden managerial power.

## Establishment requires an institution-binding path

A representation mandate becomes effective only through a governed institution-binding path. Atlas must be able to explain why the represented institution is actually bound by the establishment act.

Valid architectural source classes include the following.

### 1. Root governing basis

An explicit root governing fact over the affected Ledger reality may serve as a constitutional base for establishing narrower action mandates.

Existing `principal_ledger_authorities` with `authority_kind = root_governing` are a precedent for such a root fact.

That precedent must be interpreted carefully:

- root governing standing is action-governance evidence, not factual truth;
- it does not create unlimited visibility;
- it does not itself create a Person↔Ledger membership relation;
- cross-Ledger establishment requires sufficient governing basis over every affected effective-custody intersection;
- no current helper is silently promoted into an executable generic mandate-grant resolver until action-class semantics exist.

### 2. Existing mandate with explicit mandate-grant action

A current representation holder may establish a narrower mandate only if their own mandate explicitly permits the action class of establishing/revoking representation over the affected boundary.

Conceptually:

```text
M1 permits P to establish representation mandates
for action family A
within Scope S

P establishes M2 for Q
where M2 is within A/S
```

may be valid.

But:

```text
P has broader operational responsibility than Q
```

or:

```text
P has broader visibility than Q
```

or:

```text
P has a broad representation mandate for some other action
```

never implies subdelegation power.

### 3. Institution-governed rule or workflow

An institution may have a previously established governed rule or workflow that creates or ends mandates when defined conditions occur.

The workflow itself must have a valid institutional governance basis and preserve the triggering facts/provenance.

For example, an employment onboarding workflow could materialize a bounded representation mandate only if the institution has already governed that workflow as capable of doing so and the required employment/appointment conditions are established.

The workflow cannot bootstrap its own authority merely because it exists in software.

### 4. Evidence-backed reconstruction/adjudication

Atlas may discover evidence that a mandate was already established outside Atlas or in historical institutional reality.

Examples could include a signed board resolution, contract, appointment instrument, or other governed evidence.

In that case Atlas is not creating the mandate by believing a claim. It is reconstructing/adjudicating whether an institutional act actually occurred and what its effective boundaries were.

Conflicting evidence remains conflict. A false claim that a mandate existed does not create one.

## Existing delegated-authority substrate

`principal_authority_allocations` is useful precedent for several laws:

- explicit grants rather than role inference;
- bounded `authority_kind` plus JSON scope;
- effective begin/end time;
- active/revoked/expired lifecycle;
- durable allocation-event history;
- explicit source/reason;
- a returned truth boundary stating that organization/farm roles do not imply an authority grant and a grant requires an explicit source.

However, it is not adopted as the generic representation primitive because it is currently shaped around:

- a Principal;
- the Principal's Organization membership;
- optional portfolio units;
- optional operating functions.

It currently has no live allocation rows. That makes it a valuable compatibility/precedent substrate without forcing the new ontology into deployed data.

A future migration may correlate or supersede aspects of this machinery, but the architecture must not silently reinterpret existing rows or APIs.

## No role-label grant

The following are not sufficient by themselves to create representation:

- `owner`;
- `manager`;
- `employee`;
- `member`;
- Principal identity;
- job title;
- position appointment;
- payroll relationship;
- broader visibility;
- broader responsibility;
- endpoint send permission;
- possession of a password;
- being listed in a signature;
- being copied on institutional communications.

Those facts may be evidence or context. None is the mandate.

## Scope and impact containment

A mandate is bounded by the reality its actions may affect.

For a proposed action E, Atlas must establish that E falls inside both:

- the permitted action class; and
- the mandate's governed boundary.

Cross-Ledger mandates must be evaluated per effective custody intersection. Authority over one Ledger cannot fill a missing intersection in another Ledger.

A mandate whose predicate or Scope could dynamically expand must not silently gain new institutional reach. Future executable design must either bound the possible reach in advance or fail closed when expansion would cross outside the established mandate boundary.

## No implicit subdelegation

Subdelegation is an action class, not a property of being "higher."

A Person with a mandate to issue production work cannot grant that same power to another Person unless the original mandate also permits establishing such mandates.

Likewise, a Person with broad responsibility containment does not automatically gain power to grant representation.

This is deliberately different from the previously settled triage rule, where broader **visibility + responsibility** can produce coordination standing over narrower additions. Triage and institutional representation are distinct action systems.

## Lifecycle and append-only history

Representation must be historically reconstructable.

Conceptually relevant events include:

```text
established
revised
suspended
resumed
revoked
expired
superseded
```

A future schema may use different names, but changes must preserve append-only or equivalent durable provenance.

Historical action evaluation uses the mandate effective at the time the action occurred.

A later revocation does not rewrite earlier actions as unauthorized merely because the mandate is inactive today.

## Revocation and suspension

Revocation is itself an institution-binding action.

A Person or workflow may revoke/suspend a mandate only when a valid governing path permits that action over the affected mandate boundary.

The mandate holder's broader visibility, responsibility, or title does not determine who may revoke it.

An explicit expiry requires no later revocation action; the mandate simply ceases to be current at the governed end time.

If evidence later shows that the original establishment act was invalid, that is a claims/evidence/adjudication question about whether the mandate was ever effectively established, not ordinary prospective revocation.

## Holder consent and responsibility remain separate

A representation mandate is permission/standing to act for an institution. It does not by itself create a duty to act.

An institution may recognize that P **may** perform action A without P carrying responsibility to do so.

If the relationship also requires P to perform those actions, that obligation belongs in the responsibility/employment/agreement layer.

Thus:

```text
may act for institution
!=
must act for institution
```

A Person choosing not to exercise a mandate is not the same event as the institution revoking it.

## Mandate use and source attribution

When Person P performs institutional action E, source attribution should be able to preserve:

```text
actual actor: P
represented institution: I
representation mandate: M
action class: A
affected Scope/context: X
channel/workflow: C
effective custody evidence: ...
performed_at: ...
```

If E falls outside M, Atlas may still record what P actually did or claimed to do, but E does not automatically become institution-attributable through M.

For responsibility intake, a standing agreement that accepts work from institution I should rely on an offer only when both institutional source attribution and the action-class mandate are sufficiently established.

## Purported actions and later ratification

Atlas must preserve actions attempted without sufficient representation rather than silently deleting them or pretending they were institutional acts.

Conceptually:

```text
actor P performed purported action E
institutional representation at time E = not established
```

A later institution may choose to adopt or ratify some consequence of E through a separate valid institutional action.

That later act must not erase the original provenance or manufacture a fiction that P had a mandate at the earlier time. Whether a domain permits retroactive legal effect is a separate governed/domain-specific question and must not be assumed generically.

## False claims about representation

Anyone may claim:

> "I represent Elm Farm for this."

The claim may be false.

Atlas must not treat the assertion itself as sufficient representation evidence.

Likewise, a third party may claim that P has authority. That remains a claim until supported by governed evidence or a constitutive institutional act.

## Explainability requirement

For any action treated as validly represented, Atlas should be able to explain at least:

- represented institution;
- actual actor;
- action class;
- affected Scope/context;
- effective Ledger custody intersections;
- current/historical mandate identity;
- establishment basis;
- establishment actor/workflow/root basis;
- effective begin/end time;
- whether subdelegation was permitted and relevant;
- channel/endpoint/workflow used;
- any suspension/revocation/supersession history;
- conflicting evidence or later adjudication where relevant.

## Deliberately not included yet

This architecture tranche creates no:

- generic representation-mandate table;
- mandate event table;
- generic action-class registry;
- representation resolver;
- mandate grant/revoke RPC;
- ratification schema;
- generic actor registry;
- automatic migration of `principal_authority_allocations`;
- endpoint permission migration;
- role hierarchy;
- universal `speaks_for` boolean;
- visibility grant;
- responsibility grant;
- custody transfer;
- production permission change;
- UI.

## Resulting law

The settled law is:

> Institutional representation is a bounded, action-local, provenance-backed mandate to perform a class of constitutive actions for an institution over a governed boundary and time. Descriptive claims made by the holder may still be false. The mandate is established only through an institution-binding path such as explicit root governance, an existing mandate that specifically permits narrower mandate establishment, a properly governed institutional workflow, or evidence-backed reconstruction of a real prior institutional act. Role labels, responsibility breadth, visibility breadth, employment, membership, Principal identity, or endpoint send permission do not themselves create representation. Subdelegation is never implicit. Revocation is prospective unless evidence establishes that the original mandate never validly existed, and historical actions retain their actual provenance.