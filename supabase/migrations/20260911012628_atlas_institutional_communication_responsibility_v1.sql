begin;

create or replace function atlas.communication_endpoint_membership_has_capability_v1(p_endpoint_id uuid,p_membership_id uuid,p_capability text)
returns boolean language sql stable security definer set search_path=pg_catalog,atlas as $function$
  select exists(
    select 1
    from atlas.communication_endpoints ep
    join atlas.organization_memberships om on om.id=p_membership_id and om.organization_id=ep.organization_id and om.active
    where ep.id=p_endpoint_id and ep.endpoint_state='active'
      and (om.role='owner' or exists(
        select 1 from atlas.communication_endpoint_member_grants g
        where g.communication_endpoint_id=ep.id and g.membership_id=om.id
          and g.capability in (lower(btrim(coalesce(p_capability,''))),'admin') and g.grant_state='active'
      ))
  );
$function$;

create table atlas.institutional_conversation_response_cases (
  id uuid primary key default gen_random_uuid(),
  institutional_conversation_id uuid not null references atlas.institutional_conversations(id) on delete cascade,
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid,
  case_number integer not null check (case_number>0),
  case_state text not null check (case_state in ('unclaimed','needs_response','waiting_external','waiting_internal','scheduled_follow_up','complete','informational')),
  opened_by_communication_event_id uuid references atlas.communication_events(id) on delete restrict,
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(institutional_conversation_id,case_number),
  foreign key (organization_id,organization_unit_id) references atlas.organization_units(organization_id,id) on delete restrict,
  check (closed_at is null or case_state in ('complete','informational'))
);
create unique index institutional_conversation_one_active_response_case_uq on atlas.institutional_conversation_response_cases(institutional_conversation_id) where case_state not in ('complete','informational');
create index institutional_response_cases_org_state_idx on atlas.institutional_conversation_response_cases(organization_id,organization_unit_id,case_state,updated_at desc,id);
comment on table atlas.institutional_conversation_response_cases is 'A bounded unresolved-response episode inside a durable Institutional Conversation. Unclaimed is institutional triage state, not human assignment and not Company Work. Claiming establishes Company Work responsibility.';

create table atlas.institutional_conversation_response_events (
  id uuid primary key default gen_random_uuid(),
  response_case_id uuid not null references atlas.institutional_conversation_response_cases(id) on delete cascade,
  institutional_conversation_id uuid not null references atlas.institutional_conversations(id) on delete cascade,
  event_kind text not null check (event_kind in ('opened','inbound_received','claimed','handed_off','state_changed','outbound_sent','reopened','completed','marked_informational')),
  from_state text,
  to_state text not null check (to_state in ('unclaimed','needs_response','waiting_external','waiting_internal','scheduled_follow_up','complete','informational')),
  actor_membership_id uuid references atlas.organization_memberships(id) on delete set null,
  target_membership_id uuid references atlas.organization_memberships(id) on delete set null,
  work_item_id uuid references atlas.work_items(id) on delete set null,
  related_communication_event_id uuid references atlas.communication_events(id) on delete set null,
  reason text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index institutional_response_events_case_idx on atlas.institutional_conversation_response_events(response_case_id,occurred_at,id);
comment on table atlas.institutional_conversation_response_events is 'Append-only response-state and responsibility-transition evidence. Reading a message is never a claim; human responsibility changes only through explicit governed transitions.';

create table atlas.institutional_conversation_response_work_bindings (
  id uuid primary key default gen_random_uuid(),
  response_case_id uuid not null unique references atlas.institutional_conversation_response_cases(id) on delete cascade,
  work_item_id uuid not null unique references atlas.work_items(id) on delete restrict,
  created_at timestamptz not null default now()
);
comment on table atlas.institutional_conversation_response_work_bindings is 'Bridge from a claimed institutional response case to ordinary Company Work. Conversation response does not invent an email-specific assignee system.';

create table atlas.communication_attention_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  institutional_conversation_id uuid not null references atlas.institutional_conversations(id) on delete cascade,
  communication_event_id uuid not null references atlas.communication_events(id) on delete restrict,
  membership_id uuid not null references atlas.organization_memberships(id) on delete cascade,
  attention_kind text not null check (attention_kind in ('previewed','opened','marked_read','marked_unread')),
  client_event_key text not null check (btrim(client_event_key)<>''),
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique(membership_id,communication_event_id,attention_kind,client_event_key)
);
create index communication_attention_event_idx on atlas.communication_attention_events(communication_event_id,attention_kind,occurred_at,id);
create index communication_attention_member_idx on atlas.communication_attention_events(membership_id,institutional_conversation_id,occurred_at desc,id);
comment on table atlas.communication_attention_events is 'Per-human Atlas attention evidence for institution-owned communication. This is distinct from provider IMAP Seen state and from response responsibility. Opening/reading never claims a conversation.';

create or replace function atlas.prevent_institutional_response_history_mutation_v1() returns trigger language plpgsql set search_path=pg_catalog,atlas as $function$
begin raise exception 'Institutional communication response/attention history is append-only.' using errcode='55000'; end;$function$;
create trigger institutional_response_events_append_only_v1 before update or delete on atlas.institutional_conversation_response_events for each row execute function atlas.prevent_institutional_response_history_mutation_v1();
create trigger institutional_response_work_binding_append_only_v1 before update or delete on atlas.institutional_conversation_response_work_bindings for each row execute function atlas.prevent_institutional_response_history_mutation_v1();
create trigger communication_attention_events_append_only_v1 before update or delete on atlas.communication_attention_events for each row execute function atlas.prevent_institutional_response_history_mutation_v1();

create or replace function atlas.guard_institutional_response_case_v1() returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_conv atlas.institutional_conversations%rowtype; v_event atlas.communication_events%rowtype;
begin
  select * into v_conv from atlas.institutional_conversations where id=new.institutional_conversation_id;
  if v_conv.id is null or v_conv.organization_id is distinct from new.organization_id or v_conv.organization_unit_id is distinct from new.organization_unit_id then raise exception 'Response case must share conversation organization/unit scope.' using errcode='23514'; end if;
  if new.opened_by_communication_event_id is not null then
    select * into v_event from atlas.communication_events where id=new.opened_by_communication_event_id;
    if v_event.id is null or v_event.organization_id is distinct from new.organization_id or v_event.organization_unit_id is distinct from new.organization_unit_id then raise exception 'Response-case opening event must share institutional scope.' using errcode='23514'; end if;
  end if;
  new.updated_at:=now();
  return new;
end;$function$;
create trigger institutional_response_case_guard_v1 before insert or update on atlas.institutional_conversation_response_cases for each row execute function atlas.guard_institutional_response_case_v1();

create or replace function atlas.guard_institutional_response_event_v1() returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_case atlas.institutional_conversation_response_cases%rowtype; v_actor atlas.organization_memberships%rowtype; v_target atlas.organization_memberships%rowtype; v_work atlas.work_items%rowtype;
begin
  select * into v_case from atlas.institutional_conversation_response_cases where id=new.response_case_id;
  if v_case.id is null or v_case.institutional_conversation_id is distinct from new.institutional_conversation_id then raise exception 'Response event must belong to its response case/conversation.' using errcode='23514'; end if;
  if new.actor_membership_id is not null then select * into v_actor from atlas.organization_memberships where id=new.actor_membership_id; if v_actor.id is null or v_actor.organization_id is distinct from v_case.organization_id then raise exception 'Response actor is outside organization.' using errcode='23514'; end if; end if;
  if new.target_membership_id is not null then select * into v_target from atlas.organization_memberships where id=new.target_membership_id; if v_target.id is null or v_target.organization_id is distinct from v_case.organization_id then raise exception 'Response target is outside organization.' using errcode='23514'; end if; end if;
  if new.work_item_id is not null then select * into v_work from atlas.work_items where id=new.work_item_id; if v_work.id is null or v_work.organization_id is distinct from v_case.organization_id then raise exception 'Response Work is outside organization.' using errcode='23514'; end if; end if;
  return new;
end;$function$;
create trigger institutional_response_event_guard_v1 before insert on atlas.institutional_conversation_response_events for each row execute function atlas.guard_institutional_response_event_v1();

create or replace function atlas.guard_institutional_response_work_binding_v1() returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_case atlas.institutional_conversation_response_cases%rowtype; v_work atlas.work_items%rowtype;
begin
  select * into v_case from atlas.institutional_conversation_response_cases where id=new.response_case_id;
  select * into v_work from atlas.work_items where id=new.work_item_id;
  if v_case.id is null or v_work.id is null or v_work.organization_id is distinct from v_case.organization_id or v_work.organization_unit_id is distinct from v_case.organization_unit_id then raise exception 'Response Work binding must share organization/unit scope.' using errcode='23514'; end if;
  if v_work.source_object_type is distinct from 'institutional_conversation_response_case' or v_work.source_object_id is distinct from v_case.id then raise exception 'Response Work must identify the response case as its source object.' using errcode='23514'; end if;
  return new;
end;$function$;
create trigger institutional_response_work_binding_guard_v1 before insert on atlas.institutional_conversation_response_work_bindings for each row execute function atlas.guard_institutional_response_work_binding_v1();

create or replace function atlas.guard_communication_attention_event_v1() returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_msg atlas.institutional_conversation_messages%rowtype; v_member atlas.organization_memberships%rowtype; v_conv atlas.institutional_conversations%rowtype;
begin
  select * into v_msg from atlas.institutional_conversation_messages where communication_event_id=new.communication_event_id;
  select * into v_conv from atlas.institutional_conversations where id=new.institutional_conversation_id;
  select * into v_member from atlas.organization_memberships where id=new.membership_id;
  if v_msg.id is null or v_conv.id is null or v_member.id is null then raise exception 'Attention evidence requires an institutional message, conversation, and membership.' using errcode='23514'; end if;
  if v_msg.institutional_conversation_id is distinct from new.institutional_conversation_id or v_conv.organization_id is distinct from new.organization_id or v_member.organization_id is distinct from new.organization_id then raise exception 'Attention evidence must share organization/conversation scope.' using errcode='23514'; end if;
  return new;
end;$function$;
create trigger communication_attention_event_guard_v1 before insert on atlas.communication_attention_events for each row execute function atlas.guard_communication_attention_event_v1();

create or replace function atlas.ensure_institutional_response_case_for_event_service_v1(p_communication_event_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_event atlas.communication_events%rowtype; v_msg atlas.institutional_conversation_messages%rowtype; v_case atlas.institutional_conversation_response_cases%rowtype; v_num int; v_from text;
begin
  select * into v_event from atlas.communication_events where id=p_communication_event_id;
  select * into v_msg from atlas.institutional_conversation_messages where communication_event_id=p_communication_event_id;
  if v_event.id is null or v_msg.id is null then return jsonb_build_object('contractVersion','institutional_response_case_admission_v1','state','not_admitted','communicationEventId',p_communication_event_id); end if;
  if v_event.direction<>'incoming' then return jsonb_build_object('contractVersion','institutional_response_case_admission_v1','state','no_inbound_obligation_inferred','communicationEventId',p_communication_event_id,'institutionalConversationId',v_msg.institutional_conversation_id); end if;
  if not exists(select 1 from atlas.communication_event_participants p where p.communication_event_id=v_event.id and not p.is_self) then return jsonb_build_object('contractVersion','institutional_response_case_admission_v1','state','no_external_participant','communicationEventId',p_communication_event_id); end if;

  select * into v_case from atlas.institutional_conversation_response_cases where institutional_conversation_id=v_msg.institutional_conversation_id and case_state not in ('complete','informational') order by case_number desc limit 1 for update;
  if v_case.id is null then
    select coalesce(max(case_number),0)+1 into v_num from atlas.institutional_conversation_response_cases where institutional_conversation_id=v_msg.institutional_conversation_id;
    insert into atlas.institutional_conversation_response_cases(institutional_conversation_id,organization_id,organization_unit_id,case_number,case_state,opened_by_communication_event_id,opened_at,metadata)
    values(v_msg.institutional_conversation_id,v_event.organization_id,v_event.organization_unit_id,v_num,'unclaimed',v_event.id,coalesce(v_event.occurred_at,v_event.captured_at),jsonb_build_object('openingRule','incoming_institutional_communication')) returning * into v_case;
    insert into atlas.institutional_conversation_response_events(response_case_id,institutional_conversation_id,event_kind,from_state,to_state,related_communication_event_id,metadata,occurred_at)
    values(v_case.id,v_case.institutional_conversation_id,'opened',null,'unclaimed',v_event.id,jsonb_build_object('communicationDoesNotEqualResponsibility',true),coalesce(v_event.occurred_at,v_event.captured_at));
    return jsonb_build_object('contractVersion','institutional_response_case_admission_v1','state','opened_unclaimed','responseCaseId',v_case.id,'institutionalConversationId',v_case.institutional_conversation_id);
  end if;

  v_from:=v_case.case_state;
  if v_case.case_state='waiting_external' then
    update atlas.institutional_conversation_response_cases set case_state='needs_response',updated_at=now() where id=v_case.id returning * into v_case;
    insert into atlas.institutional_conversation_response_events(response_case_id,institutional_conversation_id,event_kind,from_state,to_state,work_item_id,related_communication_event_id,metadata,occurred_at)
    values(v_case.id,v_case.institutional_conversation_id,'inbound_received',v_from,'needs_response',(select work_item_id from atlas.institutional_conversation_response_work_bindings where response_case_id=v_case.id),v_event.id,'{}'::jsonb,coalesce(v_event.occurred_at,v_event.captured_at));
    return jsonb_build_object('contractVersion','institutional_response_case_admission_v1','state','returned_to_needs_response','responseCaseId',v_case.id);
  end if;

  insert into atlas.institutional_conversation_response_events(response_case_id,institutional_conversation_id,event_kind,from_state,to_state,work_item_id,related_communication_event_id,metadata,occurred_at)
  values(v_case.id,v_case.institutional_conversation_id,'inbound_received',v_case.case_state,v_case.case_state,(select work_item_id from atlas.institutional_conversation_response_work_bindings where response_case_id=v_case.id),v_event.id,'{}'::jsonb,coalesce(v_event.occurred_at,v_event.captured_at));
  return jsonb_build_object('contractVersion','institutional_response_case_admission_v1','state','inbound_recorded','responseCaseId',v_case.id,'caseState',v_case.case_state);
end;$function$;

create or replace function atlas.ingest_organization_communication_events_service_v3(p_connected_source_id uuid,p_events jsonb,p_manifest jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_receipt jsonb; v_batch_id uuid; v_event_id uuid; v_result jsonb; v_cases int:=0;
begin
  v_receipt:=atlas.ingest_organization_communication_events_service_v2(p_connected_source_id,p_events,p_manifest);
  v_batch_id:=(v_receipt->>'batchId')::uuid;
  for v_event_id in select id from atlas.communication_events where ingest_batch_id=v_batch_id order by created_at,id loop
    v_result:=atlas.ensure_institutional_response_case_for_event_service_v1(v_event_id);
    if v_result->>'state' in ('opened_unclaimed','returned_to_needs_response','inbound_recorded') then v_cases:=v_cases+1; end if;
  end loop;
  return v_receipt||jsonb_build_object('responseCasesTouched',v_cases,'contractVersion','organization_communication_ingest_receipt_v3');
end;$function$;

create or replace function atlas.record_communication_attention_self_api_v1(p_communication_event_id uuid,p_attention_kind text default 'opened',p_client_event_key text default null,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_msg atlas.institutional_conversation_messages%rowtype; v_event atlas.communication_events%rowtype; v_endpoint_id uuid; v_member atlas.organization_memberships%rowtype; v_kind text:=lower(btrim(coalesce(p_attention_kind,''))); v_key text:=coalesce(nullif(btrim(p_client_event_key),''),gen_random_uuid()::text); v_first atlas.communication_attention_events%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if v_kind not in ('previewed','opened','marked_read','marked_unread') then raise exception 'Unsupported communication attention event.' using errcode='22023'; end if;
  select * into v_msg from atlas.institutional_conversation_messages where communication_event_id=p_communication_event_id;
  select * into v_event from atlas.communication_events where id=p_communication_event_id;
  if v_msg.id is null or v_event.id is null then raise exception 'Institutional communication message not found.' using errcode='P0002'; end if;
  select communication_endpoint_id into v_endpoint_id from atlas.institutional_conversation_messages where communication_event_id=p_communication_event_id;
  select * into v_member from atlas.organization_memberships where organization_id=v_event.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_member.id,'view') then raise exception 'Communication endpoint view authority required.' using errcode='42501'; end if;
  insert into atlas.communication_attention_events(organization_id,institutional_conversation_id,communication_event_id,membership_id,attention_kind,client_event_key,metadata)
  values(v_event.organization_id,v_msg.institutional_conversation_id,v_event.id,v_member.id,v_kind,v_key,coalesce(p_metadata,'{}'::jsonb)) on conflict do nothing;
  select * into v_first from atlas.communication_attention_events where communication_event_id=v_event.id and attention_kind='opened' order by occurred_at,id limit 1;
  return jsonb_build_object('contractVersion','communication_attention_v1','communicationEventId',v_event.id,'institutionalConversationId',v_msg.institutional_conversation_id,'membershipId',v_member.id,'attentionKind',v_kind,'firstOpenedAt',v_first.occurred_at,'firstOpenedByMembershipId',v_first.membership_id,'readingClaimsResponsibility',false);
end;$function$;

create or replace function atlas.claim_institutional_conversation_self_api_v1(p_institutional_conversation_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_conv atlas.institutional_conversations%rowtype; v_case atlas.institutional_conversation_response_cases%rowtype; v_endpoint_id uuid; v_member atlas.organization_memberships%rowtype; v_binding atlas.institutional_conversation_response_work_bindings%rowtype; v_work_id uuid; v_assignment jsonb; v_from text;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_conv from atlas.institutional_conversations where id=p_institutional_conversation_id and conversation_state='open';
  if v_conv.id is null then raise exception 'Open institutional conversation not found.' using errcode='P0002'; end if;
  select communication_endpoint_id into v_endpoint_id from atlas.institutional_conversation_endpoints where institutional_conversation_id=v_conv.id order by case endpoint_role when 'primary' then 0 else 1 end,created_at limit 1;
  select * into v_member from atlas.organization_memberships where organization_id=v_conv.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_member.id,'claim') then raise exception 'Communication claim authority required.' using errcode='42501'; end if;
  select * into v_case from atlas.institutional_conversation_response_cases where institutional_conversation_id=v_conv.id and case_state not in ('complete','informational') order by case_number desc limit 1 for update;
  if v_case.id is null then raise exception 'This conversation has no active response case to claim.' using errcode='22023'; end if;
  select * into v_binding from atlas.institutional_conversation_response_work_bindings where response_case_id=v_case.id;
  if v_binding.id is null then
    insert into atlas.work_items(organization_id,organization_unit_id,title,instructions,work_state,operation_class,jurisdiction_key,source_object_type,source_object_id,stable_key,metadata)
    values(v_conv.organization_id,v_conv.organization_unit_id,'Respond: '||coalesce(nullif(v_conv.subject,''),'institutional conversation'),'Handle the unresolved communication consequence for this institutional conversation. Reading alone never establishes responsibility.','open','communication_response','communication:endpoint:'||v_endpoint_id::text,'institutional_conversation_response_case',v_case.id,'communication-response:'||v_case.id::text,jsonb_build_object('institutionalConversationId',v_conv.id,'communicationEndpointId',v_endpoint_id)) returning id into v_work_id;
    insert into atlas.institutional_conversation_response_work_bindings(response_case_id,work_item_id) values(v_case.id,v_work_id) returning * into v_binding;
  else v_work_id:=v_binding.work_item_id; end if;
  v_assignment:=atlas.set_company_work_responsibility_internal_v1(v_work_id,v_member.id,v_member.id,coalesce(nullif(btrim(p_reason),''),'conversation_claimed'),jsonb_build_object('source','claim_institutional_conversation_self_api_v1','institutionalConversationId',v_conv.id,'responseCaseId',v_case.id));
  v_from:=v_case.case_state;
  update atlas.institutional_conversation_response_cases set case_state='needs_response',updated_at=now() where id=v_case.id;
  insert into atlas.institutional_conversation_response_events(response_case_id,institutional_conversation_id,event_kind,from_state,to_state,actor_membership_id,target_membership_id,work_item_id,reason,metadata)
  values(v_case.id,v_conv.id,'claimed',v_from,'needs_response',v_member.id,v_member.id,v_work_id,nullif(btrim(coalesce(p_reason,'')),''),jsonb_build_object('assignment',v_assignment));
  return jsonb_build_object('contractVersion','institutional_conversation_claim_v1','institutionalConversationId',v_conv.id,'responseCaseId',v_case.id,'workItemId',v_work_id,'responsibleMembershipId',v_member.id,'responseState','needs_response');
end;$function$;

create or replace function atlas.handoff_institutional_conversation_self_api_v1(p_institutional_conversation_id uuid,p_target_membership_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_conv atlas.institutional_conversations%rowtype; v_case atlas.institutional_conversation_response_cases%rowtype; v_endpoint_id uuid; v_actor atlas.organization_memberships%rowtype; v_binding atlas.institutional_conversation_response_work_bindings%rowtype; v_current atlas.work_allocations%rowtype; v_assignment jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_conv from atlas.institutional_conversations where id=p_institutional_conversation_id and conversation_state='open';
  if v_conv.id is null then raise exception 'Open institutional conversation not found.' using errcode='P0002'; end if;
  select communication_endpoint_id into v_endpoint_id from atlas.institutional_conversation_endpoints where institutional_conversation_id=v_conv.id order by case endpoint_role when 'primary' then 0 else 1 end,created_at limit 1;
  select * into v_actor from atlas.organization_memberships where organization_id=v_conv.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  select * into v_case from atlas.institutional_conversation_response_cases where institutional_conversation_id=v_conv.id and case_state not in ('complete','informational') order by case_number desc limit 1;
  select * into v_binding from atlas.institutional_conversation_response_work_bindings where response_case_id=v_case.id;
  if v_binding.id is null then raise exception 'Conversation must be claimed before it can be handed off.' using errcode='22023'; end if;
  select * into v_current from atlas.work_allocations where work_item_id=v_binding.work_item_id and allocation_role='responsible' and state='active' limit 1;
  if v_actor.id is null or (v_current.assignee_membership_id is distinct from v_actor.id and not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_actor.id,'handoff')) then raise exception 'Current responsibility or endpoint handoff authority required.' using errcode='42501'; end if;
  if not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,p_target_membership_id,'claim') then raise exception 'Target member must be active and authorized to claim this endpoint.' using errcode='42501'; end if;
  v_assignment:=atlas.set_company_work_responsibility_internal_v1(v_binding.work_item_id,p_target_membership_id,v_actor.id,coalesce(nullif(btrim(p_reason),''),'conversation_handoff'),jsonb_build_object('source','handoff_institutional_conversation_self_api_v1','institutionalConversationId',v_conv.id,'responseCaseId',v_case.id));
  update atlas.institutional_conversation_response_cases set case_state='needs_response',updated_at=now() where id=v_case.id;
  insert into atlas.institutional_conversation_response_events(response_case_id,institutional_conversation_id,event_kind,from_state,to_state,actor_membership_id,target_membership_id,work_item_id,reason,metadata)
  values(v_case.id,v_conv.id,'handed_off',v_case.case_state,'needs_response',v_actor.id,p_target_membership_id,v_binding.work_item_id,nullif(btrim(coalesce(p_reason,'')),''),jsonb_build_object('assignment',v_assignment));
  return jsonb_build_object('contractVersion','institutional_conversation_handoff_v1','institutionalConversationId',v_conv.id,'responseCaseId',v_case.id,'workItemId',v_binding.work_item_id,'fromMembershipId',v_current.assignee_membership_id,'toMembershipId',p_target_membership_id,'responseState','needs_response');
end;$function$;

create or replace function atlas.set_institutional_conversation_response_state_self_api_v1(p_institutional_conversation_id uuid,p_to_state text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_conv atlas.institutional_conversations%rowtype; v_case atlas.institutional_conversation_response_cases%rowtype; v_endpoint_id uuid; v_actor atlas.organization_memberships%rowtype; v_binding atlas.institutional_conversation_response_work_bindings%rowtype; v_current atlas.work_allocations%rowtype; v_to text:=lower(btrim(coalesce(p_to_state,''))); v_from text;
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
  update atlas.institutional_conversation_response_cases set case_state=v_to,closed_at=case when v_to in ('complete','informational') then now() else null end,updated_at=now() where id=v_case.id;
  if v_binding.id is not null and v_to='complete' then
    update atlas.work_allocations set state='completed',completed_at=now(),updated_at=now(),metadata=metadata||jsonb_build_object('completionSource','institutional_communication_response','responseCaseId',v_case.id) where work_item_id=v_binding.work_item_id and allocation_role='responsible' and state='active';
    update atlas.work_items set work_state='completed',completed_at=now(),updated_at=now(),metadata=metadata||jsonb_build_object('completionSource','institutional_communication_response','responseCaseId',v_case.id) where id=v_binding.work_item_id and work_state='open';
  elsif v_binding.id is not null and v_to='informational' then
    update atlas.work_allocations set state='released',released_at=now(),release_reason='communication_marked_informational',updated_at=now() where work_item_id=v_binding.work_item_id and allocation_role='responsible' and state='active';
    update atlas.work_items set work_state='cancelled',cancelled_at=now(),updated_at=now(),metadata=metadata||jsonb_build_object('cancellationSource','institutional_communication_informational','responseCaseId',v_case.id) where id=v_binding.work_item_id and work_state='open';
  end if;
  insert into atlas.institutional_conversation_response_events(response_case_id,institutional_conversation_id,event_kind,from_state,to_state,actor_membership_id,target_membership_id,work_item_id,reason,metadata)
  values(v_case.id,v_conv.id,case when v_to='complete' then 'completed' when v_to='informational' then 'marked_informational' else 'state_changed' end,v_from,v_to,v_actor.id,case when v_current.id is null then null else v_current.assignee_membership_id end,v_binding.work_item_id,nullif(btrim(coalesce(p_reason,'')),''),'{}'::jsonb);
  return jsonb_build_object('contractVersion','institutional_conversation_response_state_v1','institutionalConversationId',v_conv.id,'responseCaseId',v_case.id,'fromState',v_from,'toState',v_to,'responsibleMembershipId',case when v_to in ('complete','informational') then null else v_current.assignee_membership_id end);
end;$function$;

create or replace view atlas.v_institutional_shared_inbox_v1 as
select
  c.organization_id,c.organization_unit_id,c.id as institutional_conversation_id,c.subject,c.conversation_state,c.opened_at,c.last_activity_at,
  ep.id as communication_endpoint_id,ep.endpoint_kind,ep.address as endpoint_address,ep.display_name as endpoint_display_name,
  rc.id as response_case_id,rc.case_number,rc.case_state as response_state,rc.opened_at as response_opened_at,
  wb.work_item_id,wa.assignee_membership_id as responsible_membership_id,
  lm.communication_event_id as last_message_event_id,e.direction as last_message_direction,e.occurred_at as last_message_at,e.body as last_message_body,
  fo.membership_id as first_opened_by_membership_id,fo.occurred_at as first_opened_at
from atlas.institutional_conversations c
left join lateral (select ce.communication_endpoint_id from atlas.institutional_conversation_endpoints ce where ce.institutional_conversation_id=c.id order by case ce.endpoint_role when 'primary' then 0 else 1 end,ce.created_at limit 1) cep on true
left join atlas.communication_endpoints ep on ep.id=cep.communication_endpoint_id
left join lateral (select r.* from atlas.institutional_conversation_response_cases r where r.institutional_conversation_id=c.id order by r.case_number desc limit 1) rc on true
left join atlas.institutional_conversation_response_work_bindings wb on wb.response_case_id=rc.id
left join lateral (select a.* from atlas.work_allocations a where a.work_item_id=wb.work_item_id and a.allocation_role='responsible' and a.state='active' order by a.allocated_at desc,a.id desc limit 1) wa on true
left join lateral (select m.* from atlas.institutional_conversation_messages m where m.institutional_conversation_id=c.id order by m.occurred_at desc nulls last,m.created_at desc,m.id desc limit 1) lm on true
left join atlas.communication_events e on e.id=lm.communication_event_id
left join lateral (select a.membership_id,a.occurred_at from atlas.communication_attention_events a where a.communication_event_id=lm.communication_event_id and a.attention_kind='opened' order by a.occurred_at,a.id limit 1) fo on true;
comment on view atlas.v_institutional_shared_inbox_v1 is 'Institutional shared-inbox projection separating message receipt, first human open, current response state, and current Company Work responsibility.';

create or replace function atlas.institutional_shared_inbox_self_v1(p_communication_endpoint_id uuid,p_limit integer default 200)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_member atlas.organization_memberships%rowtype; v_endpoint atlas.communication_endpoints%rowtype; v_items jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_limit<1 or p_limit>1000 then raise exception 'Limit must be between 1 and 1000.' using errcode='22023'; end if;
  select * into v_endpoint from atlas.communication_endpoints where id=p_communication_endpoint_id;
  if v_endpoint.id is null then raise exception 'Communication endpoint not found.' using errcode='P0002'; end if;
  select * into v_member from atlas.organization_memberships where organization_id=v_endpoint.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'view') then raise exception 'Communication endpoint view authority required.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.last_activity_at desc,x.institutional_conversation_id),'[]'::jsonb) into v_items from (
    select v.*,
      exists(select 1 from atlas.communication_attention_events a where a.communication_event_id=v.last_message_event_id and a.membership_id=v_member.id and a.attention_kind in ('opened','marked_read')) as last_message_opened_by_me
    from atlas.v_institutional_shared_inbox_v1 v where v.communication_endpoint_id=v_endpoint.id order by v.last_activity_at desc limit p_limit
  ) x;
  return jsonb_build_object('contractVersion','institutional_shared_inbox_v1','communicationEndpointId',v_endpoint.id,'membershipId',v_member.id,'items',v_items);
end;$function$;

create or replace function atlas.institutional_conversation_detail_self_v1(p_institutional_conversation_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_conv atlas.institutional_conversations%rowtype; v_endpoint_id uuid; v_member atlas.organization_memberships%rowtype; v_messages jsonb; v_response jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_conv from atlas.institutional_conversations where id=p_institutional_conversation_id;
  if v_conv.id is null then raise exception 'Institutional conversation not found.' using errcode='P0002'; end if;
  select communication_endpoint_id into v_endpoint_id from atlas.institutional_conversation_endpoints where institutional_conversation_id=v_conv.id order by case endpoint_role when 'primary' then 0 else 1 end,created_at limit 1;
  select * into v_member from atlas.organization_memberships where organization_id=v_conv.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_member.id,'view') then raise exception 'Communication endpoint view authority required.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.occurred_at,x.communication_event_id),'[]'::jsonb) into v_messages from (
    select e.id as communication_event_id,e.occurred_at,e.direction,e.speaker_address,e.body,e.body_state,e.canonical_event,
      (select min(a.occurred_at) from atlas.communication_attention_events a where a.communication_event_id=e.id and a.attention_kind='opened') as first_opened_at,
      (select a.membership_id from atlas.communication_attention_events a where a.communication_event_id=e.id and a.attention_kind='opened' order by a.occurred_at,a.id limit 1) as first_opened_by_membership_id,
      exists(select 1 from atlas.communication_attention_events a where a.communication_event_id=e.id and a.membership_id=v_member.id and a.attention_kind in ('opened','marked_read')) as opened_by_me
    from atlas.institutional_conversation_messages m join atlas.communication_events e on e.id=m.communication_event_id
    where m.institutional_conversation_id=v_conv.id
  ) x;
  select to_jsonb(r) into v_response from atlas.v_institutional_shared_inbox_v1 r where r.institutional_conversation_id=v_conv.id;
  return jsonb_build_object('contractVersion','institutional_conversation_detail_v1','conversation',jsonb_build_object('id',v_conv.id,'subject',v_conv.subject,'state',v_conv.conversation_state,'endpointId',v_endpoint_id),'response',coalesce(v_response,'{}'::jsonb),'messages',v_messages,'membershipId',v_member.id);
end;$function$;

alter table atlas.institutional_conversation_response_cases enable row level security;
alter table atlas.institutional_conversation_response_events enable row level security;
alter table atlas.institutional_conversation_response_work_bindings enable row level security;
alter table atlas.communication_attention_events enable row level security;
revoke all on atlas.institutional_conversation_response_cases,atlas.institutional_conversation_response_events,atlas.institutional_conversation_response_work_bindings,atlas.communication_attention_events,atlas.v_institutional_shared_inbox_v1 from public,anon,authenticated;
grant all on atlas.institutional_conversation_response_cases,atlas.institutional_conversation_response_events,atlas.institutional_conversation_response_work_bindings,atlas.communication_attention_events to service_role;
grant select on atlas.v_institutional_shared_inbox_v1 to service_role;

revoke all on function atlas.communication_endpoint_membership_has_capability_v1(uuid,uuid,text),atlas.prevent_institutional_response_history_mutation_v1(),atlas.guard_institutional_response_case_v1(),atlas.guard_institutional_response_event_v1(),atlas.guard_institutional_response_work_binding_v1(),atlas.guard_communication_attention_event_v1(),atlas.ensure_institutional_response_case_for_event_service_v1(uuid),atlas.ingest_organization_communication_events_service_v3(uuid,jsonb,jsonb) from public,anon,authenticated;
grant execute on function atlas.communication_endpoint_membership_has_capability_v1(uuid,uuid,text),atlas.prevent_institutional_response_history_mutation_v1(),atlas.guard_institutional_response_case_v1(),atlas.guard_institutional_response_event_v1(),atlas.guard_institutional_response_work_binding_v1(),atlas.guard_communication_attention_event_v1(),atlas.ensure_institutional_response_case_for_event_service_v1(uuid),atlas.ingest_organization_communication_events_service_v3(uuid,jsonb,jsonb) to service_role;
revoke all on function atlas.record_communication_attention_self_api_v1(uuid,text,text,jsonb),atlas.claim_institutional_conversation_self_api_v1(uuid,text),atlas.handoff_institutional_conversation_self_api_v1(uuid,uuid,text),atlas.set_institutional_conversation_response_state_self_api_v1(uuid,text,text),atlas.institutional_shared_inbox_self_v1(uuid,integer),atlas.institutional_conversation_detail_self_v1(uuid) from public,anon;
grant execute on function atlas.record_communication_attention_self_api_v1(uuid,text,text,jsonb),atlas.claim_institutional_conversation_self_api_v1(uuid,text),atlas.handoff_institutional_conversation_self_api_v1(uuid,uuid,text),atlas.set_institutional_conversation_response_state_self_api_v1(uuid,text,text),atlas.institutional_shared_inbox_self_v1(uuid,integer),atlas.institutional_conversation_detail_self_v1(uuid) to authenticated,service_role;

commit;