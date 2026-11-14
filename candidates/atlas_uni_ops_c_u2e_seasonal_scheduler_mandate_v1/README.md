# UNI-OPS-01 / U2E — approved season, one offer, separate scheduler (HELD)

**Owner decisions recorded exactly:** `1C / 2C / 3C` on November 4, 2026:
- **1C** — a separately registered and expressly authorized background carrier will eventually finalize **one** previously accepted native candidate into original Work.
- **2C** — the owner's seasonal mandate can last up to **120 calendar days inclusive**. It is not an unbounded relationship.
- **3C** — completion of original Work / accepted Actual must NOT automatically offer more Work. **No repeat until the owner authorizes a new campaign**. One campaign has at most one associated candidate and one original.

This is **source code in a held draft**, not a migration, active privilege, deploy, release, scheduler or autonomous work issuance. Built on [U2C](https://github.com/optical-lift/noel-core-db/pull/2485), including U1A/U1B/U2. Atlas consumer stays default-OFF in [Atlas draft #535](https://github.com/optical-lift/atlas/pull/535).

## Scoped outcome

**Owning Source:** Noel native Ledger root, original native Rulebook/Subject, worker's accepted standing scope, and previously implemented pre-original candidate offering.

**1.** `01_pending_campaign_root_source_held.sql` creates three private RLS tables with immutable evidence: exact root-approved seasonal campaign, explicit signed revocation, and one source-generated candidate association. All are append-only. They retain actual attribution, date/timezone/ISO weekdays, existing worker scope, and one original maximum. A historical decision is read by a current signed governing Ledger root, **not** by automatically claiming the historical approving principal's identity.

The root may approve one season only with current independent farm+Ledger+Rule+worker scope, native IANA timezone and an inclusive maximum of 120 days. Overlapping unrevoked seasons for the same source+worker are refused under a transaction lock. The source-recorded mode is `separately_authorized_scheduler` but the **actual carrier binding state is `unbound`**. A campaign approval returns `schedulerAuthorized:false` and `originalWorkCreated:false`.

**2.** The current signed root may start **one** source-selected candidate per campaign using `offer_one_candidate_for_seasonal_campaign_self_api_v1`; it calls the existing U2 source's exact first eligible standing-mowing adapter and records a unique campaign↔offer claim atomically. This **never creates Work** or considers elapsed time evidence of weeds. One campaign cannot attach a second offer when its first Work is completed. The worker still signs their own accept/decline as a distinct Person.

**3.** The current root can revoke any known historical campaign without requiring a now-retired farm Rule. Revocation is prospective and append-only. A new root may inspect and revoke prior existing campaigns without pretending to be the old root. An expired or revoked campaign cannot authorize a future issuer. Past signed Actual and historical provenance remain intact.

**4.** `02_close_ungoverned_offer_and_finalizer_held.sql`, applied *last in the disposable clone*, retires both prior externally callable direct noncampaign U2 offering and root-finalization. Earlier U2C already retired R02 direct originals/worker physical bypass. **No public original Work issuer remains pending a separately registered carrier.** No credential or secret is added; only authenticated signed root campaign/offer/revoke/read and signed worker accept/decline are exposed.

**5.** `03_exact_campaign_root_reader_held.sql` returns the one campaign's current source state (pending, active-but-unbound, revoked, expired) with present one-offer state. It does not reveal any generic Person roster or become a scheduler identity.

**6.** `04_postconditions_held.sql` is an **unrun** isolated clone structural, ACL and source check. It cannot substitute for signed actor and concurrency tests.

## Exact assembly order in a disposable production-shaped native clone

Pinned full R01/R02 dependencies → U1A → U1B → U2A + U2B → U2C `01`/ `02`/ `03` (with U2C postconditions as applicable) → U2E `01` → U2E `03` → U2E **`02` LAST** → U2E `04` postconditions in a rollback transaction, plus genuine signed owner, worker and unauthorized actor tests.

The files are held **candidate SQL**, not a migration. PostgreSQL schema compilation, source data checks, GoTrue/REST signed sessions, parallel race, user-visible issuance, and CI evidence have **not** been run. Never apply on live Supabase or assume a package/install/runner exists.

## Identity and technical STOP — not resolved by 1C alone

A 1C choice establishes **the kind of carrier** the owner wants. It does NOT identify, register, verify or empower any particular one. A separate native Source-owned carrier registry and effective authorization must contain:
- separately attested technical identity, authentication proof, registered parent principal, competence/fitness, jurisdiction and bounded operations;
- exact active campaign UUID, current Ledger authority, one offered candidate with its own *signed worker acceptance*, one original, three-open-Work Person capacity, original/Result contract, planned date and current Rulebook/Subject disclosure;
- current expiry/revocation, campaign status and linked offer lock. One delegate may not reuse the root's session, an arbitrary `service_role` key, a person's user-editable claims or the old signed-root writer to impersonate authority;
- correct actor attribution and audit receipts, independent source denial for outsider/revoked/unbound/expired/duplicate/changed campaign, and no privilege to issue next campaign or task.

**No U2E runtime carrier implementation exists.** An accepted candidate remains accepted, **not original Work** until the new separate carrier path is actually authorized and verified. The current native R02 writer requires a signed human root and cannot simply be called as a scheduler. A new source-qualified writer is needed, not a spoofed `auth.uid()`.

## Evidence actually obtained

- **14/14** isolated V8 strict campaign client contract cases passed (campaign window, carrier unbound, no repeat, revocation/receipt restrictions). An additional repository Node test was authored but **not run**.
- **11/11** static source-only structural checks passed: private RLS, exact 120-day/one-original/one-offer constraints, frozen unbound carrier, 3C direct bypass closures, historical root revocation, append-only source, no new scheduler credential or extension.
- No SQL parse/PG compilation, node test execution, TS/Next build, PostgreSQL signed actors, worker load or human interaction was verified. Neither these checks nor the PR itself create authorization or release.

## Next unfinished bounded outcome

**U2F carrier identity and native issuance proof:** discover the existing deployable nonhuman principal mechanism (do not invent one), validate whether it supports source-bound registered identity and current revocation. If not, request explicit infrastructure/identity decision. Then build the narrowly scoped native command that accepts a *registered* scheduler's authenticated identity, checks exactly one owner-approved campaign and independently signed worker acceptance, atomically rechecks canonical Person-capacity/Rulebook/Result, and emits one canonical original without impersonating the governor. Subject and Person disclosure must be proved independently, and no next campaign may be automatically authorized. Until this is fully source-verifiable, **release remains held**.

Unresolved alongside U2F: real farm-wide Subject identity audit, cross-writer 3-open Person capacity locking, U1A/U1B conflicting history adjudication, signed Result→next eligibility without auto-offer, independent U5 Household and U6 Event proofs, and U7 integrated release.
