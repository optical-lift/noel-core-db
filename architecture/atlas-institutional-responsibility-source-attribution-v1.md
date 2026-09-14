# Atlas Institutional Responsibility Source Attribution v1

## Status

Architecture contract only. No executable generic institutional-source-attribution schema or runtime exists in this tranche.

## Purpose

Define when Atlas may attribute a responsibility-offer effect to an institution rather than merely to the Person or workflow that emitted the originating event.

This document now operates under `atlas-event-effect-governed-uptake-v1.md`.

Source attribution is **provenance for an event/effect**, not a generic permission system and not proof that every consequence in an event takes hold.

## Governing principle

**Actual actor and institutional source are separate facts.**

Atlas may truthfully preserve:

```text
actual actor: Marshall
originating event: message to Anna
institutional source of responsibility-offer effect: Elm Farm
```

without implying:

- Marshall is Elm Farm;
- everything Marshall says is true;
- every act Marshall performs is attributable to Elm;
- every proposed consequence in the message takes hold;
- Marshall possesses a universal `speaks_for_Elm` permission.

## Source attribution follows the effect being resolved

A single event may carry several semantic elements:

```text
message happened
information was disclosed
claim: north bed is ready
responsibility offer: harvest tomorrow
claimed source: Elm Farm
```

Institutional source attribution is resolved for the relevant consequence, not as one all-or-nothing validity flag over the entire event.

For example, Atlas may establish:

```text
message source = Marshall
responsibility-offer institutional source = Elm Farm
readiness claim truth = unresolved
```

or:

```text
message source = Marshall
responsibility-offer institutional source = not established
```

The original event remains preserved either way.

## Source attribution is not factual truth

If Atlas establishes that Elm Farm is the institutional source of a responsibility offer, that establishes provenance for the offer.

It does not establish factual claims bundled with the offer.

Example:

```text
"The north bed is ready. Please harvest it today."
```

may resolve as:

```text
responsibility-offer source = Elm Farm
readiness claim = false/disputed/unresolved
```

Claims remain governed by the separate claims/evidence/adjudication architecture.

## Source attribution is not transport permission

Permission to use a communication endpoint proves only the transport capability governed by that endpoint runtime.

A Person may validly send from `hello@elmfarm.co` while a particular semantic consequence in the message still requires separate governed uptake.

Likewise, an event emitted through a personal endpoint may later produce an institutionally attributable consequence if the institution's governed relationships support that consequence.

Therefore:

```text
transport permission != institutional source attribution != effect uptake
```

## Useful source-attribution paths

Atlas may establish institutional source provenance through different governed paths. These are evidence paths, not universal actor ranks.

### Institution-custodied endpoint

An event emitted through an endpoint whose effective custody resolves to institution I is strong evidence that the communication event itself came through I's institutional channel.

Useful existing provenance includes:

- `communication_endpoints`;
- `effective_communication_endpoint_organization_v1`;
- `communication_endpoint_source_bindings`;
- `communication_endpoint_member_grants`;
- `communication_outbound_operations`;
- `connected_sources`.

The endpoint display name or From string is not sufficient by itself.

### Institution-governed workflow

A governed workflow may emit an event whose effect is attributable to its institution when Atlas can establish the workflow's effective custody, triggering reality, and governed relationship to the consequence being produced.

The workflow does not need to impersonate a human actor.

Atlas should preserve:

```text
actor kind = workflow/system
institutional source = Elm Farm
triggering subject/event = ...
workflow provenance = ...
```

### Person with a bounded institution relationship

A Person acting through a personal or otherwise non-institutional channel may still originate an institutionally attributable consequence when Atlas has sufficient governed relationship evidence over the affected reality.

For example:

```text
Marshall has a current governed Elm relationship
covering greenhouse production responsibility requests
```

may support Elm source attribution for a greenhouse responsibility-offer effect.

Atlas does not require a universal action-class permission registry to express this law. The relationship must simply be sufficiently bounded and relevant to the consequence being resolved.

The relationship must not be inferred solely from:

- Organization membership;
- employee status;
- title;
- `owner` label;
- Principal identity;
- responsibility alone;
- visibility alone;
- endpoint send permission;
- email signature;
- sender display name;
- the actor's own claim that they represent the institution.

## Existing owner endpoint compatibility behavior

Current communication helpers may treat an Organization membership whose role is `owner` as implicitly able to administer/send through an endpoint.

That remains compatibility behavior for the existing communication runtime.

It is not promoted into the generic law:

```text
role = owner
-> every consequence emitted by this Person is Elm-attributable
```

Nor does `employee` imply that a Person may originate responsibility for the employer.

## Personal-channel example

Suppose:

```text
Marshall -> Anna
from Marshall's personal email
"Elm needs you to handle this."
```

If Atlas cannot establish a relevant Elm relationship supporting that responsibility-offer consequence, Atlas preserves:

```text
actor/source event = Marshall
claimed institutional source = Elm Farm
institutional source of offer = not established
```

Anna may still receive a normal pending responsibility offer from Marshall.

If Atlas can establish sufficient bounded Elm relationship evidence for this consequence, it may preserve:

```text
actor = Marshall
channel = personal email
institutional source of offer = Elm Farm
source basis = governed relationship evidence
```

No broader Elm standing is inferred.

## Later institutional uptake

A Person-originating event may fail to establish institutional source at the time it occurs and still later be taken up by an institution.

Example:

```text
Event 1:
Katie -> Anna
"Elm wants you to prepare the venue."
```

If Elm source attribution is not established, Atlas does not pretend Katie's event came from Elm.

Later:

```text
Event 2:
Elm Farm adopts the responsibility request into Elm-governed reality.
```

Atlas then preserves:

```text
original event source = Katie
later uptake source = Elm Farm
```

The later uptake may create a new Elm-originating responsibility-offer consequence. It does not rewrite Event 1 or manufacture earlier representation.

## Standing responsibility intake

A standing intake agreement admitting offers from institution I may auto-accept only when the incoming responsibility-offer consequence is sufficiently attributable to I at the relevant time and the rest of the standing agreement matches.

Conceptually:

```text
responsibility-offer effect O
+ institutional source O = I established
+ standing agreement A active
+ target/effect/time/context satisfy A
+ no unresolved source/scope/effect conflict
-> O may be accepted under A
```

If source attribution is merely claimed or unresolved:

```text
-> no standing auto-acceptance
```

If the institution later takes up the request, that later institutional effect is evaluated at the uptake time rather than backdating automatic acceptance.

## Effective custody matters

Physical/historical Organization IDs are not sufficient when custody has been adjudicated or migrated.

Source attribution should use effective institutional custody at the relevant historical time wherever Atlas has a resolver.

If endpoint/workflow/source custody is ambiguous or unresolved, dependent institutional attribution fails closed.

## Conflicting source evidence

Atlas may encounter conflicting provenance such as:

- personal message claiming an institutional source;
- historical carrier endpoint with uncertain effective custody;
- conflicting evidence about the actor's institutional relationship;
- workflow custody conflict;
- later institution uptake after an initially personal event.

Atlas preserves the evidence and historical events rather than applying hidden precedence.

Where standing intake or another consequence depends on source attribution, unresolved attribution fails closed locally.

## Explainability requirement

For any responsibility-offer effect treated as institution-attributable, Atlas should be able to explain at least:

- originating event;
- actual actor/workflow;
- institutional source of the effect;
- channel/path;
- endpoint/source/workflow identity where applicable;
- effective custody evidence;
- relevant institutional relationship evidence;
- affected Scope/context;
- event/effect time;
- later uptake or supersession where relevant;
- conflicting source evidence.

Conceptually:

```text
responsibility_offer_source:
  originating_event: ...
  actor: Marshall
  institution: Elm Farm
  path: governed_relationship
  affected_scope: greenhouse production
  custody: Elm Farm established
  effective_at: ...
```

## Existing Atlas precedents

Useful current mechanisms include:

- `communication_endpoints`;
- `effective_communication_endpoint_organization_v1`;
- endpoint member grants;
- endpoint/source bindings;
- outbound operations;
- connected sources;
- institutional communication admission reviews;
- communication event source observations;
- communication identity links;
- effective institutional custody adjudication;
- domain workflow events and handoffs.

These provide provenance and custody evidence. None is silently promoted into a universal permission or representation ontology.

## Deliberately not included yet

This architecture tranche creates no:

- generic institutional source-attribution table;
- generic action-class registry;
- representation-mandate table;
- source-attribution resolver;
- generic uptake table;
- standing-intake trigger;
- endpoint authorization migration;
- role hierarchy;
- universal `speaks_for` relation;
- production permission change;
- UI.

## Resulting law

> Institutional source attribution is provenance attached to a particular event/effect. Atlas establishes it from governed custody and relationship evidence relevant to the consequence being resolved, not from titles, roles, sender strings, or a universal action permission. Later institutional uptake may create a new institution-originating consequence without rewriting the source of the earlier event. Source attribution establishes where the consequence came from; it does not establish factual truth or guarantee that every proposed effect takes hold.
