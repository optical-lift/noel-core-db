begin;

drop policy if exists atlas_communication_outbound_attachment_insert_v1 on storage.objects;
create policy atlas_communication_outbound_attachment_insert_v1
on storage.objects for insert to authenticated
with check (
  bucket_id='atlas-communication-outbound-attachments'
  and exists(
    select 1
    from atlas.communication_outbound_attachments attachment
    join atlas.organization_memberships member on member.id=attachment.staged_by_membership_id
    where attachment.storage_bucket=storage.objects.bucket_id
      and attachment.storage_object_path=storage.objects.name
      and attachment.attachment_state='staging'
      and member.organization_id=attachment.organization_id
      and member.user_id=auth.uid()
      and member.active
      and atlas.communication_endpoint_membership_has_capability_v1(attachment.communication_endpoint_id,member.id,'send')
  )
);

drop policy if exists atlas_communication_outbound_attachment_delete_v1 on storage.objects;
create policy atlas_communication_outbound_attachment_delete_v1
on storage.objects for delete to authenticated
using (
  bucket_id='atlas-communication-outbound-attachments'
  and exists(
    select 1
    from atlas.communication_outbound_attachments attachment
    join atlas.organization_memberships member on member.organization_id=attachment.organization_id and member.user_id=auth.uid() and member.active
    where attachment.storage_bucket=storage.objects.bucket_id
      and attachment.storage_object_path=storage.objects.name
      and attachment.attachment_state in ('staging','revoked')
      and (
        attachment.staged_by_membership_id=member.id
        or atlas.communication_endpoint_membership_has_capability_v1(attachment.communication_endpoint_id,member.id,'admin')
      )
  )
);

create or replace function atlas.confirm_communication_outbound_attachment_self_api_v1(p_attachment_id uuid,p_sha256 text,p_byte_length bigint)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth,storage as $function$
declare v_attachment atlas.communication_outbound_attachments%rowtype; v_member atlas.organization_memberships%rowtype; v_hash text:=lower(btrim(coalesce(p_sha256,''))); v_storage_exists boolean;
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
    return jsonb_build_object('contractVersion','communication_outbound_attachment_confirm_v2','attachmentId',v_attachment.id,'state','ready','sha256',v_attachment.sha256,'byteLength',v_attachment.byte_length);
  end if;
  select exists(select 1 from storage.objects o where o.bucket_id=v_attachment.storage_bucket and o.name=v_attachment.storage_object_path) into v_storage_exists;
  if not v_storage_exists then raise exception 'Attachment bytes are not yet present in governed storage.' using errcode='55000'; end if;
  update atlas.communication_outbound_attachments set sha256=v_hash,byte_length=p_byte_length,attachment_state='ready',ready_at=now(),updated_at=now() where id=v_attachment.id returning * into v_attachment;
  return jsonb_build_object('contractVersion','communication_outbound_attachment_confirm_v2','attachmentId',v_attachment.id,'state','ready','sha256',v_attachment.sha256,'byteLength',v_attachment.byte_length);
end;$function$;

commit;
