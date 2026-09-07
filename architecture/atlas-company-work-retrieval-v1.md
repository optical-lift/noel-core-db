# Atlas Company Work Retrieval v1

**Status:** Proposed application/agent read contract  
**Depends on:** Company Work Ledger v1

## Purpose

Provide one governed retrieval contract for organization work so the Employee Ledger UI, management searches, and agents share identical filter semantics.

## Governing rule

Consumers ask the Company Work Ledger for filtered work. They do not reconstruct responsibility, overdue state, planning state, or person responsibility independently.

## Responsibility semantics

The canonical Ledger distinguishes:

- `allocated` — lawful active responsible allocation;
- `unresolved_named` — canonical Company Work conflict truth names a person, but lawful allocation is not currently possible;
- `unassigned` — no active allocation and no canonical named responsibility candidate.

A person lens filters `responsibility_user_id`, not only `assignee_membership_id`. This means a management query for Anna includes both lawfully allocated Anna work and unresolved-named Anna work, with `responsibility_position` preserving the distinction.

The Unassigned lens includes only `responsibility_position='unassigned'`. It must not absorb named-but-unallocatable work.

## Required query dimensions

The canonical query must support:

- organization scope;
- responsibility person/user scope;
- responsibility position: allocated / unresolved_named / unassigned;
- work lifecycle states;
- management positions;
- operation classes;
- organization units;
- planning state: planned / unscheduled / conflict / waiting dependency;
- time lens: overdue / hard missed / planned today / planned date range / lawful-window date range;
- text search across approved display fields;
- pagination/cursor;
- include/exclude terminal work.

## Person resolution

Human-facing callers may resolve a display name to a canonical user identity before invoking the work query. The database query contract itself uses canonical identifiers rather than a bare name string.

Where multiple current/historical memberships exist, person retrieval remains anchored to `user_id`; membership is custody evidence, not person identity. Ambiguous display-name resolution must fail explicitly rather than guessing.

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

A person facet count includes both `allocated` and `unresolved_named` work for that person. The row display must preserve which responsibility position each item is in.

Facet counts must never be computed from a different population than the displayed rows.

## Authorization

The Ledger is an organizational management read surface, not a public worker endpoint.

Direct browser access to raw canonical work remains prohibited until the appropriate authorization API exists. Server/application callers must establish requester identity and organization-level read authority before invoking the governed query.

Do not solve authorization failures by widening RLS, granting broad table access, or adding an unscoped `SECURITY DEFINER` function.

## Worker boundary

Worker Day or `/anna` may use narrower delivery projections. A worker-facing view is not evidence that work outside that view does not exist.

Unresolved named responsibility in the management Ledger does not itself authorize worker delivery. Worker exposure still requires its own lawful delivery path.

## Principal boundary

Retrievability by higher management does not grant ordinary delegated work a place in Principal Clock. Principal escalation remains a separate governed transition.

## Acceptance queries

The initial implementation is incomplete until each of these can be answered through one governed retrieval path:

1. all open company work;
2. all truly unassigned open work;
3. all open work canonically associated with Anna, including unresolved-named responsibility;
4. Anna's work separated by allocated vs unresolved-named responsibility;
5. Anna's responsibility that is unscheduled;
6. all open overdue work;
7. all work with an open planning conflict;
8. all work in a selected organization unit;
9. all work of a selected operation class;
10. a bounded planned-date range;
11. a text search without bypassing organization scope.

## Agent invariant

When the canonical Company Work retrieval contract is available, agents must use it first for questions about organization work, employee responsibility, unassigned work, overdue work, or planning position. Git history, Worker Day pages, application memory, and raw legacy task tables are diagnostic fallbacks only when the canonical contract reports missing or contradictory evidence.
