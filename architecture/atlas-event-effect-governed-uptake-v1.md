# Atlas Event, Effect, and Governed Uptake v1

## Status

Architecture contract only. No generic event/effect/uptake schema or runtime is created in this tranche.

## Purpose

Replace the overly permission-centric question:

> What named class of action was this actor authorized to perform?

with a reality-first model:

> What actually happened, what consequences did that event attempt or appear to create, and which of those consequences take hold in governed reality?

Atlas must preserve the event first. Claims, responsibility offers, disclosures, institutional source, Scope changes, resource commitments, obligations, releases, and other consequences are resolved independently from that event.

## Governing law

**Events happen. Effects are interpreted from events. Governed relationships determine which effects take hold. Later events may adopt, redirect, supersede, reject, or otherwise change consequences without rewriting the originating event.**

Conceptually:

```text
observed/performed event E
        ↓
interpretations of E
        ↓
claims + proposed effects
        ↓
claims/evidence/custody/relationships/Scope/context
        ↓
independent effect resolution
        ↓
current governed consequences
```

The event is not made false merely because one proposed effect does not take hold.

Likewise, one valid consequence does not make every claim or proposed consequence inside the same event valid.

## Event is primary historical reality

An event records that something happened.

Examples:

- a Person sent a message;
- a Person clicked Accept;
- a Person moved an addition from one Scope to another;
- a workflow emitted a request;
- a Person signed a document;
- an institution later adopted a prior request;
- a Person reported work complete;
- a payment instruction was sent.

Atlas should preserve enough event provenance to answer, where applicable:

```text
who/what acted
what happened
when it happened
through what channel/workflow
what payload or referenced subjects were involved
what institution/Person/endpoint physically emitted it
what source/custody evidence existed
what earlier event it responded to
```

The event layer is not itself an assertion that every intended consequence became effective.

## One event may carry multiple independent semantic consequences

For example:

```text
Marshall -> Anna
"The north bed is ready. Please harvest it tomorrow."
```

may contain at least:

```text
communication event:
  Marshall sent a message to Anna

disclosure effect:
  Anna received the text and any intentionally attached information

claim:
  north bed is ready

responsibility-offer effect:
  Anna is being asked to carry tomorrow's harvest

institutional-source candidate:
  the offer may be presented as coming from Elm Farm
```

These do not rise and fall together.

Atlas may resolve:

```text
message happened = established
Anna can see disclosed text = established
readiness claim = false/disputed/unresolved
responsibility offer = established
institutional source = not established
Anna responsibility = not established until acceptance
```

No generic `event_valid = true/false` flag may replace those independent resolutions.

## Claims are not effects

A claim describes or predicts reality.

Examples:

```text
"The north bed is ready."
"The invoice was paid."
"Katie already accepted this."
```

A proposed effect attempts to change a governed relationship or consequence.

Examples:

```text
please carry this responsibility
accept this responsibility
include this subject in this Scope
reroute this addition
commit this resource
create this obligation
release this obligation
adopt this prior request as institutional work
```

A single event may contain both claims and proposed effects.

Claims continue through the separate claims/evidence/adjudication architecture. An effect cannot become valid merely because a related factual claim was asserted by someone with institutional standing.

## Effect semantics, not universal action classes

Atlas should understand the kind of consequence being proposed because different consequences have different governing rules.

The architecture currently recognizes effect families such as:

- disclose bounded information;
- create a claim;
- offer responsibility;
- accept responsibility;
- decline/withdraw responsibility offer;
- create or end a Responsibility Relation;
- add or alter a living Scope definition;
- reroute an existing addition;
- establish shared participation;
- transfer a responsibility carrier;
- create a resource commitment;
- create an obligation or promise;
- release an obligation;
- adopt a prior consequence into institutional reality.

These are semantic effect families, not a commitment to one executable enum and not a registry of every possible human act.

Atlas need not classify every message or behavior before preserving it as an event.

## Proposed effect versus effective consequence

An event may propose a consequence that never takes hold.

Conceptually:

```text
Event E
  proposes effect F over reality X
```

Atlas resolves F using the governing rules for that effect and the reality it would change.

Possible architectural outcomes include:

```text
effect takes hold
effect does not take hold
effect remains unresolved
```

These are conceptual states, not a final schema enum.

The resolver must preserve why the consequence did or did not take hold.

## Governed relationships determine uptake

The important question is not whether the actor possesses a universal title or a giant permission class.

The important question is whether existing governed relationships, over the affected reality, are sufficient for that proposed consequence to take hold.

Relevant evidence may include, depending on the effect:

- current responsibility over the affected reality;
- broader visibility + broader responsibility for Scope triage;
- root Ledger governance;
- a bounded institutional relationship allowing a Person to originate a particular kind of institutional consequence;
- receiver assent or standing responsibility-intake agreement;
- effective custody;
- a governed workflow relationship;
- contractual or external evidence;
- an existing institutional policy;
- a prior accepted Scope definition event;
- domain-specific governing relationships.

No one relationship silently substitutes for all others.

In particular:

```text
visibility != responsibility
responsibility != institutional uptake standing
institutional uptake standing != factual truth
endpoint transport permission != institutional uptake standing
commercial seat != any of the above
```

## Representation becomes evidence, not the primary ontology

The previous representation-mandate framing is superseded as the primary model.

Atlas may still need to know that a Person has a durable relationship to an institution that supports certain consequences taking hold.

For example:

```text
Marshall has a governed relationship to Elm Farm
covering greenhouse production responsibility requests
```

may be evidence that a responsibility-offer effect from Marshall should be treated as an Elm-originating offer within that bounded reality.

But Atlas does not need to begin with:

```text
Marshall owns permission ACTION_CLASS_173
```

Representation is therefore one form of relationship evidence used in effect resolution and source attribution. It is not a truth authority, universal rank, or required global action taxonomy.

## Transport remains separate

A Person may be able to send through `hello@elmfarm.co`.

That proves a transport capability under the current communication runtime.

It does not by itself determine every semantic consequence carried by the message.

For example, the same institutional email could contain:

- an ordinary informational disclosure;
- a responsibility offer;
- a factual claim;
- a purchase commitment;
- a contractual promise.

Each consequence must resolve under its own governing relationships.

The endpoint event remains real regardless.

## Governed uptake

**Governed uptake** is the later event by which a Person/institution/process takes up, adopts, redirects, rejects, supersedes, or otherwise establishes a consequence in its own governed reality.

This replaces the overly broad generic idea of retroactive `ratification`.

Example:

```text
Event 1:
Katie -> Anna
"Elm wants you to prepare the venue."
```

Suppose Atlas cannot establish that Katie's event produced an Elm-originating responsibility offer.

Atlas still preserves:

```text
Katie asked Anna to prepare the venue.
```

Later:

```text
Event 2:
Elm Farm takes up that request as Elm work.
```

The resulting history is:

```text
Katie made the original request.
Elm later adopted the requested consequence.
```

It is not:

```text
Katie was secretly authorized all along.
```

Uptake creates a new governed event/consequence. It does not rewrite provenance.

## Uptake is consequence-specific

An institution may take up one consequence of an earlier event without adopting everything in it.

Example:

```text
original event:
"The north bed is ready. Please harvest it tomorrow for Elm."
```

Elm may later adopt:

```text
the responsibility request
```

without adopting as established fact:

```text
the north bed is ready
```

The readiness statement remains a claim governed by evidence.

This is a central reason Atlas must decompose events into independent claims and proposed effects.

## Uptake does not automatically act retroactively

Generic Atlas semantics do not assume that later uptake reaches backward in time.

If Elm takes up Katie's request on September 15, Atlas must not automatically rewrite September 14 as though Elm originated the request then.

Instead:

```text
September 14: Katie-originating event
September 15: Elm uptake event
```

A domain may establish a separate legally or contractually meaningful retroactive consequence, but that requires its own governed rule/evidence and must not be assumed by the generic architecture.

## Standing responsibility intake after later institutional uptake

Suppose Anna has a standing agreement that pre-accepts qualifying responsibility offers from Elm Farm.

If Katie personally sends a request and Elm source attribution is not established at that time, Anna's Elm standing agreement does not fire merely because Katie says `Elm`.

If Elm later takes up the request, Atlas may create or establish an Elm-originating responsibility-offer consequence at the uptake time.

That later Elm consequence may then be evaluated against Anna's standing intake agreement.

Atlas must not fabricate an earlier automatic acceptance date.

If Anna independently accepted Katie's original request before Elm's uptake, that acceptance remains its own historical fact and the later Elm uptake may change the institutional context/custody of the resulting responsibility only where separate governing rules support that consequence.

## Scope changes fit the same model

A Person with sufficient local visibility + responsibility may directly add a Scope-definition event over reality they both see and carry.

That is an event whose Scope-definition effect takes hold because the already-settled local-addition relationship law admits it.

A broader participant may later triage through a new event.

The later triage does not invalidate or erase the first event.

Thus the same event/effect model applies to:

```text
local addition
broader reroute
split
consolidation
supersession
```

## Responsibility offers fit the same model

A responsibility-bearing communication creates at most a responsibility-offer effect for the receiver.

It does not create receiver responsibility by delivery.

Receiver acceptance is a later event whose responsibility-acceptance effect may establish a Responsibility Relation.

A standing intake agreement is prior receiver assent that may make the acceptance consequence take hold immediately when a qualifying offer arrives.

This remains fully consistent with the cross-Atlas responsibility architecture.

## Completion fits the same model

A Person may report:

```text
"Done."
```

The report event is real.

The claim that the obligation is fulfilled may require evidence.

The responsibility-completion consequence becomes effective only when Atlas has sufficient governed basis to treat the Responsibility Relation as completed.

Thus the event/effect model also prevents `reported complete` from being collapsed into `completed`.

## Institutional source attribution under this model

Source attribution answers:

> To whom is this event or effect attributable?

It does not answer:

> Did every proposed consequence take hold?

An event can be institutionally sourced while some of its proposed effects fail.

Conversely, a Person-originating event may later have one consequence institutionally taken up without changing the original event's source.

Source attribution therefore stays provenance-oriented and effect resolution stays consequence-oriented.

## No generic event invalidation

Atlas must avoid architecture such as:

```text
event.authorized = false
therefore ignore event
```

An event that was not sufficient to establish its intended institutional effect may still be important evidence, communication history, provenance, or a source of later claims and offers.

The correct pattern is:

```text
event preserved
proposed effects resolved independently
```

## Conflicts and uncertainty

If Atlas cannot determine whether a semantic effect was actually proposed, it may preserve the interpretation as uncertain rather than silently creating the effect.

If the proposed effect is clear but the governing relationship is uncertain, the effect remains unresolved and dependent downstream behavior fails closed.

Examples:

```text
message definitely sent
responsibility request interpretation uncertain
```

or:

```text
responsibility offer clearly present
institutional source unresolved
```

or:

```text
Scope-change intent clear
actor's local visibility/responsibility containment unresolved
```

The event itself remains preserved in every case.

## Historical reconstruction

Atlas must be able to reconstruct:

1. what events occurred;
2. what claims/effects were interpreted from them at the time;
3. what governing relationships/evidence existed then;
4. which consequences took hold then;
5. which later events adopted, rejected, redirected, superseded, released, completed, or otherwise changed those consequences.

Current state must not be projected backward onto historical events.

## Existing Atlas precedents

Current Atlas already contains useful local examples of this architecture:

- communication events preserve messages separately from derived Company Work;
- `communication_derived_work_links` preserve message -> work provenance;
- work allocations separate work identity from responsibility carrier;
- append-only Scope-definition architecture separates definition events from current materialized state;
- claim/evidence tables separate claims from supporting/contradicting evidence;
- custody adjudications preserve historical physical state while establishing current institutional treatment;
- workflow/task handoff events preserve domain-local changes without rewriting earlier events.

None is automatically promoted into one universal event/effect schema in this tranche.

## Superseded architecture

The prior architecture document `atlas-institutional-action-representation-mandates-v1.md` treated a generic representation mandate plus explicit action classes as the primary ontology.

That framing is superseded.

The useful laws preserved from it are narrower:

- roles/titles do not automatically establish institutional consequence;
- transport permission does not establish every semantic consequence;
- factual claims remain independently true/false;
- broader responsibility/visibility does not generically establish every institutional effect;
- provenance and historical timing must be preserved;
- institution-binding relationships may be important evidence.

The rejected part is the assumption that Atlas should organize institutional behavior first around a generic action-class permission registry.

## Deliberately not included yet

This architecture tranche creates no:

- universal event table;
- universal effect table;
- effect enum;
- generic action-class registry;
- representation-mandate table;
- generic uptake table;
- event/effect resolver;
- retroactive ratification behavior;
- generic actor registry;
- production permission change;
- UI.

## Resulting law

The settled law is:

> Atlas preserves what happened first. It then resolves the claims and proposed consequences carried by that event independently. Governed relationships, evidence, custody, Scope, receiver assent, and other effect-specific rules determine which consequences take hold. Later institutional uptake is a new event that may adopt or redirect a prior consequence without rewriting the origin or manufacturing earlier representation. Representation is relationship evidence inside that resolution process, not the primary ontology and not a universal action-class permission system.
