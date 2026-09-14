# Atlas Work Sentence Context v1

## Purpose

Atlas must be able to accept work in the way a person naturally specifies it without reducing that work to a title string that later intelligence must guess at again.

The historical Atlas sentence builder had the correct authoring instinct:

> Create [action] [work] in [area] at [bed/object] for [person] on [farm day]

Its authority model was not durable enough. Subject, location, assignment, timing, and object ownership were repeatedly conflated, and later readers had to infer meaning from prose.

This contract carries the sentence-builder idea forward into the Company Work kernel.

## Governing rule

**The sentence is a projection of typed facts. It is never the source of truth.**

Atlas must never need to parse a task title or rendered sentence to recover subject, place, responsibility, timing, dependency, evidence, or handling mode.

A sentence such as:

> Prepare the revised florist email for Katie in Feast Guild after Pricing Review by Tuesday.

may render naturally, but its authority is distributed across separate contracts:

- `work_items`: the durable work identity and editable instructions;
- `work_item_context_links`: non-causal subjects and places;
- `work_item_relations`: causal/structural work-to-work relations;
- `work_allocations`: responsibility;
- `work_time_contracts`: time;
- source-specific evidence links, such as `communication_derived_work_links`: evidence/provenance;
- `work_items.metadata.handlingMode`: the bounded v1 intelligence posture (`do`, `decide`, `research`, `prepare`, `watch`).

## Semantic dimensions

### Subject

Who or what the work is about.

Examples:

- for Katie;
- about a customer relationship;
- about a crop, project, or Ledger object in a future extension.

Subject is not assignment. A task can be **for Katie** while **Anna is responsible for doing it**.

### Location

Where the work belongs or where it acts.

Examples:

- located in Bed 7;
- acts on North Cooler;
- located in a named place.

Location is not assignment and is not inferred from title prose.

### Related work

How this work relates to other durable Company Work.

Existing `work_item_relations` remains authoritative for:

- `depends_on` (including the UI word “after”);
- `part_of`;
- `blocks`;
- `enables`;
- `alternative_to`;
- `handoff_to` where already valid.

Work-to-work meaning must not be duplicated into the context-link table.

### Responsibility

Who owns execution. Authority remains in `work_allocations` and Company Work responsibility functions.

### Time

When the work becomes due or relevant. Authority remains in `work_time_contracts`.

### Evidence

Why Atlas believes this work exists. Source-specific evidence contracts remain authoritative. Correspondence-derived work preserves the exact selected canonical message excerpt through `communication_derived_work_links`.

### Handling mode

How Atlas should reason about the work at a broad intelligence level:

- `do`: perform an action;
- `decide`: reach an authorized decision;
- `research`: acquire or verify truth;
- `prepare`: produce a reviewable result;
- `watch`: monitor until a condition, reply, date, or state warrants action.

Handling mode is deliberately separate from domain `task_type` and physical/operational `operation_class`. It must not overwrite those more specific semantics.

## Work context graph

`atlas.work_item_context_links` is the generic non-causal subject/context seam beneath Company Work.

Each link carries:

- the owning organization;
- the work item;
- a bounded `subject_domain`;
- a bounded `subject_kind`;
- the canonical subject UUID;
- a bounded `relation_kind`;
- creator/provenance metadata.

v1 accepts these canonical contexts:

- `spatial / zone`;
- `spatial / place`;
- `identity / identity_subject`;
- `identity / external_relationship`.

v1 relation kinds are:

- `about`;
- `for`;
- `located_in`;
- `acts_on`;
- `supports`.

The storage shape is intentionally extensible to projects, Ledger objects, crops, assets, and other governed subjects later. New subject kinds require explicit custody validation; arbitrary UUIDs are never accepted merely because they are syntactically valid.

## Custody

Every context relation must be organization-safe.

- a zone/place must belong to a farm in the work item’s organization;
- an identity subject projection must belong to the work item’s organization;
- an external relationship must belong to the work item’s organization;
- related work must belong to the same organization;
- authenticated browser callers receive no direct table write authority.

The browser submits intent only through governed RPCs.

## Correspondence-derived work v2

`create_communication_derived_work_self_api_v2` remains additive beside v1.

It first creates/deduplicates the canonical Company Work and evidence through the existing v1 contract, then atomically adds:

- handling mode;
- context links;
- related-work relations.

This preserves all existing Mailroom authority checks and evidence guarantees while making newly authored work semantically placeable.

## Sentence-builder projection

The authoring UI may render a natural sentence such as:

> Prepare [revised florist email] for [Katie] at [Elm Farm] after [Pricing Review].

The bracketed values are controls bound to canonical IDs. Editing the rendered sentence never becomes a freeform parser problem.

Responsibility and due date remain visibly separate because “for Katie” and “give task to Anna” are different truths.

## Incomplete context is lawful

A work item is not discarded because one semantic coordinate is absent.

- no assignee -> valid unassigned Company Work;
- no date -> valid unplaced time;
- no place -> valid work with unknown/not-applicable location;
- no subject -> valid general work;
- unresolved planning -> explicit planning conflict or unplaced state, never disappearance.

This is the central reason for the contract: later Atlas intelligence may enrich, place, route, or challenge work, but it must not silently drop user-authored work merely because it was authored outside a pre-existing domain template.

## Legacy boundary

`task_subject_links` belongs to the legacy task architecture. It is not revived as the Company Work context seam.

Current Company Work uses `work_item_context_links` plus the existing kernel primitives. Historical sentence-builder UI is a design ancestor, not an authority source.
