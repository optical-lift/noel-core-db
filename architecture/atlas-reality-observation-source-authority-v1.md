# Atlas Reality Observation — Connected Source Authority v1

**Status:** Current-canon database/application contract candidate  
**Established:** September 25, 2026  
**Scope:** Authenticated use of a Connected Source for read-only Reality Observation  
**Depends on production release of:** `20260919233031_atlas_provider_connection_activation_current_canon_v1`  
**Related Atlas contract:** `optical-lift/atlas/docs/architecture/ATLAS_INTAKE_INTERPRETATION_V1.md`

## Purpose

Atlas already separates provider custody, provider evidence, interpretation, and canonical domain consequence. The Reality Observation Membrane makes that separation explicit across machine and human observers.

This contract closes one narrower database gap:

> A person being allowed to **see that a Connected Source exists** is not the same as being allowed to **use its reusable credential to inspect the external source**.

The first machine-observer proof uses an authenticated supplier catalogue, but this contract is provider- and domain-neutral.

## Governing movement

```text
authenticated Atlas actor
→ exact Connected Source
→ observation-use authority proof
→ non-secret observation context
→ server-side credential retrieval
→ bounded acquisition method
→ provider/source evidence
→ source observation custody where fitting
→ owning-domain interpretation
```

The authority proof ends before reusable credential material is returned.

## Authority distinction

Current `connected_sources_self_api_v1` intentionally exposes source status to the human or Organization context that may need to understand its integrations.

That visibility must not be reused as credential-use authority.

For v1, observation-use authority is deliberately narrow:

- a human-custodied source may be observed by that exact authenticated human;
- an Organization-custodied source may be observed only by an actor who already satisfies the current Organization Connected Source administration authority (active owner or active onboarding `setup_actor`);
- the source must currently be `connected`;
- the caller may additionally require an exact provider key and declared source capability before acquisition begins.

Ordinary Organization membership alone is insufficient in this first slice.

This is intentionally conservative. A later source-use capability grant may widen lawful operational use without widening configuration administration, but that requires its own proof. This contract does not create a universal permission table.

## New authenticated membrane

`atlas.connected_source_observe_authorized_self_v1(source_id)`

Answers only whether the current authenticated actor may use that Connected Source for observation under the v1 law.

`atlas.prepare_source_observation_self_api_v1(source_id, provider_key, capability)`

Returns only bounded non-secret source context after:

1. exact observation-use authority;
2. current `connected` authorization state;
3. optional exact provider-key match;
4. optional declared capability match.

It does not return a password, cookie, OAuth token, refresh token, browser storage state, API key, or Vault reference.

## Credential custody

Reusable credentials remain owned by the existing Vault-backed Connected Source secret contract.

The application may retrieve one exact credential only through service authority after the authenticated preparation membrane has succeeded.

The machine observer receives only the credential material required for that bounded acquisition attempt. It does not receive Supabase service-role authority.

## REST membrane repair

Current source functions for Organization Connected Source registration/transition/sync and service-only secret/observation operations live canonically in the `atlas` schema.

The application uses PostgREST RPC calls through the public API surface. Several long Organization function names are also vulnerable to PostgreSQL's 63-byte identifier truncation and are not present as stable public RPC names.

This candidate therefore adds short public wrappers for the existing canonical functions. The wrappers do not create second authority; they only expose stable application/service transport names.

Authenticated wrappers:

- `begin_source_connection_self_api_v1`
- `organization_source_authorized_self_api_v1`
- `register_organization_source_self_api_v1`
- `transition_organization_source_self_api_v1`
- `update_organization_source_sync_self_api_v1`
- `prepare_source_observation_self_api_v1`

Service-only wrappers:

- `complete_source_connection_identity_service_v1`
- `activate_source_connection_service_v1`
- `store_source_secret_service_v1`
- `read_source_secret_service_v1`
- `delete_source_secret_service_v1`
- `record_source_observation_batch_service_v1`
- `bind_source_org_unit_service_v1`

## Truth boundary

```text
source visible
!= source usable

source usable
!= credential visible to the human

credential usable
!= observation succeeded

observation succeeded
!= provider claim is canonical truth

provider claim
!= domain consequence

read authority
!= write authority
```

No function in this slice purchases, reserves, messages, changes provider state, establishes procurement, establishes Work readiness, or writes another domain's truth.

## Browser-session connection ceremony

A browser-only provider still uses the same current-canon provider-connection rail:

```text
authorized actor
→ begin provider connection session
→ isolated interactive browser carrier
→ provider authentication succeeds
→ provider adapter proves stable account identity
→ Connected Source identity completed under intended custody
→ browser storage state enters Vault as browser_storage_state_v1
→ activation verifies credential custody
→ Connected Source becomes connected
```

The interactive browser carrier is temporary authorization machinery. It does not become durable provider identity.

The Atlas application server must not receive the user's provider password. Browser interaction may travel directly from the user's browser to the isolated authorization worker under a short-lived interaction token. The worker must not log typed input or persist screenshots/session state.

Successful login is insufficient until the provider adapter can establish a stable provider account identity. Where a provider's login identifier is itself the stable account identifier, the adapter may use a privacy-preserving digest of that identifier only after successful provider authentication proves that the session belongs to it.

The worker returns reusable browser storage state only to a signed Atlas service callback. That callback must complete provider identity, store the reusable session in Vault, and activate the Connected Source through the existing two-phase connection rail.

Abandoned browser ceremonies expire naturally. They do not weaken or bypass the durable provider-connection session lifecycle.

## First proof

The first application proof may ask:

> What current offers does this authorized source expose that could satisfy 50 cm red roses for the requested delivery context?

A successful acquisition may preserve provider evidence in `connected_source_observations` because that storage shape fits this provider-observation case.

The Reality Observation Membrane remains broader than that table. Human physical observations, files, photos, and other evidence paths do not become Connected Source observations merely to appear uniform.

## Production boundary

This candidate deliberately depends on the current-canon provider connection session/activation migration already present in source.

Current production does not yet contain:

- `atlas.provider_connection_sessions`;
- `atlas.begin_provider_connection_self_api_v1`;
- `atlas.complete_provider_connection_identity_service_v1`;
- `atlas.activate_provider_connection_service_v1`.

Therefore the governed release order is mandatory:

```text
1. production-schema clone + release provider connection activation current canon
2. generate this observation/source-authority migration from its immutable candidate
3. production-schema clone + release this candidate
4. only then deploy an application that calls the new public wrappers
```

This candidate must not be made self-contained by duplicating those already-canonical provider-connection structures merely to bypass release order.

This file and its candidate SQL do not authorize production mutation.

The candidate must enter the governed migration-source generation lane, receive production-schema-clone proof, and cross the explicit production release boundary before the application depends on it in production.
