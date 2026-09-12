# Atlas Addressability + Resolver — Database Adjudication v1

**Status:** Architecture adjudication; no executable migration in this change  
**Established:** September 11, 2026  
**Database authority:** `optical-lift/noel-core-db`  
**Upstream product architecture:** `optical-lift/atlas#47`  
**Tracking issue:** `#521`

## 1. Decision

Atlas needs one new universal identity seam for **addressability**, but it does **not** need a second Local database, a second communications system, a duplicate location store, or a public copy of organizational truth.

The governed movement is:

```text
real entity
  -> source-backed Addressable Subject
  -> publication / discoverability policy
  -> Addressable Interface
  -> actor/context-sensitive resolution
  -> existing owning domain
```

The new seam is intentionally thin. It gives Atlas a stable thing to resolve across organizations and across the pre-Atlas / Atlas-native boundary. It does not absorb the truth already owned by Organization, Organization Unit, Communications, Local, Capability, Event, Location, Commerce, Evidence, Claim, Connected Source, or other canonical domains.

## 2. Live-state evidence inspected

This adjudication was made against current `noel-core` production schema read-only and current `noel-core-db` `main`.

Relevant live facts include:

- `atlas.identity_subjects` exists and is explicitly Organization/tenant scoped.
- `atlas.identity_source_records`, `atlas.identity_claims`, source-subject assertions, pair assertions, human review/adjudication, and `atlas.identity_subject_projections` form the existing Core Identity reconciliation substrate.
- The released Core Identity migration explicitly states that the thin subject UUID is tenant-scoped and is **not a canonical Party directory**.
- `local_intel.entities` is scoped by `local_context_id`; `(local_context_id, stable_key)` is unique, and ingestion candidate identity/deduplication is likewise Local scoped.
- `atlas.organizations` and `atlas.organization_units` own Atlas institutional identity. Elm currently exists as Organization Unit `elm` beneath Organization `feast_guild`.
- Elm currently has an active Organization-Unit-scoped `atlas.communication_endpoints` email endpoint at `hello@elmfarm.co`.
- `atlas.evidence_records` and `atlas.claim_records` already provide cross-domain source evidence, proposition lifecycle, authority/provenance, validity, and supersession contracts without restricting `scope_kind` / subject vocabulary to one domain.
- `atlas.connected_sources` and `atlas.communication_endpoint_source_bindings` already separate provider transport custody from durable institutional communication endpoints.
- `atlas.places` is currently farm-scoped (`farm_id`) operational place truth; it is not a universal semantic Building/Place registry.
- Current live schema does not expose a public/actor-safe known-entity resolver, a universal addressable identity anchor, addressability publication authority, or subject/interface reachability contract.

## 3. Existing authorities to reuse

### 3.1 Organization and Organization Unit

`atlas.organizations` and `atlas.organization_units` remain the institutional authority for organizations that actually participate in Atlas.

An Atlas-native Organization or Organization Unit may **bind to** an Addressable Subject. The Addressable Subject does not replace the Organization or Unit and does not copy its institutional state.

For Elm:

```text
Feast Guild (Organization)
  -> Elm (Organization Unit)
      -> bound Addressable Subject: Elm Farm
```

The Addressable Subject is the network-reachable identity. Elm remains the institutional operating body.

### 3.2 Core Identity reconciliation

`atlas.identity_subjects` remains a tenant-scoped reconciliation anchor.

It must **not** be promoted into the universal/public resolver simply because it already has names, aliases, contact points, and person/organization/place projections. Its `organization_id` custody and released architecture are intentional.

Where useful, a tenant-scoped Identity Subject may later assert/bind that it refers to an Addressable Subject. That relation must preserve tenant scope; it must not make one tenant's reconciliation state globally authoritative.

### 3.3 Atlas Local

`local_intel.entities` remains Organization/Local-owned external-world state.

A Local entity may contribute evidence that it refers to an Addressable Subject, but Local identity must remain independently scoped. Two Local contexts may represent the same real-world organization differently without sharing private relationship, relevance, research, market, or execution state.

Therefore:

```text
Local Entity != Addressable Subject
```

and:

```text
Local Entity
  -> source-backed reconciliation assertion
      -> Addressable Subject
```

The bridge should be owned from the Local side rather than making the universal identity root depend on `local_intel`.

### 3.4 Evidence and Claim

`atlas.evidence_records` should remain the universal source-evidence carrier for externally observed names, URLs, emails, phone numbers, addresses, provider assertions, domain proof, owner statements, and other addressability evidence where their existing contract fits.

`atlas.claim_records` should remain the governed proposition layer for source-backed statements about an Addressable Subject.

Examples may include canonical/display name, alias, entity classification, website route, email route, phone route, published physical destination, domain-control assertion, Atlas Organization / Unit binding evidence, and publication assertion.

A Resolver projection may summarize current accepted/admitted claims for fast reads. The projection must not become a second evidence authority.

### 3.5 Institutional Communications

`atlas.communication_endpoints` remains the durable institutional communications endpoint authority.

`atlas.communication_endpoint_source_bindings` remains the replaceable provider-transport binding.

An Addressable Interface such as `contact` or `message` may resolve to a Communication Endpoint. It must not copy the endpoint address, provider account, source token, thread identity, response responsibility, or transport state into an addressability table.

Correct:

```text
Addressable Subject: Elm Farm
  -> interface: contact
      -> resolver kind: institutional_communication
          -> Elm Organization Unit
              -> active Communication Endpoint
                  -> provider/source transport
```

### 3.6 Atlas Capability

Atlas Capability retains its established meaning: an enduring organizational ability.

Do not reuse `Capability` to mean a public network endpoint.

An Addressable Interface may eventually expose or invoke an organizational Capability, but they remain different concepts:

```text
Capability = what an organization knows how to do
Addressable Interface = a governed way another actor may reach, inspect, request, or invoke something
```

### 3.7 Places / Buildings

Current `atlas.places` is operational/farm-scoped and cannot be silently promoted into universal public place identity.

The selected Building Addressability architecture still requires a semantic Building/Place identity and custody contract. The new Addressable Subject seam may host or bind that future identity, but this adjudication does not declare current farm `places` to be public Building authority.

## 4. Genuinely missing canonical roles

The following roles are not supplied by current released authority.

Logical role names below are **not automatically table names**; the executable candidate must keep the physical object count as small as possible.

### 4.1 Addressable Subject

A thin, durable, non-tenant identity anchor for a real entity that may participate in Atlas resolution.

Required properties:

- stable UUID identity independent of display name;
- supported semantic class sufficient for v1 resolution (`organization`, `institution`, future `person`, `building/place` as separately admitted);
- lifecycle / retirement without destructive deletion;
- source-backed establishment/provenance;
- no provider account, email address, URL, phone number, physical address, employee, Local relationship state, or current interface result stored as identity-defining truth.

This is distinct from tenant-scoped `atlas.identity_subjects`.

### 4.2 Controlled institutional binding / publication authority

Atlas needs a bounded relation proving when an existing Atlas Organization or Organization Unit has authority to publish for an Addressable Subject.

For v1 this should use real foreign keys to Organization / Organization Unit. Do not introduce unrestricted polymorphic `object_type + object_id` authority.

The binding must distinguish at least externally observed / no Atlas publishing authority, Atlas institution bound but not necessarily publicly discoverable, entity-authorized publication active, and retired/revoked/superseded authority.

Binding authority is not the same as transport control and is not implied merely by a matching domain name or email string.

### 4.3 Discoverability / reachability policy

Identity existence does not imply that it may be enumerated or contacted.

Atlas needs governed policy sufficient to determine whether the subject may be returned in exact known-identity resolution, whether it may appear in broader discovery/search, whether a particular interface is visible/usable to the current actor/context, and whether authentication is required.

V1 should default closed.

### 4.4 Addressable Interface

A subject-specific governed interface descriptor such as `contact`, `message`, `visit`, `events`, `availability`, and later `apply`, `volunteer`, `book`, `buy`, `pay`, `support`, `report`, or `request` when real owning domains exist.

An interface owns only the fact that this interface is exposed for this subject, interface lifecycle, discoverability/reachability policy, a bounded resolver kind, and source/publication authority/provenance.

It does **not** own the current answer returned by the target domain.

### 4.5 Bounded resolver-kind registry

Resolution must not become arbitrary SQL/JSON execution configured in rows.

V1 needs a bounded resolver-kind contract whose implementations call existing governed reads/operations.

Candidate resolver kinds include `institutional_communication_endpoint`, `source_attributed_external_route`, and later governed public place/event/availability projections.

Unsupported/missing resolver authority returns an explicit unavailable/unresolved result. It does not encourage the application to join raw tables.

### 4.6 Local -> Addressable Subject reconciliation assertion

Atlas needs a source-backed assertion that a particular Local-owned entity appears to represent a particular Addressable Subject.

This should be a Local-side bridge so universal addressability does not acquire a hard dependency on Local state.

A model recommendation alone cannot establish the global match.

### 4.7 Actor-safe known-entity Resolver API

A governed server-side read membrane is missing.

V1 should return stable Addressable Subject identity, current safe display projection, semantic class, verification/publication position, source freshness/conflict position where relevant, visible Addressable Interfaces, and explicit unavailable/ambiguous states.

The authenticated client must not receive raw private evidence, private Local state, hidden candidate identities, provider credentials, or unrestricted internal identifiers merely because resolution succeeded.

## 5. Bootstrap lifecycle

### State A — externally observed

Atlas has source evidence that a real entity exists and has one or more external routes. Atlas must not imply that the entity has authenticated, published, endorsed, or delegated authority to Atlas.

### State B — entity reconciled / claimed

An authorized Atlas Organization/Unit proves and establishes that it is the institutional authority for the already-existing Addressable Subject. The existing subject is strengthened; a duplicate identity is not created merely because the entity joined Atlas.

### State C — entity-published interfaces

The bound entity explicitly publishes allowed interfaces and policies. Atlas may now resolve directly into Atlas-native domains where those domains have governed seams.

### State D — Atlas-native interaction

When both sides participate and the relevant interface permits it, the Resolver may use Atlas-native transport/operations without requiring the user to know the carrier.

## 6. Claim / authentication boundary

A claim workflow must never reduce to `matching email = ownership`.

V1 institutional claim/publication authority should be derived from existing authenticated Atlas Organization authority plus an explicit binding/establishment operation. Domain/provider proof may be supporting evidence when required, not an automatic universal authority grant.

## 7. Privacy / anti-enumeration decision

V1 is **authenticated Atlas resolution only**. Anonymous/public-web resolver access is deferred.

- Atlas-bound organizations/operating institutions may be discoverable only through explicit publication policy.
- Externally observed organizations may be returned when source evidence and policy admit it, but must be labeled source-attributed / externally observed.
- Persons are private/non-enumerable by default.
- Households/residences are private/non-enumerable by default.
- Buildings are private/non-enumerable unless an authorized steward explicitly activates public addressability.
- Physical surfaces/devices are never independently public identities.

Exact known-identity resolution and broad search are separate operations.

## 8. Resolver behavior

```text
input identity / exact name / admitted identifier
  -> bounded candidate set
  -> identity ambiguity check
  -> subject discoverability policy
  -> actor/context authorization
  -> Addressable Interface visibility
  -> bounded resolver-kind dispatch
  -> owning-domain governed read/operation
  -> provenance/freshness/conflict envelope
  -> result
```

Material ambiguity fails closed. A missing target-domain seam returns `interface exists / currently unavailable` or `interface not yet established`; it does not cause application code to fabricate an answer from convenient raw tables.

## 9. Elm first proof — adjudicated form

Elm is suitable as the first Atlas-native subject because the underlying institution and one communication endpoint already exist in released canonical state.

### 9.1 Identity binding

The fixture should establish one Addressable Subject representing **Elm Farm** and bind it to Organization `Feast Guild` + Organization Unit `Elm`.

### 9.2 `contact`

This is the first interface that current authority can support end-to-end:

```text
Elm Farm
  -> contact
      -> institutional_communication_endpoint
          -> Elm Organization Unit
              -> active Communication Endpoint
```

The addressability layer stores no copy of that endpoint address.

### 9.3 `visit`

Current `atlas.places` is farm-scoped operational truth rather than universal semantic public Place/Building authority. Do not pretend it already satisfies public `visit` resolution.

### 9.4 `events`

No current actor-safe public Event/Occurrence read seam was found during this adjudication. Do not create a Resolver-owned event store.

### 9.5 `wholesale-availability`

Live Flower readiness/availability machinery exists, but no current public/actor-safe wholesale availability read membrane suitable for Resolver use was found. Do not query raw production/inventory tables from the Resolver.

### 9.6 Minimum proof

```text
Elm Addressable Subject
  -> exact authenticated resolution
  -> entity-authorized publication position
  -> contact interface
  -> existing Elm Communication Endpoint
```

plus explicit non-fabrication for the still-missing interfaces.

## 10. Externally observed organization proof

A second rollback-safe fixture must use one organization not controlled by Atlas/Optical Lift and prove:

```text
Local-discovered/source-observed external organization
  -> Addressable Subject
  -> externally_observed authority position
  -> source-attributed external route
```

It must prove no Atlas publication binding exists, provenance remains visible, and later entity claim strengthens the same subject rather than creating a duplicate.

## 11. Candidate physical schema direction

The next executable candidate should attempt the smallest coherent object set and justify every new object. Likely minimum roles:

1. `atlas.addressable_subjects` — thin global/network identity anchor;
2. bounded institutional publication/binding relation using real Organization / Organization Unit FKs;
3. governed subject/interface publication/reachability state;
4. Addressable Interface rows or equivalent normalized relation;
5. Local-side reconciliation assertion from `local_intel.entities` to Addressable Subject;
6. role-safe Resolver projection/API.

Before adding separate alias, route, verification, or current-state tables, attempt to reuse `atlas.evidence_records` + `atlas.claim_records` and derive a bounded resolver projection over them.

Do not implement an unrestricted polymorphic reference registry, arbitrary resolver JSON, generic SQL dispatch, provider-specific addressability columns, or a copied `public profile` truth store.

## 12. Security requirements for executable candidate

- no anonymous execution in v1;
- no direct `anon`/`authenticated` mutation of canonical addressability tables;
- no broad direct table reads when a governed Resolver API is intended;
- internal privileged helpers pin `search_path` and re-check actor authority;
- public/PostgREST wrappers expose only the intended safe contract;
- person/household/building subjects fail closed on enumeration/discoverability;
- provider secrets never cross the Resolver response;
- Local-private fields never cross the Resolver response merely because a Local entity reconciles to the subject;
- source conflicts/freshness uncertainty remain visible;
- resolver-kind dispatch is bounded to registered implementations.

Production Schema Clone Validation and candidate-introduced lint/advisor review remain required before release consideration.

## 13. Deferred

Deferred: anonymous public-web Resolver exposure, `/.well-known/atlas`, DNS verification, public Person directory semantics, household/residential publication, semantic Building/Place kernel details, exact public Event and Commerce projections, purchase/payment/booking action interfaces, cross-resolver federation, global handle uniqueness, and cryptographic portable identity.

## 14. Non-authorities

The addressability layer is not a global copy of Atlas Local, canonical Party directory from tenant projections, marketing profile store, replacement for Organization / Organization Unit, communications inbox, provider-account registry, location database, Event store, inventory/availability truth, Capability library, Work system, authority inference engine, or model-owned identity merge system.

## 15. Completion judgment

The database seam is sufficiently adjudicated to permit a **separate executable migration candidate**.

That candidate should first prove only:

```text
source-backed Addressable Subject
+ institution binding/publication authority
+ authenticated known-identity resolution
+ bounded Addressable Interface
+ Elm contact resolution through existing Institutional Communications
+ externally observed source-route fixture
```

`visit`, `events`, and `wholesale-availability` remain required product interfaces, but they must wait for or explicitly establish their owning-domain public read seams rather than being reconstructed inside the Resolver.
