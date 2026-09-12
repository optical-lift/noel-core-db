\set ON_ERROR_STOP on
begin;

-- Cursor begins empty.
do $$
declare r jsonb;
begin
  r:=atlas.institutional_email_capture_cursor_service_v1(
    '00000000-0000-4000-8000-000000002204'::uuid,'INBOX'
  );
  if coalesce((r->>'lastUid')::bigint,-1)<>0 then raise exception 'expected empty UID cursor: %',r; end if;
end$$;

-- Seed one already-canonical outgoing event. The inbound adapter must use its Message-ID
-- only as explicit reply evidence and must not invent a second durable conversation.
select atlas.ingest_organization_communication_events_service_v3(
  '00000000-0000-4000-8000-000000002204'::uuid,
  jsonb_build_array(jsonb_build_object(
    'schemaVersion','atlas_communication_event_v1',
    'sourceAuthority','evidence_only',
    'permittedStateEffect','append_source_attributed_evidence_only',
    'governingStateChanged',false,
    'captureMode','validation_fixture',
    'source',jsonb_build_object(
      'kind','imap_smtp_email',
      'accountRef','fixture-inbound@example.invalid',
      'eventRef','fixture-outbound-prior',
      'threadRef','atlas-institutional-conversation:fixture-thread-1'
    ),
    'direction','outgoing',
    'speaker',jsonb_build_object('isSelf',true,'address','fixture-inbound@example.invalid'),
    'occurredAt','2026-09-12T16:00:00Z',
    'capturedAt','2026-09-12T16:00:01Z',
    'subject','Fixture thread',
    'body','Initial outbound',
    'bodyState','exact_text',
    'participants',jsonb_build_array(
      jsonb_build_object('role','sender','addressKind','email','address','fixture-inbound@example.invalid','isSelf',true),
      jsonb_build_object('role','to','addressKind','email','address','alice@example.invalid','isSelf',false)
    ),
    'attachments','[]'::jsonb,
    'sourcePayload',jsonb_build_object('messageId','<atlas-outbound-1@example.invalid>','subject','Fixture thread'),
    'contentHash',repeat('b',64)
  )),
  '{"source":"validation_fixture"}'::jsonb
);

create temp table _prior_conversation as
select m.institutional_conversation_id
from atlas.institutional_conversation_messages m
join atlas.communication_events e on e.id=m.communication_event_id
where e.connected_source_id='00000000-0000-4000-8000-000000002204'::uuid
  and e.source_event_ref='fixture-outbound-prior';

do $$
begin
  if (select count(*) from _prior_conversation)<>1 then raise exception 'prior outbound was not admitted to exactly one conversation'; end if;
end$$;

-- Inbound RFC reply: exact In-Reply-To continuity must reuse the existing source thread.
create temp table _reply_receipt as
select atlas.ingest_institutional_email_transport_service_v1(
  '00000000-0000-4000-8000-000000002204'::uuid,
  'INBOX',77,101,
  '<reply-101@example.invalid>',
  '<atlas-outbound-1@example.invalid>',
  '["<atlas-outbound-1@example.invalid>"]'::jsonb,
  '{"address":"alice@example.invalid","name":"Alice Fixture"}'::jsonb,
  '[{"address":"fixture-inbound@example.invalid","name":"Inbound Fixture"}]'::jsonb,
  '[]'::jsonb,'[]'::jsonb,
  'Re: Fixture thread','2026-09-12T16:05:00Z'::timestamptz,
  'Reply body',null,'[]'::jsonb,
  repeat('a',64),123,'2026-09-12T16:05:01Z'::timestamptz
) as value;

do $$
declare r jsonb; prior_id uuid; reply_id uuid;
begin
  select value into r from _reply_receipt;
  select institutional_conversation_id into prior_id from _prior_conversation;
  reply_id:=nullif(r->>'institutionalConversationId','')::uuid;
  if r->>'threadResolutionState'<>'explicit_rfc_reply_reference' then raise exception 'reply continuity was not explicit: %',r; end if;
  if reply_id is distinct from prior_id then raise exception 'reply created wrong conversation: prior %, reply %',prior_id,reply_id; end if;
  if r->>'canonicalEventSource'<>'atlas_database' then raise exception 'canonical event was not database-owned: %',r; end if;
end$$;

-- Durable evidence and response-state consequences come from the existing kernel.
do $$
begin
  if (select count(*) from atlas.communication_events where connected_source_id='00000000-0000-4000-8000-000000002204'::uuid and source_event_ref='imap:inbox:77:101')<>1 then
    raise exception 'expected exactly one inbound Communication Event';
  end if;
  if (select count(*) from atlas.communication_raw_message_custody c join atlas.communication_events e on e.id=c.communication_event_id where e.source_event_ref='imap:inbox:77:101' and c.raw_mime_sha256=repeat('a',64) and c.custody_state='hash_only')<>1 then
    raise exception 'raw MIME hash custody missing';
  end if;
  if (select count(*) from atlas.communication_event_participants p join atlas.communication_events e on e.id=p.communication_event_id where e.source_event_ref='imap:inbox:77:101')<>2 then
    raise exception 'expected sender plus self recipient participants';
  end if;
  if not exists(
    select 1
    from atlas.institutional_conversation_response_cases rc
    join _prior_conversation pc on pc.institutional_conversation_id=rc.institutional_conversation_id
    where rc.case_state in ('unclaimed','needs_response')
  ) then raise exception 'inbound reply did not create/touch a response case'; end if;
end$$;

-- Identical replay stays idempotent.
select atlas.ingest_institutional_email_transport_service_v1(
  '00000000-0000-4000-8000-000000002204'::uuid,
  'INBOX',77,101,
  '<reply-101@example.invalid>',
  '<atlas-outbound-1@example.invalid>',
  '["<atlas-outbound-1@example.invalid>"]'::jsonb,
  '{"address":"alice@example.invalid","name":"Alice Fixture"}'::jsonb,
  '[{"address":"fixture-inbound@example.invalid","name":"Inbound Fixture"}]'::jsonb,
  '[]'::jsonb,'[]'::jsonb,
  'Re: Fixture thread','2026-09-12T16:05:00Z'::timestamptz,
  'Reply body',null,'[]'::jsonb,
  repeat('a',64),123,'2026-09-12T16:05:01Z'::timestamptz
);

do $$
begin
  if (select count(*) from atlas.communication_events where connected_source_id='00000000-0000-4000-8000-000000002204'::uuid and source_event_ref='imap:inbox:77:101')<>1 then raise exception 'replay duplicated inbound event'; end if;
  if (select count(*) from atlas.communication_raw_message_custody c join atlas.communication_events e on e.id=c.communication_event_id where e.source_event_ref='imap:inbox:77:101')<>1 then raise exception 'replay duplicated raw custody'; end if;
end$$;

-- Bcc-style delivery: the visible headers do not name the mailbox. Atlas records mailbox
-- delivery as self evidence without inventing whether the hidden recipient was To/Cc/Bcc.
select atlas.ingest_institutional_email_transport_service_v1(
  '00000000-0000-4000-8000-000000002204'::uuid,
  'INBOX',77,102,
  '<bcc-102@example.invalid>',null,'[]'::jsonb,
  '{"address":"sender@example.invalid"}'::jsonb,
  '[{"address":"public@example.invalid"}]'::jsonb,
  '[]'::jsonb,'[]'::jsonb,
  'Hidden mailbox delivery','2026-09-12T16:06:00Z'::timestamptz,
  'Bcc body',null,'[]'::jsonb,
  repeat('c',64),88,'2026-09-12T16:06:01Z'::timestamptz
);

do $$
begin
  if not exists(
    select 1 from atlas.communication_event_participants p
    join atlas.communication_events e on e.id=p.communication_event_id
    where e.source_event_ref='imap:inbox:77:102'
      and p.is_self
      and p.participant_role='participant'
      and p.metadata @> '{"mailboxDeliveryObserved":true,"headerRecipientRoleUnknown":true}'::jsonb
  ) then raise exception 'Bcc-style delivery did not preserve unknown header-recipient role'; end if;
end$$;

-- Cursor is database-owned and monotonic within the UIDVALIDITY epoch.
select atlas.record_institutional_email_capture_cursor_service_v1(
  '00000000-0000-4000-8000-000000002204'::uuid,'INBOX',77,101
);
select atlas.record_institutional_email_capture_cursor_service_v1(
  '00000000-0000-4000-8000-000000002204'::uuid,'INBOX',77,102
);

do $$
declare r jsonb;
begin
  r:=atlas.institutional_email_capture_cursor_service_v1('00000000-0000-4000-8000-000000002204'::uuid,'INBOX');
  if (r->>'uidValidity')::bigint<>77 or (r->>'lastUid')::bigint<>102 then raise exception 'unexpected cursor state: %',r; end if;
end$$;

-- A new UIDVALIDITY epoch may restart UIDs.
select atlas.record_institutional_email_capture_cursor_service_v1(
  '00000000-0000-4000-8000-000000002204'::uuid,'INBOX',78,1
);

do $$
declare r jsonb;
begin
  r:=atlas.institutional_email_capture_cursor_service_v1('00000000-0000-4000-8000-000000002204'::uuid,'INBOX');
  if (r->>'uidValidity')::bigint<>78 or (r->>'lastUid')::bigint<>1 then raise exception 'UIDVALIDITY reset failed: %',r; end if;
end$$;

rollback;
