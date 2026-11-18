# Titus U0/U1 — separate-account and licensing-source crosswalk

**Status:** L1C account model SELECTED; U1 source implementation HELD pending signed validation. No live DDL, grant, account, migration, cutover, merge or release.  
**Prepared:** November 17, 2026.  
**Owning source:** Noel `shared_` for cross-domain Auth/Reality identity; Titus `titus_` for product license, Course, school-site and teaching semantics. Atlas consumers remain independent.  
**Product authority:** [Titus universal empty-first contract, L1C–L6D and U0–U10](https://github.com/optical-lift/titus/blob/work/titus-unified-manuscript-surface-20261106/docs/TITUS_UNIVERSAL_EMPTY_FIRST_BUILD_CONTRACT_20261117.md).  
**Delivery home:** Existing [Noel PR #2617](https://github.com/optical-lift/noel-core-db/pull/2617), with [Titus #72](https://github.com/optical-lift/titus/pull/72) as app consumer and [Atlas #548](https://github.com/optical-lift/atlas/pull/548) as optional institutional consumer. This is **not** permission to implement an identity change.

## 1. Bounded outcome and protected field

**Requested result:** Reconcile the owner's **one canonical Person, one sign-in, multiple independently governed account scopes** with existing Auth, institutional standing, Titus licensing and Course rights without duplicating People or auth identities.

**In this increment:** Read-only audit, an explicit source-ownership crosswalk, unresolved decision and test gates.  
**Protected:** Current Reality Person bindings, Auth identities/sessions, all existing Atlas/Noel/Titus data and author manuscripts, current entitlement/case/payment rows, Course originals, permissions, RLS, CI, migrations, preview and production deployment. No automatic account linking or access expansion.

**Completion criterion for this document:** The one-login scope rule, distinct account source subjects, negative gates and next source owner are recorded. This **does not close U1**: a signed institutional authorization reader and independent license/seat source are still required.

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

## 3. Owner-selected identity and account context model (L1C clarified)

**Selected rule, November 17, 2026:** **One verified canonical Person. One signed login. Multiple independently authorized Titus accounts.** A teacher may navigate between their **personal account** and any university/institution account they are **currently admitted** to, using a selector in the same Titus application. The context selection is not a second Supabase Auth user, not another canonical Person, not a new app, not a newly minted institution and **not authority**.

This clarifies L1C's earlier words "separate accounts": separation is at the **account context, licensing, billing, workspace, Course and permissions** boundaries, **not at the sign-in credential** boundary. The prior proposed same-human two-Auth linking is **superseded** and no longer a blocker or requirement. Retain the current one-active-Auth-per-Person constraints in `reality.auth_person_bindings` and the compatibility credential carrier.

**Canonical scope keys (source design, not a released schema):**
- **Personal Titus account:** subject is the caller's **verified canonical Reality Person**; its context is `personal`. Signing in establishes identity, not any Titus paid license, authoring right or Course existence.
- **Institution Titus account:** subject is a **specific admitted canonical institution/organization** (with its genuine source-identified Ledger context as appropriate), not the currently signed Person. Its context is `institution`. The caller must have an independently accepted **current Titus account participation/admission**, linked to exact institution, and the exact operation must independently meet licensing, role and Course-rights guards. Existing generic `ledger.seats` and Atlas organization membership can be evidence but do **not** by themselves grant Titus access or a paid Titus seat.
- The **account selector** presents only server-proven, currently admitted eligible contexts. It does not surface another organization's private name, courses or billing to an unrelated Person. Personal scope may exist before purchase but authoring must be separately licensed.
- A context switch changes which account is **requested**, not the user's logged-in identity or permission. Context can be carried by a route or explicit request parameter; it is not a trustworthy authorization claim. Every server read/mutation must revalidate it against current source standing.
- **Course origin:** one immutable canonical Person-created Course; account placement, teacher appointment, institutional publication and billing are independently granted relationships. An institution never creates a duplicate Course by selecting its workspace. Teacher departure revokes only source-justified institutional capabilities, preserving personal ownership/history and any separately accepted Course agreement rights.

**Required server-side evaluation chain:**

```text
Signed current Auth user + live session (issuer/client checked)
  -> exactly one active canonical Reality Person binding
  -> requested Titus context type + exact subject (personal Person / real institution)
  -> exact current account admission (institution), never inferred from selector or Ledger seat
  -> independent Titus license + term / platform pilot or paid institution seat, if operation requires
  -> exact Course rights (author/coauthor/appointed teacher/learner/publisher) + agreement/edition
  -> operation-specific allow / deny + minimal authorized result
```

**Forbidden shortcuts:** creating a second Auth identity to enter an institution; a second canonical Person for one teacher; interpreting a Ledger Seat, membership, payment, Course author, owner of another product or selector click as a Titus license/issuer; copying billing or private Course records between scopes; allowing a client-selected `organization_id` to skip an admission check; accepting stale permissions or continuing a university session after institutional withdrawal. An outage must not display an account as empty-but-authorized.

**Existing held grant incompatibility remains:** `titus.course_authoring_access_grants(person_entity_id PRIMARY KEY)` conflates a Person with a licensable account and cannot represent both an institution's license and a personal grant, nor separate terms/renewals. The change in Auth model does **not** repair that U2 source gap.

## 4. Ownership and code change routing

| Change class | Owning source | Dependency |
| --- | --- | --- |
| Existing Auth, session and canonical Person resolver | Shared Reality `shared_`, **no change required for this account decision** | Keep one active Auth binding per Person; protect Atlas callers |
| Scoped Titus account admission (personal; exact institution, current admitted actor), verified context reader | `titus_` source with reviewed institutional shared-identity dependency | Current signed Person, real institution, accepted participation and independent revocation. Do not add a duplicate institution or Person registry |
| Personal/organization licenses, immutable acquisition/terms, independent read/export after end | Titus logical source under Noel `titus_` | Verified subject, plan and receipt; never reused Atlas-only entitlement kind |
| Organization purchased-seat capacity and organization-issued claim codes | Titus entitlement/seat source; shared institutional issuer/authority validation | Paid organization license and independent code issuer (not platform pilot issuer) |
| Source Course, roles, rights agreements, learner relations | Shared Course authority + Titus/Atlas-specific projections | One Person-origin Course, exact accepted Course-rights agreement, no inferred Course copying |
| Account selector, per-scope UI and customer self-service | Titus PR #72 | Released server-authorized scope reader; never infer rights in UI |
| Optional institutional course consumer | Atlas PR #548 | Exact independent institutional Course right, not Ledger-seat-only |

No multi-credential identity linking or unique-index relaxation is needed. **Do not construct a second Titus organization ontology to describe the same institutional reality.** A small Titus-specific account-admission source may be needed, but it must explicitly reference existing admitted canonical institution identity and preserve the institutional evidence chain.

## 5. First acceptance matrix — MUST DENY unless independently warranted

| Case | Expected result | Current proof |
| --- | --- | --- |
| A. Valid signed Person, no Titus license | Personal context identity can resolve; no course authoring, institution, enrollment, entitlement or tenant minted from login | Prior synthetic source covers narrower grant denial |
| B. One signed Person legitimately admitted to personal and institution scopes | Both contexts selectable; personal and institution title lists, Course permissions, billing and students stay strictly separate absent specific accepted rights | **NEW U1 signed scope proof required** |
| C. Same signed Person selects a non-admitted institution or forges its UUID | Fail closed: no returned roster, organization billing, private Course or organization scope | **NEW U1 negative proof required** |
| D. Different signed Person attempts the first Person's personal or institutional scope | Fail closed even with known UUID or prior cached selector value | **NEW U1 signed-other-Person proof required** |
| E. Signed Person has an Atlas Ledger Seat but no independently accepted Titus institutional account admission | No Titus institution account access, organization license or Course right merely from seat | Not implemented |
| F. Institutional account admission is withdrawn while the same Auth user remains signed in | The institution scope disappears/refuses on every new operation; personal scope remains unaffected | Not implemented; revoke test required |
| G. Platform pilot code submitted as an organizational paid-seat claim | Reject, issuer jurisdictions distinct | Earlier platform pilot synthetic only |
| H. Concurrent claims for last paid organizational seat | At most one succeeds; no over-capacity | U2 not implemented |
| I. Person's live Auth session or canonical identity binding becomes invalid | Deny all personal and institution operations; stale bearer or client context cannot revive | Real signed test pending |
| J. Teacher exits institution after Course agreement | University scope and rights adjust per exact accepted agreement; original Course ID and Person source preserved | U4 held |
| K. License ends; students already admitted | Read/export for owner retained, mutation/new enrollment denied, per-Course student policy governs continuation | U5/U8 held |
| L. Existing live Titus customer pilot/workspace/draft | No record loss, no silent conversion to organization, no new grant, unchanged title confidentiality | Protected restored-data parity pending |

**First implementation acceptance:** On a disposable production-shaped source clone, authenticate one actual signed Person and separately authorize the personal and an institutional scope, plus an independently signed second Person. Test personal → institution → personal transitions and operations, forbidden institution and ID tampering, affiliation withdrawal, license absence, Course-rights absence, signed-session revocation and other-Person isolation. Assert no extra Auth/Person rows and no changes to Atlas authority. A selector visual or synthetic unsigned JWT is not equivalent to source-signed proof.

## 6. Next unfinished bounded increment

**Owner choice closed:** one Person/one login with distinct account scopes; no pending same-human second-login question. **Next U1 source work:** define and test a fail-closed `titus_` personal/institution account-scope reader and its exact institutional admission source. A personal scope does not require purchase to *exist* but does require a license to author. Until organizational admission and licensed seats are implemented, **institution access must deny**, not be simulated from membership or Ledger Seat. Preserve the existing single customer pilot and draft data. Follow with U2 licensable-subject/term and seat originals, not a Person-PK grant expansion.

**Completion/accounting:** L1C clarification and crosswalk source update on held Noel #2617; no live schema, customer account, Auth, permission, migration, Course ID, merge or deployment. U1 implementation and protected signed verification **remain open**.
