# Atlas Ledger Aperture — Visibility Independence Decision v1

**Status:** Binding architecture decision for the Ledger Aperture v1 candidate
**Date:** 2026-09-14
**Executable scope:** None

## Decision

Visibility and responsibility are completely independent dimensions of a person's effective Ledger aperture.

> **Responsibility never creates visibility.**

This includes visibility to the responsible subject itself.

Atlas may truthfully hold all of the following states:

```text
responsibility = present
visibility = absent
```

That state is not automatically contradictory, corrupt, or incomplete. It means only that institutional responsibility has been situated with the Person while no governed visibility contract currently admits the Person to know that responsibility or its subject through the queried surface/context.

Atlas must not repair that state by inference.

## Consequences

### 1. No responsibility visibility floor

An active `responsible` Company Work allocation does not, by itself, permit the responsible Person to know:

- that the Work exists;
- its title;
- its status;
- its date;
- its instructions;
- its subject;
- its surrounding context;
- related Work;
- downstream or upstream consequences.

Any such exposure requires independently admissible visibility evidence.

The same rule applies to standing responsibility from positions/responsibility scopes. Standing responsibility does not itself grant read visibility to the governed scope.

### 2. Responsibility may be hidden from the responsible Person

The aperture resolver must preserve responsibility evidence even when the same Person has no visibility evidence for that subject.

A caller asking for institutional responsibility may therefore learn that responsibility exists when the caller's own aperture permits that observation, while the responsible Person's own delivery surface may receive nothing.

The responsible Person's lack of visibility does not erase, release, or reinterpret the responsibility.

### 3. Delivery requires visibility independently

A Work Brief or other Person-facing execution surface may expose Company Work only when all requirements of that surface are independently satisfied.

Conceptually:

```text
responsibility
  + visibility admission
  + delivery capability
  + surface-specific readiness/eligibility
  -> work may be delivered
```

No term substitutes for another.

In particular:

- responsibility without visibility is not delivered;
- visibility without responsibility may permit observation but not imply custody;
- delivery entitlement without visibility exposes nothing;
- delivery entitlement without responsibility does not manufacture responsibility.

### 4. Necessary execution context is separate visibility truth

Atlas must not derive context visibility merely because execution would be difficult or impossible without it.

If a responsibility-bearing Person needs method, location, materials, readiness, neighboring state, or other information to execute correctly, that context must be admitted through a separate governed visibility contract or policy.

Responsibility may be referenced when evaluating whether a visibility rule applies, but responsibility is not itself the visibility source.

The difference is material:

```text
BAD
responsible for X
  -> therefore may see X and necessary context

GOVERNED
responsible for X
explicit visibility policy/grant independently admits Y
  -> may see Y
```

### 5. Resolver output must not collapse the dimensions

`resolve_effective_ledger_aperture(Person, Ledger, Context)` must be capable of returning responsibility evidence for subjects that are absent from that Person's visibility result.

The resolver must not trim the canonical responsibility dimension merely to make a Person-facing UI easier to render.

Instead, surfaces consume the dimensions according to their own purpose. A Work Brief takes the visible/deliverable intersection. A broader responsibility-scaffolding projection may expose hidden responsibility to another Person only when that other Person independently has visibility to it.

### 6. No automatic visibility transaction on responsibility mutation

Creating, moving, or ending responsibility must not silently create, broaden, or revoke visibility unless an explicit governed mutation contract separately performs that visibility change and records its basis.

Responsibility mutation and visibility mutation are semantically different institutional acts even when a product workflow eventually performs both together.

### 7. No contradiction auto-healing

If Atlas detects responsibility for a Person who cannot currently see the responsible subject, it must not:

- create an exposure grant;
- broaden an information class;
- reinterpret a seat or credential as visibility;
- release the responsibility;
- copy the Work into a different visibility container;
- infer visibility from position/title/role;
- disclose the Work merely because it appears on a plan.

Any future warning, adjudication cue, or setup workflow for that condition must be a separate product decision.

## Supersession within Ledger Aperture v1

This decision governs any ambiguous wording in `atlas-ledger-aperture-v1.md` that could be read as establishing a minimum visibility floor from responsibility.

In particular:

- “necessary context” must mean independently admitted visibility, not visibility derived from responsibility;
- a narrow execution surface shows entrusted Work only when visibility independently admits it;
- a Work Brief is the deliverable intersection of responsibility, visibility, delivery capability, and surface-specific rules, not a direct projection of responsibility alone;
- responsibility evidence remains canonical even when omitted from the responsible Person's own visible projection.

No schema, grant, RPC, policy, or production behavior is created or changed by this decision record.
