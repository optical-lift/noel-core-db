# Noel Physical Mark Evidence Kernel v1

## Purpose

Noel needs a physical evidence authority that can receive deliberate durable marks before those marks are forced into language, Unicode, conventional character boundaries, cultural categories, or scholarly interpretation.

The `mark` schema is that authority.

It is deliberately broader than `core.manuscript_registry`. A sign-bearing source object may be a manuscript leaf, tablet, bone, seal, stone, textile, tally, diagram, painted surface, knot system, pottery shard, or a future durable carrier that does not fit a manuscript/text model.

The kernel answers only physical questions:

- What physical object exists?
- What sign-bearing surface belongs to it?
- Which image/capture depicts that surface?
- Which pixels/region are being observed?
- Which candidate mark structures are present?
- Which physical components make up those structures?
- What touches, crosses, contains, aligns with, lies above/below, or otherwise relates to what?
- What physical order can be observed without assuming word or character boundaries?
- What is damaged, uncertain, duplicated, derived, or unavailable?

It does not answer what a mark means.

---

## Constitutional Boundary

The governing rule is:

> **Downstream analysis may reference physical source truth, but it may not rewrite physical source truth.**

A later Unicode identification does not change the observed pixels.

A scholarly reading does not change component geometry.

A recovery engine prediction does not turn a damaged component into an observed one.

A later theory does not erase an observed junction.

Once a physical record is frozen, it is immutable. Corrections are represented as new records with explicit `mark.record_supersessions` lineage.

`mark.record_supersessions` itself is append-only.

---

## Authority Chain

```text
SOURCE OBJECT
      ↓
PHYSICAL SURFACE
      ↓
CAPTURE
      ↓
CAPTURE ↔ SURFACE MAPPING
      ↓
REGION
      ↓
CANDIDATE MARK INSTANCE
      ↓
PHYSICAL COMPONENTS
      ↓
COMPONENT RELATIONS / JUNCTION GRAPH
      ↓
ANONYMOUS SEQUENCE ZONE + POSITION
```

The chain intentionally stops before functional or semantic interpretation.

---

## Tables

### `mark.source_objects`

Culture-agnostic physical objects.

The object registry stores custody/provenance information without requiring a language, canonical passage, script identity, or Unicode representation.

A source object may have a parent object so a leaf, fragment, shard, or component can remain attached to its larger physical object.

### `mark.surfaces`

Physical sign-bearing surfaces attached to source objects.

A surface is not a chapter, verse, word, character, or linguistic text unit.

### `mark.captures`

Image/capture custody.

A capture can remain a remote registered source or later point to governed object storage. It can store:

- dimensions,
- SHA-256,
- perceptual hash,
- source URI,
- derivative lineage,
- acquisition metadata,
- rights metadata.

`bytes_verified` requires a SHA-256 and dimensions.

### `mark.capture_surfaces`

Many-to-many capture-to-surface mapping.

This is necessary because one screenshot or photograph may contain more than one physical leaf/surface, and the same physical surface may appear in multiple captures.

Surface bounding geometry in the capture is retained here.

### `mark.capture_equivalences`

Duplicate and derivative adjudication.

This table exists to prevent one physical image from masquerading as independent recurrence evidence.

Supported v1 relations include:

- exact duplicate,
- viewer duplicate,
- same physical capture,
- derivative,
- non-equivalent control.

### `mark.regions`

Geometry-bearing physical regions in capture pixels.

A region may represent a row, zone, damage area, component area, candidate structure, margin, or another declared physical region.

Regions remain physical geometry; they do not inherit conventional character or word identity.

### `mark.instances`

Candidate physical mark units.

An instance is explicitly provisional. Modern or conventional character boundaries are not assumed.

Segmentation may be human supplied, imported, mechanically proposed, or later proposed by recurrence.

### `mark.components`

Observable pieces of candidate instances.

Every component belongs to a physical channel such as dark pigment, red pigment, orange/yellow pigment, incision, damage, or unresolved physical channel.

Channel is not meaning.

### `mark.component_relations`

The physical junction dictionary.

Relations are first-class observations such as:

- touches,
- crosses,
- overlaps,
- inside / contains,
- above / below,
- left / right,
- extends through,
- terminates on,
- adjacent to,
- aligned with,
- connected to.

This is the source substrate from which later operational candidates may be inferred.

Observation and inference remain separate.

### `mark.sequence_zones`

Physical ordered zones such as rows, columns, margins, bands, radial sequences, networks, or currently undetermined flows.

### `mark.sequence_members`

Anonymous candidate instance ordering inside sequence zones.

This provides sequence input without asserting word, syllable, verse, or character segmentation.

### `mark.record_supersessions`

Append-only correction lineage.

Frozen records are never edited into a new truth. A corrected physical observation receives a new record and explicit relation to the old one.

---

## Freeze Model

Physical evidence records have:

```text
record_status = draft | reviewed | frozen
frozen_at
```

The database enforces that a frozen physical row cannot be updated or deleted.

Corrections after freeze create new physical records.

This is intentionally different from interpretive systems where conclusions may be revised in place.

---

## Physical Observation Status

The physical layer preserves uncertainty rather than resolving it by inference.

Relevant v1 states include:

```text
observed_visible
observed_damaged
observed_uncertain
occluded
not_visible
```

A future Recovery Engine may predict what belongs in a damaged or hidden position, but the original observation status remains unchanged.

---

## Strict-Blind Interface

The `mark` schema does not itself decide which features a research engine may consume.

That belongs to Noel's existing `instrument` control plane.

The next governed release will register permitted physical features in `instrument.feature_registry` and explicitly prohibit conventional/semantic features in strict-blind runs.

Expected strict-blind inputs include:

```text
capture pixel identity
source coordinates
physical channel
component geometry
damage/uncertainty state
junction/topology relation
anonymous sequence position
capture duplicate/derivative relation
```

Expected prohibited discovery inputs include:

```text
Unicode identity
lexical/phonetic reading
translation
culture/script label as discovery evidence
scholarly interpretation
```

This keeps physical source custody separate from experiment permission.

---

## Relationship to Existing Noel Instrument Architecture

Do not build a second experimental system for glyphs.

The physical kernel feeds Noel's existing:

```text
instrument.runs
instrument.feature_registry
instrument.engine_registry
instrument.structure_candidates
instrument.structure_instances
instrument.structure_tests
instrument.structure_invariance
instrument.structure_promotions
instrument.corpus_snapshots
instrument.calibration_corpora
instrument.calibration_truth
instrument.blind_target_freezes
```

The next slice adds only the missing masked-state recovery contract and mark-specific feature/engine registrations.

---

## Binary Storage Boundary

The database is authoritative for capture identity, hashes, lineage, remote URI, and optional governed storage coordinates.

The migration intentionally does not manipulate Supabase Storage internals directly.

`mark.captures.storage_bucket` and `storage_object_path` are nullable until an approved Storage API path provisions the private image bucket.

No bulk glyph ingestion should begin until that byte-storage path is governed and verified.

---

## Required Pre-Glyph Release Sequence

Ancient glyphs should not be ingested merely because the physical schema exists.

The intended sequence is:

1. Release and verify `core_mark_physical_evidence_kernel_v1`.
2. Provision a private governed capture-byte storage path through an approved Storage API/surface; do not write Storage metadata tables directly.
3. Release the mark strict-blind feature registrations, Sequence Miner engine contract, State Recovery Trial contract, and synthetic calibration corpus definitions.
4. Execute synthetic calibration corpora before ancient evidence:
   - recoverable/redundant positive control,
   - random negative control,
   - row-confounded leakage control,
   - duplicate-leakage control,
   - damage/uncertainty control.
5. Require the engine to recover the deliberate signal and correctly fail/abstain on the controls.
6. Freeze the calibration result.
7. Only then ingest the first ancient physical corpus.

The first ancient corpus must therefore enter a system that has already demonstrated that it can distinguish real recoverability from accidental duplication, row confounding, and random pattern noise.

---

## Governing Principle

The purpose of the kernel is not to make Noel believe the Mark Engine theory.

It is to make Noel capable of preserving the evidence strongly enough to test it.

```text
PHYSICAL FACT
     ≠
ANALYTICAL INFERENCE
     ≠
RECOVERY PREDICTION
     ≠
LINGUISTIC READING
     ≠
SCHOLARLY INTERPRETATION
```

All of those may eventually coexist.

None is allowed to overwrite another.
