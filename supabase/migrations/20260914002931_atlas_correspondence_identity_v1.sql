begin;

-- Atlas Correspondence Identity v1
--
-- A Correspondence Identity is the recognizable endeavor/persona presented in
-- Mailroom. It sits above one or more durable Communication Endpoints. Endpoints
-- remain transport/address routes; identity marks do not become provider truth.

create table atlas.correspondence_identities (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid references atlas.principals(id) on delete cascade,
  organization_id uuid references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid,
  display_name text not null,
  identity_state text not null default 'active',
  mark_kind text not null default 'monogram',
  icon_key text,
  active_logo_asset_id uuid,
  created_by_user_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint correspondence_identities_custody_root_check
    check (((principal_id is not null)::int + (organization_id is not null)::int) = 1),
  constraint correspondence_identities_principal_has_no_unit_check
    check (principal_id is null or organization_unit_id is null),
  constraint correspondence_identities_display_name_check
    check (btrim(display_name) <> ''),
  constraint correspondence_identities_state_check
    check (identity_state in ('active','inactive')),
  constraint correspondence_identities_mark_kind_check
    check (mark_kind in ('monogram','icon','logo')),
  constraint correspondence_identities_icon_shape_check
    check ((mark_kind = 'icon' and nullif(btrim(icon_key),'') is not null) or mark_kind <> 'icon'),
  constraint correspondence_identities_metadata_check
    check (jsonb_typeof(metadata) = 'object'),
  constraint correspondence_identities_organization_unit_fkey
    foreign key (organization_id, organization_unit_id)
      references atlas.organization_units(organization_id,id) on delete restrict
);

create index correspondence_identities_principal_idx
  on atlas.correspondence_identities(principal_id)
  where principal_id is not null;
create index correspondence_identities_organization_idx
  on atlas.correspondence_identities(organization_id,organization_unit_id)
  where organization_id is not null;

create trigger correspondence_identities_set_updated_at
before update on atlas.correspondence_identities
for each row execute function atlas.set_updated_at();

create table atlas.correspondence_identity_endpoint_bindings (
  id uuid primary key default gen_random_uuid(),
  correspondence_identity_id uuid not null references atlas.correspondence_identities(id) on delete cascade,
  communication_endpoint_id uuid not null references atlas.communication_endpoints(id) on delete cascade,
  binding_state text not null default 'active',
  created_by_user_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  retired_at timestamptz,
  constraint correspondence_identity_endpoint_bindings_state_check
    check (binding_state in ('active','retired')),
  constraint correspondence_identity_endpoint_bindings_retirement_check
    check ((binding_state='active' and retired_at is null) or binding_state='retired'),
  constraint correspondence_identity_endpoint_bindings_metadata_check
    check (jsonb_typeof(metadata) = 'object')
);

create unique index correspondence_identity_one_active_binding_per_endpoint_v1
  on atlas.correspondence_identity_endpoint_bindings(communication_endpoint_id)
  where binding_state='active';
create index correspondence_identity_endpoint_bindings_identity_idx
  on atlas.correspondence_identity_endpoint_bindings(correspondence_identity_id,binding_state);

create table atlas.correspondence_identity_logo_assets (
  id uuid primary key default gen_random_uuid(),
  correspondence_identity_id uuid not null references atlas.correspondence_identities(id) on delete cascade,
  storage_bucket text not null default 'atlas-correspondence-identity-marks',
  storage_object_path text not null,
  original_filename text,
  mime_type text not null,
  byte_size bigint not null,
  asset_state text not null default 'staging',
  staged_by_user_id uuid not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  ready_at timestamptz,
  revoked_at timestamptz,
  constraint correspondence_identity_logo_assets_bucket_check
    check (storage_bucket='atlas-correspondence-identity-marks'),
  constraint correspondence_identity_logo_assets_path_check
    check (btrim(storage_object_path) <> ''),
  constraint correspondence_identity_logo_assets_mime_check
    check (mime_type in ('image/png','image/jpeg','image/webp')),
  constraint correspondence_identity_logo_assets_byte_size_check
    check (byte_size between 1 and 5242880),
  constraint correspondence_identity_logo_assets_state_check
    check (asset_state in ('staging','ready','revoked')),
  constraint correspondence_identity_logo_assets_metadata_check
    check (jsonb_typeof(metadata) = 'object'),
  unique(storage_bucket,storage_object_path)
);

alter table atlas.correspondence_identities
  add constraint correspondence_identities_active_logo_asset_fkey
  foreign key (active_logo_asset_id)
  references atlas.correspondence_identity_logo_assets(id)
  on delete set null;

alter table atlas.correspondence_identities enable row level security;
alter table atlas.correspondence_identity_endpoint_bindings enable row level security;
alter table atlas.correspondence_identity_logo_assets enable row level security;

revoke all on atlas.correspondence_identities from anon, authenticated;
revoke all on atlas.correspondence_identity_endpoint_bindings from anon, authenticated;
revoke all on atlas.correspondence_identity_logo_assets from anon, authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values(
  'atlas-correspondence-identity-marks',
  'atlas-correspondence-identity-marks',
  false,
  5242880,
  array['image/png','image/jpeg','image/webp']::text[]
)
on conflict (id) do nothing;

create or replace function atlas.correspondence_identity_read_authorized_self_v1(
  p_correspondence_identity_id uuid
) returns boolean
language plpgsql
stable
security definer
set search_path to pg_catalog,atlas,auth
as $function$
declare
  v_identity atlas.correspondence_identities%rowtype;
  v_member atlas.organization_memberships%rowtype;
begin
  if auth.uid() is null or p_correspondence_identity_id is null then return false; end if;
  select * into v_identity
  from atlas.correspondence_identities
  where id=p_correspondence_identity_id and identity_state='active';
  if v_identity.id is null then return false; end if;

  if v_identity.principal_id is not null then
    return exists(
      select 1 from atlas.principals p
      where p.id=v_identity.principal_id and p.user_id=auth.uid() and p.status='active'
    );
  end if;

  select * into v_member
  from atlas.organization_memberships m
  where m.organization_id=v_identity.organization_id
    and m.user_id=auth.uid()
    and m.active
  order by m.created_at,m.id
  limit 1;
  if v_member.id is null then return false; end if;
  if v_member.role='owner' then return true; end if;

  return exists(
    select 1
    from atlas.correspondence_identity_endpoint_bindings b
    where b.correspondence_identity_id=v_identity.id
      and b.binding_state='active'
      and atlas.communication_endpoint_membership_has_capability_v1(
        b.communication_endpoint_id,v_member.id,'view'
      )
  );
end;
$function$;

create or replace function atlas.correspondence_identity_manage_authorized_self_v1(
  p_correspondence_identity_id uuid
) returns boolean
language plpgsql
stable
security definer
set search_path to pg_catalog,atlas,auth
as $function$
declare
  v_identity atlas.correspondence_identities%rowtype;
  v_member atlas.organization_memberships%rowtype;
begin
  if auth.uid() is null or p_correspondence_identity_id is null then return false; end if;
  select * into v_identity
  from atlas.correspondence_identities
  where id=p_correspondence_identity_id and identity_state='active';
  if v_identity.id is null then return false; end if;

  if v_identity.principal_id is not null then
    return exists(
      select 1 from atlas.principals p
      where p.id=v_identity.principal_id and p.user_id=auth.uid() and p.status='active'
    );
  end if;

  select * into v_member
  from atlas.organization_memberships m
  where m.organization_id=v_identity.organization_id
    and m.user_id=auth.uid()
    and m.active
  order by m.created_at,m.id
  limit 1;
  if v_member.id is null then return false; end if;
  if v_member.role='owner' then return true; end if;

  return exists(
    select 1
    from atlas.correspondence_identity_endpoint_bindings b
    where b.correspondence_identity_id=v_identity.id
      and b.binding_state='active'
      and atlas.communication_endpoint_membership_has_capability_v1(
        b.communication_endpoint_id,v_member.id,'admin'
      )
  );
end;
$function$;

create or replace function atlas.correspondence_identity_logo_storage_authorized_self_v1(
  p_bucket_id text,
  p_object_name text,
  p_action text
) returns boolean
language plpgsql
stable
security definer
set search_path to pg_catalog,atlas,auth
as $function$
declare
  v_asset atlas.correspondence_identity_logo_assets%rowtype;
  v_action text := lower(btrim(coalesce(p_action,'')));
begin
  if auth.uid() is null
     or p_bucket_id <> 'atlas-correspondence-identity-marks'
     or nullif(btrim(coalesce(p_object_name,'')),'') is null then
    return false;
  end if;

  select * into v_asset
  from atlas.correspondence_identity_logo_assets
  where storage_bucket=p_bucket_id and storage_object_path=p_object_name;
  if v_asset.id is null then return false; end if;

  if v_action='insert' then
    return v_asset.asset_state='staging'
      and v_asset.staged_by_user_id=auth.uid()
      and atlas.correspondence_identity_manage_authorized_self_v1(v_asset.correspondence_identity_id);
  elsif v_action='select' then
    return (v_asset.asset_state='ready'
      and atlas.correspondence_identity_read_authorized_self_v1(v_asset.correspondence_identity_id))
      or (v_asset.asset_state='staging'
        and v_asset.staged_by_user_id=auth.uid()
        and atlas.correspondence_identity_manage_authorized_self_v1(v_asset.correspondence_identity_id));
  elsif v_action='delete' then
    return v_asset.asset_state in ('staging','revoked')
      and (v_asset.staged_by_user_id=auth.uid()
        or atlas.correspondence_identity_manage_authorized_self_v1(v_asset.correspondence_identity_id));
  end if;
  return false;
end;
$function$;

create policy atlas_correspondence_identity_mark_insert_v1
on storage.objects
for insert
to authenticated
with check (atlas.correspondence_identity_logo_storage_authorized_self_v1(bucket_id,name,'insert'));

create policy atlas_correspondence_identity_mark_select_v1
on storage.objects
for select
to authenticated
using (atlas.correspondence_identity_logo_storage_authorized_self_v1(bucket_id,name,'select'));

create policy atlas_correspondence_identity_mark_delete_v1
on storage.objects
for delete
to authenticated
using (atlas.correspondence_identity_logo_storage_authorized_self_v1(bucket_id,name,'delete'));

create or replace function atlas.create_correspondence_identity_for_endpoint_self_api_v1(
  p_communication_endpoint_id uuid,
  p_display_name text,
  p_icon_key text default null
) returns jsonb
language plpgsql
security definer
set search_path to pg_catalog,atlas,auth
as $function$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_member atlas.organization_memberships%rowtype;
  v_identity atlas.correspondence_identities%rowtype;
  v_icon text := nullif(lower(btrim(coalesce(p_icon_key,''))), '');
  v_name text := btrim(coalesce(p_display_name,''));
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_communication_endpoint_id is null then raise exception 'Communication endpoint is required.' using errcode='22023'; end if;
  if v_name='' then raise exception 'Correspondence identity name is required.' using errcode='22023'; end if;
  if v_icon is not null and v_icon <> all(array[
    'briefcase','building','home','flower','leaf','heart','book','megaphone','community','star','person','spark'
  ]) then
    raise exception 'Unsupported correspondence icon.' using errcode='22023';
  end if;

  select * into v_endpoint
  from atlas.communication_endpoints
  where id=p_communication_endpoint_id and endpoint_state='active';
  if v_endpoint.id is null then raise exception 'Communication endpoint not found.' using errcode='23503'; end if;

  if v_endpoint.principal_id is not null then
    if not exists(
      select 1 from atlas.principals p
      where p.id=v_endpoint.principal_id and p.user_id=auth.uid() and p.status='active'
    ) then raise exception 'Correspondence identity administration required.' using errcode='42501'; end if;
  else
    select * into v_member
    from atlas.organization_memberships m
    where m.organization_id=v_endpoint.organization_id and m.user_id=auth.uid() and m.active
    order by m.created_at,m.id limit 1;
    if v_member.id is null
       or not (v_member.role='owner' or atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'admin')) then
      raise exception 'Correspondence identity administration required.' using errcode='42501';
    end if;
  end if;

  if exists(
    select 1 from atlas.correspondence_identity_endpoint_bindings b
    where b.communication_endpoint_id=v_endpoint.id and b.binding_state='active'
  ) then raise exception 'Communication endpoint already has a correspondence identity.' using errcode='23505'; end if;

  insert into atlas.correspondence_identities(
    principal_id,organization_id,organization_unit_id,display_name,mark_kind,icon_key,created_by_user_id,metadata
  ) values(
    v_endpoint.principal_id,v_endpoint.organization_id,v_endpoint.organization_unit_id,v_name,
    case when v_icon is null then 'monogram' else 'icon' end,v_icon,auth.uid(),
    jsonb_build_object('source','atlas_correspondence_identity_v1')
  ) returning * into v_identity;

  insert into atlas.correspondence_identity_endpoint_bindings(
    correspondence_identity_id,communication_endpoint_id,created_by_user_id,metadata
  ) values(
    v_identity.id,v_endpoint.id,auth.uid(),jsonb_build_object('source','create_with_endpoint_v1')
  );

  return jsonb_build_object(
    'ok',true,
    'correspondenceIdentityId',v_identity.id,
    'displayName',v_identity.display_name,
    'markKind',v_identity.mark_kind,
    'iconKey',v_identity.icon_key,
    'communicationEndpointId',v_endpoint.id
  );
end;
$function$;

create or replace function atlas.bind_correspondence_identity_endpoint_self_api_v1(
  p_correspondence_identity_id uuid,
  p_communication_endpoint_id uuid
) returns jsonb
language plpgsql
security definer
set search_path to pg_catalog,atlas,auth
as $function$
declare
  v_identity atlas.correspondence_identities%rowtype;
  v_endpoint atlas.communication_endpoints%rowtype;
  v_member atlas.organization_memberships%rowtype;
  v_existing atlas.correspondence_identity_endpoint_bindings%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if not atlas.correspondence_identity_manage_authorized_self_v1(p_correspondence_identity_id) then
    raise exception 'Correspondence identity administration required.' using errcode='42501';
  end if;
  select * into v_identity from atlas.correspondence_identities where id=p_correspondence_identity_id and identity_state='active';
  select * into v_endpoint from atlas.communication_endpoints where id=p_communication_endpoint_id and endpoint_state='active';
  if v_identity.id is null or v_endpoint.id is null then raise exception 'Correspondence identity or endpoint not found.' using errcode='23503'; end if;

  if v_identity.principal_id is not null then
    if v_endpoint.principal_id is distinct from v_identity.principal_id then
      raise exception 'Endpoint custody does not match correspondence identity.' using errcode='23514';
    end if;
  else
    if v_endpoint.organization_id is distinct from v_identity.organization_id
       or (v_identity.organization_unit_id is not null and v_endpoint.organization_unit_id is distinct from v_identity.organization_unit_id) then
      raise exception 'Endpoint custody does not match correspondence identity.' using errcode='23514';
    end if;
    select * into v_member
    from atlas.organization_memberships m
    where m.organization_id=v_endpoint.organization_id and m.user_id=auth.uid() and m.active
    order by m.created_at,m.id limit 1;
    if v_member.id is null
       or not (v_member.role='owner' or atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'admin')) then
      raise exception 'Endpoint administration required.' using errcode='42501';
    end if;
  end if;

  select * into v_existing
  from atlas.correspondence_identity_endpoint_bindings b
  where b.communication_endpoint_id=v_endpoint.id and b.binding_state='active'
  limit 1;
  if v_existing.id is not null then
    if v_existing.correspondence_identity_id=v_identity.id then
      return jsonb_build_object('ok',true,'alreadyBound',true,'correspondenceIdentityId',v_identity.id,'communicationEndpointId',v_endpoint.id);
    end if;
    raise exception 'Communication endpoint already has a different correspondence identity.' using errcode='23505';
  end if;

  insert into atlas.correspondence_identity_endpoint_bindings(
    correspondence_identity_id,communication_endpoint_id,created_by_user_id,metadata
  ) values(v_identity.id,v_endpoint.id,auth.uid(),jsonb_build_object('source','bind_endpoint_v1'));

  return jsonb_build_object('ok',true,'alreadyBound',false,'correspondenceIdentityId',v_identity.id,'communicationEndpointId',v_endpoint.id);
end;
$function$;

create or replace function atlas.set_correspondence_identity_mark_self_api_v1(
  p_correspondence_identity_id uuid,
  p_mark_kind text,
  p_icon_key text default null
) returns jsonb
language plpgsql
security definer
set search_path to pg_catalog,atlas,auth
as $function$
declare
  v_kind text := lower(btrim(coalesce(p_mark_kind,'')));
  v_icon text := nullif(lower(btrim(coalesce(p_icon_key,''))), '');
  v_identity atlas.correspondence_identities%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if not atlas.correspondence_identity_manage_authorized_self_v1(p_correspondence_identity_id) then
    raise exception 'Correspondence identity administration required.' using errcode='42501';
  end if;
  if v_kind not in ('monogram','icon') then raise exception 'Mark kind must be monogram or icon.' using errcode='22023'; end if;
  if v_kind='icon' and (v_icon is null or v_icon <> all(array[
    'briefcase','building','home','flower','leaf','heart','book','megaphone','community','star','person','spark'
  ])) then raise exception 'Unsupported correspondence icon.' using errcode='22023'; end if;

  update atlas.correspondence_identities
  set mark_kind=v_kind,
      icon_key=case when v_kind='icon' then v_icon else null end,
      active_logo_asset_id=null
  where id=p_correspondence_identity_id
  returning * into v_identity;

  return jsonb_build_object('ok',true,'correspondenceIdentityId',v_identity.id,'markKind',v_identity.mark_kind,'iconKey',v_identity.icon_key);
end;
$function$;

create or replace function atlas.prepare_correspondence_identity_logo_self_api_v1(
  p_correspondence_identity_id uuid,
  p_original_filename text,
  p_mime_type text,
  p_byte_size bigint
) returns jsonb
language plpgsql
security definer
set search_path to pg_catalog,atlas,auth
as $function$
declare
  v_asset_id uuid := gen_random_uuid();
  v_mime text := lower(split_part(btrim(coalesce(p_mime_type,'')),';',1));
  v_ext text;
  v_path text;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if not atlas.correspondence_identity_manage_authorized_self_v1(p_correspondence_identity_id) then
    raise exception 'Correspondence identity administration required.' using errcode='42501';
  end if;
  if p_byte_size is null or p_byte_size < 1 or p_byte_size > 5242880 then
    raise exception 'Logo must be between 1 byte and 5 MB.' using errcode='22023';
  end if;
  v_ext := case v_mime when 'image/png' then 'png' when 'image/jpeg' then 'jpg' when 'image/webp' then 'webp' else null end;
  if v_ext is null then raise exception 'Logo must be PNG, JPEG, or WebP.' using errcode='22023'; end if;
  v_path := 'correspondence-identities/' || p_correspondence_identity_id::text || '/' || v_asset_id::text || '/logo.' || v_ext;

  insert into atlas.correspondence_identity_logo_assets(
    id,correspondence_identity_id,storage_object_path,original_filename,mime_type,byte_size,staged_by_user_id,metadata
  ) values(
    v_asset_id,p_correspondence_identity_id,v_path,nullif(btrim(coalesce(p_original_filename,'')),''),v_mime,p_byte_size,auth.uid(),
    jsonb_build_object('source','atlas_correspondence_identity_logo_v1')
  );

  return jsonb_build_object(
    'ok',true,
    'assetId',v_asset_id,
    'correspondenceIdentityId',p_correspondence_identity_id,
    'storageBucket','atlas-correspondence-identity-marks',
    'storagePath',v_path,
    'mimeType',v_mime,
    'byteSize',p_byte_size
  );
end;
$function$;

create or replace function atlas.commit_correspondence_identity_logo_self_api_v1(
  p_asset_id uuid
) returns jsonb
language plpgsql
security definer
set search_path to pg_catalog,atlas,auth,storage
as $function$
declare
  v_asset atlas.correspondence_identity_logo_assets%rowtype;
  v_object storage.objects%rowtype;
  v_object_size bigint;
  v_object_mime text;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_asset from atlas.correspondence_identity_logo_assets where id=p_asset_id;
  if v_asset.id is null then raise exception 'Logo asset not found.' using errcode='23503'; end if;
  if not atlas.correspondence_identity_manage_authorized_self_v1(v_asset.correspondence_identity_id) then
    raise exception 'Correspondence identity administration required.' using errcode='42501';
  end if;
  if v_asset.asset_state <> 'staging' then raise exception 'Logo asset is not awaiting upload.' using errcode='55000'; end if;

  select * into v_object
  from storage.objects
  where bucket_id=v_asset.storage_bucket and name=v_asset.storage_object_path
  limit 1;
  if v_object.id is null then raise exception 'Uploaded logo object was not found.' using errcode='23503'; end if;
  begin v_object_size := nullif(v_object.metadata->>'size','')::bigint; exception when others then v_object_size := null; end;
  v_object_mime := lower(nullif(v_object.metadata->>'mimetype',''));
  if v_object_size is not null and v_object_size <> v_asset.byte_size then
    raise exception 'Uploaded logo size does not match the prepared asset.' using errcode='22023';
  end if;
  if v_object_mime is not null and v_object_mime <> v_asset.mime_type then
    raise exception 'Uploaded logo type does not match the prepared asset.' using errcode='22023';
  end if;

  update atlas.correspondence_identity_logo_assets
  set asset_state='ready',ready_at=now()
  where id=v_asset.id;

  update atlas.correspondence_identities
  set mark_kind='logo',icon_key=null,active_logo_asset_id=v_asset.id
  where id=v_asset.correspondence_identity_id;

  return jsonb_build_object(
    'ok',true,
    'assetId',v_asset.id,
    'correspondenceIdentityId',v_asset.correspondence_identity_id,
    'markKind','logo',
    'storageBucket',v_asset.storage_bucket,
    'storagePath',v_asset.storage_object_path,
    'mimeType',v_asset.mime_type
  );
end;
$function$;

create or replace function atlas.institutional_communications_home_self_api_v2()
returns jsonb
language plpgsql
stable
security definer
set search_path to pg_catalog,atlas,auth
as $function$
declare
  v_base jsonb;
  v_items jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_base := atlas.institutional_communications_home_self_api_v1();

  select coalesce(jsonb_agg(
    item || jsonb_build_object('correspondenceIdentity',ci.identity_json)
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
      on identity.id=binding.correspondence_identity_id and identity.identity_state='active'
    left join atlas.correspondence_identity_logo_assets logo
      on logo.id=identity.active_logo_asset_id and logo.asset_state='ready'
    where binding.communication_endpoint_id=(item->>'communicationEndpointId')::uuid
      and binding.binding_state='active'
    order by binding.created_at desc,binding.id desc
    limit 1
  ) ci on true;

  return v_base || jsonb_build_object(
    'contractVersion','institutional_communications_home_v2',
    'items',v_items
  );
end;
$function$;

create or replace function public.institutional_communications_home_self_api_v2()
returns jsonb
language sql
set search_path to pg_catalog,atlas,public
as $function$
  select atlas.institutional_communications_home_self_api_v2();
$function$;

create or replace function public.create_correspondence_identity_for_endpoint_self_api_v1(
  p_communication_endpoint_id uuid,
  p_display_name text,
  p_icon_key text default null
) returns jsonb
language sql
set search_path to pg_catalog,atlas,public
as $function$
  select atlas.create_correspondence_identity_for_endpoint_self_api_v1($1,$2,$3);
$function$;

create or replace function public.bind_correspondence_identity_endpoint_self_api_v1(
  p_correspondence_identity_id uuid,
  p_communication_endpoint_id uuid
) returns jsonb
language sql
set search_path to pg_catalog,atlas,public
as $function$
  select atlas.bind_correspondence_identity_endpoint_self_api_v1($1,$2);
$function$;

create or replace function public.set_correspondence_identity_mark_self_api_v1(
  p_correspondence_identity_id uuid,
  p_mark_kind text,
  p_icon_key text default null
) returns jsonb
language sql
set search_path to pg_catalog,atlas,public
as $function$
  select atlas.set_correspondence_identity_mark_self_api_v1($1,$2,$3);
$function$;

create or replace function public.prepare_correspondence_identity_logo_self_api_v1(
  p_correspondence_identity_id uuid,
  p_original_filename text,
  p_mime_type text,
  p_byte_size bigint
) returns jsonb
language sql
set search_path to pg_catalog,atlas,public
as $function$
  select atlas.prepare_correspondence_identity_logo_self_api_v1($1,$2,$3,$4);
$function$;

create or replace function public.commit_correspondence_identity_logo_self_api_v1(
  p_asset_id uuid
) returns jsonb
language sql
set search_path to pg_catalog,atlas,public
as $function$
  select atlas.commit_correspondence_identity_logo_self_api_v1($1);
$function$;

revoke all on function atlas.correspondence_identity_read_authorized_self_v1(uuid) from public,anon;
revoke all on function atlas.correspondence_identity_manage_authorized_self_v1(uuid) from public,anon;
revoke all on function atlas.correspondence_identity_logo_storage_authorized_self_v1(text,text,text) from public,anon;
revoke all on function atlas.create_correspondence_identity_for_endpoint_self_api_v1(uuid,text,text) from public,anon;
revoke all on function atlas.bind_correspondence_identity_endpoint_self_api_v1(uuid,uuid) from public,anon;
revoke all on function atlas.set_correspondence_identity_mark_self_api_v1(uuid,text,text) from public,anon;
revoke all on function atlas.prepare_correspondence_identity_logo_self_api_v1(uuid,text,text,bigint) from public,anon;
revoke all on function atlas.commit_correspondence_identity_logo_self_api_v1(uuid) from public,anon;
revoke all on function atlas.institutional_communications_home_self_api_v2() from public,anon;

grant execute on function atlas.correspondence_identity_read_authorized_self_v1(uuid) to authenticated,service_role;
grant execute on function atlas.correspondence_identity_manage_authorized_self_v1(uuid) to authenticated,service_role;
grant execute on function atlas.correspondence_identity_logo_storage_authorized_self_v1(text,text,text) to authenticated,service_role;
grant execute on function atlas.create_correspondence_identity_for_endpoint_self_api_v1(uuid,text,text) to authenticated,service_role;
grant execute on function atlas.bind_correspondence_identity_endpoint_self_api_v1(uuid,uuid) to authenticated,service_role;
grant execute on function atlas.set_correspondence_identity_mark_self_api_v1(uuid,text,text) to authenticated,service_role;
grant execute on function atlas.prepare_correspondence_identity_logo_self_api_v1(uuid,text,text,bigint) to authenticated,service_role;
grant execute on function atlas.commit_correspondence_identity_logo_self_api_v1(uuid) to authenticated,service_role;
grant execute on function atlas.institutional_communications_home_self_api_v2() to authenticated,service_role;

revoke all on function public.institutional_communications_home_self_api_v2() from public,anon;
revoke all on function public.create_correspondence_identity_for_endpoint_self_api_v1(uuid,text,text) from public,anon;
revoke all on function public.bind_correspondence_identity_endpoint_self_api_v1(uuid,uuid) from public,anon;
revoke all on function public.set_correspondence_identity_mark_self_api_v1(uuid,text,text) from public,anon;
revoke all on function public.prepare_correspondence_identity_logo_self_api_v1(uuid,text,text,bigint) from public,anon;
revoke all on function public.commit_correspondence_identity_logo_self_api_v1(uuid) from public,anon;

grant execute on function public.institutional_communications_home_self_api_v2() to authenticated,service_role;
grant execute on function public.create_correspondence_identity_for_endpoint_self_api_v1(uuid,text,text) to authenticated,service_role;
grant execute on function public.bind_correspondence_identity_endpoint_self_api_v1(uuid,uuid) to authenticated,service_role;
grant execute on function public.set_correspondence_identity_mark_self_api_v1(uuid,text,text) to authenticated,service_role;
grant execute on function public.prepare_correspondence_identity_logo_self_api_v1(uuid,text,text,bigint) to authenticated,service_role;
grant execute on function public.commit_correspondence_identity_logo_self_api_v1(uuid) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,anonymous_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at,reviewed_at
) values
(
  'atlas.correspondence_identity_read_authorized_self_v1(p_correspondence_identity_id uuid)',
  'policy_or_composition_helper','verified','active',true,false,true,true,0,1,
  jsonb_build_object('purpose','Correspondence Identity read authorization and logo storage policy helper','migration','20260914002931'),now(),now()
),
(
  'atlas.correspondence_identity_manage_authorized_self_v1(p_correspondence_identity_id uuid)',
  'policy_or_composition_helper','verified','active',true,false,true,true,5,2,
  jsonb_build_object('purpose','Correspondence Identity administration authorization helper','migration','20260914002931'),now(),now()
),
(
  'atlas.correspondence_identity_logo_storage_authorized_self_v1(p_bucket_id text, p_object_name text, p_action text)',
  'policy_or_composition_helper','verified','active',true,false,true,true,0,3,
  jsonb_build_object('purpose','Private logo object storage policy helper','migration','20260914002931'),now(),now()
),
(
  'atlas.create_correspondence_identity_for_endpoint_self_api_v1(p_communication_endpoint_id uuid, p_display_name text, p_icon_key text)',
  'owner_admin_endpoint','verified','active',true,false,true,true,1,0,
  jsonb_build_object('purpose','Create and immediately bind a correspondence identity to an administered endpoint','migration','20260914002931'),now(),now()
),
(
  'atlas.bind_correspondence_identity_endpoint_self_api_v1(p_correspondence_identity_id uuid, p_communication_endpoint_id uuid)',
  'owner_admin_endpoint','verified','active',true,false,true,true,1,0,
  jsonb_build_object('purpose','Bind another same-custody endpoint to an existing correspondence identity','migration','20260914002931'),now(),now()
),
(
  'atlas.set_correspondence_identity_mark_self_api_v1(p_correspondence_identity_id uuid, p_mark_kind text, p_icon_key text)',
  'owner_admin_endpoint','verified','active',true,false,true,true,1,0,
  jsonb_build_object('purpose','Select a curated icon or monogram mark','migration','20260914002931'),now(),now()
),
(
  'atlas.prepare_correspondence_identity_logo_self_api_v1(p_correspondence_identity_id uuid, p_original_filename text, p_mime_type text, p_byte_size bigint)',
  'owner_admin_endpoint','verified','active',true,false,true,true,1,0,
  jsonb_build_object('purpose','Prepare a bounded private logo upload','migration','20260914002931'),now(),now()
),
(
  'atlas.commit_correspondence_identity_logo_self_api_v1(p_asset_id uuid)',
  'owner_admin_endpoint','verified','active',true,false,true,true,1,0,
  jsonb_build_object('purpose','Activate a successfully uploaded correspondence identity logo','migration','20260914002931'),now(),now()
),
(
  'atlas.institutional_communications_home_self_api_v2()',
  'app_endpoint','verified','active',true,false,true,true,1,0,
  jsonb_build_object('purpose','Institutional Mailroom home with optional correspondence identity presentation','migration','20260914002931'),now(),now()
)
on conflict (signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at;

comment on table atlas.correspondence_identities is
  'Recognizable endeavor/persona presentation identity above one or more Communication Endpoints. Endpoint remains the route; this row owns Mailroom-facing mark and label.';
comment on table atlas.correspondence_identity_endpoint_bindings is
  'History-preserving binding from a Correspondence Identity to durable Communication Endpoints. At most one active identity per endpoint.';
comment on table atlas.correspondence_identity_logo_assets is
  'Private, bounded user-uploaded logo assets for Correspondence Identity presentation. Not communication evidence or provider truth.';

commit;
