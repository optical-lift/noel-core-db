begin;

create or replace function atlas.ensure_institutional_conversation_for_communication_event_service_v1(p_communication_event_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,extensions as $function$
declare
  v_event atlas.communication_events%rowtype; v_endpoint_id uuid; v_candidate_count int; v_conv_id uuid; v_stable_key text; v_subject text; v_review jsonb; v_review_hash text; v_rel uuid; v_created boolean:=false;
begin
  select * into v_event from atlas.communication_events where id=p_communication_event_id;
  if v_event.id is null then raise exception 'Communication event not found.' using errcode='P0002'; end if;
  if v_event.organization_id is null then return jsonb_build_object('contractVersion','institutional_conversation_admission_v1','state','not_institutional','communicationEventId',v_event.id); end if;

  select count(*),(array_agg(ep.id order by ep.id))[1] into v_candidate_count,v_endpoint_id
  from atlas.communication_endpoint_source_bindings b join atlas.communication_endpoints ep on ep.id=b.communication_endpoint_id
  where b.connected_source_id=v_event.connected_source_id and b.binding_state='active' and ep.endpoint_state='active'
    and (b.binding_role='send_receive' or (v_event.direction='incoming' and b.binding_role='receive') or (v_event.direction='outgoing' and b.binding_role='send') or v_event.direction='unknown')
    and exists(select 1 from atlas.communication_event_participants p where p.communication_event_id=v_event.id and p.is_self and p.address_normalized=ep.address_normalized and ((ep.endpoint_kind='email' and p.address_kind='email') or (ep.endpoint_kind in ('phone','sms','voice') and p.address_kind='phone') or ep.endpoint_kind not in ('email','phone','sms','voice')));

  if v_candidate_count=0 then
    select count(*),(array_agg(ep.id order by ep.id))[1] into v_candidate_count,v_endpoint_id
    from atlas.communication_endpoint_source_bindings b join atlas.communication_endpoints ep on ep.id=b.communication_endpoint_id
    where b.connected_source_id=v_event.connected_source_id and b.binding_state='active' and ep.endpoint_state='active'
      and (b.binding_role='send_receive' or (v_event.direction='incoming' and b.binding_role='receive') or (v_event.direction='outgoing' and b.binding_role='send') or v_event.direction='unknown');
  end if;

  if v_candidate_count<>1 then
    v_review:=jsonb_build_object('state',case when v_candidate_count=0 then 'no_endpoint' else 'ambiguous_endpoint' end,'communicationEventId',v_event.id,'connectedSourceId',v_event.connected_source_id,'candidateCount',v_candidate_count);
    v_review_hash:=encode(extensions.digest(convert_to(v_review::text,'UTF8'),'sha256'),'hex');
    insert into atlas.institutional_communication_admission_reviews(communication_event_id,connected_source_id,organization_id,organization_unit_id,review_state,evidence,evidence_sha256)
    values(v_event.id,v_event.connected_source_id,v_event.organization_id,v_event.organization_unit_id,case when v_candidate_count=0 then 'no_endpoint' else 'ambiguous_endpoint' end,v_review,v_review_hash) on conflict do nothing;
    return jsonb_build_object('contractVersion','institutional_conversation_admission_v1','state',case when v_candidate_count=0 then 'no_endpoint' else 'ambiguous_endpoint' end,'communicationEventId',v_event.id,'candidateCount',v_candidate_count);
  end if;

  if v_event.thread_id is not null then select institutional_conversation_id into v_conv_id from atlas.institutional_conversation_source_threads where communication_thread_id=v_event.thread_id; end if;
  if v_conv_id is null then
    v_stable_key:=case when v_event.thread_id is not null then 'source-thread:'||v_event.connected_source_id::text||':'||v_event.thread_id::text else 'source-event:'||v_event.id::text end;
    v_subject:=coalesce(nullif(btrim(v_event.canonical_event->>'subject'),''),nullif(btrim(v_event.canonical_event#>>'{sourcePayload,subject}'),''),'Conversation');
    insert into atlas.institutional_conversations(organization_id,organization_unit_id,stable_key,subject,opened_at,last_activity_at,metadata)
    values(v_event.organization_id,v_event.organization_unit_id,v_stable_key,v_subject,coalesce(v_event.occurred_at,v_event.captured_at),coalesce(v_event.occurred_at,v_event.captured_at),jsonb_build_object('createdFromCommunicationEventId',v_event.id))
    on conflict (organization_id,stable_key) do update set last_activity_at=greatest(atlas.institutional_conversations.last_activity_at,excluded.last_activity_at),updated_at=now()
    returning id into v_conv_id;
    v_created:=true;
    insert into atlas.institutional_conversation_endpoints(institutional_conversation_id,communication_endpoint_id,endpoint_role) values(v_conv_id,v_endpoint_id,'primary') on conflict do nothing;
    if v_event.thread_id is not null then insert into atlas.institutional_conversation_source_threads(institutional_conversation_id,communication_thread_id,connected_source_id,continuity_basis,metadata) values(v_conv_id,v_event.thread_id,v_event.connected_source_id,'source_thread',jsonb_build_object('firstCommunicationEventId',v_event.id)) on conflict (communication_thread_id) do nothing; end if;
  else
    update atlas.institutional_conversations set last_activity_at=greatest(last_activity_at,coalesce(v_event.occurred_at,v_event.captured_at)),updated_at=now() where id=v_conv_id;
    insert into atlas.institutional_conversation_endpoints(institutional_conversation_id,communication_endpoint_id,endpoint_role) values(v_conv_id,v_endpoint_id,'participant') on conflict do nothing;
  end if;

  insert into atlas.institutional_conversation_messages(institutional_conversation_id,communication_event_id,communication_endpoint_id,continuity_basis,occurred_at,metadata)
  values(v_conv_id,v_event.id,v_endpoint_id,case when v_event.thread_id is null then 'source_event' else 'source_thread' end,v_event.occurred_at,jsonb_build_object('connectedSourceId',v_event.connected_source_id,'sourceEventRef',v_event.source_event_ref)) on conflict (communication_event_id) do nothing;

  for v_rel in select distinct r.external_relationship_id from atlas.communication_participant_relationship_resolutions r where r.communication_event_id=v_event.id and r.external_relationship_id is not null loop
    insert into atlas.institutional_conversation_relationships(institutional_conversation_id,external_relationship_id,relationship_role) values(v_conv_id,v_rel,'external_party') on conflict do nothing;
  end loop;

  return jsonb_build_object('contractVersion','institutional_conversation_admission_v1','state','admitted','communicationEventId',v_event.id,'institutionalConversationId',v_conv_id,'communicationEndpointId',v_endpoint_id,'conversationCreated',v_created);
end;$function$;

create or replace function atlas.prepare_institutional_email_send_self_api_v1(
  p_communication_endpoint_id uuid,p_institutional_conversation_id uuid,p_to_recipients jsonb,p_cc_recipients jsonb default '[]'::jsonb,p_bcc_recipients jsonb default '[]'::jsonb,
  p_subject text default null,p_body_text text default null,p_body_html text default null,p_attachment_refs jsonb default '[]'::jsonb,p_reply_to_communication_event_id uuid default null,p_idempotency_key text default null
) returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth,extensions as $function$
declare v_endpoint atlas.communication_endpoints%rowtype; v_member atlas.organization_memberships%rowtype; v_conv atlas.institutional_conversations%rowtype; v_conv_id uuid:=p_institutional_conversation_id; v_source_id uuid; v_source_count int; v_case atlas.institutional_conversation_response_cases%rowtype; v_binding atlas.institutional_conversation_response_work_bindings%rowtype; v_current atlas.work_allocations%rowtype; v_operation_id uuid:=gen_random_uuid(); v_key text:=coalesce(nullif(btrim(p_idempotency_key),''),v_operation_id::text); v_hash text; v_stable text;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_endpoint from atlas.communication_endpoints where id=p_communication_endpoint_id and endpoint_state='active';
  if v_endpoint.id is null or v_endpoint.endpoint_kind<>'email' then raise exception 'Active email communication endpoint required.' using errcode='P0002'; end if;
  select * into v_member from atlas.organization_memberships where organization_id=v_endpoint.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'send') then raise exception 'Communication endpoint send authority required.' using errcode='42501'; end if;
  if jsonb_typeof(coalesce(p_to_recipients,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_to_recipients,'[]'::jsonb))<1 or jsonb_typeof(coalesce(p_cc_recipients,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(p_bcc_recipients,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(p_attachment_refs,'[]'::jsonb))<>'array' then raise exception 'Recipients/attachments must be JSON arrays and at least one To recipient is required.' using errcode='22023'; end if;
  select count(*),(array_agg(b.connected_source_id order by b.connected_source_id))[1] into v_source_count,v_source_id from atlas.communication_endpoint_source_bindings b join atlas.connected_sources s on s.id=b.connected_source_id where b.communication_endpoint_id=v_endpoint.id and b.binding_state='active' and b.binding_role in ('send','send_receive') and s.authorization_state='connected' and (s.capabilities @> '{"communicationSend":true}'::jsonb);
  if v_source_count<>1 then raise exception 'Exactly one connected send transport is required for this endpoint; found %.',v_source_count using errcode='55000'; end if;

  if v_conv_id is null then
    v_stable:='outbound-intent:'||v_operation_id::text;
    insert into atlas.institutional_conversations(organization_id,organization_unit_id,stable_key,subject,opened_at,last_activity_at,metadata) values(v_endpoint.organization_id,v_endpoint.organization_unit_id,v_stable,nullif(btrim(coalesce(p_subject,'')),''),now(),now(),jsonb_build_object('createdFromOutboundIntent',true,'initiatedByMembershipId',v_member.id)) returning id into v_conv_id;
    insert into atlas.institutional_conversation_endpoints(institutional_conversation_id,communication_endpoint_id,endpoint_role) values(v_conv_id,v_endpoint.id,'primary');
  else
    select * into v_conv from atlas.institutional_conversations where id=v_conv_id and organization_id=v_endpoint.organization_id and organization_unit_id is not distinct from v_endpoint.organization_unit_id and conversation_state='open';
    if v_conv.id is null then raise exception 'Institutional conversation is outside endpoint scope or not open.' using errcode='42501'; end if;
    if not exists(select 1 from atlas.institutional_conversation_endpoints ce where ce.institutional_conversation_id=v_conv_id and ce.communication_endpoint_id=v_endpoint.id) then raise exception 'Conversation is not associated with the sending endpoint.' using errcode='42501'; end if;
  end if;

  select * into v_case from atlas.institutional_conversation_response_cases where institutional_conversation_id=v_conv_id and case_state not in ('complete','informational') order by case_number desc limit 1;
  if v_case.id is not null then
    select * into v_binding from atlas.institutional_conversation_response_work_bindings where response_case_id=v_case.id;
    if v_binding.id is not null then select * into v_current from atlas.work_allocations where work_item_id=v_binding.work_item_id and allocation_role='responsible' and state='active' limit 1; end if;
    if v_current.id is not null and v_current.assignee_membership_id is distinct from v_member.id and not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'admin') then raise exception 'Another member currently owns this conversation response. Hand it off before sending.' using errcode='42501'; end if;
    if v_current.id is null and v_case.case_state='unclaimed' and not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'claim') then raise exception 'Claim authority is required to answer an unclaimed conversation.' using errcode='42501'; end if;
  end if;

  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('endpointId',v_endpoint.id,'conversationId',v_conv_id,'to',coalesce(p_to_recipients,'[]'::jsonb),'cc',coalesce(p_cc_recipients,'[]'::jsonb),'bcc',coalesce(p_bcc_recipients,'[]'::jsonb),'subject',p_subject,'bodyText',p_body_text,'bodyHtml',p_body_html,'attachments',coalesce(p_attachment_refs,'[]'::jsonb),'replyToCommunicationEventId',p_reply_to_communication_event_id)::text,'UTF8'),'sha256'),'hex');
  insert into atlas.communication_outbound_operations(id,organization_id,organization_unit_id,communication_endpoint_id,institutional_conversation_id,connected_source_id,initiated_by_membership_id,to_recipients,cc_recipients,bcc_recipients,subject,body_text,body_html,attachment_refs,reply_to_communication_event_id,idempotency_key,content_sha256,operation_state,metadata)
  values(v_operation_id,v_endpoint.organization_id,v_endpoint.organization_unit_id,v_endpoint.id,v_conv_id,v_source_id,v_member.id,coalesce(p_to_recipients,'[]'::jsonb),coalesce(p_cc_recipients,'[]'::jsonb),coalesce(p_bcc_recipients,'[]'::jsonb),p_subject,p_body_text,p_body_html,coalesce(p_attachment_refs,'[]'::jsonb),p_reply_to_communication_event_id,v_key,v_hash,'authorized',jsonb_build_object('authorizationSource','explicit_authenticated_send_command','actorUserId',auth.uid()))
  on conflict (organization_id,idempotency_key) do nothing;
  select id into strict v_operation_id from atlas.communication_outbound_operations where organization_id=v_endpoint.organization_id and idempotency_key=v_key;
  return jsonb_build_object('contractVersion','institutional_email_send_intent_v1','outboundOperationId',v_operation_id,'institutionalConversationId',v_conv_id,'communicationEndpointId',v_endpoint.id,'connectedSourceId',v_source_id,'operationState','authorized','initiatedByMembershipId',v_member.id,'contentSha256',v_hash);
end;$function$;

commit;