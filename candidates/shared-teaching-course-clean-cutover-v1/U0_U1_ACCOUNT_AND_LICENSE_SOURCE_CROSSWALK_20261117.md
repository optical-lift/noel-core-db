# Titus U0/U1 — separate-account and licensing-source crosswalk

**Status:** HELD source/architecture contract; no DDL, grant, account, migration, cutover, merge or release.  
**Prepared:** November 17, 2026.  
**Owning source:** Noel `shared_` for cross-domain Auth/Reality identity; Titus `titus_` for product license, Course, school-site and teaching semantics. Atlas consumers remain independent.  
**Product authority:** [Titus universal empty-first contract, L1C–L6D and U0–U10](https://github.com/optical-lift/titus/blob/work/titus-unified-manuscript-surface-20261106/docs/TITUS_UNIVERSAL_EMPTY_FIRST_BUILD_CONTRACT_20261117.md).  
**Delivery home:** Existing [Noel PR #2617](https://github.com/optical-lift/noel-core-db/pull/2617), with [Titus #72](https://github.com/optical-lift/titus/pull/72) as app consumer and [Atlas #548](https://github.com/optical-lift/atlas/pull/548) as optional institutional consumer. This is **not** permission to implement an identity change.

## 1. Bounded outcome and protected field

**Requested result:** Determine which established source owns Auth account, canonical Person, institutional standing, product license, purchased-seat claim and Course access; prevent duplicate realities before implementing Titus licensing.

**In this increment:** Read-only audit, an explicit source-ownership crosswalk, unresolved decision and test gates.  
**Protected:** Current Reality Person bindings, Auth identities/sessions, all existing Atlas/Noel/Titus data and author manuscripts, current entitlement/case/payment rows, Course originals, permissions, RLS, CI, migrations, preview and production deployment. No automatic account linking or access expansion.

**Completion criterion for this document:** Source facts and incompatibilities identified; no invented policy; positive and negative proof sequence named; first implementation owner and dependency stated. This **does not close U1**. The first executable identity proof remains pending a separately authorized, reviewed shared contract.

## 2. Established sources and their actual meaning (read-only November 17)

| Subject | Existing source | What it establishes | What it does not establish |
| --- | --- | --- | --- |
| Signed Auth account and live session | Supabase Auth user/session; Titus's existing Atlas OAuth session transport | Who authenticated, client and live session identity | Canonical Person, institutional authority, purchase or Course right |
| Canonical Person binding | `reality.auth_person_bindings` and `reality.entities` | Present Auth-user-to-canonical-Person identity under Reality rules | Personal-versus-university license or visibility |
| Historic credential carrier | `atlas.person_auth_credentials` | Existing credential history / compatibility | New canonical identity root: Atlas's Reality access cutover uses Reality bindings |
| Institution and participation | Canonical Reality entities/relationships and `ledger.ledgers`, `ledger.seats`; scoped Atlas membership/position/responsibility sources where still authoritative | Institutional identity, a bounded participation or responsibility relation | Automatically owned institution, Titus license, Course rights or platform issuer status |
| Existing Titus customer gate | `titus.customer_workspace_entitlements_v1` with `owner_auth_user_id` primary key | An inherited customer-specific pilot/purchase access carrier | Universal personal/organization license, multiple terms or two-account identity bridge |
| Inherited customer workspace | `titus.customer_workspaces_v1`, `titus.customer_course_drafts_v1` | Historic owner-Auth-scoped workspace and private Course drafts | Universal canonical Course or automatic tenant/teacher status |
| Held universal Titus access candidate | `titus.course_authoring_access_grants` in this PR, `person_entity_id` primary key | One founding Person-scoped grant with append-only status history in synthetic source | Distinct personal/university accounts, multiple terms, organization licensure, paid seats or renewal |
| Held platform pilot code | `titus.course_authoring_pilot_codes` in this PR | A transferable single-claim platform pilot code under separate issuer authority, synthetic only | Organization employee seat code, purchased capacity, self-service checkout or production issuer |
| Atlas commercial precedent | `atlas.ledger_entitlements`, bindings and capability grants; personal purchase/subscription evidence | Distinguishes commercial original, scope binding, capability and provider observation | Titus product license by reuse of an Atlas-only entitlement kind |
| Course original and teaching | Person-origin Course candidate in Noel #2617; Atlas Teaching / enrollment and Titus learner-source patterns | Course identity, source-dependent editorial and student relationships | Identity or license merely because a user created, teaches or sees a Course |
| Rights agreement and learner continuation | Booking-agreement pattern; draft Course relations | Reusable agreement/version/party pattern and learner-edition precedent | An implemented Titus Course-rights agreement or after-license continuing-study policy |

**Live shape checks, no Person or private content read:** `reality.auth_person_bindings` has a unique active-`person_entity_id` index and a unique active-`auth_user_id` index. `atlas.person_auth_credentials` also has a one-active-Person index. `titus.customer_workspace_entitlements_v1` is keyed by `owner_auth_user_id`. Those constraints are current real behavior, not hypothetical design. The held shared Course grant's Person primary key is confirmed in `person_first_candidate.sql`.

**Historical data custody:** At the audit checkpoint the live Titus customer source held one customer workspace, one draft Course and one active private-pilot entitlement; Atlas had no Ledger entitlement or teaching enrollment rows, while Ledger participation rows existed. These are count-only observations, **not** permission to migrate or erase records. Before any real cutover, recheck counts, row provenance, access and exact no-loss parity on an approved protected restore.

## 3. U1 is NOT solved by renaming login screens

**Binding owner choice L1C:** Titus must offer separate personal and university **account/sign-in contexts**, separate license/billing/admin and strict private disclosure boundaries, without automatically creating a second canonical human.

**Actual conflict:** The current Reality binding model permits one active Auth user per Person. Two independently signed Auth users representing the **same** canonical Person cannot both be active through it unchanged. Meanwhile, the held Titus grant looks up access solely by Person, so simply lifting that uniqueness would expose the same grant to every newly linked login unless a second account/license/scope authorization is enforced.

**Forbidden shortcuts:**
- Do not mint a duplicate canonical Person for the same known human to work around uniqueness.
- Do not equate Atlas Auth session with Titus institutional account or use a product-specific localStorage identity assertion.
- Do not repurpose a `ledger.seats` row as a paid Titus license or let one institution's membership create Course editorial rights.
- Do not expand a Person-keyed grant into universal personal + university Course access just because it resolves to the same Person.
- Do not loosen the shared Reality active-person uniqueness, bypass canonical access functions, or broaden RLS on a Titus-only branch.
- Do not overwrite historical grants, workspaces or Course UUIDs to tidy up the transition.

**Unselected owner choice:** May separately signed personal and university Auth accounts be explicitly associated with **one verified canonical Person**, following a new independent identity-verification/adjudication procedure? The Titus governing contract explicitly leaves this open. A future decision must specify whether linking is permitted and how an employee's departure, lost login, credential replacement and context revocation work. A verified link, if later approved, proves identity **only**, never cross-account content access.

**Required shape regardless of that decision:**
1. Independently authenticate the active signed session and issuer/client; never accept a caller-provided Person or account context as authority.
2. Resolve the current canonical Person through shared Reality authority and then verify the separately admitted **account context** (personal or exact institution) as a current authorization relationship.
3. Resolve the license to an explicit licensable subject (Person/personal account or real organization) and its immutable purchase/pilot/trial/renewal origin; do not infer an organization from payment.
4. For organization consumption, prove exactly the current institutional standing plus paid seat claim/capacity where required. A platform-issued pilot code is a different issuing jurisdiction.
5. Resolve each Course operation to the original Course and a current exact right: originator, coauthor, appointed teacher, learner or authorized institutional publisher. Identity, payment, seat and role each answer different questions.
6. Deny by default for missing, ambiguous, inactive, disputed, withdrawn or cross-context source facts. After a license ends, evaluate read/export independently from edit, new enrollment, publication and student continuation.
7. Return the minimum scoped data necessary; a private or unavailable source must never be translated into an apparently empty, authorized institutional record.

**Design-level evaluation order (not executable SQL):** signed session → verified account context → current canonical Person and permitted institution association → explicit active license/term or pilot provenance → seat and operation rights where needed → exact Course/right/edition → allowed read or command. Failure at any step is a refusal, not a new account, license, institution, Course or membership.

## 4. Ownership and code change routing

| Change class | Source owner / release lane | Prerequisite |
| --- | --- | --- |
| Additional verified Auth credentials for one canonical Person, account-context relationship or shared lookup changes | Noel shared Reality authority; `shared_` | Explicit owner decision on same-Person multi-account linking; impact audit of Atlas current-person and Titus source callers; cross-app signed denial tests |
| Personal vs organizational Titus license subject, immutable acquisition/term origins, renewal status and post-license read/export | Titus logical source under Noel `titus_`, with shared commercial dependency review if necessary | U1 account scope; owner decisions on tiers, prices and trial/renewal details where not yet selected |
| Organization paid-seat capacity and transferable seat-claim codes | Shared institutional authority and Titus product-entitlement contract, exact lane adjudicated before generation | Real institutional identity and authorized seat distributor; atomic claim/reclaim and concurrency tests |
| Person-origin Course, coauthors/teachers, Course-rights agreement, learner participation and continuation | Noel shared Course + Titus/Atlas-specific projections, correct source boundaries | Exact accepted Course-rights and continuity choices, versioned admission and negative consent tests |
| Titus login, account UI, editor and customer self-service | Titus PR #72 | Only consumes released signed source contracts; never reconstructs permissions in React |
| Institutional operator/course consumer | Atlas PR #548 | Genuine organization authority and a granted Course right; never mints a second Course |

The `shared_` structural source review must precede any change to common Auth/Person uniqueness or resolver semantics. Identity reconciliation is **not** a Titus-only SQL migration. Do not add a separate Titus Person registry or a second institution ontology.

## 5. First acceptance matrix — MUST DENY unless independently warranted

| Case | Expected source result | Current proof state |
| --- | --- | --- |
| A. Same signed Person, no Titus license | No Course creation or authority from login alone | Synthetic prior candidate only |
| B. Two distinct signed Auth accounts with distinct canonical People | No private Course, grant, payment, Notebook or institution leakage | Prior synthetic two-person tests cover only narrower Person isolation |
| C. Separately signed personal and university contexts for the same verified human, if linking is approved | Neither context borrows the other's licensed access, billing or Course rights without a specific grant | **BLOCKED:** current one-active-Auth-per-Person index; owner identity-linking choice not made |
| D. Signed account claims another account-context or organization identifier | Refuse; no arbitrary context switching, no cross-organization roster | Not implemented |
| E. Same Person holding an Atlas Ledger Seat | Seat shows participation only; no personal or organizational Titus paid license or Course editorial right | Source contract; independent signed test pending |
| F. A platform pilot code is offered as an institution's paid seat code | Refuse; source issuer jurisdictions and claims are distinct | Platform code synthetic only; org seat path absent |
| G. Two concurrent organization claimants for the last licensed seat | At most one succeeds; no oversubscription or grant from stale/revoked capacity | Unimplemented; U2 |
| H. Session or verified Person binding revoked mid-request | Refuse access with no stale JWT, account or license fallback | Required shared signed/transactional test |
| I. Teacher exits an organization | Original Course/Work survives; institution and teacher retain only accepted agreement rights | Agreement source absent; U4 |
| J. License ends while a student is enrolled | Owner may still read/export retained Course; new edit/enroll denied; learner's permitted study follows Course policy and history remains intact | Renewal and continuity sources absent; U5/U8 |
| K. Existing live Titus customer workspace during source cutover | No loss, no cross-account title disclosure, no retroactive new entitlement or Course | Protected restore and actual-data parity pending |

**U1 executable test gate:** On a disposable production-shaped shared schema clone with separately authenticated real GoTrue/PostgREST sessions, prove positive personal and university account establishment within the approved identity shape, both cross-context denial directions, stale/departed institution, revoked Auth and altered-context input. If same-Person linking is selected, add actual independently signed dual-Auth same-Person positive identity and cross-context negative permission tests. A static mock or unsigned JWT fixture is not proof. Verify Atlas current-person, personal home/Household and Ledger access do not widen because a Titus login exists.

## 6. Next unfinished bounded increment (after this document)

**First owner-level fork:** Decide the exact same-Person account-link policy. Until chosen, maintain independent Auth account/Person cardinality and deny same-Person dual-login behavior rather than inventing duplicates. **First source change after that fork:** a separate, source-reviewed `shared_` account-context/credential-resolution proposal with an explicit compatibility/withdrawal and negative-test plan. This should be prepared as a held candidate in the existing shared source lane, not applied directly to the live Supabase project.

**Completion/accounting for this increment:** Documentation only on existing held Noel PR #2617; no schema, grants, live Auth, migrations, data, source history, Atlas consumer, Titus UI, merge or deployment changed. U0 crosswalk is documented; U1 implementation, verification and release are **NOT complete**.
