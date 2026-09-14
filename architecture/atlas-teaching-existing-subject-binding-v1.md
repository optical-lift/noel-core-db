# Atlas Teaching Existing Subject Binding v1

**Status:** Gate A.1 implementation contract  
**Date:** 2026-09-13  
**Base:** `noel-core-db` main after Teaching Academic Kernel v1  
**Capability:** `teaching` v1

## Purpose

This tranche makes the first literal **Teach this** relationship truthful.

Before this change, Teaching v1 could activate only on a Ledger. Gate B could therefore create Courses, but a Course could not preserve which existing Atlas subject caused a user to choose **Teach this**.

Gate A.1 adds one proven existing subject kind without inventing a universal subject registry or a Titus-only source table:

```text
Organization Ledger Entry
  -> Teaching v1 capability activation
      -> Course
```

The Course preserves the source through its existing `capability_activation_id`. The source subject itself is not copied or converted.

## First proven subject kind

The first non-Ledger subject kind is:

```text
organization_ledger_entry
```

Its canonical identity is `atlas.organization_ledger_entries.id`.

This subject is acceptable because an Organization Ledger entry has:

- a durable UUID identity;
- an explicit `ledger_id`;
- established Atlas custody rather than presentation-only identity;
- existing truth semantics independent of Titus.

The following candidates remain rejected:

- `notebook_spread_instances`: projection/runtime identity and Principal-scoped;
- `organization_ledger_subjects`: a relation from one Ledger entry to another subject, so its row ID would make Teaching depend on an arbitrary event linkage.

## Ledger boundary

Teaching v1 requires:

```text
capability_activations.ledger_id
=
capability_activations.subject_ledger_id
```

for both Ledger-root and `organization_ledger_entry` subjects.

This restriction is Teaching-specific in v1. Gate A keeps `ledger_id` and `subject_ledger_id` distinct so future capabilities are not prematurely constrained.

A subject governed by a different Ledger is not attached directly. Cross-Ledger source reality must first be represented through the Ledger correlation contract rather than by copying the source or bypassing Ledger authority.

## Capability validation

`capability_subject_valid_v1` recognizes two Teaching v1 subject kinds:

1. `ledger`
2. `organization_ledger_entry`

For `organization_ledger_entry`, validation requires:

- non-null subject Ledger;
- non-null UUID subject ID;
- no subject key/path;
- an existing Organization Ledger entry with exactly that `id`;
- that entry's `ledger_id` equals `subject_ledger_id`;
- an active subject Ledger.

`capability_subject_governed_v1` is the new governance-aware validator. It first requires intrinsic subject validity, then enforces Teaching v1's same-Ledger governing boundary.

Creation and non-retiring activation transitions use the governance-aware validator. Historical retirement remains possible even if active behavior is no longer valid.

## Course source preservation

Existing `create_teaching_course_self_api_v1(ledger_id, course_key, name)` remains unchanged in meaning: it creates a Ledger-root Course from an active Ledger-root Teaching activation.

Gate A.1 adds:

```text
create_teaching_course_from_activation_self_api_v1(
  capability_activation_id,
  course_key,
  name
)
```

This API:

- resolves the exact activation first;
- requires root governing authority over that activation's Ledger;
- requires the activation to be active Teaching v1;
- creates the Course using that exact `capability_activation_id`;
- returns the source subject Ledger/kind/ID for the caller;
- is idempotent only when the same Course key, name, and exact activation already agree;
- refuses to silently rebind an existing Course key to another Teaching source.

The existing `teaching_courses_activation_guard_v1` is generalized from Ledger-root-only Teaching to any valid, same-Ledger Teaching v1 subject. The insert path still requires an active Teaching activation.

## Explicit non-goals

This tranche does not add:

- a universal Atlas subject registry;
- a Titus-local source table;
- arbitrary notebook-spread activation;
- direct cross-Ledger Teaching;
- Course material custody;
- assignments, submissions, grading, credentials, tuition, calendar, or Clock integration;
- delegated faculty authority.

## Compatibility

Production contained no capability activation rows at audit time, so the Teaching same-Ledger rule does not reinterpret existing activation history.

Ledger-root Teaching remains supported. The original Ledger-root Course-create API remains supported.

## Next runtime step

Once this contract is merged and released, the Atlas frontend may implement the first truthful vertical:

```text
existing Organization Ledger entry
-> Teach this
-> create draft Teaching activation
-> activate
-> create Course from that exact activation
-> continue through the existing Gate B Course Version / Offering / Enrollment path
```

The UI must not infer or duplicate source identity; it must carry the returned capability activation ID.
