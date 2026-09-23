# Atlas Implementation Reality Responsibility Promotion v1

## Purpose

Graduate the structural family after Position:

`Organization has Responsibility`

The canonical owner is `atlas.organization_responsibilities`. Responsibilities are reusable institutional duties owned by the Organization. They are distinct from Positions, Position↔Responsibility assignment, responsibility scopes, appointments, Initial Scope, and Findings.

## Reality Sentence grammar

Operation: `organization_responsibility.establish`

Bindings:
- subject = proposed `organization_responsibility`;
- object = canonical `organization`;
- context = null.

Semantic payload:
- required `responsibilityKind` = nonblank string.

The existing Organization object binding is constitutionally correct because the canonical Responsibility table is Organization-scoped. Unit/domain scope belongs to separate responsibility-scope truth and must not be smuggled into Responsibility establishment.

`stable_key` remains an owning-domain implementation identifier.

## Human rendering

`Organization has Responsibility Responsibility Name (responsibilityKind).`

Canonical rerender is derived from canonical Responsibility custody.

## Authority

Readiness requires an open Implementation Case, assigned practitioner, active root Ledger binding for the canonical Organization, active Organization participation, and a verified setup sponsor whose canonical Principal governs that Ledger.

## Identity

For v1, normalized responsibility name inside one Organization is the semantic identity boundary:
- same name + same kind + active = existing canonical identity;
- same name with conflicting kind/status = canonical conflict.

## Preview boundary

The preview is read-only. It may validate candidate grammar, semantic payload, authority/scope, and duplicate identity; rerender already-promoted canonical truth; and dynamically report future command availability.

It may not mutate Responsibility truth, candidate state, Position↔Responsibility links, responsibility scopes, appointments, Initial Scope, or Findings.

## Mutation tranche

After preview release, the owning-domain command will expose a PostgREST-safe `public.promote_implementation_reality_responsibility_self_api_v1(uuid)`, re-run preview, generate an internal stable key, establish/reuse lawful canonical Responsibility truth, record a receipt, and canonical-rerender.

## Sequence

`Organization Unit → Position → Responsibility → Position↔Responsibility → Person↔Position appointment`

## Private Atlas Actions boundary

This tranche uses public `noel-core-db` custody/release infrastructure only. Private `optical-lift/atlas` Actions remain untouched until their quota returns.
