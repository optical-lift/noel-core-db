# Atlas original personal task amendment — SOURCE CANDIDATE ONLY

Owner: Noel atlas_ structural release lane. No production deployment or personal Task Focus feature results from this draft.

The authenticated established Principal may change sentence (1–500 characters), due date, or both for exactly one open, unarchived original task, when the signed expected amendment revision still matches. Owner user ID, Principal, task ID and initial create-action identity are unchanged. The writer locks the task row and forbids edits after the original has been linked to Company Work. Promotion also locks that row.

An interrupted request may be retried against its original expected revision: when the locked row has moved exactly one revision, the requested state matches, and a matching previously recorded event exists, the signed writer returns the original event ID and old date with `idempotent=true` rather than applying a second change. A conflicting/staler edit is rejected. The rejection uses `PT409` (HTTP 409 conflict), not PostgreSQL serialization SQLSTATE `40001`, so the signed HTTP gateway does not retry an ordinary stale request. Each original revision admits at most one event, enforced by a unique constraint.

A new amendment event is written only for a changed task. Private events have no direct table grants and use RLS. Permanent deletion of the original cascades its private amendment text history. A no-op creates no event.

The explicit source-only PR workflow executes this candidate's Node assertions. The synthetic supplemental fixture at validation/fixtures/atlas_personal_task_amendment_signed_clone_extra_v1.sql is intended to be appended AFTER candidates/atlas_work_self_assignment_native_v1/fixture.sql, inside a disposable full-schema clone. It is not a genuine signed actor test, does not install a migration, and is not sufficient for release.

Release gates: independently reviewed source, governed source generation, full disposable production-schema clone, postconditions, signed GoTrue/PostgREST positive and negative tests, exact receipt, and a separately authorized protected production release. Signed cases must include owner text-only/date-only/both/no-op/stale, other owner, anonymous, locked or revoked Principal, completed, archived and transferred tasks, competing promotion, exact replay versus changed payload/stale revision, old/new day reads, no additional Work, and permanent deletion after amendment. No claimed live success until performed.

Only after the protected source release is verified may Atlas expose editing; the application must fail closed when source capability is absent, reread the original and both old/new daily projections, and keep the same task ID.
