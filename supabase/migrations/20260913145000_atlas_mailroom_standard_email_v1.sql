-- Industry-standard Mailroom foundations v1
-- Durable drafts/send-later, signatures, mailbox disposition, search, attachment membranes,
-- and outbound delivery projections. Reuses canonical communication/outbound custody.

begin;

-- ---------------------------------------------------------------------------
-- Signatures
-- ---------------------------------------------------------------------------

create table atlas.communication_email_signatures (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid,
  communication_endpoint_id uuid not null references atlas.communication_endpoints(id) on delete cascade,
  owner_membership_id uuid,
  signature_name text not null,
  body_text text not null,
  body_html text,
  is_default boolean not null default false,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_email_signatures_owner_org_fk
    foreign key (organization_id, owner_membership_id)
    references atlas.organization_memberships(organization_id,id) on delete cascade,
  constraint communication_email_signatures_unit_org_fk
    foreign key (organization_id,organization_unit_id)
    references atlas.organization_units(organization_id,id) on delete restrict,
  constraint communication_email_signatures_name_nonblank check (btrim(signature_name)<>''),
  constraint communication_email_signatures_body_nonblank check (btrim(body_text)<>'' or nullif(btrim(coalesce(body_html,'')),'') is not null),
  constraint communication_email_signatures_metadata_object check (jsonb_typeof(metadata)='object')
);

create unique index communication_email_signatures_member_default_uq
  on atlas.communication_email_signatures(communication_endpoint_id,owner_membership_id)
  where active and is_default and owner_membership_id is not null;
create unique index communication_email_signatures_endpoint_default_uq
  on atlas.communication_email_signatures(communication_endpoint_id)
  where active and is_default and owner_membership_id is null;

revoke all on atlas.communication_email_signatures from anon,authenticated;

create or replace function atlas.upsert_communication_email_signature_self_api_v1(
  p_signature_id uuid,
  p_communication_endpoint_id uuid,
  p_scope text,
  p_signature_name text,
  p_body_text text,
  p_body_html text default null,
  p_is_default boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_member atlas.organization_memberships%rowtype;
  v_id uuid:=coalesce(p_signature_id,gen_random_uuid());
  v_owner uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_scope not in ('mine','endpoint') then raise exception 'Signature scope must be mine or endpoint.' using errcode='22023'; end if;
  if nullif(btrim(coalesce(p_signature_name,'')),'') is null then raise exception 'Signature name is required.' using errcode='22023'; end if;
  if nullif(btrim(coalesce(p_body_text,'')),'') is null and nullif(btrim(coalesce(p_body_html,'')),'') is null then raise exception 'Signature content is required.' using errcode='22023'; end if;

  select * into v_endpoint from atlas.communication_endpoints where id=p_communication_endpoint_id and endpoint_state='active';
  if v_endpoint.id is null or v_endpoint.endpoint_kind<>'email' then raise exception 'Active email endpoint required.' using errcode='P0002'; end if;
  select * into v_member from atlas.organization_memberships where organization_id=v_endpoint.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'send') then raise exception 'Communication endpoint send authority required.' using errcode='42501'; end if;
  if p_scope='endpoint' and not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'admin') then raise exception 'Endpoint admin authority required for a shared signature.' using errcode='42501'; end if;
  v_owner:=case when p_scope='mine' then v_member.id else null end;

  if p_signature_id is not null then
    if not exists(select 1 from atlas.communication_email_signatures s where s.id=p_signature_id and s.communication_endpoint_id=v_endpoint.id and s.owner_membership_id is not distinct from v_owner) then raise exception 'Signature not found in this scope.' using errcode='P0002'; end if;
  end if;

  if coalesce(p_is_default,false) then
    update atlas.communication_email_signatures
    set is_default=false,updated_at=now()
    where communication_endpoint_id=v_endpoint.id and active and owner_membership_id is not distinct from v_owner and id<>v_id and is_default;
  end if;

  insert into atlas.communication_email_signatures(
    id,organization_id,organization_unit_id,communication_endpoint_id,owner_membership_id,
    signature_name,body_text,body_html,is_default,active
  ) values (
    v_id,v_endpoint.organization_id,v_endpoint.organization_unit_id,v_endpoint.id,v_owner,
    btrim(p_signature_name),coalesce(p_body_text,''),nullif(p_body_html,''),coalesce(p_is_default,false),true
  )
  on conflict(id) do update set
    signature_name=excluded.signature_name,body_text=excluded.body_text,body_html=excluded.body_html,
    is_default=excluded.is_default,active=true,updated_at=now();

  return jsonb_build_object('contractVersion','communication_email_signature_v1','signatureId',v_id,'scope',p_scope,'isDefault',coalesce(p_is_default,false));
end;
$$;

create or replace function atlas.communication_email_signatures_self_v1(p_communication_endpoint_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare v_endpoint atlas.communication_endpoints%rowtype; v_member atlas.organization_memberships%rowtype; v_items jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_endpoint from atlas.communication_endpoints where id=p_communication_endpoint_id and endpoint_state='active';
  if v_endpoint.id is null then raise exception 'Communication endpoint not found.' using errcode='P0002'; end if;
  select * into v_member from atlas.organization_memberships where organization_id=v_endpoint.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'view') then raise exception 'Communication endpoint view authority required.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'signatureId',s.id,'scope',case when s.owner_membership_id is null then 'endpoint' else 'mine' end,
    'name',s.signature_name,'bodyText',s.body_text,'bodyHtml',s.body_html,'isDefault',s.is_default
  ) order by s.is_default desc,s.signature_name),'[]'::jsonb) into v_items
  from atlas.communication_email_signatures s where s.communication_endpoint_id=v_endpoint.id and s.active and (s.owner_membership_id is null or s.owner_membership_id=v_member.id);
  return jsonb_build_object('contractVersion','communication_email_signatures_v1','items',v_items);
end;
$$;

-- ---------------------------------------------------------------------------
-- Actor-aware send core. Browser send and scheduled-draft release share it.
-- ---------------------------------------------------------------------------

create or replace function atlas.prepare_institutional_email_send_internal_v2(
  p_actor_membership_id uuid,
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
  p_idempotency_key text default null,
  p_authorization_source text default 'internal_send_command'
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth,extensions
as $$
declare
  v_endpoint atlas.communication_endpoints%rowtype; v_member atlas.organization_memberships%rowtype;
  v_conv atlas.institutional_conversations%rowtype; v_conv_id uuid:=p_institutional_conversation_id;
  v_source_id uuid; v_source_count integer; v_case atlas.institutional_conversation_response_cases%rowtype;
  v_binding atlas.institutional_conversation_response_work_bindings%rowtype; v_current atlas.work_allocations%rowtype;
  v_is_collaborator boolean:=false; v_operation_id uuid:=gen_random_uuid();
  v_key text:=coalesce(nullif(btrim(p_idempotency_key),''),v_operation_id::text); v_hash text; v_stable text;
  v_attachment uuid; v_attachment_count integer:=0;
begin
  select * into v_endpoint from atlas.communication_endpoints where id=p_communication_endpoint_id and endpoint_state='active';
  if v_endpoint.id is null or v_endpoint.endpoint_kind<>'email' then raise exception 'Active email communication endpoint required.' using errcode='P0002'; end if;
  select * into v_member from atlas.organization_memberships where id=p_actor_membership_id and organization_id=v_endpoint.organization_id and active;
  if v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'send') then raise exception 'Communication endpoint send authority required.' using errcode='42501'; end if;
  if jsonb_typeof(coalesce(p_to_recipients,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_to_recipients,'[]'::jsonb))<1
     or jsonb_typeof(coalesce(p_cc_recipients,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(p_bcc_recipients,'[]'::jsonb))<>'array'
     or jsonb_typeof(coalesce(p_attachment_refs,'[]'::jsonb))<>'array' then raise exception 'Recipients/attachments must be JSON arrays and at least one To recipient is required.' using errcode='22023'; end if;

  select count(*),(array_agg(b.connected_source_id order by b.connected_source_id))[1] into v_source_count,v_source_id
  from atlas.communication_endpoint_source_bindings b join atlas.connected_sources s on s.id=b.connected_source_id
  where b.communication_endpoint_id=v_endpoint.id and b.binding_state='active' and b.binding_role in ('send','send_receive')
    and s.authorization_state='connected' and s.capabilities @> '{"communicationSend":true}'::jsonb;
  if v_source_count<>1 then raise exception 'Exactly one connected send transport is required for this endpoint; found %.',v_source_count using errcode='55000'; end if;

  for v_attachment in select (value #>> '{}')::uuid from jsonb_array_elements(coalesce(p_attachment_refs,'[]'::jsonb)) loop
    if not exists(select 1 from atlas.communication_outbound_attachments a where a.id=v_attachment and a.communication_endpoint_id=v_endpoint.id and a.attachment_state='ready') then raise exception 'Every outbound attachment must be ready and belong to the sending endpoint.' using errcode='22023'; end if;
    v_attachment_count:=v_attachment_count+1;
  end loop;

  if v_conv_id is null then
    v_stable:='outbound-intent:'||v_operation_id::text;
    insert into atlas.institutional_conversations(organization_id,organization_unit_id,stable_key,subject,opened_at,last_activity_at,metadata)
    values(v_endpoint.organization_id,v_endpoint.organization_unit_id,v_stable,nullif(btrim(coalesce(p_subject,'')),''),now(),now(),jsonb_build_object('createdFromOutboundIntent',true,'initiatedByMembershipId',v_member.id)) returning id into v_conv_id;
    insert into atlas.institutional_conversation_endpoints(institutional_conversation_id,communication_endpoint_id,endpoint_role) values(v_conv_id,v_endpoint.id,'primary');
  else
    select * into v_conv from atlas.institutional_conversations where id=v_conv_id and organization_id=v_endpoint.organization_id and organization_unit_id is not distinct from v_endpoint.organization_unit_id and conversation_state='open';
    if v_conv.id is null then raise exception 'Institutional conversation is outside endpoint scope or not open.' using errcode='42501'; end if;
    if not exists(select 1 from atlas.institutional_conversation_endpoints ce where ce.institutional_conversation_id=v_conv_id and ce.communication_endpoint_id=v_endpoint.id) then raise exception 'Conversation is not associated with the sending endpoint.' using errcode='42501'; end if;
  end if;

  select * into v_case from atlas.institutional_conversation_response_cases where institutional_conversation_id=v_conv_id and case_state not in ('complete','informational') order by case_number desc limit 1;
  if v_case.id is not null then
    select * into v_binding from atlas.institutional_conversation_response_work_bindings where response_case_id=v_case.id;
    if v_binding.id is not null then
      select * into v_current from atlas.work_allocations where work_item_id=v_binding.work_item_id and allocation_role='responsible' and state='active' limit 1;
      select exists(select 1 from atlas.work_allocations a where a.work_item_id=v_binding.work_item_id and a.assignee_membership_id=v_member.id and a.allocation_role in ('participant','approver') and a.state='active') into v_is_collaborator;
    end if;
    if v_current.id is not null and v_current.assignee_membership_id is distinct from v_member.id and not v_is_collaborator and not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'admin') then raise exception 'Another member currently owns this conversation response. Join the response work or receive a handoff before sending.' using errcode='42501'; end if;
    if v_current.id is null and v_case.case_state='unclaimed' and not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'claim') then raise exception 'Claim authority is required to answer an unclaimed conversation.' using errcode='42501'; end if;
  end if;

  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('endpointId',v_endpoint.id,'conversationId',v_conv_id,'to',coalesce(p_to_recipients,'[]'::jsonb),'cc',coalesce(p_cc_recipients,'[]'::jsonb),'bcc',coalesce(p_bcc_recipients,'[]'::jsonb),'subject',p_subject,'bodyText',p_body_text,'bodyHtml',p_body_html,'attachments',coalesce(p_attachment_refs,'[]'::jsonb),'replyToCommunicationEventId',p_reply_to_communication_event_id)::text,'UTF8'),'sha256'),'hex');
  insert into atlas.communication_outbound_operations(id,organization_id,organization_unit_id,communication_endpoint_id,institutional_conversation_id,connected_source_id,initiated_by_membership_id,to_recipients,cc_recipients,bcc_recipients,subject,body_text,body_html,attachment_refs,reply_to_communication_event_id,idempotency_key,content_sha256,operation_state,metadata)
  values(v_operation_id,v_endpoint.organization_id,v_endpoint.organization_unit_id,v_endpoint.id,v_conv_id,v_source_id,v_member.id,coalesce(p_to_recipients,'[]'::jsonb),coalesce(p_cc_recipients,'[]'::jsonb),coalesce(p_bcc_recipients,'[]'::jsonb),p_subject,p_body_text,p_body_html,coalesce(p_attachment_refs,'[]'::jsonb),p_reply_to_communication_event_id,v_key,v_hash,'authorized',jsonb_build_object('authorizationSource',p_authorization_source,'actorUserId',v_member.user_id,'responseCollaborator',v_is_collaborator,'attachmentCount',v_attachment_count))
  on conflict(organization_id,idempotency_key) do nothing;
  select id into strict v_operation_id from atlas.communication_outbound_operations where organization_id=v_endpoint.organization_id and idempotency_key=v_key;
  return jsonb_build_object('contractVersion','institutional_email_send_intent_v2','outboundOperationId',v_operation_id,'institutionalConversationId',v_conv_id,'communicationEndpointId',v_endpoint.id,'connectedSourceId',v_source_id,'operationState','authorized','initiatedByMembershipId',v_member.id,'contentSha256',v_hash);
end;
$$;
revoke all on function atlas.prepare_institutional_email_send_internal_v2(uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text,text) from public,anon,authenticated;

create or replace function atlas.prepare_institutional_email_send_self_api_v1(
  p_communication_endpoint_id uuid,p_institutional_conversation_id uuid,p_to_recipients jsonb,p_cc_recipients jsonb default '[]'::jsonb,p_bcc_recipients jsonb default '[]'::jsonb,p_subject text default null,p_body_text text default null,p_body_html text default null,p_attachment_refs jsonb default '[]'::jsonb,p_reply_to_communication_event_id uuid default null,p_idempotency_key text default null
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $$
declare v_endpoint atlas.communication_endpoints%rowtype; v_member atlas.organization_memberships%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_endpoint from atlas.communication_endpoints where id=p_communication_endpoint_id and endpoint_state='active';
  if v_endpoint.id is null then raise exception 'Communication endpoint not found.' using errcode='P0002'; end if;
  select * into v_member from atlas.organization_memberships where organization_id=v_endpoint.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_member.id is null then raise exception 'Active organization membership required.' using errcode='42501'; end if;
  return atlas.prepare_institutional_email_send_internal_v2(v_member.id,p_communication_endpoint_id,p_institutional_conversation_id,p_to_recipients,p_cc_recipients,p_bcc_recipients,p_subject,p_body_text,p_body_html,p_attachment_refs,p_reply_to_communication_event_id,p_idempotency_key,'explicit_authenticated_send_command');
end;
$$;

-- ---------------------------------------------------------------------------
-- Durable drafts + send later
-- ---------------------------------------------------------------------------

create table atlas.communication_email_drafts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid,
  communication_endpoint_id uuid not null references atlas.communication_endpoints(id) on delete cascade,
  institutional_conversation_id uuid references atlas.institutional_conversations(id) on delete cascade,
  reply_to_communication_event_id uuid references atlas.communication_events(id) on delete set null,
  author_membership_id uuid not null,
  to_recipients jsonb not null default '[]'::jsonb,
  cc_recipients jsonb not null default '[]'::jsonb,
  bcc_recipients jsonb not null default '[]'::jsonb,
  subject text,
  body_text text,
  body_html text,
  attachment_refs jsonb not null default '[]'::jsonb,
  signature_id uuid references atlas.communication_email_signatures(id) on delete set null,
  send_after timestamptz,
  draft_state text not null default 'active',
  authorized_outbound_operation_id uuid references atlas.communication_outbound_operations(id) on delete set null,
  version integer not null default 1,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_email_drafts_author_org_fk foreign key(organization_id,author_membership_id) references atlas.organization_memberships(organization_id,id) on delete cascade,
  constraint communication_email_drafts_unit_org_fk foreign key(organization_id,organization_unit_id) references atlas.organization_units(organization_id,id) on delete restrict,
  constraint communication_email_drafts_state_check check(draft_state in ('active','scheduled','discarded','authorized')),
  constraint communication_email_drafts_recipient_arrays check(jsonb_typeof(to_recipients)='array' and jsonb_typeof(cc_recipients)='array' and jsonb_typeof(bcc_recipients)='array' and jsonb_typeof(attachment_refs)='array'),
  constraint communication_email_drafts_metadata_object check(jsonb_typeof(metadata)='object'),
  constraint communication_email_drafts_version_positive check(version>0)
);
create index communication_email_drafts_author_state_idx on atlas.communication_email_drafts(author_membership_id,draft_state,updated_at desc);
create index communication_email_drafts_conversation_idx on atlas.communication_email_drafts(institutional_conversation_id,updated_at desc) where institutional_conversation_id is not null;
create index communication_email_drafts_schedule_idx on atlas.communication_email_drafts(send_after) where draft_state='scheduled';
revoke all on atlas.communication_email_drafts from anon,authenticated;

create or replace function atlas.save_communication_email_draft_self_api_v1(
  p_draft_id uuid,p_communication_endpoint_id uuid,p_institutional_conversation_id uuid,p_reply_to_communication_event_id uuid,
  p_to_recipients jsonb,p_cc_recipients jsonb,p_bcc_recipients jsonb,p_subject text,p_body_text text,p_body_html text,
  p_attachment_refs jsonb,p_signature_id uuid,p_send_after timestamptz,p_metadata jsonb default '{}'::jsonb
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $$
declare v_endpoint atlas.communication_endpoints%rowtype; v_member atlas.organization_memberships%rowtype; v_id uuid:=coalesce(p_draft_id,gen_random_uuid()); v_state text; v_row atlas.communication_email_drafts%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_endpoint from atlas.communication_endpoints where id=p_communication_endpoint_id and endpoint_state='active';
  if v_endpoint.id is null or v_endpoint.endpoint_kind<>'email' then raise exception 'Active email endpoint required.' using errcode='P0002'; end if;
  select * into v_member from atlas.organization_memberships where organization_id=v_endpoint.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'send') then raise exception 'Communication endpoint send authority required.' using errcode='42501'; end if;
  if jsonb_typeof(coalesce(p_to_recipients,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(p_cc_recipients,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(p_bcc_recipients,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(p_attachment_refs,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then raise exception 'Draft recipients, attachments, and metadata must be valid JSON containers.' using errcode='22023'; end if;
  if p_institutional_conversation_id is not null and not exists(select 1 from atlas.institutional_conversation_endpoints ce where ce.institutional_conversation_id=p_institutional_conversation_id and ce.communication_endpoint_id=v_endpoint.id) then raise exception 'Draft conversation is not associated with this endpoint.' using errcode='42501'; end if;
  if p_reply_to_communication_event_id is not null and (p_institutional_conversation_id is null or not exists(select 1 from atlas.institutional_conversation_messages m where m.institutional_conversation_id=p_institutional_conversation_id and m.communication_event_id=p_reply_to_communication_event_id)) then raise exception 'Reply target must belong to the draft conversation.' using errcode='22023'; end if;
  if p_signature_id is not null and not exists(select 1 from atlas.communication_email_signatures s where s.id=p_signature_id and s.communication_endpoint_id=v_endpoint.id and s.active and (s.owner_membership_id is null or s.owner_membership_id=v_member.id)) then raise exception 'Signature is not available to this sender.' using errcode='22023'; end if;
  v_state:=case when p_send_after is not null and p_send_after>now() then 'scheduled' else 'active' end;

  if p_draft_id is not null then
    select * into v_row from atlas.communication_email_drafts where id=p_draft_id for update;
    if v_row.id is null or v_row.author_membership_id<>v_member.id then raise exception 'Draft not found for this author.' using errcode='P0002'; end if;
    if v_row.draft_state in ('discarded','authorized') then raise exception 'Finalized draft cannot be edited.' using errcode='55000'; end if;
  end if;

  insert into atlas.communication_email_drafts(id,organization_id,organization_unit_id,communication_endpoint_id,institutional_conversation_id,reply_to_communication_event_id,author_membership_id,to_recipients,cc_recipients,bcc_recipients,subject,body_text,body_html,attachment_refs,signature_id,send_after,draft_state,metadata)
  values(v_id,v_endpoint.organization_id,v_endpoint.organization_unit_id,v_endpoint.id,p_institutional_conversation_id,p_reply_to_communication_event_id,v_member.id,coalesce(p_to_recipients,'[]'::jsonb),coalesce(p_cc_recipients,'[]'::jsonb),coalesce(p_bcc_recipients,'[]'::jsonb),nullif(p_subject,''),p_body_text,p_body_html,coalesce(p_attachment_refs,'[]'::jsonb),p_signature_id,p_send_after,v_state,coalesce(p_metadata,'{}'::jsonb))
  on conflict(id) do update set institutional_conversation_id=excluded.institutional_conversation_id,reply_to_communication_event_id=excluded.reply_to_communication_event_id,to_recipients=excluded.to_recipients,cc_recipients=excluded.cc_recipients,bcc_recipients=excluded.bcc_recipients,subject=excluded.subject,body_text=excluded.body_text,body_html=excluded.body_html,attachment_refs=excluded.attachment_refs,signature_id=excluded.signature_id,send_after=excluded.send_after,draft_state=excluded.draft_state,metadata=excluded.metadata,version=atlas.communication_email_drafts.version+1,updated_at=now()
  returning * into v_row;
  return jsonb_build_object('contractVersion','communication_email_draft_v1','draftId',v_row.id,'state',v_row.draft_state,'version',v_row.version,'updatedAt',v_row.updated_at,'sendAfter',v_row.send_after);
end;
$$;

create or replace function atlas.discard_communication_email_draft_self_api_v1(p_draft_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $$
declare v_row atlas.communication_email_drafts%rowtype; v_member atlas.organization_memberships%rowtype;
begin
 if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
 select * into v_row from atlas.communication_email_drafts where id=p_draft_id for update;
 if v_row.id is null then raise exception 'Draft not found.' using errcode='P0002'; end if;
 select * into v_member from atlas.organization_memberships where id=v_row.author_membership_id and user_id=auth.uid() and active;
 if v_member.id is null then raise exception 'Only the draft author may discard it.' using errcode='42501'; end if;
 if v_row.draft_state='authorized' then raise exception 'Authorized draft cannot be discarded.' using errcode='55000'; end if;
 update atlas.communication_email_drafts set draft_state='discarded',send_after=null,updated_at=now() where id=v_row.id;
 return jsonb_build_object('contractVersion','communication_email_draft_discard_v1','draftId',v_row.id,'state','discarded');
end;
$$;

create or replace function atlas.authorize_communication_email_draft_self_api_v1(p_draft_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $$
declare v_row atlas.communication_email_drafts%rowtype; v_member atlas.organization_memberships%rowtype; v_signature atlas.communication_email_signatures%rowtype; v_body text; v_result jsonb; v_operation_id uuid;
begin
 if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
 select * into v_row from atlas.communication_email_drafts where id=p_draft_id for update;
 if v_row.id is null then raise exception 'Draft not found.' using errcode='P0002'; end if;
 select * into v_member from atlas.organization_memberships where id=v_row.author_membership_id and user_id=auth.uid() and active;
 if v_member.id is null then raise exception 'Only the draft author may send it.' using errcode='42501'; end if;
 if v_row.draft_state='authorized' then return jsonb_build_object('contractVersion','communication_email_draft_authorize_v1','draftId',v_row.id,'outboundOperationId',v_row.authorized_outbound_operation_id,'deduplicated',true); end if;
 if v_row.draft_state='discarded' then raise exception 'Discarded draft cannot be sent.' using errcode='55000'; end if;
 if jsonb_array_length(v_row.to_recipients)<1 then raise exception 'At least one To recipient is required.' using errcode='22023'; end if;
 v_body:=coalesce(v_row.body_text,'');
 if v_row.signature_id is not null then select * into v_signature from atlas.communication_email_signatures where id=v_row.signature_id and active; if v_signature.id is not null and btrim(v_signature.body_text)<>'' then v_body:=rtrim(v_body)||E'\n\n'||v_signature.body_text; end if; end if;
 v_result:=atlas.prepare_institutional_email_send_internal_v2(v_member.id,v_row.communication_endpoint_id,v_row.institutional_conversation_id,v_row.to_recipients,v_row.cc_recipients,v_row.bcc_recipients,v_row.subject,v_body,v_row.body_html,v_row.attachment_refs,v_row.reply_to_communication_event_id,'draft:'||v_row.id::text,'draft_send_now');
 v_operation_id:=(v_result->>'outboundOperationId')::uuid;
 update atlas.communication_email_drafts set draft_state='authorized',send_after=null,authorized_outbound_operation_id=v_operation_id,updated_at=now() where id=v_row.id;
 return v_result||jsonb_build_object('contractVersion','communication_email_draft_authorize_v1','draftId',v_row.id,'deduplicated',false);
end;
$$;

create or replace function atlas.communication_email_drafts_self_v1(p_communication_endpoint_id uuid,p_institutional_conversation_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $$
declare v_endpoint atlas.communication_endpoints%rowtype; v_member atlas.organization_memberships%rowtype; v_items jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
 select * into v_endpoint from atlas.communication_endpoints where id=p_communication_endpoint_id and endpoint_state='active';
 select * into v_member from atlas.organization_memberships where organization_id=v_endpoint.organization_id and user_id=auth.uid() and active order by created_at limit 1;
 if v_endpoint.id is null or v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'view') then raise exception 'Communication endpoint view authority required.' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('draftId',d.id,'conversationId',d.institutional_conversation_id,'replyToCommunicationEventId',d.reply_to_communication_event_id,'authorMembershipId',d.author_membership_id,'authorLabel',coalesce(up.display_name,u.email,d.author_membership_id::text),'isMine',d.author_membership_id=v_member.id,'to',case when d.author_membership_id=v_member.id then d.to_recipients else '[]'::jsonb end,'cc',case when d.author_membership_id=v_member.id then d.cc_recipients else '[]'::jsonb end,'bcc',case when d.author_membership_id=v_member.id then d.bcc_recipients else '[]'::jsonb end,'subject',d.subject,'bodyText',case when d.author_membership_id=v_member.id then d.body_text else null end,'attachmentRefs',case when d.author_membership_id=v_member.id then d.attachment_refs else '[]'::jsonb end,'signatureId',case when d.author_membership_id=v_member.id then d.signature_id else null end,'sendAfter',d.send_after,'state',d.draft_state,'version',d.version,'updatedAt',d.updated_at) order by d.updated_at desc),'[]'::jsonb) into v_items
 from atlas.communication_email_drafts d join atlas.organization_memberships om on om.id=d.author_membership_id left join auth.users u on u.id=om.user_id left join atlas.user_profiles up on up.user_id=om.user_id
 where d.communication_endpoint_id=v_endpoint.id and d.draft_state in ('active','scheduled') and (p_institutional_conversation_id is null or d.institutional_conversation_id=p_institutional_conversation_id);
 return jsonb_build_object('contractVersion','communication_email_drafts_v1','items',v_items);
end;
$$;

create or replace function atlas.release_due_communication_email_drafts_service_v1(p_limit integer default 50)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $$
declare v_row atlas.communication_email_drafts%rowtype; v_signature atlas.communication_email_signatures%rowtype; v_body text; v_result jsonb; v_released integer:=0; v_failed integer:=0;
begin
 if p_limit<1 or p_limit>500 then raise exception 'Limit must be between 1 and 500.' using errcode='22023'; end if;
 for v_row in select * from atlas.communication_email_drafts where draft_state='scheduled' and send_after<=now() order by send_after,id for update skip locked limit p_limit loop
   begin
     v_body:=coalesce(v_row.body_text,'');
     if v_row.signature_id is not null then select * into v_signature from atlas.communication_email_signatures where id=v_row.signature_id and active; if v_signature.id is not null and btrim(v_signature.body_text)<>'' then v_body:=rtrim(v_body)||E'\n\n'||v_signature.body_text; end if; end if;
     v_result:=atlas.prepare_institutional_email_send_internal_v2(v_row.author_membership_id,v_row.communication_endpoint_id,v_row.institutional_conversation_id,v_row.to_recipients,v_row.cc_recipients,v_row.bcc_recipients,v_row.subject,v_body,v_row.body_html,v_row.attachment_refs,v_row.reply_to_communication_event_id,'draft:'||v_row.id::text,'scheduled_draft_release');
     update atlas.communication_email_drafts set draft_state='authorized',authorized_outbound_operation_id=(v_result->>'outboundOperationId')::uuid,updated_at=now(),metadata=metadata-'lastScheduleError' where id=v_row.id;
     v_released:=v_released+1;
   exception when others then
     update atlas.communication_email_drafts set metadata=metadata||jsonb_build_object('lastScheduleError',sqlerrm,'lastScheduleAttemptAt',now()),updated_at=now() where id=v_row.id;
     v_failed:=v_failed+1;
   end;
 end loop;
 return jsonb_build_object('contractVersion','communication_email_draft_release_v1','released',v_released,'failed',v_failed);
end;
$$;
revoke all on function atlas.release_due_communication_email_drafts_service_v1(integer) from public,anon,authenticated;

-- ---------------------------------------------------------------------------
-- Mailbox disposition + endpoint sender spam rules
-- ---------------------------------------------------------------------------

create table atlas.institutional_conversation_disposition_events (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references atlas.organizations(id) on delete restrict,
 institutional_conversation_id uuid not null references atlas.institutional_conversations(id) on delete cascade,
 communication_endpoint_id uuid not null references atlas.communication_endpoints(id) on delete cascade,
 disposition text not null, actor_membership_id uuid not null, reason text, metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now(),
 constraint institutional_conversation_disposition_events_actor_org_fk foreign key(organization_id,actor_membership_id) references atlas.organization_memberships(organization_id,id) on delete restrict,
 constraint institutional_conversation_disposition_events_disposition_check check(disposition in ('inbox','archive','trash','spam')),
 constraint institutional_conversation_disposition_events_metadata_object check(jsonb_typeof(metadata)='object')
);
create index institutional_conversation_disposition_events_latest_idx on atlas.institutional_conversation_disposition_events(institutional_conversation_id,created_at desc,id desc);
revoke all on atlas.institutional_conversation_disposition_events from anon,authenticated;

create table atlas.communication_endpoint_sender_rules (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references atlas.organizations(id) on delete restrict,
 communication_endpoint_id uuid not null references atlas.communication_endpoints(id) on delete cascade,
 address_normalized text not null, rule_kind text not null, rule_state text not null default 'active', created_by_membership_id uuid not null,
 metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 constraint communication_endpoint_sender_rules_creator_org_fk foreign key(organization_id,created_by_membership_id) references atlas.organization_memberships(organization_id,id) on delete restrict,
 constraint communication_endpoint_sender_rules_kind_check check(rule_kind='spam'), constraint communication_endpoint_sender_rules_state_check check(rule_state in ('active','revoked')),
 constraint communication_endpoint_sender_rules_address_nonblank check(btrim(address_normalized)<>''), constraint communication_endpoint_sender_rules_metadata_object check(jsonb_typeof(metadata)='object')
);
create unique index communication_endpoint_sender_rules_active_uq on atlas.communication_endpoint_sender_rules(communication_endpoint_id,address_normalized,rule_kind) where rule_state='active';
revoke all on atlas.communication_endpoint_sender_rules from anon,authenticated;

create or replace function atlas.set_institutional_conversation_disposition_self_api_v1(p_institutional_conversation_id uuid,p_disposition text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $$
declare v_conv atlas.institutional_conversations%rowtype; v_endpoint_id uuid; v_member atlas.organization_memberships%rowtype; v_sender text;
begin
 if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
 if p_disposition not in ('inbox','archive','trash','spam') then raise exception 'Invalid mailbox disposition.' using errcode='22023'; end if;
 select * into v_conv from atlas.institutional_conversations where id=p_institutional_conversation_id;
 if v_conv.id is null then raise exception 'Institutional conversation not found.' using errcode='P0002'; end if;
 select communication_endpoint_id into v_endpoint_id from atlas.institutional_conversation_endpoints where institutional_conversation_id=v_conv.id order by case endpoint_role when 'primary' then 0 else 1 end,created_at limit 1;
 select * into v_member from atlas.organization_memberships where organization_id=v_conv.organization_id and user_id=auth.uid() and active order by created_at limit 1;
 if v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_member.id,'close') then raise exception 'Communication close authority required to change shared mailbox disposition.' using errcode='42501'; end if;
 insert into atlas.institutional_conversation_disposition_events(organization_id,institutional_conversation_id,communication_endpoint_id,disposition,actor_membership_id,reason)
 values(v_conv.organization_id,v_conv.id,v_endpoint_id,p_disposition,v_member.id,nullif(btrim(coalesce(p_reason,'')),''));
 if p_disposition='spam' then
   select p.address_normalized into v_sender from atlas.institutional_conversation_messages m join atlas.communication_event_participants p on p.communication_event_id=m.communication_event_id and p.participant_role='sender' and not p.is_self where m.institutional_conversation_id=v_conv.id order by m.occurred_at desc nulls last,m.created_at desc limit 1;
   if v_sender is not null then insert into atlas.communication_endpoint_sender_rules(organization_id,communication_endpoint_id,address_normalized,rule_kind,created_by_membership_id,metadata) values(v_conv.organization_id,v_endpoint_id,v_sender,'spam',v_member.id,jsonb_build_object('sourceConversationId',v_conv.id)) on conflict(communication_endpoint_id,address_normalized,rule_kind) where rule_state='active' do update set updated_at=now(),metadata=atlas.communication_endpoint_sender_rules.metadata||excluded.metadata; end if;
 elsif p_disposition='inbox' then
   select p.address_normalized into v_sender from atlas.institutional_conversation_messages m join atlas.communication_event_participants p on p.communication_event_id=m.communication_event_id and p.participant_role='sender' and not p.is_self where m.institutional_conversation_id=v_conv.id order by m.occurred_at desc nulls last,m.created_at desc limit 1;
   if v_sender is not null then update atlas.communication_endpoint_sender_rules set rule_state='revoked',updated_at=now() where communication_endpoint_id=v_endpoint_id and address_normalized=v_sender and rule_kind='spam' and rule_state='active'; end if;
 end if;
 return jsonb_build_object('contractVersion','institutional_conversation_disposition_v1','conversationId',v_conv.id,'disposition',p_disposition);
end;
$$;

-- ---------------------------------------------------------------------------
-- Search + disposition-aware inbox
-- ---------------------------------------------------------------------------

create or replace function atlas.institutional_shared_inbox_self_v3(p_communication_endpoint_id uuid,p_limit integer default 200)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $$
declare v_payload jsonb; v_items jsonb;
begin
 v_payload:=atlas.institutional_shared_inbox_self_v2(p_communication_endpoint_id,p_limit);
 select coalesce(jsonb_agg(item||jsonb_build_object('disposition',coalesce(disposition,'inbox')) order by item->>'last_activity_at' desc),'[]'::jsonb) into v_items
 from (
   select value as item,
     coalesce((select e.disposition from atlas.institutional_conversation_disposition_events e where e.institutional_conversation_id=(value->>'institutional_conversation_id')::uuid order by e.created_at desc,e.id desc limit 1),
       case when exists(select 1 from atlas.communication_endpoint_sender_rules r where r.communication_endpoint_id=p_communication_endpoint_id and r.rule_kind='spam' and r.rule_state='active' and r.address_normalized=lower(coalesce(value->>'last_message_speaker_address',''))) then 'spam' else 'inbox' end) as disposition
   from jsonb_array_elements(coalesce(v_payload->'items','[]'::jsonb))
 ) q;
 return (v_payload-'contractVersion'-'items')||jsonb_build_object('contractVersion','institutional_shared_inbox_v3','items',v_items);
end;
$$;

create or replace function atlas.institutional_correspondence_search_self_api_v1(p_query text,p_communication_endpoint_id uuid default null,p_filters jsonb default '{}'::jsonb,p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $$
declare v_query text:=btrim(coalesce(p_query,'')); v_filters jsonb:=coalesce(p_filters,'{}'::jsonb); v_member atlas.organization_memberships%rowtype; v_items jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
 if p_limit<1 or p_limit>500 then raise exception 'Search limit must be between 1 and 500.' using errcode='22023'; end if;
 if jsonb_typeof(v_filters)<>'object' then raise exception 'Search filters must be an object.' using errcode='22023'; end if;
 select * into v_member from atlas.organization_memberships where user_id=auth.uid() and active and (p_communication_endpoint_id is null or organization_id=(select organization_id from atlas.communication_endpoints where id=p_communication_endpoint_id)) order by created_at limit 1;
 if v_member.id is null then raise exception 'Active organization membership required.' using errcode='42501'; end if;

 with candidates as (
   select distinct c.id,c.subject,c.last_activity_at,ep.id as endpoint_id,ep.endpoint_kind,ep.display_name as endpoint_name,
     coalesce((select de.disposition from atlas.institutional_conversation_disposition_events de where de.institutional_conversation_id=c.id order by de.created_at desc,de.id desc limit 1),'inbox') as disposition,
     coalesce((select string_agg(coalesce(p.metadata->>'displayName','')||' '||p.address,' ') from atlas.institutional_conversation_messages im join atlas.communication_event_participants p on p.communication_event_id=im.communication_event_id where im.institutional_conversation_id=c.id),'') as participant_text,
     coalesce((select string_agg(coalesce(e.body,''),' ') from atlas.institutional_conversation_messages im join atlas.communication_events e on e.id=im.communication_event_id where im.institutional_conversation_id=c.id),'') as body_text,
     coalesce((select string_agg(coalesce(a.transfer_name,''),' ') from atlas.institutional_conversation_messages im join atlas.communication_attachments a on a.event_id=im.communication_event_id where im.institutional_conversation_id=c.id),'') as attachment_text,
     coalesce((select string_agg(w.title||' '||coalesce(w.instructions,''),' ') from atlas.communication_derived_work_links l join atlas.work_items w on w.id=l.work_item_id where l.institutional_conversation_id=c.id),'') as work_text,
     exists(select 1 from atlas.institutional_conversation_messages im join atlas.communication_attachments a on a.event_id=im.communication_event_id where im.institutional_conversation_id=c.id) as has_attachment
   from atlas.institutional_conversations c join atlas.institutional_conversation_endpoints ce on ce.institutional_conversation_id=c.id join atlas.communication_endpoints ep on ep.id=ce.communication_endpoint_id
   where ep.organization_id=v_member.organization_id and ep.endpoint_state='active' and (p_communication_endpoint_id is null or ep.id=p_communication_endpoint_id) and atlas.communication_endpoint_membership_has_capability_v1(ep.id,v_member.id,'view')
 ), ranked as (
   select *, case when v_query='' then 0 else ts_rank_cd(to_tsvector('simple',coalesce(subject,'')||' '||participant_text||' '||body_text||' '||attachment_text||' '||work_text),websearch_to_tsquery('simple',v_query)) end as rank
   from candidates
   where (v_query='' or to_tsvector('simple',coalesce(subject,'')||' '||participant_text||' '||body_text||' '||attachment_text||' '||work_text) @@ websearch_to_tsquery('simple',v_query))
     and (not(v_filters ? 'disposition') or disposition=v_filters->>'disposition')
     and (coalesce((v_filters->>'hasAttachment')::boolean,false)=false or has_attachment)
     and (not(v_filters ? 'dateFrom') or last_activity_at >= (v_filters->>'dateFrom')::timestamptz)
     and (not(v_filters ? 'dateTo') or last_activity_at <= (v_filters->>'dateTo')::timestamptz)
 )
 select coalesce(jsonb_agg(jsonb_build_object('conversationId',id,'endpointId',endpoint_id,'endpointKind',endpoint_kind,'endpointName',endpoint_name,'subject',subject,'lastActivityAt',last_activity_at,'disposition',disposition,'hasAttachment',has_attachment,'rank',rank) order by rank desc,last_activity_at desc),'[]'::jsonb) into v_items from (select * from ranked order by rank desc,last_activity_at desc limit p_limit) q;
 return jsonb_build_object('contractVersion','institutional_correspondence_search_v1','query',v_query,'items',v_items);
end;
$$;

-- ---------------------------------------------------------------------------
-- Attachment + delivery projections
-- ---------------------------------------------------------------------------

create or replace function atlas.institutional_conversation_delivery_self_v1(p_institutional_conversation_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $$
declare v_conv atlas.institutional_conversations%rowtype; v_endpoint_id uuid; v_member atlas.organization_memberships%rowtype; v_items jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
 select * into v_conv from atlas.institutional_conversations where id=p_institutional_conversation_id;
 if v_conv.id is null then raise exception 'Conversation not found.' using errcode='P0002'; end if;
 select communication_endpoint_id into v_endpoint_id from atlas.institutional_conversation_endpoints where institutional_conversation_id=v_conv.id order by case endpoint_role when 'primary' then 0 else 1 end,created_at limit 1;
 select * into v_member from atlas.organization_memberships where organization_id=v_conv.organization_id and user_id=auth.uid() and active order by created_at limit 1;
 if v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_member.id,'view') then raise exception 'Communication endpoint view authority required.' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('outboundOperationId',o.id,'communicationEventId',el.communication_event_id,'operationState',o.operation_state,'authorizedAt',o.authorized_at,'acceptedAt',o.accepted_at,'failedAt',o.failed_at,'initiatedByMembershipId',o.initiated_by_membership_id,'to',o.to_recipients,'cc',o.cc_recipients,'bcc',o.bcc_recipients,'subject',o.subject,'attachments',o.attachment_refs,'latestAttempt',la.attempt,'recipientResults',coalesce(la.recipients,'[]'::jsonb)) order by o.created_at),'[]'::jsonb) into v_items
 from atlas.communication_outbound_operations o left join atlas.communication_outbound_event_links el on el.outbound_operation_id=o.id
 left join lateral (
   select jsonb_build_object('attemptId',a.id,'attemptNumber',a.attempt_number,'resultState',a.result_state,'providerMessageRef',a.provider_message_ref,'attemptedAt',a.attempted_at) as attempt,
     (select coalesce(jsonb_agg(jsonb_build_object('role',r.recipient_role,'address',r.recipient_address,'resultState',r.result_state,'providerResponse',r.provider_response) order by r.recipient_role,r.recipient_address),'[]'::jsonb) from atlas.communication_outbound_attempt_recipients r where r.outbound_attempt_id=a.id) as recipients
   from atlas.communication_outbound_attempts a where a.outbound_operation_id=o.id order by a.attempt_number desc limit 1
 ) la on true where o.institutional_conversation_id=v_conv.id;
 return jsonb_build_object('contractVersion','institutional_conversation_delivery_v1','items',v_items);
end;
$$;

create or replace function atlas.communication_event_attachments_self_v1(p_communication_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $$
declare v_conv_id uuid; v_endpoint_id uuid; v_org uuid; v_member atlas.organization_memberships%rowtype; v_items jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
 select m.institutional_conversation_id,c.organization_id into v_conv_id,v_org from atlas.institutional_conversation_messages m join atlas.institutional_conversations c on c.id=m.institutional_conversation_id where m.communication_event_id=p_communication_event_id limit 1;
 if v_conv_id is null then raise exception 'Communication event is not in an institutional conversation.' using errcode='P0002'; end if;
 select communication_endpoint_id into v_endpoint_id from atlas.institutional_conversation_endpoints where institutional_conversation_id=v_conv_id order by case endpoint_role when 'primary' then 0 else 1 end,created_at limit 1;
 select * into v_member from atlas.organization_memberships where organization_id=v_org and user_id=auth.uid() and active order by created_at limit 1;
 if v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_member.id,'view') then raise exception 'Communication endpoint view authority required.' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('attachmentId',a.id,'fileName',a.transfer_name,'mimeType',a.mime_type,'contentHash',a.source_content_hash,'custodyLocator',a.custody_locator,'metadata',a.metadata) order by a.created_at),'[]'::jsonb) into v_items from atlas.communication_attachments a where a.event_id=p_communication_event_id;
 return jsonb_build_object('contractVersion','communication_event_attachments_v1','items',v_items);
end;
$$;

-- Public browser membranes.
create or replace function public.upsert_communication_email_signature_self_api_v1(p_signature_id uuid,p_communication_endpoint_id uuid,p_scope text,p_signature_name text,p_body_text text,p_body_html text default null,p_is_default boolean default false) returns jsonb language sql security invoker set search_path=pg_catalog,public,atlas as $$ select atlas.upsert_communication_email_signature_self_api_v1($1,$2,$3,$4,$5,$6,$7); $$;
create or replace function public.communication_email_signatures_self_v1(p_communication_endpoint_id uuid) returns jsonb language sql security invoker set search_path=pg_catalog,public,atlas as $$ select atlas.communication_email_signatures_self_v1($1); $$;
create or replace function public.save_communication_email_draft_self_api_v1(p_draft_id uuid,p_communication_endpoint_id uuid,p_institutional_conversation_id uuid,p_reply_to_communication_event_id uuid,p_to_recipients jsonb,p_cc_recipients jsonb,p_bcc_recipients jsonb,p_subject text,p_body_text text,p_body_html text,p_attachment_refs jsonb,p_signature_id uuid,p_send_after timestamptz,p_metadata jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path=pg_catalog,public,atlas as $$ select atlas.save_communication_email_draft_self_api_v1($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14); $$;
create or replace function public.discard_communication_email_draft_self_api_v1(p_draft_id uuid) returns jsonb language sql security invoker set search_path=pg_catalog,public,atlas as $$ select atlas.discard_communication_email_draft_self_api_v1($1); $$;
create or replace function public.authorize_communication_email_draft_self_api_v1(p_draft_id uuid) returns jsonb language sql security invoker set search_path=pg_catalog,public,atlas as $$ select atlas.authorize_communication_email_draft_self_api_v1($1); $$;
create or replace function public.communication_email_drafts_self_v1(p_communication_endpoint_id uuid,p_institutional_conversation_id uuid default null) returns jsonb language sql security invoker set search_path=pg_catalog,public,atlas as $$ select atlas.communication_email_drafts_self_v1($1,$2); $$;
create or replace function public.set_institutional_conversation_disposition_self_api_v1(p_institutional_conversation_id uuid,p_disposition text,p_reason text default null) returns jsonb language sql security invoker set search_path=pg_catalog,public,atlas as $$ select atlas.set_institutional_conversation_disposition_self_api_v1($1,$2,$3); $$;
create or replace function public.institutional_shared_inbox_self_v3(p_communication_endpoint_id uuid,p_limit integer default 200) returns jsonb language sql security invoker set search_path=pg_catalog,public,atlas as $$ select atlas.institutional_shared_inbox_self_v3($1,$2); $$;
create or replace function public.institutional_correspondence_search_self_api_v1(p_query text,p_communication_endpoint_id uuid default null,p_filters jsonb default '{}'::jsonb,p_limit integer default 100) returns jsonb language sql security invoker set search_path=pg_catalog,public,atlas as $$ select atlas.institutional_correspondence_search_self_api_v1($1,$2,$3,$4); $$;
create or replace function public.institutional_conversation_delivery_self_v1(p_institutional_conversation_id uuid) returns jsonb language sql security invoker set search_path=pg_catalog,public,atlas as $$ select atlas.institutional_conversation_delivery_self_v1($1); $$;
create or replace function public.communication_event_attachments_self_v1(p_communication_event_id uuid) returns jsonb language sql security invoker set search_path=pg_catalog,public,atlas as $$ select atlas.communication_event_attachments_self_v1($1); $$;
create or replace function public.prepare_communication_outbound_attachment_self_api_v1(p_communication_endpoint_id uuid,p_file_name text,p_mime_type text default null,p_metadata jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path=pg_catalog,public,atlas as $$ select atlas.prepare_communication_outbound_attachment_self_api_v1($1,$2,$3,$4); $$;
create or replace function public.confirm_communication_outbound_attachment_self_api_v1(p_attachment_id uuid,p_sha256 text,p_byte_length bigint) returns jsonb language sql security invoker set search_path=pg_catalog,public,atlas as $$ select atlas.confirm_communication_outbound_attachment_self_api_v1($1,$2,$3); $$;

revoke all on function public.upsert_communication_email_signature_self_api_v1(uuid,uuid,text,text,text,text,boolean) from public,anon; grant execute on function public.upsert_communication_email_signature_self_api_v1(uuid,uuid,text,text,text,text,boolean) to authenticated,service_role;
revoke all on function public.communication_email_signatures_self_v1(uuid) from public,anon; grant execute on function public.communication_email_signatures_self_v1(uuid) to authenticated,service_role;
revoke all on function public.save_communication_email_draft_self_api_v1(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb) from public,anon; grant execute on function public.save_communication_email_draft_self_api_v1(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb) to authenticated,service_role;
revoke all on function public.discard_communication_email_draft_self_api_v1(uuid) from public,anon; grant execute on function public.discard_communication_email_draft_self_api_v1(uuid) to authenticated,service_role;
revoke all on function public.authorize_communication_email_draft_self_api_v1(uuid) from public,anon; grant execute on function public.authorize_communication_email_draft_self_api_v1(uuid) to authenticated,service_role;
revoke all on function public.communication_email_drafts_self_v1(uuid,uuid) from public,anon; grant execute on function public.communication_email_drafts_self_v1(uuid,uuid) to authenticated,service_role;
revoke all on function public.set_institutional_conversation_disposition_self_api_v1(uuid,text,text) from public,anon; grant execute on function public.set_institutional_conversation_disposition_self_api_v1(uuid,text,text) to authenticated,service_role;
revoke all on function public.institutional_shared_inbox_self_v3(uuid,integer) from public,anon; grant execute on function public.institutional_shared_inbox_self_v3(uuid,integer) to authenticated,service_role;
revoke all on function public.institutional_correspondence_search_self_api_v1(text,uuid,jsonb,integer) from public,anon; grant execute on function public.institutional_correspondence_search_self_api_v1(text,uuid,jsonb,integer) to authenticated,service_role;
revoke all on function public.institutional_conversation_delivery_self_v1(uuid) from public,anon; grant execute on function public.institutional_conversation_delivery_self_v1(uuid) to authenticated,service_role;
revoke all on function public.communication_event_attachments_self_v1(uuid) from public,anon; grant execute on function public.communication_event_attachments_self_v1(uuid) to authenticated,service_role;
revoke all on function public.prepare_communication_outbound_attachment_self_api_v1(uuid,text,text,jsonb) from public,anon; grant execute on function public.prepare_communication_outbound_attachment_self_api_v1(uuid,text,text,jsonb) to authenticated,service_role;
revoke all on function public.confirm_communication_outbound_attachment_self_api_v1(uuid,text,bigint) from public,anon; grant execute on function public.confirm_communication_outbound_attachment_self_api_v1(uuid,text,bigint) to authenticated,service_role;

-- Security-invoker public membranes need authenticated execution on their atlas targets.
grant execute on function atlas.upsert_communication_email_signature_self_api_v1(uuid,uuid,text,text,text,text,boolean) to authenticated,service_role;
grant execute on function atlas.communication_email_signatures_self_v1(uuid) to authenticated,service_role;
grant execute on function atlas.save_communication_email_draft_self_api_v1(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb) to authenticated,service_role;
grant execute on function atlas.discard_communication_email_draft_self_api_v1(uuid) to authenticated,service_role;
grant execute on function atlas.authorize_communication_email_draft_self_api_v1(uuid) to authenticated,service_role;
grant execute on function atlas.communication_email_drafts_self_v1(uuid,uuid) to authenticated,service_role;
grant execute on function atlas.set_institutional_conversation_disposition_self_api_v1(uuid,text,text) to authenticated,service_role;
grant execute on function atlas.institutional_shared_inbox_self_v3(uuid,integer) to authenticated,service_role;
grant execute on function atlas.institutional_correspondence_search_self_api_v1(text,uuid,jsonb,integer) to authenticated,service_role;
grant execute on function atlas.institutional_conversation_delivery_self_v1(uuid) to authenticated,service_role;
grant execute on function atlas.communication_event_attachments_self_v1(uuid) to authenticated,service_role;
grant execute on function atlas.prepare_communication_outbound_attachment_self_api_v1(uuid,text,text,jsonb) to authenticated,service_role;
grant execute on function atlas.confirm_communication_outbound_attachment_self_api_v1(uuid,text,bigint) to authenticated,service_role;

commit;