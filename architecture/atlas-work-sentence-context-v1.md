# Atlas Work Sentence Context v1

## Purpose

Atlas must be able to accept work in the way a person naturally specifies it without reducing that work to a title string that later intelligence must guess at again.

The historical Atlas sentence builder had the correct authoring instinct:

> Create [action] [work] in [area] at [bed/object] for [person] on [farm day]

Its authority model was not durable enough. Subject, location, assignment, timing, and object ownership were repeatedly conflated, and later readers had to infer meaning from prose.

This contract carries the sentence-builder idea forward into the Company Work kernel and aligns it with the David Task Grammar:

`Authority Root -> Domain -> System -> Context -> Target -> Current State -> Function -> Action -> Resulting State -> Evidence`

## Governing rule

**The sentence is a projection of typed facts. It is never the source of truth.**

Atlas must never need to parse a task title or rendered sentence to recover subject, place, responsibility, timing, dependency, evidence, handling mode, or the intended state transition.

## Work transition

For task authoring, the central semantic spine is:

`CURRENT -> MOVE -> AFTER`

Where:

- **CURRENT** is the observed or asserted starting-state phrase supplied for the work. It does not overwrite a domain-owned canonical state.
- **MOVE** is represented by **Function + Action**. Function names the kind of change or operating function; Action names the requested act within it.
- **AFTER** is the requested resulting-state phrase. It is an intent or acceptance target, not evidence that the result has actually occurred.

Domain and System may also be supplied when they help position the transition. They remain semantic phrases until and unless Atlas can lawfully resolve them to canonical domain objects.

## Context and target

Person, place, and related work surround the transition as address/context. They are not substituted for CURRENT, MOVE, or AFTER.

Canonical links currently supported by this tranche are:

- Identity subjects and external relationships, with relations such as `for`, `about`, and `supports`.
- Spatial zones and places, with relations such as `located_in`, `acts_on`, `about`, and `supports`.
- Company Work relations through the existing work relation graph, including `blocks`, `enables`, `depends_on`, `part_of`, `alternative_to`, and `handoff_to`.

The historical Zone / Zone Detail vocabulary is therefore treated as local authoring language. A Zone can resolve to Context; Zone Detail can resolve to another Context or the Target according to the governed object actually selected.

## Execution envelope

The following are deliberately orthogonal to the semantic transition:

- responsibility / assignment;
- due date and other timing contracts;
- authority;
- handling mode (`do`, `decide`, `research`, `prepare`, `watch`);
- evidence.

These contracts answer who may or should act, when action is expected, how Atlas should handle the work, and why the work exists. They do not redefine the state transition itself.

## Evidence

Correspondence-derived work keeps the selected communication excerpt as Evidence through the existing communication-to-work evidence contract.

Evidence is never copied into CURRENT or AFTER merely to make the task look complete. The communication remains the source authority for what was said; the Company Work semantic frame records the requested work interpretation.

## Unknowns are lawful

A person can know that something needs doing without knowing every grammar slot. Atlas must permit semantic-frame fields to remain unknown rather than inventing values or refusing to create durable work.

Later reasoning may propose additional typed placement, but it must not silently rewrite source evidence or canonical domain state.

## Storage

`atlas.work_item_semantic_frames` owns the Work-authored semantic frame:

- optional Domain phrase;
- optional System phrase;
- CURRENT / current-state phrase;
- Function phrase;
- Action phrase;
- AFTER / resulting-state phrase;
- handling mode and provenance metadata.

`atlas.work_item_context_links` owns typed non-causal identity and spatial context.

`atlas.work_item_relations` remains authoritative for Work-to-Work semantics.

Existing allocation, timing, evidence, and authority contracts remain authoritative for their respective domains.

## Correspondence projection

The Mailroom authoring surface may render a human-readable sentence or CURRENT -> MOVE -> AFTER diagram from these facts. The projection is for comprehension and editing only.

A correspondence-derived task therefore remains valid even when only a title and evidence are known. As more of the work grammar becomes known, Atlas can persist those facts without reparsing the title.
