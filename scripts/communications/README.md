# Institutional email outbound runtime

This directory contains the provider-neutral external email transport runtime for Atlas.

## Authority boundary

The runtime does **not** decide that a user may send mail. The Atlas application prepares an authorized durable outbound operation through the existing institutional communication contracts. This worker only leases those already-authorized operations and performs transport.

It must never call the user-facing prepare/send authority RPC and it does not create parallel communication canon, threading, participants, attachment authority, or retry semantics. The worker also never constructs an Atlas canonical Communication Event.

After a definitive SMTP result, the worker reports transport facts to `finalize_communication_outbound_transport_service_v1`. That database function reconstructs the canonical outbound Communication Event from the already-authorized operation, endpoint/source custody, reply context, and governed attachment records, then delegates to the existing outbound result contract atomically.

## Existing database contracts used

- `mark_expired_communication_outbound_leases_uncertain_service_v1`
- `lease_communication_outbound_operations_service_v1`
- `generic_email_transport_config_service_v1`
- `communication_outbound_transport_payload_service_v1`
- `communication_reply_transport_context_service_v1`
- `communication_outbound_attachment_transport_service_v1`
- `finalize_communication_outbound_transport_service_v1`

Configuration and credentials come from the connected source's generic email transport configuration. No provider or organization is hard-coded into the runtime.

## SMTP uncertainty rule

The runtime drives SMTP explicitly through `MAIL`, `RCPT`, and `DATA` so the ambiguity boundary is visible.

- A known failure before `DATA` is recorded as a normal known failure.
- An explicit server response to `DATA` is definitive and may be recorded.
- If an exception/timeout/socket loss occurs after `DATA` begins and acceptance is ambiguous, the runtime records **nothing**. It leaves the lease unresolved so the database reconciliation contract can move the operation to `transport_uncertain`.
- `transport_uncertain` is not automatically resent.

This rule prevents duplicate mail caused by retrying a message that the remote server may already have accepted.

## Attachments

Attachment manifests are supplied by Atlas. The worker downloads private Storage objects with its service-role credential and verifies both `byteLength` and SHA-256 before entering SMTP DATA. A mismatch is a known pre-DATA transport error.

## Environment

Required:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `ATLAS_CONNECTED_SOURCE_ID` (or `--connected-source-id`)

Optional:

- `ATLAS_EMAIL_LEASE_OWNER`
- `ATLAS_EMAIL_LEASE_LIMIT`
- `ATLAS_EMAIL_LEASE_SECONDS`

The runtime is intentionally one-shot: lease, process, exit. Scheduling/hosting is external and must not change its authority model.
