# Atlas — Native Ledger information permissions, relationship-derived v1

**State:** Source architecture candidate, NOT a released grant, migration, or application feature  
**Date:** 2026-10-25  
**Selected product direction:** D — responsibility-derived *suggestions*, explicitly reviewed by the exact Ledger's governor.  
**First proof:** Flower operational data (zones, plantings, crop status, condition observations); second independent proof required before wider horizontal promotion.

## 1. Exact reality artery

`canonical Person → active native Ledger seat → current effective institution responsibility → source-specific proposed exposure/operation → exact Ledger governor decision → bounded active source authority → authorized read/command → notebook projection → revocation/denial proof`.

The following never imply one another:
- Auth/identity is not native Ledger participation.
- Participation is not knowledge/disclosure authority.
- Position or responsibility is **evidence for a proposal**, not automatic permission.
- Read is not contribute, revise, approve, delete, finance, provider administration, or root-governing authority.
- Task responsibility is not a Worker Day execution warrant; it cannot be replaced by a generic permission.
- Principal root-governing authority is not a property editable by a connected Person checkbox.
- One Ledger's grants never propagate to another, even if they share an Organization, farm, person, or physical location.

## 2. Existing canonical carriers to reuse

- Identity: `atlas.current_person_id_v1()`; signed Principal: `atlas.current_principal_id_v1()`.
- Exact Ledger membership: `ledger.seats`, `atlas.person_has_native_ledger_connection_v1(...)`.
- Governor: `atlas.principal_ledger_authorities`, `atlas.principal_has_ledger_authority_v1(...)`. A governor needs an effective, active exact-Ledger root-governing grant at decision time.
- Current responsibility evidence: `atlas.effective_person_organization_responsibilities_current_v1(person, organization)` exposing verified appointment, responsibility, scope and source IDs.
- Institution ↔ native Ledger scope: `atlas.ledger_organization_participations`, both active.
- Existing **organization-wide** information exposure: `atlas.organization_member_exposure_grants`, *not* a reusable exact-Ledger permission table; do not reinterpret its historical grants.
- Already existing domain action laws: Company Work allocation/result acceptance, Communication Endpoint member capabilities, Crop/Harvest source commands, Event and Financial source governance. Never bypass them.
- Existing farm `atlas.zones`, `atlas.crop_cycles`, `atlas.crop_placements`, `atlas.crop_observations`, and `atlas.crop_profiles` carry different field sensitivity. Existing owner/manager farm-role RLS and privileged RPCs must be inventoried before any source adapter.
- Commercial `atlas.ledger_entitlements` are **subscriptions**, not information permissions.

The September 2026 authority-dimensions tranche in `optical-lift/atlas/atlas.features.yaml` prohibits promoting a single generic permission table for all authorities. This design creates a **common proposal/decision grammar** plus source-owned grant and enforcement adapters, not one universal `can_write_anything` switch.

## 3. Canonical decision vocabulary

**Proposal** is generated solely from admitted, versioned mapping(s) between an established responsibility ID/function and a specific source-owned permission. No role-name substring inference, arbitrary LLM decision, or presumption that 'stewardship' means crops. If no registered mapping resolves, proposal is `unmapped` and grants nothing.

**Grant decision** must identify:
- actual signed governor Principal and Person;
- exact active Ledger ID plus participating Organization;
- target canonical Person, active native Ledger seat;
- exact source permission key, version and human-readable purpose;
- scope kind and *resolved* scope ID (e.g. exact operating unit, selected crop zones, own Work);
- the responsibility/relationship evidence IDs (if derived), including their current effective state;
- explicit governor-approved `allow` or `withhold`/denial and recorded date/actor;
- effective/expiry conditions, optimistic concurrency/idempotency token, revocation and supersession history.

**Active access** is derived, not copied from a checkbox:
`authenticated actor ∧ current canonical Person ∧ active exact Ledger seat ∧ existing governing-source scope ∧ current effective grant ∧ not suspended/revoked/expired ∧ lawful source operation`.

An explicit grant of one operation may not imply another operation. A proposal, preview, subscription, task, position, or even signed-in governor session cannot serve as the source of a Person's content read grant. Historical activity remains historically attributable on revocation.

## 4. Domain-local first proof: Flower operational exposure

Register these narrow semantics as source adapter operations:

| Key (candidate) | Human label | Data permitted | Explicit exclusion |
|---|---|---|---|
| `flower.zone.status.read` | View growing zones and beds | Zone names, operational locations, care/condition | Restricted location evidence, unrelated farm zones, finance, private notes |
| `flower.crop.operational.read` | View crops/plantings | Identifiers, varieties, operational cycles/status within allowed scope | Prices, margin, revenue forecasts, buyer data, private business commentary |
| `flower.crop.condition.submit` | Record crop conditions | Append source-qualified observations through the existing lawful domain command | Rewrite planted history, relocate crops, modify cycle state, delete observation |
| `company_work.own.read` | View assigned Work | Existing allocation-based Work reader | Other people's Work or all institution Work |
| `company_work.own.report` | Report Work result | Existing result contract/authorized worker command | Manager acceptance, assignment powers, completion without a result contract |

The Work rows are **references to already governed responsibilities**, not a second Work grant writer. Work permissions should be projected from current Work domain authority, not overridden by the Flower access catalog.

Expose only allowlisted fields in authenticated source-specific RPCs; do not select raw `crop_profiles.*` or `zones.*`. Crop profile can contain money fields. Enforce exact farm ↔ operating unit ↔ Ledger custody, verified by canonical bindings, not matching names or dates. Crop reading never implies Flower Ledger sales/finance exposure.

`flower.crop.condition.submit` must be withheld from executable choices until a source command exists that validates the same authorization and reports provenance and idempotency.

## 5. Source structure and command boundaries

After existing-schema audit choose the smallest **Flower operational exposure** carrier (using existing governed tables where valid; otherwise narrowly owned grant/decision and mapping records). Do **not** create a generic cross-domain allow-all grant table.

Required membranes:
1. `...permission_review_self_api_v1(organization, exact_ledger, target_person)`: signed root governor only; identifies current responsibilities, mapped suggestions, active/rejected decisions and evidence. Redact unrelated Person private data. No writes.
2. `...permission_decide_self_api_v1(...)`: signed exact-Ledger root governor; validates active target seat, mapping, scope, permitted operation, current source authority, conflict/version and idempotency, then records append-only grant/deny/revoke. No user impersonation and no implicit new employee account.
3. `...flower_operational_read_self_api_v1(ledger, scope, ...)`: checks signed requester, exact seat, currently effective source-specific grant and source record ownership **before** releasing records. Governor browsing uses independently verified governing source privileges, never the connected-person grant route.
4. Existing source-specific observation command, gated by current grant **in addition to** its original command requirements. No generic SQL table update.
5. Connection permission sheet in the Atlas application after actual RPC release. Application only reviews proposals and invokes approved commands; no local mutation as truth.

Do not create UI checkboxes tied to unimplemented source operations. Mark those categories `Not available yet`; do not pretend a grant makes them writable.

**Critical negative control:** A root governor's approval of Flower crop reading must not indirectly widen old farm membership RLS, `has_operations_membership()`, old Owner/Manager RPCs, `service_role`, Communication Endpoint privileges, or other Organization-wide exposure grants.

## 6. Relationship and rule lifecycle

- A live responsibility definition may lead to multiple **suggestions**; governor approval is independent for each.
- A materially changed appointment/responsibility/scope makes linked dependent grants invalid until re-adjudicated. An independently justified grant requires its own separate origin, authority and effective period.
- Rejections should be preserved with mapping version and evidence so repeated reads do not nag the governor. A new material relationship or mapping version may reopen review, never silently allow access.
- Explicit revocation must stop subsequent reads/commands, including cached client projection refresh and any server search/export path. Old audit records remain.
- Active grants of two distinct Ledgers are evaluated independently. An overlapping zone/crop cannot be read through a Ledger lacking its own lawful source connection and access scope.
- Multiple governors may act; decision writes must use locks/version checks, record the deciding Principal, and reject stale conflicting reviews.
- Policy evaluation must fail closed on missing/ambiguous mappings, expired membership, unresolved cross-Ledger farm custody, lost credential/Principal binding, revoked seat, and stale or unsupported scope.

## 7. Protected implementation train

### Gate A — Flower source audit / rights contract
Map each source read/command and every alternate entry point (RLS, public RPC, invoker/definer view, search, export, notes/attachments). Document current ordinary farm-member reads separately from new Ledger permissions. Define the minimum authorized fields and exactly how sensitive columns are excluded.

### Gate B — first domain implementation
Source first in `optical-lift/noel-core-db` using `atlas_` reviewed candidate → owner source/security review → generated exact migration → full-schema disposable clone → real signed owner/member/outsider tests → protected release with explicit owner approval. A source merge is not a production authorization. No direct production `execute_sql` DDL, SQL impersonation or blanket GRANT.

### Gate C — notebook connection review and human proof
Atlas UI consumes released RPCs using the universal notebook visual/interaction constitution. The Person connection surface shows current responsibilities, evidence-backed suggested access, per-permission decision and actual outcome, history, and the effects of withdrawal. Prove on separate signed governor/worker accounts. A governor may configure proposed grants for an **existing** connected Person without creating/altering their identity.

### Gate D — second proof
Venue event-preparation read access is a separate source adapter with its own sensitive data, not an alias of crop/zone tables. Compare the shared proposal/decision grammar across Flower and Venue and only promote the proven common portion.

## 8. Security acceptance matrix (required for release)

- Correct Ledger governor may inspect/review Person's scoped proposals; unrelated governor cannot enumerate target users/records.
- Signed connected Person with no active grant cannot read operational crop/zone source via new pathway, including raw PostgREST, RPC, search and export.
- With approved `flower.crop.operational.read`, exact allowed fields/records appear; no price/revenue/private note fields are returned.
- `flower.zone.status.read` does not silently grant crop financial or other Ledger access.
- A signed Person cannot grant/revoke to self by spoofing governor IDs/metadata; never trust user-editable JWT metadata for authorization.
- A proposed or denied mapping never grants read; revoked, expired and changed-basis grants fail closed on next request.
- Two governors' stale concurrent edits conflict explicitly; idempotent replays do not duplicate live grants.
- Old company Work authorizations still govern own tasks and result reporting. No spurious task creation/acceptance.
- Invalid/absent provider identity, revoked seat, unrelated Organization, inactive farm→Ledger binding, ambiguous zone custody, off-scope responsibility, and unsigned requests all reject without record disclosure.
- Read-only release must not change existing Production farm RLS policies or expand application-role table privileges.
- Tested code, signed auth denials, production release and browser acceptance are distinct receipts.

## 9. Explicit stop conditions

Do not promote or release if (1) the source farm/crop/zone-to-native-Ledger mapping is not provable, (2) any RPC leaks restricted columns, (3) grant write works without an authenticated exact governor, (4) old farm role paths bypass a promised new boundary, (5) a domain writer is missing or unsupported, or (6) the protected clone/sign-in tests have not run.

**No permissions for any actual human are established by this architectural document.**
