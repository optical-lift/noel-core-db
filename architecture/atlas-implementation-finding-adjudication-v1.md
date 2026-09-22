# Atlas Implementation Finding Adjudication v1

**Status:** candidate architecture  
**Date:** 2026-09-21  
**Release lane:** Atlas  
**Depends on:** Implementation Case/Thread/Finding custody; assigned practitioner authority; Reality Candidate custody  
**Purpose:** make `IMP-04 Finding Review / Promotion` a real governed seam without turning implementation text into canonical domain truth.

## 1. Problem

Production already has `atlas.implementation_findings` with statuses:

- `proposed`
- `governed`
- `rejected`
- `superseded`
- `unresolved`

but there is no ordinary practitioner command that immutably adjudicates a Finding into those states.

The current artifact-review path may create a **proposed** Finding. It does not govern the Finding.

This means `IMP-05` cannot lawfully publish a Client Operating Model from “governed Findings” until a real adjudication seam exists.

## 2. Governing distinction

A Finding adjudication governs the implementation interpretation of one exact Finding.

It does **not** establish the underlying domain fact.

Examples:

- “The dispatch handoff should be represented by this governed crosswalk” may be eligible as implementation configuration.
- “Alice is an institutional Person of Acme” is an existing-domain fact. A Finding adjudication alone may not establish that relation. Model eligibility requires a separately promoted Reality Candidate / owning-domain consequence.
- “We should move approval authority to Bob” is a proposed repair. Governing the recommendation does not make that future authority current truth.

Therefore:

> **Finding governance and domain establishment are separate authority events.**

## 3. New append-only evidence

Introduce:

`atlas.implementation_finding_adjudications`

Each row records:

- exact Finding;
- exact Case + Thread;
- immutable statement snapshot;
- Finding class;
- decision;
- prior and resulting Finding status;
- whether the decision is eligible for future Client Operating Model use;
- optional linked promoted Reality Candidate for an existing-domain fact;
- optional superseding Finding;
- practitioner/reviewer identity;
- evidence snapshot;
- basis;
- governing policy/version;
- previous adjudication in the chain;
- idempotency request id;
- timestamp and provenance.

The adjudication row is append-only. Updates/deletes fail closed.

`implementation_findings.status` remains a current projection updated transactionally from the immutable adjudication.

## 4. Initial Finding classes

V1 admits:

- `configuration_crosswalk`
- `existing_domain_fact`
- `proposed_repair`
- `decision_authority_fact`
- `privacy_custody_boundary`
- `activation_risk_acceptance`
- `unresolved_structure`

These classes are intentionally not a universal ontology. They exist only to decide what the implementation adjudication is allowed to mean next.

## 5. Initial decisions

V1 admits:

- `govern_for_model`
- `keep_proposed`
- `mark_unresolved`
- `reject`
- `supersede`

Status projection:

- govern_for_model → governed
- keep_proposed → proposed
- mark_unresolved → unresolved
- reject → rejected
- supersede → superseded

## 6. Model-eligibility boundary

V1 deliberately permits `govern_for_model` only for:

### configuration_crosswalk

A model/crosswalk interpretation whose governance does not itself claim to mutate domain truth.

It must not carry a linked Reality Candidate.

### existing_domain_fact

A Finding that describes reality already owned by another domain.

It is model-eligible only when linked to an `implementation_reality_candidates` row that:

- belongs to the same Implementation Case;
- belongs to the same Thread or is case-level;
- is already `promoted`;
- carries nonblank canonical consequence kind/ref.

The adjudication references that promoted consequence. It does not replace it.

Other classes may be preserved/rejected/unresolved/superseded in v1 but may not become model-eligible through this command. Their stronger authority paths remain future work.

## 7. Practitioner authority

Mutation requires:

`implementation_practitioner_assigned_to_case_self_v1(case_id)`.

General practitioner authorization without assignment to the exact case is insufficient.

The initial v1 command does not claim to satisfy future second-practitioner requirements for high-consequence classes. Those classes therefore cannot become model-eligible through v1.

## 8. Idempotency

Every adjudication command requires a caller-supplied UUID request id.

Exact retry returns the original adjudication.

Reusing the request id with different semantics fails closed.

## 9. Supersession

`supersede` requires a distinct Finding in the same Implementation Case.

The superseding Finding is not automatically governed. It keeps its own current state and requires its own adjudication.

## 10. Read membrane

Expose one assigned-practitioner read:

`implementation_finding_review_self_api_v1(finding_id)`.

It returns:

- Finding current status;
- exact Case/Thread;
- adjudication history;
- current adjudication;
- current model eligibility;
- linked canonical consequence evidence where present.

No direct table access is granted to browser roles.

## 11. Explicit non-scope

This tranche does not:

- create Client Operating Model tables;
- publish a model;
- execute a domain command;
- create or mutate Reality Candidates;
- create Responsibility, Authority, Membership, Person, Organization, Work, Sale, payment, or source truth;
- implement second-practitioner policy;
- decide activation readiness;
- activate a Ledger binding.

## 12. Completion criterion

The tranche is complete when a case-assigned practitioner can immutably adjudicate one Finding; exact retry is idempotent; unsupported/high-consequence classes cannot become model-eligible; an existing-domain fact cannot become model-eligible without a promoted same-case Reality Candidate; later adjudications preserve history; and browser callers have no direct table authority.
