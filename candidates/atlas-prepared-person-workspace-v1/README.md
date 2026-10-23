# Atlas Build 3 — Prepared Person, source-only candidate v1

**State:** review-only SQL candidate. No SQL has been run against production, no migration receipt, no release, no Katie data, no invitation. Build 2 remains draft.

## Owning authority and current slice
- `atlas.prepared_person_cases` is purpose-limited preparation custody, **not** `atlas.implementation_cases`, a paid case, a Person, a Principal or a Ledger.
- `atlas.prepared_person_items` are **indexes to existing** `atlas.evidence_records` with classification and disclosure; they are not a fact/task domain.
- `atlas.prepared_person_decision_receipts` preserves actual recipient decisions as append-only evidence, **not** an accepted obligation or completed act.
- `atlas.prepared_person_operator_grants` is an explicitly delegated, revocable professional case authority with independent switches for issue permission and organization-event inspection. It does **not** turn a professional login into an institutional identity steward.
- Existing `atlas.require_identity_steward_v1`, `atlas.existing_person_claim_steward_self_v1`, `atlas.current_person_id_v1`, `reality.auth_person_bindings`, `reality.entities`, and `atlas.institutional_person_records` are reused. First slice only grants **verified organization identity steward** authority to prepare a case, and limits existing Person targets to the institution's actual verified Person records **or native Ledger-connected Person seats**, with the same existing signed organization-root stewardship boundary.
- Provisional cases contain a label and no fabricated Person ID. They **cannot be issued** until a separately reviewed identity resolution/claim membrane exists.
- Known-Person case reads retrieve **existing** `ledger.seats`, `atlas.organization_occurrence_bindings` / `local_intel.occurrences`, and `atlas.work_allocations` / `atlas.work_items` under the original Organization and exact-Person relationship. These are read-only source references; the preparation case cannot claim attendance or completion. Practitioner access to unrelated organization-wide event context requires a separate explicit case grant.
- Claimed canonical Person in an issued case can review the recipient-safe current items and append explicit per-item accept/reject/correct/defer receipts. All decisions respond `canonicalEffect:false`. An accepted proposal stays testimony until an authorized owner-domain writer exists.
- Operator and recipient reads are separate RPCs. No cross-organization or invitation-token transport. Underlying new tables have RLS and no direct anon/authenticated access.
- Source provenance and actual author live in `atlas.evidence_records`; permission and disclosure bases are explicit. A public source never implies permission to disclose.

## Not implemented in first slice
- General authorization to the professional implementation Workbench's entire corpus. Only explicitly case-granted professional credentials can read and write a preparation case; the professional connection does **not** become an unrestricted steward. In-source delegation is drafted, not clone-tested.
- Provisional identity reconciliation / Build 2 claim connection.
- Ordinary Atlas Index source-gated links, recipient notebook and operator **source implementations are drafted** in [Atlas PR #377](https://github.com/optical-lift/atlas/pull/377), using the shared notebook and these proposed RPCs. They are **not released, deployed, or end-to-end validated**; general in-notebook discoverability remains unintegrated.
- Source-owned promotion into household, program, or Work domains, formal conflict adjudication, institutional event readers, or permissioned connected-source ingestion. This draft preserves conflict links, not an adjudication engine.
- Raw source locators remain held in operator-only evidence custody; the recipient safe projection returns source class and the authored observation, **not** unrestricted original source locators. A source-owning recipient disclosure reader requires separate review.
- Compulsory multi-user signed acceptance suite; by user's 2B decision, combined tests run after Builds 3–5. Source, clone and isolated negative-permission testing are required **before even this candidate can become a numbered migration**.

## Release and validation gates
1. Security review of case-level steward authority, `atlas.evidence_records` read policies, cross-organization privacy and the effects of revoked stewardship.
2. Syntax/DDL and Postgres catalog check in a disposable production-schema clone, including correct function signatures, grants and RLS. **Not yet run.**
3. Signed disposable actor tests: steward / delegated practitioner / unassigned practitioner / revoked practitioner / unrelated Person / actual recipient. Verify private withheld material cannot cross the recipient projection; original source locators never leak to the recipient; delegated issue/event-inspection switches are independent; case-grant revocation is effective even if the original grant persists as history; and no actor can write another domain.
4. Duplicate Person and idempotent request tests; immutable revision/decision history; concurrency and contradictory source replay. The exact identical practitioner grant retries without enlarging permission; a changed grant requires revoke then new grant.
5. Release with exact source custody through canonical generated `atlas_` migration, not direct production SQL.
6. Wire governed Atlas notebook workbench and recipient projection only to released RPC contracts.
7. Preserve Build 2 draft and all existing canonical identity/institutional reality while preparing.

The `candidate.sql` file is a design **proposal**, not evidence that any of those gates passed.

## Read-only live source preflight (2026-10-23)

Confirmed by Postgres catalog inspection (no writes): all four proposed prepared-Person custody tables are absent in the active database; existing `atlas.evidence_records`, `atlas.implementation_practitioners`, `atlas.work_allocations`, `atlas.organization_occurrence_bindings`, `local_intel.occurrences`, `ledger.seats` and the exact Person/steward helper functions exist. A separate source-level invariant inspection checked 14 categories including RLS declarations, actor separation, restricted event inspection, no Person/Work-domain insertions, and fail-closed provisional case issue. **These are not syntax, schema-clone, RLS-runtime, or session proofs.**
