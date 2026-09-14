# Atlas Institutional Responsibility Source Attribution v1

## Status

Architecture contract only. No executable generic institutional-source-attribution schema or runtime exists in this tranche.

## Purpose

Define when Atlas may treat a responsibility offer as having come **from an institution** rather than merely from a Person who says they represent that institution.

This contract exists because standing responsibility intake may admit future offers from a source such as `Elm Farm`. Atlas therefore needs a governed answer to:

> What makes this offer count as having come from Elm Farm?

The answer must preserve the already-settled distinctions between:

- actor identity;
- institutional source attribution;
- truth of claims contained in the offer;
- action authority;
- transport permission;
- Ledger/institutional custody;
- responsibility acceptance.

None of these dimensions may silently substitute for another.

## Governing principle

**Actor and institutional source are separate facts.**

Conceptually:

```text
Person A performed action X
Institution I is the attributable source of X
```

may both be true at the same time.

For example:

```text
actor: Marshall
institutional source: Elm Farm
action: send routine production responsibility offer to Anna
```

This does not mean:

- Marshall is the institution;
- Marshall's statements are automatically true;
- Marshall has universal authority over Elm;
- every action Marshall takes is attributable to Elm;
- every message from Marshall's personal account counts as Elm work.

Source attribution is action-local and provenance-backed.

## Source attribution is not truth authority

If Atlas establishes that an offer came from Elm Farm, that establishes only the source provenance of the offer.

It does **not** establish that every proposition inside the offer is true.

Example:

```text
Elm Farm attributable offer:
  "The north bed is ready for harvest. Please harvest it today."
```

Atlas may validly establish:

```text
source = Elm Farm
```

while the factual claim:

```text
north bed is ready for harvest
```

remains false, disputed, unsupported, or unresolved under the claims/evidence layer.

Institutional source provenance and factual truth must remain distinct.

## Source attribution is not generic action authority

A Person may be able to send through an institutional communication endpoint without holding every form of institutional action authority.

Conversely, a Person may hold a bounded action authority and act for an institution through an Atlas-native workflow without using an email endpoint.

Therefore:

```text
transport permission != institutional source attribution != generic action authority
```

A valid source path must establish that the particular action was emitted on behalf of the institution in the relevant context.

## Canonical source-attribution paths

Atlas may recognize multiple governed paths by which an action becomes attributable to an institution. These paths are alternative provenance mechanisms, not universal rank classes.

### 1. Institution-custodied endpoint path

An action may be attributable to an institution when it is emitted through an endpoint that Atlas can resolve as effectively custodied by that institution and the sending action itself is validly performed through that endpoint.

A strong path conceptually requires:

```text
institution-custodied endpoint
+ active/valid send transport binding
+ authenticated/recorded actor
+ actor permitted to perform this endpoint action
+ durable outbound operation provenance
+ no unresolved custody/source conflict
-> institutional source attribution candidate
```

Existing communication machinery provides useful precedent:

- `communication_endpoints` has an Organization or Principal custody root;
- `effective_communication_endpoint_organization_v1` resolves endpoint institutional custody through effective custody adjudication;
- `communication_endpoint_source_bindings` binds endpoints to actual connected send/receive transports;
- `communication_endpoint_member_grants` expresses endpoint capabilities such as `send`;
- `communication_outbound_operations` preserves Organization, unit, endpoint, connected source, initiating membership, content hash, and operation state;
- outbound guards require endpoint, source, conversation, and actor to share current compatibility custody.

These mechanisms can support source provenance, but they are not yet the generic source-attribution ontology.

### 2. Institution-governed native workflow path

An Atlas-native workflow may emit a responsibility offer directly on behalf of an institution without pretending a human personally authored the event.

Conceptually:

```text
institution-governed workflow W
+ W is effectively custodied by institution I
+ W is permitted to emit action class A in context C
+ event E is durably linked to W and its triggering governed reality
+ no unresolved custody/source conflict
-> E may be attributable to institution I
```

The source actor may be recorded as a service/workflow/system actor while the institutional source remains the institution.

Existing `workflow_events`, institutional communication runtime, and other domain workflows are useful precedents, but current farm-shaped workflow tables are not silently promoted into the generic rule.

### 3. Person acting on behalf of an institution

A Person may act through a personal or otherwise non-institutional channel and still validly perform an institution-attributable action, but only when Atlas has an explicit, action-local basis for representation.

Conceptually:

```text
Person P
+ explicit current representation/delegation basis for institution I
+ representation covers action class A
+ representation covers affected Scope/context X
+ action E is attributable to P and falls inside A/X
+ provenance links E to that representation basis
-> E may be attributable to institution I
```

This path prevents Atlas from requiring every institutional action to originate from a company mailbox while still rejecting bare self-assertion.

The representation basis must not be inferred merely from:

- Organization membership;
- employee status;
- title;
- position;
- owner label;
- Principal status;
- responsibility alone;
- visibility alone;
- a signature saying `Elm Farm`;
- a From/display-name string;
- the Person's claim that they are acting for Elm.

The representation basis is itself a governed relationship/action fact.

## No role-label speaking authority

Current compatibility communication helpers sometimes grant endpoint capabilities implicitly to an Organization membership whose role is `owner`.

That is a runtime compatibility rule for existing communication operations. It is **not** adopted as the generic institutional source-attribution law.

Atlas must not infer:

```text
role = owner
-> every action by this Person is institution-attributable
```

or:

```text
role = employee
-> Person may emit responsibility offers for the employer
```

Source attribution remains action-local.

## Endpoint permission versus institutional attribution

If a Person has permission to send from `hello@elmfarm.co`, that proves an endpoint capability and enables the transport action.

For standing-intake purposes, Atlas must still preserve at least:

- actual actor;
- endpoint identity;
- effective institution custodian of the endpoint at action time;
- connected transport used;
- action/operation provenance;
- applicable action context;
- any relevant representation or workflow basis.

In the common case, an institution-custodied endpoint plus valid send operation will be sufficient source provenance for an ordinary institutional communication. But source provenance remains explainable rather than being reduced to `sender address string = institution`.

## Personal channel examples

### Personal message without representation basis

```text
Marshall -> Anna
from: Marshall personal email
message: "Elm needs you to handle this."
```

If Atlas has no action-local representation basis:

```text
actor = Marshall
claimed source = Elm Farm
institutional source attribution = not established
```

A standing intake agreement admitting only `source = Elm Farm` must not auto-accept the responsibility.

The offer may still be delivered to Anna as a normal pending offer from Marshall.

### Personal message with bounded representation basis

If Atlas has established that Marshall may issue Elm Farm production responsibility offers over Scope S during period T, and the message satisfies that bounded relationship:

```text
actor = Marshall
channel = personal email
institutional source = Elm Farm
source basis = explicit representation R
```

The offer may qualify for Anna's Elm standing intake if all other standing-intake boundaries also match.

This does not grant Marshall broader Elm powers.

## Institutional endpoint examples

If Anna receives a responsibility offer produced through an active Elm Farm endpoint whose effective institutional custody resolves to Elm Farm and whose outbound operation preserves the initiating actor and valid send path, Atlas may establish:

```text
institutional source = Elm Farm
actor = actual initiating Person/system
```

The endpoint display name is not the source evidence by itself. The governed endpoint/transport/custody chain is.

## Internal workflow examples

Suppose Elm's production system observes an established operational condition and emits a routine responsibility offer that falls inside Anna's standing intake agreement.

Atlas should preserve:

```text
actor kind = governed workflow/system
institutional source = Elm Farm
triggering reality = specific governed subject/event
workflow provenance = specific rule/run/event
```

The workflow does not need to impersonate Marshall or another human sender.

## Effective custody matters

Physical/historical Organization IDs are not sufficient when institutional custody has been adjudicated or migrated.

Source attribution should resolve effective institutional custody at the relevant historical time wherever such a resolver exists.

For communication endpoints, `effective_communication_endpoint_organization_v1` is an existing precedent.

If endpoint/workflow/source custody is ambiguous, mixed, carrier-only, or otherwise unresolved, Atlas must not auto-establish institutional source attribution.

## Action-local representation

Representation must be evaluated against the action actually performed.

Examples of distinct possible action classes include conceptually:

- issue routine responsibility offer;
- create or revise institutional work;
- send informational communication;
- approve expenditure;
- commit institution to contract;
- reroute responsibility;
- establish customer promise;
- communicate policy;
- accept vendor obligation.

A Person may legitimately represent an institution for one action class without representing it for another.

Thus:

```text
may send Elm production work
!=
may sign Elm lease
```

No generic `speaks_for_organization = true` shortcut is established.

## Scope/context bounding

An action-local representation may also be bounded by Governed Scope, Ledger intersection, unit, workflow family, relationship, time, or other semantic context.

For example:

```text
Person P may issue Elm Farm responsibility offers
for Scope = greenhouse production
```

must not silently expand to:

```text
Person P may issue Elm Venue event commitments
```

Cross-Ledger representation must be proved for each affected effective custody intersection.

## Institutional source and standing intake

A standing intake agreement that admits offers from institution I should auto-accept an incoming offer only when:

```text
incoming offer O
+ source attribution to I is established
+ standing agreement A is active
+ O satisfies A's target boundary
+ O satisfies A's admitted effect/context/time rules
+ no unresolved source/scope/effect conflict
-> O may be accepted under A
```

If source attribution is merely claimed, uncertain, or disputed:

```text
-> no standing auto-acceptance
-> offer remains pending/unresolved
```

This fail-closed behavior prevents impersonation or ambiguous representation from manufacturing responsibility.

## Source attribution lifecycle and historical reconstruction

Institutional source attribution is time-sensitive.

A Person may have had a valid representation basis on September 10 and not on September 15. An endpoint may have been custodied by one institution before a later custody adjudication. A connected source may have been active at one time and revoked later.

Historical responsibility reconstruction must therefore use source-attribution evidence effective at the time of the offer/action.

Current status must not rewrite historical provenance.

## Conflicting source evidence

Source attribution can itself be disputed.

Examples:

- a message claims Elm Farm but came from a personal address with no resolved representation;
- an endpoint is physically attached to a historical carrier while effective custody is disputed;
- two institutional paths claim the same source action;
- a representation basis is alleged to have expired before the action;
- a workflow event is claimed to be institutional but its custody is unresolved.

Atlas should preserve the competing evidence rather than choose by hidden precedence.

Where a responsibility decision depends on source attribution and source attribution is unresolved, the dependent standing-intake path fails closed.

If adjudication is later required, the adjudication establishes Atlas's current institutional treatment of the source question; it does not make underlying propositions metaphysically true.

## Explainability requirement

For any responsibility offer treated as institution-attributable, Atlas should be able to explain at least:

- institutional source;
- actual actor or workflow/system actor;
- action class;
- channel/path kind;
- endpoint/source/workflow identity where applicable;
- effective custody evidence;
- actor capability/representation basis where applicable;
- Scope/context boundary;
- timestamp/effective window;
- provenance links;
- any superseded or conflicting source evidence.

Conceptually:

```text
source_attribution:
  institution: Elm Farm
  actor: Marshall
  path_kind: institution_endpoint
  endpoint: hello@elmfarm.co
  transport: connected mail source
  action_class: responsibility_offer
  custody: established Elm Farm
  basis: recorded outbound operation
  effective_at: ...
```

## Existing Atlas precedents

Useful existing mechanisms include:

- `communication_endpoints`;
- `effective_communication_endpoint_organization_v1`;
- `communication_endpoint_member_grants`;
- `communication_endpoint_source_bindings`;
- `communication_outbound_operations`;
- `connected_sources`;
- `institutional_communication_admission_reviews`;
- `communication_event_source_observations`;
- `communication_identity_links`;
- effective institutional custody adjudication;
- domain workflow events and workflow handoffs.

These provide transport, custody, identity, conflict, and provenance precedents. None is automatically the complete generic institutional-source-attribution object.

## Deliberately not included yet

This architecture tranche creates no:

- generic institutional source-attribution table;
- representation/delegation table;
- generic action-class registry;
- source-attribution resolver;
- standing-intake automatic-acceptance trigger;
- generic responsibility-offer table;
- generic Responsibility Relation table;
- endpoint authorization migration;
- removal of existing owner compatibility behavior;
- role hierarchy;
- universal `speaks_for` relation;
- production permission change;
- UI.

## Resulting law

The settled law is:

> A responsibility offer counts as having come from an institution only when Atlas can establish an action-local, provenance-backed path from the actual actor/workflow through reality effectively attributable to that institution. Institution-custodied endpoints, institution-governed workflows, and explicit bounded Person representation may each provide such a path. Role labels, titles, membership, display names, sender assertions, or transport permission alone do not create universal institutional attribution. Source attribution establishes provenance, not factual truth. When source attribution is unresolved, any standing-intake behavior that depends on it fails closed.
