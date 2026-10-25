# Foundry historical continuity — recovered workspace → Implementation
Status: SOURCE CANDIDATE; not merged, released, or applied to production.
Date: 2026-10-24.

## Existing truth, never recreated
- The old Foundry is an append-only source stream. Historic event envelopes and sequence numbers are immutable.
- A new owner registry is a lookup/authorization carrier, not the historic source authority.
- A Personal Atlas Implementation Case is scoped to its Person. It must not be relabeled a paid institutional case just because the person governs a business.
- Ledger onboarding cases, Ledger scopes, and Foundry histories each keep their own identity and lifecycle.
- Practitioner Workbench credentials do not grant private Principal research access.

## Proposed release order
1. DB source candidate in Noel's `shared_` lane because recovery crosses Foundry, Ledger, canonical identity and Atlas Implementation authority. Signed Principal eligibility searches canonical identity anchored in the historical `WORKSPACE_CREATED` event, the exact inventory of preexisting Ledger IDs, matching canonical ledger subject IDs, and active root governance for **every** inventoried Ledger. The actor must explicitly acknowledge recovery; possession of an ID or Ledger membership does not suffice.
2. The signed claim writes only a registry link and one new recovery receipt. Historical source rows are never modified, copied or relabeled. Conflicting claims fail closed; stable request UUIDs are idempotent.
3. A paginated signed-owner chronology projects event IDs/types/dates and brief source excerpts. Full original envelopes require a second, event-scoped owner-authorized read. No unbounded Index dump.
4. A signed owner-only context projection returns references to the existing Personal Atlas Implementation Case and canonical Ledger onboarding cases. It cannot create or promote any cases or truth.
5. Atlas Foundry notebook presents eligible historical continuation before new-workspace preparation; after recovery, it can reopen the same original workspace, read its historical chronology, and create additional modern evidence entries.
6. Practitioner presentation may link historical Foundry evidence only after a separately established, case-scoped source access mandate. Existing Workbench case queue must not become a shortcut through research privacy.

## Signed test matrix
- Owner with root authority over both historical Ledgers: recovery candidate visible; explicit signed claim succeeds; original history and further additions readable.
- Another governing participant with authority over only one of those Ledgers: cannot list/claim/read the complete source stream.
- Unrelated signed Principal, unauthenticated request, expired/revoked session: denied without subject disclosure.
- Historical workspace with missing canonical subject, missing inventory, mismatched Ledger subject, conflicting owner registry: no automatic claim.
- Replayed UUID and repeated recovery: idempotent; different request must not reassign; original event count/IDs unchanged.
- Original 63 Elm records remain unchanged; 64th receipt is append-only, not a replay of 63.
- New capture shows in one chronology; unresolved evidence remains unresolved; no canonical Establishment occurs.
- Referenced Personal Implementation Case and two Ledger onboarding cases retain their original IDs and states.
- Source deployment follows Noel's protected clone/release; Atlas UI follows its own manual-release process. No production deploy from PR merge.

## Live audit basis (recorded in private Atlas/Supabase; not copied to this repository)
The historical Elm stream has 63 original events, no owner-registry row, and no new-format intake records. Both separately completed Elm Ledgers point to the same canonical business subject. The original Principal has root governance over both. This is sufficient to build a signed recovery candidate, not to silently assign or disclose the source history.

## Precise limitation of first tranche
Until the signed data authority is released and validated, the UI must display an unavailable/release-gated state. No front-end flag, client-provided workspace ID, or guessed UUID may simulate server authorization.