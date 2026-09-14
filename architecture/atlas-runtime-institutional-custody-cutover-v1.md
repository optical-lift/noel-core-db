# Atlas Runtime Institutional Custody Cutover v1

## Purpose

Move selected authenticated Atlas presentation and authority seams from historical physical Organization storage to the canonical institutional custody established by `20260914000504_atlas_institutional_custody_reconstruction_v1.sql`, without breaking the still-physical compatibility-era APIs that have not yet been cut over.

This tranche is a **targeted runtime membrane**, not a global reinterpretation of every Organization helper and not a physical rehome.

## Critical distinction

Atlas currently has two legitimate kinds of Organization semantics during the transition:

1. **Physical compatibility semantics** — existing APIs that still operate directly on preserved historical `organization_id` values. These must keep using the existing `current_organization_membership_v1`, `is_organization_member`, and `is_organization_owner` contracts until each caller is deliberately migrated.
2. **Effective canonical semantics** — the selected Stage-2 surfaces that must present or authorize against canonical institutional custody even though the underlying rows remain physical.

The first `20260914010315` candidate incorrectly replaced the global physical helpers. It was superseded before merge/release after a blast-radius audit showed many untouched authenticated APIs still depend on those physical semantics, including generic-email transport/history/credential controls, commercial correspondence, project/task controls, Organization Ledger owner windows, Company Work planning, and operating-knowledge reads.

This replacement therefore leaves all global physical helpers unchanged and introduces separate effective-custody helpers used only by the surfaces explicitly cut over here.

## Governing laws

1. **Canonical custody governs selected presentation and authority.** A row adjudicated `reassigned` is presented and authorized against its canonical Organization/Ledger on Stage-2 surfaces.
2. **Physical compatibility remains valid behind the membrane.** Existing non-cut-over APIs may continue to use physical Organization membership/owner predicates until migrated deliberately.
3. **No semantic monkey-patching.** Stage 2 does not globally change what `is_organization_member` or `is_organization_owner` means.
4. **Physical history remains immutable.** Work items, execution results, acceptances, communication endpoints, connected sources, memberships, employee seats, credentials, and Ledger entries remain physically where established.
5. **Unresolved and archived custody never becomes canonical institutional identity.** Effective helpers return no canonical membership/authority for those adjudications.
6. **Direct canonical rows remain canonical.** Rows with no adjudication remain their physical Organization/Ledger unless they are inside an active compatibility carrier with stronger explicit Unit evidence.
7. **Membership and Principal authority are distinct.** Effective employee access resolves through effective membership/seat/credential custody. Effective Organization-owner compatibility authority may also be proven by current Principal root authority over that Organization’s active governing compatibility-primary Ledger.
8. **Ledger authority is not flattened generally.** Only root authority over the Organization’s active `governing`, compatibility-primary Ledger satisfies the effective Organization-owner compatibility predicate. Operating/sibling/dependency Ledgers do not confer Organization-wide authority.
9. **Company Work writes remain physical while selected authority becomes canonical.** The work item’s effective custody determines who may decide it; the acceptance/event remains attached to the preserved physical Company Work chain.
10. **Correspondence presentation becomes canonical while transport remains physical.** Endpoint/source IDs, bindings, capability grants, capture/send state, credentials, heartbeat state, and communication history are untouched.
11. **No trigger bypass, FK rewrite, mail activation, polling, or outbound send.**
12. **Compatibility is visible, never normative.** Principal context may expose the legacy singleton Organization only under an explicitly named compatibility field; governed Ledgers/Organizations are the governing truth.

## Effective-only helpers

Stage 2 introduces private effective helpers without replacing their physical predecessors:

- `current_effective_organization_membership_v1(canonical_organization_id)`
- `is_effective_organization_member_v1(canonical_organization_id)`
- `is_effective_organization_owner_v1(canonical_organization_id)`
- `effective_work_item_organization_v1(work_item_id)`
- `effective_communication_endpoint_organization_v1(endpoint_id)`

### Effective membership

The current Person’s membership resolves by:

- preferring a direct active membership in the requested canonical Organization;
- otherwise accepting an active membership whose immutable custody adjudication is `reassigned` to that Organization;
- never using `archived` or `unresolved` adjudications as canonical membership.

The existing physical `current_organization_membership_v1` remains untouched.

### Effective Organization-owner authority

The effective owner predicate is satisfied by either:

- an effective active `owner` membership; or
- current Principal `root_governing` authority over an active Ledger participating as the requested Organization’s active `governing`, compatibility-primary Ledger.

An active institutional custody carrier is explicitly excluded from this Principal-authority route.

The existing physical `is_organization_owner` remains untouched so compatibility-era APIs using the old carrier keep functioning.

### New compatibility-era rows

Stage 1 adjudicated rows that existed when it ran. New rows can still be written physically to the historical carrier before physical retirement.

For Company Work and communication endpoints only, Stage 2 permits a fallback from the row to its explicit `organization_unit_id`. If that Unit itself has immutable `reassigned` custody, the row inherits that canonical Organization for the selected runtime surface. If the row has no direct adjudication and no explicit adjudicated Unit, an active compatibility carrier is **not guessed** as canonical.

## Authenticated surfaces cut over

### Principal Ledger projection

`principal_ledgers_self_api_v1()` excludes active compatibility-carrier Ledgers while leaving the underlying legacy authority row intact.

### Organization access

`organization_access_self_api_v1()` keeps its mature physical employee-seat/credential query behind a private compatibility function, then maps each returned membership to effective custody for presentation.

The response preserves physical membership/seat/credential IDs and adds `physicalOrganizationId` while presenting canonical `organizationId` / `organizationName`.

For Anna, the durable physical employment chain therefore presents Elm Farm rather than the historical mixed carrier.

### Session context

`current_session_context_api_v1()` keeps its mature session validation behind a private compatibility function, then:

- projects `organizationMemberships` through effective custody;
- excludes `archived` and `unresolved` membership adjudications from canonical presentation;
- exposes physical Organization ID additively;
- projects `profile.default_organization_id` through profile custody where adjudicated.

Lex’s unresolved historical mixed-container owner membership is not a canonical institutional membership; Lex’s direct canonical Elm membership remains.

### Principal context

`principal_self_context_api_v1()` retains the historical `principals.organization_id` only as explicitly named compatibility evidence. It adds:

- `legacyCompatibilityOrganizationId`;
- `organizationIdSemantics = legacy_compatibility_only`;
- `governedLedgers` from the Principal → Ledger graph, excluding active custody carriers;
- `governedOrganizations`, deduplicated from those active Ledger participations.

No single Organization is promoted as the Principal’s governing root.

### Company Work accountability and decision

`organization_work_accountability_self_api_v1()` uses effective-only helpers to:

- determine canonical owner Organizations;
- present pending Company Work against effective Organization custody;
- present established completion events against the effective source work chain while preserving physical Organization/Ledger IDs as provenance.

`organization_owner_decide_company_work_result_api_v1()` authorizes using the work item’s effective Organization and the effective owner predicate, then writes the acceptance/reopen event to the preserved physical Company Work chain. It records canonical authority evidence alongside physical provenance.

Existing planning/scheduling APIs are **not** cut over by this tranche and continue to use physical helper semantics.

### Institutional Correspondence

`institutional_communications_home_self_api_v1()` keeps the mature physical membership, endpoint, source, capability, credential, and heartbeat logic behind a private compatibility function. The outer membrane maps endpoint Organization identity to effective custody for presentation only.

Transport state does not change.

## Compatibility functions

The existing mature bodies are renamed behind private, non-browser-executable compatibility functions:

- `organization_access_physical_compatibility_internal_v1()`
- `current_session_context_physical_compatibility_internal_v1()`
- `principal_self_context_physical_compatibility_internal_v1()`
- `institutional_communications_home_physical_compatibility_internal_v1()`

The public API names are recreated as effective-custody wrappers with the original authenticated/service-role execution boundary.

## Validation requirements

The production-shaped clone must prove:

1. the preexisting physical membership/owner helpers keep their physical semantics;
2. effective helpers resolve direct canonical membership and reassigned membership separately;
3. unresolved legacy membership is excluded only from effective/canonical identity, not deleted or made unusable for still-physical APIs;
4. Anna’s preserved physical employment presents canonical Elm;
5. Principal projection hides the active compatibility carrier and exposes multiple governed Ledgers/Organizations;
6. Company Work physically stored on the carrier presents canonical Elm and can be decided by effective Elm authority while the physical row stays put;
7. new compatibility-era Company Work without direct adjudication can inherit Elm only from an explicitly adjudicated Elm Unit;
8. Correspondence physically on the carrier presents canonical Elm while endpoint/source/capture/send state remains unchanged;
9. new compatibility-era endpoints without direct adjudication can inherit Elm only from an explicitly adjudicated Elm Unit;
10. Feast Guild remains clean-room;
11. no outbound communication is created;
12. compatibility internals and effective helpers remain browser-inaccessible;
13. zero runtime triggers are disabled and FK deferrability is unchanged.

## Release boundary

After this tranche, the selected authenticated surfaces operate through canonical custody while untouched compatibility-era APIs retain their preexisting physical semantics.

This is a **partial runtime cutover**, not retirement of the historical carrier. Later tranches must migrate remaining physical callers one governed contract at a time before the carrier and its legacy authority can be retired.