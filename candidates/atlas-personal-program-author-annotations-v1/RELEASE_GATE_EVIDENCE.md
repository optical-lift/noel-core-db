# Atlas author-private Program annotations — release-gate evidence packet
Status: draft source; no production migration generated or executed.
Review target: Noel PR #2239 (source only); consuming application: Atlas PR #455.
Project: `zirqkouammpwxlqfbsvf`. Release lane: `atlas`.

## Source identities
- SQL candidate: `candidates/atlas-personal-program-author-annotations-v1/candidate.sql`
- Data-only fictional fixture: `candidates/atlas-personal-program-author-annotations-v1/fixture.sql`
- Protected clone postconditions: `candidates/atlas-personal-program-author-annotations-v1/postconditions.sql`
- Isolated PG16 contracts: `validation/atlas-program-author-annotations-isolated-v1/`
- Genuine local signed auth probe: `scripts/validate-atlas-program-author-notes-signed-http.py`
- Governed clone adapter: `scripts/validate-production-schema-clone.sh`; note-specific activation ONLY when candidate migration basename is `<14-digit>_atlas_personal_program_author_annotations_v1.sql`.

## Source checks actually executed
- PG16 candidate schema/function SQL, table RLS and private/public grants, author-bound create/revise/read, invalid source anchor, approved Program packet unchanged.
- Fictional simulated-role other/unentitled/anon denials (not equivalent to authenticated HTTP).
- Concurrent independent database transactions: identical request key produces one note; competing revision with same expected number produces one success/one stale conflict.
- Newest 200 out of 209 source notes, explicit global truncation and latest 50 out of 52 revisions with per-note `historyTruncated`.
- Exact signed-probe source Python compilation, bash syntax and data-only clone fixture admissibility checked in candidate CI.
- Database Custody CI passed. Attach exact head SHA and run IDs from GitHub PR checks before final source signoff.

## Independently signed test prepared but NOT executed
On a true **disposable production-schema/role clone**, run local Supabase Auth+REST and:
1. three separate signed GoTrue logins for fictional Program author, other eligible author and unbound user; prove each `session_id` exists in local `auth.sessions`;
2. verify other user with spoofed `user_metadata.is_owner` cannot read/create/revise the author's note;
3. ensure anonymous/unbound principal denials are genuine, not missing endpoints;
4. create Program v2 source and approve one immutable version before note creation;
5. reject wrong version, invented quote, conflicting duplicate request, stale revision;
6. create/revise/replay one note and read back append-only 1→2 history, correct source key and approved version;
7. prove Program draft and immutable approval bytes unchanged;
8. revoke the author's server-side Personal Atlas grant **without refreshing the JWT** and verify note read/create/revise and original Program source reader are all denied.
The signed probe refuses any remote URL and must never be run against live source or users.

## Blocker and allowed next order
The canonical protected schema-clone workflow is triggered by an **owner-authored issue referring to an already generated 14-digit migration file**. It cannot validate a draft candidate `candidate.sql` as a fake migration name.

The repository's owner must review the actual candidate and source-only evidence; the candidate may then be source-merged through the permitted lane. Next follow `docs/GOVERNED_MIGRATION_SOURCE_GENERATION.md` using an immutable already-merged candidate SHA; review the generated migration PR. After generating the migration and providing the correct clone-only fixture/postcondition files, the owner can trigger `docs/PRODUCTION_SCHEMA_CLONE_VALIDATION.md`. **Do not skip the signed probe in that run.** A passing clone is still not a production release.

If owner policy requires signed evidence before candidate-source merge, the repository needs an owner-approved **pre-generation protected clone test entrypoint** instead; do not fabricate a timestamp or source receipt to satisfy the existing workflow.

Only after documented source/clone/signed owner acceptance may the separately authorized `docs/PRODUCTION_DATABASE_RELEASE.md` manual production issue/workflow be considered. Atlas UI browser acceptance is later and independent. No source disclosure or recipient grant is implied by private notes.

## Stop conditions
- source SQL not identical to reviewed and staged version;
- independently signed denial relies on 404/missing route rather than authorization;
- original approved Program packet mutated, or a note becomes visible via a recipient reader;
- fixture imports real user/program data;
- a release requires a paid Supabase development branch;
- another build simultaneously owns the operational Subject/Need/Rhythm/Work or effective recipient disclosure decisions.
