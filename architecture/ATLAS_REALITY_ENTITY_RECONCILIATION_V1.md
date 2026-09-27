# Atlas Reality Entity Reconciliation v1

Status: governing implementation architecture  
Date: 2026-09-27

## Purpose

Reality is Atlas's canonical identity authority. Shared Intelligence is an evidence and custody system.

That separation creates a necessary second boundary after admission:

```text
evidence later establishes A and B are one real-world entity
→ evidence may propose reconciliation
→ Reality shows the consequences
→ an explicitly authorized human confirms
→ Reality reconciles the identities atomically
```

Shared Intelligence never acquires canonical merge authority.

## Core law

```text
evidence equivalence != Reality merge
review approval != Reality merge
proposal != Reality merge
preview != Reality merge
canonical merge = explicit Reality responsibility + human confirmation
```

An evidence system may discover identity equivalence before or after Reality admission. If both identities have already been admitted to `reality.entities`, the evidence system cannot silently collapse them.

## Durable identity history

A confirmed reconciliation has one **survivor** and one **superseded identity**.

The superseded `reality.entities` row is never deleted. It is retired with explicit supersession metadata and a durable row in `reality.entity_supersessions`.

Therefore an old Entity ID remains historically intelligible:

```text
old Reality ID
→ entity_supersessions
→ surviving canonical Reality ID
```

`reality.resolve_canonical_entity_v1(uuid)` provides that resolution primitive.

`retired` alone does not mean “duplicate.” The supersession table carries that meaning explicitly.

## Proposal

A reconciliation case identifies:

- the proposed surviving Reality Entity;
- the proposed superseded Reality Entity;
- where the proposal came from;
- the evidence/source reference;
- the proposal basis;
- the human Reality Person and responsibility relation when a human opened it.

Both entities must already exist in Reality, be canonical, and have the same `entity_kind`.

A proposed pair cannot already be superseded and cannot have another unresolved reconciliation case in either direction.

## Shared Intelligence boundary

`atlas.reality_entity_reconciliation_propose_from_evidence_service_v1(...)` permits service-side evidence machinery to open a proposal.

It can do exactly one thing of authority significance:

```text
evidence → proposed Reality reconciliation case
```

It cannot preview through a human authority context, confirm the case, write `entity_supersessions`, retire a Reality Entity, or rewrite a Reality reference.

The service role has no raw mutation grant on the reconciliation tables and no execute privilege on the confirmation API.

## Human authority

Canonical reconciliation uses a distinct explicit Reality responsibility:

- responsibility: `reality_identity_reconciliation`;
- jurisdiction domain: `reality.identity_resolution`;
- operations:
  - `canonical_merge.propose`;
  - `canonical_merge.preview`;
  - `canonical_merge.execute`.

This responsibility is distinct from `reality_identity_adjudication`.

A Person who may approve a Shared Intelligence identity review does not thereby gain canonical merge authority.

The current operator relation is explicitly established by this migration. It is not inferred from a Seat, legacy owner role, Principal, Organization Membership, or the pre-existing identity-review relation.

## Impact preview

Before confirmation Atlas computes a live impact projection from PostgreSQL foreign-key metadata.

The preview identifies every direct single-column foreign key to `reality.entities(id)` that currently references either candidate and reports:

- schema/table/column;
- constraint name;
- survivor reference count;
- superseded reference count;
- compatibility bindings that must move;
- known hard blockers.

A direct `reality.entity_relationships` edge between the two candidate identities is a hard blocker because blind repointing would create a self-relationship. That relationship must be adjudicated first.

The preview deliberately does **not** claim that every downstream unique/check constraint is predictable in advance. Confirmation remains atomic and fail-closed.

## Confirmation and execution

Human confirmation requires `canonical_merge.execute`.

The execution transaction:

1. locks the case and both Reality Entity rows;
2. recomputes the live impact;
3. refuses known blockers;
4. discovers direct foreign keys to `reality.entities(id)`;
5. repoints each superseded reference to the survivor;
6. aborts the entire transaction if any dependent unique/check/FK constraint rejects the rewrite;
7. rewrites `compatibility.legacy_bindings` that routed to the superseded Reality ID;
8. records `reality.entity_supersessions`;
9. retires — but does not delete — the superseded `reality.entities` row;
10. marks the reconciliation case confirmed with an impact snapshot and execution receipt.

No partially completed merge is allowed.

## Reference-rewrite rule

Confirmed equivalence means the two Entity IDs were alternate identities of the same real-world thing. Current direct Reality foreign-key references therefore move to the surviving canonical ID.

The reconciliation case and supersession record are deliberately excluded from that rewrite so the identity history itself remains immutable and intelligible.

Compatibility bindings are not foreign-keyed to Reality by design, so they are rewritten explicitly.

## Fail-closed constraints

A v1 reconciliation refuses or atomically aborts when:

- either candidate is no longer canonical;
- entity kinds differ;
- either candidate is already superseded;
- a direct relationship between the two candidates would become a self-edge;
- any composite foreign key to `reality.entities` exists that v1 cannot safely rewrite;
- a dependent unique/check/FK constraint cannot accept the reference transfer.

Atlas must resolve the conflicting dependent truth before retrying. The merge executor does not invent conflict policy for unrelated domains.

## Workbench semantics

The Implementation Workbench should render this as a governed sentence, not a raw database operation:

```text
These two Reality identities refer to one real-world entity.
Keep: [survivor]
Supersede: [duplicate]
Because: [basis]
```

The next screen is the impact preview.

Only after that preview may the operator perform the separate confirmation act.

This is the same constitutional pattern as the wider Workbench:

```text
information
→ typed proposal
→ consequence preview
→ explicit responsibility
→ confirmation
→ durable truth
```

## Acceptance criteria

1. Evidence may propose but cannot execute a canonical Reality merge.
2. Identity-review authority does not imply canonical-merge authority.
3. Proposal, preview, and execute are separate operations.
4. Both candidates must be canonical Reality entities of the same kind.
5. Preview exposes direct Reality reference impact and known blockers.
6. Confirmation recomputes impact under row locks.
7. Reference transfer is atomic.
8. A dependent constraint failure rolls the entire merge back.
9. Compatibility routing moves to the survivor.
10. The superseded Reality row is retained, not deleted.
11. Durable supersession history resolves the old ID to the survivor.
12. Raw reconciliation tables are not mutation surfaces for authenticated or service roles.
13. No Shared Intelligence table becomes Atlas-wide canonical identity authority.
