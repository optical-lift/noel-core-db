# Atlas Ledger Target Intelligence v1

**Status:** candidate implementation contract  
**Date:** 2026-09-30  
**Canonical source lane:** `optical-lift/noel-core-db`  
**Depends on:** Reality / Ledger core; Reality / Ledger External Entity Bridge v1; Claims/Evidence separation; Reality Transition law  
**Does not supersede:** Governed Scope, Shared Intelligence acquisition, domain-owned Reality admission, Communication, Ledger Entity Context, or domain-specific outcome authority

## 1. Purpose

Atlas needs a universal way to answer:

> For this Ledger's present purpose, which Reality subjects currently satisfy the governed target definition, which do not, and which remain indeterminate because required facts are unresolved?

The immediate proving case is business prospecting, but the architecture must not encode a CRM, a venue, a corridor, an industry, a campaign, or one sales method.

The reusable movement is:

```text
Ledger purpose
  -> versioned Target Definition
  -> deterministic evaluation against current governed Reality
  -> qualified | not_qualified | indeterminate
  -> exact Evidence Obligation for unresolved predicates
  -> later acquisition / evidence / admission through the owning domains
  -> reevaluation
```

The Target Intelligence layer does not own external-world truth. It does not manufacture Reality from inference. It does not authorize communication.

## 2. Governing distinctions

The following facts are different and must remain different:

```text
Reality Entity exists
!=
this Ledger cares about the Entity
!=
the Entity satisfies this Target Definition
!=
the Entity ranks highly among qualifying Entities
!=
communication is authorized
!=
communication occurred
!=
a commercial outcome occurred
!=
a learned pattern should change policy
```

The first executable slice proves only the target-definition/evaluation boundary.

## 3. Relationship to Smart Contacts

The existing Smart Contacts / `build_target_contact_set` work is a proving case and quarry.

It established useful patterns including:

- literal-intent capture;
- interpretation separated from deterministic execution;
- reusable canonical identity;
- discovery/enrichment distinction;
- immutable selection snapshots;
- saved-search revisioning;
- model-version provenance;
- outcome-bearing contact history.

It predates the current Reality / Ledger root and must not become the universal ontology by extension.

Therefore v1 does not depend on:

- `smart_contact_*` tables;
- `atlas.external_relationships`;
- `atlas.external_relationship_interactions`;
- Organization-owned contact sets;
- `local_intel` as target-definition authority;
- the TypeScript `build_target_contact_set` schema.

Those remain compatibility/proving evidence until deliberately migrated.

## 4. Purpose is Ledger-private

A Target Definition exists because a particular Ledger is trying to accomplish something.

V1 introduces a bounded `Target Purpose` object owned by one Ledger.

A Target Purpose answers:

> Why is this Ledger evaluating subjects?

It does not answer:

> Which subjects qualify?

Example conceptual separation:

```text
Purpose:
  develop a new institutional customer channel

Target Definition A:
  subjects with operating presence in two governed regions

Target Definition B:
  appointment-driven professional organizations in a governed service area
```

One Purpose may therefore govern multiple Target Definitions.

A Purpose is not canonical Reality about the target Entity and must never be copied into `reality.entities`.

## 5. Target Definition

A Target Definition is a Ledger-private governed selection construct.

It answers:

> What must be true, false, or otherwise resolved for a Reality subject to belong to this target population under this definition version?

The identity of a Target Definition is stable across revisions.

The semantic rule lives in append-oriented Target Definition Versions.

A definition does not itself:

- admit a Reality Entity;
- alter a Reality relationship;
- attach an Entity to `ledger.entity_contexts`;
- create a prospect/customer/supplier context;
- rank the subject;
- authorize research;
- authorize outreach;
- create a task;
- create institutional Scope membership.

## 6. Target Definition is not Governed Scope

Governed Scope and Target Definition share constitutional requirements:

- explicit definitions;
- composition;
- versioning;
- explainability;
- fail-closed ambiguity;
- historical reconstruction.

They answer different questions.

Governed Scope answers which bounded institutional reality a Scope refers to and participates in visibility/responsibility/authority architecture.

Target Definition answers whether a Reality subject satisfies a Ledger's selection rule for a purpose.

Therefore:

```text
Target qualification
!=
Scope membership
!=
institutional custody
!=
visibility
!=
responsibility
!=
authority
```

V1 does not create a Scope when a subject qualifies.

## 7. Predicate grammar v1

The first predicate grammar is intentionally small.

It must prove composition and open-world uncertainty without becoming a universal query language.

V1 supports:

### Composition

```json
{"op":"all","predicates":[...]}
{"op":"any","predicates":[...]}
{"op":"not","predicate":{...}}
```

### Exact Reality identity / type

```json
{"op":"entity_id_is","entityId":"<uuid>"}
{"op":"entity_kind_is","entityKind":"business"}
```

### Exact Reality relationship proposition

```json
{
  "op":"relationship_exists",
  "relationshipKind":"operates_in",
  "direction":"outbound",
  "counterpartyEntityId":"<uuid>"
}
```

Direction is explicit:

- `outbound`: evaluated subject is `subject_entity_id`;
- `inbound`: evaluated subject is `object_entity_id`.

A relationship counts as positive v1 evidence only when current `reality.entity_relationships.relationship_state` is `observed` or `established`.

The grammar deliberately does not include:

- SQL fragments;
- table names supplied by callers;
- arbitrary JSONPath;
- arbitrary column selectors;
- free-text search semantics;
- model score thresholds;
- web-query strings;
- provider instructions;
- executable function names.

## 8. Three-valued evaluation

Every predicate resolves to exactly one logical state:

```text
true
false
unknown
```

Target qualification is derived from the root state:

```text
true    -> qualified
false   -> not_qualified
unknown -> indeterminate
```

This is open-world evaluation.

Absence of a Reality relationship is not automatically evidence that the relationship is false.

Therefore a missing `relationship_exists` edge resolves to `unknown`, not `false`.

A disputed exact relationship also resolves to `unknown`.

### Composition law

`all`:

```text
any false   -> false
else unknown -> unknown
else         -> true
```

`any`:

```text
any true    -> true
else unknown -> unknown
else         -> false
```

`not`:

```text
true    -> false
false   -> true
unknown -> unknown
```

This is deterministic Kleene-style three-valued composition for v1.

## 9. Explainability

A bare qualification status is insufficient.

Every evaluation must preserve a predicate trace sufficient to answer:

```text
Which Target Definition Version was evaluated?
Which Reality Entity was evaluated?
Which leaf predicates were true?
Which were false?
Which were unknown?
Which canonical Reality rows supplied positive evidence?
Which exact unresolved proposition prevented a deterministic answer?
Which evaluator version produced the receipt?
When did evaluation occur?
```

The trace is a read/explanation artifact. It is not canonical external Reality.

## 10. Evidence Obligation

An `unknown` relationship predicate creates an Evidence Obligation.

An Evidence Obligation answers:

> What exact proposition must be resolved before this predicate can become determinate?

For v1 relationship evaluation, the obligation shape is conceptually:

```json
{
  "kind":"resolve_relationship_proposition",
  "subjectEntityId":"<uuid>",
  "relationshipKind":"operates_in",
  "direction":"outbound",
  "counterpartyEntityId":"<uuid>"
}
```

The obligation does not say how to research it.

It does not authorize a provider call.

It does not create a Claim, Evidence record, or Reality relationship.

It is a Ledger-private statement of missing knowledge.

A later acquisition adapter may consume the obligation and seek evidence through Shared Intelligence / external-source machinery. Admission remains owned by the appropriate Reality/evidence domain.

## 11. Evidence acquisition boundary

V1 stops before acquisition.

Future movement may be:

```text
open Evidence Obligation
  -> governed acquisition request
  -> provider/source observation
  -> Claim/Evidence/identity resolution
  -> domain-owned Reality admission or adjudication
  -> obligation rechecked
  -> Target Evaluation rerun
```

The Intelligence layer may request evidence.

It may not convert its own inference into Reality.

## 12. Evaluation receipt

Each evaluation is persisted as a Ledger-private historical receipt.

Minimum receipt identity:

- Ledger;
- Target Definition;
- Target Definition Version;
- evaluated Reality Entity;
- root evaluation state;
- qualification state;
- evaluator key/version;
- predicate trace;
- evaluation time;
- provenance;
- associated Evidence Obligations.

A later Reality change does not rewrite the old receipt.

A new evaluation creates new history.

## 13. No ranking in v1

Qualification and ranking are separate contracts.

V1 answers only:

```text
qualified
not_qualified
indeterminate
```

It does not assign:

- lead score;
- probability of conversion;
- expected revenue;
- priority order;
- nearest-match score.

A later ranking contract must consume only qualified/indeterminate candidates under an explicit model version and may not silently redefine population membership.

## 14. No communication authority

A qualified target is not authorized outreach.

Target Intelligence does not grant:

- email capability;
- phone capability;
- marketing permission;
- Communication Endpoint authority;
- delegated-agent command authority;
- responsibility to contact the subject.

Any later outreach path must pass through the existing Communication / responsibility / delegated-agent membranes applicable to the action.

## 15. No automatic Ledger Entity Context consequence

Qualification does not automatically create:

```text
ledger.entity_contexts(context_kind='prospect')
```

Target qualification means only that the subject satisfies the governed Target Definition.

An institution may separately choose to attach the Entity as a prospect, candidate, supplier, customer, participant, or another context.

That decision is a later governed consequence.

## 16. Reality metadata boundary

Target Intelligence must never write Ledger-private qualification material into canonical Reality identity metadata.

Forbidden examples include:

- campaign key;
- offer key;
- price;
- fit band;
- target score;
- selection reason;
- suggested use;
- Ledger opportunity model;
- private notes.

Canonical Reality may preserve identity/admission/evidence provenance appropriate to Reality.

Ledger-private selection meaning remains in Ledger custody.

## 17. Version law

Target Definition Versions are append-oriented semantic snapshots.

V1 requires:

- monotonically increasing `version_number` per Target Definition;
- immutable predicate JSON after insertion;
- at most one active version per Target Definition;
- no reactivation of a retired version;
- every Evaluation references one exact version UUID.

Historical evaluations remain interpretable even after a later version becomes active.

## 18. Evaluator version law

The deterministic interpreter/evaluator is separately versioned from the Target Definition.

Therefore Atlas can distinguish:

```text
Target Definition Version 4
Evaluator Version 1
Reality state observed at evaluation time
```

from a later evaluation using:

```text
Target Definition Version 4
Evaluator Version 2
```

V1 evaluator key is descriptive and static.

No evaluator key may be dynamically dispatched into a caller-supplied function name.

## 19. Predicate depth and boundedness

V1 is intentionally bounded.

The validator must reject:

- malformed predicates;
- unknown operators;
- empty `all` / `any` lists;
- `not` without exactly one nested predicate;
- invalid UUIDs;
- blank entity/relationship kinds;
- unsupported direction values;
- excessive predicate nesting.

Maximum nesting depth v1: 12.

This is a semantic and denial-of-service boundary, not merely a UI limit.

## 20. Internal-only first executable slice

The first implementation is database-internal.

It introduces no `public.*` browser RPC.

It introduces no authenticated direct table grants.

The first executable objects are:

- `ledger.target_purposes`;
- `ledger.target_definitions`;
- `ledger.target_definition_versions`;
- `ledger.target_evaluations`;
- `ledger.target_evidence_obligations`;
- predicate validation/evaluation functions;
- one internal evaluation service;
- one read-only receipt composer.

All are private to internal/service custody in v1.

## 21. Generic proving fixture

The clone proof must not depend on Elm-specific vocabulary.

Fixture topology:

```text
Ledger L
Purpose P
Target Definition T
Region A Reality Entity
Region B Reality Entity
Business X
Business Y
Business Z
```

Target rule:

```text
ALL
  entity_kind_is business
  relationship_exists outbound operates_in Region A
  relationship_exists outbound operates_in Region B
```

Fixture facts:

```text
Business X -> operates_in -> Region A
Business X -> operates_in -> Region B

Business Y -> operates_in -> Region A
(no evidence yet for Region B)

Person Z
```

Expected results:

```text
Business X -> qualified
Business Y -> indeterminate + one Evidence Obligation for Region B
Person Z   -> not_qualified
```

The SQL object names, predicate grammar, and evaluator contain no domain-specific fixture vocabulary.

## 22. Required clone proof

Before promotion, validation must prove at minimum:

1. Target Purpose belongs to exactly one Ledger.
2. Target Definition belongs to the same Ledger as its Purpose.
3. Target Definition Version predicate validates before storage.
4. unknown operators fail closed.
5. malformed UUIDs fail closed.
6. nesting deeper than 12 fails closed.
7. version numbers are unique per definition.
8. at most one active version exists per definition.
9. predicate semantics cannot change after insertion.
10. `entity_kind_is` returns deterministic true/false.
11. `entity_id_is` returns deterministic true/false.
12. established exact relationship returns true.
13. observed exact relationship returns true.
14. disputed exact relationship returns unknown.
15. absent relationship returns unknown rather than false.
16. `all` follows three-valued law.
17. `any` follows three-valued law.
18. `not` preserves unknown.
19. a true root stores `qualified`.
20. a false root stores `not_qualified`.
21. an unknown root stores `indeterminate`.
22. each unresolved relationship leaf creates exactly one Evidence Obligation.
23. a deterministic leaf creates no Evidence Obligation.
24. an Evaluation points to an exact Definition Version.
25. reevaluation creates new history rather than rewriting an earlier receipt.
26. receipt composition explains the predicate trace and obligations.
27. no Evaluation creates or modifies `reality.entities`.
28. no Evaluation creates or modifies `reality.entity_relationships`.
29. no Evaluation creates `ledger.entity_contexts`.
30. no Evaluation creates `ledger.actions`.
31. no direct `anon` or `authenticated` table access exists.
32. no browser-executable evaluation mutation API exists.
33. no dynamic SQL or caller-supplied function execution exists.
34. no Smart Contacts / legacy external-relationship dependency exists.

## 23. Explicit non-scope

Do not add in v1:

- web research;
- provider connectors;
- automatic evidence admission;
- universal Place ontology;
- distance/radius predicates;
- arbitrary numeric comparisons;
- full-text predicates;
- embedding similarity;
- model scoring;
- target ranking;
- automatic prospect attachment;
- automatic communication;
- target campaign UI;
- generic workflow queue;
- generic rule engine;
- generic Scope migration;
- learned-policy mutation;
- legacy Smart Contacts migration.

## 24. Next dependencies after proof

Once Target Intelligence v1 is clone-proved, the next Reality improvements should be chosen by real Evidence Obligations produced by target evaluation.

The expected first two proving domains are:

1. external organization topology;
2. canonical Place/location relationships.

Those should be promoted only as far as target/evidence cases actually require.

A later acquisition adapter can then turn unresolved target predicates into bounded research requests.

## 25. Core sentence

> A Ledger may define, version, and explain what would make Reality relevant to a purpose; Atlas may evaluate that definition against current governed facts and name exactly what it does not yet know, but qualification never manufactures Reality, custody, authority, outreach, or outcome.