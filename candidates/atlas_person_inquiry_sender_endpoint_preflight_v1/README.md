# Atlas Option C — Sender Endpoint Preflight v1

**Status: candidate only.** No live migration, outbound email, recipient challenge, identity binding, relationship admission, account, Ledger seat or Work consequence. Companion to the live source-intent, public-route preflight and immutable owner source-review contracts.

## Purpose

After a Ledger owner records the source of an already-observed recipient email, allow that exact owner to inspect whether a **separately selected, Ledger-scoped sending endpoint** has the structural pieces needed for a later governed Correspondence inquiry.

This is *not* send permission. The public RPC always returns `canSend=false` and `messageSent=false`, even when every observed sender prerequisite is present. Only an independent recipient suppression/opt-out check, actual provider sender permission and delivery health review, preview, per-message authorization and separately governed dispatch can change that in a future packet.

## Reuse, not parallel infrastructure

- The live `person_contact_inquiry_intent_owner_self_api_v1` establishes the signed-in canonical Person, governing Principal, native active Ledger seat, and exact owner/inquiry scope.
- The append-only `person_contact_inquiry_owner_address_reviews` establishes source testimony and withdrawal, **not recipient consent**. Unreviewed/withdrawn inquiries do not probe sender endpoints.
- Existing `communication_endpoints`, `correspondence_identities`, endpoint bindings and `connected_sources` establish structure; receive-only/pending sources cannot count as outbound-connected.
- Existing `resolve_institutional_communication_operation_self_v1(endpoint,'message.send')` is the institutional **Person-responsibility** authority test (including its current transitional carrier). This packet never upgrades the old membership carrier to canonical employment or treats it as the authority. Personal-sender authority stays unverified until reviewed by its own owner-scoped transport.
- Sender endpoint IDs in other Ledgers, inactive or unscoped IDs, and nonexistent IDs receive the same non-disclosing unavailable result.

## API

`public.person_inquiry_sender_endpoint_preflight_owner_self_api_v1(ledger_id, inquiry_id, communication_endpoint_id)`

Authenticated self-service, exactly scoped. Returns source review state, sender endpoint readiness, Correspondence identity binding, connected outbound source existence, existing institutional send-operation authority, and the **next missing prerequisite**. It returns neither another Ledger's email nor identity match, source-provider tokens, grants or provider account secrets.

Every response preserves the negative boundaries: **no sender transport verification, no recipient suppression clearance, no recipient consent, no permission to send, no message sent, no stage-one claimant response, no stage-two relationship claim, no Person admission, no Ledger seat or Work permission**.

## Observed live blocker at candidate authoring

The production-schema inventory had two connected **receive-only** email source bindings and one **pending** `send_receive` binding. There was no observed connected outbound email binding. This is a snapshot, not an enduring invariant. Do not turn a connected inbox into a sending identity.

## Independent clone verification

1. Import candidate SQL into a disposable **production-schema clone**, not directly into production.
2. Run `postconditions.sql`. Confirm signature, owner guard, revoked-anon access, source-review, withdrawal, Ledger scoping and no-send assertions.
3. Test a valid owner and exact inquiry in a rolled-back fixture. For unreviewed/withdrawn owner testimony, endpoint probing must not occur.
4. Test own organization endpoint and own personal endpoint separately. Neither may inherit another Ledger's endpoint or connected source.
5. Test unconnected, pending and receive-only sources. None may report connected outbound transport.
6. Test missing Correspondence identity binding. A label/logo alone is not a sender identity binding.
7. Test a canonical institutional Person with/without `message.send` Reality responsibility and the existing transitional endpoint carrier. A generic worker/employee label is not send authority.
8. Test wrong authenticated Person, wrong Ledger, wrong inquiry, inactive endpoint and cross-Ledger endpoint. Calls must not enumerate protected identity or private sender configuration.
9. Confirm no mail, OTP, network call, account, relationship, Work, or Person record is created, before and after the tests.
10. Inspect current production migration custody and execute the governed `atlas_` generation, independent clone checks and protected release gates **only after review**.

## Subsequent packets (not authorized here)

- Exact-address recipient suppression, opt-out, purpose and transport-policy review — current entity-keyed suppressions do not by themselves establish clearance for any arbitrary owner-supplied email.
- Verified sender/provider capability, per-message preview and explicit authorized dispatch through established Correspondence.
- One bounded, revocable no-account stage-one claimant-response path; wrong-person/no-response handling.
- Independent stage-two recipient relationship answer and governed relationship adjudication.
- Product Map/UI placement once backend semantics are ready.

Architecture source: `architecture/ATLAS_SOURCE_PERSON_RECOGNITION_TWO_STAGE_RELATIONSHIP_INQUIRY_V1.md`; selected owner Option C. This candidate makes no new canonical Person or Smart Contact store.
