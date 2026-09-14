create or replace function atlas.ensure_institutional_response_case_for_event_service_v1(p_communication_event_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_event atlas.communication_events%rowtype;
  v_msg atlas.institutional_conversation_messages%rowtype;
  v_case atlas.institutional_conversation_response_cases%rowtype;
  v_prior atlas.institutional_conversation_response_events%rowtype;
  v_num int;
  v_from text;
begin
  select * into v_event from atlas.communication_events where id=p_communication_event_id;
  select * into v_msg from atlas.institutional_conversation_messages where communication_event_id=p_communication_event_id;
  if v_event.id is null or v_msg.id is null then
    return jsonb_build_object('contractVersion','institutional_response_case_admission_v1','state','not_admitted','communicationEventId',p_communication_event_id);
  end if;
  if v_event.direction<>'incoming' then
    return jsonb_build_object('contractVersion','institutional_response_case_admission_v1','state','no_inbound_obligation_inferred','communicationEventId',p_communication_event_id,'institutionalConversationId',v_msg.institutional_conversation_id);
  end if;
  if not exists(select 1 from atlas.communication_event_participants p where p.communication_event_id=v_event.id and not p.is_self) then
    return jsonb_build_object('contractVersion','institutional_response_case_admission_v1','state','no_external_participant','communicationEventId',p_communication_event_id);
  end if;

  select * into v_prior
  from atlas.institutional_conversation_response_events
  where related_communication_event_id=p_communication_event_id
    and event_kind in ('opened','inbound_received')
  order by created_at,id
  limit 1;

  if v_prior.id is not null then
    select * into v_case
    from atlas.institutional_conversation_response_cases
    where id=v_prior.response_case_id;

    return jsonb_build_object(
      'contractVersion','institutional_response_case_admission_v1',
      'state','already_recorded',
      'communicationEventId',p_communication_event_id,
      'responseCaseId',v_prior.response_case_id,
      'institutionalConversationId',v_msg.institutional_conversation_id,
      'caseState',v_case.case_state
    );
  end if;

  select * into v_case
  from atlas.institutional_conversation_response_cases
  where institutional_conversation_id=v_msg.institutional_conversation_id
    and case_state not in ('complete','informational')
  order by case_number desc
  limit 1
  for update;

  if v_case.id is null then
    select coalesce(max(case_number),0)+1 into v_num
    from atlas.institutional_conversation_response_cases
    where institutional_conversation_id=v_msg.institutional_conversation_id;

    insert into atlas.institutional_conversation_response_cases(
      institutional_conversation_id,organization_id,organization_unit_id,case_number,case_state,
      opened_by_communication_event_id,opened_at,metadata
    )
    values(
      v_msg.institutional_conversation_id,v_event.organization_id,v_event.organization_unit_id,v_num,'unclaimed',
      v_event.id,coalesce(v_event.occurred_at,v_event.captured_at),jsonb_build_object('openingRule','incoming_institutional_communication')
    )
    returning * into v_case;

    insert into atlas.institutional_conversation_response_events(
      response_case_id,institutional_conversation_id,event_kind,from_state,to_state,
      related_communication_event_id,metadata,occurred_at
    )
    values(
      v_case.id,v_case.institutional_conversation_id,'opened',null,'unclaimed',
      v_event.id,jsonb_build_object('communicationDoesNotEqualResponsibility',true),coalesce(v_event.occurred_at,v_event.captured_at)
    );

    return jsonb_build_object(
      'contractVersion','institutional_response_case_admission_v1',
      'state','opened_unclaimed',
      'responseCaseId',v_case.id,
      'institutionalConversationId',v_case.institutional_conversation_id
    );
  end if;

  v_from:=v_case.case_state;
  if v_case.case_state='waiting_external' then
    update atlas.institutional_conversation_response_cases
    set case_state='needs_response',updated_at=now()
    where id=v_case.id
    returning * into v_case;

    insert into atlas.institutional_conversation_response_events(
      response_case_id,institutional_conversation_id,event_kind,from_state,to_state,work_item_id,
      related_communication_event_id,metadata,occurred_at
    )
    values(
      v_case.id,v_case.institutional_conversation_id,'inbound_received',v_from,'needs_response',
      (select work_item_id from atlas.institutional_conversation_response_work_bindings where response_case_id=v_case.id),
      v_event.id,'{}'::jsonb,coalesce(v_event.occurred_at,v_event.captured_at)
    );

    return jsonb_build_object(
      'contractVersion','institutional_response_case_admission_v1',
      'state','returned_to_needs_response',
      'responseCaseId',v_case.id
    );
  end if;

  insert into atlas.institutional_conversation_response_events(
    response_case_id,institutional_conversation_id,event_kind,from_state,to_state,work_item_id,
    related_communication_event_id,metadata,occurred_at
  )
  values(
    v_case.id,v_case.institutional_conversation_id,'inbound_received',v_case.case_state,v_case.case_state,
    (select work_item_id from atlas.institutional_conversation_response_work_bindings where response_case_id=v_case.id),
    v_event.id,'{}'::jsonb,coalesce(v_event.occurred_at,v_event.captured_at)
  );

  return jsonb_build_object(
    'contractVersion','institutional_response_case_admission_v1',
    'state','inbound_recorded',
    'responseCaseId',v_case.id,
    'caseState',v_case.case_state
  );
end;
$function$;

revoke all on function atlas.ensure_institutional_response_case_for_event_service_v1(uuid) from public, anon, authenticated;
grant execute on function atlas.ensure_institutional_response_case_for_event_service_v1(uuid) to service_role;