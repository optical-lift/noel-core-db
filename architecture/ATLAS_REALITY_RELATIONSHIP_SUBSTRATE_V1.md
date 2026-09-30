# ATLAS_REALITY_RELATIONSHIP_SUBSTRATE_V1

Status: candidate governing architecture

## Purpose

Establish the universal, evidence-governed path by which Atlas may represent a relationship between two canonical Reality Entities without allowing an observation, a Ledger interpretation, a research result, or an AI inference to become canonical relationship truth merely because it was discovered or useful.

This contract is domain-neutral. A relationship may later express geography, organizational topology, responsibility, participation, ownership, service, role, project connection, or another governed relation. No Elm-, prospecting-, geography-, sales-, or contact-specific meaning belongs in this substrate.

## Root distinction

Atlas MUST preserve the transition:

`relationship proposition -> evidence -> adjudication -> canonical Reality relationship`

The following are not equivalent:

- a source states that A relates to B;
- Atlas has observed evidence supporting that proposition;
- an operator or governed resolver has adjudicated the proposition;
- Reality currently treats the relationship as observed or established;
- a Ledger regards that relationship as commercially or operationally relevant.

Only the canonical relationship is reusable shared Reality. Ledger-specific fit, score, campaign, offer, opportunity, priority, selection reason, outreach state, or commercial interpretation MUST NOT be copied into canonical relationship truth.

## Existing canonical carrier

`reality.entity_relationships` remains the canonical relationship carrier. This tranche does not replace it.

Canonical rows retain:

- subject Entity;
- governed relationship kind;
- object Entity;
- relationship state;
- effective validity interval;
- admission evidence/provenance;
- canonical metadata.

Target Intelligence may continue to read canonical `observed` and `established` rows as positive evidence and `disputed` rows as unresolved evidence.

## Relationship-kind governance

Relationship strings MUST NOT be free-form application vocabulary.

`reality.relationship_kinds` is the governed registry for relationship semantics. An active kind may define:

- stable relationship key;
- human-readable name and description;
- optional allowed subject Entity kinds;
- optional allowed object Entity kinds;
- optional inverse relationship kind;
- whether the relationship is symmetric;
- lifecycle state and metadata.

A null endpoint-kind constraint means the kind is not restricted on that endpoint. Endpoint restrictions are semantic guards, not a replacement for Entity identity.

Unknown or retired relationship kinds fail closed.

No domain-specific relationship kinds are seeded by this tranche. Domains may register kinds deliberately after their semantics are governed.

## Relationship proposition

`reality.relationship_propositions` records a proposed relationship before canonical admission.

A proposition identifies:

- subject Entity;
- relationship kind;
- object Entity;
- requested canonical state (`observed` or `established`);
- optional validity interval;
- proposition basis and provenance;
- lifecycle state.

A proposition is not canonical Reality.

Its semantic content is immutable after creation. State changes occur only through the governed adjudication service.

Self-relations are refused in v1. A future relationship kind requiring reflexive semantics must establish that law explicitly rather than bypassing the guard.

## Evidence

`reality.relationship_proposition_evidence` stores append-only evidence for a proposition.

Evidence may originate from an owner assertion, operator observation, official source, imported source, API, research process, or another lawful source. Evidence kind describes the source/evidence class; it does not confer truth by itself.

Evidence rows are immutable. Accepted or disputed propositions require at least one evidence row.

Evidence may contain source locators and evidence snapshots, but must not carry a requesting Ledger's private qualification or campaign meaning into canonical Reality.

## Adjudication

`reality.relationship_proposition_adjudications` stores append-only terminal decisions.

V1 decisions are:

- `accept` — admit the proposed relationship state into canonical Reality;
- `reject` — do not create canonical relationship truth;
- `dispute` — admit a canonical disputed relationship so downstream reasoning can remain explicitly unresolved.

The adjudication records rationale, authority basis, optional adjudicating Principal, and any resulting canonical relationship id.

One v1 proposition receives one terminal adjudication. New evidence after a terminal decision requires a new proposition or a later explicit challenge/resolution architecture; history is not rewritten.

## Canonical admission

Canonical promotion MUST:

1. revalidate that subject and object are active canonical Reality Entities;
2. revalidate that the relationship kind is active;
3. enforce endpoint-kind restrictions;
4. require evidence for `accept` or `dispute`;
5. refuse invalid validity intervals and self-relations;
6. refuse a conflicting active canonical state for the same semantic tuple rather than silently overwriting it;
7. reuse an identical existing canonical relationship when its semantic tuple and state already match;
8. otherwise create one canonical `reality.entity_relationships` row;
9. append the adjudication receipt and transition the proposition state.

V1 deliberately does not resolve conflicting canonical states. That requires a separate explicit conflict/challenge transition so historical truth is not overwritten casually.

## Canonical write boundary

Application roles MUST NOT insert, update, or delete `reality.entity_relationships` directly.

Service-role callers write propositions/evidence and invoke the admission service. The admission service is `SECURITY DEFINER` and is the canonical write membrane.

Direct owner/database-administrator maintenance remains possible through PostgreSQL ownership and migration authority, but is not an application contract.

## Inverses and symmetry

V1 records the asserted orientation only.

Registering an inverse kind documents semantics but does not automatically manufacture the inverse canonical row. A symmetric kind likewise does not create a second reversed row.

Automatic inverse projections, if needed, must be deterministic read behavior or a separately governed materialization law. This prevents one observed proposition from silently becoming two canonical facts.

## Relationship state

Canonical v1 states retain the existing Reality vocabulary:

- `observed`
- `established`
- `disputed`
- `retired`

Admission creates only `observed`, `established`, or `disputed` rows. Retirement/conflict replacement is intentionally outside this tranche.

## Interaction with Target Intelligence

Target Intelligence consumes canonical Reality but does not own it.

A Target predicate that requires a relationship may therefore receive:

- TRUE from an active canonical `observed` or `established` relationship;
- UNKNOWN from a canonical `disputed` relationship or from absence of established evidence;
- an Evidence Obligation identifying the unresolved proposition.

Satisfying that obligation does not mean Target Intelligence may insert a relationship. Evidence must still cross this relationship admission membrane.

## Non-goals

This tranche does NOT establish:

- Place or geography ontology;
- organizational branch/unit ontology;
- spatial distance or route calculations;
- Target ranking or scoring;
- automatic research;
- contact discovery;
- outreach or communication authority;
- Ledger prospect/customer context;
- learning or policy mutation;
- a generic cross-domain claim engine;
- automatic relationship inverses;
- canonical conflict replacement.

## Acceptance criteria

A rollback validation must prove at minimum:

1. a registered universal test relationship kind accepts valid endpoint kinds;
2. an unknown kind fails closed;
3. invalid endpoint kinds fail closed;
4. evidence can be appended while a proposition is open;
5. an accepted evidenced proposition materializes exactly one canonical relationship;
6. Target Intelligence can subsequently read that canonical relationship as TRUE;
7. a rejected proposition creates no canonical relationship;
8. a disputed evidenced proposition creates a canonical disputed relationship;
9. Target Intelligence reads the disputed relationship as UNKNOWN with an obligation;
10. duplicate admission with the same idempotency key is stable;
11. all synthetic fixture data is rolled back.

## Universal proving rule

The component passes architecture review only if its schema, functions, and validation can operate without the words or concepts Elm, venue, prospect, customer, Springfield, Lebanon, midpoint, sales, or campaign.

Those are consumers of Reality relationships, never their ontology.