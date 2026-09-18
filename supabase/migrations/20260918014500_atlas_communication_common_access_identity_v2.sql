begin;

create or replace function atlas.organization_correspondence_access_self_api_v2(
  p_organization_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_base jsonb;
  v_items jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_base:=atlas.organization_correspondence_access_self_api_v1(p_organization_id);

  if coalesce(v_base->>'identityRoot','')<>'communication_endpoint' then
    raise exception 'Common Correspondence access lost Communication Endpoint custody.' using errcode='23514';
  end if;

  select coalesce(jsonb_agg(
    item || jsonb_build_object('correspondenceIdentity',identity_projection.identity_json)
    order by item->>'organizationName',item->>'address'
  ),'[]'::jsonb)
  into v_items
  from jsonb_array_elements(coalesce(v_base->'items','[]'::jsonb)) item
  left join lateral (
    select jsonb_build_object(
      'id',identity.id,
      'displayName',identity.display_name,
      'markKind',identity.mark_kind,
      'iconKey',identity.icon_key,
      'canManage',atlas.correspondence_identity_manage_authorized_self_v1(identity.id),
      'logo',case when logo.id is null then null else jsonb_build_object(
        'assetId',logo.id,
        'storageBucket',logo.storage_bucket,
        'storagePath',logo.storage_object_path,
        'mimeType',logo.mime_type,
        'byteSize',logo.byte_size
      ) end
    ) as identity_json
    from atlas.correspondence_identity_endpoint_bindings binding
    join atlas.correspondence_identities identity
      on identity.id=binding.correspondence_identity_id
     and identity.identity_state='active'
    left join atlas.correspondence_identity_logo_assets logo
      on logo.id=identity.active_logo_asset_id
     and logo.asset_state='ready'
    where binding.communication_endpoint_id=(item->>'communicationEndpointId')::uuid
      and binding.binding_state='active'
    order by binding.created_at desc,binding.id desc
    limit 1
  ) identity_projection on true;

  return (v_base-'items') || jsonb_build_object(
    'contractVersion','organization_correspondence_access_v2',
    'identityRoot','communication_endpoint',
    'items',v_items
  );
end;
$function$;

revoke all on function atlas.organization_correspondence_access_self_api_v2(uuid) from public,anon;
grant execute on function atlas.organization_correspondence_access_self_api_v2(uuid) to authenticated,service_role;

comment on function atlas.organization_correspondence_access_self_api_v2(uuid) is
'Common Communication Endpoint access metadata enriched with Correspondence Identity presentation. Endpoint remains the identity root; Correspondence Identity is presentation metadata, not Conversation or transport identity.';

commit;
