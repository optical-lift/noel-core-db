# Atlas — ordinary comments on one original Work (source candidate)

**Status:** Held, source-only; **not a migration**, **not installed in Noel Production**, **not a released Atlas feature**. November 13, 2026.

## Bounded outcome and source owner

Issue [Atlas #481](https://github.com/optical-lift/atlas/issues/481): a person's ordinary note about the bonfire hose did not persist as a readable coordination update. The existing `CanonicalWorkFocusUpdates` intentionally creates signed Work **Results** (`completed | partial | blocked | unable`), not comments. Neither Results nor unrelated Event progress messages may be reused as ordinary Work comments.

Noel owns persistent comment identity, author, exact original Work relationship and authenticated reader/writer admission. Atlas owns its Work Focus presentation and locally preserved draft. Neither should invent another Work, change responsibility, mark Done, infer notification delivery, or auto-email a co-worker.

This candidate adds exactly one private append-only `atlas.native_original_work_comments_v1` source and two public authenticated-only envelopes:
- `append_native_original_work_comment_self_api_v1(organization,ledger,work,sourceActionId,body)`
- `read_native_original_work_comments_self_api_v1(organization,ledger,work,limit?,afterRecordedAt?,afterCommentId?)`

A signed saved comment retains a canonical UUID, server timestamp, exact author Person ID and 1–2,000-character body, unique actor-scoped action ID, and an immutable original history. The write reply explicitly asserts that **Work Result=false**, **original Work unchanged**, and **notificationDelivered=false**. A retry uses the same action UUID and body; a collision with different body fails. A read is bounded, cursor-paginated, scoped to one current original Work; `authoredBySelf` distinguishes one's own ink. Another participant's name is **not** exposed without a separately governed Person identity-disclosure proof, although the source preserves exact author ID.

## Protected authorization

Every read and write requires the current signed Reality Person, exact Organization and native Ledger, the current original `atlas.work_items` row and the established `company_work_native_ledger_relevance` with its exact source proof. A Person's unverified Ledger seat or title match does **not** grant comment access. Either native Ledger root governing authority or an exact currently responsible or receiver-accepted participating allocation is required. Connected People also need current native Ledger connection, original Work identity disclosure, and exact linked Event identity disclosure where relevant. Other unclassified subject-link families remain denied. Writing requires the **open** original Work; authorized reading may continue on a completed Work through the existing completed-responsibility evidence. No access derived from mere organization membership, old farm role, the Event's date, a work-list count, or the front-end route.

All data remains in private `atlas` table with RLS enabled, no browser table grants, immutable-row trigger, and no public execute on the internal helpers. Only `public.` wrappers are executable by `authenticated`; anonymous users get no RPC. The wrapper re-evaluates authority on **every** read, retry, and write, so saved ink does not override later revoked access.

## Required evidence before release (NOT yet obtained)

1. **Grammar & source checks:** existing database custody PR grammar script parses this `candidates/atlas/*/candidate.sql` and postconditions. Run `postconditions.sql` only in an authorized local disposable clone **after** candidate source, checking table access, RLS, versioned APIs, immutability trigger, and internal/public ACLs.
2. **Genuine signed source test in protected throwaway database:** current governor, current responsible worker, distinct accepted participant, unrelated Person, former participant, wrong Organization/Ledger, undisclosed linked growing object and Event, unauthenticated reader/writer. They must independently prove allow/deny; **do not impersonate** real People. Verify Work identity and state unchanged, no Result or delivery events, immutable body, idempotent same-key replay and different-body 23505. Test completion/readback and concurrent action collision.
3. **Atlas UI source-integration:** fail closed when the RPC is absent/denied; no comment compose control while unavailable. Display real signed readback in the task body without refresh disappearance or duplication. Preserve draft on failed save, same idempotency key on retry; do not label it "message sent".
4. **Owner + consenting participant browser acceptance** on a legitimately available original Work in protected Preview; verify writer and independent authorized reader, refresh/return, unrelated denial. No fake real-world note or Done.
5. **Separate owner-reviewed Noel schema release** (CLI-generated migration and signed source-clone), then Atlas review, merge and governed release. This candidate authorizes **none** of those Production actions.

### Known held boundaries

- No public Person-name roster or identity display is released by `authoredBySelf`.
- The initial writer is not a universal chat or notification transport. Ordinary comments may be restricted by other Work subject types until classified.
- Pending protected signed parity means SQL/function semantics and exact current-schema compatibility are **not proven** by source-only syntax validation.
- W09 two-Person Result receipt, outsider onboarding, legacy view retirement and E05 remain independent.

**Next unfinished:** obtain the real signed disposable-clone allow/deny matrix on this exact source; only then is a working Atlas comment-entry surface eligible for real-user testing.
