# Person period source history — candidate v1

**Status:** source-only candidate; no live DDL, rollout, or private-data migration.

This adds a bounded, cursor-paginated **read membrane**, not a new history table, note writer, report table, shared organization journal, or backfill.

## Exact reuse

- `atlas.personal_reality_captures` and original `atlas.evidence_records` preserve the author's testimony, source date assertion, capture timestamp and evidence ID.
- `atlas.task_entries` preserves the Person-owned task state and `completed_at`, presented only as **marked complete** and never as verified physical execution.
- `atlas.require_active_task_principal_v1()` and `auth.uid()` scope every source row to the signed-in Person.
- A sourced time, notebook page date, recorded timestamp, and task status are separate and never overwritten by a presentation field.
- No private raw note is automatically admitted to an Organization/Ledger/board report.

## Contract

`public.person_period_source_history_self_api_v1(start,end,timeZone,limit,cursor...)` returns a source-qualified ordered packet with `hasMore` and exact continuation. Date horizon 367 inclusive days, page 1–200. `sourceCoverage` explicitly describes excluded source families. `nextCursor` is null when exhausted. Readers must show partial coverage and incomplete pagination.

## Not solved here

No text-matched identities. No automatic assignment, event creation, medical state, measurement, institutional correspondence, non-user records, physical completion proof, or generic board-report permission. Those require existing exact source relationships and owning-domain authorization. Source-backed related-work/communication adapters can extend the read composition after proving two different domains; do not create a universal cloned activity table.

## Gates before production

1. Run on an isolated schema clone with committed source migrations and inspect actual index plans for a long history; add source-owned indexes only if proved necessary.
2. Test two signed-in People, no session, inactive principal, malformed cursor, date bounds, timezone changes and source failures. Never test authorization using forged `auth.uid()` in production.
3. Confirm `public` wrapper grants only authenticated execution; Atlas schema function is not externally exposed; confirm definer search paths and protected raw tables.
4. Verify rows from both source kinds, pagination exactness, preexisting observation reread parity, and that no cross-institution facts leak.
5. Follow protected noel-core-db Atlas release lane and migration custody process. No app claims `ready` before actual contract-version proof.
