# HELD test: original Flower Work employee Result/Done

**Status: blocked by missing current production-shaped schema. Not a Venue permission failure, not a migration or production approval.**

## Exact source evidence

- Owner-only protected [signed run #42417563518](https://github.com/optical-lift/noel-core-db/actions/runs/42417563518), pinned held test source `bce5789d519cd9aa0d89ce3e4c8d5a4057e8425b`, passed identity/source checksum, local schema-only snapshot, disposable PostgreSQL startup and **41 DML-only fictional fixture safety statements**, then **FAILED before any worker-authenticated call** while executing synthetic fixture. Local `candidate-fixture.log` identified `ERROR: relation "atlas.organization_employee_seats" does not exist` at `fixture.sql:328`. Diagnostic artifact #13592636197. The test emitted no worker-report PASS.
- The table is defined in Noel **source** migration `supabase/migrations/20260908153000_atlas_employee_seat_identity_v1.sql`, but that table is **not present** in the actual production-schema snapshot used by the owner-approved validator. Source checked into GitHub is **not evidence of a released database relation**.
- The signed Worker Day writer requires (per `atlas.organization_employee_worker_context_self_v1`) active matching Organization/farm institutional identity, employee Seat, issued credential, Position appointment, actual current service date and governed work responsibility. The reporter additionally demands a real manager plan and canonical derived Worker Day projection, and distinct manager acceptance for the manager-acceptance result contract.
- **The already PASSed controls remain distinct:** [original Venue two-party signed #42412583641](https://github.com/optical-lift/noel-core-db/actions/runs/42412583641) and [original Flower Work-to-same-Bed positive signed #42415777184](https://github.com/optical-lift/noel-core-db/actions/runs/42415777184). Held feature source SQL blob is still `19e6cd0ac886bc51a1ad5682e38a14195737d2f9` unchanged. All original Bed, Work and Flower crop custody remain protected.

## What this branch preserves

This branch contains **only test-only** fictional employee identity/seat/credential/Position/adapter/policy fixture, a signed original worker appointment -> current owner Work plan -> canonical Worker Day -> result report -> manager acceptance and unauthorized actor test, plus a disposable-only invoker wrapper for owner decision when no released public route exists. No production SQL or real employee records.

This branch deliberately **must not merge** into the parent held Venue branch while the protected production-shaped schema lacks its prerequisite employee relation. The parent held branch has restored all three test files exactly to the known passing `cae3d810...` source blobs.

## Next authority-respecting gate

Verify which current **approved/released** employer/employee schema and source writer exists, and whether the employee-seat migration and its dependencies have ever been owner-adjudicated for production. Do not silently migrate employee tables or create a parallel role system merely to satisfy the Venue test. If an exact release is separately approved and genuinely deployed, renew the protected signed test with a new immutable commit and review the real public transport for institutional owner result acceptance. Until then: **Worker Result/Done signed-positive BLOCKED**, Event existing-Work signed-positive **still separate OPEN**, source/security and production Venue release **HELD**.
