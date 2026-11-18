# U1.14 — November 18 live FK catalog-only result and old Course-root scope extension

**HELD / structure only. No historical customer row read, row selector, customer vault, encrypted backup, delete or release.**

## Exact review outcome

On November 18, 2026, the owner-directed continuation ran the candidate catalog SQL against the existing Noel Supabase project's **PostgreSQL system catalogs only**, with no query against the contents of any Titus, Auth, Person, Song, Atlas, curriculum, or customer table. The initial query failed to parse because a bare alias used PostgreSQL's reserved `deferrable` token; the candidate source was corrected to `is_deferrable` and the same metadata-only query then executed.

Only the following **aggregate metadata** is preserved here. The complete live FK-column catalog result is **not committed**.

| Structural check | Observed |
| --- | ---: |
| Titus-related FK constraints | 170 |
| Unique child/parent relation pairs | 168 |
| U1.13 frozen unique pairs | 168 |
| New or missing relation pairs | 0 |
| FK delete behaviors, all 170 constraints | 93 CASCADE; 28 SET NULL; 18 RESTRICT; 31 NO ACTION |
| Actual customer values, IDs, text/revision bytes read | **0** |
| Production DDL/DML, customer capture, backup, restore | **0** |

This confirms **current relation-pair parity only**. A matching pair set cannot prove that column definitions, source semantics, private records, users or retention policy are unchanged or authorized. Constraint delete actions are observed physical effects, not authority to use those effects.

## Necessary additional retirement root

U1.13's 39-relation graph was computed from the roots:
- `titus.customer_course_drafts_v1`
- `titus.customer_workspace_entitlements_v1`
- `titus.programs`

But the intended **separate retirement of 15 old Course shells** concerns `titus.courses`, which U1.13 designated an **independently governed external parent**, not a covered retirement root. From the same frozen 168 relation pairs, including the historical `titus.courses` root yields **45 reachable relations** — 6 more than the previous three-root graph:

1. `titus.courses` (root, not automatically all rows)
2. `titus.course_slots`
3. `titus.course_lesson_placements`
4. `titus.course_lesson_prerequisites`
5. `titus.course_teachers`
6. `titus.course_slot_activity_log` (reached through slots)

These six **must be explicitly reviewed** before historical Course-root retirement. The overlap between the 13-relation independent Course closure and the other roots also prevents blindly attributing all descendants to the old Courses.

The U1.14 pure-source checker now freezes this **second structural calculation** separately: 39 for the initial three roots, 45 for the four-root extension, with exactly these six added relations. A future changed dependency must block review rather than silently shrink the old-course retirement coverage.

## Still blocked pending independent owner action

1. Exact record-level selection and dependency-closure review: 15 named old Course shells versus other Course rows and shared sources; the old McMillan Program/Formation source separately; six protected original customer relations preserved exactly.
2. Owner-selected **persistent private vault** beyond ephemeral runners/temp files, an appropriate encryption certificate, a privately held and independently recoverable decryption key, and off-device restored-recovery evidence.
3. Separate new owner-authorized **customer-data read** for consistent encrypted historical capture; independent real-data PostgreSQL restoration and byte/identity/receipt checks.
4. Review of retain/migrate/retire outcomes; only then independent owner-approved `DROP ... RESTRICT` release. Never use cascade as a shortcut.
5. Coordinated Titus #72 consumer cutover and Noel #2617 canonical same-Course source remain separately held.

This receipt does not claim that a backup, completed row manifest, actual Course migration or enrollment exists. No production records, grants, SQL schema or application deployment were changed.
