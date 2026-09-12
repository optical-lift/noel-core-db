-- Behavioral postconditions for the database-owned outbound transport finalizer.
-- Runs only inside the disposable production-schema clone validator.

DO $$
DECLARE
  v_receipt jsonb;
  v_event_id uuid;
  v_count integer;
  v_state text;
BEGIN
  v_receipt:=atlas.finalize_communication_outbound_transport_service_v1(
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
  );

  IF v_receipt->>'state' <> 'accepted'
     OR coalesce((v_receipt->>'canonicalEventConstructed')::boolean,false) IS DISTINCT FROM true
     OR v_receipt->>'canonicalEventSource' <> 'atlas_database' THEN
    RAISE EXCEPTION 'Accepted finalization receipt is malformed: %',v_receipt;
  END IF;

  SELECT id INTO v_event_id
  FROM atlas.communication_events
  WHERE connected_source_id='00000000-0000-4000-8000-000000001204'::uuid
    AND source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001210';
  IF v_event_id IS NULL THEN
    RAISE EXCEPTION 'Accepted outbound finalization did not create Communication Event custody.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM atlas.communication_events e
    WHERE e.id=v_event_id
      AND e.direction='outgoing'
      AND e.speaker_is_self
      AND e.speaker_address='fixture-mailbox@example.invalid'
      AND e.body='Accepted body'
      AND e.body_state='exact_text'
      AND e.source_authority='evidence_only'
      AND e.permitted_state_effect='append_source_attributed_evidence_only'
      AND e.governing_state_changed=false
      AND e.canonical_event->>'schemaVersion'='atlas_communication_event_v1'
      AND e.canonical_event#>>'{source,kind}'='imap_smtp_email'
      AND e.canonical_event#>>'{source,accountRef}'='fixture-mailbox@example.invalid'
      AND e.canonical_event#>>'{source,threadRef}'='atlas-institutional-conversation:00000000-0000-4000-8000-000000001207'
      AND e.canonical_event#>>'{sourcePayload,messageId}'='<fixture-accepted@example.invalid>'
  ) THEN
    RAISE EXCEPTION 'Accepted outbound canonical event does not match the evidence contract.';
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM atlas.communication_event_participants
  WHERE communication_event_id=v_event_id;
  IF v_count<>4 THEN
    RAISE EXCEPTION 'Accepted outbound event expected 4 canonical participants; found %',v_count;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM atlas.communication_event_participants
    WHERE communication_event_id=v_event_id AND participant_role='sender' AND address='fixture-mailbox@example.invalid' AND is_self
  ) OR NOT EXISTS (
    SELECT 1 FROM atlas.communication_event_participants
    WHERE communication_event_id=v_event_id AND participant_role='to' AND address='to@example.invalid' AND NOT is_self
  ) OR NOT EXISTS (
    SELECT 1 FROM atlas.communication_event_participants
    WHERE communication_event_id=v_event_id AND participant_role='cc' AND address='cc@example.invalid' AND NOT is_self
  ) OR NOT EXISTS (
    SELECT 1 FROM atlas.communication_event_participants
    WHERE communication_event_id=v_event_id AND participant_role='bcc' AND address='bcc@example.invalid' AND NOT is_self
  ) THEN
    RAISE EXCEPTION 'Accepted outbound participant materialization is incomplete.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM atlas.institutional_conversation_messages
    WHERE institutional_conversation_id='00000000-0000-4000-8000-000000001207'::uuid
      AND communication_event_id=v_event_id
      AND communication_endpoint_id='00000000-0000-4000-8000-000000001205'::uuid
  ) THEN
    RAISE EXCEPTION 'Accepted outbound event was not admitted to its institutional conversation.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM atlas.communication_outbound_event_links
    WHERE outbound_operation_id='00000000-0000-4000-8000-000000001210'::uuid
      AND communication_event_id=v_event_id
  ) THEN
    RAISE EXCEPTION 'Accepted outbound operation/event link is missing.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM atlas.communication_outbound_attempts
    WHERE outbound_operation_id='00000000-0000-4000-8000-000000001210'::uuid
      AND attempt_number=1 AND result_state='accepted'
      AND provider_message_ref='<fixture-accepted@example.invalid>'
  ) THEN
    RAISE EXCEPTION 'Accepted outbound transport attempt evidence is missing.';
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM atlas.communication_outbound_attempt_recipients
  WHERE outbound_operation_id='00000000-0000-4000-8000-000000001210'::uuid
    AND result_state='accepted';
  IF v_count<>3 THEN
    RAISE EXCEPTION 'Accepted outbound expected 3 accepted recipient results; found %',v_count;
  END IF;

  SELECT operation_state INTO v_state
  FROM atlas.communication_outbound_operations
  WHERE id='00000000-0000-4000-8000-000000001210'::uuid;
  IF v_state<>'accepted' THEN
    RAISE EXCEPTION 'Accepted outbound operation state is %, expected accepted',v_state;
  END IF;

  -- A second finalization attempt after acceptance must not create another event/attempt.
  v_receipt:=atlas.finalize_communication_outbound_transport_service_v1(
    '00000000-0000-4000-8000-000000001210'::uuid,
    'fixture-worker',
    'accepted',
    '<fixture-accepted@example.invalid>',
    '{"phase":"data","smtpCode":250,"smtpMessage":"replayed response"}'::jsonb,
    '[{"role":"to","address":"to@example.invalid","state":"accepted"}]'::jsonb,
    '2026-09-12T16:00:00Z'::timestamptz
  );
  IF v_receipt->>'state'<>'already_accepted' THEN
    RAISE EXCEPTION 'Accepted replay should be idempotent; receipt=%',v_receipt;
  END IF;
  SELECT count(*)::integer INTO v_count FROM atlas.communication_events
  WHERE connected_source_id='00000000-0000-4000-8000-000000001204'::uuid
    AND source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001210';
  IF v_count<>1 THEN RAISE EXCEPTION 'Accepted replay duplicated Communication Event custody.'; END IF;
  SELECT count(*)::integer INTO v_count FROM atlas.communication_outbound_attempts
  WHERE outbound_operation_id='00000000-0000-4000-8000-000000001210'::uuid;
  IF v_count<>1 THEN RAISE EXCEPTION 'Accepted replay duplicated transport attempt evidence.'; END IF;

  v_receipt:=atlas.finalize_communication_outbound_transport_service_v1(
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
  );
  IF v_receipt->>'operationState'<>'partially_accepted' THEN
    RAISE EXCEPTION 'Partial finalization did not preserve partial state: %',v_receipt;
  END IF;
  SELECT operation_state INTO v_state FROM atlas.communication_outbound_operations WHERE id='00000000-0000-4000-8000-000000001211'::uuid;
  IF v_state<>'partially_accepted' THEN RAISE EXCEPTION 'Partial operation state is %',v_state; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM atlas.communication_outbound_attempts
    WHERE outbound_operation_id='00000000-0000-4000-8000-000000001211'::uuid AND result_state='partially_accepted'
  ) THEN RAISE EXCEPTION 'Partial attempt state was not preserved.'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM atlas.communication_outbound_attempt_recipients
    WHERE outbound_operation_id='00000000-0000-4000-8000-000000001211'::uuid AND recipient_address='partial-ok@example.invalid' AND result_state='accepted'
  ) OR NOT EXISTS (
    SELECT 1 FROM atlas.communication_outbound_attempt_recipients
    WHERE outbound_operation_id='00000000-0000-4000-8000-000000001211'::uuid AND recipient_address='partial-reject@example.invalid' AND result_state='rejected'
  ) THEN RAISE EXCEPTION 'Partial recipient result evidence is incomplete.'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM atlas.communication_events
    WHERE source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001211'
  ) THEN RAISE EXCEPTION 'Partial acceptance must still create outbound Communication Event custody.'; END IF;

  v_receipt:=atlas.finalize_communication_outbound_transport_service_v1(
    '00000000-0000-4000-8000-000000001212'::uuid,
    'fixture-worker',
    'temporary_failure',
    null,
    '{"phase":"rcpt","smtpCode":451}'::jsonb,
    '[{"role":"to","address":"deferred@example.invalid","state":"deferred","providerResponse":{"smtpCode":451}}]'::jsonb,
    '2026-09-12T16:02:00Z'::timestamptz
  );
  IF coalesce((v_receipt->>'canonicalEventConstructed')::boolean,true) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Known failure incorrectly constructed canonical event: %',v_receipt;
  END IF;
  IF EXISTS (
    SELECT 1 FROM atlas.communication_events
    WHERE source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001212'
  ) THEN RAISE EXCEPTION 'Known failure must not create Communication Event custody.'; END IF;
  SELECT operation_state INTO v_state FROM atlas.communication_outbound_operations WHERE id='00000000-0000-4000-8000-000000001212'::uuid;
  IF v_state<>'temporary_failure' THEN RAISE EXCEPTION 'Known failure operation state is %',v_state; END IF;

  v_receipt:=atlas.mark_expired_communication_outbound_leases_uncertain_service_v1('00000000-0000-4000-8000-000000001204'::uuid);
  SELECT operation_state INTO v_state FROM atlas.communication_outbound_operations WHERE id='00000000-0000-4000-8000-000000001213'::uuid;
  IF v_state<>'transport_uncertain' THEN
    RAISE EXCEPTION 'Expired unresolved lease state is %, expected transport_uncertain',v_state;
  END IF;
  IF EXISTS (
    SELECT 1 FROM atlas.communication_events
    WHERE source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001213'
  ) THEN RAISE EXCEPTION 'Transport-uncertain operation must not create Communication Event custody.'; END IF;
  IF EXISTS (
    SELECT 1 FROM atlas.communication_outbound_attempts
    WHERE outbound_operation_id='00000000-0000-4000-8000-000000001213'::uuid
  ) THEN RAISE EXCEPTION 'Transport-uncertain lease reconciliation must not invent an SMTP attempt.'; END IF;
END;
$$;
