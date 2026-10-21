# Physical employee-seat retirement — schema-only validation correction

The first generated retirement migration `20261021005026` was **never production released**. Production-shaped schema validation found that its postcondition incorrectly demanded a real credential and membership Work row from a **schema-only** clone. The migration DDL itself completed there, but the no-data postcondition failed.

The replacement version `atlas_physical_employee_seat_retirement_v2` preserves the function rewrites and adds an **in-transaction pre-drop archive check**: every physical seat must have a matching exact original-seat snapshot in credential provenance before the FK columns or table can be removed. On production with records, an unmatched seat aborts the transaction and nothing is deleted. In an intentionally empty schema clone this condition is vacuously true.

Its postcondition asserts structural retention and rejects **invalid archived credentials when present**; it does not invent missing production fixtures or require real historical Work in a schema-only harness. The original candidate remains in Git history with its failed validation receipt. This replacement requires its own immutable generation, clone validation, and protected release.

Existing Organization Member credentials and historical Work records are not deleted by either candidate. The old employee seat table will remain on production unless and until the replacement passes validation and is separately released.
