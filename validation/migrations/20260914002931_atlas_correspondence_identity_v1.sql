-- Atlas Correspondence Identity v1 postconditions.
-- Disposable production-schema clone only.
BEGIN;
DO $proof$
declare
  v_uid uuid := '33333333-3333-4333-8333-333333333333'::uuid;
  v_endpoint_one uuid := '84848484-8484-4484-8484-848484848484'::uuid;
  v_endpoint_two uuid := '85858585-8585-4585-8585-858585858585'::uuid;
  v_other_endpoint uuid := '94949494-9494-4494-8494-949494949494'::uuid;
  v_identity uuid;
  v_asset uuid;
  v_result jsonb;
  v_home jsonb;
  v_path text;
  v_count integer;
  v_failed boolean;
begin
  perform set_config('request.jwt.claim.sub',v_uid::text,true);

  v_home := public.institutional_communications_home_self_api_v2();
  if v_home->>'contractVersion' <> 'institutional_communications_home_v2' then
    raise exception 'Mailroom home v2 contract missing: %',v_home;
  end if;
  if jsonb_array_length(v_home->'items') <> 3 then
    raise exception 'Expected three fixture endpoints in Mailroom home, got %.',jsonb_array_length(v_home->'items');
  end if;
  if exists(
    select 1 from jsonb_array_elements(v_home->'items') item
    where item->>'communicationEndpointId'=v_endpoint_one::text
      and item->'correspondenceIdentity' <> 'null'::jsonb
  ) then raise exception 'Unconfigured endpoint unexpectedly received a correspondence identity.'; end if;

  v_result := public.create_correspondence_identity_for_endpoint_self_api_v1(
    v_endpoint_one,'Primary Endeavor','flower'
  );
  v_identity := (v_result->>'correspondenceIdentityId')::uuid;
  if v_identity is null or v_result->>'markKind' <> 'icon' or v_result->>'iconKey' <> 'flower' then
    raise exception 'Correspondence identity creation projection wrong: %',v_result;
  end if;
  if not exists(
    select 1 from atlas.correspondence_identity_endpoint_bindings
    where correspondence_identity_id=v_identity and communication_endpoint_id=v_endpoint_one and binding_state='active'
  ) then raise exception 'Create-with-endpoint did not create an active binding.'; end if;

  v_result := public.bind_correspondence_identity_endpoint_self_api_v1(v_identity,v_endpoint_two);
  if not coalesce((v_result->>'ok')::boolean,false) then raise exception 'Second endpoint binding failed: %',v_result; end if;
  select count(*) into v_count
  from atlas.correspondence_identity_endpoint_bindings
  where correspondence_identity_id=v_identity and binding_state='active';
  if v_count <> 2 then raise exception 'Expected two active same-identity endpoint bindings, got %.',v_count; end if;

  v_home := public.institutional_communications_home_self_api_v2();
  if (select count(*) from jsonb_array_elements(v_home->'items') item where item->'correspondenceIdentity'->>'id'=v_identity::text) <> 2 then
    raise exception 'Mailroom home did not project the same correspondence identity onto both endpoints: %',v_home;
  end if;

  v_failed := false;
  begin
    perform public.bind_correspondence_identity_endpoint_self_api_v1(v_identity,v_other_endpoint);
  exception when others then
    v_failed := true;
  end;
  if not v_failed then raise exception 'Cross-custody endpoint binding did not fail closed.'; end if;

  v_result := public.set_correspondence_identity_mark_self_api_v1(v_identity,'monogram',null);
  if v_result->>'markKind' <> 'monogram' then raise exception 'Monogram mark switch failed: %',v_result; end if;

  v_result := public.prepare_correspondence_identity_logo_self_api_v1(
    v_identity,'primary-logo.png','image/png',128
  );
  v_asset := (v_result->>'assetId')::uuid;
  v_path := v_result->>'storagePath';
  if v_asset is null or v_result->>'storageBucket' <> 'atlas-correspondence-identity-marks' or v_path is null then
    raise exception 'Logo preparation projection wrong: %',v_result;
  end if;
  if not atlas.correspondence_identity_logo_storage_authorized_self_v1('atlas-correspondence-identity-marks',v_path,'insert') then
    raise exception 'Prepared logo upload was not storage-authorized for its stager.';
  end if;

  insert into storage.objects(bucket_id,name,owner,metadata)
  values(
    'atlas-correspondence-identity-marks',v_path,v_uid,
    jsonb_build_object('size',128,'mimetype','image/png')
  );

  v_result := public.commit_correspondence_identity_logo_self_api_v1(v_asset);
  if v_result->>'markKind' <> 'logo' then raise exception 'Logo commit did not activate logo mark: %',v_result; end if;
  if not exists(
    select 1 from atlas.correspondence_identities
    where id=v_identity and mark_kind='logo' and active_logo_asset_id=v_asset
  ) then raise exception 'Correspondence identity did not point at committed logo asset.'; end if;
  if not atlas.correspondence_identity_logo_storage_authorized_self_v1('atlas-correspondence-identity-marks',v_path,'select') then
    raise exception 'Ready logo was not readable by an authorized viewer.';
  end if;

  v_home := public.institutional_communications_home_self_api_v2();
  if not exists(
    select 1 from jsonb_array_elements(v_home->'items') item
    where item->>'communicationEndpointId'=v_endpoint_one::text
      and item->'correspondenceIdentity'->>'displayName'='Primary Endeavor'
      and item->'correspondenceIdentity'->>'markKind'='logo'
      and item->'correspondenceIdentity'->'logo'->>'assetId'=v_asset::text
      and item->'correspondenceIdentity'->'logo'->>'storagePath'=v_path
      and (item->'correspondenceIdentity'->>'canManage')::boolean
  ) then raise exception 'Mailroom home did not project committed logo identity correctly: %',v_home; end if;

  v_failed := false;
  begin
    perform public.create_correspondence_identity_for_endpoint_self_api_v1(v_endpoint_one,'Duplicate','star');
  exception when others then
    v_failed := true;
  end;
  if not v_failed then raise exception 'Endpoint accepted a second active correspondence identity.'; end if;

  if not exists(
    select 1 from storage.buckets
    where id='atlas-correspondence-identity-marks'
      and not public
      and file_size_limit=5242880
      and allowed_mime_types @> array['image/png','image/jpeg','image/webp']::text[]
  ) then raise exception 'Correspondence mark storage bucket contract is wrong.'; end if;

  if has_table_privilege('authenticated','atlas.correspondence_identities','SELECT')
     or has_table_privilege('authenticated','atlas.correspondence_identity_endpoint_bindings','SELECT')
     or has_table_privilege('authenticated','atlas.correspondence_identity_logo_assets','SELECT') then
    raise exception 'Authenticated role received direct Correspondence Identity table read authority.';
  end if;

  if has_function_privilege('anon','public.institutional_communications_home_self_api_v2()','EXECUTE')
     or has_function_privilege('anon','public.create_correspondence_identity_for_endpoint_self_api_v1(uuid,text,text)','EXECUTE')
     or has_function_privilege('anon','public.prepare_correspondence_identity_logo_self_api_v1(uuid,text,text,bigint)','EXECUTE') then
    raise exception 'Anonymous role received Correspondence Identity RPC execution authority.';
  end if;
  if not has_function_privilege('authenticated','public.institutional_communications_home_self_api_v2()','EXECUTE')
     or not has_function_privilege('authenticated','public.create_correspondence_identity_for_endpoint_self_api_v1(uuid,text,text)','EXECUTE')
     or not has_function_privilege('authenticated','public.commit_correspondence_identity_logo_self_api_v1(uuid)','EXECUTE') then
    raise exception 'Authenticated role is missing Correspondence Identity RPC authority.';
  end if;

  if not exists(
    select 1 from pg_policies
    where schemaname='storage' and tablename='objects'
      and policyname='atlas_correspondence_identity_mark_insert_v1' and cmd='INSERT'
  ) or not exists(
    select 1 from pg_policies
    where schemaname='storage' and tablename='objects'
      and policyname='atlas_correspondence_identity_mark_select_v1' and cmd='SELECT'
  ) or not exists(
    select 1 from pg_policies
    where schemaname='storage' and tablename='objects'
      and policyname='atlas_correspondence_identity_mark_delete_v1' and cmd='DELETE'
  ) then raise exception 'Correspondence Identity storage policies are incomplete.'; end if;

  if not exists(
    select 1 from atlas.authenticated_rpc_registry r
    where r.signature='atlas.institutional_communications_home_self_api_v2()'
      and r.classification='app_endpoint'
      and r.review_status='active'
      and r.authenticated_execute_expected
      and not r.anonymous_execute_expected
      and r.security_definer_expected
  ) then raise exception 'Mailroom home v2 governance registration incomplete.'; end if;
  if not exists(
    select 1 from atlas.authenticated_rpc_registry r
    where r.signature='atlas.correspondence_identity_logo_storage_authorized_self_v1(p_bucket_id text, p_object_name text, p_action text)'
      and r.classification='policy_or_composition_helper'
      and r.policy_reference_count=3
      and r.authenticated_execute_expected
      and not r.anonymous_execute_expected
  ) then raise exception 'Logo storage helper governance registration incomplete.'; end if;

  raise notice 'Atlas Correspondence Identity v1 postconditions passed.';
end;
$proof$;
ROLLBACK;
