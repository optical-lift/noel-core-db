# Native unassigned Ledger Work intake — source-only candidate

**Status:** DRAFT. Not a migration, not executed on Noel production, not a release.
**Depends on:** [Noel P0 #2410](https://github.com/optical-lift/noel-core-db/pull/2410) source-level personnel/compulsory-assignment containment.
**Consumes existing Work:** `atlas.work_items`, `atlas.company_work_native_ledger_relevance`.
**Atlas consumer:** [Atlas #494](https://github.com/optical-lift/atlas/pull/494), follow-up [#493](https://github.com/optical-lift/atlas/issues/493).

## Contract in this candidate

- A signed, canonical Person on one currently active native Ledger may submit a plain title and optional **attention-date proposal** using a replay-stable action. The Ledger must have exactly one active Organization participation; ambiguity fails closed.
- Creates exactly **one original** institution-owned `atlas.work_items`, plus one typed intake state row. The intake is not a second Work/task identity.
- New relevance evidence is `source_verified`, tied to the exact intake/Work/Ledger/Organization and extending the existing Ledger source verifier without removing the booking-request/offering cases.
- Does **not** create responsibility allocations, execution plans, a Person Today placement, recipient selection, employment status or shared Ledger directory.
- Adds private in-product events for every currently active root authority for the exact Ledger. It makes **no** claim that an email, phone alert or browser push was delivered. Source notifications are distinct from `atlas.notification_outbox` (farm/user-specific) and `atlas.ledger_person_dispatches` (Person-targeted).
- Submission status uses a signed caller-only read and returns the original Work ID, intake ID, current review state, title and requested date, not governor identities/counts.
- The Ledger root inbox requires **current, exact-Ledger root authority** on each read. New roots may read the Ledger's Work queue, while revoked roots immediately lose it. Historical queued events are not authorization.
- The intake state is represented independently of `work_state`; no workflow has yet been built that claims review/assignment/decline have occurred.

## Deliberately NOT in this file

The root decision transition (accept / needs details / decline / assign), immutable decision history, an authenticated Ledger inbox interface in Atlas, source-verified recipient display for accepted standing scopes, and notification delivery through external channels remain separate gated implementation. Do not represent a queued inbox event as sent/delivered, or infer an accepted assignment from a submitted Work item.

## Mandatory release gates

1. Compare the exact current `atlas.company_work_native_ledger_exact_source_v1`, original evidence constraint, and `atlas.work_items` triggers against the source-only SQL; fail on drift and preserve existing booking-source behavior.
2. Apply SQL to a **disposable, complete PostgreSQL 17 clone only**, under Noel's repository migration governance. The SQL has not been compiled against that clone. Do not use production Supabase for experimentation or a billed remote branch.
3. Use actual signed identities: Anna-like employee on Elm Flower/Venue; Anna root on an independent Ledger; Lex root on Elm but no inherited power in Anna's Ledger; second independent root; unrelated outsider; revoked worker/root. Call both public facades and atlas source RPCs where exposed. Require real 42501, not RPC 404 or missing function.
4. Assert cross-Ledger/foreign/withdrawn access creates zero new Work, relevance, intake, notification, allocation or plan. Check UUID recipient probing and no names/counts. Verify both root events have exact intake ID and are invisible after revocation.
5. Repeat same action twice and prove **one** Work, relevance, intake and event-per-current-root; conflicting replay rejects without changes. Verify proposed attention date never enters `atlas.work_execution_plans` or personal Today.
6. Run an authenticated Atlas mobile/desktop browser test for source receipt and fresh readback. Confirm only disclosed Ledgers are selectable and no roster is retrieved in network traffic.
7. Review source admission and all Ledger read pathways for withholding, then use a **governed** migration path. No PR merge, migration, live permissions, production data, or Vercel release until those gates pass.

If any stage fails, preserve the original Work/Person/Principal state and return the evidence. Do not quietly switch to a legacy farm inbox or duplicate task store.
