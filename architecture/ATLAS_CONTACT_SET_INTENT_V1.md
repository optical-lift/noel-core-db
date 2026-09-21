# Atlas Contact-Set Intent v1

## Purpose

Create the first executable language-to-Skill seam for Atlas Intelligence.

The motivating utterance is ordinary language:

> Go find emails for bank people in those towns.

Atlas must preserve that literal request, resolve lawful context, interpret it into a typed contact-set objective, validate ambiguity, and produce a deterministic execution plan before any research or relationship mutation occurs.

This package does not execute web research, send communication, create campaign state, or establish new external identities. It establishes the governed request/interpretation/plan carrier that later execution consumes.

## Governing distinctions

```text
literal request
!= interpretation
!= execution plan
!= research evidence
!= canonical Shared Intelligence
!= private Ledger relationship effect
!= communication authority
```

The interpreter may reason. The database validates the output and fixes the order of operations.

## Contact-set Skill

Skill key: `build_target_contact_set`

The full procedure contract is maintained by the Atlas application repository at:

`skills/build-target-contact-set/SKILL.md`

The database contract in this package is deliberately independent of any one model/provider.

## Request custody

`atlas.contact_set_intent_requests` is Organization-private Atlas Intelligence working state.

It stores:

- requesting Organization / optional Organization Unit;
- authenticated requester;
- literal request;
- capture context supplied by the lawful application/context broker;
- structured interpretation;
- deterministic validation result;
- deterministic execution plan;
- interpreter provenance.

It does not become Shared Intelligence and it does not create a relationship merely because a canonical external entity is mentioned.

## Structured interpretation

The interpreter contract must preserve at least:

- `intentFamily = build_target_contact_set`
- objective: `retrieve | enrich | discover | mixed`
- target object with non-empty `description`
- fields object with non-empty `required` array
- optional geography
- optional population semantics
- optional Ledger-effect declaration
- `resolvedReferences` array
- `unresolvedReferences` array
- `clarificationQuestion` when unresolved references materially block execution.

The database does not pretend to understand English. It validates the typed result.

## Deterministic plan

When interpretation is structurally valid and execution-ready, Atlas emits this fixed operation sequence:

1. `shared_directory_search`
2. `requesting_ledger_overlay_read`
3. `contact_gap_analysis`
4. `acquire_missing_truth` — conditional and gap-only
5. `canonical_identity_resolution` — conditional for acquired/new evidence
6. `requesting_ledger_relationship_effect` — conditional on interpreted Ledger effect
7. `return_contact_set`

The interpreter cannot reorder this to make external research the first source.

## Clarification

A request may be structurally valid but not executable because context references remain unresolved.

Example:

`Find bank people in those towns.`

If `those towns` was not resolvable from lawful capture context, the interpretation should include that unresolved reference and a focused clarification question.

If the towns were present in context, Atlas should not ask the human again.

## Security

- raw request table is private and RLS-enabled;
- authenticated callers use Organization-scoped self APIs;
- interpretation is service-only;
- anonymous callers receive no function access;
- capture does not create canonical truth or a Ledger relationship.

## Acceptance target

The first proof is not “the model generated good JSON.”

The proof is:

1. literal request is preserved;
2. requesting Organization is explicit;
3. structurally valid contextual interpretation becomes `ready`;
4. unresolved contextual reference becomes `needs_clarification`;
5. deterministic plan begins with Shared Directory and makes acquisition gap-only;
6. no Shared Intelligence or relationship state changes during capture/interpretation.
