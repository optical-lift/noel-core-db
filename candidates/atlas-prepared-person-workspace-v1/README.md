# Atlas Build 3 — Prepared Person, source-only candidate v1

**State:** review-only SQL candidate. No SQL has been run against production, no migration receipt, no release, no Katie data, no invitation. Build 2 remains draft.

## Owning authority and current slice
- `atlas.prepared_person_cases` is purpose-limited preparation custody, **not** `atlas.implementation_cases`, a paid case, a Person, a Principal or a Ledger.
- `atlas.prepared_person_items` are **indexes to existing** `atlas.evidence_records` with classification and disclosure; they are not a fact/task domain.
- `atlas.prepared_person_decision_receipts` preserves actual recipient decisions as append-only evidence, **not** an accepted obligation or completed act.
- Existing `atlas.require_identity_steward_v1`, `atlas.existing_person_claim_steward_self_v1`, `atlas.current_person_id_v1`, `reality.auth_person_bindings`, `reality.entities`, and `atlas.institutional_person_records` are reused. First slice only grants **verified organization identity steward** authority to prepare a case, and limits existing Person targets to the institution's actual verified Person records **or native Ledger-connected Person seats**, with the same existing signed organization-root stewardship boundary.
- Provisional cases contain a label and no fabricated Person ID. They **cannot be issued** until a separately reviewed identity resolution/claim membrane exists.
- Claimed canonical Person in an issued case can review the recipient-safe current items and append explicit per-item accept/reject/correct/defer receipts. All decisions respond `canonicalEffect:false`. An accepted proposal stays testimony until an authorized owner-domain writer exists.
- Operator and recipient reads are separate RPCs. No cross-organization or invitation-token transport. Underlying new tables have RLS and no direct anon/authenticated access.
- Source provenance and actual author live in `atlas.evidence_records`; permission and disclosure bases are explicit. A public source never implies permission to disclose.

## Not implemented in first slice
- Delegating a scoped preparation case from a steward to a *professional implementation practitioner*. The existing practitioner login cannot become unrestricted identity stewardship.
- Provisional identity reconciliation / Build 2 claim connection.
- Recipient notebook and operator **source implementations are drafted** in [Atlas PR #377](https://github.com/optical-lift/atlas/pull/377), using the shared notebook and these proposed RPCs. They are **not released, deployed, or end-to-end validated**; general in-notebook discoverability remains unintegrated.
- Source-owned promotion into household, program, or Work domains, formal conflict adjudication, institutional event readers, or permissioned connected-source ingestion. This draft preserves conflict links, not an adjudication engine.
- Raw source locators remain held in operator-only evidence custody; the recipient safe projection returns source class and the authored observation, **not** unrestricted original source locators. A source-owning recipient disclosure reader requires separate review.
- Compulsory multi-user signed acceptance suite; by user's 2B decision, combined tests run after Builds 3–5. Source, clone and isolated negative-permission testing are required **before even this candidate can become a numbered migration**.

## Release and validation gates
1. Security review of case-level steward authority, `atlas.evidence_records` read policies, cross-organization privacy and the effects of revoked stewardship.
2. Syntax/DDL and Postgres catalog check in a disposable production-schema clone, including correct function signatures, grants and RLS. **Not yet run.**
3. Signed disposable actor tests: steward / other operator / unrelated Person / actual recipient; verify private withheld material cannot cross the recipient projection, cannot read another case, and cannot write another domain.
4. Duplicate Person and idempotent request tests; immutable revision/decision history; concurrency and contradictory source replay.
5. Release with exact source custody through canonical generated `atlas_` migration, not direct production SQL.
6. Wire governed Atlas notebook workbench and recipient projection only to released RPC contracts.
7. Preserve Build 2 draft and all existing canonical identity/institutional reality while preparing.

The `candidate.sql` file is a design **proposal**, not evidence that any of those gates passed.
