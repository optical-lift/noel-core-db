\set ON_ERROR_STOP on
begin;

-- 1. Atlas finalizes an already-authorized outbound operation from transport facts.
create temp table _outbound_receipt as
select atlas.finalize_communication_outbound_transport_service_v1(
  '00000000-0000-4000-8000-000000001210'::uuid,
  'fixture-worker',
  'accepted',
  '<closed-loop-outbound@example.invalid>',
  '{"phase":"data","smtpCode":250,"smtpMessage":"queued"}'::jsonb,
  '[
    {"role":"to","address":"to@example.invalid","state":"accepted","providerResponse":{"smtpCode":250}},
    {"role":"cc","address":"cc@example.invalid","state":"accepted","providerResponse":{"smtpCode":250}},
    {"role":"bcc","address":"bcc@example.invalid","state":"accepted","providerResponse":{"smtpCode":250}}
  ]'::jsonb,
  '2026-09-12T16:30:00Z'::timestamptz
) as value;

do $$
declare r jsonb;
begin
  select value into r from _outbound_receipt;
  if r->>'state'<>'accepted' or r->>'canonicalEventSource'<>'atlas_database' then
    raise exception 'outbound finalizer did not produce database-owned accepted evidence: %',r;
  end if;
end$$;

-- The outbound consequence owns a waiting_external response case and remains assigned to
-- the initiating member through ordinary Company Work responsibility.
do $$
begin
  if not exists(
    select 1
    from atlas.institutional_conversation_response_cases rc
    where rc.institutional_conversation_id='00000000-0000-4000-8000-000000001207'::uuid
      and rc.case_state='waiting_external'
  ) then raise exception 'accepted outbound did not enter waiting_external'; end if;
end$$;

-- 2. External correspondent replies through physical IMAP evidence.
create temp table _inbound_receipt as
select atlas.ingest_institutional_email_transport_service_v1(
  '00000000-0000-4000-8000-000000001204'::uuid,
  'INBOX',88,201,
  '<closed-loop-reply@example.invalid>',
  '<closed-loop-outbound@example.invalid>',
  '["<closed-loop-outbound@example.invalid>"]'::jsonb,
  '{"address":"to@example.invalid","name":"To Fixture"}'::jsonb,
  '[{"address":"fixture-mailbox@example.invalid","name":"Fixture Mailbox"}]'::jsonb,
  '[]'::jsonb,'[]'::jsonb,
  'Re: Accepted fixture','2026-09-12T16:35:00Z'::timestamptz,
  'Closed-loop reply',null,'[]'::jsonb,
  repeat('e',64),222,'2026-09-12T16:35:01Z'::timestamptz
) as value;

do $$
declare r jsonb;
begin
  select value into r from _inbound_receipt;
  if r->>'threadResolutionState'<>'explicit_rfc_reply_reference' then
    raise exception 'inbound reply did not resolve from explicit RFC evidence: %',r;
  end if;
  if nullif(r->>'institutionalConversationId','')::uuid is distinct from '00000000-0000-4000-8000-000000001207'::uuid then
    raise exception 'inbound reply did not rejoin original institutional conversation: %',r;
  end if;
end$$;

-- 3. Both physical transport directions converge on the same durable source thread and
-- same institutional conversation. No second conversation is invented.
do $$
declare outbound_thread uuid; inbound_thread uuid;
begin
  select thread_id into outbound_thread
  from atlas.communication_events
  where connected_source_id='00000000-0000-4000-8000-000000001204'::uuid
    and source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001210';
  select thread_id into inbound_thread
  from atlas.communication_events
  where connected_source_id='00000000-0000-4000-8000-000000001204'::uuid
    and source_event_ref='imap:inbox:88:201';
  if outbound_thread is null or inbound_thread is null or inbound_thread is distinct from outbound_thread then
    raise exception 'closed loop did not converge on one source thread: outbound %, inbound %',outbound_thread,inbound_thread;
  end if;
  if (select count(*) from atlas.institutional_conversations where organization_id='00000000-0000-4000-8000-000000001202'::uuid)<>1 then
    raise exception 'closed loop invented an extra institutional conversation';
  end if;
  if (select count(*) from atlas.institutional_conversation_messages where institutional_conversation_id='00000000-0000-4000-8000-000000001207'::uuid)<>2 then
    raise exception 'expected exactly outbound plus inbound message in original conversation';
  end if;
end$$;

-- 4. The external reply moves the existing response consequence back to needs_response;
-- it does not invent a second responsibility system or silently change assignee.
do $$
declare work_id uuid; assignee uuid;
begin
  if not exists(
    select 1 from atlas.institutional_conversation_response_cases rc
    where rc.institutional_conversation_id='00000000-0000-4000-8000-000000001207'::uuid
      and rc.case_state='needs_response'
  ) then raise exception 'external reply did not return response case to needs_response'; end if;

  select wb.work_item_id into work_id
  from atlas.institutional_conversation_response_cases rc
  join atlas.institutional_conversation_response_work_bindings wb on wb.response_case_id=rc.id
  where rc.institutional_conversation_id='00000000-0000-4000-8000-000000001207'::uuid
    and rc.case_state='needs_response';
  if work_id is null then raise exception 'response case lost Company Work binding'; end if;

  select assignee_membership_id into assignee
  from atlas.work_allocations
  where work_item_id=work_id and allocation_role='responsible' and state='active'
  order by allocated_at desc,id desc limit 1;
  if assignee is distinct from '00000000-0000-4000-8000-000000001203'::uuid then
    raise exception 'inbound reply silently changed responsibility: %',assignee;
  end if;
end$$;

-- 5. Inbound raw RFC evidence remains separately hash-custodied.
do $$
begin
  if not exists(
    select 1
    from atlas.communication_raw_message_custody c
    join atlas.communication_events e on e.id=c.communication_event_id
    where e.source_event_ref='imap:inbox:88:201'
      and c.raw_mime_sha256=repeat('e',64)
      and c.byte_length=222
      and c.custody_state='hash_only'
  ) then raise exception 'closed-loop inbound raw MIME custody missing'; end if;
end$$;

rollback;
