# Atlas Facebook Asset Discovery v1

## Purpose

Facebook Login is an authorization relationship with a human Facebook account. It is not itself a durable Atlas communication source.

A single Facebook authorization can expose multiple managed Facebook Pages, and each Page can optionally expose a linked Instagram professional account. Those assets can belong to different Atlas custody roots or may not belong in Atlas at all.

Atlas therefore separates **authorization**, **discovery**, **selection**, and **source activation**.

## Governing rule

A Facebook user authorization must never be collapsed into one Connected Source.

The flow is:

1. Atlas chooses the intended custody root before OAuth begins (`human` or one organization/Ledger).
2. Facebook Login authorizes the human account.
3. The provider adapter discovers the Pages that authorization can manage and any linked Instagram professional accounts.
4. Atlas records those assets as temporary candidates only.
5. The signed-in Atlas actor explicitly selects one or more candidates for the already-chosen custody root.
6. Each selected Facebook Page or Instagram account becomes its own pending Connected Source.
7. The adapter reacquires the corresponding Page access token from the still-valid temporary authorization grant.
8. The selected source's reusable token enters Vault custody.
9. Provider webhook subscription succeeds.
10. Only then may that source become `connected`.

## Temporary authorization grant

The Facebook User Access Token belongs to a short-lived authorization grant, not to any business Page source.

The grant stores:

- the Atlas actor who authorized Facebook;
- the already-selected Atlas custody root;
- the provider authorization subject key;
- a Vault reference to the temporary Facebook User Access Token;
- expiration and revocation state;
- non-secret provider metadata.

The raw User Access Token is never returned to the Atlas client and never stored in ordinary metadata.

## Candidate assets

Discovered candidates contain only non-secret information needed for a person to choose correctly:

- asset kind (`facebook_page` or `instagram_business`);
- provider asset key;
- parent Page key for linked Instagram assets;
- display label;
- provider task/capability evidence;
- non-secret metadata.

Page access tokens returned by `/me/accounts` are deliberately stripped before candidate persistence or client response.

Discovery does not establish Atlas ownership or custody truth beyond the custody root already selected for this connection attempt. A candidate is only evidence that the authorizing Facebook account could see/manage that provider asset at discovery time.

## Selection

Selection is a signed-in Atlas action.

Only the actor who created the short-lived authorization grant may select its candidates in v1. This keeps the callback/selection transaction narrow and prevents a temporary provider authorization from becoming a transferable credential.

Selecting a candidate creates a durable selection record. The provider adapter then uses that selection to reacquire the current Page token and complete the source.

The same external Facebook Page or Instagram account must not be connected to multiple Atlas custody roots. Source creation fails closed if an active/pending source with the same provider account key already exists under a different custody root.

## Source identities

Selected provider assets become separate Connected Sources:

- Facebook Page → `provider_key = facebook`, `provider_account_key = <page id>`
- linked Instagram professional account → `provider_key = instagram`, `provider_account_key = <ig user id>`

The Facebook human user ID is authorization provenance, not the source account key for either business asset.

## Provider tasks and permissions

Provider-reported Page tasks are evidence used to determine whether a selected asset can support requested capabilities. They do not create Atlas roles or Atlas responsibility.

For example, Meta currently requires Page messaging authority/permissions for Messenger operations, and linked Instagram messaging through Facebook Login depends on a Page token with the relevant Instagram/Page permissions. Atlas records this as provider capability evidence only.

## Failure and retry

A selection can be retried safely while its authorization grant remains valid.

A source must remain pending if:

- the Page is no longer returned by Meta;
- the required provider task is absent;
- the Page token cannot be reacquired;
- token Vault custody fails;
- webhook subscription fails;
- source custody is ambiguous.

A failed provider step must never leave the source falsely marked connected.

## Truth boundary

Neither Facebook Login nor asset discovery may directly:

- create responsibility or assign a person;
- create Company Work;
- establish that a Page belongs to an organization merely because a Facebook user can administer it;
- merge people or external identities;
- move a source between a Principal and a Ledger;
- make provider thread identity the durable Atlas conversation identity.

## Deployment boundary

This candidate is source/schema work only. It does not create a Meta app, store production Meta credentials, connect a real account, deploy an Edge Function, mutate production, modify the Atlas app repository, or authorize a Vercel deployment.
