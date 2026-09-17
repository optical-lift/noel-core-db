begin;

-- Stage 2 source review correction.
-- Re-state the canonical Correspondence search with attachment presence derived
-- from actual attachment existence rather than aggregate-row existence.

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
      select string_agg(coalesce((
               select string_agg(coalesce(p.metadata->>'displayName','')||' '||p.address,' ')
               from atlas.communication_event_participants p
               where p.communication_event_id=e.id
             ),''),' ') as participant_text,
             string_agg(coalesce(e.body,''),' ') as body_text,
             string_agg(coalesce((
               select string_agg(coalesce(a.transfer_name,''),' ')
               from atlas.communication_attachments a
               where a.event_id=e.id
             ),''),' ') as attachment_text,
             bool_or(exists(
               select 1 from atlas.communication_attachments a where a.event_id=e.id
             )) as has_attachment
      from atlas.communication_conversation_events cce
      join atlas.communication_events e on e.id=cce.communication_event_id
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
'Searches visible Organization correspondence by common Communication Conversation identity. Attachment filtering reflects actual attachment evidence, not aggregate row shape.';

commit;
