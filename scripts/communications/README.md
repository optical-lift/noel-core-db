# Institutional email transport runtimes

This directory contains provider-neutral external email transport runtimes for Atlas. SMTP and IMAP remain physical transport adapters beneath Atlas communication canon.

## Authority boundary

Neither runtime owns communication meaning.

- The outbound worker does **not** decide that a user may send mail. Atlas must first create an authenticated, authorized durable outbound operation.
- The inbound worker does **not** decide identity, durable conversation membership, relationship/CRM state, response responsibility, or Company Work.
- Neither worker creates parallel communication canon.
- Configuration and credentials come from the connected source's generic email transport configuration. No provider or organization is hard-coded into either runtime.

## Outbound

`scripts/communications/institutional_email_outbound.py` leases only already-authorized outbound operations and performs SMTP transport.

It must never call the user-facing prepare/send authority RPC. After a definitive SMTP result, it reports transport facts to `finalize_communication_outbound_transport_service_v1`. Atlas reconstructs the canonical outbound Communication Event from the authorized operation, endpoint/source custody, reply context, and governed attachments, then records the transport result atomically.

Existing contracts used include:

- `mark_expired_communication_outbound_leases_uncertain_service_v1`
- `lease_communication_outbound_operations_service_v1`
- `generic_email_transport_config_service_v1`
- `communication_outbound_transport_payload_service_v1`
- `communication_reply_transport_context_service_v1`
- `communication_outbound_attachment_transport_service_v1`
- `finalize_communication_outbound_transport_service_v1`

### SMTP uncertainty rule

The runtime drives SMTP explicitly through `MAIL`, `RCPT`, and `DATA` so the ambiguity boundary stays visible.

- A known failure before `DATA` is ordinary known transport failure evidence.
- An explicit server response to `DATA` is definitive transport evidence and may be recorded.
- If an exception, timeout, or socket loss occurs after `DATA` begins and acceptance is ambiguous, the runtime records **nothing** and leaves the lease unresolved.
- Database reconciliation moves such an unresolved lease to `transport_uncertain`.
- `transport_uncertain` is never automatically resent.

SMTP acceptance is transport evidence, not proof of recipient delivery or read.

### Outbound attachments

Attachment manifests are supplied by Atlas. The worker downloads governed private Storage objects and verifies both byte length and SHA-256 before entering SMTP DATA. A mismatch is a known pre-DATA transport error.

## Inbound

`scripts/communications/institutional_email_inbound.py` is a one-shot generic IMAP reader. It opens the configured mailbox read-only, retrieves messages by UID with `BODY.PEEK[]`, parses RFC/MIME evidence, and reports physical transport facts to `ingest_institutional_email_transport_service_v1`.

The worker supplies facts such as:

- mailbox, UIDVALIDITY, and UID;
- Message-ID, In-Reply-To, and References;
- From, To, Cc, and visible Bcc headers;
- subject and source timestamp;
- plain-text and HTML body evidence;
- attachment metadata and SHA-256;
- complete raw MIME SHA-256 and byte length.

Atlas, not the worker, constructs the canonical inbound Communication Event. The database then delegates deduplication, normalized participants, relationship reconciliation, institutional conversation admission, and response-case consequences to the existing communication kernel.

### Reply continuity

Inbound threading is deliberately fail-closed. The database may reuse an existing source thread only when `In-Reply-To` or `References` explicitly matches a Message-ID already in Communication Event custody for the same Connected Source. No subject-line guessing or correspondent-based thread invention occurs.

If multiple distinct existing threads match the supplied RFC references, the inbound message remains on a standalone source thread rather than guessing which conversation owns it.

### Hidden-recipient delivery

An IMAP mailbox may receive a Bcc copy even though its address does not appear in the visible message headers. Atlas records the mailbox itself as a self participant with `mailboxDeliveryObserved=true` and `headerRecipientRoleUnknown=true`. It does not invent whether the hidden address was To, Cc, or Bcc.

### IMAP cursor custody

The UID checkpoint is database-owned in `communication_source_sync_states` through:

- `institutional_email_capture_cursor_service_v1`
- `record_institutional_email_capture_cursor_service_v1`

The cursor is monotonic inside one UIDVALIDITY epoch. A new UIDVALIDITY epoch may restart UIDs. The worker advances the cursor only after Atlas accepts the message into its ingestion contract.

### Raw MIME custody

Inbound currently records the raw RFC/MIME SHA-256 and byte length through `record_communication_raw_message_custody_service_v1` with `hash_only` custody. Parsed evidence remains available in Communication Events; exact raw-byte replay would require a governed raw-message storage locator in a later storage layer.

## Environment

Required for both runtimes:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `ATLAS_CONNECTED_SOURCE_ID` (or `--connected-source-id`)

Outbound optional:

- `ATLAS_EMAIL_LEASE_OWNER`
- `ATLAS_EMAIL_LEASE_LIMIT`
- `ATLAS_EMAIL_LEASE_SECONDS`

Inbound optional:

- `ATLAS_EMAIL_MAILBOX` (default `INBOX`)
- `ATLAS_EMAIL_INBOUND_LIMIT` (default `100`)

Both runtimes are intentionally one-shot. Scheduling and hosting remain external and must not widen their authority. No recurring outbound schedule should be enabled before an explicitly authorized manual live send has been proven end to end.

## Recovery validation

Recovery-branch validation proves three separate layers against a disposable clone of production structure:

1. outbound finalization contracts;
2. inbound parsing, custody, replay, reply continuity, response-case, Bcc, and UID cursor contracts;
3. a synthetic closed loop in which the real outbound finalizer creates accepted canonical evidence and an inbound RFC reply rejoins the same durable source thread and institutional conversation without changing the existing responsible assignee.

These tests do not send SMTP, connect to IMAP, execute production DDL, or deploy application code.
