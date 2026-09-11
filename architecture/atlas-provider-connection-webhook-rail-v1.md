# Atlas Provider Connection + Webhook Rail v1

## Purpose

Give every regular Atlas and every Ledger the same provider-neutral connection machinery without collapsing their custody.

A person's provider account is human-custodied. A Ledger/business provider account is organization-custodied. The OAuth/provider implementation is transport; Atlas owns the durable source, endpoint, conversation, permissions, and responsibility semantics.

## Connection movement

`authenticated Atlas actor`
→ `begin provider connection session`
→ `external provider authorization`
→ `provider callback verifies account identity`
→ `pending Connected Source`
→ `provider credential stored in Vault`
→ `source activated`
→ `provider assets/endpoints selected`
→ `communication endpoint/source binding`

Connection is deliberately two phase. Verifying provider identity may create/update a pending Connected Source, but the source is not `connected` until reusable credential custody exists.

## Custody

### Regular Atlas

- session custodian kind: `human`
- actor must be the authenticated human with an active Principal
- resulting Connected Source has `custodian_user_id=auth user`
- no organization custody is inferred

### Ledger

- session custodian kind: `organization`
- actor must have existing organization provider-connection authority
- resulting Connected Source has `custodian_organization_id=Ledger organization`
- business provider accounts are organization-owned from the beginning; they are not personal sources shared into a Ledger

## Session security

The database stores only callback correlation evidence:

- SHA-256 digest of OAuth `state` nonce;
- PKCE challenge where applicable, never the verifier;
- provider key;
- requested scopes/capabilities;
- intended custody root;
- bounded expiry;
- provider account identity after callback;
- resulting Connected Source id.

Raw OAuth state, PKCE verifier, authorization code, access token, refresh token, client secret, API key, and webhook secret are not stored in session metadata.

## Credential activation

Provider callback processing must:

1. verify provider callback state in the provider adapter;
2. resolve provider account identity from the provider, not user-entered text;
3. call the service identity-completion seam to establish a pending source;
4. store reusable credential through `store_connected_source_secret_service_v1`;
5. activate only after the expected credential reference exists.

An interrupted callback can therefore leave `pending`, never falsely `connected`.

## Webhook movement

`provider webhook`
→ `provider adapter verifies signature`
→ `immutable webhook delivery receipt`
→ `duplicate/hash conflict check`
→ `adapter normalizes provider payload into atlas_communication_event_v1[]`
→ `custody router`
→ human source: `ingest_principal_communication_events_service_v1`
→ organization source: `ingest_organization_communication_events_service_v3`
→ mark webhook delivery processed

A retry with the same provider delivery key and same payload hash is idempotent. The same delivery key with a different payload hash fails closed as a conflict.

## Provider adapters

Provider adapters may know:

- authorization URL and token exchange;
- provider account/profile/page discovery;
- webhook signature verification;
- webhook subscription mechanics;
- provider event → Atlas communication grammar normalization.

Provider adapters may not define:

- Atlas Principal or organization identity;
- durable communication endpoint identity;
- durable Atlas conversation identity;
- whether reading claims responsibility;
- Company Work responsibility;
- business truth.

## First practical adapters

- `fake`: deterministic test adapter proving the entire rail without external credentials.
- `meta`: Facebook/Instagram business transport adapter after Meta app credentials and permissions are configured.
- future adapters: Google, Microsoft, LinkedIn, SMS/voice providers, other social channels.

## Non-scope

This candidate does not deploy an Edge Function, create provider developer-app credentials, subscribe any production webhook, connect Elm Farm, or change Atlas/Vercel application code.

## Release boundary

This is a source candidate stacked on the current Principal provider foundation. Database custody/schema-clone validation must pass against the exact immutable head before any protected production release is considered.