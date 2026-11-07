# HELD: Venue uses an existing Flower Bed

**Status: source-only draft, NOT a migration or released permission.**
Ownership: Noel source design branch PR #2254, Flower access issue #2255, active reader audit PR #2263, Atlas notebook issue #437.

## Exact intended outcome

One original Bed identity remains under source-proven Flower crop custody. A signed Flower root may offer permission for a separate Venue Ledger to USE/REFERENCE that exact Bed. A signed Venue root must accept. Only then may a signed Venue root associate an ALREADY EXISTING original Venue Work with the same Bed. No second Work, second Bed, physical custody transfer, or content disclosure follows merely from a link.

The released trigger guard_work_growing_object_context_v1 still requires Flower custody for every canonical spatial/growing_object Work-context link. This candidate does not alter or use that path. A separate Venue-owned reference relation provides the missing jurisdiction; a future reviewed adapter must converge it with ordinary Work presentation without building a second task engine.

## Held source

- HELD_source_candidate.sql defines two private source-owned tables: venue_bed_shared_use_authorizations_v1 and venue_bed_work_references_v1. Both have RLS enabled and no direct authenticated or anonymous table access.
- One internal source-current predicate verifies an exact current Flower farm crop custodian, real Bed and two currently active native Ledgers.
- Four internal callable candidates implement: Flower offer; Venue root acceptance; Venue Work-to-existing-Bed reference; and withdrawal by a current governor of either Ledger. They all require an actual current signed GoTrue session and current individual Principal/seat authority; no public wrapper or authenticated EXECUTE is granted.
- A Venue Work reference is only a bounded relationship to the ORIGINAL Work item in work_items. It does NOT create Work, assign responsibility, execute Work, approve its result, or reveal its title/instructions.
- An accepted use row can become ineffective when crop custody, Ledger participation or source conditions change, even without an explicit withdrawal event; future readers must reevaluate current source, exact grant state, and current session.
- Accepted role or Organization names alone never prove Venue Work relevance; the candidate requires current exact-ledger native Work relevance, and that evidence MAY be owner-attested under existing law. Independent Venue Event/source proof remains open.

## Security and factual acceptance matrix -- partially signed-tested, release still HELD

| Scenario | Required result |
| --- | --- |
| Flower root, live session and exact active native Flower Bed custody | Can offer one Bed, no crop finance disclosed |
| Other Ledger, stranger, guessed Bed ID, unsigned, or revoked session | Denied; no existence disclosure |
| Venue root with live Seat and current Flower-approved use | Can accept exact offer |
| Wrong Venue root, missing Seat, inactive or changed custody, forged offer | Denied |
| Venue root with accepted use, open original Work, current exact Venue-ledger relevance and reviewed stable keys | Can establish a single Venue Work-Bed reference |
| Wrong original Work, wrong Organization, withdrawn Work relevance, other Bed | Denied |
| Duplicate same source action/actor/subject | Idempotent; reuse for another subject denied |
| One Ledger with two distinct current roots | Both can independently exercise only their current lawful powers |
| Withdrawal by Flower or Venue root | Further effective reference/use denied; previous source receipt kept |
| Protected Work title, instructions, financial/employee/other-Ledger private data | Never returned by these candidate procedures |
| Existing original Flower Work-to-Bed, Flower Work result/Done and Event Work links | Must remain functional for authorized signed participants |
| Anonymous, normal authenticated role direct table access, unreviewed public API | Denied |
| Existing GoTrue JWT after session revocation | Denied at next source operation |

**Do NOT confuse the unprivileged GitHub static source guard with these signed tests.**


## First real independent signed acceptance — PASSED, 2026-11-07

- Immutable owner request [#2605](https://github.com/optical-lift/noel-core-db/issues/2605) pinned HELD source+fixture commit `6a345d983792a6295f10ab8b25dd9454f0b678b7`. Owner-gated [signed clone #42412583641](https://github.com/optical-lift/noel-core-db/actions/runs/42412583641) **SUCCESS**. Existing trusted main CI controller `5519b3cbb9f97bb54eb65c2312fae75dcb44bafd` checked out held test source only *after* a read-only production ROLES+SCHEMA snapshot; the exact original held SQL blob `19e6cd0ac886bc51a1ad5682e38a14195737d2f9` is **byte-identical** to the source that passed the earlier structural clone #42407642956.
- This was a real **local PostgreSQL17 + GoTrue/Auth + PostgREST** execution, not a role-spoofed SQL simulation or a static test. The signed script's final PASS receipt was required by the controller; authorized Flower offer, independent Venue acceptance, existing Venue-original Work reference, idempotency/cross-Bed action-ID conflict, two-direction withdrawal, new approval after withdrawal with historical reference intact, wrong-Ledger Work/Bed, ordinary worker/no-seat/other-Ledger authority denials, ended native Venue Seat, and the same JWT after GoTrue session deletion all passed against purely synthetic local identities and subjects. Postconditions checked RLS/private function ACL and unchanged original Flower guard/writer. Baseline Atlas lint **14**, candidate **14**, introduced **0**.
- Earlier [signed attempt #42411735202](https://github.com/optical-lift/noel-core-db/actions/runs/42411735202) correctly failed **before local DB/real signed testing** on a fictional fixture-safety token/semicolon. Those two fictional strings were repaired in held commit `6a345d9`. Pending [attempt #42411937073](https://github.com/optical-lift/noel-core-db/actions/runs/42411937073) was **cancelled without execution** because unrelated GitHub issues displaced workflow-level concurrency. CI-only [#2604](https://github.com/optical-lift/noel-core-db/pull/2604) corrected job-only queue admission before the passing rerun. These failures remain preserved, not erased.
- **What this does NOT prove:** other concurrent current roots on the same Ledger; changed source-relevance/crop custody after active authorization; original authorized Flower Work context, worker Result/Done and Event Work context **positive parity**; independent Venue Event/source provenance versus the fictional owner-attested Work relevance; content/field disclosure, alternate public readers/exports/media/caches and connected Person notebook; canonical Work-context integration; actual production user permission. No production SQL/ACL or feature migration was applied, and the draft SQL has **no public user grant**. **The feature PR remains unmerged; release requires separate explicit source/security and production approval.**

## Next mandatory gates

1. Full-schema disposable Postgres clone sourced through existing protected Noel procedure. Run this held SQL ONLY there and verify Postgres syntax, RLS, table ACLs, function ACLs, and existing original Flower function fingerprints.
2. Grant temporary authenticated access to the precise candidate test interface IN THE CLONE ONLY; execute real signed independent Flower root, Venue root, wrong-Ledger governor, connected worker, outsider, ended-Seat and revoked-session positive/negative tests, including replay/concurrency and withdrawal.
3. Reprove authorized original Flower Work/Done and Event Work Work-context parity. A new Venue reference must not impair either existing path.
4. Decide how Venue Work source attestation earns source authority and how the new Venue reference enters canonical Work context and notebook without creating a competing Work system.
5. Audit disclosure fields, search, exports and caches before any Bed identity reader for connected Persons.
6. Source-owner review, generated exact migration, explicit protected release approval and Atlas notebook work are separate future steps. The Rounds 1-8 constitutional conflicts (including position-auto-disclosure and decision-history erasure) remain HELD.

No production SQL, ACL, data, release, or human permission is authorized by this source document. Existing Atlas Authority Graph, authority_dimensions, and Noel security rules remain effective.
## Verified clone and signed-test readiness (2026-11-07)

- Owner-gated [full-schema structural run #42407642956](https://github.com/optical-lift/noel-core-db/actions/runs/42407642956) **PASSED** using immutable candidate `7896609ac1e78559b174f299f69587568af1e3ae`. Source/ACL postconditions and unchanged original Flower fingerprints passed on a disposable PostgreSQL 17 clone. It introduced **zero** new schema lint errors (14 baseline, 14 candidate). These are **not** independent signed-actor decisions.
- A separate held `fictional_venue_extension_DISPOSABLE_ONLY.sql` now includes the synthetic Bed 3/4/5 and original Flower Work 901 absent from the immutable C1 Person/Seat base fixture; it also adds native Venue authority, Flower crop custody, and existing Venue Work relevance. The optional test-only PostgREST transport remains explicitly **clone-only** and is not part of the held source feature.
- The prepared `validate-atlas-venue-bed-signed-http.py` tests genuine distinct GoTrue roles/sessions plus two-party grant, withdraw/reapprove, cross-Bed replay conflicts, history preservation, Venue-side withdrawal, ended native Seat and revoked same-JWT session. **This script has not been executed against the assembled full-schema local clone**. It is not proof that those conditions work yet.
- **Release gate still closed:** Compose and validate the fixture under the approved protected signed runner, maintain strict production-credential separation, and obtain independently attributable run evidence. The existing owner issue #2600 approved only the prior structural test and is not authority to merge a new CI controller, install test transport outside a clone, grant authenticated access, merge feature code or deploy. Flower Work/Done and Event Work-positive parity, current source provenance, co-root conflicts, disclosure and alternate-reader audit, canonical Work presentation and owner release remain open.

