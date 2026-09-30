-- ATLAS_REALITY_PLACE_RESOLUTION_V1: source identity registry

create table if not exists reality.place_identity_keys (
  id uuid primary key default gen_random_uuid(),
  entity_id uuid not null references reality.entities(id) on delete restrict,
  identity_namespace text not null check (btrim(identity_namespace) <> ''),
  identity_key text not null check (btrim(identity_key) <> ''),
  identity_state text not null default 'active' check (identity_state in ('active','retired')),
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence)='object'),
  identity_basis jsonb not null default '{}'::jsonb check (jsonb_typeof(identity_basis)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  retired_at timestamptz,
  check ((identity_state='active' and retired_at is null) or identity_state='retired')
);

create unique index if not exists reality_place_identity_keys_active_key_uidx
  on reality.place_identity_keys (lower(identity_namespace),identity_key)
  where identity_state='active';

create index if not exists reality_place_identity_keys_entity_idx
  on reality.place_identity_keys (entity_id)
  where identity_state='active';

alter table reality.place_identity_keys enable row level security;
revoke all on reality.place_identity_keys from public,anon,authenticated,service_role;
grant select on reality.place_identity_keys to service_role;

create or replace function reality.register_place_identity_key_service_v1(
  p_entity_id uuid,
  p_identity_namespace text,
  p_identity_key text,
  p_evidence jsonb default '{}'::jsonb,
  p_identity_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path to ''
as $function$
declare
  v_namespace text:=lower(btrim(coalesce(p_identity_namespace,'')));
  v_key text:=btrim(coalesce(p_identity_key,''));
  v_entity reality.entities%rowtype;
  v_existing reality.place_identity_keys%rowtype;
  v_id uuid;
begin
  if p_entity_id is null then raise exception 'Place Entity id is required.' using errcode='22023'; end if;
  if v_namespace='' or v_namespace !~ '^[a-z0-9][a-z0-9._:-]*$' then raise exception 'Place identity namespace is invalid.' using errcode='22023'; end if;
  if v_key='' then raise exception 'Place identity key is required.' using errcode='22023'; end if;
  if p_evidence is null or jsonb_typeof(p_evidence)<>'object'
     or p_identity_basis is null or jsonb_typeof(p_identity_basis)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Place identity evidence, basis, and metadata must be JSON objects.' using errcode='22023';
  end if;

  select * into v_entity from reality.entities where id=p_entity_id and identity_state='canonical';
  if v_entity.id is null or v_entity.entity_kind<>'place' then raise exception 'Canonical Reality Place Entity required.' using errcode='23514'; end if;
  if not exists(select 1 from reality.place_profiles pp where pp.entity_id=p_entity_id and pp.profile_state='active') then
    raise exception 'Active governed Place profile required before identity-key registration.' using errcode='23514';
  end if;

  select * into v_existing
  from reality.place_identity_keys
  where lower(identity_namespace)=v_namespace and identity_key=v_key and identity_state='active'
  limit 1;

  if v_existing.id is not null then
    if v_existing.entity_id<>p_entity_id then
      raise exception 'Active Place identity key is already bound to a different canonical Place.' using errcode='23505';
    end if;
    return jsonb_build_object('contractVersion','reality_place_identity_key_v1','state','existing','identityKeyId',v_existing.id,'entityId',v_existing.entity_id,'identityNamespace',v_namespace,'identityKey',v_key);
  end if;

  insert into reality.place_identity_keys(entity_id,identity_namespace,identity_key,evidence,identity_basis,metadata)
  values(p_entity_id,v_namespace,v_key,p_evidence,p_identity_basis,p_metadata)
  returning id into v_id;

  return jsonb_build_object('contractVersion','reality_place_identity_key_v1','state','registered','identityKeyId',v_id,'entityId',p_entity_id,'identityNamespace',v_namespace,'identityKey',v_key);
end
$function$;

revoke all on function reality.register_place_identity_key_service_v1(uuid,text,text,jsonb,jsonb,jsonb) from public,anon,authenticated;
grant execute on function reality.register_place_identity_key_service_v1(uuid,text,text,jsonb,jsonb,jsonb) to service_role;

create or replace function reality.resolve_place_identity_service_v1(
  p_identity_namespace text,
  p_identity_key text
) returns jsonb
language plpgsql stable security definer set search_path to ''
as $function$
declare
  v_namespace text:=lower(btrim(coalesce(p_identity_namespace,'')));
  v_key text:=btrim(coalesce(p_identity_key,''));
  v_identity reality.place_identity_keys%rowtype;
  v_entity reality.entities%rowtype;
  v_profile reality.place_profiles%rowtype;
begin
  if v_namespace='' or v_key='' then raise exception 'Place identity namespace and key are required.' using errcode='22023'; end if;
  select * into v_identity from reality.place_identity_keys where lower(identity_namespace)=v_namespace and identity_key=v_key and identity_state='active' limit 1;
  if v_identity.id is null then
    return jsonb_build_object('contractVersion','reality_place_identity_resolution_v1','state','absent','identityNamespace',v_namespace,'identityKey',v_key);
  end if;

  select * into v_entity from reality.entities where id=v_identity.entity_id;
  select * into v_profile from reality.place_profiles where entity_id=v_identity.entity_id;
  if v_entity.id is null or v_entity.identity_state<>'canonical' or v_entity.entity_kind<>'place' or v_profile.entity_id is null or v_profile.profile_state<>'active' then
    return jsonb_build_object('contractVersion','reality_place_identity_resolution_v1','state','invalid_binding','identityNamespace',v_namespace,'identityKey',v_key,'entityId',v_identity.entity_id);
  end if;

  return jsonb_build_object(
    'contractVersion','reality_place_identity_resolution_v1','state','resolved',
    'identityNamespace',v_namespace,'identityKey',v_key,'identityKeyId',v_identity.id,
    'entityId',v_entity.id,'stableKey',v_entity.stable_key,'displayName',v_entity.display_name,
    'placeKind',v_profile.place_kind,'countryCode',v_profile.country_code,
    'centroidLatitude',v_profile.centroid_latitude,'centroidLongitude',v_profile.centroid_longitude,
    'coordinatePrecision',v_profile.coordinate_precision
  );
end
$function$;

revoke all on function reality.resolve_place_identity_service_v1(text,text) from public,anon,authenticated;
grant execute on function reality.resolve_place_identity_service_v1(text,text) to service_role;
