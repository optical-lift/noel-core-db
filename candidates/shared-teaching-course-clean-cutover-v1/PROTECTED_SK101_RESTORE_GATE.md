# SK 101 protected restoration and single-Course cutover verification gate

**Status:** HELD. Source-only plan and test fixtures, not a protected data backup, owner approval, generated migration, live source release or authorization to delete.

## Owner-governing outcome

SK 101's existing `titus.customer_course_drafts_v1.course_id` becomes **the same** `atlas.teaching_courses.id`, never a newly minted second Course. Its founding manuscript, both authored Units (Class and Homework draft), their three saved Unit revisions, exact original revision and request UUIDs, authors, positions, timestamps and UTF-8 body bytes remain unchanged. A draft Homework document is not assigned Work. Titus product access is separately source issued. An institutional proposal does not give the operator access.

## Latest read-only live source inventory (2026-11-07)

| Check | Observation |
|---|---:|
| Existing private Course originals | 1 |
| Founding manuscript revisions | 1 |
| Founding manuscript character length | 10,228 |
| Authored Units | 2 |
| Original Unit revisions | 3 |
| Combined Unit revision characters | 111 |
| Existing Atlas institutional Course roots | 0 |
| Obsolete Course shells | 15 |
| Obsolete McMillan program roots | 1 |
| Source-issued Titus authoring grants | 1 |
| Exact Course UUID collisions | 0 |
| Unresolved unique canonical current Course authors | 0 |
| Unresolved Titus grant holders | 0 |
| Multiple author/editor actor conflicts within Units | 0 |

This evidence was obtained from SELECT-only live queries that returned counts/booleans only. **No private IDs, names, original text, receipts, data export, or hash values were committed to Git.** This inventory can drift while old writers remain active; it is NOT a frozen or restored backup.

## Source-only proof added

- `sk101_exact_adoption_candidate.sql` compares adopted Course titles, Unit kinds/titles and all manuscript/Unit bodies with `convert_to(text, 'UTF8')` **bytea** comparisons. This avoids relying on text collation or merely matching character count. It also compares IDs, revision chains, request receipts, timestamps and original Auth custody.
- `sk101_clone_byte_attestation.sql` is an independent, **post-adoption, pre-deletion** clone-only audit. It uses full joins to detect missing/extra rows, UUID mismatch, changed author/date/order, and UTF-8 byte differences, without returning content or any private identifier.
- `synthetic_pg17_journey.sql` calls both checks and deliberately mutates a restored fictional manuscript's line endings and a Unit's ordering inside isolated savepoints. Each mutation must be rejected with SQLSTATE 23514, then rolled back and the original positive attestation repeated. These are fictional records, **not** a restored SK 101 backup.

## Protected owner-controlled verification order

1. **Source freeze/authorization:** Obtain exact owner approval for testing the production source in a credential-protected, private **disposable** PG17 clone. Lock immutable Noel/Titus PR heads and establish the maintenance/freeze plan separately; the owner issue must pass the repository's OWNER and protected-environment gates. Do not invoke a generic production release. An assistant-written or bot-authored issue cannot stand in for the actual owner authorization.
2. **Protected backup:** On the credentialed runner only, create independent encrypted/permission-restricted copies of roles, schema, and actual data, including SK 101 original rows and the full old Course/program dependent graph. Keep dump files out of git, log output, GH Actions artifacts and untrusted external storage. Protect and restrict retention. A schema-only dump is **not** a backup-restore acceptance.
3. **Restore and attest baseline:** Restore those bytes into an isolated disposable PG17 instance with no production write route; verify restored row counts, original IDs, all bytes and independently retained protected manifest values. Do not print private text, UUIDs, hashes or credentials. Verify genuine `auth` session/GoTrue context separately; fabricated SQL JWT settings are not signed integration tests.
4. **Clone source rehearsal:** In an explicit transaction on the restored clone, verify production catalog/trigger/FK shape, run the HELD M1 Person-first root adaptation, M2 adoption, `sk101_clone_byte_attestation.sql`, M3 authoring, and M3.5 proposal-only standing. Verify same UUID, original history, no duplicate Course, no source-created student Work. Roll back. **Never point these candidates at the live database.** Marker `app.shared_course_clone=approved` is only an accidental-use deterrent, not an authorization mechanism.
5. **Signed negative tests:** With a real disposable GoTrue/PostgREST transport and two separately authenticated test People, prove author, outsider, stale session, revoked binding, product entitlement, mismatched Course/Unit access, changed request idempotency, and concurrency. Verify institution Ledger membership alone conveys **no** authority. Institution acceptance is NOT yet implemented; do not claim that test passes.
6. **Retention/deletion rehearsal:** After exact source and backup proof and a reviewed descendant-by-descendant retirement manifest, run a separately reviewed **explicit** deletion plan only on another restored clone. Stop old writers; delete exclusively old Course/program rows; preserve independent Noel Song/teacher/research originals; drop obsolete objects with RESTRICT, never CASCADE. After removal, compare the preserved target against the independent protected pre-delete manifest, because source tables will no longer exist for a direct old/new join.
7. **Release gate:** The independent restored-data proof, signed negative tests, fully passing no-legacy end-state assertion, exact generated migration, Titus+Atlas API consumer cutover, independent owner approval, and recovery evidence are all required before any production migration/deployment. Leave both draft PRs held until those are complete.

## Why the existing GitHub schema workflow cannot clear this gate

`.github/workflows/production-schema-clone-validation.yml` is limited to owner-authored issues and an exact versioned migration package. It snapshots roles and schema, **not actual SK 101 data**. The current draft contains ungenerated, HELD `candidates/` SQL, not a releasable migration file. Calling that existing workflow now—or passing it with a synthetic fixture—would only validate a different, narrower contract. No shortcut through `supabase/migrations`, CLI push, an ordinary live `execute_sql` write, or unsigned fictional actor test is approved.

**Next non-destructive engineering gate:** A separately reviewed owner-only *protected data restoration harness* under main repository custody, with a read-only data acquisition step and isolated clone verification, followed by a genuine owner-authored request. Until that exists and is approved, do not claim the protected backup is restored or the real Course adopted.


## M4 private original retention without old source tables

The supported local-only test has two additional scripts: `sk101_clone_temporary_manifest.sql` prepares a session-private source snapshot before M1, and `sk101_clone_postretirement_manifest_attestation.sql` verifies the original identity/history/custody and literal UTF-8 bytes against the canonical records **without referring to old source tables**. The fictional PG17 runner then deletes four private Course source table families under a SAVEPOINT with `DROP TABLE ... RESTRICT`, checks the preserved Course against the private manifest, proves a deliberate retained-byte mutation is rejected, rolls back the savepoint and entire transaction. No real legacy curriculum, independent manuscript or Formation data was targeted. No production backup/restore has been performed.

The original private snapshot only lives within the isolated clone transaction; a future owner-approved full data restore must initialize the manifest from the actual restored source and retain a separately authenticated protected backup receipt. This is not proof that the 15 old Course shells or obsolete RPCs have been retired.
