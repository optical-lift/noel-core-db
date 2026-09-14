# Atlas Work Sentence Context v1

## Purpose

Atlas must be able to accept work in the way a person naturally specifies it without reducing that work to a title string that later intelligence must guess at again.

The historical Atlas sentence builder had the correct authoring instinct:

> Create [action] [work] in [area] at [bed/object] for [person] on [farm day]

David's later operational grammar made the semantic structure clearer:

> Zone -> Zone Detail -> Function -> Action

The universal reality grammar then generalized that local language to:

> Authority Root -> Domain -> System -> Context -> Target -> Current State -> Function -> Action -> Resulting State -> Evidence

This contract carries those ideas into the current Company Work kernel without turning the rendered sentence, a UI form, or a task title into a new authority.

## Governing rule

**The sentence is a projection of typed facts. It is never the source of truth.**

Atlas must never need to parse a task title or rendered sentence to recover context, target, state transition, function, action, responsibility, timing, dependency, evidence, or handling mode.

A sentence such as:

> The florist email does not have the Elm header. Under Correspondence, revise it for Katie after Pricing Review so the delivered email carries the Elm header.

may render naturally, but its authority is distributed across separate contracts:

- `work_items`: durable Company Work identity and editable instructions;
- `work_item_semantic_frames`: the Work-owned semantic sentence frame and intended state transition;
- `work_item_context_links`: canonical Context/Target references such as a person, zone, or place;
- `work_item_relations`: causal/structural work-to-work relations;
- `work_allocations`: responsibility;
- `work_time_contracts`: time;
- source/domain evidence contracts, such as `communication_derived_work_links`: evidence and provenance.

## David grammar lineage

The original `Zone -> Zone Detail -> Function -> Action` proposal remains useful because it preserves two distinctions that ordinary task lists usually erase:

1. **where/what is being addressed is not the same thing as the work being done;**
2. **Function comes before Action.**

Examples remain lawful local grammars:

- `Landscape -> Weed / Cut / Plant / Fertilize`;
- `Fluids -> Check / Fill`;
- `Correspondence -> Reply / Forward / Acknowledge`;
- `Reconciliation -> Match / Allocate / Resolve`.

`Zone` and `Zone Detail` remain local vocabulary. Atlas must not create a universal `Zone` ontology merely because one organization uses that word. Depending on evidence, a local Zone Detail may be a finer Context or the actual Target.

## Semantic work frame

`atlas.work_item_semantic_frames` carries the part of the universal sentence that belongs to the requested Company Work transition.

The v1 frame may retain these phrases:

- `domain_phrase` — the local field of responsibility/work, when not already inherited;
- `system_phrase` — the bounded system, when not already inherited;
- `current_state_phrase` — the author's statement of what is currently true or why attention is needed;
- `function_phrase` — what purpose/kind of work is being served;
- `action_phrase` — the intended operation/verb;
- `resulting_state_phrase` — what the author intends to become true;
- `handling_mode` — the broad Atlas reasoning posture (`do`, `decide`, `research`, `prepare`, `watch`).

These phrases are semantic authoring state, not a second canonical ontology.

In particular:

- `current_state_phrase` does **not** overwrite a domain-owned canonical state or observation;
- `resulting_state_phrase` is the requested result, not proof that the result occurred;
- `function_phrase` is not a Capability and is not an Organization Function merely because the words happen to match;
- `action_phrase` is not the Company Work identity;
- `handling_mode` is not Function or Action.

Where a domain already owns canonical truth, Atlas should resolve/link to it rather than treating the phrase as a replacement authority. Where the organization has not yet mapped the phrase, preserving the unresolved phrase with provenance is lawful.

## CURRENT -> MOVE -> AFTER

The execution-side Task Move work supplied another durable distinction:

> CURRENT -> MOVE -> AFTER

For Company Work authoring:

- **CURRENT** is represented by the current-state statement and any canonical Context/Target evidence;
- **MOVE** is Function + Action applied to the addressed reality;
- **AFTER** is the requested Resulting State;
- execution requirements such as resources, methods, prerequisites, capacity, or dependencies remain branches around MOVE rather than fake sequential steps;
- actual completion and Evidence remain separate from the requested AFTER state.

A blocked or unresolved branch may prevent execution while preserving the intended AFTER state. Atlas must not discard the work merely because one branch is unresolved.

## Addressing the reality

The full universal sentence may include Authority Root, Domain, System, Context, and Target. Company Work should inherit what the current governed surface already establishes and ask only for unresolved meaning.

### Authority Root

For organizational Company Work, `work_items.organization_id` establishes the owning organization. This does not identify the executor.

### Domain and System

Domain/System may be inherited from existing organization/work context or remain an unresolved local phrase in `work_item_semantic_frames`. A stored phrase does not create a new canonical Domain, department, operating unit, or System object.

### Context and Target

`atlas.work_item_context_links` is the generic non-causal seam for canonical real things the work is in, about, for, or acting on.

v1 accepts:

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

A human-facing sentence may render those differently, but the relation remains inspectable.

Subject/context is not responsibility. A task can be **for Katie** while **Anna is responsible for doing it**.

Location is not responsibility. A task can be **in Bed 7** while being owned by someone elsewhere.

The storage shape is intentionally extensible to projects, Ledger objects, crops, assets, communications, accounts, and other governed subjects later. New subject kinds require explicit custody validation; arbitrary UUIDs are never accepted merely because they are syntactically valid.

## Related work

Existing `work_item_relations` remains authoritative for work-to-work meaning:

- `depends_on` (including UI language such as “after”);
- `part_of`;
- `blocks`;
- `enables`;
- `alternative_to`;
- `handoff_to` where already valid.

Work-to-work meaning must not be duplicated into the context-link table or inferred from prose.

## Responsibility

Responsibility remains in `work_allocations` and Company Work responsibility functions.

`for Katie` and `assigned to Katie` are different truths.

## Time

Due/relevance timing remains in `work_time_contracts`.

A date in the rendered sentence is a projection of that contract, not a second date field owned by the sentence builder.

## Evidence

Evidence answers **what supports the claim about what happened?**

Source/domain evidence contracts remain authoritative. Correspondence-derived work preserves the exact selected canonical message excerpt through `communication_derived_work_links`.

The semantic frame may state CURRENT and requested AFTER, but it does not manufacture proof. Intent is not result; result is not evidence.

## Handling mode

Handling mode tells Atlas how to reason about unresolved Company Work at a broad intelligence level:

- `do`: perform an action;
- `decide`: reach an authorized decision;
- `research`: acquire or verify truth;
- `prepare`: produce a reviewable result;
- `watch`: monitor until a condition, reply, date, or state warrants action.

Handling mode is deliberately separate from `operation_class`, local task type, Function, Action, Capability, and authority.

## Custody

Every semantic/context relation must remain organization-safe.

- a semantic frame belongs to the same organization as its work item;
- its author/updater must be an active membership of that organization when supplied;
- a zone/place must belong to a farm in the work item's organization;
- an identity subject projection must belong to the work item's organization;
- an external relationship must belong to the work item's organization;
- related work must belong to the same organization;
- authenticated browser callers receive no direct table write authority.

The browser submits intent only through governed RPCs.

## Correspondence-derived work v2

`create_communication_derived_work_self_api_v2` remains additive beside the existing v1 evidence/Company Work creator.

It first creates/deduplicates the canonical Company Work and source evidence through v1, then atomically adds:

- the semantic work frame;
- handling mode;
- context/target links;
- related-work relations.

This preserves existing Mailroom authority checks and evidence guarantees while giving new work enough coordinates to survive later Atlas reasoning.

## Sentence-builder behavior

The authoring experience should behave as a narrowing semantic sentence, not a universal ten-dropdown form.

Rules:

1. inherit Authority Root, Domain, System, or Context where the current Atlas surface already establishes them unambiguously;
2. ask only for unresolved meaning;
3. keep Context/Target, Function, Action, responsibility, time, dependency, and evidence distinct;
4. allow unresolved text where the organization's grammar dictionary is incomplete;
5. never require physical location for non-spatial work;
6. never infer completion from the selected Action;
7. preserve CURRENT and intended AFTER even if execution cannot yet be placed;
8. filter downstream choices when governed local grammar exists, especially Function -> Action;
9. retain the organization's preferred words while keeping the semantic role inspectable.

A correspondence authoring surface may therefore show a compact spine such as:

> CURRENT [header absent] -> FUNCTION [Correspondence] / ACTION [Revise] -> AFTER [email carries Elm header]

with context branches beneath it:

> for [Katie] · in [Feast Guild] · after [Pricing Review]

and execution envelope separately:

> assigned to [Lex] · due [Tuesday] · handling [Prepare]

The human sees one coherent sentence. Atlas retains several authorities.

## Incomplete context is lawful

A work item is not discarded because one semantic coordinate is absent.

- no assignee -> valid unassigned Company Work;
- no date -> valid temporally unplaced work;
- no place -> valid non-spatial or unresolved-spatial work;
- no person/target -> valid general work;
- unknown Function or Action -> valid unresolved semantic work;
- unknown Current State -> valid work whose basis still needs clarification/evidence;
- unknown Resulting State -> valid work whose completion contract still needs clarification;
- unresolved planning -> explicit planning/placement need, never disappearance.

This is the central reason for the contract: later Atlas intelligence may enrich, place, route, challenge, or escalate work, but it must not silently drop user-authored work merely because it was authored outside a pre-existing domain template.

## Non-collapse rules

The sentence builder must preserve at minimum:

- Authority Root != actor/carrier;
- Domain != System;
- Context != Target;
- Target != Function;
- Function != Action;
- Handling mode != Function or Action;
- Capability != Function or Action;
- Current State != requested Resulting State;
- requested Resulting State != actual Result;
- Result != Evidence;
- person/subject != assignee;
- place != assignee;
- dependency != context;
- title != semantic authority.

## Legacy boundary

`task_subject_links` belongs to the legacy Task architecture. It is not revived as the Company Work context seam.

Historical sentence-builder and Task Move UIs are design ancestors, not authority sources. Current Company Work uses `work_item_semantic_frames`, `work_item_context_links`, and existing kernel primitives so that the same semantics can be used by Mailroom, Ledgers, projects, farm operation, household work, and future Atlas intelligence without reparsing the sentence.