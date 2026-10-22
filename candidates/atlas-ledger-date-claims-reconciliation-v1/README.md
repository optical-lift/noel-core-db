# Atlas Ledger date claims reconciliation — candidate v1

**Status:** Review-only SQL candidate. **Not deployed.** `noel-core-db` owns migration source; do not run this source directly against production.

## Governing reason

The universal Temporal Field already composes canonical Occurrences and independent Ledger Resource occupancy. An operational community Event can nevertheless carry a different title, local time, date, or lifecycle status while pointing to **the same canonical Occurrence**. The existing Ledger occurrence Index and Temporal composer do not expose the competing community-event fields together.

This candidate creates one **read-only, Ledger-seat-authorized evidence membrane**, not another calendar, event, scheduling, or claims source. It is the first source-identity reconciliation slice required by the Universal Subject Workspace / One Date build.

## Contract

`atlas.ledger_occurrence_date_evidence_self_api_v1(ledger_id, start_date, end_date, timezone_name, limit)`

- Requires valid authenticated session and active native Ledger participation using the same identity access gate as the existing Event Index.
- Includes only active **Ledger-bound canonical Occurrences** overlapping the requested civil date window **or** having a linked operational community-event assertion bearing a source-local date in that window.
- Emits **one row per canonical Occurrence ID**, with explicit canonical source coordinates and an array of linked, source-qualified Organization community-event assertions.
- Returns per-assertion difference fields as **review candidates**, not a judgment about which proposition is correct. Labels and statuses may have different lawful meanings.
- Includes only `atlas.community_events.visibility_scope='farm_shared'` in this native Ledger-participant reader. Owner- and management-scoped operational assertions require separate, more restrictive Organization authorization; their titles, existence, and counts are not exposed through this projection. Does not include customer, resource, contact, private communications, or unrelated Organization details.
- If multiple Organization relationships could supply a community Event, it exposes a source-bound ambiguity count without leaking competing Organization overlays.
- Reports bounded-result truncation, admitted source families, and `wholeDayComplete=false`. Personal Life, Work timing, communication time, other calendars, unknown timezones, independent occupancy and non-bound Occurrences are **not** silently represented as complete.
- Preserves current source values; no `INSERT`, `UPDATE`, `DELETE`, or new persisted calendar state.
- The `public` delegate is an unprivileged SQL invoker wrapper; source identity and Ledger authorization remain server-side.

## Dependencies and limits

- Depends on `ledger.occurrence_calendar_bindings`, `ledger.seats`, `atlas.ledger_organization_participations`, `atlas.organization_occurrence_bindings`, `atlas.community_events`, and `local_intel.occurrences`.
- This is **not yet** the complete Person-wide `One Date` composer. It is the guarded, provenance-bearing canonical Occurrence/overlay discrepancy adapter that the future full composer and Subject Workspace should consume.
- The first query window is bounded to 46 civil days and the result to 250 Occurrences.
- Source-local operational dates are compared against requested dates without coercing an unverified event timezone into an authoritative instant. Canonical time is returned as `timestamptz` and requested-zone civil fields are explicitly tagged.
- Writer-side corrected schedule/adjudication, independent Work deadlines, non-Ledger personal data, source failures and freshness evaluation remain separate packets. **No automatic schedule correction.**
- Disposable synthetic fixture and postconditions test authorized Ledger Person, authenticated outsider denial, owner-only operational-overlay non-disclosure, role ACL, same-date different-occurrence non-conflation, one source ID, disagreement retained, source-local date drift, unknown canonical end time, and incomplete coverage. Actual signed GoTrue/PostgREST tests remain a separate release gate.
- No synthetic data belongs in production.

## Release gate

1. Review `candidate.sql` and `validation.sql` for identity/privacy and clock correctness.
2. Merge only reviewed candidate source to canonical `main`.
3. Generate exact `atlas_` migration through the repository's owner-triggered canonical migration-generation workflow.
4. Run protected disposable production-schema clone validation and rollback-only role/identity fixtures; confirm no new security advisor findings.
5. Prove actual signed Auth/PostgREST session of a permitted Ledger Person and denied outsider (not merely simulated `auth.uid()`).
6. Require a separate deliberate protected production release and app consumer rollout.

Original fixed user scenario is kept as a **private acceptance packet**; the public source does not hardcode an event title, real person's identity, date or Ledger UUID.
