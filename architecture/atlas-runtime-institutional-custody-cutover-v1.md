# Atlas Runtime Institutional Custody Cutover v1

## Purpose

Move authenticated Atlas runtime identity, Organization access, Company Work accountability, and institutional Correspondence presentation from historical physical Organization storage to the canonical institutional custody established by `20260914000504_atlas_institutional_custody_reconstruction_v1.sql`.

This tranche is a **runtime membrane**. It does not physically move historical rows. It changes which Organization Atlas presents and authorizes against while retaining historical physical IDs as implementation/provenance evidence behind the membrane.

## Governing laws

1. **Canonical custody governs presentation and authority.** A row adjudicated `reassigned` is presented and authorized against its canonical Organization/Ledger, not its historical carrier.
2. **Physical history remains immutable.** Work items, execution results, acceptances, communication endpoints, connected sources, memberships, employee seats, credentials, and Ledger entries remain physically where established unless a later governed migration expressly moves mutable state.
3. **Unresolved and archived custody never becomes runtime institutional identity.** An unresolved/archived membership cannot make its historical container appear as a current institution.
4. **Direct canonical rows remain canonical.** Rows with no adjudication continue to resolve to their physical Organization/Ledger.
5. **Membership and Principal authority are distinct.** Employee access resolves through effective membership/seat/credential custody. Top-level Organization governance may also be proven by current Principal root authority over that Organization's active governing compatibility-primary Ledger.
6. **Ledger authority is not flattened into Organization ownership generally.** Only root authority over the Organization's active `governing` compatibility-primary Ledger satisfies the Organization-owner compatibility helper. Operating/sibling/dependency Ledgers do not silently confer Organization-wide authority.
7. **Company Work writes remain physical while authority becomes canonical.** The work item's effective custody determines who may decide it; the acceptance/event remains attached to the preserved physical work chain.
8. **Correspondence presentation becomes canonical while transport remains physical.** Endpoint/source IDs, bindings, capability grants, capture/send state, heartbeat state, credentials, and communication history are untouched.
9. **No trigger bypass, FK rewrite, mail activation, polling, or outbound send.**
10. **Compatibility is visible, never normative.** Principal context may expose the legacy singleton Organization only under an explicitly named compatibility field; governed Ledgers/Organizations are the governing truth.

## Effective membership membrane

`atlas.current_organization_membership_v1(canonical_organization_id)` resolves the signed-in Person's active membership by:

- preferring a direct active membership in the requested canonical Organization;
- otherwise accepting an active membership whose immutable custody adjudication is `reassigned` to the requested Organization;
- never treating `archived` or `unresolved` adjudications as current membership.

`atlas.is_organization_member(...)` follows that helper.

`atlas.is_organization_owner(...)` is satisfied by either:

- an effective active `owner` membership; or
- the current Principal holding active `root_governing` authority over an active Ledger that is the requested Organization's active `governing`, compatibility-primary participation.

This is a compatibility Organization-owner predicate. Ledger-specific governance must continue to use Ledger authority directly.

## Authenticated surfaces cut over

### Organization access

`organization_access_self_api_v1()` keeps its existing response keys but returns the canonical effective Organization. Historical physical Organization ID is additive metadata (`physicalOrganizationId`). Employee seat, credential, membership, and identity IDs are preserved.

For Anna this means the existing durable employment chain now presents **Elm Farm**, not the historical mixed `Feast Guild` carrier.

### Session context

`current_session_context_api_v1()`:

- projects `organizationMemberships` through effective custody;
- excludes `archived` and `unresolved` membership adjudications;
- exposes physical Organization ID additively;
- projects `profile.default_organization_id` through the profile's effective custody where adjudicated.

Lex's unresolved historical mixed-container owner membership is therefore not a current institutional membership. Lex's direct canonical Elm membership remains.

### Principal context

`principal_self_context_api_v1()` retains `principal.organizationId` only for compatibility and labels its semantics explicitly. It adds:

- `legacyCompatibilityOrganizationId`;
- `organizationIdSemantics = legacy_compatibility_only`;
- `governedLedgers`, using the canonical Principal → Ledger graph;
- `governedOrganizations`, deduplicated from active Ledger participations.

No single Organization is promoted as the Principal's governing root.

### Company Work

`organization_work_accountability_self_api_v1()` resolves each work item and completion Ledger entry through effective custody before:

- determining Organization authority;
- naming the Organization;
- returning `organizationId`.

It returns physical Organization/Ledger IDs only as additive provenance fields.

`organization_owner_decide_company_work_result_api_v1()` resolves the work item's effective Organization, checks owner authority against that canonical Organization, and then writes the acceptance/reopen event to the preserved physical Company Work chain. No historical work row is moved.

### Institutional Correspondence

`institutional_communications_home_self_api_v1()` continues to use the preserved physical membership and endpoint for transport/capability evidence, but resolves each endpoint's Organization through effective custody for presentation. It adds `physicalOrganizationId` and returns canonical `organizationId`/`organizationName`.

Transport state is not changed.

## Validation requirements

The production-shaped clone must prove:

1. direct canonical membership remains resolvable;
2. Anna's preserved physical employment membership resolves as canonical Elm;
3. unresolved legacy owner membership is excluded from session institutional memberships;
4. authenticated Organization access presents canonical Elm while preserving Anna's existing membership/seat/credential IDs;
5. Principal context exposes multiple governed Ledgers/Organizations and labels the legacy singleton Organization as compatibility-only;
6. Company Work physically stored on the historical carrier presents canonical Elm and can be decided by canonical Elm authority without changing the work item's physical Organization;
7. completion Ledger entries physically on the historical carrier present canonical Elm / Elm Farm Ledger;
8. institutional Correspondence physically on the historical carrier presents canonical Elm while endpoint/source/capture/send state remains unchanged;
9. Feast Guild remains clean-room and is not populated by the cutover;
10. archived/unresolved adjudications never become current institutional identity;
11. zero production/runtime triggers are disabled and FK deferrability is unchanged;
12. no new outbound communication operation is created;
13. browser roles gain no direct access to custody internals.

## Release boundary

After this tranche, current authenticated presentation and the selected authority seams operate through canonical custody, while physical historical storage remains behind the compatibility membrane.

This does **not** retire the historical carrier. A later retirement gate must first prove that remaining authenticated Organization-scoped APIs either operate canonically or are intentionally physical implementation seams.