# Atlas Development Cross-Domain Qualification Audit v1

**Status:** Architecture qualification record  
**Date:** 2026-09-22  
**Compared proofs:** CI Washers; Elm Flower Preparation / Bunching  
**Decision scope:** Whether Development has earned a native Atlas domain contract and what may be implemented next.

## 1. Comparison

| Mechanic | CI Washers | Elm Flower Preparation | Shared? |
|---|---|---|---|
| Exact target subject | CI Activity | production procedure/practice | yes |
| Exact Development Standard Version | CI Activity Development Standard | Elm Procedure Development Standard | yes |
| Durable Case | develop Washers | develop preparation procedure | yes |
| Criterion identity | construction, teaching, cost, etc. | quantity, quality, handling, etc. | yes |
| Reusable inherited rule | CI/family standard | Operating Knowledge default/exception | yes |
| Evidence before decision | field tests, source docs, prototypes | timings, rejects, operating evidence | yes |
| Work separated from decision | price/build/test | measure/observe/test | yes |
| Human authority separated from research | methodology/design decision | owner operating-standard decision | yes |
| Explicit unresolved/conflict state | yes | yes | yes |
| Gate/maturity recomputation | Buildable/Portable/etc. | Delegable/etc. | yes |
| Released output owned by target domain | CI Activity Version | procedure/Operating Knowledge version | yes |
| Historical release immutable | required | required | yes |

## 2. What has qualified

The comparison supports a native Atlas **Development domain contract** with these four universal semantic roots:

1. Development Standard Version
2. Development Case
3. Development Criterion Resolution
4. Development Release

The comparison also supports the following reusable platform integrations:

- Claims/Evidence;
- Company Work;
- Company Operating Knowledge;
- institutional Communication;
- Reality Sentence / manual authoring;
- Reality Transition Receipt;
- Reality Continuation;
- Reality Reconciliation;
- authority-required Decision Requirements;
- future Semantic Interaction Runtime.

## 3. What has not qualified

The comparison does **not** justify:

- one universal finished-specification table;
- one universal Resource model;
- one universal Knowledge model;
- one universal qualification system inside Development;
- a generic workflow engine;
- an EAV criterion-answer blob;
- hard-coded CI maturity names;
- hard-coded Elm procedure gates;
- automatic conversion of Work Result into Criterion resolution;
- automatic conversion of evidence into release.

## 4. Field-by-field comparison

### Standard Version custody

Both domains require one institution to define what “sufficiently developed” means.

Shared.

### Standard criterion definition

Both require stable criterion keys, questions/rationale, applicability, dependencies and gate membership.

Shared.

### Release gate names

Different.

Therefore gate identity is standard-owned data, not platform enum.

### Case target

Different domain/kind/ref.

Shared address grammar, different owning domain.

### Criterion resolution kind

Both require:

- established;
- inherited;
- local/not-applicable where appropriate;
- needs evidence;
- unresolved;
- deferred;
- conflicted.

Shared enough for candidate normalization, but exact transition permissions still require executable proof.

### Evidence mechanics

Both consume source/field evidence.

Shared platform Claims/Evidence.

### Work mechanics

Both can create Work Requirements and Company Work.

Shared platform Company Work.

### Decision authority

Authority differs by institution and decision class.

Therefore Development must name requirements but never own a universal “approver role.”

### Inheritance

Both benefit from institution/family reusable rules.

Shared through Company Operating Knowledge or other owning rule domain.

### Gate evaluation

Both require deterministic read-time evaluation from exact Criterion positions.

Shared architecture.

### Release output

Different target domain.

Development Release therefore references output; it does not own output semantics.

## 5. Qualification conclusion

The two proofs are sufficiently different to support Development as a **native Atlas domain architecture**.

They are not yet two executable Development implementations.

Therefore the safe next step is:

> build the smallest executable Development candidate in a candidate/validation lane, proving the four contracts with no generic workflow engine and no CI-specific schema.

Do not release directly to production from this audit.

## 6. Smallest executable candidate

The first candidate should implement only:

- Development Standard Version identity;
- criterion definitions;
- release-gate definitions;
- Development Case;
- Criterion Resolution history/current projection;
- read-only gate evaluation;
- Development Release accounting;
- organization/ledger custody;
- references to external basis/evidence/work by typed address.

It should **not** yet implement:

- automatic Work creation;
- artifact ingestion;
- attention ranking;
- communications;
- Decision Requirement orchestration;
- AI extraction;
- Qualification;
- Packages;
- money/fundraising;
- physical-resource lifecycle.

Those integrations should be added only after the core can prove its own truth boundaries.

## 7. First executable fixtures

The candidate should include two fixtures.

### CI fixture

A synthetic Washers subject address with a tiny Standard:

```text
criterion: player capacity
criterion: construction specification
criterion: current cost

gate: Playable
  requires player capacity

gate: Buildable
  requires construction specification

gate: Fundable
  requires current cost
```

Prove:

- player capacity resolved;
- construction unresolved;
- cost needs evidence;
- Playable satisfied;
- Buildable blocked;
- Fundable blocked.

Then establish construction resolution and prove only Buildable changes.

### Elm fixture

A synthetic flower-preparation subject address with a tiny Standard:

```text
criterion: default bunch quantity
criterion: quality acceptance

gate: Delegable
  requires both
```

Prove:

- default quantity resolves by inherited Operating Knowledge ref;
- quality remains unresolved;
- Delegable blocked;
- resolving quality causes gate to satisfy.

## 8. Candidate invariants

At minimum:

1. Standard Versions used by Cases cannot be semantically rewritten.
2. Criterion keys are unique inside a Standard Version.
3. Gates can reference only criteria from their own Standard Version.
4. A Case binds exactly one Standard Version and one target address.
5. A Criterion Resolution cannot name a criterion outside the Case Standard.
6. Resolution history is append-only.
7. Current position is derived or transactionally projected from history.
8. A Release may name only gates currently satisfied for that Case.
9. Release points to a nonblank target-domain version/ref.
10. Release is append-only.
11. No browser gets direct table mutation authority.
12. No generic dynamic command dispatch exists.
13. No Work, Evidence, Operating Knowledge, or target-domain truth is copied into Development merely for convenience.

## 9. Release criterion for the Development kernel

The Development candidate earns promotion only if disposable production-schema validation proves:

- both fixtures;
- immutable Standard semantics;
- resolution history;
- inherited-basis address preservation;
- blocker/gate recomputation;
- release refusal when gate blocked;
- release success when exact gates satisfied;
- no cross-Organization references;
- idempotent/replay-safe establishment commands where applicable;
- browser authority closed except through bounded APIs;
- no dependency on CI-only or farm-only tables in the universal kernel.

## 10. Next action

Create the candidate SQL/fixtures/validation from current production `main` on a private architecture/candidate branch.

Keep it out of the release lane until the two-fixture proof passes.
