# Delegated private Course reads — held source candidate

This increment adds two service-only read operations over the existing canonical Course/Unit originals. It uses the current exact owner-private working-draft authorization and credential; it creates no Course, Unit, revision, grant, or credential row. The signed self readers remain unchanged.

## Operations

- `shared_delegated_course_outline_read_service_v1(token_hash, course_id)` returns the existing outline contract.
- `shared_delegated_course_unit_read_service_v1(token_hash, course_id, unit_id)` returns the existing current Unit-material contract, including the exact current revision number or null material.

Both reject a missing/revoked/expired token, another Course, a Unit outside that Course, a non-current authoring grant, or a published Course through the current working grant predicate. The public-schema facades have `service_role` EXECUTE only. Atlas must accept only the fixed command names, derive the token hash locally, and verify the result before sending it to Sites. No arbitrary RPC or caller-supplied hash is exposed.

## Release gates

1. Review this SQL against the released Course and delegated authorization definitions and generate a canonical `shared_` migration through Noel's normal workflow.
2. Run syntax and ACL postconditions on a production-shaped disposable clone. Prove a genuine current signed owner plus a separately signed outsider, revoked grant, wrong Course/Unit, expired credential, and independent Course revision readback. Keep private text out of CI output.
3. Release source with exact owner authorization; then integrate Atlas and Sites against these two fixed RPCs. A Site tool must remain disabled until its source endpoint and receipt validation are available.

The existing 24-hour authorization and Atlas command window still apply. A reusable revocable authoring grant and separate credential rotation policy require their own reviewed source and transport change; this read increment does not silently extend them.
