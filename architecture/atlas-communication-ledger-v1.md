# Atlas Communication Ledger v1

## Purpose

Establish the person-owned Atlas Continuity custody layer beneath Ask Atlas and every future communication adapter.

The governing sequence remains:

`source → capture → custody → reconciliation → interpretation → authorized state`

This tranche implements source registration, relay authentication, and custody only. It does not interpret communication into tasks, decisions, CRM state, calendar state, payment state, Company Work, inventory state, or other governing truth.

## First real fixture

The initial macOS Messages fixture produced by `farm-atlas` on 2026-08-31 is the acceptance set:

- 3,932 canonical communication events;
- 2,328 incoming / 1,604 outgoing;
- 8 source threads;
- 3,929 exact-text events (99.92%);
- 3 empty-body events preserved without inference;
- 0 invalid events;
- 0 missing event refs, thread refs, or timestamps;
- 0 duplicate event refs or content hashes;
- manifest count and SHA-256 both verified.

The raw fixture remains private source evidence on the fixture Mac and is not committed to Git.

## One external-source registry

Atlas already has `atlas.connected_sources` as the canonical registry of externally authorized sources. Communication custody therefore does **not** create a second source-account ontology.

For Apple Messages on the first Mac:

- `connected_sources.custodian_user_id` is the human account custody root;
- `provider_key = apple_messages`;
- `provider_account_key` is the stable adapter account reference carried by canonical events;
- `capabilities.communicationCapture = true` marks the source as a communication source.

A communication event is then identified by:

`(connected_source, source_event_ref)`

The event also carries `principal_id` so person-owned read policy remains explicit. A database trigger requires the Principal's `user_id` to equal the connected source's `custodian_user_id` on every custody row.

Farm, Organization, Household, buyer profile, property, project, CRM opportunity, or other downstream entity may later be linked to a communication claim, but none owns the raw source communication.

## Relay authentication

RiverSong or another source device must never hold a Supabase service-role key or reusable browser session.

`atlas.communication_relay_credentials` stores only a SHA-256 hash of a revocable ingest credential. The plaintext relay credential remains on the paired device with user-only local permissions.

Pairing happens through `atlas.register_communication_relay_api_v1(...)`, which:

1. requires an authenticated Atlas human;
2. resolves that human's active `atlas.principals` row;
3. creates or reconnects the human-owned `atlas.connected_sources` row;
4. revokes any prior active relay credential for that source;
5. stores the new credential hash;
6. returns no secret from the database.

The application creates the plaintext token and returns it once to the authenticated user. The database sees only its digest.

Relay ingestion happens through `atlas.ingest_communication_events_relay_api_v1(...)`. It is callable only by the server `service_role`, not by the relay device directly. The Vercel route hashes the presented bearer token and passes only the digest to PostgreSQL.

The ingest function derives the Principal and connected source from that credential. The relay cannot supply or override a Principal ID, organization ID, farm ID, or destination entity.

## Two independent event hashes

Each event preserves two integrity signals:

1. **Adapter content hash** — deterministic fingerprint of the source-observed message state.
2. **Database custody source hash** — PostgreSQL independently hashes the source-observed canonical fields it receives.

The database hash intentionally excludes acquisition metadata such as `capturedAt`. Re-reading the same message tomorrow therefore remains `alreadyInCustody`; a changed source-observed body, participants/source payload, direction, speaker, source identity, body state, or occurrence state becomes a conflict.

## Append-only source event rule

`atlas.communication_events` is immutable source evidence. UPDATE and DELETE are rejected by trigger.

If the same `(connected_source, source_event_ref)` arrives again:

- same adapter hash + same database custody hash → `alreadyInCustody`;
- changed source-observed state → append `communication_event_conflicts`; never overwrite the original event.

Later support for edits, unsends, reactions, or deletions should add explicit source observations/version records rather than mutating history.

## Required acceptance behavior

For the exact 3,932-event fixture:

### First ingest

- supplied: 3,932
- admitted: 3,932
- already in custody: 0
- conflicts: 0

### Exact replay

- supplied: 3,932
- admitted: 0
- already in custody: 3,932
- conflicts: 0

### Later re-observation with only acquisition metadata changed

- admitted: 0
- already in custody: 1
- conflicts: 0

### Same source event with changed source-observed state

- admitted: 0
- already in custody: 0
- conflicts: 1
- original source event unchanged

## Incremental/live capture behavior

The database contract deliberately permits overlapping capture windows. A Mac relay may reread recent source history after wake/sleep/offline periods and rely on idempotent custody to collapse duplicates.

A relay batch is limited to 1,000 events so long catch-up windows can be chunked safely. Each batch records:

- source and Principal custody root;
- relay credential used;
- capture mode;
- supplied/admitted/already/conflict counts;
- source occurrence bounds;
- optional manifest metadata.

`atlas.connected_sources.last_sync_at` and Continuity metadata are updated only after successful custody admission.

`atlas.communication_source_health_self_api_v1()` exposes person-owned source health without exposing relay token hashes.

## Privacy and access

All Continuity custody tables have RLS enabled.

Authenticated users receive read access only to communication rows whose `principal_id` resolves to their own active Principal. Anonymous access is revoked. Direct client writes to communication tables are not granted.

Relay credential rows are not directly readable by `authenticated`; only pairing/ingest functions touch them.

Future employer, organization, household, practitioner, collaborator, or buyer-profile access must cross a separate explicit sharing/authority membrane. Organizational membership must never imply access to a human's raw communications.

## Deliberately not included yet

- no production migration identity in this proof branch;
- no production release;
- no raw fixture upload yet;
- no communication interpretation/claim extraction;
- no identity/entity resolution;
- no Journal projection;
- no Ask Atlas communication read surface;
- no independent iPhone/device reconciliation;
- no claim that a local Mac contains every message on the authoritative Apple source;
- no resolution of the three empty-body fixture events yet.

## Rollback proof

The proposed DDL and ingest behavior are exercised against the live PostgreSQL engine inside explicit transactions ending in `ROLLBACK` before migration materialization.

The proof must verify:

1. authenticated pairing into the existing `connected_sources` human root;
2. relay credential is stored hashed and source-bound;
3. first admission;
4. exact replay idempotency;
5. later re-observation with changed `capturedAt` remaining idempotent;
6. changed source-observed state becoming a conflict;
7. original source event remaining immutable;
8. source/Principal mismatch being rejected;
9. no Continuity tables/functions surviving rollback.

The earlier proof already caught one issue: `pgcrypto.digest` is installed in the `extensions` schema. The contract therefore explicitly calls `extensions.digest(...)` rather than broadening function `search_path`.

## Migration custody

This branch remains a **schema proof**, not a production migration release.

`noel-core-db` is the canonical post-fence database authority. The final migration identity must be generated with the repository's governed Supabase migration workflow rather than inventing a timestamp while concurrent migrations are advancing production.
