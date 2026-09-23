# Atlas Notebook Exposure Admission v1

**Status:** candidate architecture only  
**Date:** 2026-09-23  
**Depends on:** canonical Person Position + canonical Domain Exposure Evaluator v1  
**Production effect:** none until a separately authorized generated migration is validated and released.

## Purpose

Extend the shared Domain Exposure artery into the read side of Notebook admission.

The missing distinction is:

```text
durable carrier exists
!= ordinary Index may advertise it
!= direct NotebookAddress may resolve it
!= source truth may be read
```

This candidate creates no notebook places, source bindings, Index rows, Today placement, action authority, or source truth.

## Canonical artery

```text
canonical domain truth
→ Person Position
→ Domain Exposure Evaluation
→ Notebook read admission
   → ordinary Index admission
   → direct NotebookAddress admission
→ later carrier/source-binding reconciliation
→ source projection
→ Notebook Composition
```

Attention, Clock, Today, Shared Composition, Intake/Interpretation, Classification, Reality Sentence authoring, and Knowledge Acquisition remain outside this candidate.

## Knowledge-Jurisdiction slice

This is the first concrete notebook-facing slice of Atlas Knowledge-Jurisdiction Security.

It is intentionally narrower than a universal permission engine.

The candidate answers only:

- whether ordinary Index may advertise an already-existing durable notebook place;
- whether a caller may resolve one exact durable NotebookAddress;
- which governed source read must still separately authorize source content.

It does not answer whether the Person may perform an operation against the source object.

## Listed / quiet / absent / unresolved

For a durable place:

- `listed`: direct address resolves and ordinary Index may advertise it;
- `quiet`: direct address resolves but ordinary Index does not advertise it;
- `absent`: the NotebookAddress is not exposed to this Person;
- `unresolved`: exposure warrant is insufficient; encounter fails closed.

An admitted place using `absent` is invalid. `quiet` is the direct-only state.

## Candidate reads

### atlas.notebook_index_admitted_self_api_v1()

Returns only system addresses plus durable places whose current Domain Exposure Evaluation is:

```text
encounter = eligible
place = stable | transient
index = listed
sourceBinding.governedRead present
```

Quiet, absent, unresolved, unmapped, or invalid carriers are not returned.

The API does not enumerate hidden carriers in diagnostic buckets.

### atlas.notebook_address_admitted_self_api_v1(spread_key)

Resolves one exact durable address only when the matching Domain Exposure Evaluation is:

```text
encounter = eligible
place = stable | transient
index = listed | quiet
sourceBinding.governedRead present
```

Otherwise it returns the same not-found error used for a nonexistent address so an absent carrier is not disclosed merely because its key is guessed or retained.

The admitted resolver returns the durable spread descriptor and the name of the governed source read. It does not execute or grant that source read.

## Transitional raw-reader boundary

Current `atlas.notebook_spread_instance_self_api_v1(spread_key)` is still callable by authenticated clients and resolves by Principal-owned carrier existence.

That is a transitional bypass path.

This candidate does **not** revoke it because the Atlas application has not yet cut over to the admitted resolver.

Retirement sequence:

```text
Person Position canonical
→ Domain Exposure evaluator canonical
→ admitted Index/address reads canonical
→ Atlas application consumes admitted reads
→ human + negative proof
→ retire/internalize raw direct spread reader
```

Do not revoke the raw reader earlier.

## No mutation

Both candidate reads are stable/read-only.

They perform no durable `INSERT`, `UPDATE`, or `DELETE`.

They do not call ensure/open/close/bind/retire notebook mutation functions.

## Source authority boundary

Notebook admission can name the source membrane required to populate the page.

It never means that source read will succeed.

Lawful populated encounter remains:

```text
NotebookAddress admitted
+ source-owned read authorizes caller
= source truth may populate the encounter
```

## Required proof

Clone validation must prove at minimum:

1. active Person Life is listed and directly resolvable;
2. Connections is listed and directly resolvable for an active Principal;
3. current owner-compatible Organization Ledger is listed and directly resolvable;
4. a durable historical Ledger carrier remaining after downgrade to ordinary membership is neither listed nor directly resolvable;
5. a direct request for that hidden carrier is indistinguishable from not-found;
6. the admitted reads perform no durable mutation;
7. the admitted reads consume Domain Exposure rather than re-deriving Organization membership, Person identity, Ledger authority, or Life ownership from raw domain tables;
8. source read authority remains separate;
9. quiet semantics are encoded as direct-resolvable but non-listed even if no current production domain uses quiet yet.

## Dependency boundary

The source candidate may be reviewed while upstream dependencies remain unreleased.

Do not generate or production-clone-validate this candidate until:

1. Person Position is canonical in the receiving schema; and
2. Domain Exposure Evaluator v1 is canonical in the receiving schema.

Do not route around either dependency by copying their logic into this candidate.

Passing future clone validation still will not authorize production release.
