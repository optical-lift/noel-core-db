begin;

-- Package 7 Communications convergence Stage 4.
-- Common Communication Conversation becomes the command-side root for
-- Organization Correspondence consequences. Institutional Conversation remains
-- a compatibility carrier while historical response/send/work tables require it.

alter table atlas.communication_email_drafts
  add column if not exists communication_conversation_id uuid
  references atlas.communication_conversations(id) on delete restrict;

alter table atlas.communication_outbound_operations
  add column if not exists communication_conversation_id uuid
  references atlas.communication_conversations(id) on delete restrict;

create index if not exists communication_email_drafts_common_conversation_idx
  on atlas.communication_email_drafts(communication_conversation_id,updated_at desc)
  where communication_conversation_id is not null;

create index if not exists communication_outbound_operations_common_conversation_idx
  on atlas.communication_outbound_operations(communication_conversation_id,created_at desc)
  where communication_conversation_id is not null;

update atlas.communication_email_drafts draft
set communication_conversation_id=root.communication_conversation_id
from atlas.institutional_conversation_roots root
where draft.communication_conversation_id is null
  and draft.institutional_conversation_id=root.institutional_conversation_id;

update atlas.communication_outbound_operations operation
set communication_conversation_id=root.communication_conversation_id
from atlas.institutional_conversation_roots root
where operation.communication_conversation_id is null
  and operation.institutional_conversation_id=root.institutional_conversation_id;

comment on column atlas.communication_email_drafts.communication_conversation_id is
'Common provider-independent Communication Conversation custody for a draft when continuity is established. Institutional Conversation is compatibility only.';
comment on column atlas.communication_outbound_operations.communication_conversation_id is
'Common provider-independent Communication Conversation custody for an authorized outbound operation. Institutional Conversation is compatibility only.';

create or replace function atlas.require_institutional_compatibility_for_communication_conversation_v1(p_communication_conversation_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_common atlas.communication_conversations%rowtype;
  v_institutional_id uuid;
begin
  select * into v_common from atlas.communication_conversations where id=p_communication_conversation_id;
  if v_common.id is null then raise exception 'Communication Conversation not found.' using errcode='P0002'; end if;
  if v_common.organization_id is null or v_common.principal_id is not null then
    raise exception 'Institutional compatibility requires an Organization Communication Conversation.' using errcode='22023';
  end if;
  select institutional_conversation_id into v_institutional_id
  from atlas.institutional_conversation_roots where communication_conversation_id=v_common.id;
  if v_institutional_id is null then
    raise exception 'Communication Conversation has no Institutional compatibility carrier.' using errcode='23514';
  end if;
  if not exists(
    select 1 from atlas.institutional_conversations institutional
    where institutional.id=v_institutional_id
      and institutional.organization_id=v_common.organization_id
      and institutional.organization_unit_id is not distinct from v_common.organization_unit_id
  ) then
    raise exception 'Institutional compatibility carrier disagrees with common Conversation custody.' using errcode='23514';
  end if;
  return v_institutional_id;
end;
$function$;

create or replace function atlas.require_common_communication_conversation_for_institutional_v1(p_institutional_conversation_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare v_common_id uuid;
begin
  select communication_conversation_id into v_common_id
  from atlas.institutional_conversation_roots where institutional_conversation_id=p_institutional_conversation_id;
  if v_common_id is null then
    raise exception 'Institutional Conversation has no common Communication Conversation root.' using errcode='23514';
  end if;
  perform atlas.require_institutional_compatibility_for_communication_conversation_v1(v_common_id);
  return v_common_id;
end;
$function$;

-- Deferred AFTER triggers re-read final persisted state; NEW may reflect an
-- earlier compatibility insert that the Stage 4 wrapper completes later.
create or replace function atlas.guard_communication_consequence_common_root_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_common_id uuid;
  v_institutional_id uuid;
  v_endpoint_id uuid;
  v_reply_event_id uuid;
  v_root uuid;
  v_reply_common_id uuid;
  v_reply_endpoint_id uuid;
begin
  if tg_table_name='communication_outbound_operations' then
    select operation.communication_conversation_id,operation.institutional_conversation_id,
           operation.communication_endpoint_id,operation.reply_to_communication_event_id
    into v_common_id,v_institutional_id,v_endpoint_id,v_reply_event_id
    from atlas.communication_outbound_operations operation where operation.id=new.id;
  elsif tg_table_name='communication_email_drafts' then
    select draft.communication_conversation_id,draft.institutional_conversation_id,
           draft.communication_endpoint_id,draft.reply_to_communication_event_id
    into v_common_id,v_institutional_id,v_endpoint_id,v_reply_event_id
    from atlas.communication_email_drafts draft where draft.id=new.id;
  else
    raise exception 'Unsupported Communication consequence table %.',tg_table_name using errcode='23514';
  end if;

  if not found then return null; end if;

  if tg_table_name='communication_outbound_operations'
     and (v_common_id is null or v_institutional_id is null) then
    raise exception 'Outbound Communication operations require common Conversation and Institutional compatibility custody.' using errcode='23514';
  end if;

  if v_common_id is null and v_institutional_id is null then
    if v_reply_event_id is not null then
      raise exception 'A reply draft cannot be unbound from its Communication Conversation.' using errcode='23514';
    end if;
    return null;
  end if;

  if v_common_id is null or v_institutional_id is null then
    raise exception 'Communication consequence conversation custody must be paired.' using errcode='23514';
  end if;

  select communication_conversation_id into v_root
  from atlas.institutional_conversation_roots where institutional_conversation_id=v_institutional_id;
  if v_root is distinct from v_common_id then
    raise exception 'Communication consequence Institutional compatibility does not match common Conversation.' using errcode='23514';
  end if;

  if v_reply_event_id is not null then
    select membership.communication_conversation_id,membership.communication_endpoint_id
    into v_reply_common_id,v_reply_endpoint_id
    from atlas.communication_conversation_events membership
    where membership.communication_event_id=v_reply_event_id;
    if v_reply_common_id is null
       or v_reply_common_id is distinct from v_common_id
       or v_reply_endpoint_id is distinct from v_endpoint_id then
      raise exception 'Reply consequence must preserve exact common Conversation and Communication Endpoint continuity.' using errcode='23514';
    end if;
  end if;
  return null;
end;
$function$;

drop trigger if exists communication_email_draft_common_root_guard_v1 on atlas.communication_email_drafts;
create constraint trigger communication_email_draft_common_root_guard_v1
after insert or update on atlas.communication_email_drafts
deferrable initially deferred
for each row execute function atlas.guard_communication_consequence_common_root_v1();

drop trigger if exists communication_outbound_operation_common_root_guard_v1 on atlas.communication_outbound_operations;
create constraint trigger communication_outbound_operation_common_root_guard_v1
after insert or update on atlas.communication_outbound_operations
deferrable initially deferred
for each row execute function atlas.guard_communication_consequence_common_root_v1();

create or replace function atlas.ensure_organization_communication_command_pair_service_v1(
  p_actor_membership_id uuid,
  p_communication_endpoint_id uuid,
  p_communication_conversation_id uuid default null,
  p_institutional_conversation_id uuid default null,
  p_reply_to_communication_event_id uuid default null,
  p_subject text default null,
  p_create_if_missing boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_actor atlas.organization_memberships%rowtype;
  v_common atlas.communication_conversations%rowtype;
  v_common_id uuid:=p_communication_conversation_id;
  v_institutional_id uuid:=p_institutional_conversation_id;
  v_reply_common_id uuid;
  v_reply_endpoint_id uuid;
  v_root_id uuid;
  v_pair_key text;
begin
  select * into v_endpoint from atlas.communication_endpoints
  where id=p_communication_endpoint_id and endpoint_state='active';
  if v_endpoint.id is null then raise exception 'Active Communication Endpoint required.' using errcode='P0002'; end if;

  select * into v_actor from atlas.organization_memberships
  where id=p_actor_membership_id and organization_id=v_endpoint.organization_id and active;
  if v_actor.id is null then raise exception 'Active Organization membership required.' using errcode='42501'; end if;

  if p_reply_to_communication_event_id is not null then
    select communication_conversation_id,communication_endpoint_id
    into v_reply_common_id,v_reply_endpoint_id
    from atlas.communication_conversation_events
    where communication_event_id=p_reply_to_communication_event_id;
    if v_reply_common_id is null then
      raise exception 'Reply target is not attached to a common Communication Conversation.' using errcode='23514';
    end if;
    if v_reply_endpoint_id is distinct from v_endpoint.id then
      raise exception 'Reply command must use the exact Communication Endpoint of the source Event.' using errcode='42501';
    end if;
    if v_common_id is not null and v_common_id is distinct from v_reply_common_id then
      raise exception 'Reply target belongs to a different Communication Conversation.' using errcode='23514';
    end if;
    v_common_id:=v_reply_common_id;
  end if;

  if v_institutional_id is not null then
    v_root_id:=atlas.require_common_communication_conversation_for_institutional_v1(v_institutional_id);
    if v_common_id is not null and v_common_id is distinct from v_root_id then
      raise exception 'Institutional compatibility ID and common Conversation ID disagree.' using errcode='23514';
    end if;
    v_common_id:=v_root_id;
  end if;

  if v_common_id is not null then
    select * into v_common from atlas.communication_conversations
    where id=v_common_id
      and organization_id=v_endpoint.organization_id
      and organization_unit_id is not distinct from v_endpoint.organization_unit_id
      and principal_id is null and conversation_state='open';
    if v_common.id is null then
      raise exception 'Common Communication Conversation is outside Endpoint scope or not open.' using errcode='42501';
    end if;

    v_root_id:=atlas.require_institutional_compatibility_for_communication_conversation_v1(v_common.id);
    if v_institutional_id is not null and v_institutional_id is distinct from v_root_id then
      raise exception 'Common Conversation resolves to a different Institutional compatibility carrier.' using errcode='23514';
    end if;
    v_institutional_id:=v_root_id;

    if not exists(
      select 1 from atlas.communication_conversation_endpoints endpoint_link
      where endpoint_link.communication_conversation_id=v_common.id
        and endpoint_link.communication_endpoint_id=v_endpoint.id
    ) or not exists(
      select 1 from atlas.institutional_conversation_endpoints compatibility_endpoint
      where compatibility_endpoint.institutional_conversation_id=v_institutional_id
        and compatibility_endpoint.communication_endpoint_id=v_endpoint.id
    ) then
      raise exception 'Communication Endpoint is not a governed participant in this Conversation.' using errcode='42501';
    end if;

    return jsonb_build_object(
      'contractVersion','organization_communication_command_pair_v1','state','resolved',
      'communicationConversationId',v_common.id,'institutionalCompatibilityId',v_institutional_id,
      'communicationEndpointId',v_endpoint.id,'created',false
    );
  end if;

  if not p_create_if_missing then
    return jsonb_build_object(
      'contractVersion','organization_communication_command_pair_v1','state','unbound',
      'communicationConversationId',null,'institutionalCompatibilityId',null,
      'communicationEndpointId',v_endpoint.id,'created',false
    );
  end if;

  v_pair_key:='outbound-intent:'||gen_random_uuid()::text;

  insert into atlas.communication_conversations(
    principal_id,organization_id,organization_unit_id,stable_key,subject,opened_at,last_activity_at,metadata
  ) values(
    null,v_endpoint.organization_id,v_endpoint.organization_unit_id,v_pair_key,
    nullif(btrim(coalesce(p_subject,'')),''),now(),now(),
    jsonb_build_object('createdFromOutboundIntent',true,'initiatedByMembershipId',v_actor.id,'communicationEndpointId',v_endpoint.id)
  ) returning id into v_common_id;

  insert into atlas.communication_conversation_endpoints(
    communication_conversation_id,communication_endpoint_id,endpoint_role,metadata
  ) values(v_common_id,v_endpoint.id,'primary',jsonb_build_object('source','outbound_intent'));

  insert into atlas.institutional_conversations(
    organization_id,organization_unit_id,stable_key,subject,opened_at,last_activity_at,metadata
  ) values(
    v_endpoint.organization_id,v_endpoint.organization_unit_id,v_pair_key,
    nullif(btrim(coalesce(p_subject,'')),''),now(),now(),
    jsonb_build_object('compatibilityForCommunicationConversationId',v_common_id,'createdFromOutboundIntent',true,'initiatedByMembershipId',v_actor.id)
  ) returning id into v_institutional_id;

  insert into atlas.institutional_conversation_endpoints(
    institutional_conversation_id,communication_endpoint_id,endpoint_role
  ) values(v_institutional_id,v_endpoint.id,'primary');

  insert into atlas.institutional_conversation_roots(
    institutional_conversation_id,communication_conversation_id
  ) values(v_institutional_id,v_common_id);

  return jsonb_build_object(
    'contractVersion','organization_communication_command_pair_v1','state','created',
    'communicationConversationId',v_common_id,'institutionalCompatibilityId',v_institutional_id,
    'communicationEndpointId',v_endpoint.id,'created',true
  );
end;
$function$;

create or replace function atlas.prepare_communication_email_send_internal_v3(
  p_actor_membership_id uuid,
  p_communication_endpoint_id uuid,
  p_communication_conversation_id uuid,
  p_institutional_conversation_id uuid,
  p_to_recipients jsonb,
  p_cc_recipients jsonb default '[]'::jsonb,
  p_bcc_recipients jsonb default '[]'::jsonb,
  p_subject text default null,
  p_body_text text default null,
  p_body_html text default null,
  p_attachment_refs jsonb default '[]'::jsonb,
  p_reply_to_communication_event_id uuid default null,
  p_idempotency_key text default null,
  p_authorization_source text default 'common_conversation_send_command'
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_pair jsonb;
  v_common_id uuid;
  v_institutional_id uuid;
  v_existing atlas.communication_outbound_operations%rowtype;
  v_result jsonb;
  v_operation_id uuid;
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
begin
  select * into v_endpoint from atlas.communication_endpoints
  where id=p_communication_endpoint_id and endpoint_state='active';
  if v_endpoint.id is null then raise exception 'Active Communication Endpoint required.' using errcode='P0002'; end if;

  if v_key is not null then
    perform pg_advisory_xact_lock(hashtextextended(v_endpoint.organization_id::text||':'||v_key,0));
    select * into v_existing from atlas.communication_outbound_operations
    where organization_id=v_endpoint.organization_id and idempotency_key=v_key limit 1;
  end if;

  if v_existing.id is not null then
    v_pair:=atlas.ensure_organization_communication_command_pair_service_v1(
      p_actor_membership_id,p_communication_endpoint_id,
      coalesce(v_existing.communication_conversation_id,p_communication_conversation_id),
      coalesce(v_existing.institutional_conversation_id,p_institutional_conversation_id),
      p_reply_to_communication_event_id,p_subject,false
    );
    v_common_id=(v_pair->>'communicationConversationId')::uuid;
    v_institutional_id=(v_pair->>'institutionalCompatibilityId')::uuid;
    if p_communication_conversation_id is not null and p_communication_conversation_id is distinct from v_common_id then
      raise exception 'Idempotency key already belongs to another Communication Conversation.' using errcode='23505';
    end if;
  else
    v_pair:=atlas.ensure_organization_communication_command_pair_service_v1(
      p_actor_membership_id,p_communication_endpoint_id,p_communication_conversation_id,
      p_institutional_conversation_id,p_reply_to_communication_event_id,p_subject,true
    );
    v_common_id=(v_pair->>'communicationConversationId')::uuid;
    v_institutional_id=(v_pair->>'institutionalCompatibilityId')::uuid;
  end if;

  v_result:=atlas.prepare_institutional_email_send_internal_v2(
    p_actor_membership_id,p_communication_endpoint_id,v_institutional_id,
    p_to_recipients,p_cc_recipients,p_bcc_recipients,p_subject,p_body_text,p_body_html,
    p_attachment_refs,p_reply_to_communication_event_id,p_idempotency_key,p_authorization_source
  );

  v_operation_id=(v_result->>'outboundOperationId')::uuid;
  update atlas.communication_outbound_operations
  set communication_conversation_id=v_common_id,
      metadata=metadata||jsonb_build_object(
        'communicationConversationId',v_common_id,'institutionalCompatibilityId',v_institutional_id,'commandRoot','communication_conversation'
      ),updated_at=now()
  where id=v_operation_id;

  return v_result||jsonb_build_object(
    'contractVersion','communication_email_send_intent_v3','communicationConversationId',v_common_id,
    'institutionalCompatibilityId',v_institutional_id,'commandRoot','communication_conversation'
  );
end;
$function$;

create or replace function atlas.prepare_institutional_email_send_self_api_v1(
  p_communication_endpoint_id uuid,
  p_institutional_conversation_id uuid,
  p_to_recipients jsonb,
  p_cc_recipients jsonb default '[]'::jsonb,
  p_bcc_recipients jsonb default '[]'::jsonb,
  p_subject text default null,
  p_body_text text default null,
  p_body_html text default null,
  p_attachment_refs jsonb default '[]'::jsonb,
  p_reply_to_communication_event_id uuid default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare v_endpoint atlas.communication_endpoints%rowtype; v_member atlas.organization_memberships%rowtype; v_common_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_endpoint from atlas.communication_endpoints where id=p_communication_endpoint_id and endpoint_state='active';
  if v_endpoint.id is null then raise exception 'Communication Endpoint not found.' using errcode='P0002'; end if;
  select * into v_member from atlas.organization_memberships
  where organization_id=v_endpoint.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_member.id is null then raise exception 'Active Organization membership required.' using errcode='42501'; end if;
  if p_institutional_conversation_id is not null then
    v_common_id:=atlas.require_common_communication_conversation_for_institutional_v1(p_institutional_conversation_id);
  end if;
  return atlas.prepare_communication_email_send_internal_v3(
    v_member.id,p_communication_endpoint_id,v_common_id,p_institutional_conversation_id,
    p_to_recipients,p_cc_recipients,p_bcc_recipients,p_subject,p_body_text,p_body_html,
    p_attachment_refs,p_reply_to_communication_event_id,p_idempotency_key,'legacy_institutional_send_compatibility'
  );
end;
$function$;

create or replace function atlas.prepare_communication_email_send_self_api_v2(
  p_communication_endpoint_id uuid,
  p_communication_conversation_id uuid,
  p_to_recipients jsonb,
  p_cc_recipients jsonb default '[]'::jsonb,
  p_bcc_recipients jsonb default '[]'::jsonb,
  p_subject text default null,
  p_body_text text default null,
  p_body_html text default null,
  p_attachment_refs jsonb default '[]'::jsonb,
  p_reply_to_communication_event_id uuid default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare v_endpoint atlas.communication_endpoints%rowtype; v_member atlas.organization_memberships%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_endpoint from atlas.communication_endpoints where id=p_communication_endpoint_id and endpoint_state='active';
  if v_endpoint.id is null then raise exception 'Communication Endpoint not found.' using errcode='P0002'; end if;
  select * into v_member from atlas.organization_memberships
  where organization_id=v_endpoint.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_member.id is null then raise exception 'Active Organization membership required.' using errcode='42501'; end if;
  return atlas.prepare_communication_email_send_internal_v3(
    v_member.id,p_communication_endpoint_id,p_communication_conversation_id,null,
    p_to_recipients,p_cc_recipients,p_bcc_recipients,p_subject,p_body_text,p_body_html,
    p_attachment_refs,p_reply_to_communication_event_id,p_idempotency_key,'common_conversation_authenticated_send'
  );
end;
$function$;

alter function atlas.save_communication_email_draft_self_api_v1(
  uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb
) rename to save_communication_email_draft_compatibility_self_api_v1;

create or replace function atlas.save_communication_email_draft_self_api_v1(
  p_draft_id uuid,p_communication_endpoint_id uuid,p_institutional_conversation_id uuid,
  p_reply_to_communication_event_id uuid,p_to_recipients jsonb,p_cc_recipients jsonb,
  p_bcc_recipients jsonb,p_subject text,p_body_text text,p_body_html text,p_attachment_refs jsonb,
  p_signature_id uuid,p_send_after timestamptz,p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare v_common_id uuid; v_result jsonb; v_draft_id uuid;
begin
  if p_institutional_conversation_id is not null then
    v_common_id:=atlas.require_common_communication_conversation_for_institutional_v1(p_institutional_conversation_id);
  end if;
  v_result:=atlas.save_communication_email_draft_compatibility_self_api_v1(
    p_draft_id,p_communication_endpoint_id,p_institutional_conversation_id,p_reply_to_communication_event_id,
    p_to_recipients,p_cc_recipients,p_bcc_recipients,p_subject,p_body_text,p_body_html,p_attachment_refs,
    p_signature_id,p_send_after,p_metadata
  );
  v_draft_id=(v_result->>'draftId')::uuid;
  update atlas.communication_email_drafts
  set communication_conversation_id=v_common_id,
      metadata=metadata||case when v_common_id is null then '{}'::jsonb else jsonb_build_object(
        'communicationConversationId',v_common_id,'institutionalCompatibilityId',p_institutional_conversation_id,
        'commandRoot','communication_conversation'
      ) end,updated_at=now()
  where id=v_draft_id;
  return v_result||jsonb_build_object('communicationConversationId',v_common_id,'institutionalCompatibilityId',p_institutional_conversation_id);
end;
$function$;

create or replace function atlas.save_communication_email_draft_self_api_v2(
  p_draft_id uuid,p_communication_endpoint_id uuid,p_communication_conversation_id uuid,
  p_reply_to_communication_event_id uuid,p_to_recipients jsonb,p_cc_recipients jsonb,
  p_bcc_recipients jsonb,p_subject text,p_body_text text,p_body_html text,p_attachment_refs jsonb,
  p_signature_id uuid,p_send_after timestamptz,p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_common_id uuid:=p_communication_conversation_id;
  v_institutional_id uuid;
  v_reply_common_id uuid;
  v_reply_endpoint_id uuid;
  v_result jsonb;
  v_draft_id uuid;
begin
  if p_reply_to_communication_event_id is not null then
    select communication_conversation_id,communication_endpoint_id
    into v_reply_common_id,v_reply_endpoint_id
    from atlas.communication_conversation_events where communication_event_id=p_reply_to_communication_event_id;
    if v_reply_common_id is null then raise exception 'Reply target is not attached to a common Communication Conversation.' using errcode='23514'; end if;
    if v_reply_endpoint_id is distinct from p_communication_endpoint_id then raise exception 'Reply draft must use the exact Communication Endpoint of the source Event.' using errcode='42501'; end if;
    if v_common_id is not null and v_common_id is distinct from v_reply_common_id then raise exception 'Reply target belongs to another Communication Conversation.' using errcode='23514'; end if;
    v_common_id:=v_reply_common_id;
  end if;
  if v_common_id is not null then
    v_institutional_id:=atlas.require_institutional_compatibility_for_communication_conversation_v1(v_common_id);
  end if;
  v_result:=atlas.save_communication_email_draft_compatibility_self_api_v1(
    p_draft_id,p_communication_endpoint_id,v_institutional_id,p_reply_to_communication_event_id,
    p_to_recipients,p_cc_recipients,p_bcc_recipients,p_subject,p_body_text,p_body_html,p_attachment_refs,
    p_signature_id,p_send_after,p_metadata
  );
  v_draft_id=(v_result->>'draftId')::uuid;
  update atlas.communication_email_drafts
  set communication_conversation_id=v_common_id,
      metadata=metadata||case when v_common_id is null then '{}'::jsonb else jsonb_build_object(
        'communicationConversationId',v_common_id,'institutionalCompatibilityId',v_institutional_id,
        'commandRoot','communication_conversation'
      ) end,updated_at=now()
  where id=v_draft_id;
  return v_result||jsonb_build_object(
    'contractVersion','communication_email_draft_v3','communicationConversationId',v_common_id,
    'institutionalCompatibilityId',v_institutional_id,
    'commandRoot',case when v_common_id is null then 'unbound_draft' else 'communication_conversation' end
  );
end;
$function$;

create or replace function atlas.authorize_communication_email_draft_self_api_v1(p_draft_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_row atlas.communication_email_drafts%rowtype;
  v_member atlas.organization_memberships%rowtype;
  v_signature atlas.communication_email_signatures%rowtype;
  v_body text; v_result jsonb; v_operation_id uuid; v_common_id uuid; v_institutional_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_row from atlas.communication_email_drafts where id=p_draft_id for update;
  if v_row.id is null then raise exception 'Draft not found.' using errcode='P0002'; end if;
  select * into v_member from atlas.organization_memberships where id=v_row.author_membership_id and user_id=auth.uid() and active;
  if v_member.id is null then raise exception 'Only the draft author may send it.' using errcode='42501'; end if;
  if v_row.draft_state='authorized' then
    return jsonb_build_object('contractVersion','communication_email_draft_authorize_v2','draftId',v_row.id,
      'outboundOperationId',v_row.authorized_outbound_operation_id,'communicationConversationId',v_row.communication_conversation_id,'deduplicated',true);
  end if;
  if v_row.draft_state='discarded' then raise exception 'Discarded draft cannot be sent.' using errcode='55000'; end if;
  if jsonb_array_length(v_row.to_recipients)<1 then raise exception 'At least one To recipient is required.' using errcode='22023'; end if;
  v_body:=coalesce(v_row.body_text,'');
  if v_row.signature_id is not null then
    select * into v_signature from atlas.communication_email_signatures where id=v_row.signature_id and active;
    if v_signature.id is not null and btrim(v_signature.body_text)<>'' then v_body:=rtrim(v_body)||E'\n\n'||v_signature.body_text; end if;
  end if;
  v_result:=atlas.prepare_communication_email_send_internal_v3(
    v_member.id,v_row.communication_endpoint_id,v_row.communication_conversation_id,v_row.institutional_conversation_id,
    v_row.to_recipients,v_row.cc_recipients,v_row.bcc_recipients,v_row.subject,v_body,v_row.body_html,
    v_row.attachment_refs,v_row.reply_to_communication_event_id,'draft:'||v_row.id::text,'draft_send_now'
  );
  v_operation_id=(v_result->>'outboundOperationId')::uuid;
  v_common_id=(v_result->>'communicationConversationId')::uuid;
  v_institutional_id=(v_result->>'institutionalCompatibilityId')::uuid;
  update atlas.communication_email_drafts
  set draft_state='authorized',send_after=null,authorized_outbound_operation_id=v_operation_id,
      communication_conversation_id=v_common_id,institutional_conversation_id=v_institutional_id,
      metadata=metadata||jsonb_build_object('commandRoot','communication_conversation'),updated_at=now()
  where id=v_row.id;
  return v_result||jsonb_build_object('contractVersion','communication_email_draft_authorize_v2','draftId',v_row.id,'deduplicated',false);
end;
$function$;

create or replace function atlas.release_due_communication_email_drafts_service_v1(p_limit integer default 50)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_row atlas.communication_email_drafts%rowtype;
  v_signature atlas.communication_email_signatures%rowtype;
  v_body text; v_result jsonb; v_released integer:=0; v_failed integer:=0;
begin
  if p_limit<1 or p_limit>500 then raise exception 'Limit must be between 1 and 500.' using errcode='22023'; end if;
  for v_row in
    select d.* from atlas.communication_email_drafts d
    where d.draft_state='scheduled' and d.send_after<=now()
      and exists(
        select 1 from atlas.communication_endpoint_source_bindings binding
        join atlas.connected_sources source on source.id=binding.connected_source_id
        where binding.communication_endpoint_id=d.communication_endpoint_id
          and binding.binding_state='active' and binding.binding_role in ('send','send_receive')
          and source.authorization_state='connected' and source.capabilities @> '{"communicationSend":true}'::jsonb
      )
    order by d.send_after,d.id for update skip locked limit p_limit
  loop
    begin
      v_body:=coalesce(v_row.body_text,'');
      if v_row.signature_id is not null then
        select * into v_signature from atlas.communication_email_signatures where id=v_row.signature_id and active;
        if v_signature.id is not null and btrim(v_signature.body_text)<>'' then v_body:=rtrim(v_body)||E'\n\n'||v_signature.body_text; end if;
      end if;
      v_result:=atlas.prepare_communication_email_send_internal_v3(
        v_row.author_membership_id,v_row.communication_endpoint_id,v_row.communication_conversation_id,
        v_row.institutional_conversation_id,v_row.to_recipients,v_row.cc_recipients,v_row.bcc_recipients,
        v_row.subject,v_body,v_row.body_html,v_row.attachment_refs,v_row.reply_to_communication_event_id,
        'draft:'||v_row.id::text,'scheduled_draft_release'
      );
      update atlas.communication_email_drafts
      set draft_state='authorized',send_after=null,
          authorized_outbound_operation_id=(v_result->>'outboundOperationId')::uuid,
          communication_conversation_id=(v_result->>'communicationConversationId')::uuid,
          institutional_conversation_id=(v_result->>'institutionalCompatibilityId')::uuid,
          metadata=((metadata-'lastScheduleError')-'lastScheduleAttemptAt')||jsonb_build_object('commandRoot','communication_conversation'),updated_at=now()
      where id=v_row.id;
      v_released:=v_released+1;
    exception when others then
      update atlas.communication_email_drafts
      set metadata=metadata||jsonb_build_object('lastScheduleError',sqlerrm,'lastScheduleAttemptAt',now()),updated_at=now()
      where id=v_row.id;
      v_failed:=v_failed+1;
    end;
  end loop;
  return jsonb_build_object('contractVersion','communication_email_draft_release_v3','released',v_released,'failed',v_failed,'commandRoot','communication_conversation');
end;
$function$;

-- Sent is a common-Conversation read. The outbound operation is now the direct
-- holder of common identity; the Institutional root only proves compatibility.
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
    select o.*,el.communication_event_id,
           la.attempt as latest_attempt,coalesce(la.recipients,'[]'::jsonb) as recipient_results
    from atlas.communication_outbound_operations o
    join atlas.institutional_conversation_roots r
      on r.institutional_conversation_id=o.institutional_conversation_id
     and r.communication_conversation_id=o.communication_conversation_id
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
    where atlas.organization_correspondence_read_authorized_self_v1(o.communication_conversation_id)
      and (p_organization_id is null or atlas.organization_correspondence_effective_organization_v1(o.communication_conversation_id)=p_organization_id)
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

create or replace function atlas.claim_communication_conversation_self_api_v1(p_communication_conversation_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth
as $function$
declare v_institutional_id uuid; v_result jsonb;
begin
  v_institutional_id:=atlas.require_institutional_compatibility_for_communication_conversation_v1(p_communication_conversation_id);
  v_result:=atlas.claim_institutional_conversation_self_api_v1(v_institutional_id,p_reason);
  return v_result||jsonb_build_object('contractVersion','communication_conversation_claim_v1','communicationConversationId',p_communication_conversation_id,'institutionalCompatibilityId',v_institutional_id);
end;
$function$;

create or replace function atlas.handoff_communication_conversation_self_api_v1(p_communication_conversation_id uuid,p_target_membership_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth
as $function$
declare v_institutional_id uuid; v_result jsonb;
begin
  v_institutional_id:=atlas.require_institutional_compatibility_for_communication_conversation_v1(p_communication_conversation_id);
  v_result:=atlas.handoff_institutional_conversation_self_api_v1(v_institutional_id,p_target_membership_id,p_reason);
  return v_result||jsonb_build_object('contractVersion','communication_conversation_handoff_v1','communicationConversationId',p_communication_conversation_id,'institutionalCompatibilityId',v_institutional_id);
end;
$function$;

create or replace function atlas.add_communication_conversation_collaborator_self_api_v1(p_communication_conversation_id uuid,p_target_membership_id uuid,p_allocation_role text default 'participant')
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth
as $function$
declare v_institutional_id uuid; v_result jsonb;
begin
  v_institutional_id:=atlas.require_institutional_compatibility_for_communication_conversation_v1(p_communication_conversation_id);
  v_result:=atlas.add_institutional_conversation_collaborator_self_api_v1(v_institutional_id,p_target_membership_id,p_allocation_role);
  return v_result||jsonb_build_object('contractVersion','communication_conversation_collaborator_v1','communicationConversationId',p_communication_conversation_id,'institutionalCompatibilityId',v_institutional_id);
end;
$function$;

create or replace function atlas.remove_communication_conversation_collaborator_self_api_v1(p_communication_conversation_id uuid,p_target_membership_id uuid,p_allocation_role text default 'participant')
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth
as $function$
declare v_institutional_id uuid; v_result jsonb;
begin
  v_institutional_id:=atlas.require_institutional_compatibility_for_communication_conversation_v1(p_communication_conversation_id);
  v_result:=atlas.remove_institutional_conversation_collaborator_self_api_v1(v_institutional_id,p_target_membership_id,p_allocation_role);
  return v_result||jsonb_build_object('contractVersion','communication_conversation_collaborator_remove_v1','communicationConversationId',p_communication_conversation_id,'institutionalCompatibilityId',v_institutional_id);
end;
$function$;

create or replace function atlas.set_communication_conversation_response_state_self_api_v1(p_communication_conversation_id uuid,p_to_state text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth
as $function$
declare v_institutional_id uuid; v_result jsonb;
begin
  v_institutional_id:=atlas.require_institutional_compatibility_for_communication_conversation_v1(p_communication_conversation_id);
  v_result:=atlas.set_institutional_conversation_response_state_self_api_v1(v_institutional_id,p_to_state,p_reason);
  return v_result||jsonb_build_object('contractVersion','communication_conversation_response_state_v1','communicationConversationId',p_communication_conversation_id,'institutionalCompatibilityId',v_institutional_id);
end;
$function$;

create or replace function atlas.communication_work_context_candidates_self_v2(p_communication_conversation_id uuid,p_query text default null)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth
as $function$
declare v_institutional_id uuid; v_result jsonb;
begin
  v_institutional_id:=atlas.require_institutional_compatibility_for_communication_conversation_v1(p_communication_conversation_id);
  v_result:=atlas.communication_work_context_candidates_self_v1(v_institutional_id,p_query);
  return v_result||jsonb_build_object('contractVersion','communication_work_context_candidates_v2','communicationConversationId',p_communication_conversation_id,'institutionalCompatibilityId',v_institutional_id);
end;
$function$;

create or replace function atlas.create_communication_derived_work_self_api_v3(
  p_communication_conversation_id uuid,p_communication_event_id uuid,p_excerpt text,p_title text,
  p_instructions text,p_assignee_membership_id uuid,p_due_at timestamptz,p_handling_mode text,
  p_semantic_frame jsonb,p_context_links jsonb,p_related_work jsonb,p_idempotency_key text
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth
as $function$
declare v_institutional_id uuid; v_result jsonb; v_work_id uuid;
begin
  v_institutional_id:=atlas.require_institutional_compatibility_for_communication_conversation_v1(p_communication_conversation_id);
  if not exists(
    select 1 from atlas.communication_conversation_events membership
    where membership.communication_conversation_id=p_communication_conversation_id
      and membership.communication_event_id=p_communication_event_id
  ) then
    raise exception 'Communication Event is not evidence inside this common Conversation.' using errcode='23514';
  end if;
  v_result:=atlas.create_communication_derived_work_self_api_v2(
    v_institutional_id,p_communication_event_id,p_excerpt,p_title,p_instructions,p_assignee_membership_id,
    p_due_at,p_handling_mode,p_semantic_frame,p_context_links,p_related_work,p_idempotency_key
  );
  v_work_id=nullif(v_result->>'workItemId','')::uuid;
  if v_work_id is not null then
    update atlas.work_items
    set metadata=metadata||jsonb_build_object(
      'communicationConversationId',p_communication_conversation_id,'institutionalCompatibilityId',v_institutional_id,
      'communicationEventId',p_communication_event_id,'communicationCommandRoot','communication_conversation'
    ),updated_at=now()
    where id=v_work_id;
  end if;
  return v_result||jsonb_build_object(
    'contractVersion','communication_derived_work_create_v3','communicationConversationId',p_communication_conversation_id,
    'institutionalCompatibilityId',v_institutional_id,'communicationEventId',p_communication_event_id
  );
end;
$function$;

-- Mailbox disposition remains endpoint/mailbox-scoped in Stage 4.

revoke all on function atlas.require_institutional_compatibility_for_communication_conversation_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.require_common_communication_conversation_for_institutional_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.guard_communication_consequence_common_root_v1() from public,anon,authenticated;
revoke all on function atlas.ensure_organization_communication_command_pair_service_v1(uuid,uuid,uuid,uuid,uuid,text,boolean) from public,anon,authenticated;
revoke all on function atlas.prepare_communication_email_send_internal_v3(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text,text) from public,anon,authenticated;
revoke all on function atlas.save_communication_email_draft_compatibility_self_api_v1(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb) from public,anon,authenticated;

grant execute on function atlas.require_institutional_compatibility_for_communication_conversation_v1(uuid) to service_role;
grant execute on function atlas.require_common_communication_conversation_for_institutional_v1(uuid) to service_role;
grant execute on function atlas.guard_communication_consequence_common_root_v1() to service_role;
grant execute on function atlas.ensure_organization_communication_command_pair_service_v1(uuid,uuid,uuid,uuid,uuid,text,boolean) to service_role;
grant execute on function atlas.prepare_communication_email_send_internal_v3(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text,text) to service_role;
grant execute on function atlas.save_communication_email_draft_compatibility_self_api_v1(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb) to service_role;

-- Recreated legacy draft-save wrapper keeps the original authenticated-only ACL.
revoke all on function atlas.save_communication_email_draft_self_api_v1(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb) from public,anon;
grant execute on function atlas.save_communication_email_draft_self_api_v1(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb) to authenticated,service_role;

revoke all on function atlas.prepare_communication_email_send_self_api_v2(uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text) from public,anon;
revoke all on function atlas.save_communication_email_draft_self_api_v2(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb) from public,anon;
revoke all on function atlas.claim_communication_conversation_self_api_v1(uuid,text) from public,anon;
revoke all on function atlas.handoff_communication_conversation_self_api_v1(uuid,uuid,text) from public,anon;
revoke all on function atlas.add_communication_conversation_collaborator_self_api_v1(uuid,uuid,text) from public,anon;
revoke all on function atlas.remove_communication_conversation_collaborator_self_api_v1(uuid,uuid,text) from public,anon;
revoke all on function atlas.set_communication_conversation_response_state_self_api_v1(uuid,text,text) from public,anon;
revoke all on function atlas.communication_work_context_candidates_self_v2(uuid,text) from public,anon;
revoke all on function atlas.create_communication_derived_work_self_api_v3(uuid,uuid,text,text,text,uuid,timestamptz,text,jsonb,jsonb,jsonb,text) from public,anon;

grant execute on function atlas.prepare_communication_email_send_self_api_v2(uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text) to authenticated,service_role;
grant execute on function atlas.save_communication_email_draft_self_api_v2(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb) to authenticated,service_role;
grant execute on function atlas.claim_communication_conversation_self_api_v1(uuid,text) to authenticated,service_role;
grant execute on function atlas.handoff_communication_conversation_self_api_v1(uuid,uuid,text) to authenticated,service_role;
grant execute on function atlas.add_communication_conversation_collaborator_self_api_v1(uuid,uuid,text) to authenticated,service_role;
grant execute on function atlas.remove_communication_conversation_collaborator_self_api_v1(uuid,uuid,text) to authenticated,service_role;
grant execute on function atlas.set_communication_conversation_response_state_self_api_v1(uuid,text,text) to authenticated,service_role;
grant execute on function atlas.communication_work_context_candidates_self_v2(uuid,text) to authenticated,service_role;
grant execute on function atlas.create_communication_derived_work_self_api_v3(uuid,uuid,text,text,text,uuid,timestamptz,text,jsonb,jsonb,jsonb,text) to authenticated,service_role;

comment on function atlas.prepare_communication_email_send_internal_v3(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text,text) is
'Stage 4 outbound command membrane. Common Communication Conversation is established/resolved before Institutional compatibility and outbound transport authorization.';
comment on function atlas.prepare_institutional_email_send_self_api_v1(uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text) is
'Transitional Institutional-ID browser send contract. Resolves/creates common Communication Conversation first through Stage 4 and should be retired after Product cutover.';
comment on function atlas.create_communication_derived_work_self_api_v3(uuid,uuid,text,text,text,uuid,timestamptz,text,jsonb,jsonb,jsonb,text) is
'Creates Company Work from exact Communication Event evidence under common Communication Conversation command identity; Institutional Conversation is compatibility only.';

commit;