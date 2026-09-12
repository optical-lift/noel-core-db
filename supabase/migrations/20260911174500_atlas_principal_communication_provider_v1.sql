begin;

-- Generic Principal-owned provider registration. This is deliberately not a
-- Gmail-specific account table and not a communication-relay pairing seam.
create or replace function atlas.register_principal_connected_source_self_api_v1(
  p_provider_key text,
  p_provider_account_key text,
  p_display_label text default null,
  p_account_hint text default null,
  p_granted_scopes text[] default '{}'::text[],
  p_capabilities jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_principal_id uuid;
  v_source atlas.connected_sources%rowtype;
  v_provider text:=lower(nullif(btrim(p_provider_key),''));
  v_account text:=nullif(btrim(p_provider_account_key),'');
begin
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if v_provider is null or v_account is null then raise exception 'Provider and provider account key are required.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_capabilities,'{}'::jsonb))<>'object' or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Capabilities and metadata must be JSON objects.' using errcode='22023';
  end if;
  select id into v_principal_id from atlas.principals where user_id=v_user_id and status='active' order by created_at,id limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  insert into atlas.connected_sources(
    custodian_user_id,custodian_organization_id,custodian_organization_unit_id,
    provider_key,provider_account_key,display_label,account_hint,authorization_state,
    granted_scopes,capabilities,metadata,revoked_at
  ) values(
    v_user_id,null,null,v_provider,v_account,
    coalesce(nullif(btrim(p_display_label),''),v_provider),nullif(btrim(p_account_hint),''),'connected',
    coalesce(p_granted_scopes,'{}'::text[]),coalesce(p_capabilities,'{}'::jsonb),coalesce(p_metadata,'{}'::jsonb),null
  )
  on conflict (custodian_user_id,provider_key,provider_account_key) where custodian_user_id is not null
  do update set
    display_label=coalesce(excluded.display_label,atlas.connected_sources.display_label),
    account_hint=coalesce(excluded.account_hint,atlas.connected_sources.account_hint),
    authorization_state='connected',
    granted_scopes=excluded.granted_scopes,
    capabilities=atlas.connected_sources.capabilities||excluded.capabilities,
    metadata=atlas.connected_sources.metadata||excluded.metadata,
    revoked_at=null,
    updated_at=now()
  returning * into v_source;

  return jsonb_build_object(
    'contractVersion','principal_connected_source_v1',
    'connectedSourceId',v_source.id,
    'principalId',v_principal_id,
    'providerKey',v_source.provider_key,
    'providerAccountKey',v_source.provider_account_key,
    'authorizationState',v_source.authorization_state,
    'governingStateChanged',false
  );
end;
$function$;
revoke all on function atlas.register_principal_connected_source_self_api_v1(text,text,text,text,text[],jsonb,jsonb) from public,anon;
grant execute on function atlas.register_principal_connected_source_self_api_v1(text,text,text,text,text[],jsonb,jsonb) to authenticated;

-- Provider-independent event membership in a durable conversation.
create table atlas.communication_conversation_events (
  id uuid primary key default gen_random_uuid(),
  communication_conversation_id uuid not null references atlas.communication_conversations(id) on delete cascade,
  communication_event_id uuid not null unique references atlas.communication_events(id) on delete restrict,
  communication_endpoint_id uuid references atlas.communication_endpoints(id) on delete restrict,
  continuity_basis text not null check (btrim(continuity_basis)<>''),
  occurred_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now()
);
create index communication_conversation_events_conversation_idx
  on atlas.communication_conversation_events(communication_conversation_id,occurred_at,id);
comment on table atlas.communication_conversation_events is
'Provider-independent event membership for a durable Atlas Communication Conversation. Source-local thread identity remains separate evidence.';

create or replace function atlas.guard_communication_conversation_event_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_conversation atlas.communication_conversations%rowtype; v_event atlas.communication_events%rowtype; v_endpoint atlas.communication_endpoints%rowtype;
begin
  select * into v_conversation from atlas.communication_conversations where id=new.communication_conversation_id;
  select * into v_event from atlas.communication_events where id=new.communication_event_id;
  if v_conversation.id is null or v_event.id is null then raise exception 'Conversation and event are required.' using errcode='23514'; end if;
  if v_conversation.principal_id is not null then
    if v_event.principal_id is distinct from v_conversation.principal_id or v_event.organization_id is not null then raise exception 'Conversation event must share Principal custody.' using errcode='23514'; end if;
  else
    if v_event.organization_id is distinct from v_conversation.organization_id or v_event.organization_unit_id is distinct from v_conversation.organization_unit_id or v_event.principal_id is not null then raise exception 'Conversation event must share Organization/unit custody.' using errcode='23514'; end if;
  end if;
  if new.communication_endpoint_id is not null then
    select * into v_endpoint from atlas.communication_endpoints where id=new.communication_endpoint_id;
    if v_endpoint.id is null then raise exception 'Conversation event endpoint is unavailable.' using errcode='23514'; end if;
    if v_conversation.principal_id is not null and v_endpoint.principal_id is distinct from v_conversation.principal_id then raise exception 'Conversation event endpoint is outside Principal custody.' using errcode='23514'; end if;
    if v_conversation.organization_id is not null and (v_endpoint.organization_id is distinct from v_conversation.organization_id or v_endpoint.organization_unit_id is distinct from v_conversation.organization_unit_id) then raise exception 'Conversation event endpoint is outside Organization custody.' using errcode='23514'; end if;
  end if;
  return new;
end;$function$;
create trigger communication_conversation_event_guard_v1 before insert or update on atlas.communication_conversation_events for each row execute function atlas.guard_communication_conversation_event_v1();

-- Admit a Principal-owned event into one durable conversation without treating
-- provider thread IDs as the durable conversation itself.
create or replace function atlas.ensure_principal_communication_conversation_for_event_service_v1(p_communication_event_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_event atlas.communication_events%rowtype;
  v_endpoint_id uuid;
  v_candidate_count int;
  v_conversation_id uuid;
  v_stable_key text;
  v_subject text;
  v_created boolean:=false;
begin
  select * into v_event from atlas.communication_events where id=p_communication_event_id;
  if v_event.id is null then raise exception 'Communication event not found.' using errcode='P0002'; end if;
  if v_event.principal_id is null or v_event.organization_id is not null then
    return jsonb_build_object('contractVersion','principal_communication_conversation_admission_v1','state','not_principal','communicationEventId',v_event.id);
  end if;

  select count(*),(array_agg(ep.id order by ep.id))[1]
  into v_candidate_count,v_endpoint_id
  from atlas.communication_endpoint_source_bindings b
  join atlas.communication_endpoints ep on ep.id=b.communication_endpoint_id
  where b.connected_source_id=v_event.connected_source_id and b.binding_state='active' and ep.endpoint_state='active'
    and ep.principal_id=v_event.principal_id
    and (b.binding_role='send_receive' or (v_event.direction='incoming' and b.binding_role='receive') or (v_event.direction='outgoing' and b.binding_role='send') or v_event.direction='unknown')
    and exists(
      select 1 from atlas.communication_event_participants p
      where p.communication_event_id=v_event.id and p.is_self
        and p.address_normalized=ep.address_normalized
        and ((ep.endpoint_kind='email' and p.address_kind='email') or (ep.endpoint_kind in ('phone','sms','voice') and p.address_kind='phone') or ep.endpoint_kind not in ('email','phone','sms','voice'))
    );

  if v_candidate_count=0 then
    select count(*),(array_agg(ep.id order by ep.id))[1]
    into v_candidate_count,v_endpoint_id
    from atlas.communication_endpoint_source_bindings b
    join atlas.communication_endpoints ep on ep.id=b.communication_endpoint_id
    where b.connected_source_id=v_event.connected_source_id and b.binding_state='active' and ep.endpoint_state='active' and ep.principal_id=v_event.principal_id
      and (b.binding_role='send_receive' or (v_event.direction='incoming' and b.binding_role='receive') or (v_event.direction='outgoing' and b.binding_role='send') or v_event.direction='unknown');
  end if;

  if v_candidate_count<>1 then
    return jsonb_build_object('contractVersion','principal_communication_conversation_admission_v1','state',case when v_candidate_count=0 then 'no_endpoint' else 'ambiguous_endpoint' end,'communicationEventId',v_event.id,'candidateCount',v_candidate_count);
  end if;

  if v_event.thread_id is not null then
    select communication_conversation_id into v_conversation_id from atlas.communication_conversation_source_threads where communication_thread_id=v_event.thread_id;
  end if;

  if v_conversation_id is null then
    v_stable_key:=case when v_event.thread_id is not null then 'source-thread:'||v_event.connected_source_id::text||':'||v_event.thread_id::text else 'source-event:'||v_event.id::text end;
    v_subject:=coalesce(nullif(btrim(v_event.canonical_event->>'subject'),''),nullif(btrim(v_event.canonical_event#>>'{sourcePayload,subject}'),''),'Conversation');
    insert into atlas.communication_conversations(principal_id,organization_id,organization_unit_id,stable_key,subject,opened_at,last_activity_at,metadata)
    values(v_event.principal_id,null,null,v_stable_key,v_subject,coalesce(v_event.occurred_at,v_event.captured_at),coalesce(v_event.occurred_at,v_event.captured_at),jsonb_build_object('createdFromCommunicationEventId',v_event.id))
    on conflict (principal_id,stable_key) where principal_id is not null
    do update set last_activity_at=greatest(atlas.communication_conversations.last_activity_at,excluded.last_activity_at),updated_at=now()
    returning id into v_conversation_id;
    v_created:=true;

    insert into atlas.communication_conversation_endpoints(communication_conversation_id,communication_endpoint_id,endpoint_role)
    values(v_conversation_id,v_endpoint_id,'primary') on conflict do nothing;
    if v_event.thread_id is not null then
      insert into atlas.communication_conversation_source_threads(communication_conversation_id,communication_thread_id,connected_source_id,continuity_basis,metadata)
      values(v_conversation_id,v_event.thread_id,v_event.connected_source_id,'source_thread',jsonb_build_object('firstCommunicationEventId',v_event.id))
      on conflict (communication_thread_id) do nothing;
    end if;
  else
    update atlas.communication_conversations set last_activity_at=greatest(last_activity_at,coalesce(v_event.occurred_at,v_event.captured_at)),updated_at=now() where id=v_conversation_id;
    insert into atlas.communication_conversation_endpoints(communication_conversation_id,communication_endpoint_id,endpoint_role)
    values(v_conversation_id,v_endpoint_id,'participant') on conflict do nothing;
  end if;

  insert into atlas.communication_conversation_events(communication_conversation_id,communication_event_id,communication_endpoint_id,continuity_basis,occurred_at,metadata)
  values(v_conversation_id,v_event.id,v_endpoint_id,case when v_event.thread_id is null then 'source_event' else 'source_thread' end,v_event.occurred_at,jsonb_build_object('connectedSourceId',v_event.connected_source_id,'sourceEventRef',v_event.source_event_ref))
  on conflict (communication_event_id) do nothing;

  return jsonb_build_object('contractVersion','principal_communication_conversation_admission_v1','state','admitted','communicationEventId',v_event.id,'communicationConversationId',v_conversation_id,'communicationEndpointId',v_endpoint_id,'conversationCreated',v_created);
end;$function$;
revoke all on function atlas.ensure_principal_communication_conversation_for_event_service_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.ensure_principal_communication_conversation_for_event_service_v1(uuid) to service_role;

-- Generic provider sync for person-owned Connected Sources. OAuth/API adapters
-- invoke this service seam; relay credentials are intentionally not involved.
create or replace function atlas.ingest_principal_communication_events_service_v1(
  p_connected_source_id uuid,
  p_events jsonb,
  p_manifest jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,extensions
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_principal_id uuid;
  v_supplied int;
  v_admitted int:=0;
  v_already int:=0;
  v_conflicts int:=0;
  v_conversations int:=0;
  v_batch_id uuid;
  v_event jsonb;
  v_event_ref text;
  v_thread_ref text;
  v_thread_id uuid;
  v_event_id uuid;
  v_existing atlas.communication_events%rowtype;
  v_occurred_at timestamptz;
  v_captured_at timestamptz;
  v_source_hash text;
  v_custody_hash text;
  v_participants jsonb;
  v_participant_result jsonb;
  v_admission jsonb;
  v_first timestamptz;
  v_last timestamptz;
begin
  select * into v_source from atlas.connected_sources where id=p_connected_source_id and custodian_user_id is not null and custodian_organization_id is null and authorization_state='connected';
  if v_source.id is null then raise exception 'A connected Principal-owned source is required.' using errcode='42501'; end if;
  if not (v_source.capabilities @> '{"communicationCapture":true}'::jsonb) then raise exception 'Connected source is not authorized for communication capture.' using errcode='42501'; end if;
  select p.id into v_principal_id from atlas.principals p where p.user_id=v_source.custodian_user_id and p.status='active' order by p.created_at,p.id limit 1;
  if v_principal_id is null then raise exception 'Connected source has no active Principal custody root.' using errcode='42501'; end if;
  if jsonb_typeof(p_events)<>'array' then raise exception 'p_events must be a JSON array.' using errcode='22023'; end if;
  v_supplied:=jsonb_array_length(p_events);
  if v_supplied<1 or v_supplied>1000 then raise exception 'Communication batches must contain between 1 and 1000 events.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_manifest,'{}'::jsonb))<>'object' then raise exception 'Manifest must be a JSON object.' using errcode='22023'; end if;
  if exists(select 1 from jsonb_array_elements(p_events) e where e#>>'{source,kind}' is distinct from v_source.provider_key or e#>>'{source,accountRef}' is distinct from v_source.provider_account_key) then raise exception 'Communication batch source identity does not match the Connected Source.' using errcode='42501'; end if;

  insert into atlas.communication_ingest_batches(principal_id,organization_id,organization_unit_id,connected_source_id,relay_credential_id,capture_mode,supplied_count,metadata)
  values(v_principal_id,null,null,v_source.id,null,coalesce(nullif(btrim(p_events#>>'{0,captureMode}'),''),'provider_sync'),v_supplied,coalesce(p_manifest,'{}'::jsonb)||jsonb_build_object('ingestContract','principal_provider_communication_v1'))
  returning id into v_batch_id;

  for v_event in select value from jsonb_array_elements(p_events) loop
    if v_event->>'schemaVersion' is distinct from 'atlas_communication_event_v1' or v_event->>'sourceAuthority' is distinct from 'evidence_only' or v_event->>'permittedStateEffect' is distinct from 'append_source_attributed_evidence_only' or coalesce((v_event->>'governingStateChanged')::boolean,true)<>false then raise exception 'Communication event violates evidence-only contract.' using errcode='22023'; end if;
    if v_event->>'direction' not in ('incoming','outgoing','unknown') or v_event->>'bodyState' not in ('exact_text','attributed_body_preserved','empty') then raise exception 'Communication event contains unsupported state.' using errcode='22023'; end if;
    v_event_ref:=nullif(btrim(v_event#>>'{source,eventRef}'),''); if v_event_ref is null then raise exception 'source.eventRef is required.' using errcode='22023'; end if;
    v_source_hash:=lower(coalesce(v_event->>'contentHash','')); if v_source_hash !~ '^[0-9a-f]{64}$' then raise exception 'contentHash must be lowercase SHA-256.' using errcode='22023'; end if;
    v_occurred_at:=case when v_event->>'occurredAt' is null then null else (v_event->>'occurredAt')::timestamptz end;
    v_captured_at:=coalesce((v_event->>'capturedAt')::timestamptz,now());
    v_thread_ref:=nullif(btrim(v_event#>>'{source,threadRef}'),'');
    v_participants:=coalesce(v_event->'participants','[]'::jsonb);
    if jsonb_typeof(v_participants)<>'array' or jsonb_array_length(v_participants)=0 then raise exception 'Provider communication requires canonical participants.' using errcode='22023'; end if;
    v_custody_hash:=encode(extensions.digest(convert_to(jsonb_build_object('source',v_event->'source','direction',v_event->'direction','speaker',v_event->'speaker','occurredAt',v_event->'occurredAt','body',v_event->'body','bodyState',v_event->'bodyState','participants',v_participants,'sourcePayload',v_event->'sourcePayload')::text,'UTF8'),'sha256'),'hex');

    v_thread_id:=null;
    if v_thread_ref is not null then
      insert into atlas.communication_threads(principal_id,organization_id,organization_unit_id,connected_source_id,source_thread_ref,first_event_at,last_event_at)
      values(v_principal_id,null,null,v_source.id,v_thread_ref,v_occurred_at,v_occurred_at)
      on conflict (connected_source_id,source_thread_ref) do update set first_event_at=coalesce(least(atlas.communication_threads.first_event_at,excluded.first_event_at),atlas.communication_threads.first_event_at,excluded.first_event_at),last_event_at=coalesce(greatest(atlas.communication_threads.last_event_at,excluded.last_event_at),atlas.communication_threads.last_event_at,excluded.last_event_at),updated_at=now()
      returning id into v_thread_id;
    end if;

    select * into v_existing from atlas.communication_events where connected_source_id=v_source.id and source_event_ref=v_event_ref;
    if v_existing.id is not null then
      v_event_id:=v_existing.id;
      if v_existing.source_content_hash=v_source_hash then
        v_already:=v_already+1;
      else
        v_conflicts:=v_conflicts+1;
        insert into atlas.communication_event_conflicts(principal_id,organization_id,organization_unit_id,connected_source_id,existing_event_id,ingest_batch_id,source_event_ref,existing_source_content_hash,incoming_source_content_hash,existing_custody_source_hash,incoming_custody_source_hash,incoming_event)
        values(v_principal_id,null,null,v_source.id,v_existing.id,v_batch_id,v_event_ref,v_existing.source_content_hash,v_source_hash,v_existing.custody_source_hash,v_custody_hash,v_event)
        on conflict (existing_event_id,incoming_custody_source_hash) do nothing;
        continue;
      end if;
    else
      insert into atlas.communication_events(principal_id,organization_id,organization_unit_id,connected_source_id,thread_id,ingest_batch_id,source_event_ref,occurred_at,captured_at,direction,speaker_is_self,speaker_address,body,body_state,source_authority,permitted_state_effect,governing_state_changed,source_content_hash,custody_source_hash,canonical_event)
      values(v_principal_id,null,null,v_source.id,v_thread_id,v_batch_id,v_event_ref,v_occurred_at,v_captured_at,v_event->>'direction',coalesce((v_event#>>'{speaker,isSelf}')::boolean,false),v_event#>>'{speaker,address}',v_event->>'body',v_event->>'bodyState','evidence_only','append_source_attributed_evidence_only',false,v_source_hash,v_custody_hash,v_event)
      returning id into v_event_id;
      v_admitted:=v_admitted+1;
    end if;

    if not exists(select 1 from atlas.communication_event_participants where communication_event_id=v_event_id) then
      v_participant_result:=atlas.record_communication_event_participants_service_v1(v_event_id,v_participants);
    end if;
    v_admission:=atlas.ensure_principal_communication_conversation_for_event_service_v1(v_event_id);
    if v_admission->>'state'='admitted' then v_conversations:=v_conversations+1; end if;
    if v_occurred_at is not null then v_first:=case when v_first is null then v_occurred_at else least(v_first,v_occurred_at) end; v_last:=case when v_last is null then v_occurred_at else greatest(v_last,v_occurred_at) end; end if;
  end loop;

  update atlas.communication_ingest_batches set admitted_count=v_admitted,already_in_custody_count=v_already,conflict_count=v_conflicts,first_occurred_at=v_first,last_occurred_at=v_last,completed_at=now(),metadata=metadata||jsonb_build_object('conversationAdmissions',v_conversations) where id=v_batch_id;
  update atlas.connected_sources set last_sync_at=now(),metadata=metadata||jsonb_build_object('communicationLastBatchId',v_batch_id,'communicationLastIngestedAt',now(),'communicationLastOccurredAt',v_last),updated_at=now() where id=v_source.id;

  return jsonb_build_object('contractVersion','principal_provider_communication_ingest_v1','batchId',v_batch_id,'connectedSourceId',v_source.id,'principalId',v_principal_id,'supplied',v_supplied,'admitted',v_admitted,'alreadyInCustody',v_already,'conflicts',v_conflicts,'conversationAdmissions',v_conversations,'firstOccurredAt',v_first,'lastOccurredAt',v_last,'governingStateChanged',false);
end;$function$;
revoke all on function atlas.ingest_principal_communication_events_service_v1(uuid,jsonb,jsonb) from public,anon,authenticated;
grant execute on function atlas.ingest_principal_communication_events_service_v1(uuid,jsonb,jsonb) to service_role;

-- Principal-owned conversation list/detail membranes for the Personal Atlas.
create or replace function atlas.principal_communication_conversations_self_api_v1(
  p_communication_endpoint_id uuid default null,
  p_limit integer default 100
)
returns table(
  communication_conversation_id uuid,
  subject text,
  conversation_state text,
  last_activity_at timestamptz,
  communication_endpoint_id uuid,
  endpoint_address text,
  last_communication_event_id uuid,
  last_event_direction text,
  last_event_at timestamptz,
  last_event_body text
)
language sql stable security definer set search_path=pg_catalog,atlas,auth as $function$
  with me as (
    select p.id principal_id from atlas.principals p where p.user_id=auth.uid() and p.status='active' order by p.created_at,p.id limit 1
  ), scoped as (
    select cc.id,cc.subject,cc.conversation_state,cc.last_activity_at,cep.communication_endpoint_id,ep.address
    from me join atlas.communication_conversations cc on cc.principal_id=me.principal_id
    join atlas.communication_conversation_endpoints cep on cep.communication_conversation_id=cc.id
    join atlas.communication_endpoints ep on ep.id=cep.communication_endpoint_id and ep.principal_id=me.principal_id
    where p_communication_endpoint_id is null or ep.id=p_communication_endpoint_id
  )
  select s.id,s.subject,s.conversation_state,s.last_activity_at,s.communication_endpoint_id,s.address,
         last_event.communication_event_id,e.direction,coalesce(e.occurred_at,e.captured_at),e.body
  from scoped s
  left join lateral (
    select ce.communication_event_id from atlas.communication_conversation_events ce where ce.communication_conversation_id=s.id order by coalesce(ce.occurred_at,ce.created_at) desc,ce.id desc limit 1
  ) last_event on true
  left join atlas.communication_events e on e.id=last_event.communication_event_id
  order by s.last_activity_at desc,s.id
  limit greatest(1,least(coalesce(p_limit,100),250));
$function$;
revoke all on function atlas.principal_communication_conversations_self_api_v1(uuid,integer) from public,anon;
grant execute on function atlas.principal_communication_conversations_self_api_v1(uuid,integer) to authenticated;

create or replace function atlas.principal_communication_conversation_detail_self_api_v1(p_communication_conversation_id uuid)
returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_principal_id uuid; v_conversation atlas.communication_conversations%rowtype; v_messages jsonb;
begin
  select id into v_principal_id from atlas.principals where user_id=auth.uid() and status='active' order by created_at,id limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;
  select * into v_conversation from atlas.communication_conversations where id=p_communication_conversation_id and principal_id=v_principal_id;
  if v_conversation.id is null then raise exception 'Communication conversation not found.' using errcode='P0002'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'communicationEventId',e.id,'occurredAt',e.occurred_at,'capturedAt',e.captured_at,'direction',e.direction,
    'speakerAddress',e.speaker_address,'body',e.body,'bodyState',e.body_state,'canonicalEvent',e.canonical_event
  ) order by coalesce(e.occurred_at,e.captured_at),e.id),'[]'::jsonb)
  into v_messages
  from atlas.communication_conversation_events ce join atlas.communication_events e on e.id=ce.communication_event_id
  where ce.communication_conversation_id=v_conversation.id;
  return jsonb_build_object('contractVersion','principal_communication_conversation_detail_v1','conversation',jsonb_build_object('id',v_conversation.id,'subject',v_conversation.subject,'state',v_conversation.conversation_state,'lastActivityAt',v_conversation.last_activity_at),'messages',v_messages);
end;$function$;
revoke all on function atlas.principal_communication_conversation_detail_self_api_v1(uuid) from public,anon;
grant execute on function atlas.principal_communication_conversation_detail_self_api_v1(uuid) to authenticated;

revoke all on table atlas.communication_conversation_events from public,anon,authenticated;
alter table atlas.communication_conversation_events enable row level security;

commit;