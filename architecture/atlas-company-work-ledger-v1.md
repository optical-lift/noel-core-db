# Atlas Company Work Ledger v1

**Status:** Proposed canonical read architecture  
**Scope:** Organization-level discoverable work  
**Depends on:** Atlas Company Work Kernel v1; Atlas Effective Position Authority v1

## Purpose

The Company Work Ledger is the canonical organization-level read surface for discoverable work.

> Work remains discoverable regardless of assignment, planning, Day admission, Clock placement, or worker exposure.

The Ledger exists so authorized management can inspect the whole field of company work without reconstructing truth from Worker Day, delivery projections, application code, or legacy task feeds.

## Governing position

Work identity belongs to `atlas.work_items`.

Assignment is custody layered onto work through `atlas.work_allocations`.

Time truth belongs to `atlas.work_time_contracts`.

Dependencies belong to `atlas.work_item_relations`.

Planning conflict belongs to `atlas.work_planning_conflicts`.

Current management position is owned by `atlas.company_work_position_v2` and must not be independently re-derived by downstream consumers.

Worker Day, Worker Week, Clock placement, and worker exposure are downstream execution/delivery projections. They may narrow what a worker sees, but they may not define whether organization work exists.

## Row grain

One Ledger row equals one canonical `atlas.work_items.id`.

The Ledger must not duplicate one work item because it has multiple historical allocations, planning events, legacy task carriers, worker projections, or execution adapters.

## Required read fields

The canonical Ledger read should expose at least:

- work identity: `work_item_id`, title, instructions, work state;
- organization and organization-unit custody;
- canonical work classification: operation class, jurisdiction, work definition/source where lawful;
- current responsible allocation and resolved assignee identity;
- current management position from `company_work_position_v2`;
- current active time contract;
- dependency count;
- open planning conflict;
- current active execution plan where one exists;
- stable derived lenses such as assigned/unassigned, planned/unscheduled, overdue, hard-date missed;
- created/updated/completed/cancelled timestamps;
- source provenance sufficient to trace the work back to its originating domain object.

## Derived-lens rule

Ledger booleans such as `is_unassigned`, `is_unscheduled`, or `is_overdue` are side-effect-free read conveniences. They do not become mutation authority or source truth.

Time lenses must preserve temporal vocabulary. A preferred date is not a hard finish. A work item may be unscheduled without being unassigned or irrelevant.

## Employee lenses

Employee Ledger tabs are filters over one company-work population:

- All: no assignee restriction;
- Unassigned: no active responsible allocation;
- Person: active responsible allocation resolves to that organization member/person.

No person-specific task table or person-specific ledger is permitted.

## Planning lenses

The Ledger should support at least:

- planned;
- unscheduled;
- waiting dependency;
- planning conflict;
- overdue;
- hard-finish missed.

Planning state is an overlay on work identity. Removal from a day/week must never erase the work item.

## Principal boundary

The Company Work Ledger is a management inspection surface. It is not a Principal Clock candidate feed.

Ordinary delegated work may remain visible to authorized higher-level management without automatically earning Principal attention. Escalation into Principal arbitration remains governed by the Principal Operating System escalation contract.

## Legacy boundary

The finished Ledger must not `UNION` legacy `atlas.tasks` into canonical work.

Legacy tasks are ingestion/reconciliation inputs only. They must cross an explicit canonicalization boundary into Company Work before the Ledger may treat them as current company work.

The Ledger therefore knows only canonical work identities. Legacy provenance may remain traceable through adapters/source metadata, but legacy schema semantics do not become Ledger semantics.

## Read-authority rule

Downstream applications, agents, reports, and management screens must consume the Ledger/current-position authority rather than reimplementing assignment, dependency, planning-conflict, or time-state precedence independently.

## Initial consumers

- Employee Ledger UI;
- Atlas Work agent tools;
- management work search;
- person responsibility queries;
- unassigned-work queries;
- planning and capacity inspection.

## Non-consumers

- Worker Day delivery decisions;
- Principal Clock admission;
- mutation commands.

Those systems may consume canonical work facts where appropriate but remain separate authorities.

## Acceptance tests

1. Open unassigned work appears in All and Unassigned.
2. Open assigned work appears in All and the correct employee lens.
3. Assigned but unscheduled work remains discoverable.
4. Removing work from a Worker Day or Worker Week does not remove it from the Ledger.
5. Planning conflict is visible without changing work identity.
6. Waiting dependency is visible without pretending the work is unassigned.
7. Completed/cancelled/superseded work can be filtered without contaminating open-work counts.
8. Preferred time and lawful/hard limits are distinguishable.
9. One canonical work item produces one Ledger row.
10. Worker delivery state does not determine Ledger existence.
11. Ordinary delegated work does not become Principal Clock work merely because management can inspect it.
12. No finished Ledger query reads legacy `atlas.tasks` directly.
