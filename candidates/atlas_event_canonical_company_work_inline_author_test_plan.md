# Atlas Event → original Company Work — Build 2 verification packet

**Status: source-only candidate; not executable production migration.**
Source: `candidates/atlas_event_canonical_company_work_inline_author_v1.sql`.
Governance: `optical-lift/noel-core-db` owns structural SQL and grants; Atlas consumes a read/write membrane, never clones a task.

## Exact semantics
Writing a sentence inside a bound canonical Event creates a **single ordinary original `atlas.work_items` record**. The Event is a context relationship, the Ledger is a native relevance relationship; neither creates a second Work item. A real connected Person is the author, but **not automatically the responsible worker**. Initial responsibility and date are absent. The same ordinary `worker_attestation` result contract governs eventual first-person progress/completion. The original can be assigned via already-governed Event responsibility commands.

## Required disposable-schema-clone tests
1. Actual signed in native Ledger Person and exact active Organization/Ledger/Occurrence → create one original open `work_items` row with ordinary result policy, one bound contract, one native Ledger relevance, one occurrence context, no allocation, no execution plan, no due date.
2. Same action ID with same payload after a lost response → identical Work ID, `createdNow=false`, no extra row or link, and correct current state.
3. Same action ID with altered sentence → reject, do not duplicate or mutate original.
4. Different action ID, same sentence → distinct explicitly authored original Work only when human actually chooses a new action.
5. Two simultaneous requests with the same action ID → serialize and return one original Work ID.
6. Connected Person without Organization-owner role may author; they may **not** gain owner reassignment or read unrelated private Ledger Work as a side effect.
7. Authenticated person without native Ledger connection → reject. Person with wrong Event, wrong Ledger, wrong Organization, or inactive Occurrence binding → reject. Anonymous → no function EXECUTE.
8. Name collision / mis-resolved Occurrence does not create a duplicate Event or external-world Person.
9. A task created this way appears in the existing original Event Work read and original Work Focus without a second identity; a subsequent owner connected-Person assignment reuses exactly this Work ID. Verify owner can give responsibility without a per-task offer under lawful direct-obligation rule.
10. Responsible signed worker can read, record first-person progress, and finish original Work according to ordinary accepted result contract. Writer does not mark Work Done itself.
11. Removing its Event association must **not** silently delete or cancel underlying Company Work, particularly if another relation, result, allocation, or plan exists.
12. Child Work dependency or bundle triggers, ledger completion projection, replay receipt and existing legacy Event-only checklist state remain coherent.
13. Retry after work was assigned/finished does not create a second Work or invalidate historical source identity.
14. RLS and schema usage: authenticated only; `anon` and PUBLIC EXECUTE denied on internal and public wrappers. Test browser-facing PostgREST with real signed independent owner/worker/outsider sessions, not service-role impersonation.
15. Test Word/Punctuation/Unicode sentences (1–500 characters) and empty/oversized/whitespace titles. Injection strings remain data, never executable SQL.
16. Current Event UI: a new task is immediately addressable as original Work; focus opens it for assignment; cross-user rereads show the new Work only where permitted, no full application reload needed.
17. Mobile notebook composer works without pill explosion or an invented event date.
18. No paid Supabase branch, real Harvest Party mutation or extra task during test. Use synthetic local schema fixtures only.

## Required pre-release decisions
- `source_object_type` is deliberately NULL and the Event is referenced through original context plus source metadata. Confirm legacy Event extension treats it as original Work without promoting Event-only checklist authority.
- `company_work_result_contract_bindings_v1.actor_membership_id` accepts NULL; creator remains canonical Person, not a manufactured employee/member.
- Ensure `sourceContract='event_canonical_company_work_v1'` is admitted by source guards and the selected read projections.
- Confirm a new unassigned task does not silently appear as owner Today obligation.
- Coordinate with Noel owner-recorded completion draft #2246, and the existing Event migration custody on current `main`, before generating any new `atlas_` migration.

## Separate release gates
1. Schema-clone + authentic signed role tests and real receipt IDs from **synthetic** fixtures.
2. Source/security review, then reviewed candidate under canonical `noel-core-db` migration generation from main.
3. Protected manual schema release after exact custody proof.
4. Atlas UI application CI, signed mobile/desktop browser proof and explicit manual Production release.
5. Store per-actor/Work outcome privately, not in public fixtures or GitHub comments.

No tests are claimed passed by this plan itself.
