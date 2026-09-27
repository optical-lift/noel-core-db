# Atlas Implementation Workbench v1

Status: governing implementation architecture  
Date: 2026-09-27

## Purpose

The Implementation Workbench is Atlas's universal manual intent surface.

A human operator may build a sentence by tapping/long-pressing structured pieces, type ordinary language that is interpreted into the same pieces, or accept a carrier-assisted draft. The carrier is replaceable. The typed sentence is the durable request.

The Workbench does **not** own truth, Foundry adjudication, Reality admission, canonical reconciliation, domain authority, or execution effects.

Its job is:

```text
preserve literal request
→ normalize a domain-independent sentence
→ resolve an explicitly registered operation
→ derive DISCOVER / ESTABLISH / ACT
→ preview destination, authority and consequence
→ human confirms routing
→ hand the typed request to the governing membrane
```

A routed sentence is not proof that the destination operation succeeded.

## Constitutional distinction

```text
sentence != interpretation
interpretation != route
route != authority
route confirmation != truth confirmation
route confirmation != execution warrant
preview != effect
```

The Workbench may tell the right system what the operator is trying to do. It may not become that system's authority merely because it can describe the request.

## Three routes

### DISCOVER

Use when the request supplies evidence/testimony, proposes candidate understanding, opens inquiry, or asks Foundry to adjudicate pre-Atlas structure.

Destination: governed Foundry service.

Examples:

- preserve testimony;
- submit candidate assertions;
- open an adjudication case;
- request case adjudication.

`DISCOVER` never writes canonical Atlas Reality.

### ESTABLISH

Use when the request asks a governed Atlas membrane to admit, reconcile, correct, or otherwise establish canonical truth.

Destinations in v1 are bounded to membranes already defined by Atlas architecture, including:

- Foundry → Atlas admission;
- Reality Entity reconciliation.

The Workbench can route the request. The destination membrane performs its own authority check and confirmation ceremony.

### ACT

Use when the request asks for a governed operation over reality Atlas already knows.

The Workbench uses the existing company-neutral Operation Contract membrane as the preview grammar:

```text
subject
requirement
operation
responsibility
execution conditions
routing
result contract
continuation
provenance
```

An ACT sentence is not executable merely because its Operation Contract normalizes successfully. The target domain command still owns execution authority and effects.

## Universal sentence grammar

The Workbench sentence is deliberately smaller than a domain ontology.

Required:

- `operator.operationKey` — exact registered semantic operation;
- `subject` — what the sentence is about.

Optional but first-class:

- `literal` — original human wording;
- `source` — who/what supplied the information or request;
- `object` — target/value/referent of the operation;
- `scope` — jurisdiction, field, collection, place, or other boundary;
- `time` — current/historical/effective/occurred/planned/conditional timing;
- `qualifiers` — modality, conditions, exceptions, quantities, or other typed modifiers;
- `basis` — evidence/provenance references;
- `destinationInput` — typed input expected by the destination membrane;
- `operationContract` — ACT-only operation-contract material when available.

The grammar does not contain a free-form SQL target, table name, function name, or arbitrary mutation instruction.

## Registry, not model discretion

A carrier may suggest an `operationKey`, but the route comes from Atlas's operation registry.

The registry fixes:

- operation key;
- route class;
- destination membrane;
- destination operation;
- whether destination input is required;
- whether an ACT Operation Contract is required;
- whether routing requires explicit human confirmation;
- the truth/effect boundary shown in preview.

An unknown operation key remains unresolved. The Workbench must not guess a route from prose and then mutate truth.

This means two carriers interpreting the same operation key get the same constitutional route.

## v1 registered operations

DISCOVER:

- `discover.record_testimony` → Foundry `record_testimony`;
- `discover.submit_candidate_assertions` → Foundry `submit_candidate_assertions`;
- `discover.open_case` → Foundry `open_case`;
- `discover.request_case_adjudication` → Foundry `request_case_adjudication`.

ESTABLISH:

- `establish.foundry_admission_plan` → Foundry admission planning membrane;
- `establish.foundry_admission_handoff` → Foundry admission execution membrane;
- `establish.reality_identity_merge_proposal` → Reality reconciliation proposal membrane;
- `establish.reality_identity_merge_confirmation` → Reality reconciliation confirmation membrane.

ACT:

- `act.governed_operation` → an already-registered domain command, represented through `operation_contract_v1` before execution.

The ACT registry entry is a routing class, not generic execution authority. Its `destinationInput` must identify an existing governed adapter/command contract. The Workbench never dynamically executes a supplied PostgreSQL function name.

## Request custody

`atlas.workbench_intents` preserves:

- the canonical Reality Person who composed it;
- original literal request;
- normalized sentence;
- operation key and deterministic route;
- carrier/provenance metadata;
- preview snapshot;
- routing receipt;
- optional superseded-intent link;
- timestamps and lifecycle.

Once routed, the sentence is immutable. Correction creates a new intent linked with `supersedes_intent_id`.

This preserves the difference between what the human asked and what later systems did with it.

## Preview

Preview is mandatory before routing.

It must show at least:

- route: DISCOVER / ESTABLISH / ACT;
- destination membrane and operation;
- literal request and typed sentence;
- canonical actor;
- what this routing step can and cannot establish;
- destination authority requirement;
- blockers;
- whether routing may proceed;
- for ACT, the normalized Operation Contract or a blocker explaining why one cannot yet be formed.

Preview may change when the registry or relevant current state changes. Routing re-previews immediately before it records the handoff.

## Human route confirmation

v1 requires the authenticated canonical Person who owns the Workbench intent to confirm routing.

This confirmation means only:

> Send this typed intent to this governing membrane.

It does not mean:

> I have already established the claim as canonical truth.

It does not bypass destination confirmation.

## Destination envelopes

A routed intent produces an immutable receipt/envelope containing:

- Workbench intent ID;
- route class;
- operation key;
- destination membrane;
- destination operation;
- normalized sentence;
- destination input;
- actor Reality Person;
- Workbench preview;
- route-confirmation basis/time;
- Workbench provenance.

DISCOVER envelopes are suitable for a connected Foundry carrier/service.

ESTABLISH envelopes point at the exact Atlas authority membrane that must perform the next decision.

ACT envelopes carry the Operation Contract plus target command metadata, but never execute arbitrary effects themselves.

## Relationship to Foundry

Workbench does not duplicate Foundry's answer-processing pipeline.

```text
Workbench DISCOVER
→ Foundry testimony/candidate/case/adjudication
→ Foundry structural delta / sealed candidate
→ Atlas admission when appropriate
```

A manual sentence can therefore begin Foundry work without requiring AI to directly edit Supabase.

## Relationship to existing language-to-Skill seams

Existing typed intent surfaces such as Contact-Set Intent remain valid domain adapters.

The Workbench sits one level above them:

```text
Workbench ACT sentence
→ operation registry
→ existing governed Skill / domain adapter
→ Operation Contract / domain authority
→ effect
```

The Workbench should reuse such contracts rather than reimplementing their domain-specific interpretation or execution plans.

## Carrier neutrality

The same normalized sentence may be assembled by:

- direct manual selection;
- typed ordinary language plus AI interpretation;
- a practitioner tool;
- an external authorized carrier;
- native Atlas UI.

Carrier metadata is provenance, not authority.

The database validates the typed sentence. It does not pretend the database itself understood English.

## Security and authority

- anonymous callers cannot compose, preview, or route;
- authenticated callers require a canonical Reality Person binding;
- raw tables are private and RLS-enabled;
- composing and previewing create no canonical truth;
- routing requires the same authenticated Person who composed the intent in v1;
- Workbench routing cannot grant any destination permission;
- no table/function/SQL name supplied in a sentence is executed dynamically;
- service role does not receive a generic Workbench truth-write endpoint;
- destination membranes remain independently authoritative.

## State machine

```text
COMPOSED
→ PREVIEWED
→ ROUTED

COMPOSED/PREVIEWED
→ CANCELLED
```

`ROUTED` and `CANCELLED` are terminal.

A changed sentence is a new intent, not an edit of routed history.

## Acceptance criteria

Workbench v1 is valid only when:

1. a canonical authenticated Person can compose a domain-independent sentence;
2. literal wording and typed structure are both preserved;
3. route is derived from a closed operation registry rather than free-form model choice;
4. all three route classes are represented;
5. DISCOVER routes only to Foundry operations and cannot establish Reality;
6. ESTABLISH routes only to explicit Atlas authority membranes and cannot bypass them;
7. ACT requires an Operation Contract and cannot execute an arbitrary supplied function;
8. preview precedes routing;
9. routing requires explicit human confirmation;
10. Workbench confirmation is explicitly not destination truth/execution confirmation;
11. routed sentence history is immutable;
12. corrections use superseding intents;
13. unknown operation keys fail closed;
14. carriers cannot add registry entries through the API;
15. no generic SQL/CRUD surface exists;
16. no `ledger.ledgers` or `reality.entities` row is created by Workbench routing itself;
17. destination envelopes preserve actor, source sentence, provenance, preview, and route basis.
