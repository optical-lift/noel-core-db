begin;

create or replace function atlas.communication_outbound_attachment_storage_authorized_self_v1(p_bucket_id text,p_object_name text,p_action text)
returns boolean
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare v_attachment atlas.communication_outbound_attachments%rowtype; v_member atlas.organization_memberships%rowtype; v_action text:=lower(btrim(coalesce(p_action,'')));
begin
  if auth.uid() is null or p_bucket_id<>'atlas-communication-outbound-attachments' then return false; end if;
  select * into v_attachment from atlas.communication_outbound_attachments where storage_bucket=p_bucket_id and storage_object_path=p_object_name;
  if v_attachment.id is null then return false; end if;
  select * into v_member from atlas.organization_memberships where organization_id=v_attachment.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_member.id is null then return false; end if;
  if v_action='insert' then
    return v_attachment.attachment_state='staging'
      and v_attachment.staged_by_membership_id=v_member.id
      and atlas.communication_endpoint_membership_has_capability_v1(v_attachment.communication_endpoint_id,v_member.id,'send');
  elsif v_action='delete' then
    return v_attachment.attachment_state in ('staging','revoked')
      and (v_attachment.staged_by_membership_id=v_member.id or atlas.communication_endpoint_membership_has_capability_v1(v_attachment.communication_endpoint_id,v_member.id,'admin'));
  end if;
  return false;
end;
$function$;

revoke all on function atlas.communication_outbound_attachment_storage_authorized_self_v1(text,text,text) from public,anon;
grant execute on function atlas.communication_outbound_attachment_storage_authorized_self_v1(text,text,text) to authenticated,service_role;

drop policy if exists atlas_communication_outbound_attachment_insert_v1 on storage.objects;
create policy atlas_communication_outbound_attachment_insert_v1
on storage.objects for insert to authenticated
with check (atlas.communication_outbound_attachment_storage_authorized_self_v1(bucket_id,name,'insert'));

drop policy if exists atlas_communication_outbound_attachment_delete_v1 on storage.objects;
create policy atlas_communication_outbound_attachment_delete_v1
on storage.objects for delete to authenticated
using (atlas.communication_outbound_attachment_storage_authorized_self_v1(bucket_id,name,'delete'));

commit;
