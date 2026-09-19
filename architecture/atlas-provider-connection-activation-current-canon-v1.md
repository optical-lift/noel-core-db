# Atlas Provider Connection Activation — Current Canon v1

**Status:** Architecture contract for the first External Source Continuity implementation slice  
**Established:** September 19, 2026  
**Canonical repository:** optical-lift/noel-core-db  
**Supersedes as merge direction:** draft PR #501 connection-session/activation implementation  
**Does not supersede:** released Connected Source, secret-custody, Communication, Identity, implementation, or Organization authority.

## 1. Purpose

Atlas already has the durable external-account custody root: atlas.connected_sources.

Current production already has:

- human versus Organization custody on Connected Source;
- stable provider/account uniqueness inside that custody;
- Organization provider-connection authority;
- provider authorization lifecycle states;
- Vault-backed Connected Source secret custody;
- provider-neutral Connected Source observations;
- current Communication provider ingest beneath common Conversation/Event/Endpoint custody;
- Identity Source Record reconciliation;
- implementation source requirement/admission state.

What Atlas does not yet have is one current-canon connection movement that safely coordinates provider authorization before a Connected Source becomes usable.

Without that movement, each provider adapter can independently decide how to bind the initiating Atlas actor, remember intended custody, correlate an OAuth/API callback, establish provider account identity, create/reuse the Connected Source, store credentials, and decide when the source is actually connected.

This contract closes that gap before Gmail, Meta, Stripe, calendars, file providers, or other adapters add another local version.

## 2. Governing movement

    authorized Atlas actor
    -> bounded provider connection session
    -> external authorization
    -> callback proves provider account identity
    -> pending Connected Source created/reused under intended custody
    -> reusable credential enters existing secret custody
    -> source activation verifies required credential custody
    -> Connected Source becomes connected

This slice ends there.

Webhook delivery, historical sync, provider observation normalization, institutional mapping, domain consequence, and outbound provider execution are later Source Continuity slices.

## 3. Existing current-canon authority that must be reused

### Connected Source

atlas.connected_sources remains the only durable provider-account connection identity.

Current production already enforces exactly one human or Organization custody root, provider/account identity, the states pending / connected / reauthorization_required / revoked / error, and unique provider/account identity inside human or Organization custody.

No new provider-account table is permitted.

### Organization connection authority

atlas.organization_connected_source_authorized_self_v1(organization_id) is current authority for organization-level provider setup:

- active Organization owner; or
- active onboarding setup_actor.

Ordinary membership or consultant visibility is insufficient.

### Secret custody

atlas.store_connected_source_secret_service_v1(...) and atlas.connected_source_secret_refs already own reusable provider credential custody through Vault.

The connection-session tranche must not invent another credential store.

### Existing source commands

Current Organization source registration/transition commands already establish and govern Organization-owned Connected Sources.

They may be factored behind a provider-neutral internal seam where necessary, but their custody and transition laws must not be weakened or duplicated.

## 4. The first collision this tranche must repair

Current implementation intake has a truthful object: atlas.implementation_case_sources.

It answers:

> Which external source is required/admitted for this implementation case, and is it usable?

It does not answer:

> Who owns the external provider account?

Current register_implementation_connected_source_self_api_v1 can create a Connected Source with custodian_user_id = auth.uid() for the setup sponsor.

That was a workable onboarding carrier, but it is not safe as a general provider-connection law for an Organization account. A practitioner/setup sponsor authorizing an Organization's Stripe, Google Workspace, Meta, accounting, or similar account must not cause that account to become their personal Atlas source merely because they performed the setup action.

Therefore:

    Implementation Case Source != Connected Source custody root

Implementation may establish that a source is required, which provider is expected, which authorized person is carrying setup, whether authorization is pending/usable/blocked, and which Connected Source ultimately satisfies the requirement.

It may not manufacture source ownership.

## 5. Custody selection

A provider connection session must state intended Atlas custody before external authorization begins.

### Human custody

Allowed when the authenticated user has an active Principal and the provider account is truly personal/human-custodied.

Result:

    Connected Source.custodian_user_id = authenticated user
    Connected Source.custodian_organization_id = null

### Organization custody

Allowed when the target Organization already exists and the authenticated actor satisfies current Organization provider-connection authority.

Result:

    Connected Source.custodian_user_id = null
    Connected Source.custodian_organization_id = target Organization

### Implementation setup

An implementation/setup actor may initiate an Organization-custodied connection because current Organization source authority explicitly admits active setup_actor, not because implementation-case participation itself changes ownership.

An implementation_case_source may be linked to the resulting Connected Source after identity verification or activation according to its own governed command.

### Before an Organization exists

If implementation has identified a required Organization source but no canonical Organization exists yet, Atlas must not pretend the setup sponsor owns it.

The source requirement may remain identified / authorization_blocked / awaiting organization custody until a lawful custody root exists.

A future deliberately governed provisional-custody concept would require separate proof; it is not invented by this tranche.

## 6. Provider connection session

The connection session is short-lived authorization correlation, not durable provider identity.

It may preserve:

- session id;
- initiating actor user id;
- intended custody kind;
- intended human or Organization custody id;
- provider key;
- SHA-256 digest of OAuth/state correlation material;
- PKCE challenge where applicable, never verifier;
- requested scopes;
- requested Atlas capabilities;
- bounded callback/redirect context where required;
- expiry;
- lifecycle state;
- provider account identity after callback;
- resulting Connected Source id;
- non-secret failure/provenance metadata.

It must not store raw OAuth state when a digest suffices, authorization code, PKCE verifier, access token, refresh token, client secret, API key, webhook secret, or provider password.

Session lifecycle should distinguish at minimum:

    pending -> identity_verified -> connected
    pending / identity_verified -> failed | expired

Session state is authorization-workflow state. It is not Connected Source authorization state and not domain truth.

## 7. Actor binding

The session must bind to the initiating authenticated actor at creation.

A callback/service completion may run under service authority, but it must complete an already bounded session. It may not accept an arbitrary actor or custodian supplied by the callback and create a new source from that alone.

Where the provider supports a state parameter:

- browser-visible state remains opaque/high entropy;
- Atlas stores a digest or similarly bounded proof;
- provider adapter verifies callback state against the session;
- session expiry is enforced;
- completed/failed/expired session is not silently reused as fresh authorization.

## 8. Provider account identity

The stable provider account key must come from provider-verified callback/API evidence, not user-entered display text.

Display label, email/account hint, page name, workspace name, or similar values are descriptive evidence only.

Connection completion reuses the existing Connected Source when truthful identity matches:

    human: custody user + provider_key + provider_account_key
    organization: organization custody + provider_key + provider_account_key

Retrying the same truthful connection must not mint another Connected Source.

A callback resolving a different provider account is a different source identity and must not overwrite the old account identity.

## 9. Two-phase activation

Provider identity verification and Connected Source activation are separate.

After the callback proves account identity, Atlas may establish/reuse the source as authorization_state = pending and bind it to the connection session.

The adapter then stores reusable credential through current atlas.store_connected_source_secret_service_v1 or a later governed secret-custody replacement.

Only after the required credential reference exists may a service-only activation seam move the source to authorization_state = connected.

This prevents an interrupted callback from leaving a falsely usable source.

## 10. Revocation and reauthorization

Current Connected Source law already forbids silently reviving a revoked source.

This tranche preserves that law.

A source in revoked requires an explicit future reauthorization policy. A connection callback must not simply clear revoked_at because provider authorization succeeded.

reauthorization_required and error may return to connected only through an allowed transition plus fresh credential evidence.

## 11. Scopes and capabilities

Provider scopes are provider authorization evidence.

Atlas capabilities are declarations of what the source is configured/authorized to support inside Atlas.

They are distinct:

    provider scopes != Atlas permissions
    provider scopes != Atlas capabilities
    Atlas capabilities != domain authority

A downstream domain still checks its own authority before consequence.

## 12. No provider-specific semantics in the shared rail

The shared connection/activation layer may know provider key, provider account key, scopes, generic requested capabilities, callback/session lifecycle, and secret-custody requirements.

It may not know Gmail thread semantics, Stripe Checkout meaning, Meta Page/Instagram asset meaning, Microsoft Graph delta semantics, or domain-specific Money/Work/commerce consequences.

Those belong to provider adapters and owning domains.

## 13. Relationship to historical PR #501

PR #501 correctly identified actor-bound sessions, human versus Organization intended custody, digest-only callback correlation, two-phase activation, secret custody before connected state, provider-verified account identity, and idempotent Connected Source reuse.

Those ideas should be replayed.

The PR must not be merged as historical source because current canon has materially changed:

- common Communication Conversation/Event/Endpoint now owns Correspondence;
- Principal provider communication ingest is released;
- Organization Connected Source commands are released;
- secret custody is released;
- Identity/External Relationship reconciliation is released;
- evidence and commercial source interpretation have evolved;
- the old PR couples its generic webhook rail directly to a Communication event ingest path.

This contract replaces #501 as the source of truth for the first replay slice.

## 14. Explicit non-scope of implementation slice 1

Do not add yet:

- provider webhook delivery table;
- universal webhook router;
- Communication-specific provider ingest router;
- historical sync scheduler;
- source-health universal table;
- Gmail/Google adapter;
- Meta adapter;
- Stripe adapter;
- provider asset selection;
- provider-specific UI;
- universal Provider object;
- universal Source Observation table;
- domain mapping rules.

Those become later slices only after connection/activation is clone-validated.

## 15. Required validation before release

The canonical migration implementing this contract must prove on a production-schema clone:

1. signed-out caller cannot begin a connection;
2. active Principal can begin a human-custodied session for self only;
3. human session cannot name Organization custody;
4. Organization owner can begin an Organization session;
5. active Organization setup_actor can begin an Organization session;
6. ordinary member cannot begin/rebind an Organization source;
7. consultant membership alone cannot begin/rebind an Organization source;
8. session stores only digest/challenge/non-secret callback correlation;
9. expired session cannot complete;
10. service completion cannot change intended custody;
11. provider account identity is required before source creation/reuse;
12. same custody/provider/account retry reuses one Connected Source;
13. human and Organization source identity remain distinct;
14. provider identity completion leaves source pending;
15. source cannot become connected before required credential reference exists;
16. storing credential through current Vault custody then activating succeeds;
17. no provider secret appears in session or Connected Source metadata;
18. revoked source is not silently revived;
19. requested/granted provider scopes do not grant unrelated Atlas authority;
20. implementation-case source may link to the resulting source without becoming its custody root;
21. no existing Connected Source, Communication, Identity, Money, Work, or implementation command is weakened.

## 16. Application/API boundary

The browser-facing start operation may return only bounded authorization-session information needed to begin provider authorization.

Provider callback completion and source activation are service-side operations.

The application must not receive reusable provider credentials, write Connected Source tables directly, choose provider account identity without provider proof, mark a source connected, or infer Organization source-administration authority in presentation code.

## 17. Next slice

After connection/activation is canonical, the next Source Continuity slice should govern delivery receipt plus observation/reconciliation custody:

    verified provider delivery/fetch
    -> idempotent delivery/observation custody
    -> provider adapter normalization
    -> source-specific/domain-specific observation seam
    -> coverage/reconciliation update

Only after that should a concrete adapter such as Google, Meta, or Stripe become the proof fixture.
