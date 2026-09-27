# Atlas Foundry → Atlas Admission Bridge v1

Status: governing implementation architecture  
Date: 2026-09-27

## Purpose

Atlas Ledger Foundry now defines a durable pre-Atlas truth-making process:

```text
evidence
→ testimony
→ candidate structure
→ clarification
→ reconciliation
→ closure
→ acceptance
→ sealed Ledger candidate
```

A sealed Foundry candidate is not canonical Atlas Reality and is not an active Atlas Ledger.

The admission bridge is the authority boundary between those worlds.

```text
Foundry reconciles what the candidate says
Atlas decides what canonical Reality already exists
Atlas decides how the candidate maps into governed structures
practitioner onboarding decides whether a Ledger may activate
```

No carrier, Foundry service, sealed package, AI recommendation, or structurally valid import may skip that sequence.

## Constitutional boundary

Foundry is upstream of Atlas canonical truth.

`Foundry ESTABLISHED` means established inside the Foundry workspace under the Foundry protocol. It does not mean `reality.entities`, `reality.entity_relationships`, `reality.responsibility_relations`, `ledger.ledgers`, or any other Atlas canonical/operational row already exists.

Therefore:

```text
Foundry establishment != Atlas admission
Foundry seal != Ledger activation
Foundry identity merge disposition != Reality merge execution
Foundry topology decision != active Ledger creation
package validity != admission authority
```

## v1 sequence

The v1 bridge implements:

```text
sealed Foundry exchange package
→ immutable Atlas staging receipt
→ governed Atlas admission case
→ identity collision / continuity review
→ Ledger topology review against Reality Atlas already knows
→ explicit admission plan
→ human-authorized handoff
→ canonical subject Entity admitted or bound
→ practitioner onboarding case opened
→ sealed Foundry baseline remains attached as pending onboarding material
```

v1 stops there.

It does **not** activate a Ledger and it does **not** bulk-promote the sealed Foundry assertions into canonical Atlas structures.

That stopping point is intentional. Atlas does not yet have one generic canonical table that faithfully represents every Foundry Entity, Relation, Event, state/configuration, constraint, authority, commitment, evidence claim, and dependency edge. A fake universal importer would destroy distinctions Foundry exists to preserve.

## Immutable package receipt

Atlas stages the complete sealed exchange package before interpreting it.

The staged record preserves:

- Foundry package ID;
- workspace ID;
- Ledger candidate ID;
- Foundry protocol version;
- exchange version;
- release version;
- subject name;
- field description;
- seal time;
- optional integrity hash supplied by the carrier/service;
- complete package payload;
- source/transport metadata that is explicitly not human testimony.

Once staged, the package identity and payload are immutable.

A retry of the same package ID with the same payload is idempotent. Reuse of a package ID for different content is rejected.

## Version boundary

Bridge v1 accepts only Foundry protocol `0.1` and Ledger Exchange `0.1`.

Future Foundry versions require an explicit compatibility path. Atlas must never silently reinterpret an older sealed package under newer semantics.

## Identity decision

Before creating any new Reality Entity, Atlas must decide whether the Foundry subject:

1. is an already-existing canonical Reality Entity; or
2. requires a new canonical Reality Entity.

The operator must explicitly choose one.

For `use_existing_entity`, the selected Entity must already be canonical.

For `create_entity`, the admission plan must provide explicit:

- Reality stable key;
- Entity kind;
- display name;
- identity-collision basis when Atlas finds an exact same-kind/same-name candidate.

A stable-key collision is always blocking.

An exact name/kind match does not prove identity, but it requires explicit review rather than silent duplication.

Atlas's database preview is deliberately not represented as omniscient identity resolution. Broader evidence from Foundry, Shared Intelligence, or a human reviewer may be needed.

## Existing Reality identity conflict

When Foundry work establishes that **two identities already admitted into Reality** are one real-world entity, the bridge does not merge them itself.

Foundry receives first-class proposal provenance:

```text
Foundry case
→ IDENTITY_MERGE disposition
→ structural delta / basis
→ Reality reconciliation proposal
→ Reality impact preview
→ separate canonical_merge.execute authority
```

Foundry may justify and propose the merge.

Foundry may not execute the canonical Reality merge.

The existing Reality reconciliation membrane remains the only canonical merge executor.

## Ledger topology review

Binding a Foundry subject to an existing Reality Entity may reveal existing active Ledgers.

That does not automatically block a new Ledger: one Entity may express more than one genuinely separate operational field.

But an existing Ledger means the admission plan must state why the sealed Foundry candidate represents a distinct Ledger boundary rather than duplicate truth.

Thus:

```text
existing Ledger != automatic rejection
existing Ledger + no boundary basis = blocked handoff
```

## Handoff, not activation

A successful v1 admission handoff may:

- bind the Foundry candidate to an existing canonical Reality Entity; or
- create one new canonical Reality Entity under explicit admission authority;
- create a normal `ledger.onboarding_cases` row with `case_kind=practitioner_onboarding` and `onboarding_state=requested`;
- attach the immutable Foundry package/admission provenance to the onboarding basis.

It may not:

- insert `ledger.ledgers`;
- mark onboarding `ready_to_activate`;
- invent a practitioner;
- create Seats;
- promote Foundry assertions as canonical simply because the package is sealed;
- bypass any claim, practitioner, authority, or activation rules that later onboarding requires.

The Entity may exist in Reality even if Ledger onboarding later does not activate. Reality does not depend on Atlas participation.

## Baseline import is deliberately pending

The sealed package contains more than identity and Ledger boundary. It may contain:

- entities;
- relations;
- events;
- current position;
- standing law;
- authority/responsibility;
- commitments;
- unknowns;
- closure;
- topology decisions;
- acceptance results;
- adjudication history.

v1 preserves all of it, but does not flatten it into whichever Atlas tables happen to exist today.

The practitioner/onboarding side can later use a governed mapper that classifies each Foundry record into an exact destination operation, for example:

```text
Reality Entity admission
Reality relationship
Reality responsibility
Ledger standing law
Ledger current state/configuration
Ledger event/action
Ledger observation/evidence
external related reality
known unknown / unresolved
no canonical promotion
```

That mapper must use operations, not generic CRUD.

## Workbench consequence

The Implementation Workbench should not be a universal database writer.

Its universal sentence-building surface should classify intent into one of three high-level paths:

```text
DISCOVER
  evidence/testimony/candidate understanding
  → Foundry

ESTABLISH
  governed admission/correction of canonical truth
  → Atlas admission / Reality reconciliation membranes

ACT
  governed operation over already-canonical reality
  → existing domain command
```

A sentence is therefore an intent carrier. The destination membrane determines what authority and confirmation are required.

## Authority

Admission authority is explicit and separate from:

- Foundry carrier capability;
- Foundry principal ownership;
- Reality identity-review authority;
- Reality canonical-merge authority;
- Ledger Seat participation;
- legacy Organization role;
- Principal compatibility state.

The v1 responsibility is `foundry_admission_governance` in domain `atlas.foundry_admission` with bounded operations:

- `foundry_admission.read`;
- `foundry_admission.plan`;
- `foundry_admission.execute`.

A service role may stage a sealed package. It may not perform the human admission handoff.

## Foundry as first-class Reality reconciliation provenance

Reality reconciliation proposal source kinds include `foundry`.

The dedicated Foundry proposal service requires structured provenance identifying the Foundry workspace, adjudication case, disposition, and `IDENTITY_MERGE` reason code.

That proposal endpoint remains service-callable but confirmation remains authenticated-human-only through `canonical_merge.execute`.

## Acceptance criteria

Bridge v1 is valid only when:

1. a sealed Foundry package can be staged without creating Reality or a Ledger;
2. staged package content is immutable;
3. only supported protocol/exchange versions are accepted;
4. a package with blocking unknown count greater than zero is refused;
5. subject identity disposition is explicit;
6. stable-key collision blocks new Entity creation;
7. exact name/kind candidates are surfaced for explicit collision review;
8. existing active Ledgers are surfaced before opening another onboarding case;
9. an existing-Ledger boundary requires explicit separation basis;
10. successful handoff creates or binds exactly one canonical subject Entity;
11. successful handoff opens a practitioner onboarding case in `requested` state;
12. successful handoff does not create `ledger.ledgers`;
13. sealed baseline import remains pending rather than partially promoted;
14. Foundry identity-merge evidence can open a Reality reconciliation proposal;
15. Foundry/service authority cannot execute canonical Reality reconciliation;
16. the bridge exposes no generic SQL/CRUD route;
17. all decisions retain Foundry package/workspace/release provenance.
