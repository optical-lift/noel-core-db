# Atlas Build 1/5 — Company Work / native Ledger custody (candidate v1)

**Stage:** draft source contract only, NOT a deployed migration or RPC.  
**Authority decision:** owner approved separate `owner_attested` relevance and `source_verified` attribution, without converting either into the other or backfilling historical Work (October 17, 2026).  
**Source owner:** `optical-lift/noel-core-db` candidate, eventual `atlas_` migration lane. Atlas app and People UX are NOT part of this tranche.

## 1. Observed source truth

- Company Work identity: `atlas.work_items.id`; owning institution: `work_items.organization_id`; optional operating-unit locus: `organization_unit_id`. Assignment/schedule/result are distinct domains.
- `ledger.ledgers` is the native notebook Ledger. `atlas.ledgers` is the older institutional graph; matching UUIDs are compatibility routing only. `atlas.ledger_organization_participations` proves active Organization/Ledger participation, **not** Work attribution.
- `atlas.work_item_context_links` currently permits spatial/identity links only; it cannot be repurposed silently as Ledger attribution.
- Live scan: 154 Company Work rows in Elm Farm Organization (151 Elm unit: 77 open, 55 completed, 19 cancelled; 3 Waiting Room unit: 1 open, 2 completed). No proven Work→native Ledger relation.
- Native `ledger.booking_requests.ledger_id` and `ledger.booking_offerings.ledger_id` are real source-owned FKs. They support an exact verification route when the Work item explicitly names that native source object by type + UUID. Current Work contains **zero** such source types, so none can be silently source-verified.
- Native keys in current live sample: `elm-farm:flower` and `elm-farm:venue` participate in Elm Farm; `optical-lift:agency` participates in Optical Lift. A Ledger seat is participation, not owner authority.

## 2. One obligation; two independent evidence tracks

`atlas.company_work_native_ledger_relevance` is a **relationship record**, not a new task, assignment, or human identity. Composite active uniqueness: `(work_item_id,ledger_id,evidence_kind)`.

**`owner_attested` (owner-established relevance)** means: the signed-in authorized institutional owner affirms that this Work serves the selected Ledger purpose. The command requires a `sourceRef` and `reason`. These are preserved as an attestation; they are not converted into an FK, independently verified by AI, or presented as source fact. The asserted relevance may be corrected through a reasoned withdrawal.

**`source_verified` (exact database attribution)** means: the database found an actual allowlisted native source row whose `ledger_id` equals the selected native Ledger and whose `id` equals the Company Work row's canonical typed `source_object_id`. Only the server constructs `source_schema`, `source_table`, `source_id`, and `verified_at`. No client-supplied proof JSON, label, Organization membership, Work title, legacy farm task, or owner attestation is enough. The initial allowlist is:
- `work_items.source_object_type='ledger_booking_request'` → `ledger.booking_requests.id` and `ledger.booking_requests.ledger_id`
- `work_items.source_object_type='ledger_booking_offering'` → `ledger.booking_offerings.id` and `ledger.booking_offerings.ledger_id`

A Work/Ledger pair may have one active attestation **and** one active source verification simultaneously. Establishing either leaves the other evidence unchanged. The RPC never upgrades one row's evidence kind. Repeating verification is idempotent only when the existing evidence identifies the same source schema/table/UUID; a different current source fails closed and requires reasoned withdrawal of the historic assertion before a new verification can be recorded. Both share the one original Work ID. They are two different reasons for relevance, not two tasks.

Lifecycle is separate from epistemic evidence: `attribution_state=active|withdrawn`. Withdrawal preserves immutable source/evidence/actor and history. A source-verified row is historical evidence of verification at `verified_at`; the read recomputes `currentSourceProof` from the exact source rows. If source proof disappears or changes, the record is still visible but `currentSourceProof=false` and it **must not establish current effective scope** without a separate active owner attestation. Lack of a link is unknown, not proven exclusion. Association with Flower does not rule out Venue.

## 3. Source rules, unknowns and external service

| Input reality | Candidate result |
|---|---|
| Owner explicitly affirms Elm work serves Flower | one `owner_attested` Flower link |
| Same work also serves Venue | second `owner_attested` Venue link, **same work_id** |
| Exact native booking request/offering is its typed Work source | one `source_verified` link after FK check |
| Later source deletion/change | stale historical verification; no current source proof |
| Both proof types exist | two active evidence records, one Work row in Ledger read |
| Generic Elm/Waiting Room unit or work title implies flower/venue | **unknown**, no automatic designation |
| Optical Lift has an internal task implementing Elm client promise | Optical Lift still owns that task; Elm requires separately established consented service commitment/result publication, not cross-company task exposure |
| Wrong attestation | withdraw with reason, preserving Work and evidence |

No institutional permissions are inferred from a shared Organization or matching native/legacy Ledger UUID. The candidate allows only current governing/operating Ledger participation for the Work Organization. It does not cover intercompany shared work. Future service agreements need an independent authority membrane.

## 4. Guarded candidate API

| Candidate object | Authority/meaning |
|---|---|
| `atlas.company_work_native_ledger_relevance` | work ID + native Ledger relevance evidence/history |
| `atlas.company_work_native_ledger_exact_source_v1(uuid,uuid)` | private exact native FK source proof; no text lookup |
| `atlas.guard_company_work_native_ledger_relevance_v1()` | preserve parent Organization, participation, immutable evidence |
| `atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)` | current session + canonical Person + Principal + native seat + both governing roots |
| `atlas.establish_company_work_native_ledger_relevance_self_api_v1(uuid,uuid,jsonb)` | owner attestation only; cannot supply source-verified evidence |
| `atlas.verify_company_work_native_ledger_source_self_api_v1(uuid,uuid)` | verifies allowlisted native FK and records independent `source_verified` evidence |
| `atlas.withdraw_company_work_native_ledger_relevance_self_api_v1(uuid,text)` | reasoned withdrawal, no task reassignment |
| `atlas.company_work_native_ledger_scope_self_api_v1(uuid,uuid,integer,uuid)` | one row per Work ID, nested evidence records, `has_current_scope` and Organization unknown count |

V1 browser calls require the caller's current authenticated Atlas session; `atlas.current_person_id_v1` / `current_principal_id_v1`; an active native Ledger seat; root authority over that Ledger **and** over the Work Organization's unique primary governing Ledger. Initial writer/read audience is conservative root owner only. The candidate adds **no** manager/worker access by title/seat alone. Direct reads/writes to new table and private helpers are revoked; authenticated access is through narrowly gated RPCs. The two positive writers are both independently privileged and proof-class specific.

## 5. Validation and release gates

Candidate SQL: `candidates/atlas_company_work_native_ledger_relevance_v1.sql`.  
Clone checks: `candidates/atlas_company_work_native_ledger_relevance_v1_validation.sql`.  
**Staged (not released):** `supabase/migrations/20261017170000_atlas_company_work_native_ledger_relevance_v1.sql` and `validation/migrations/20261017170000_atlas_company_work_native_ledger_relevance_v1.sql` on draft PR #1675. The canonical migration is only source staged; a released migration is one that has passed clone gates and the protected production release process. No live migration receipt currently exists.

Checks require zero initial link rows; direct table SELECT/INSERT/UPDATE denied; RLS; anonymous RPC denial; helper RPC denial; separately granted gated commands; source resolver failure on missing source; distinct pair+evidence uniqueness. This validation must run against a **disposable clone**, never production. A successful PR custody CI does not execute migration SQL and is **not** proof of PostgreSQL execution.

**Still required before a migration is promoted:** identity-bound *positive and negative* authenticated fixture tests (authorized Elm owner; wrong Org, seat-only, lost session, false source ID, dual-Ledger same work, both evidence kinds, stale source proof, withdrawal immutability); schema clone lint; security review of `SECURITY DEFINER` RPC grants; source FK semantics review; canonical timestamped migration generation and protected DB release. Run through existing `docs/PRODUCTION_SCHEMA_CLONE_VALIDATION.md` workflow only after correct migration/lane preparation and explicit release steps. No source merge or CI status is a production deployment.

## 6. Conversation 2 handoff (conditional)

Only after tested DB release: use `work_item_id` as the one Company Work identity; `organization_id` and `organization_unit_id` as institution/locus; native `ledger_id` as authorized Ledger relevance; `evidence_kind` and `currentSourceProof` as independent source statuses; `has_current_scope=false` as unresolved relevance. Do not derive a human/role/employment from this relation. Anna/People/Worker Day are later steps. **No historic work, institution, worker, assignment or result changed in this candidate PR.**

At the audit: 154 existing work items remain without established native Ledger scope; three of them have Waiting Room unit locus and must be reviewed separately. Optical Lift employee work remains private to Optical Lift; a contract to publish Elm-facing obligations is unresolved. Confirm actual data again before Conversation 2.
