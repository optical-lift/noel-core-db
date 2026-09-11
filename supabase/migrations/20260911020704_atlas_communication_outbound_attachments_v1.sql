begin;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('atlas-communication-outbound-attachments','atlas-communication-outbound-attachments',false,52428800,null)
on conflict (id) do update set public=false,file_size_limit=excluded.file_size_limit;

create table atlas.communication_outbound_attachments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid,
  communication_endpoint_id uuid not null references atlas.communication_endpoints(id) on delete restrict,
  staged_by_membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  file_name text not null check (btrim(file_name)<>''),
  mime_type text,
  byte_length bigint check (byte_length is null or byte_length>=0),
  sha256 text check (sha256 is null or sha256 ~ '^[0-9a-f]{64}$'),
  storage_bucket text not null default 'atlas-communication-outbound-attachments' check (storage_bucket='atlas-communication-outbound-attachments'),
  storage_object_path text not null unique check (btrim(storage_object_path)<>''),
  attachment_state text not null default 'staging' check (attachment_state in ('staging','ready','revoked')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  ready_at timestamptz,
  revoked_at timestamptz,
  updated_at timestamptz not null default now(),
  foreign key (organization_id,organization_unit_id) references atlas.organization_units(organization_id,id) on delete restrict,
  check ((attachment_state='ready')=(ready_at is not null)),
  check (revoked_at is null or attachment_state='revoked')
);
create index communication_outbound_attachments_org_idx on atlas.communication_outbound_attachments(organization_id,organization_unit_id,communication_endpoint_id,attachment_state,created_at desc,id);
comment on table atlas.communication_outbound_attachments is 'Governed organization-owned attachment staging for institutional outbound communication. User-visible file references are UUIDs; the gateway resolves storage only after endpoint/scope validation.';

create or replace function atlas.guard_communication_outbound_attachment_v1() returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_endpoint atlas.communication_endpoints%rowtype; v_member atlas.organization_memberships%rowtype;
begin
  select * into v_endpoint from atlas.communication_endpoints where id=new.communication_endpoint_id;
  select * into v_member from atlas.organization_memberships where id=new.staged_by_membership_id;
  if v_endpoint.id is null or v_member.id is null or v_endpoint.organization_id is distinct from new.organization_id or v_endpoint.organization_unit_id is distinct from new.organization_unit_id or v_member.organization_id is distinct from new.organization_id then raise exception 'Outbound attachment must share endpoint/organization scope.' using errcode='23514'; end if;
  if new.sha256 is not null then new.sha256:=lower(btrim(new.sha256)); end if;
  new.updated_at:=now();
  return new;
end;$function$;
create trigger communication_outbound_attachment_guard_v1 before insert or update on atlas.communication_outbound_attachments for each row execute function atlas.guard_communication_outbound_attachment_v1();

create or replace function atlas.prepare_communication_outbound_attachment_self_api_v1(p_communication_endpoint_id uuid,p_file_name text,p_mime_type text default null,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_endpoint atlas.communication_endpoints%rowtype; v_member atlas.organization_memberships%rowtype; v_id uuid:=gen_random_uuid(); v_path text;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_endpoint from atlas.communication_endpoints where id=p_communication_endpoint_id and endpoint_state='active';
  if v_endpoint.id is null then raise exception 'Active communication endpoint not found.' using errcode='P0002'; end if;
  select * into v_member from atlas.organization_memberships where organization_id=v_endpoint.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'send') then raise exception 'Communication endpoint send authority required.' using errcode='42501'; end if;
  if btrim(coalesce(p_file_name,''))='' or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then raise exception 'File name and object metadata are required.' using errcode='22023'; end if;
  v_path:='org/'||v_endpoint.organization_id::text||'/endpoint/'||v_endpoint.id::text||'/'||v_id::text;
  insert into atlas.communication_outbound_attachments(id,organization_id,organization_unit_id,communication_endpoint_id,staged_by_membership_id,file_name,mime_type,storage_object_path,metadata)
  values(v_id,v_endpoint.organization_id,v_endpoint.organization_unit_id,v_endpoint.id,v_member.id,btrim(p_file_name),nullif(lower(btrim(coalesce(p_mime_type,''))),''),v_path,coalesce(p_metadata,'{}'::jsonb));
  return jsonb_build_object('contractVersion','communication_outbound_attachment_prepare_v1','attachmentId',v_id,'storageBucket','atlas-communication-outbound-attachments','storageObjectPath',v_path,'fileName',btrim(p_file_name),'mimeType',nullif(lower(btrim(coalesce(p_mime_type,''))),''),'state','staging');
end;$function$;

create or replace function atlas.confirm_communication_outbound_attachment_self_api_v1(p_attachment_id uuid,p_sha256 text,p_byte_length bigint)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_attachment atlas.communication_outbound_attachments%rowtype; v_member atlas.organization_memberships%rowtype; v_hash text:=lower(btrim(coalesce(p_sha256,'')));
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_attachment from atlas.communication_outbound_attachments where id=p_attachment_id for update;
  if v_attachment.id is null then raise exception 'Outbound attachment not found.' using errcode='P0002'; end if;
  select * into v_member from atlas.organization_memberships where organization_id=v_attachment.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_attachment.communication_endpoint_id,v_member.id,'send') then raise exception 'Communication endpoint send authority required.' using errcode='42501'; end if;
  if v_hash !~ '^[0-9a-f]{64}$' or p_byte_length is null or p_byte_length<0 or p_byte_length>52428800 then raise exception 'Valid SHA-256 and attachment size up to 50 MiB are required.' using errcode='22023'; end if;
  if v_attachment.attachment_state='revoked' then raise exception 'Revoked attachment cannot become ready.' using errcode='55000'; end if;
  if v_attachment.attachment_state='ready' then
    if v_attachment.sha256 is distinct from v_hash or v_attachment.byte_length is distinct from p_byte_length then raise exception 'Attachment confirmation conflicts with existing custody.' using errcode='23505'; end if;
    return jsonb_build_object('contractVersion','communication_outbound_attachment_confirm_v1','attachmentId',v_attachment.id,'state','ready','sha256',v_attachment.sha256,'byteLength',v_attachment.byte_length);
  end if;
  update atlas.communication_outbound_attachments set sha256=v_hash,byte_length=p_byte_length,attachment_state='ready',ready_at=now(),updated_at=now() where id=v_attachment.id returning * into v_attachment;
  return jsonb_build_object('contractVersion','communication_outbound_attachment_confirm_v1','attachmentId',v_attachment.id,'state','ready','sha256',v_attachment.sha256,'byteLength',v_attachment.byte_length);
end;$function$;

create or replace function atlas.communication_outbound_attachment_transport_service_v1(p_outbound_operation_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas as $function$
declare v_op atlas.communication_outbound_operations%rowtype; v_items jsonb; v_ref jsonb; v_id uuid; v_attachment atlas.communication_outbound_attachments%rowtype;
begin
  select * into v_op from atlas.communication_outbound_operations where id=p_outbound_operation_id;
  if v_op.id is null then raise exception 'Outbound operation not found.' using errcode='P0002'; end if;
  v_items:='[]'::jsonb;
  for v_ref in select value from jsonb_array_elements(coalesce(v_op.attachment_refs,'[]'::jsonb)) loop
    begin v_id:=trim(both '"' from v_ref::text)::uuid; exception when invalid_text_representation then raise exception 'Outbound attachment reference is invalid.' using errcode='22023'; end;
    select * into v_attachment from atlas.communication_outbound_attachments where id=v_id;
    if v_attachment.id is null or v_attachment.organization_id is distinct from v_op.organization_id or v_attachment.organization_unit_id is distinct from v_op.organization_unit_id or v_attachment.communication_endpoint_id is distinct from v_op.communication_endpoint_id or v_attachment.attachment_state<>'ready' then raise exception 'Outbound attachment is missing, unready, or outside operation scope.' using errcode='42501'; end if;
    v_items:=v_items||jsonb_build_array(jsonb_build_object('attachmentId',v_attachment.id,'bucket',v_attachment.storage_bucket,'path',v_attachment.storage_object_path,'fileName',v_attachment.file_name,'mimeType',v_attachment.mime_type,'sha256',v_attachment.sha256,'byteLength',v_attachment.byte_length));
  end loop;
  return jsonb_build_object('contractVersion','communication_outbound_attachment_transport_v1','outboundOperationId',v_op.id,'items',v_items);
end;$function$;

create or replace function atlas.guard_communication_outbound_operation_v1() returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_endpoint atlas.communication_endpoints%rowtype; v_conv atlas.institutional_conversations%rowtype; v_source atlas.connected_sources%rowtype; v_member atlas.organization_memberships%rowtype; v_ref jsonb; v_attachment_id uuid; v_attachment atlas.communication_outbound_attachments%rowtype;
begin
  select * into v_endpoint from atlas.communication_endpoints where id=new.communication_endpoint_id;
  select * into v_conv from atlas.institutional_conversations where id=new.institutional_conversation_id;
  select * into v_source from atlas.connected_sources where id=new.connected_source_id;
  select * into v_member from atlas.organization_memberships where id=new.initiated_by_membership_id;
  if v_endpoint.id is null or v_conv.id is null or v_source.id is null or v_member.id is null then raise exception 'Outbound communication requires endpoint, conversation, source, and initiating membership.' using errcode='23514'; end if;
  if v_endpoint.organization_id is distinct from new.organization_id or v_endpoint.organization_unit_id is distinct from new.organization_unit_id or v_conv.organization_id is distinct from new.organization_id or v_conv.organization_unit_id is distinct from new.organization_unit_id or v_source.custodian_organization_id is distinct from new.organization_id or v_source.custodian_organization_unit_id is distinct from new.organization_unit_id or v_member.organization_id is distinct from new.organization_id then raise exception 'Outbound operation must share organization/unit custody.' using errcode='23514'; end if;
  if not exists(select 1 from atlas.communication_endpoint_source_bindings b where b.communication_endpoint_id=v_endpoint.id and b.connected_source_id=v_source.id and b.binding_state='active' and b.binding_role in ('send','send_receive')) then raise exception 'Outbound source is not an active send transport for endpoint.' using errcode='23514'; end if;
  if jsonb_typeof(coalesce(new.attachment_refs,'[]'::jsonb))<>'array' then raise exception 'Outbound attachment references must be an array.' using errcode='22023'; end if;
  for v_ref in select value from jsonb_array_elements(coalesce(new.attachment_refs,'[]'::jsonb)) loop
    begin v_attachment_id:=trim(both '"' from v_ref::text)::uuid; exception when invalid_text_representation then raise exception 'Outbound attachment reference is invalid.' using errcode='22023'; end;
    select * into v_attachment from atlas.communication_outbound_attachments where id=v_attachment_id;
    if v_attachment.id is null or v_attachment.organization_id is distinct from new.organization_id or v_attachment.organization_unit_id is distinct from new.organization_unit_id or v_attachment.communication_endpoint_id is distinct from new.communication_endpoint_id or v_attachment.attachment_state<>'ready' then raise exception 'Outbound attachment is missing, unready, or outside operation scope.' using errcode='42501'; end if;
  end loop;
  new.updated_at:=now();
  return new;
end;$function$;

alter table atlas.communication_outbound_attachments enable row level security;
revoke all on atlas.communication_outbound_attachments from public,anon,authenticated;
grant all on atlas.communication_outbound_attachments to service_role;
revoke all on function atlas.guard_communication_outbound_attachment_v1(),atlas.communication_outbound_attachment_transport_service_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.guard_communication_outbound_attachment_v1(),atlas.communication_outbound_attachment_transport_service_v1(uuid) to service_role;
revoke all on function atlas.prepare_communication_outbound_attachment_self_api_v1(uuid,text,text,jsonb),atlas.confirm_communication_outbound_attachment_self_api_v1(uuid,text,bigint) from public,anon;
grant execute on function atlas.prepare_communication_outbound_attachment_self_api_v1(uuid,text,text,jsonb),atlas.confirm_communication_outbound_attachment_self_api_v1(uuid,text,bigint) to authenticated,service_role;

commit;