# Atlas Build 2/5 — authenticated institutional People and native Ledger context

**Status:** reviewed candidate source; NOT a production release or Atlas UI. Source owner: `optical-lift/noel-core-db`. Entry authority from released Build 1: `atlas.company_work_native_ledger_owner_self_v1(organization_id,ledger_id)`.

## Existing identity and institution truth

- Human: `atlas.people.id` (Person), not a name, email, title, or credential. Institutional relationship: `atlas.institutional_person_records(organization_id,person_id)`. One canonical Person can appear under distinct Organizations without being cloned.
- Auth account: `reality.auth_person_bindings` / `atlas.person_auth_credentials`, separate from Person. An institution-local `organization_member_credentials` supplies institutional login evidence; a human can exist without it.
- Institutional placement: `atlas.organization_position_appointments.institutional_person_record_id` → `atlas.organization_positions` → `atlas.organization_units`. Organization positions are **not exact native Ledger positions**.
- Position-defined responsibility and scope: existing canonical `atlas.effective_person_organization_responsibilities_current_v2(person_id,organization_id)`; even an established responsibility does not prove an assignment to a particular `atlas.work_items.id`, or any execution warrant.
- `atlas.organization_memberships` is organization participation/access compatibility. `atlas.organization_employee_seats` is organization-paid delivery capacity; native `ledger.seats` is native Ledger participation. Neither grants root authority or an appointment.
- Current transfers already have `atlas.company_work_responsibility_transfer_offers` and owner/send/receiver reply APIs. A transfer **offer is not accepted responsibility**. Build 2 does not replace, automatically invoke, or synthesize these writers. The actual recipient and manager permissions remain with source-specific existing commands.
- Build 1: `atlas.company_work_native_ledger_relevance` proves source-verified or independently owner-attested Work/Ledger purpose, without changing Work ownership.

## Candidate read RPC

`atlas.company_people_native_ledger_scope_self_api_v1(p_organization_id,p_ledger_id,p_limit default 50,p_after_person_id default null)`

Read-only; returns JSON `contractVersion=company_people_native_ledger_scope_v1`, Organization/native Ledger, a keyset-paged list of institutionally established people and `hasMore`/`nextPersonId`. The **owner-only** gate is the already-released Build-1 helper which checks live session, canonical Person/Principal, active native seat, native Ledger↔Organization participation and institutional/native root governing authority. This initial gate is intentional; no unproven delegated manager right is introduced.

Every Person row includes exact stable Person and IPR IDs, established current Organization position appointments and organization units, separately projected position responsibility scopes, current organization membership state, exact native Ledger seat participation when the same canonical Person ID is proved, employee seat readiness, and institutional auth credential recorded state. A Person without an Atlas account remains visible if they have a source Institutional Person Record. Nothing reads `personal.atlases`, private calendar, private support reasons, hidden worker causes, credentials/tokens or unauthorized institutional overlays. Cross-Organization access requires a separately authorized call for that Organization's native Ledger; clients can compose identical canonical Person IDs without text matching.

**Not claimed:** exact Flowers/Venue position from an organizational unit, title, generic membership, participation seat or legacy task; granted delegation from an appointment; Worker Day exposure/result; private Personal Atlas readiness beyond the specific institutional credential evidence; full historical reconstruction. Absent appointments and credentials are exposed as not-proven, never as fabricated records. The same institution roster may be seen when selecting its Flowers and Venue Ledgers, but an institution-wide Person row is not an attested member of both Ledger workforces.

## Owner/manager & delegation matrix

| Actor/source | May read | May write through this candidate |
|---|---|---|
| Authenticated root owner with native seat and both root proofs | Institution People/roles from chosen native Ledger scope | Nothing (read-only) |
| Active native seat only; no root | Denied | Nothing |
| Organization member with no separate Ledger owner proof | Denied | Nothing |
| Other Organization root | Denied unless separately authorized for requested Organization/Ledger | Nothing |
| Invalid/revoked session | Denied | Nothing |
| Non-Atlas Person | A visible institutional roster entry to authorized owner | No self-RPC absent account |
| Manager/delegate | Source-specific existing management read/writers only, as authorized; no invented global management grant | Only independently governed source commands |

An Owner who wishes to appoint a Person, delegate a responsibility, grant execution, or publish agency→client commitments must use the *separate* existing domain-controlled path with lawful source authority and provenance. A worker accepting a responsibility transfer is different from a manager offering it; a work recipient does not acquire unrestricted Ledger access.

## Test and release gates

- Source: `supabase/migrations/20261017183000_atlas_company_people_native_ledger_scope_v1.sql`; matching candidate copy. Atomic `BEGIN;` and `COMMIT;` required by protected release script.
- Synthetic rollback-only validation: `validation/migrations/20261017183000_atlas_company_people_native_ledger_scope_v1.sql`, exercising session/Principal/native seat/root gating, existing Company Work compatibility, multi-Ledger roster identity stability, distinction of ledger seat and organizational appointment, non-account human and negative denial paths.
- Disposable current-production-schema clone and lint-delta CI must pass **before** main merge; production release is a separate protected manual authorization after merge. A signed-in real-account UI smoke remains a separate gate.

## Conversation 3 handoff (conditional — only after release)

Use Person key `atlas.people.id` and IPR key `atlas.institutional_person_records.id`; Owner People read is source-scoped. Responsibility, custody, work assignment, work execution and worker-day projection remain independent. The next build must not translate a People row, role, native seat, or employee credential into a work allocation; it must follow exact Company Work source identity and authorized assignment/projection.