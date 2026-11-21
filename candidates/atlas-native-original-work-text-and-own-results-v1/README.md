# Native original Work text and own-result readback — candidate

**Status: DRAFT / NOT DEPLOYED.** Atlas usability Bugs
[481](https://github.com/optical-lift/atlas/issues/481) and
[486](https://github.com/optical-lift/atlas/issues/486), within
[Noel universal Work specification #2359](https://github.com/optical-lift/noel-core-db/issues/2359).
No production SQL, records, actor permissions, or held lifecycle PRs are changed.

## Scope

One original `atlas.work_items.id` throughout; no replacement Work,
fake acceptance, parallel task store or result mutation.

- **Owner detail:** read title/instructions, state, `updated_at` from exact
  original native Atlas-authored Ledger/Event Work.
- **Owner edit:** exact owner with both existing native/institutional governing
  roots + active owner membership + exact original Work/Ledger provenance.
  Open Work only. Edit title/instructions *on that row*, with immutable,
  signed person/user, before-and-after audit event and optimistic stale-version
  rejection (`40001`); no forced prose reason. Source-managed legacy,
  production, medical, household and unproven Work are rejected.
- **Signed own report history:** same narrow owner scope. Read only Result
  entries whose `reported_by_user_id=auth.uid()`; return Result ID, kind,
  timestamp and `payload.note`. **Other workers' private payloads never
  leave the source.** No claim of worker/participant access or message delivery.

Two native source types initially admitted:
`ledger_occurrence_shared_work`, `ledger_connected_direct_task`.
A direct current-data count shows these correspond to a meaningful native
Event/connected Work slice, but no signed actor acceptance has yet run.
The ledger-relevance check mirrors the native owner accountability read.
No automatically mirrored change to external source titles is inferred.

## Delivery / source custody

`candidate.sql` is proposed SQL. New objects are all private
`atlas` objects except three narrowly signed `public` RPC membranes.
The browser has no table DML or audit table SELECT permission.
`postconditions.sql` is a **structural and negative-auth** check,
and **cannot be counted as a real signed governor/worker test**.

Before migration/release:
1. Run rollback-only against real-sourced schema clone with strict PGDATA/
   database/source SHA verification. Do not point a runner at production.
2. Confirm `work_items(organization_id,id)` unique key, trigger effects,
   and existing native relevance functions with exact deployed schema.
3. On disposable **real-object** copy: owner read/edit/own-result and fresh
   readback; same result without another Work; stale concurrent edit rejected;
   audit immutable; non-owner, unrelated Person, revoked access, other Ledger,
   household, legacy and unknown source denied. No 404 counted as a denial.
4. Test signed connected worker **not** granted edit and not granted
   another reporter's Result narrative; decide worker-owned, collaborator
   and governor-shared disclosure in separate source-reviewed slice.
5. Only then create a normal Noel migration from this candidate through
   release custody and align the Atlas UI PR; no direct live SQL.

## Explicit remaining work

This is NOT a general Result conversation/history reader. Katie receiving
the governor's bonfire note requires a **separately authorized append/read
Work comment channel** with original Work/Event relation and precise field
disclosure. Worker-reported Result payload privacy needs a decision before
owner/other worker reads. A signed source for existing `legacy_task` text
amendments also requires its own provenance audit rather than silently
translating it into native Work.

No Atlas UI can truthfully claim this candidate is live until Noel release
and a signed, reloaded real browser proves original title, instructions
and written evidence persist.
