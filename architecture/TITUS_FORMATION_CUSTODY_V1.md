# Titus Formation Custody v1

**Status:** Governing database architecture for the first formation slice  
**Established:** October 3, 2026  
**Physical project:** `noel-core`  
**Logical schema:** `titus`

## 1. Purpose

This document explicitly adjudicates the inherited `titus` schema for post-fence use by the Titus Formation Workspace.

The `titus` schema remains the canonical person-specific formation/curriculum custody layer. It may reference reusable Noel/Song truth structures through explicit governed links, but Marlene-specific claims, patterns, responses, formation state, and matured articulations remain in Titus rather than being mirrored into Noel.

The governing formation artery is:

```text
teacher/source evidence
→ historical claim / teacher-native pattern
→ independent canon claim / structure
→ Song/function placement
→ worldview↔canon adjudication
→ Formation Unit
→ learner encounter
→ teach-back
→ transfer proof
→ matured articulation
→ downstream teaching projection
```

## 2. Authority boundaries

### Canon truth

Owned by reviewed canon claims, evidence, truth refs, and canon structures already carried in Titus/Noel research architecture.

### Reusable Song/Noel function truth

Owned by the reusable Noel/Song layer. Titus may reference it; person-specific formation state must not be promoted into Noel merely to simplify UI joins.

### Historical Marlene worldview

Owned by existing Titus teacher-source, teacher-term, and teacher-pattern objects.

### Adjudication

Existing source adjudications and teacher-pattern↔canon links remain the primary adjudication carriers where they are semantically sufficient.

Do not create a second generic worldview-claim or worldview-function store merely to support the Formation Workspace.

### Formation state

New formation-specific objects belong in `titus`:

- Formation Unit;
- Formation Unit inputs/dependencies;
- Formation Unit sections;
- integration/research questions;
- learner response / teach-back artifacts;
- transfer cases and attempts;
- matured articulations.

### Product

`optical-lift/titus` owns application composition over governed reads/writes. It does not own canonical formation state.

## 3. Reuse decisions for the first vertical slice

The first proof is Session 11 / **“He who defines controls.”**

Reuse existing nouns:

- `titus.teacher_source_units` for historical source claims;
- `titus.teacher_source_adjudications` for source-specific correction/disposition;
- `titus.teacher_source_adjudication_targets` for precise canon/function targets;
- `titus.teacher_patterns` for recurring neutral/functional teacher architecture;
- `titus.teacher_pattern_claim_links` for recurring pattern↔canon adjudication;
- `titus.teacher_term_senses` and target links where vocabulary-sense work is material;
- `titus.canon_claims` and evidence;
- `titus.canon_structures`;
- `titus.truth_refs`;
- lesson/session identity and existing links.

Do **not** add in v1:

- generic `worldview_claims`;
- generic `worldview_functions`;
- a second generic worldview↔canon adjudication table;
- a universal graph table;
- a universal workflow engine.

The existing source/pattern/canon architecture already carries those distinctions for the current learner.

## 4. New formation nouns

### Formation Unit

One bounded learner-facing reconstruction governed by existing historical, functional, canon, and Song/adjudication inputs.

A Formation Unit is not a lesson drawer and not a canon claim. It is the formation object that teaches the relationship among those existing truths.

### Formation Unit Input

A typed dependency from a Formation Unit to one existing governed object.

Inputs make dependency/staleness inspectable without copying upstream truth into the unit.

### Formation Unit Section

Learner-facing connective teaching assembled around the governed inputs.

Sections are versioned content carriers inside the Formation Unit; they do not become the source of canon truth.

### Formation Question

A durable research/integration/challenge question that may remain open across multiple research passes.

### Formation Response

A raw learner-authored response or teach-back artifact. Model/analyst interpretation of that response must remain separate from the raw response itself.

### Transfer Case / Attempt

A novel case and the learner's response used to test whether the architecture transfers beyond rehearsed examples.

### Formation Articulation

A versioned matured articulation after formation. It does not overwrite the historical worldview or raw teach-back.

## 5. Phase-fit and review

Formation lifecycle and review fitness remain distinct.

A unit can have lifecycle state `integrated` historically while its current review state becomes `needs_review` after an upstream canon/adjudication change.

The v1 schema therefore carries both:

- `formation_state`;
- `review_state`.

Potential staleness is derived from explicit input dependency plus upstream `updated_at` versus the input's `reviewed_at`. The first implementation should avoid a broad trigger engine. A governed health view may expose potential staleness for human review.

## 6. Security

New formation tables are private by default.

For v1:

- enable RLS;
- grant no direct privileges to `anon` or `authenticated`;
- permit `service_role` as the server-side application transport;
- create no permissive end-user policies until the Marlene/private-workspace identity and authorization relation is explicitly designed.

This preserves the distinction:

```text
service-role technical capability
!= end-user authorization
```

Older inherited Titus tables with RLS disabled are not mass-remediated by this tranche. Their exposure/policy state requires a separate security review.

## 7. Application membrane

The first private product slice should consume a governed read projection over the Formation Unit rather than reconstructing its state from many raw tables in page code.

Mutation seams should be introduced only for operations the first slice actually needs.

Until viewer-aware end-user authorization exists, the Formation Workspace may be built/tested through server-side controlled paths but is not considered production-private proof merely because the service role can reach the data.

## 8. First seed

The migration may seed one Formation Unit using existing stable keys rather than generated IDs:

- Session: `m01-s11-language-redefinition-cultural-formation`
- Teacher: `marlene_mcmillan`
- Unit key: `definition_control_reconstruction`
- Title: `Definitions Can Steer Without Sovereign Control`

The unit should depend on the already-existing 2018 and 2023 definition-control source units, approved source adjudications, recurring teacher patterns, reviewed canon claims, and the primary Session 11 canon structures.

The seed must use subqueries by durable keys and fail if required governing objects are missing; do not hardcode environment-generated UUIDs.

## 9. Governing test

Before another formation table or generic engine is added, ask:

1. Is this a real durable formation noun, or a projection over existing nouns?
2. Which existing Titus/Noel identity can already carry the needed truth?
3. Would adding this create a second authority for historical claim, canon truth, Song function, or adjudication?
4. Does the first vertical slice actually require persistence here?
5. Can the carrier later be replaced without rewriting legitimate history?
6. What second session/person proof would justify horizontal promotion?

If the answer exposes duplicate authority or speculative universalization, the object does not enter the canonical schema yet.
