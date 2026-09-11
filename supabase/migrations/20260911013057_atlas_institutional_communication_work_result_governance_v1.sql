begin;

insert into atlas.work_result_contract_policies(contract_key,source_domain,acceptance_mode,active,description,metadata)
values(
  'institutional_communication_response_v1','communication','domain_adapter',true,
  'Institutional conversation response work completes only when the Communication domain records an explicit terminal response-state event and accepts that domain result as the governing completion evidence.',
  jsonb_build_object('communicationDoesNotEqualResponsibility',true,'readingDoesNotClaim',true,'terminalResponseEventRequired',true,'domainResultAutoAccepted',true)
)
on conflict (contract_key) do update set source_domain=excluded.source_domain,acceptance_mode=excluded.acceptance_mode,active=true,description=excluded.description,metadata=excluded.metadata,updated_at=now();

create or replace function atlas.guard_institutional_communication_response_work_contract_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
begin
  if new.source_object_type='institutional_conversation_response_case' then
    new.result_contract_key:='institutional_communication_response_v1';
    if new.operation_class is null then new.operation_class:='communication_response'; end if;
  end if;
  return new;
end;$function$;
drop trigger if exists institutional_communication_response_work_contract_v1 on atlas.work_items;
create trigger institutional_communication_response_work_contract_v1
before insert or update of source_object_type,source_object_id,result_contract_key on atlas.work_items
for each row execute function atlas.guard_institutional_communication_response_work_contract_v1();

update atlas.work_items w
set result_contract_key='institutional_communication_response_v1',updated_at=now()
where w.source_object_type='institutional_conversation_response_case'
  and w.result_contract_key is distinct from 'institutional_communication_response_v1';

create or replace function atlas.complete_institutional_communication_response_work_service_v1(p_work_item_id uuid,p_response_case_id uuid,p_actor_membership_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare
  v_work atlas.work_items%rowtype; v_case atlas.institutional_conversation_response_cases%rowtype; v_actor atlas.organization_memberships%rowtype; v_allocation atlas.work_allocations%rowtype; v_result atlas.work_execution_results%rowtype; v_result_id uuid; v_acceptance_id uuid; v_key text;
begin
  select * into v_work from atlas.work_items where id=p_work_item_id for update;
  select * into v_case from atlas.institutional_conversation_response_cases where id=p_response_case_id;
  select * into v_actor from atlas.organization_memberships where id=p_actor_membership_id and active;
  if v_work.id is null or v_case.id is null or v_actor.id is null then raise exception 'Communication response completion requires work, response case, and active actor.' using errcode='P0002'; end if;
  if v_work.organization_id is distinct from v_case.organization_id or v_actor.organization_id is distinct from v_work.organization_id or v_work.source_object_type is distinct from 'institutional_conversation_response_case' or v_work.source_object_id is distinct from v_case.id then raise exception 'Communication response completion scope mismatch.' using errcode='23514'; end if;
  if v_work.result_contract_key is distinct from 'institutional_communication_response_v1' then raise exception 'Communication response Work must use the institutional communication result contract.' using errcode='23514'; end if;
  if v_work.work_state='completed' then
    return jsonb_build_object('contractVersion','institutional_communication_response_completion_v1','state','already_completed','workItemId',v_work.id,'responseCaseId',v_case.id);
  end if;
  if v_work.work_state<>'open' then raise exception 'Only open communication response Work can complete.' using errcode='22023'; end if;
  select * into v_allocation from atlas.work_allocations where work_item_id=v_work.id and allocation_role='responsible' and state='active' order by allocated_at desc,id desc limit 1;
  if v_allocation.id is null then raise exception 'Communication response Work requires active responsibility before completion.' using errcode='23514'; end if;
  v_key:='institutional-communication-response:'||v_case.id::text||':complete';
  select * into v_result from atlas.work_execution_results where organization_id=v_work.organization_id and idempotency_key=v_key;
  if v_result.id is null then
    insert into atlas.work_execution_results(organization_id,work_item_id,responsible_allocation_id,reported_by_user_id,reported_by_organization_membership_id,result_kind,result_contract_key,idempotency_key,payload,metadata)
    values(v_work.organization_id,v_work.id,v_allocation.id,v_actor.user_id,v_actor.id,'completed','institutional_communication_response_v1',v_key,jsonb_build_object('responseCaseId',v_case.id,'institutionalConversationId',v_case.institutional_conversation_id,'terminalResponseState','complete','reason',nullif(btrim(coalesce(p_reason,'')),'')),jsonb_build_object('source','complete_institutional_communication_response_work_service_v1'))
    returning * into v_result;
  end if;
  v_result_id:=v_result.id;
  insert into atlas.work_result_acceptances(organization_id,work_item_id,execution_result_id,decision,acceptance_kind,accepted_by_domain,evidence,metadata)
  values(v_work.organization_id,v_work.id,v_result_id,'accepted','domain_adapter','communication',jsonb_build_object('responseCaseId',v_case.id,'terminalResponseState','complete'),jsonb_build_object('source','institutional_communication_response_v1'))
  on conflict (execution_result_id) do nothing;
  select id into v_acceptance_id from atlas.work_result_acceptances where execution_result_id=v_result_id;
  update atlas.work_allocations set state='completed',completed_at=now(),updated_at=now(),metadata=metadata||jsonb_build_object('completionResultId',v_result_id,'completionAcceptanceId',v_acceptance_id) where id=v_allocation.id and state='active';
  update atlas.work_items set work_state='completed',completed_at=now(),updated_at=now(),metadata=metadata||jsonb_build_object('completionResultId',v_result_id,'completionAcceptanceId',v_acceptance_id) where id=v_work.id and work_state='open';
  return jsonb_build_object('contractVersion','institutional_communication_response_completion_v1','state','completed','workItemId',v_work.id,'responseCaseId',v_case.id,'executionResultId',v_result_id,'acceptanceId',v_acceptance_id);
end;$function$;

create or replace function atlas.set_institutional_conversation_response_state_self_api_v1(p_institutional_conversation_id uuid,p_to_state text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_conv atlas.institutional_conversations%rowtype; v_case atlas.institutional_conversation_response_cases%rowtype; v_endpoint_id uuid; v_actor atlas.organization_memberships%rowtype; v_binding atlas.institutional_conversation_response_work_bindings%rowtype; v_current atlas.work_allocations%rowtype; v_to text:=lower(btrim(coalesce(p_to_state,''))); v_from text; v_completion jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if v_to not in ('needs_response','waiting_external','waiting_internal','scheduled_follow_up','complete','informational') then raise exception 'Unsupported response state.' using errcode='22023'; end if;
  select * into v_conv from atlas.institutional_conversations where id=p_institutional_conversation_id and conversation_state='open';
  if v_conv.id is null then raise exception 'Open institutional conversation not found.' using errcode='P0002'; end if;
  select communication_endpoint_id into v_endpoint_id from atlas.institutional_conversation_endpoints where institutional_conversation_id=v_conv.id order by case endpoint_role when 'primary' then 0 else 1 end,created_at limit 1;
  select * into v_actor from atlas.organization_memberships where organization_id=v_conv.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  select * into v_case from atlas.institutional_conversation_response_cases where institutional_conversation_id=v_conv.id and case_state not in ('complete','informational') order by case_number desc limit 1 for update;
  if v_case.id is null then raise exception 'No active response case exists.' using errcode='22023'; end if;
  select * into v_binding from atlas.institutional_conversation_response_work_bindings where response_case_id=v_case.id;
  if v_binding.id is not null then select * into v_current from atlas.work_allocations where work_item_id=v_binding.work_item_id and allocation_role='responsible' and state='active' limit 1; end if;
  if v_actor.id is null then raise exception 'Active organization membership required.' using errcode='42501'; end if;
  if v_to in ('complete','informational') then
    if (v_current.id is null or v_current.assignee_membership_id is distinct from v_actor.id) and not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_actor.id,'close') then raise exception 'Current responsibility or endpoint close authority required.' using errcode='42501'; end if;
  else
    if v_current.id is null or v_current.assignee_membership_id is distinct from v_actor.id then raise exception 'Current conversation responsibility required.' using errcode='42501'; end if;
  end if;
  v_from:=v_case.case_state;
  if v_binding.id is not null and v_to='complete' then
    v_completion:=atlas.complete_institutional_communication_response_work_service_v1(v_binding.work_item_id,v_case.id,v_actor.id,p_reason);
  elsif v_binding.id is not null and v_to='informational' then
    update atlas.work_allocations set state='released',released_at=now(),release_reason='communication_marked_informational',updated_at=now(),metadata=metadata||jsonb_build_object('responseCaseId',v_case.id) where work_item_id=v_binding.work_item_id and allocation_role='responsible' and state='active';
    update atlas.work_items set work_state='cancelled',cancelled_at=now(),updated_at=now(),metadata=metadata||jsonb_build_object('cancellationSource','institutional_communication_informational','responseCaseId',v_case.id) where id=v_binding.work_item_id and work_state='open';
  end if;
  update atlas.institutional_conversation_response_cases set case_state=v_to,closed_at=case when v_to in ('complete','informational') then now() else null end,updated_at=now() where id=v_case.id;
  insert into atlas.institutional_conversation_response_events(response_case_id,institutional_conversation_id,event_kind,from_state,to_state,actor_membership_id,target_membership_id,work_item_id,reason,metadata)
  values(v_case.id,v_conv.id,case when v_to='complete' then 'completed' when v_to='informational' then 'marked_informational' else 'state_changed' end,v_from,v_to,v_actor.id,case when v_current.id is null then null else v_current.assignee_membership_id end,v_binding.work_item_id,nullif(btrim(coalesce(p_reason,'')),''),jsonb_build_object('completion',coalesce(v_completion,'{}'::jsonb)));
  return jsonb_build_object('contractVersion','institutional_conversation_response_state_v2','institutionalConversationId',v_conv.id,'responseCaseId',v_case.id,'fromState',v_from,'toState',v_to,'responsibleMembershipId',case when v_to in ('complete','informational') then null else v_current.assignee_membership_id end,'completion',v_completion);
end;$function$;

revoke all on function atlas.guard_institutional_communication_response_work_contract_v1(),atlas.complete_institutional_communication_response_work_service_v1(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function atlas.guard_institutional_communication_response_work_contract_v1(),atlas.complete_institutional_communication_response_work_service_v1(uuid,uuid,uuid,text) to service_role;

commit;