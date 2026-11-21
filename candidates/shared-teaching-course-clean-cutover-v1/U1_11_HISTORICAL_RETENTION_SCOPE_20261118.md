# U1.11 — source-only historical retention / dependency scope

**Status: HELD, catalog-only.** This is a prerequisite to the protected actual-customer-data backup-and-restore harness. It does not read, copy, encrypt, restore, modify, delete, or migrate customer rows. No live backup has been created.

## Live structural observation, November 18, 2026

The read-only pg_catalog foreign-key inventory of Noel reported:

| Measure | Observed |
|---|---:|
| FK constraints involving Titus | 170 |
| Distinct directed child/parent relation pairs | 168 |
| Historical starting relations | 3 |
| Reachable descendant relations including roots | 39 |
| External child-to-parent references from those descendants | 38 |
| Unique external parent relation names | 13 |

Starting relations: titus.customer_course_drafts_v1, titus.customer_workspace_entitlements_v1, titus.programs.

External parents (not presumed disposable): auth.users, draft.song_objects, titus.course_slots, titus.courses, titus.customer_workspaces_v1, titus.lesson_packets, titus.lesson_script_segments, titus.teacher_patterns, titus.teacher_source_song_scopes, titus.teacher_source_units, titus.teacher_term_senses, titus.teachers, titus.truth_refs.

This is a transitive child-of graph. It does NOT mean every reachable table has rows for SK 101 or obsolete McMillan programs. Counts may drift if the schema changes. No row values, UUIDs, names, emails, receipts or private text were inspected or recorded.

The independent Song, teacher, lesson and Person originals must not be implicitly retired. Preserve and classify each via its owning source. Never use DROP CASCADE to resolve an unexpected dependency.

## HELD source-only checks

- U1_11_HISTORICAL_FK_CATALOG_ONLY.sql reads only pg_catalog FK metadata, not customer data.
- scripts/audit-titus-u111-historical-fk-closure.py accepts local JSON child/parent relation pairs, de-duplicates and traverses descendants, reports external dependencies, rejects malformed or missing roots, and explicitly records no data access, backup or release.
- tests/test_titus_u111_historical_catalog_safety.py supplies fictional cycles, duplicate edges, missing roots, and unreviewed dependencies. No remote secrets.
- The source-only PR workflow runs the tests without a protected environment or credential.

## Gates before the real customer-history rehearsal

1. **Row-scoped disposition:** Review each historical original, matching descendants, and external sources. Classify exact rows as preserve, same-ID adoption, independent original, possible retirement or out of scope. Do NOT classify all 39 relations as obsolete. The owner-selected backup-before-deleting-15-Course-shells-and-one-McMillan-program condition still stands.
2. **Trusted private capture/recovery:** Define a trusted execution/storage location, encrypted separately restorable data copy, protected key custody, retention/cleanup and roles/schema dependency plan. Do not indiscriminately dump Auth secrets or unrelated medical, Song and other-owner originals.
3. **Consistent source cut:** Define write-freeze or a transactionally consistent read-only snapshot, plus an independently preserved protected pre-adoption manifest of original IDs, UUID request receipts, authors, dates, sequence and literal UTF-8 bytes. No private IDs, body text, hashes or dump diagnostics should appear in logs, issues, PRs or uploaded artifacts.
4. **Independent owner gate:** A reviewed protected data-restore workflow needs a NEW exact owner-authored request and environment permission. Prior U1.9/U1.10 requests expressly permitted schema and roles only; they cannot authorize customer-row extraction.
5. **Clone-only adoption/retirement:** Run independently reviewed M1/M2 retention attestation on restored real rows. Rehearse the restrictive M4 retirement only with another separately approved clone and manifest. Never apply held SQL or deletion to production.
6. **Independent release gates:** Genuine signed full-schema GoTrue/PostgREST behavior, Atlas native Ledger/Reality eligibility, Titus licensing/seat/teacher/student lifecycle and application consumer cutover remain separate.

**Proof boundary:** FK inventory prevents unreviewed structural omissions. It is NOT a backup, real-row no-loss test, real same-ID adoption proof or authority to delete or release.
