begin;

create table atlas.communication_raw_message_custody (
  id uuid primary key default gen_random_uuid(),
  communication_event_id uuid not null unique references atlas.communication_events(id) on delete restrict,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  raw_mime_sha256 text not null check (raw_mime_sha256 ~ '^[0-9a-f]{64}$'),
  byte_length bigint check (byte_length is null or byte_length>=0),
  storage_locator text,
  custody_state text not null default 'hash_only' check (custody_state in ('stored','hash_only','missing')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  recorded_at timestamptz not null default now()
);
comment on table atlas.communication_raw_message_custody is 'Custody evidence for the original RFC/MIME source message. Parsed Communication Event fields remain usable, while exact raw-message hash/storage permits future re-parsing without replacing source history.';

create table atlas.communication_outbound_operations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid,
  communication_endpoint_id uuid not null references atlas.communication_endpoints(id) on delete restrict,
  institutional_conversation_id uuid not null references atlas.institutional_conversations(id) on delete restrict,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  initiated_by_membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  operation_kind text not null default 'email_send' check (operation_kind in ('email_send')),
  to_recipients jsonb not null check (jsonb_typeof(to_recipients)='array'),
  cc_recipients jsonb not null default '[]'::jsonb check (jsonb_typeof(cc_recipients)='array'),
  bcc_recipients jsonb not null default '[]'::jsonb check (jsonb_typeof(bcc_recipients)='array'),
  subject text,
  body_text text,
  body_html text,
  attachment_refs jsonb not null default '[]'::jsonb check (jsonb_typeof(attachment_refs)='array'),
  reply_to_communication_event_id uuid references atlas.communication_events(id) on delete restrict,
  idempotency_key text not null check (btrim(idempotency_key)<>''),
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  operation_state text not null default 'authorized' check (operation_state in ('authorized','leased','accepted','temporary_failure','failed','cancelled')),
  lease_owner text,
  lease_expires_at timestamptz,
  authorized_at timestamptz not null default now(),
  accepted_at timestamptz,
  failed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,idempotency_key),
  foreign key (organization_id,organization_unit_id) references atlas.organization_units(organization_id,id) on delete restrict
);
create index communication_outbound_queue_idx on atlas.communication_outbound_operations(connected_source_id,operation_state,created_at,id);
comment on table atlas.communication_outbound_operations is 'Exact authorized institutional outbound communication operation. Human initiator, institution endpoint, exact recipients/content, provider transport, and delivery attempt are distinct. Provider connectivity alone never authorizes an operation.';

create table atlas.communication_outbound_attempts (
  id uuid primary key default gen_random_uuid(),
  outbound_operation_id uuid not null references atlas.communication_outbound_operations(id) on delete cascade,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  attempt_number integer not null check (attempt_number>0),
  result_state text not null check (result_state in ('accepted','temporary_failure','rejected','transport_error','unknown')),
  provider_message_ref text,
  provider_response jsonb not null default '{}'::jsonb check (jsonb_typeof(provider_response)='object'),
  attempted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique(outbound_operation_id,attempt_number)
);
comment on table atlas.communication_outbound_attempts is 'Append-only provider transport attempt evidence. SMTP acceptance is transport evidence, not recipient delivery/read truth.';

create table atlas.communication_outbound_event_links (
  id uuid primary key default gen_random_uuid(),
  outbound_operation_id uuid not null unique references atlas.communication_outbound_operations(id) on delete cascade,
  communication_event_id uuid not null unique references atlas.communication_events(id) on delete restrict,
  created_at timestamptz not null default now()
);

create or replace function atlas.prevent_communication_outbound_history_mutation_v1() returns trigger language plpgsql set search_path=pg_catalog,atlas as $function$
begin raise exception 'Communication outbound attempt/link/raw custody history is append-only.' using errcode='55000'; end;$function$;
create trigger communication_raw_message_custody_append_only_v1 before update or delete on atlas.communication_raw_message_custody for each row execute function atlas.prevent_communication_outbound_history_mutation_v1();
create trigger communication_outbound_attempts_append_only_v1 before update or delete on atlas.communication_outbound_attempts for each row execute function atlas.prevent_communication_outbound_history_mutation_v1();
create trigger communication_outbound_event_links_append_only_v1 before update or delete on atlas.communication_outbound_event_links for each row execute function atlas.prevent_communication_outbound_history_mutation_v1();

create or replace function atlas.guard_communication_outbound_operation_v1() returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_endpoint atlas.communication_endpoints%rowtype; v_conv atlas.institutional_conversations%rowtype; v_source atlas.connected_sources%rowtype; v_member atlas.organization_memberships%rowtype;
begin
  select * into v_endpoint from atlas.communication_endpoints where id=new.communication_endpoint_id;
  select * into v_conv from atlas.institutional_conversations where id=new.institutional_conversation_id;
  select * into v_source from atlas.connected_sources where id=new.connected_source_id;
  select * into v_member from atlas.organization_memberships where id=new.initiated_by_membership_id;
  if v_endpoint.id is null or v_conv.id is null or v_source.id is null or v_member.id is null then raise exception 'Outbound communication requires endpoint, conversation, source, and initiating membership.' using errcode='23514'; end if;
  if v_endpoint.organization_id is distinct from new.organization_id or v_endpoint.organization_unit_id is distinct from new.organization_unit_id or v_conv.organization_id is distinct from new.organization_id or v_conv.organization_unit_id is distinct from new.organization_unit_id or v_source.custodian_organization_id is distinct from new.organization_id or v_source.custodian_organization_unit_id is distinct from new.organization_unit_id or v_member.organization_id is distinct from new.organization_id then raise exception 'Outbound operation must share organization/unit custody.' using errcode='23514'; end if;
  if not exists(select 1 from atlas.communication_endpoint_source_bindings b where b.communication_endpoint_id=v_endpoint.id and b.connected_source_id=v_source.id and b.binding_state='active' and b.binding_role in ('send','send_receive')) then raise exception 'Outbound source is not an active send transport for endpoint.' using errcode='23514'; end if;
  new.updated_at:=now();
  return new;
end;$function$;
create trigger communication_outbound_operation_guard_v1 before insert or update on atlas.communication_outbound_operations for each row execute function atlas.guard_communication_outbound_operation_v1();

create or replace function atlas.configure_generic_email_endpoint_self_api_v1(
  p_organization_id uuid,p_organization_unit_id uuid,p_email_address text,p_display_name text,
  p_imap_host text,p_imap_port integer,p_imap_security text,
  p_smtp_host text,p_smtp_port integer,p_smtp_security text,
  p_username text,p_password text
) returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_endpoint_result jsonb; v_endpoint_id uuid; v_source_result jsonb; v_source_id uuid; v_member atlas.organization_memberships%rowtype; v_metadata jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_member from atlas.organization_memberships where organization_id=p_organization_id and user_id=auth.uid() and active and role='owner' order by created_at limit 1;
  if v_member.id is null then raise exception 'Organization owner authority required.' using errcode='42501'; end if;
  if btrim(coalesce(p_email_address,''))='' or btrim(coalesce(p_imap_host,''))='' or btrim(coalesce(p_smtp_host,''))='' or btrim(coalesce(p_username,''))='' or coalesce(p_password,'')='' then raise exception 'Email address, IMAP/SMTP hosts, username, and password are required.' using errcode='22023'; end if;
  if p_imap_port<1 or p_imap_port>65535 or p_smtp_port<1 or p_smtp_port>65535 then raise exception 'Mail transport ports are invalid.' using errcode='22023'; end if;
  if lower(btrim(coalesce(p_imap_security,''))) not in ('tls','ssl','starttls') or lower(btrim(coalesce(p_smtp_security,''))) not in ('tls','ssl','starttls') then raise exception 'Mail transport security must be TLS/SSL/STARTTLS.' using errcode='22023'; end if;
  v_endpoint_result:=atlas.upsert_communication_endpoint_self_api_v1(p_organization_id,p_organization_unit_id,'email',p_email_address,p_display_name,jsonb_build_object('transportClass','generic_imap_smtp'));
  v_endpoint_id:=(v_endpoint_result->>'communicationEndpointId')::uuid;
  v_metadata:=jsonb_build_object('transportClass','generic_imap_smtp','imap',jsonb_build_object('host',btrim(p_imap_host),'port',p_imap_port,'security',lower(btrim(p_imap_security))),'smtp',jsonb_build_object('host',btrim(p_smtp_host),'port',p_smtp_port,'security',lower(btrim(p_smtp_security))),'username',btrim(p_username));
  v_source_result:=atlas.register_organization_connected_source_self_api_v1(p_organization_id,'imap_smtp_email',atlas.normalize_communication_endpoint_address_v1('email',p_email_address),coalesce(nullif(btrim(p_display_name),''),p_email_address),p_email_address,'pending',array['mail.read','mail.send'],jsonb_build_object('communicationCapture',false,'communicationSend',false),v_metadata);
  v_source_id:=(v_source_result->>'sourceId')::uuid;
  perform atlas.store_connected_source_secret_service_v1(v_source_id,'mailbox_password',p_password,'Generic IMAP/SMTP mailbox password');
  perform atlas.bind_communication_endpoint_source_self_api_v1(v_endpoint_id,v_source_id,'send_receive',v_metadata);
  return jsonb_build_object('contractVersion','generic_email_endpoint_setup_v1','communicationEndpointId',v_endpoint_id,'connectedSourceId',v_source_id,'authorizationState','pending','credentialStored',true,'transport',v_metadata);
end;$function$;
comment on function atlas.configure_generic_email_endpoint_self_api_v1(uuid,uuid,text,text,text,integer,text,text,integer,text,text,text) is 'Owner setup seam for a generic IMAP/SMTP institutional email endpoint. Provider password is stored in Vault, never endpoint/source metadata. Source remains pending until the gateway proves transport authentication.';

create or replace function atlas.record_generic_email_transport_test_service_v1(p_connected_source_id uuid,p_imap_ok boolean,p_smtp_ok boolean,p_details jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_source atlas.connected_sources%rowtype; v_state text;
begin
  select * into v_source from atlas.connected_sources where id=p_connected_source_id and provider_key='imap_smtp_email' and custodian_organization_id is not null for update;
  if v_source.id is null then raise exception 'Generic institutional email source not found.' using errcode='P0002'; end if;
  v_state:=case when coalesce(p_imap_ok,false) and coalesce(p_smtp_ok,false) then 'connected' else 'error' end;
  update atlas.connected_sources set authorization_state=v_state,capabilities=capabilities||jsonb_build_object('communicationCapture',coalesce(p_imap_ok,false),'communicationSend',coalesce(p_smtp_ok,false)),metadata=metadata||jsonb_build_object('lastTransportTestAt',now(),'lastTransportTest',coalesce(p_details,'{}'::jsonb)),updated_at=now() where id=v_source.id;
  return jsonb_build_object('contractVersion','generic_email_transport_test_v1','connectedSourceId',v_source.id,'authorizationState',v_state,'imapOk',coalesce(p_imap_ok,false),'smtpOk',coalesce(p_smtp_ok,false));
end;$function$;

create or replace function atlas.generic_email_transport_config_service_v1(p_connected_source_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_source atlas.connected_sources%rowtype; v_password text; v_endpoint_id uuid;
begin
  select * into v_source from atlas.connected_sources where id=p_connected_source_id and provider_key='imap_smtp_email' and custodian_organization_id is not null and authorization_state<>'revoked';
  if v_source.id is null then raise exception 'Generic institutional email source not found.' using errcode='P0002'; end if;
  v_password:=atlas.read_connected_source_secret_service_v1(v_source.id,'mailbox_password');
  if v_password is null then raise exception 'Mailbox credential is missing.' using errcode='P0002'; end if;
  select communication_endpoint_id into v_endpoint_id from atlas.communication_endpoint_source_bindings where connected_source_id=v_source.id and binding_state='active' and binding_role in ('send_receive','receive','send') order by created_at limit 1;
  return jsonb_build_object('contractVersion','generic_email_transport_config_v1','connectedSourceId',v_source.id,'communicationEndpointId',v_endpoint_id,'organizationId',v_source.custodian_organization_id,'organizationUnitId',v_source.custodian_organization_unit_id,'providerAccountKey',v_source.provider_account_key,'authorizationState',v_source.authorization_state,'transport',v_source.metadata->'transportClass','mailConfig',jsonb_build_object('imap',v_source.metadata->'imap','smtp',v_source.metadata->'smtp','username',v_source.metadata->>'username','password',v_password));
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
  select count(*),min(b.connected_source_id) into v_source_count,v_source_id from atlas.communication_endpoint_source_bindings b join atlas.connected_sources s on s.id=b.connected_source_id where b.communication_endpoint_id=v_endpoint.id and b.binding_state='active' and b.binding_role in ('send','send_receive') and s.authorization_state='connected' and (s.capabilities @> '{"communicationSend":true}'::jsonb);
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
  select * into strict v_operation_id from (select id from atlas.communication_outbound_operations where organization_id=v_endpoint.organization_id and idempotency_key=v_key) q;
  return jsonb_build_object('contractVersion','institutional_email_send_intent_v1','outboundOperationId',v_operation_id,'institutionalConversationId',v_conv_id,'communicationEndpointId',v_endpoint.id,'connectedSourceId',v_source_id,'operationState','authorized','initiatedByMembershipId',v_member.id,'contentSha256',v_hash);
end;$function$;

create or replace function atlas.lease_communication_outbound_operations_service_v1(p_connected_source_id uuid,p_lease_owner text,p_limit integer default 20,p_lease_seconds integer default 120)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_items jsonb;
begin
  if btrim(coalesce(p_lease_owner,''))='' or p_limit<1 or p_limit>100 or p_lease_seconds<30 or p_lease_seconds>600 then raise exception 'Valid lease owner, limit, and lease seconds are required.' using errcode='22023'; end if;
  if not exists(select 1 from atlas.connected_sources s where s.id=p_connected_source_id and s.authorization_state='connected' and s.custodian_organization_id is not null and (s.capabilities @> '{"communicationSend":true}'::jsonb)) then raise exception 'Connected institutional send source required.' using errcode='42501'; end if;
  with candidates as (
    select id from atlas.communication_outbound_operations where connected_source_id=p_connected_source_id and (operation_state='authorized' or (operation_state='leased' and lease_expires_at<now())) order by created_at,id for update skip locked limit p_limit
  ), leased as (
    update atlas.communication_outbound_operations o set operation_state='leased',lease_owner=p_lease_owner,lease_expires_at=now()+make_interval(secs=>p_lease_seconds),updated_at=now() from candidates c where o.id=c.id returning o.*
  ) select coalesce(jsonb_agg(to_jsonb(leased) order by created_at,id),'[]'::jsonb) into v_items from leased;
  return jsonb_build_object('contractVersion','communication_outbound_transport_lease_v1','connectedSourceId',p_connected_source_id,'leaseOwner',p_lease_owner,'items',v_items);
end;$function$;

create or replace function atlas.ensure_outbound_conversation_responsibility_service_v1(p_outbound_operation_id uuid,p_communication_event_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_op atlas.communication_outbound_operations%rowtype; v_case atlas.institutional_conversation_response_cases%rowtype; v_num int; v_binding atlas.institutional_conversation_response_work_bindings%rowtype; v_current atlas.work_allocations%rowtype; v_work_id uuid; v_assignment jsonb; v_from text;
begin
  select * into v_op from atlas.communication_outbound_operations where id=p_outbound_operation_id;
  if v_op.id is null then raise exception 'Outbound operation not found.' using errcode='P0002'; end if;
  select * into v_case from atlas.institutional_conversation_response_cases where institutional_conversation_id=v_op.institutional_conversation_id and case_state not in ('complete','informational') order by case_number desc limit 1 for update;
  if v_case.id is null then
    select coalesce(max(case_number),0)+1 into v_num from atlas.institutional_conversation_response_cases where institutional_conversation_id=v_op.institutional_conversation_id;
    insert into atlas.institutional_conversation_response_cases(institutional_conversation_id,organization_id,organization_unit_id,case_number,case_state,opened_by_communication_event_id,opened_at,metadata) values(v_op.institutional_conversation_id,v_op.organization_id,v_op.organization_unit_id,v_num,'waiting_external',p_communication_event_id,now(),jsonb_build_object('openingRule','explicit_outbound_initiation')) returning * into v_case;
  end if;
  v_from:=v_case.case_state;
  select * into v_binding from atlas.institutional_conversation_response_work_bindings where response_case_id=v_case.id;
  if v_binding.id is null then
    insert into atlas.work_items(organization_id,organization_unit_id,title,instructions,work_state,operation_class,jurisdiction_key,source_object_type,source_object_id,stable_key,metadata)
    select v_op.organization_id,v_op.organization_unit_id,'Follow up: '||coalesce(nullif(c.subject,''),'institutional conversation'),'Carry the unresolved communication consequence for this institutional conversation.','open','communication_response','communication:endpoint:'||v_op.communication_endpoint_id::text,'institutional_conversation_response_case',v_case.id,'communication-response:'||v_case.id::text,jsonb_build_object('institutionalConversationId',v_op.institutional_conversation_id,'communicationEndpointId',v_op.communication_endpoint_id) from atlas.institutional_conversations c where c.id=v_op.institutional_conversation_id returning id into v_work_id;
    insert into atlas.institutional_conversation_response_work_bindings(response_case_id,work_item_id) values(v_case.id,v_work_id) returning * into v_binding;
    v_assignment:=atlas.set_company_work_responsibility_internal_v1(v_work_id,v_op.initiated_by_membership_id,v_op.initiated_by_membership_id,'outbound_conversation_initiated',jsonb_build_object('source','ensure_outbound_conversation_responsibility_service_v1','outboundOperationId',v_op.id));
  else
    v_work_id:=v_binding.work_item_id;
    select * into v_current from atlas.work_allocations where work_item_id=v_work_id and allocation_role='responsible' and state='active' limit 1;
    if v_current.id is null then v_assignment:=atlas.set_company_work_responsibility_internal_v1(v_work_id,v_op.initiated_by_membership_id,v_op.initiated_by_membership_id,'unclaimed_conversation_answered',jsonb_build_object('source','ensure_outbound_conversation_responsibility_service_v1','outboundOperationId',v_op.id)); end if;
  end if;
  update atlas.institutional_conversation_response_cases set case_state='waiting_external',closed_at=null,updated_at=now() where id=v_case.id;
  insert into atlas.institutional_conversation_response_events(response_case_id,institutional_conversation_id,event_kind,from_state,to_state,actor_membership_id,target_membership_id,work_item_id,related_communication_event_id,reason,metadata)
  values(v_case.id,v_op.institutional_conversation_id,'outbound_sent',v_from,'waiting_external',v_op.initiated_by_membership_id,coalesce(v_current.assignee_membership_id,v_op.initiated_by_membership_id),v_work_id,p_communication_event_id,'Provider accepted institutional outbound message.',jsonb_build_object('outboundOperationId',v_op.id,'assignment',coalesce(v_assignment,'{}'::jsonb)));
  return jsonb_build_object('contractVersion','outbound_conversation_responsibility_v1','responseCaseId',v_case.id,'workItemId',v_work_id,'responseState','waiting_external');
end;$function$;

create or replace function atlas.record_communication_outbound_result_service_v1(p_outbound_operation_id uuid,p_lease_owner text,p_result_state text,p_provider_message_ref text,p_provider_response jsonb,p_canonical_event jsonb default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_op atlas.communication_outbound_operations%rowtype; v_attempt_no int; v_state text:=lower(btrim(coalesce(p_result_state,''))); v_event_ref text; v_thread_ref text; v_thread_id uuid; v_receipt jsonb; v_event_id uuid; v_resp jsonb;
begin
  select * into v_op from atlas.communication_outbound_operations where id=p_outbound_operation_id for update;
  if v_op.id is null then raise exception 'Outbound operation not found.' using errcode='P0002'; end if;
  if v_op.operation_state='accepted' then return jsonb_build_object('contractVersion','communication_outbound_result_v1','state','already_accepted','outboundOperationId',v_op.id); end if;
  if v_op.operation_state<>'leased' or v_op.lease_owner is distinct from p_lease_owner or v_op.lease_expires_at<now() then raise exception 'Valid outbound transport lease required.' using errcode='42501'; end if;
  if v_state not in ('accepted','temporary_failure','rejected','transport_error','unknown') then raise exception 'Unsupported outbound transport result.' using errcode='22023'; end if;
  select coalesce(max(attempt_number),0)+1 into v_attempt_no from atlas.communication_outbound_attempts where outbound_operation_id=v_op.id;
  insert into atlas.communication_outbound_attempts(outbound_operation_id,connected_source_id,attempt_number,result_state,provider_message_ref,provider_response) values(v_op.id,v_op.connected_source_id,v_attempt_no,v_state,nullif(btrim(coalesce(p_provider_message_ref,'')),''),coalesce(p_provider_response,'{}'::jsonb));
  if v_state='accepted' then
    if p_canonical_event is null or jsonb_typeof(p_canonical_event)<>'object' then raise exception 'Accepted transport requires the exact canonical outbound Communication Event.' using errcode='22023'; end if;
    v_event_ref:=nullif(btrim(p_canonical_event#>>'{source,eventRef}'),''); v_thread_ref:=nullif(btrim(p_canonical_event#>>'{source,threadRef}'),'');
    if v_event_ref is null or v_thread_ref is null then raise exception 'Accepted outbound canonical event requires source eventRef and threadRef.' using errcode='22023'; end if;
    insert into atlas.communication_threads(principal_id,organization_id,organization_unit_id,connected_source_id,source_thread_ref,first_event_at,last_event_at,metadata)
    values(null,v_op.organization_id,v_op.organization_unit_id,v_op.connected_source_id,v_thread_ref,(p_canonical_event->>'occurredAt')::timestamptz,(p_canonical_event->>'occurredAt')::timestamptz,jsonb_build_object('createdFromOutboundOperationId',v_op.id))
    on conflict (connected_source_id,source_thread_ref) do update set last_event_at=greatest(atlas.communication_threads.last_event_at,excluded.last_event_at),updated_at=now() returning id into v_thread_id;
    insert into atlas.institutional_conversation_source_threads(institutional_conversation_id,communication_thread_id,connected_source_id,continuity_basis,metadata) values(v_op.institutional_conversation_id,v_thread_id,v_op.connected_source_id,'atlas_outbound_thread',jsonb_build_object('outboundOperationId',v_op.id)) on conflict (communication_thread_id) do nothing;
    v_receipt:=atlas.ingest_organization_communication_events_service_v3(v_op.connected_source_id,jsonb_build_array(p_canonical_event),jsonb_build_object('source','atlas_outbound_transport','outboundOperationId',v_op.id));
    select id into v_event_id from atlas.communication_events where connected_source_id=v_op.connected_source_id and source_event_ref=v_event_ref;
    if v_event_id is null then raise exception 'Accepted outbound event did not enter Communication Event custody.' using errcode='55000'; end if;
    insert into atlas.communication_outbound_event_links(outbound_operation_id,communication_event_id) values(v_op.id,v_event_id);
    update atlas.communication_outbound_operations set operation_state='accepted',accepted_at=now(),lease_owner=null,lease_expires_at=null,updated_at=now(),metadata=metadata||jsonb_build_object('providerMessageRef',nullif(btrim(coalesce(p_provider_message_ref,'')),'')) where id=v_op.id;
    v_resp:=atlas.ensure_outbound_conversation_responsibility_service_v1(v_op.id,v_event_id);
    return jsonb_build_object('contractVersion','communication_outbound_result_v1','state','accepted','outboundOperationId',v_op.id,'communicationEventId',v_event_id,'ingestReceipt',v_receipt,'response',v_resp);
  elsif v_state='temporary_failure' or v_state='unknown' then
    update atlas.communication_outbound_operations set operation_state='temporary_failure',lease_owner=null,lease_expires_at=null,updated_at=now() where id=v_op.id;
    return jsonb_build_object('contractVersion','communication_outbound_result_v1','state','temporary_failure','outboundOperationId',v_op.id,'attemptNumber',v_attempt_no);
  else
    update atlas.communication_outbound_operations set operation_state='failed',failed_at=now(),lease_owner=null,lease_expires_at=null,updated_at=now() where id=v_op.id;
    return jsonb_build_object('contractVersion','communication_outbound_result_v1','state','failed','outboundOperationId',v_op.id,'attemptNumber',v_attempt_no,'providerResult',v_state);
  end if;
end;$function$;

create or replace function atlas.record_communication_raw_message_custody_service_v1(p_communication_event_id uuid,p_raw_mime_sha256 text,p_byte_length bigint,p_storage_locator text,p_custody_state text default 'stored',p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_event atlas.communication_events%rowtype; v_row atlas.communication_raw_message_custody%rowtype; v_state text:=lower(btrim(coalesce(p_custody_state,'')));
begin
  select * into v_event from atlas.communication_events where id=p_communication_event_id;
  if v_event.id is null then raise exception 'Communication event not found.' using errcode='P0002'; end if;
  if lower(btrim(coalesce(p_raw_mime_sha256,''))) !~ '^[0-9a-f]{64}$' or v_state not in ('stored','hash_only','missing') then raise exception 'Valid raw MIME hash and custody state are required.' using errcode='22023'; end if;
  insert into atlas.communication_raw_message_custody(communication_event_id,connected_source_id,raw_mime_sha256,byte_length,storage_locator,custody_state,metadata)
  values(v_event.id,v_event.connected_source_id,lower(btrim(p_raw_mime_sha256)),p_byte_length,nullif(btrim(coalesce(p_storage_locator,'')),''),v_state,coalesce(p_metadata,'{}'::jsonb))
  on conflict (communication_event_id) do nothing;
  select * into v_row from atlas.communication_raw_message_custody where communication_event_id=v_event.id;
  if v_row.raw_mime_sha256 is distinct from lower(btrim(p_raw_mime_sha256)) then raise exception 'Raw MIME custody hash conflicts with existing evidence.' using errcode='23505'; end if;
  return jsonb_build_object('contractVersion','communication_raw_message_custody_v1','communicationEventId',v_event.id,'rawMimeSha256',v_row.raw_mime_sha256,'custodyState',v_row.custody_state,'storageLocator',v_row.storage_locator);
end;$function$;

alter table atlas.communication_raw_message_custody enable row level security;
alter table atlas.communication_outbound_operations enable row level security;
alter table atlas.communication_outbound_attempts enable row level security;
alter table atlas.communication_outbound_event_links enable row level security;
revoke all on atlas.communication_raw_message_custody,atlas.communication_outbound_operations,atlas.communication_outbound_attempts,atlas.communication_outbound_event_links from public,anon,authenticated;
grant all on atlas.communication_raw_message_custody,atlas.communication_outbound_operations,atlas.communication_outbound_attempts,atlas.communication_outbound_event_links to service_role;

revoke all on function atlas.prevent_communication_outbound_history_mutation_v1(),atlas.guard_communication_outbound_operation_v1(),atlas.record_generic_email_transport_test_service_v1(uuid,boolean,boolean,jsonb),atlas.generic_email_transport_config_service_v1(uuid),atlas.lease_communication_outbound_operations_service_v1(uuid,text,integer,integer),atlas.ensure_outbound_conversation_responsibility_service_v1(uuid,uuid),atlas.record_communication_outbound_result_service_v1(uuid,text,text,text,jsonb,jsonb),atlas.record_communication_raw_message_custody_service_v1(uuid,text,bigint,text,text,jsonb) from public,anon,authenticated;
grant execute on function atlas.prevent_communication_outbound_history_mutation_v1(),atlas.guard_communication_outbound_operation_v1(),atlas.record_generic_email_transport_test_service_v1(uuid,boolean,boolean,jsonb),atlas.generic_email_transport_config_service_v1(uuid),atlas.lease_communication_outbound_operations_service_v1(uuid,text,integer,integer),atlas.ensure_outbound_conversation_responsibility_service_v1(uuid,uuid),atlas.record_communication_outbound_result_service_v1(uuid,text,text,text,jsonb,jsonb),atlas.record_communication_raw_message_custody_service_v1(uuid,text,bigint,text,text,jsonb) to service_role;
revoke all on function atlas.configure_generic_email_endpoint_self_api_v1(uuid,uuid,text,text,text,integer,text,text,integer,text,text,text),atlas.prepare_institutional_email_send_self_api_v1(uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text) from public,anon;
grant execute on function atlas.configure_generic_email_endpoint_self_api_v1(uuid,uuid,text,text,text,integer,text,text,integer,text,text,text),atlas.prepare_institutional_email_send_self_api_v1(uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text) to authenticated,service_role;

commit;