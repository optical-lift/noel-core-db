-- Database-native pgTAP contract for the outbound transport finalizer.
-- Runs only inside the disposable production-structure clone and rolls back all mutations.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET LOCAL search_path = extensions, public, atlas, pg_catalog;

SELECT plan(21);

SELECT is(
  (atlas.finalize_communication_outbound_transport_service_v1(
    '00000000-0000-4000-8000-000000001210'::uuid,
    'fixture-worker',
    'accepted',
    '<fixture-accepted@example.invalid>',
    '{"phase":"data","smtpCode":250,"smtpMessage":"queued"}'::jsonb,
    '[
      {"role":"to","address":"to@example.invalid","state":"accepted","providerResponse":{"smtpCode":250}},
      {"role":"cc","address":"cc@example.invalid","state":"accepted","providerResponse":{"smtpCode":250}},
      {"role":"bcc","address":"bcc@example.invalid","state":"accepted","providerResponse":{"smtpCode":250}}
    ]'::jsonb,
    '2026-09-12T16:00:00Z'::timestamptz
  )->>'state')::text,
  'accepted'::text,
  'accepted transport finalizes as accepted'
);

SELECT is(
  (SELECT operation_state::text FROM atlas.communication_outbound_operations
   WHERE id='00000000-0000-4000-8000-000000001210'::uuid),
  'accepted'::text,
  'accepted transport updates operation state'
);

SELECT is(
  (SELECT count(*) FROM atlas.communication_events
   WHERE source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001210'),
  1::bigint,
  'accepted transport creates exactly one canonical Communication Event'
);

SELECT is(
  (SELECT count(*)
   FROM atlas.communication_event_participants p
   JOIN atlas.communication_events e ON e.id=p.communication_event_id
   WHERE e.source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001210'),
  4::bigint,
  'accepted event materializes sender, to, cc, and bcc participants'
);

SELECT is(
  (SELECT count(*) FROM atlas.communication_outbound_attempts
   WHERE outbound_operation_id='00000000-0000-4000-8000-000000001210'::uuid),
  1::bigint,
  'accepted transport records one transport attempt'
);

SELECT is(
  (SELECT count(*) FROM atlas.communication_outbound_attempt_recipients
   WHERE outbound_operation_id='00000000-0000-4000-8000-000000001210'::uuid),
  3::bigint,
  'accepted transport preserves three recipient results'
);

SELECT is(
  (SELECT canonical_event#>>'{source,kind}' FROM atlas.communication_events
   WHERE source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001210'),
  'imap_smtp_email'::text,
  'database constructs provider-neutral canonical source kind from connected source'
);

SELECT is(
  (SELECT canonical_event#>>'{sourcePayload,messageId}' FROM atlas.communication_events
   WHERE source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001210'),
  '<fixture-accepted@example.invalid>'::text,
  'canonical event preserves transport Message-ID as source evidence'
);

SELECT is(
  (atlas.finalize_communication_outbound_transport_service_v1(
    '00000000-0000-4000-8000-000000001210'::uuid,
    'fixture-worker',
    'accepted',
    '<fixture-accepted@example.invalid>',
    '{"phase":"data","smtpCode":250,"smtpMessage":"replayed response"}'::jsonb,
    '[{"role":"to","address":"to@example.invalid","state":"accepted"}]'::jsonb,
    '2026-09-12T16:00:00Z'::timestamptz
  )->>'state')::text,
  'already_accepted'::text,
  'accepted replay resolves to already_accepted'
);

SELECT is(
  (SELECT count(*) FROM atlas.communication_events
   WHERE source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001210'),
  1::bigint,
  'accepted replay does not duplicate canonical event'
);

SELECT is(
  (SELECT count(*) FROM atlas.communication_outbound_attempts
   WHERE outbound_operation_id='00000000-0000-4000-8000-000000001210'::uuid),
  1::bigint,
  'accepted replay does not duplicate transport attempt'
);

SELECT is(
  (atlas.finalize_communication_outbound_transport_service_v1(
    '00000000-0000-4000-8000-000000001211'::uuid,
    'fixture-worker',
    'partially_accepted',
    '<fixture-partial@example.invalid>',
    '{"phase":"data","smtpCode":250}'::jsonb,
    '[
      {"role":"to","address":"partial-ok@example.invalid","state":"accepted","providerResponse":{"smtpCode":250}},
      {"role":"to","address":"partial-reject@example.invalid","state":"rejected","providerResponse":{"smtpCode":550}}
    ]'::jsonb,
    '2026-09-12T16:01:00Z'::timestamptz
  )->>'operationState')::text,
  'partially_accepted'::text,
  'partial acceptance remains partially_accepted'
);

SELECT is(
  (SELECT count(*) FROM atlas.communication_events
   WHERE source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001211'),
  1::bigint,
  'partial acceptance still creates canonical Communication Event custody'
);

SELECT is(
  (SELECT count(*) FROM atlas.communication_outbound_attempt_recipients
   WHERE outbound_operation_id='00000000-0000-4000-8000-000000001211'::uuid
     AND result_state='accepted'),
  1::bigint,
  'partial acceptance preserves accepted recipient result'
);

SELECT is(
  (SELECT count(*) FROM atlas.communication_outbound_attempt_recipients
   WHERE outbound_operation_id='00000000-0000-4000-8000-000000001211'::uuid
     AND result_state='rejected'),
  1::bigint,
  'partial acceptance preserves rejected recipient result'
);

SELECT is(
  (atlas.finalize_communication_outbound_transport_service_v1(
    '00000000-0000-4000-8000-000000001212'::uuid,
    'fixture-worker',
    'temporary_failure',
    null,
    '{"phase":"rcpt","smtpCode":451}'::jsonb,
    '[{"role":"to","address":"deferred@example.invalid","state":"deferred","providerResponse":{"smtpCode":451}}]'::jsonb,
    '2026-09-12T16:02:00Z'::timestamptz
  )->>'canonicalEventConstructed')::text,
  'false'::text,
  'known temporary failure remains transport evidence only'
);

SELECT is(
  (SELECT count(*) FROM atlas.communication_events
   WHERE source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001212'),
  0::bigint,
  'known temporary failure creates no canonical Communication Event'
);

SELECT lives_ok(
  $$SELECT atlas.mark_expired_communication_outbound_leases_uncertain_service_v1(
      '00000000-0000-4000-8000-000000001204'::uuid
    )$$,
  'expired unresolved lease reconciliation completes'
);

SELECT is(
  (SELECT operation_state::text FROM atlas.communication_outbound_operations
   WHERE id='00000000-0000-4000-8000-000000001213'::uuid),
  'transport_uncertain'::text,
  'expired unresolved lease becomes transport_uncertain'
);

SELECT is(
  (SELECT count(*) FROM atlas.communication_events
   WHERE source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001213'),
  0::bigint,
  'transport_uncertain creates no canonical Communication Event'
);

SELECT is(
  (SELECT count(*) FROM atlas.communication_outbound_attempts
   WHERE outbound_operation_id='00000000-0000-4000-8000-000000001213'::uuid),
  0::bigint,
  'transport_uncertain reconciliation invents no SMTP attempt'
);

SELECT * FROM finish();
ROLLBACK;
