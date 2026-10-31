# R02: delegated original-Work assignment — source boundary

**Date:** October 31, 2026, America/Chicago. **Outcome: BLOCKED on a missing native grant lifecycle.** This is a source inspection and negative-authorization increment on held PR #2435, not delegated assignment implementation or production authorization.

Continuation: [Atlas completion register, R02](https://github.com/optical-lift/atlas/blob/docs/atlas-completion-register-reconciliation-20261031/docs/integration/ATLAS_INTEGRATION_COMPLETION_REGISTER.md#r02--next-coding-unit-not-started-one-delegated-original-work-assignment-operation). The round permits one existing original-Work operation; it explicitly queues additional grant machinery as a separate dependency. Do not enlarge a root resolver or borrow an unrelated grant to make the operation succeed.

## Inspected state and owning seams

Reviewed Noel main `bb067d1eec201cc5dc0e411e7da771122f2aee2c` and held #2435 base `59c3418f7a4a0ffbfc4f1af8f134abcb9a1a032a`. Read-only production **catalog/function-definition** inspection confirmed the following shapes on October 31. No user/business rows, source permissions, grants, schema or migrations were mutated. The catalog inventory is not a signed actor test or a complete audit of all historic authority systems.

| Existing source | What it actually authorizes | Why it does not supply human assignment delegation |
| --- | --- | --- |
| `atlas.company_work_native_ledger_owner_self_v1(org,ledger)` | Current Atlas session, canonical Person/Principal, exact active native seat and Organization participation, plus the same Principal's current native and institutional governing roots | The assignment writer calls it before looking up the original Work. It does not accept a nonroot delegate. Changing this shared helper would widen many independent readers/writers, outside this round. |
| `atlas.principal_ledger_authorities` | `authority_kind='root_governing'` only, enforced by a live CHECK | Adding a row promotes a root; it is not a bounded assignment permission. |
| `atlas.company_work_standing_assignment_scopes` | Another Person's separately proposed/accepted responsibility for Work | Consent to carry Work does not grant authority to allocate Work to someone else. Preserve `respond_native_ledger_standing_scope_self_api_v1`. |
| `atlas.company_work_adjudication_authority_grants` | `authority_kind='result_acceptance'` only; present target is Organization-membership-bound | Result acceptance is not assignment. Do not reinterpret its operation, revive membership authority or broaden its CHECK. |
| `atlas.principal_authority_allocations` / `principal_upsert_authority_allocation_api_v1` | Principal/portfolio operating allocation; existing writer requires an active Organization membership and does not prove the requested exact Ledger grant | Not a native Person assignment-delegation command. Labels/scope JSON are not sufficient evidence for this writer. |
| `atlas.delegated_agent_authorizations` and credential/command kernel | Automated carrier, token, command class and target scope | An agent carrier is not the independently signed human Person receiving Ledger authority. No carrier impersonation or service credential substitution. |
| `reality.responsibility_relations` / `resolve_responsibility_relation_v1` | Existing bounded Person + jurisdiction + explicit operation set, used by other institutional operations | A potential reusable primitive, not an already established signed native assignment grant. The inspected current catalog has no authenticated INSERT/UPDATE on the table and no identified signed grant/revoke writer for this operation. Do not fabricate a private service-inserted row and call it governor approval. |

Source pointers: existing owner and allocation checks in [candidate.sql](candidate.sql); [first-class Ledger authority](../../supabase/migrations/20260913190915_atlas_first_class_ledger_v1.sql); [bounded responsibility relation](../../supabase/migrations/20260925141451_atlas_reality_responsibility_authority_v1.sql); [adjudication grant authority](../../supabase/migrations/20260922182354_atlas_company_work_adjudication_grant_root_authority_v1.sql). A catalog keyword search can include read-only functions; it is not proof that each returned name is a writer. The determination above also uses source review and operation semantics.

## Implemented in this increment: exact negative signed cases

The existing localhost-only GoTrue/PostgREST validator now attempts the actual original-Work assignment RPC, requires PostgreSQL `42501` for independently signed denied callers (anonymous uses its own 401/403 admission boundary), and compares before/after hashes of the original Work, allocations, plans, plan events, exact standing scopes and intake, plus global Work/Person/Principal counts. It never logs those fictional record bodies or signed tokens.

- A genuinely signed connected worker has spoofable `user_metadata.is_owner=true` and an independent real root on another Ledger. Neither confers this Ledger's assignment authority.
- That worker cannot change the request's Ledger to their own root Ledger and assign the same accepted original.
- Outsider, unconnected Person and anonymous caller cannot assign the accepted original.
- After the recipient genuinely accepts the exact-Work responsibility scope, that recipient still cannot invoke direct assignment or the governor scope-assignment writer.
- At the end of the fictional disposable test, ending the original root's exact Ledger authority leaves the same real GoTrue session present. The old token cannot replay its earlier successful assignment. No test regrants the authority.
- The earlier positive root direct-unscheduled/idempotent route, independent recipient consent, root assignment, Needs Assignment pagination, blocked Result and no-duplicate cases remain in the same test.

This is **not** the delegated-positive acceptance matrix. Local compilation and static checks do not establish these signed outcomes. The exact protected run/commit verdict must be recorded on the PR and completion register before calling them passed. Product source functions and grant machinery are unchanged by this increment.

## Concrete next dependency, proposed for a separately bounded coding round

**Outcome:** an authorized root can explicitly grant and revoke **one human Person's ability to assign an already accepted original Work in one exact native Ledger**, with a durable source receipt. No other operation is granted.

Reuse current canonical Person, native Ledger, connection and responsibility/authority primitives where their semantics fit. Before choosing storage, verify that grant provenance, immutable decision history, validity, revocation and concurrency can be preserved; this document does not authorize a new universal permission table. Keep new operation-specific grant administration separate from the shared owner helper.

Required contract for that round:

1. Only an independently signed, currently authorized exact-Ledger root may establish/revoke the bounded grant. Prove the legitimate institutional grantor boundary as well as the selected native Ledger; do not promote the delegate to either root.
2. Target is an existing canonical Person with current native Ledger connection. Grant identifies exact Organization, Ledger, operation, grantor, target, validity, reason and idempotent action. Reject unrecognized operation/scope fields rather than accepting an arbitrary permission JSON bag.
3. Granting authority creates no Work, allocation, plan, recipient consent, subject disclosure or notification. The consent mechanism for a responsibility stays independent.
4. Only the specific existing original-Work assignment writer and its exact allocation-integrity guard may later consume that grant. Final intake acceptance, original provenance, eligible target, competing allocation/offer checks and retry provenance still apply. Assignment permission alone cannot schedule, transfer, edit, review intake, enumerate a whole roster or expose private Event/bed context.
5. Ending the grant, target connection, grantor authority or session must deny future assignment and unauthorized retry through the same still-valid token. Exact effective-time and regrant semantics must be defined and tested, preserving history.
6. Signed positive/negative disposable cases: root, actually granted delegate, ungranted/expired/revoked delegate, wrong-Ledger delegate, worker with only responsibility consent, outsider and anonymous. Prove original identity, no competing responsibility, no implicit plan, exact action replay/collision and no private existence/count leak.

**Not implemented here:** a grant/revoke RPC, grant rows, delegate-positive assignment, Atlas capability projection/UI, broad Ledger permissions, all-reader conversion, generated migration, source merge, production release or live Person/Work changes. The next round must explicitly admit the missing grant lifecycle before changing assignment authorization. Keep all other completion-register rows queued.
