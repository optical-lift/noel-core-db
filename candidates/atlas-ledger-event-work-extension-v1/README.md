# Atlas Event Work extension: three user-approved features

**Source status:** Implementation candidate, not deployed. Dependency: the proposed ordinary Event Work source migration `20261022013255` must be validated and released first. The existing finished Event PRs remain separate from other Atlas work.

## 1. Connect existing Work, never clone

An exact, currently active native Ledger relevance is a prerequisite to attaching previously established `atlas.work_items` to the exact Occurrence with `atlas.work_item_context_links`. No duplicated Work, allocations or recreated result evidence. The choices RPC reveals only a limited list of Work already relevant to this Ledger. Subject-link actions are idempotent, attributed and recorded.

**Not permitted:** using an Event screen to smuggle an unrelated Organization's or Ledger's Work into view; silently upgrading specialized Work to ordinary shared completion.

## 2. Complete ordinary lifecycle and truthful history

The canonical `atlas.work_items.work_state` currently only supports open/completed/cancelled/superseded. **Blocked** is therefore a source-backed Event state projected from append-only action history, not a fifth work_state.

**Reopen** unblocks open Work, or restores a completed Work to open only when it was created by the ordinary Event contract; accepted original completion evidence remains historically true. The closed-work kernel must be audited for projection consistency when reopening.

**Remove** distinguishes:
- a newly created, outstanding, Event-only ordinary Work record with no dependencies: guarded cancellation of the actual Work, not a ghost backlog;
- an existing independent Work item linked into the Event: remove from this Event's active projection **without deleting its source Work or underlying obligations**;
- dependent Event-created Work, including active offers/allocations/results: fail closed and require explicit reconciliation, never hide a still-active obligation.

History combines original Work creation, accepted completion results and the new actor-attributed actions. The checker is never falsely labelled as the physical performer. A new guard prevents the older Mark Done RPC bypassing Blocked status.

## 3. Direct personal attention without transferring custody

`atlas.ledger_occurrence_work_attention_v1` relates **one canonical Work** and **one canonical Person** in the exact Ledger Event. It can point to people with active native Ledger seats even before they claim Auth; the authenticated personal reader returns their pointers when their Personal Atlas becomes valid.

Attention is not `work_allocations`, an optional responsibility offer, an employee assignment, acceptance of a new obligation, or proof that a Person did the work. Clearing attention removes the personal pointer, not the Ledger's Work. Completed/removed tasks automatically disappear from the outstanding Personal attention projection, preserving history.

The new `atlas.my_ledger_event_work_attention_self_api_v1()` is the presentation adapter for the other conversation's active Today/My Work build. **Do not edit or merge conflicting Today components from this branch.**

## Release proof

1. SQL must compile against the cloned source graph with prerequisite `20261022013255` applied first; run schema postconditions and lint delta.
2. Authenticated Person A attaches existing relevant Work; Person B sees original Work ID, and action history identifies A. Replayed action ID creates no duplicate.
3. Person B blocks it; direct Mark Done through the *original* RPC must be denied; then B reopens it.
4. Person C removes the Event link: unrelated original Work remains open in its Ledger and no longer appears in the Event.
5. Event-born ordinary Work without dependencies may be removed and leaves no outstanding Work; dependencies require explicit reconciliation; prior results remain append-only.
6. A connected Person directs ordinary Work to another connected Person, including a Person without an Auth account; the pointer does not create an allocation or worker acceptance.
7. Signed-in target sees the exact source Work from Personal Atlas; the source changes to done and the personal outstanding pointer disappears. Another authorized Event participant may still complete it.
8. Cross Ledger/Organization/Event and unseated people denied; every action identity bound to real actor and source action id.
9. The Event UI must fail closed if any source call is absent; no fabricated correspondence or false send proof.

**This source-only candidate has no migration, production release, or authenticated end-to-end proof yet.**
