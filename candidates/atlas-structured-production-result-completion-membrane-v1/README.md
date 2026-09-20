# Structured Production Result Completion Membrane v1

Candidate source for issue #892.

## Failure proved by the Rocket closed-loop specimen

A Production hardening task was marked `done` through the generic task transition path while its metadata required a structured result. Task completion therefore diverged from Production reality:

- no Production Lot event;
- no tray-batch state transition;
- no Production Lot stage transition;
- no crop-cycle state transition;
- no downstream transplant-readiness work.

The same historical shape currently exists on multiple completed Production-linked tasks.

## Law

Generic `done` / `checklist_done` may not close a task when both are true:

1. the task is linked to a Production Lot through `production_lot_tasks`;
2. `worker_task_requires_structured_result_v1(task_id)` is true.

The Production domain adapter must record canonical result evidence/state first and then complete through the trusted internal transition path.

## Scope boundary

This tranche is deliberately Production-exact. Other domains still have heterogeneous durable-result contracts and some legitimately write domain evidence before calling the public transition wrapper. They are not silently migrated here.

## Historical boundary

The new audit view surfaces completed Production-linked structured-result tasks with no `production_lot_event`. It does not repair them.

A task completion timestamp is not a biological observation timestamp. Recovery requires current observation or separately supported historical evidence.
