begin;

-- Package 7 Communications convergence Stage 2.
--
-- Canonical read identity is the provider-independent Communication Conversation.
-- Communication Endpoint remains access/transport context. Institutional Conversation
-- remains a compatibility/governance carrier for response/work semantics.
--
-- This migration is intentionally read-only in behavior: it creates no Response Case,
-- Company Work, responsibility, disposition, read state, or Communication Event.

create or replace function atlas.organization_correspondence_effective_organization_v1(
  p_communication_conversation_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_count int;
  v_organization_id uuid;
begin
  select count(distinct atlas.effective_communication_endpoint_organization_v1(cce.communication_endpoint_id)),
         min(atlas.effective_communication_endpoint_organization_v1(cce.communication_endpoint_id)::text)::uuid
  into v_count,v_organization_id
  from atlas.communication_conversation_endpoints cce
  join atlas.communication_endpoints ep on ep.id=cce.communication_endpoint_id
  where cce.communication_conversation_id=p_communication_conversation_id;

  if v_count<>1 then
    return null;
  end if;

  return v_organization_id;
end;
$function$;

comment on function atlas.organization_correspondence_effective_organization_v1(uuid) is
'Resolves one effective institutional-custody Organization for a common Communication Conversation from its endpoint contexts. Returns null when endpoint custody is absent or ambiguous.';

create or replace function atlas.organization_correspondence_read_authorized_self_v1(
  p_communication_conversation_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_conversation atlas.communication_conversations%rowtype;
  v_endpoint_count int;
  v_effective_organization_count int;
  v_all_visible boolean;
begin
  if auth.uid() is null then
    return false;
  end if;

  select * into v_conversation
  from atlas.communication_conversations
  where id=p_communication_conversation_id;

  if v_conversation.id is null
     or v_conversation.organization_id is null
     or v_conversation.principal_id is not null then
    return false;
  end if;

  select count(*),
         count(distinct atlas.effective_communication_endpoint_organization_v1(cce.communication_endpoint_id)),
         coalesce(bool_and(atlas.communication_endpoint_authorized_self_v1(cce.communication_endpoint_id,'view')),false)
  into v_endpoint_count,v_effective_organization_count,v_all_visible
  from atlas.communication_conversation_endpoints cce
  where cce.communication_conversation_id=v_conversation.id;

  -- A correspondence Conversation with no endpoint context cannot inherit the
  -- Organization Mailroom's existing view authority. Multiple effective custody
  -- organizations are ambiguous and therefore fail closed.
  if v_endpoint_count=0 or v_effective_organization_count<>1 then
    return false;
  end if;

  return v_all_visible;
end;
$function$;

comment on function atlas.organization_correspondence_read_authorized_self_v1(uuid) is
'Common Conversation read membrane for Organization correspondence. Preserves effective institutional custody plus existing endpoint view capability/owner semantics while making the Conversation, not the endpoint, the read identity.';

create or replace function atlas.organization_correspondence_list_self_api_v1(
  p_organization_id uuid default null,
  p_communication_endpoint_id uuid default null,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_items jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_limit<1 or p_limit>500 then
    raise exception 'Correspondence limit must be between 1 and 500.' using errcode='22023';
  end if;

  if p_communication_endpoint_id is not null
     and not atlas.communication_endpoint_authorized_self_v1(p_communication_endpoint_id,'view') then
    raise exception 'Communication endpoint view authority required.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(q.item order by q.last_activity_at desc,q.communication_conversation_id),'[]'::jsonb)
  into v_items
  from (
    select cc.id as communication_conversation_id,
           cc.last_activity_at,
           jsonb_build_object(
             'communicationConversationId',cc.id,
             'effectiveOrganizationId',atlas.organization_correspondence_effective_organization_v1(cc.id),
             'physicalOrganizationId',cc.organization_id,
             'organizationUnitId',cc.organization_unit_id,
             'subject',cc.subject,
             'conversationState',cc.conversation_state,
             'openedAt',cc.opened_at,
             'lastActivityAt',cc.last_activity_at,
             'latestEvent',case when latest_event.id is null then null else jsonb_build_object(
               'communicationEventId',latest_event.id,
               'communicationEndpointId',latest_event.communication_endpoint_id,
               'direction',latest_event.direction,
               'occurredAt',latest_event.occurred_at,
               'capturedAt',latest_event.captured_at,
               'speakerIsSelf',latest_event.speaker_is_self,
               'speakerAddress',latest_event.speaker_address,
               'body',latest_event.body,
               'bodyState',latest_event.body_state,
               'hasAttachment',latest_event.has_attachment
             ) end,
             'endpoints',coalesce(endpoint_context.items,'[]'::jsonb),
             'institutionalCompatibility',jsonb_build_object(
               'institutionalConversationIds',coalesce(institutional_context.conversation_ids,'[]'::jsonb),
               'primaryInstitutionalConversationId',institutional_context.primary_conversation_id,
               'disposition',coalesce(institutional_context.disposition,'inbox'),
               'responseCase',institutional_context.response_case,
               'latestResponseEvent',institutional_context.latest_response_event,
               'derivedWorkCount',coalesce(institutional_context.derived_work_count,0)
             )
           ) as item
    from atlas.communication_conversations cc
    left join lateral (
      select e.id,cce.communication_endpoint_id,e.direction,e.occurred_at,e.captured_at,
             e.speaker_is_self,e.speaker_address,e.body,e.body_state,
             exists(select 1 from atlas.communication_attachments a where a.event_id=e.id) as has_attachment
      from atlas.communication_conversation_events cce
      join atlas.communication_events e on e.id=cce.communication_event_id
      where cce.communication_conversation_id=cc.id
      order by coalesce(cce.occurred_at,e.occurred_at,e.captured_at) desc,cce.created_at desc,cce.id desc
      limit 1
    ) latest_event on true
    left join lateral (
      select jsonb_agg(jsonb_build_object(
               'communicationEndpointId',ep.id,
               'endpointKind',ep.endpoint_kind,
               'address',ep.address,
               'displayName',ep.display_name,
               'endpointState',ep.endpoint_state,
               'effectiveOrganizationId',atlas.effective_communication_endpoint_organization_v1(ep.id)
             ) order by ep.display_name nulls last,ep.address,ep.id) as items
      from atlas.communication_conversation_endpoints cce
      join atlas.communication_endpoints ep on ep.id=cce.communication_endpoint_id
      where cce.communication_conversation_id=cc.id
    ) endpoint_context on true
    left join lateral (
      with roots as (
        select r.institutional_conversation_id
        from atlas.institutional_conversation_roots r
        where r.communication_conversation_id=cc.id
      ), primary_root as (
        select institutional_conversation_id
        from roots
        order by institutional_conversation_id
        limit 1
      ), current_disposition as (
        select de.disposition
        from atlas.institutional_conversation_disposition_events de
        join roots r on r.institutional_conversation_id=de.institutional_conversation_id
        order by de.created_at desc,de.id desc
        limit 1
      ), current_case as (
        select rc.*
        from atlas.institutional_conversation_response_cases rc
        join roots r on r.institutional_conversation_id=rc.institutional_conversation_id
        order by (rc.case_state<>'closed') desc,rc.opened_at desc,rc.id desc
        limit 1
      ), current_response_event as (
        select re.*
        from atlas.institutional_conversation_response_events re
        join current_case rc on rc.id=re.response_case_id
        order by re.occurred_at desc,re.id desc
        limit 1
      )
      select (select jsonb_agg(r.institutional_conversation_id order by r.institutional_conversation_id) from roots r) as conversation_ids,
             (select institutional_conversation_id from primary_root) as primary_conversation_id,
             (select disposition from current_disposition) as disposition,
             (select case when rc.id is null then null else jsonb_build_object(
                       'responseCaseId',rc.id,
                       'institutionalConversationId',rc.institutional_conversation_id,
                       'caseNumber',rc.case_number,
                       'caseState',rc.case_state,
                       'openedAt',rc.opened_at,
                       'closedAt',rc.closed_at
                     ) end from current_case rc) as response_case,
             (select case when re.id is null then null else jsonb_build_object(
                       'responseEventId',re.id,
                       'eventKind',re.event_kind,
                       'fromState',re.from_state,
                       'toState',re.to_state,
                       'actorMembershipId',re.actor_membership_id,
                       'targetMembershipId',re.target_membership_id,
                       'workItemId',re.work_item_id,
                       'occurredAt',re.occurred_at
                     ) end from current_response_event re) as latest_response_event,
             (select count(*) from atlas.communication_derived_work_links l join roots r on r.institutional_conversation_id=l.institutional_conversation_id) as derived_work_count
    ) institutional_context on true
    where cc.organization_id is not null
      and cc.principal_id is null
      and atlas.organization_correspondence_read_authorized_self_v1(cc.id)
      and (p_organization_id is null or atlas.organization_correspondence_effective_organization_v1(cc.id)=p_organization_id)
      and (p_communication_endpoint_id is null or exists(
        select 1 from atlas.communication_conversation_endpoints cce
        where cce.communication_conversation_id=cc.id
          and cce.communication_endpoint_id=p_communication_endpoint_id
      ))
    order by cc.last_activity_at desc,cc.id
    limit p_limit
  ) q;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','organization_correspondence_list_v1',
    'identityRoot','communication_conversation',
    'organizationId',p_organization_id,
    'communicationEndpointFilterId',p_communication_endpoint_id,
    'items',v_items
  );
end;
$function$;

comment on function atlas.organization_correspondence_list_self_api_v1(uuid,uuid,integer) is
'Reads Organization correspondence as provider-independent Communication Conversations. Endpoint is an optional access/filter context, never the canonical item identity.';

create or replace function atlas.organization_correspondence_conversation_self_api_v1(
  p_communication_conversation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_conversation atlas.communication_conversations%rowtype;
  v_endpoints jsonb;
  v_events jsonb;
  v_institutional_ids jsonb;
  v_response_cases jsonb;
  v_derived_work jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_conversation
  from atlas.communication_conversations
  where id=p_communication_conversation_id;

  if v_conversation.id is null then
    raise exception 'Communication Conversation not found.' using errcode='P0002';
  end if;
  if not atlas.organization_correspondence_read_authorized_self_v1(v_conversation.id) then
    raise exception 'Correspondence view authority required.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'communicationEndpointId',ep.id,
           'endpointKind',ep.endpoint_kind,
           'address',ep.address,
           'displayName',ep.display_name,
           'endpointState',ep.endpoint_state,
           'effectiveOrganizationId',atlas.effective_communication_endpoint_organization_v1(ep.id)
         ) order by ep.display_name nulls last,ep.address,ep.id),'[]'::jsonb)
  into v_endpoints
  from atlas.communication_conversation_endpoints cce
  join atlas.communication_endpoints ep on ep.id=cce.communication_endpoint_id
  where cce.communication_conversation_id=v_conversation.id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'communicationEventId',e.id,
           'communicationEndpointId',cce.communication_endpoint_id,
           'connectedSourceId',e.connected_source_id,
           'communicationThreadId',e.thread_id,
           'direction',e.direction,
           'occurredAt',e.occurred_at,
           'capturedAt',e.captured_at,
           'speakerIsSelf',e.speaker_is_self,
           'speakerAddress',e.speaker_address,
           'body',e.body,
           'bodyState',e.body_state,
           'participants',coalesce((
             select jsonb_agg(jsonb_build_object(
               'participantRole',p.participant_role,
               'addressKind',p.address_kind,
               'address',p.address,
               'isSelf',p.is_self,
               'displayName',p.metadata->>'displayName'
             ) order by p.is_self desc,p.participant_role,p.address_normalized,p.id)
             from atlas.communication_event_participants p
             where p.communication_event_id=e.id
           ),'[]'::jsonb),
           'attachments',coalesce((
             select jsonb_agg(jsonb_build_object(
               'attachmentId',a.id,
               'sourceAttachmentRef',a.source_attachment_ref,
               'mimeType',a.mime_type,
               'transferName',a.transfer_name,
               'custodyLocator',a.custody_locator,
               'metadata',a.metadata
             ) order by a.created_at,a.id)
             from atlas.communication_attachments a
             where a.event_id=e.id
           ),'[]'::jsonb)
         ) order by coalesce(cce.occurred_at,e.occurred_at,e.captured_at),cce.created_at,cce.id),'[]'::jsonb)
  into v_events
  from atlas.communication_conversation_events cce
  join atlas.communication_events e on e.id=cce.communication_event_id
  where cce.communication_conversation_id=v_conversation.id;

  select coalesce(jsonb_agg(r.institutional_conversation_id order by r.institutional_conversation_id),'[]'::jsonb)
  into v_institutional_ids
  from atlas.institutional_conversation_roots r
  where r.communication_conversation_id=v_conversation.id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'responseCaseId',rc.id,
           'institutionalConversationId',rc.institutional_conversation_id,
           'caseNumber',rc.case_number,
           'caseState',rc.case_state,
           'openedByCommunicationEventId',rc.opened_by_communication_event_id,
           'openedAt',rc.opened_at,
           'closedAt',rc.closed_at,
           'latestResponseEvent',(
             select jsonb_build_object(
               'responseEventId',re.id,
               'eventKind',re.event_kind,
               'fromState',re.from_state,
               'toState',re.to_state,
               'actorMembershipId',re.actor_membership_id,
               'targetMembershipId',re.target_membership_id,
               'workItemId',re.work_item_id,
               'relatedCommunicationEventId',re.related_communication_event_id,
               'occurredAt',re.occurred_at
             )
             from atlas.institutional_conversation_response_events re
             where re.response_case_id=rc.id
             order by re.occurred_at desc,re.id desc
             limit 1
           )
         ) order by rc.opened_at,rc.id),'[]'::jsonb)
  into v_response_cases
  from atlas.institutional_conversation_response_cases rc
  join atlas.institutional_conversation_roots r
    on r.institutional_conversation_id=rc.institutional_conversation_id
  where r.communication_conversation_id=v_conversation.id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'workItemId',w.id,
           'institutionalConversationId',l.institutional_conversation_id,
           'communicationEventId',l.communication_event_id,
           'title',w.title,
           'workState',w.work_state,
           'evidenceExcerpt',l.evidence_excerpt,
           'createdAt',l.created_at
         ) order by l.created_at,l.id),'[]'::jsonb)
  into v_derived_work
  from atlas.communication_derived_work_links l
  join atlas.institutional_conversation_roots r
    on r.institutional_conversation_id=l.institutional_conversation_id
  join atlas.work_items w on w.id=l.work_item_id
  where r.communication_conversation_id=v_conversation.id;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','organization_correspondence_conversation_v1',
    'identityRoot','communication_conversation',
    'communicationConversationId',v_conversation.id,
    'effectiveOrganizationId',atlas.organization_correspondence_effective_organization_v1(v_conversation.id),
    'physicalOrganizationId',v_conversation.organization_id,
    'organizationUnitId',v_conversation.organization_unit_id,
    'subject',v_conversation.subject,
    'conversationState',v_conversation.conversation_state,
    'openedAt',v_conversation.opened_at,
    'lastActivityAt',v_conversation.last_activity_at,
    'endpoints',v_endpoints,
    'events',v_events,
    'institutionalCompatibility',jsonb_build_object(
      'institutionalConversationIds',v_institutional_ids,
      'responseCases',v_response_cases,
      'derivedWork',v_derived_work
    )
  );
end;
$function$;

comment on function atlas.organization_correspondence_conversation_self_api_v1(uuid) is
'Reads one Organization correspondence Conversation from common event membership. Institutional Response Case and Company Work state are projected as consequences without becoming correspondence identity.';

create or replace function atlas.organization_correspondence_search_self_api_v1(
  p_query text,
  p_organization_id uuid default null,
  p_communication_endpoint_id uuid default null,
  p_filters jsonb default '{}'::jsonb,
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_query text:=btrim(coalesce(p_query,''));
  v_filters jsonb:=coalesce(p_filters,'{}'::jsonb);
  v_items jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_limit<1 or p_limit>500 then raise exception 'Search limit must be between 1 and 500.' using errcode='22023'; end if;
  if jsonb_typeof(v_filters)<>'object' then raise exception 'Search filters must be an object.' using errcode='22023'; end if;
  if p_communication_endpoint_id is not null
     and not atlas.communication_endpoint_authorized_self_v1(p_communication_endpoint_id,'view') then
    raise exception 'Communication endpoint view authority required.' using errcode='42501';
  end if;

  with candidates as (
    select cc.id as communication_conversation_id,
           cc.subject,
           cc.last_activity_at,
           atlas.organization_correspondence_effective_organization_v1(cc.id) as effective_organization_id,
           endpoint_context.endpoint_id,
           endpoint_context.endpoint_kind,
           endpoint_context.endpoint_name,
           institutional_context.institutional_conversation_id,
           coalesce(institutional_context.disposition,'inbox') as disposition,
           coalesce(event_text.participant_text,'') as participant_text,
           coalesce(event_text.body_text,'') as body_text,
           coalesce(event_text.attachment_text,'') as attachment_text,
           coalesce(institutional_context.work_text,'') as work_text,
           coalesce(event_text.has_attachment,false) as has_attachment
    from atlas.communication_conversations cc
    left join lateral (
      select ep.id as endpoint_id,ep.endpoint_kind,ep.display_name as endpoint_name
      from atlas.communication_conversation_endpoints cce
      join atlas.communication_endpoints ep on ep.id=cce.communication_endpoint_id
      where cce.communication_conversation_id=cc.id
        and (p_communication_endpoint_id is null or ep.id=p_communication_endpoint_id)
      order by ep.id
      limit 1
    ) endpoint_context on true
    left join lateral (
      select string_agg(coalesce(p.metadata->>'displayName','')||' '||p.address,' ') as participant_text,
             string_agg(coalesce(e.body,''),' ') as body_text,
             string_agg(coalesce(a.transfer_names,''),' ') as attachment_text,
             bool_or(coalesce(a.has_attachment,false)) as has_attachment
      from atlas.communication_conversation_events cce
      join atlas.communication_events e on e.id=cce.communication_event_id
      left join lateral (
        select string_agg(coalesce(p.metadata->>'displayName','')||' '||p.address,' ') as participant_text
        from atlas.communication_event_participants p
        where p.communication_event_id=e.id
      ) participant on true
      left join lateral (
        select string_agg(coalesce(att.transfer_name,''),' ') as transfer_names,true as has_attachment
        from atlas.communication_attachments att
        where att.event_id=e.id
      ) a on true
      left join atlas.communication_event_participants p on p.communication_event_id=e.id
      where cce.communication_conversation_id=cc.id
    ) event_text on true
    left join lateral (
      with roots as (
        select r.institutional_conversation_id
        from atlas.institutional_conversation_roots r
        where r.communication_conversation_id=cc.id
      )
      select (select institutional_conversation_id from roots order by institutional_conversation_id limit 1) as institutional_conversation_id,
             (select de.disposition
              from atlas.institutional_conversation_disposition_events de
              join roots r on r.institutional_conversation_id=de.institutional_conversation_id
              order by de.created_at desc,de.id desc limit 1) as disposition,
             (select string_agg(coalesce(w.title,'')||' '||coalesce(w.instructions,''),' ')
              from atlas.communication_derived_work_links l
              join roots r on r.institutional_conversation_id=l.institutional_conversation_id
              join atlas.work_items w on w.id=l.work_item_id) as work_text
    ) institutional_context on true
    where cc.organization_id is not null
      and cc.principal_id is null
      and atlas.organization_correspondence_read_authorized_self_v1(cc.id)
      and (p_organization_id is null or atlas.organization_correspondence_effective_organization_v1(cc.id)=p_organization_id)
      and (p_communication_endpoint_id is null or endpoint_context.endpoint_id is not null)
  ), ranked as (
    select *,case when v_query='' then 0::real else ts_rank_cd(
      to_tsvector('simple',coalesce(subject,'')||' '||participant_text||' '||body_text||' '||attachment_text||' '||work_text),
      websearch_to_tsquery('simple',v_query)
    ) end as rank
    from candidates
    where (v_query='' or to_tsvector('simple',coalesce(subject,'')||' '||participant_text||' '||body_text||' '||attachment_text||' '||work_text)
             @@ websearch_to_tsquery('simple',v_query))
      and (not(v_filters ? 'disposition') or disposition=v_filters->>'disposition')
      and (coalesce((v_filters->>'hasAttachment')::boolean,false)=false or has_attachment)
      and (not(v_filters ? 'dateFrom') or last_activity_at >= (v_filters->>'dateFrom')::timestamptz)
      and (not(v_filters ? 'dateTo') or last_activity_at <= (v_filters->>'dateTo')::timestamptz)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'communicationConversationId',communication_conversation_id,
           'institutionalConversationId',institutional_conversation_id,
           'effectiveOrganizationId',effective_organization_id,
           'endpointId',endpoint_id,
           'endpointKind',endpoint_kind,
           'endpointName',endpoint_name,
           'subject',subject,
           'lastActivityAt',last_activity_at,
           'disposition',disposition,
           'hasAttachment',has_attachment,
           'rank',rank
         ) order by rank desc,last_activity_at desc,communication_conversation_id),'[]'::jsonb)
  into v_items
  from (select * from ranked order by rank desc,last_activity_at desc,communication_conversation_id limit p_limit) q;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','organization_correspondence_search_v1',
    'identityRoot','communication_conversation',
    'query',v_query,
    'organizationId',p_organization_id,
    'communicationEndpointFilterId',p_communication_endpoint_id,
    'items',v_items
  );
end;
$function$;

comment on function atlas.organization_correspondence_search_self_api_v1(text,uuid,uuid,jsonb,integer) is
'Searches visible Organization correspondence by common Communication Conversation identity across message, participant, attachment, and derived-work evidence.';

create or replace function atlas.organization_correspondence_sent_self_api_v1(
  p_organization_id uuid default null,
  p_communication_endpoint_id uuid default null,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_items jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_limit<1 or p_limit>500 then raise exception 'Sent limit must be between 1 and 500.' using errcode='22023'; end if;
  if p_communication_endpoint_id is not null
     and not atlas.communication_endpoint_authorized_self_v1(p_communication_endpoint_id,'view') then
    raise exception 'Communication endpoint view authority required.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'outboundOperationId',q.id,
           'communicationConversationId',q.communication_conversation_id,
           'institutionalConversationId',q.institutional_conversation_id,
           'communicationEndpointId',q.communication_endpoint_id,
           'communicationEventId',q.communication_event_id,
           'operationState',q.operation_state,
           'authorizedAt',q.authorized_at,
           'acceptedAt',q.accepted_at,
           'failedAt',q.failed_at,
           'to',q.to_recipients,
           'cc',q.cc_recipients,
           'bcc',q.bcc_recipients,
           'subject',q.subject,
           'bodyText',q.body_text,
           'attachmentRefs',q.attachment_refs,
           'latestAttempt',q.latest_attempt,
           'recipientResults',q.recipient_results
         ) order by q.authorized_at desc,q.id),'[]'::jsonb)
  into v_items
  from (
    select o.*,r.communication_conversation_id,el.communication_event_id,
           la.attempt as latest_attempt,coalesce(la.recipients,'[]'::jsonb) as recipient_results
    from atlas.communication_outbound_operations o
    join atlas.institutional_conversation_roots r
      on r.institutional_conversation_id=o.institutional_conversation_id
    left join atlas.communication_outbound_event_links el on el.outbound_operation_id=o.id
    left join lateral (
      select jsonb_build_object(
               'attemptId',a.id,'attemptNumber',a.attempt_number,'resultState',a.result_state,
               'providerMessageRef',a.provider_message_ref,'attemptedAt',a.attempted_at
             ) as attempt,
             (select coalesce(jsonb_agg(jsonb_build_object(
                'role',ar.recipient_role,'address',ar.recipient_address,
                'resultState',ar.result_state,'providerResponse',ar.provider_response
              ) order by ar.recipient_role,ar.recipient_address),'[]'::jsonb)
              from atlas.communication_outbound_attempt_recipients ar
              where ar.outbound_attempt_id=a.id) as recipients
      from atlas.communication_outbound_attempts a
      where a.outbound_operation_id=o.id
      order by a.attempt_number desc
      limit 1
    ) la on true
    where atlas.organization_correspondence_read_authorized_self_v1(r.communication_conversation_id)
      and (p_organization_id is null or atlas.organization_correspondence_effective_organization_v1(r.communication_conversation_id)=p_organization_id)
      and (p_communication_endpoint_id is null or o.communication_endpoint_id=p_communication_endpoint_id)
    order by o.authorized_at desc,o.id
    limit p_limit
  ) q;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','organization_correspondence_sent_v1',
    'identityRoot','communication_conversation',
    'organizationId',p_organization_id,
    'communicationEndpointFilterId',p_communication_endpoint_id,
    'items',v_items
  );
end;
$function$;

comment on function atlas.organization_correspondence_sent_self_api_v1(uuid,uuid,integer) is
'Reads sent correspondence with common Communication Conversation identity while retaining outbound operation and endpoint transport evidence.';

-- ---------------------------------------------------------------------------
-- Institutional Mailroom compatibility carriers.
-- The legacy implementations remain intact under private names so callers can
-- keep their existing JSON contracts while every primary read first resolves
-- and authorizes the common Communication Conversation root.
-- ---------------------------------------------------------------------------

alter function atlas.institutional_shared_inbox_self_v3(uuid,integer)
  rename to institutional_shared_inbox_legacy_v3;
revoke all on function atlas.institutional_shared_inbox_legacy_v3(uuid,integer) from public,anon,authenticated;
grant execute on function atlas.institutional_shared_inbox_legacy_v3(uuid,integer) to service_role;

create or replace function atlas.institutional_shared_inbox_self_v3(
  p_communication_endpoint_id uuid,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_payload jsonb;
  v_items jsonb;
  v_expected int;
  v_resolved int;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if not atlas.communication_endpoint_authorized_self_v1(p_communication_endpoint_id,'view') then
    raise exception 'Communication endpoint view authority required.' using errcode='42501';
  end if;

  v_payload:=atlas.institutional_shared_inbox_legacy_v3(p_communication_endpoint_id,p_limit);
  select jsonb_array_length(coalesce(v_payload->'items','[]'::jsonb)) into v_expected;

  select count(*),coalesce(jsonb_agg(
           item || jsonb_build_object('communication_conversation_id',root.communication_conversation_id)
           order by item->>'last_activity_at' desc
         ),'[]'::jsonb)
  into v_resolved,v_items
  from jsonb_array_elements(coalesce(v_payload->'items','[]'::jsonb)) item
  join atlas.institutional_conversation_roots root
    on root.institutional_conversation_id=nullif(item->>'institutional_conversation_id','')::uuid
  where atlas.organization_correspondence_read_authorized_self_v1(root.communication_conversation_id);

  if v_resolved<>v_expected then
    raise exception 'Institutional inbox contains correspondence outside the common Conversation read membrane.' using errcode='23514';
  end if;

  return (v_payload-'items') || jsonb_build_object(
    'items',v_items,
    'identityRoot','communication_conversation',
    'compatibilityCarrier','institutional_shared_inbox_v3'
  );
end;
$function$;

alter function atlas.institutional_conversation_detail_self_v4(uuid)
  rename to institutional_conversation_detail_legacy_v4;
revoke all on function atlas.institutional_conversation_detail_legacy_v4(uuid) from public,anon,authenticated;
grant execute on function atlas.institutional_conversation_detail_legacy_v4(uuid) to service_role;

create or replace function atlas.institutional_conversation_detail_self_v4(
  p_institutional_conversation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_root uuid;
  v_common jsonb;
  v_legacy jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select communication_conversation_id into v_root
  from atlas.institutional_conversation_roots
  where institutional_conversation_id=p_institutional_conversation_id;

  if v_root is null then
    raise exception 'Institutional Conversation is not rooted in common Communication Conversation.' using errcode='23514';
  end if;

  -- Canonical read and authorization occur through the common membrane first.
  v_common:=atlas.organization_correspondence_conversation_self_api_v1(v_root);
  v_legacy:=atlas.institutional_conversation_detail_legacy_v4(p_institutional_conversation_id);

  return v_legacy || jsonb_build_object(
    'communicationConversationId',v_root,
    'identityRoot','communication_conversation',
    'compatibilityCarrier','institutional_conversation_detail_v4'
  );
end;
$function$;

alter function atlas.institutional_correspondence_search_self_api_v1(text,uuid,jsonb,integer)
  rename to institutional_correspondence_search_legacy_v1;
revoke all on function atlas.institutional_correspondence_search_legacy_v1(text,uuid,jsonb,integer) from public,anon,authenticated;
grant execute on function atlas.institutional_correspondence_search_legacy_v1(text,uuid,jsonb,integer) to service_role;

create or replace function atlas.institutional_correspondence_search_self_api_v1(
  p_query text,
  p_communication_endpoint_id uuid default null,
  p_filters jsonb default '{}'::jsonb,
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_common jsonb;
  v_items jsonb;
begin
  v_common:=atlas.organization_correspondence_search_self_api_v1(
    p_query,null,p_communication_endpoint_id,p_filters,p_limit
  );

  select coalesce(jsonb_agg(jsonb_build_object(
           'conversationId',nullif(item->>'institutionalConversationId','')::uuid,
           'communicationConversationId',nullif(item->>'communicationConversationId','')::uuid,
           'endpointId',nullif(item->>'endpointId','')::uuid,
           'endpointKind',item->>'endpointKind',
           'endpointName',item->>'endpointName',
           'subject',item->>'subject',
           'lastActivityAt',item->>'lastActivityAt',
           'disposition',item->>'disposition',
           'hasAttachment',coalesce((item->>'hasAttachment')::boolean,false),
           'rank',coalesce((item->>'rank')::real,0)
         ) order by coalesce((item->>'rank')::real,0) desc,(item->>'lastActivityAt')::timestamptz desc),'[]'::jsonb)
  into v_items
  from jsonb_array_elements(coalesce(v_common->'items','[]'::jsonb)) item
  where nullif(item->>'institutionalConversationId','') is not null;

  return jsonb_build_object(
    'contractVersion','institutional_correspondence_search_v1',
    'query',btrim(coalesce(p_query,'')),
    'identityRoot','communication_conversation',
    'compatibilityCarrier','institutional_correspondence_search_v1',
    'items',v_items
  );
end;
$function$;

alter function atlas.institutional_sent_mail_self_v1(uuid,integer)
  rename to institutional_sent_mail_legacy_v1;
revoke all on function atlas.institutional_sent_mail_legacy_v1(uuid,integer) from public,anon,authenticated;
grant execute on function atlas.institutional_sent_mail_legacy_v1(uuid,integer) to service_role;

create or replace function atlas.institutional_sent_mail_self_v1(
  p_communication_endpoint_id uuid,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_common jsonb;
  v_items jsonb;
begin
  v_common:=atlas.organization_correspondence_sent_self_api_v1(null,p_communication_endpoint_id,p_limit);

  select coalesce(jsonb_agg(
           (item - 'institutionalConversationId' - 'communicationConversationId') || jsonb_build_object(
             'conversationId',nullif(item->>'institutionalConversationId','')::uuid,
             'communicationConversationId',nullif(item->>'communicationConversationId','')::uuid
           )
           order by (item->>'authorizedAt')::timestamptz desc,item->>'outboundOperationId'
         ),'[]'::jsonb)
  into v_items
  from jsonb_array_elements(coalesce(v_common->'items','[]'::jsonb)) item;

  return jsonb_build_object(
    'contractVersion','institutional_sent_mail_v1',
    'communicationEndpointId',p_communication_endpoint_id,
    'identityRoot','communication_conversation',
    'compatibilityCarrier','institutional_sent_mail_v1',
    'items',v_items
  );
end;
$function$;

-- Public/anonymous access remains closed. Canonical self APIs are the only new
-- authenticated read surface; internal custody/authority helpers stay private.
revoke all on function atlas.organization_correspondence_effective_organization_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.organization_correspondence_read_authorized_self_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.organization_correspondence_effective_organization_v1(uuid) to service_role;
grant execute on function atlas.organization_correspondence_read_authorized_self_v1(uuid) to service_role;

revoke all on function atlas.organization_correspondence_list_self_api_v1(uuid,uuid,integer) from public,anon;
revoke all on function atlas.organization_correspondence_conversation_self_api_v1(uuid) from public,anon;
revoke all on function atlas.organization_correspondence_search_self_api_v1(text,uuid,uuid,jsonb,integer) from public,anon;
revoke all on function atlas.organization_correspondence_sent_self_api_v1(uuid,uuid,integer) from public,anon;
grant execute on function atlas.organization_correspondence_list_self_api_v1(uuid,uuid,integer) to authenticated,service_role;
grant execute on function atlas.organization_correspondence_conversation_self_api_v1(uuid) to authenticated,service_role;
grant execute on function atlas.organization_correspondence_search_self_api_v1(text,uuid,uuid,jsonb,integer) to authenticated,service_role;
grant execute on function atlas.organization_correspondence_sent_self_api_v1(uuid,uuid,integer) to authenticated,service_role;

revoke all on function atlas.institutional_shared_inbox_self_v3(uuid,integer) from public,anon;
revoke all on function atlas.institutional_conversation_detail_self_v4(uuid) from public,anon;
revoke all on function atlas.institutional_correspondence_search_self_api_v1(text,uuid,jsonb,integer) from public,anon;
revoke all on function atlas.institutional_sent_mail_self_v1(uuid,integer) from public,anon;
grant execute on function atlas.institutional_shared_inbox_self_v3(uuid,integer) to authenticated,service_role;
grant execute on function atlas.institutional_conversation_detail_self_v4(uuid) to authenticated,service_role;
grant execute on function atlas.institutional_correspondence_search_self_api_v1(text,uuid,jsonb,integer) to authenticated,service_role;
grant execute on function atlas.institutional_sent_mail_self_v1(uuid,integer) to authenticated,service_role;

comment on function atlas.institutional_shared_inbox_self_v3(uuid,integer) is
'Compatibility carrier. Institutional inbox contract is preserved, but every row must resolve to and pass the common Communication Conversation read membrane.';
comment on function atlas.institutional_conversation_detail_self_v4(uuid) is
'Compatibility carrier. Institutional detail first resolves and reads the common Communication Conversation, then overlays the preserved Institutional v4 contract.';
comment on function atlas.institutional_correspondence_search_self_api_v1(text,uuid,jsonb,integer) is
'Compatibility carrier over organization_correspondence_search_self_api_v1; conversationId remains legacy Institutional identity while communicationConversationId is canonical.';
comment on function atlas.institutional_sent_mail_self_v1(uuid,integer) is
'Compatibility carrier over organization_correspondence_sent_self_api_v1; outbound transport evidence is preserved while common Conversation is canonical correspondence identity.';

commit;
