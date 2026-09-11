begin;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('atlas-communication-raw','atlas-communication-raw',false,52428800,array['message/rfc822','application/octet-stream'])
on conflict (id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create table atlas.communication_mailbox_sync_checkpoints (
  id uuid primary key default gen_random_uuid(),
  connected_source_id uuid not null references atlas.connected_sources(id) on delete cascade,
  folder_key text not null check (btrim(folder_key)<>''),
  folder_role text not null default 'other' check (folder_role in ('inbox','sent','other')),
  uid_validity numeric,
  last_uid numeric not null default 0 check (last_uid>=0),
  highest_modseq numeric,
  live_watch_supported boolean,
  baseline_policy text not null default 'from_now' check (baseline_policy in ('from_now','all','days')),
  baseline_days integer check (baseline_days is null or baseline_days between 1 and 3650),
  last_reconciled_at timestamptz,
  last_live_event_at timestamptz,
  last_error_at timestamptz,
  last_error_code text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(connected_source_id,folder_key),
  check (baseline_policy='days' or baseline_days is null),
  check (baseline_policy<>'days' or baseline_days is not null)
);
create index communication_mailbox_checkpoint_source_idx on atlas.communication_mailbox_sync_checkpoints(connected_source_id,folder_role,updated_at desc,id);
comment on table atlas.communication_mailbox_sync_checkpoints is 'Provider mailbox folder continuity checkpoint. A gateway advances last_uid only after source messages are admitted/custodied; UIDVALIDITY change requires reconciliation rather than trusting stale UID positions.';

create table atlas.communication_gateway_heartbeats (
  id uuid primary key default gen_random_uuid(),
  gateway_instance_key text not null check (btrim(gateway_instance_key)<>''),
  connected_source_id uuid not null references atlas.connected_sources(id) on delete cascade,
  state text not null check (state in ('starting','live','reconnecting','degraded','stopped','error')),
  detail jsonb not null default '{}'::jsonb check (jsonb_typeof(detail)='object'),
  observed_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index communication_gateway_heartbeat_source_idx on atlas.communication_gateway_heartbeats(connected_source_id,observed_at desc,id);
comment on table atlas.communication_gateway_heartbeats is 'Append-only runtime heartbeat evidence from persistent communication gateways. It describes transport health only and grants no communication authority.';

create trigger communication_gateway_heartbeats_append_only_v1 before update or delete on atlas.communication_gateway_heartbeats for each row execute function atlas.prevent_institutional_response_history_mutation_v1();

create or replace function atlas.communication_gateway_sources_service_v1()
returns jsonb language sql stable security definer set search_path=pg_catalog,atlas as $function$
  select jsonb_build_object(
    'contractVersion','communication_gateway_sources_v1',
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'connectedSourceId',s.id,
      'organizationId',s.custodian_organization_id,
      'organizationUnitId',s.custodian_organization_unit_id,
      'providerKey',s.provider_key,
      'providerAccountKey',s.provider_account_key,
      'authorizationState',s.authorization_state,
      'capabilities',s.capabilities,
      'lastSyncAt',s.last_sync_at,
      'communicationEndpointId',b.communication_endpoint_id,
      'endpointAddress',ep.address,
      'endpointDisplayName',ep.display_name,
      'bindingRole',b.binding_role,
      'historyPolicy',coalesce(s.metadata->'communicationHistoryPolicy',jsonb_build_object('mode','from_now'))
    ) order by s.created_at,s.id),'[]'::jsonb)
  )
  from atlas.connected_sources s
  join atlas.communication_endpoint_source_bindings b on b.connected_source_id=s.id and b.binding_state='active'
  join atlas.communication_endpoints ep on ep.id=b.communication_endpoint_id and ep.endpoint_state='active'
  where s.provider_key='imap_smtp_email'
    and s.custodian_organization_id is not null
    and s.authorization_state in ('pending','connected','error','reauthorization_required');
$function$;

create or replace function atlas.communication_mailbox_checkpoint_service_v1(p_connected_source_id uuid,p_folder_key text)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas as $function$
declare v_row atlas.communication_mailbox_sync_checkpoints%rowtype;
begin
  select * into v_row from atlas.communication_mailbox_sync_checkpoints where connected_source_id=p_connected_source_id and folder_key=btrim(coalesce(p_folder_key,''));
  if v_row.id is null then return jsonb_build_object('contractVersion','communication_mailbox_checkpoint_v1','exists',false,'connectedSourceId',p_connected_source_id,'folderKey',btrim(coalesce(p_folder_key,''))); end if;
  return jsonb_build_object('contractVersion','communication_mailbox_checkpoint_v1','exists',true,'connectedSourceId',v_row.connected_source_id,'folderKey',v_row.folder_key,'folderRole',v_row.folder_role,'uidValidity',v_row.uid_validity,'lastUid',v_row.last_uid,'highestModseq',v_row.highest_modseq,'liveWatchSupported',v_row.live_watch_supported,'baselinePolicy',v_row.baseline_policy,'baselineDays',v_row.baseline_days,'lastReconciledAt',v_row.last_reconciled_at,'lastLiveEventAt',v_row.last_live_event_at,'lastErrorAt',v_row.last_error_at,'lastErrorCode',v_row.last_error_code,'metadata',v_row.metadata);
end;$function$;

create or replace function atlas.advance_communication_mailbox_checkpoint_service_v1(
  p_connected_source_id uuid,p_folder_key text,p_folder_role text,p_uid_validity numeric,p_last_uid numeric,p_highest_modseq numeric,p_live_watch_supported boolean,p_live_event boolean default false,p_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_source atlas.connected_sources%rowtype; v_row atlas.communication_mailbox_sync_checkpoints%rowtype; v_folder text:=btrim(coalesce(p_folder_key,'')); v_role text:=lower(btrim(coalesce(p_folder_role,'')));
begin
  select * into v_source from atlas.connected_sources where id=p_connected_source_id and provider_key='imap_smtp_email' and custodian_organization_id is not null and authorization_state<>'revoked';
  if v_source.id is null then raise exception 'Generic institutional email source not found.' using errcode='P0002'; end if;
  if v_folder='' or v_role not in ('inbox','sent','other') or coalesce(p_last_uid,-1)<0 then raise exception 'Valid folder, role, and UID checkpoint are required.' using errcode='22023'; end if;
  select * into v_row from atlas.communication_mailbox_sync_checkpoints where connected_source_id=v_source.id and folder_key=v_folder for update;
  if v_row.id is not null and v_row.uid_validity is not null and p_uid_validity is not null and v_row.uid_validity<>p_uid_validity then
    raise exception 'Mailbox UIDVALIDITY changed; explicit baseline reset/reconciliation is required.' using errcode='55000';
  end if;
  insert into atlas.communication_mailbox_sync_checkpoints(connected_source_id,folder_key,folder_role,uid_validity,last_uid,highest_modseq,live_watch_supported,baseline_policy,baseline_days,last_reconciled_at,last_live_event_at,metadata)
  values(v_source.id,v_folder,v_role,p_uid_validity,p_last_uid,p_highest_modseq,p_live_watch_supported,coalesce(v_row.baseline_policy,coalesce(v_source.metadata#>>'{communicationHistoryPolicy,mode}','from_now')),coalesce(v_row.baseline_days,(v_source.metadata#>>'{communicationHistoryPolicy,days}')::integer),now(),case when p_live_event then now() else v_row.last_live_event_at end,coalesce(p_metadata,'{}'::jsonb))
  on conflict (connected_source_id,folder_key) do update set folder_role=excluded.folder_role,uid_validity=coalesce(excluded.uid_validity,atlas.communication_mailbox_sync_checkpoints.uid_validity),last_uid=greatest(atlas.communication_mailbox_sync_checkpoints.last_uid,excluded.last_uid),highest_modseq=case when atlas.communication_mailbox_sync_checkpoints.highest_modseq is null then excluded.highest_modseq when excluded.highest_modseq is null then atlas.communication_mailbox_sync_checkpoints.highest_modseq else greatest(atlas.communication_mailbox_sync_checkpoints.highest_modseq,excluded.highest_modseq) end,live_watch_supported=excluded.live_watch_supported,last_reconciled_at=now(),last_live_event_at=case when p_live_event then now() else atlas.communication_mailbox_sync_checkpoints.last_live_event_at end,metadata=atlas.communication_mailbox_sync_checkpoints.metadata||excluded.metadata,updated_at=now()
  returning * into v_row;
  return atlas.communication_mailbox_checkpoint_service_v1(v_source.id,v_folder);
end;$function$;

create or replace function atlas.initialize_communication_mailbox_checkpoint_service_v1(p_connected_source_id uuid,p_folder_key text,p_folder_role text,p_uid_validity numeric,p_current_last_uid numeric,p_live_watch_supported boolean,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_source atlas.connected_sources%rowtype; v_policy text; v_days int; v_row atlas.communication_mailbox_sync_checkpoints%rowtype; v_initial_uid numeric;
begin
  select * into v_source from atlas.connected_sources where id=p_connected_source_id and provider_key='imap_smtp_email' and custodian_organization_id is not null and authorization_state<>'revoked';
  if v_source.id is null then raise exception 'Generic institutional email source not found.' using errcode='P0002'; end if;
  v_policy:=coalesce(v_source.metadata#>>'{communicationHistoryPolicy,mode}','from_now');
  v_days:=nullif(v_source.metadata#>>'{communicationHistoryPolicy,days}','')::integer;
  if v_policy not in ('from_now','all','days') then raise exception 'Unsupported communication history policy.' using errcode='22023'; end if;
  select * into v_row from atlas.communication_mailbox_sync_checkpoints where connected_source_id=v_source.id and folder_key=btrim(p_folder_key);
  if v_row.id is not null then return atlas.communication_mailbox_checkpoint_service_v1(v_source.id,btrim(p_folder_key)); end if;
  v_initial_uid:=case when v_policy='from_now' then greatest(coalesce(p_current_last_uid,0),0) else 0 end;
  insert into atlas.communication_mailbox_sync_checkpoints(connected_source_id,folder_key,folder_role,uid_validity,last_uid,live_watch_supported,baseline_policy,baseline_days,last_reconciled_at,metadata)
  values(v_source.id,btrim(p_folder_key),lower(btrim(p_folder_role)),p_uid_validity,v_initial_uid,p_live_watch_supported,v_policy,case when v_policy='days' then v_days else null end,now(),coalesce(p_metadata,'{}'::jsonb));
  return atlas.communication_mailbox_checkpoint_service_v1(v_source.id,btrim(p_folder_key));
end;$function$;

create or replace function atlas.record_communication_mailbox_checkpoint_error_service_v1(p_connected_source_id uuid,p_folder_key text,p_error_code text,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
begin
  update atlas.communication_mailbox_sync_checkpoints set last_error_at=now(),last_error_code=nullif(btrim(coalesce(p_error_code,'')),''),metadata=metadata||coalesce(p_metadata,'{}'::jsonb),updated_at=now() where connected_source_id=p_connected_source_id and folder_key=btrim(coalesce(p_folder_key,''));
  return jsonb_build_object('contractVersion','communication_mailbox_checkpoint_error_v1','connectedSourceId',p_connected_source_id,'folderKey',btrim(coalesce(p_folder_key,'')),'errorCode',nullif(btrim(coalesce(p_error_code,'')),''),'recordedAt',now());
end;$function$;

create or replace function atlas.record_communication_gateway_heartbeat_service_v1(p_gateway_instance_key text,p_connected_source_id uuid,p_state text,p_detail jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_state text:=lower(btrim(coalesce(p_state,''))); v_id uuid;
begin
  if btrim(coalesce(p_gateway_instance_key,''))='' or v_state not in ('starting','live','reconnecting','degraded','stopped','error') then raise exception 'Valid gateway instance and state required.' using errcode='22023'; end if;
  if not exists(select 1 from atlas.connected_sources where id=p_connected_source_id and custodian_organization_id is not null) then raise exception 'Institutional connected source required.' using errcode='23514'; end if;
  insert into atlas.communication_gateway_heartbeats(gateway_instance_key,connected_source_id,state,detail) values(btrim(p_gateway_instance_key),p_connected_source_id,v_state,coalesce(p_detail,'{}'::jsonb)) returning id into v_id;
  return jsonb_build_object('contractVersion','communication_gateway_heartbeat_v1','heartbeatId',v_id,'connectedSourceId',p_connected_source_id,'state',v_state,'observedAt',now());
end;$function$;

create or replace function atlas.lookup_communication_event_by_source_ref_service_v1(p_connected_source_id uuid,p_source_event_ref text)
returns jsonb language sql stable security definer set search_path=pg_catalog,atlas as $function$
  select coalesce((select jsonb_build_object('found',true,'communicationEventId',e.id,'organizationId',e.organization_id,'organizationUnitId',e.organization_unit_id,'sourceEventRef',e.source_event_ref,'occurredAt',e.occurred_at) from atlas.communication_events e where e.connected_source_id=p_connected_source_id and e.source_event_ref=btrim(coalesce(p_source_event_ref,''))),jsonb_build_object('found',false,'sourceEventRef',btrim(coalesce(p_source_event_ref,''))))||jsonb_build_object('contractVersion','communication_event_source_lookup_v1');
$function$;

create or replace function atlas.communication_outbound_transport_payload_service_v1(p_outbound_operation_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas as $function$
declare v_op atlas.communication_outbound_operations%rowtype; v_ep atlas.communication_endpoints%rowtype;
begin
  select * into v_op from atlas.communication_outbound_operations where id=p_outbound_operation_id;
  if v_op.id is null then raise exception 'Outbound operation not found.' using errcode='P0002'; end if;
  select * into v_ep from atlas.communication_endpoints where id=v_op.communication_endpoint_id;
  return jsonb_build_object('contractVersion','communication_outbound_transport_payload_v1','outboundOperationId',v_op.id,'operationState',v_op.operation_state,'leaseOwner',v_op.lease_owner,'leaseExpiresAt',v_op.lease_expires_at,'connectedSourceId',v_op.connected_source_id,'communicationEndpointId',v_ep.id,'fromAddress',v_ep.address,'fromDisplayName',v_ep.display_name,'institutionalConversationId',v_op.institutional_conversation_id,'initiatedByMembershipId',v_op.initiated_by_membership_id,'to',v_op.to_recipients,'cc',v_op.cc_recipients,'bcc',v_op.bcc_recipients,'subject',v_op.subject,'bodyText',v_op.body_text,'bodyHtml',v_op.body_html,'attachmentRefs',v_op.attachment_refs,'replyToCommunicationEventId',v_op.reply_to_communication_event_id,'contentSha256',v_op.content_sha256);
end;$function$;

create or replace function atlas.set_generic_email_history_policy_self_api_v1(p_connected_source_id uuid,p_mode text,p_days integer default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_source atlas.connected_sources%rowtype; v_mode text:=lower(btrim(coalesce(p_mode,'')));
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_source from atlas.connected_sources where id=p_connected_source_id and provider_key='imap_smtp_email' and custodian_organization_id is not null for update;
  if v_source.id is null then raise exception 'Generic institutional email source not found.' using errcode='P0002'; end if;
  if not atlas.is_organization_owner(v_source.custodian_organization_id) then raise exception 'Organization owner authority required.' using errcode='42501'; end if;
  if v_mode not in ('from_now','all','days') or (v_mode='days' and (p_days is null or p_days<1 or p_days>3650)) then raise exception 'History policy must be from_now, all, or days with 1-3650 days.' using errcode='22023'; end if;
  if exists(select 1 from atlas.communication_mailbox_sync_checkpoints where connected_source_id=v_source.id) then raise exception 'History policy cannot be changed after mailbox checkpoints have initialized without an explicit reconciliation/reset operation.' using errcode='55000'; end if;
  update atlas.connected_sources set metadata=metadata||jsonb_build_object('communicationHistoryPolicy',case when v_mode='days' then jsonb_build_object('mode',v_mode,'days',p_days) else jsonb_build_object('mode',v_mode) end),updated_at=now() where id=v_source.id;
  return jsonb_build_object('contractVersion','generic_email_history_policy_v1','connectedSourceId',v_source.id,'mode',v_mode,'days',case when v_mode='days' then p_days else null end);
end;$function$;

update atlas.connected_sources
set metadata=metadata||jsonb_build_object('communicationHistoryPolicy',jsonb_build_object('mode','from_now')),updated_at=now()
where id='238df033-5704-4404-bf34-a509f4e4d1c1' and provider_key='imap_smtp_email' and not (metadata ? 'communicationHistoryPolicy');

alter table atlas.communication_mailbox_sync_checkpoints enable row level security;
alter table atlas.communication_gateway_heartbeats enable row level security;
revoke all on atlas.communication_mailbox_sync_checkpoints,atlas.communication_gateway_heartbeats from public,anon,authenticated;
grant all on atlas.communication_mailbox_sync_checkpoints,atlas.communication_gateway_heartbeats to service_role;

revoke all on function atlas.communication_gateway_sources_service_v1(),atlas.communication_mailbox_checkpoint_service_v1(uuid,text),atlas.advance_communication_mailbox_checkpoint_service_v1(uuid,text,text,numeric,numeric,numeric,boolean,boolean,jsonb),atlas.initialize_communication_mailbox_checkpoint_service_v1(uuid,text,text,numeric,numeric,boolean,jsonb),atlas.record_communication_mailbox_checkpoint_error_service_v1(uuid,text,text,jsonb),atlas.record_communication_gateway_heartbeat_service_v1(text,uuid,text,jsonb),atlas.lookup_communication_event_by_source_ref_service_v1(uuid,text),atlas.communication_outbound_transport_payload_service_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.communication_gateway_sources_service_v1(),atlas.communication_mailbox_checkpoint_service_v1(uuid,text),atlas.advance_communication_mailbox_checkpoint_service_v1(uuid,text,text,numeric,numeric,numeric,boolean,boolean,jsonb),atlas.initialize_communication_mailbox_checkpoint_service_v1(uuid,text,text,numeric,numeric,boolean,jsonb),atlas.record_communication_mailbox_checkpoint_error_service_v1(uuid,text,text,jsonb),atlas.record_communication_gateway_heartbeat_service_v1(text,uuid,text,jsonb),atlas.lookup_communication_event_by_source_ref_service_v1(uuid,text),atlas.communication_outbound_transport_payload_service_v1(uuid) to service_role;
revoke all on function atlas.set_generic_email_history_policy_self_api_v1(uuid,text,integer) from public,anon;
grant execute on function atlas.set_generic_email_history_policy_self_api_v1(uuid,text,integer) to authenticated,service_role;

commit;