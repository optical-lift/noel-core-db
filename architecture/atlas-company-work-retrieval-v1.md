# Atlas Company Work Retrieval v1

**Status:** Proposed application/agent read contract  
**Depends on:** Company Work Ledger v1

## Purpose

Provide one governed retrieval contract for organization work so the Employee Ledger UI, management searches, and agents share identical filter semantics.

## Governing rule

Consumers ask the Company Work Ledger for filtered work. They do not reconstruct assignment, overdue state, planning state, or person responsibility independently.

## Required query dimensions

The canonical query must support:

- organization scope;
- assignee membership/person scope;
- assignment scope: all / assigned / unassigned;
- work lifecycle states;
- management positions;
- operation classes;
- organization units;
- planning state: planned / unscheduled / conflict / waiting dependency;
- time lens: overdue / hard missed / planned today / planned date range / lawful-window date range;
- text search across approved display fields;
- pagination/cursor;
- include/exclude terminal work.

## Person semantics

Human-facing callers may resolve a display name to a canonical user/membership identity before invoking the work query. The database query contract itself must use canonical identifiers rather than a bare name string.

Ambiguous person resolution must fail explicitly rather than guessing.

## Core operations

The application/tool layer may expose convenience operations such as:

- `get_company_work`
- `get_person_work`
- `get_unassigned_work`
- `get_overdue_work`
- `get_person_unscheduled_work`
- `get_work_history`

These are convenience adapters over one Ledger contract, not independent sources of truth.

## Facets

A companion facet contract should return counts using the same predicates as the row query so the UI can render lenses such as:

- All;
- Unassigned;
- Anna;
- Fred;
- Open;
- Overdue;
- Unscheduled;
- Planning conflict;
- organization unit;
- operation class.

Facet counts must never be computed from a different population than the displayed rows.

## Authorization

The Ledger is an organizational management read surface, not a public worker endpoint.

Direct browser access to raw canonical work remains prohibited until the appropriate authorization API exists. Server/application callers must establish requester identity and organization-level read authority before invoking the governed query.

Do not solve authorization failures by widening RLS, granting broad table access, or adding an unscoped `SECURITY DEFINER` function.

## Worker boundary

Worker Day or `/anna` may use narrower delivery projections. A worker-facing view is not evidence that work outside that view does not exist.

## Principal boundary

Retrievability by higher management does not grant ordinary delegated work a place in Principal Clock. Principal escalation remains a separate governed transition.

## Acceptance queries

The initial implementation is incomplete until each of these can be answered through one governed retrieval path:

1. all open company work;
2. all unassigned open work;
3. all open work currently assigned to Anna;
4. Anna's assigned but unscheduled work;
5. all open overdue work;
6. all work with an open planning conflict;
7. all work in a selected organization unit;
8. all work of a selected operation class;
9. a bounded planned-date range;
10. a text search without bypassing organization scope.

## Agent invariant

When the canonical Company Work retrieval contract is available, agents must use it first for questions about organization work, employee responsibility, unassigned work, overdue work, or planning position. Git history, Worker Day pages, application memory, and raw legacy task tables are diagnostic fallbacks only when the canonical contract reports missing or contradictory evidence.
