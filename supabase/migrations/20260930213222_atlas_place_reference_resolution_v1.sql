-- ATLAS_CONTACT_SET_PAIRED_GEOGRAPHY_V1: universal Place-reference resolution.

create or replace function atlas.resolve_or_admit_place_reference_service_v1(
  p_reference jsonb
) returns jsonb
language plpgsql security definer set search_path to ''
as $function$
declare
  v_place_id uuid;
  v_identity_namespace text;
  v_identity_key text;
  v_name text;
  v_admin_hint text;
  v_country_code text;
  v_place_kind text;
  v_resolution jsonb;
  v_entity reality.entities%rowtype;
  v_profile reality.place_profiles%rowtype;
  v_modes integer:=0;
begin
  if p_reference is null or jsonb_typeof(p_reference)<>'object' then
    raise exception 'Place reference must be a JSON object.' using errcode='22023';
  end if;
  if nullif(btrim(p_reference->>'placeEntityId'),'') is not null then v_modes:=v_modes+1; end if;
  if nullif(btrim(p_reference->>'identityNamespace'),'') is not null or nullif(btrim(p_reference->>'identityKey'),'') is not null then v_modes:=v_modes+1; end if;
  if nullif(btrim(p_reference->>'name'),'') is not null then v_modes:=v_modes+1; end if;
  if v_modes<>1 then
    raise exception 'Place reference must use exactly one identity mode: placeEntityId, identityNamespace+identityKey, or name.' using errcode='22023';
  end if;

  if nullif(btrim(p_reference->>'placeEntityId'),'') is not null then
    begin v_place_id:=(p_reference->>'placeEntityId')::uuid;
    exception when invalid_text_representation then raise exception 'placeEntityId must be UUID.' using errcode='22023'; end;
    select * into v_entity from reality.entities where id=v_place_id and identity_state='canonical' and entity_kind='place';
    select * into v_profile from reality.place_profiles where entity_id=v_place_id and profile_state='active';
    if v_entity.id is null or v_profile.entity_id is null then
      return jsonb_build_object('contractVersion','atlas_place_reference_resolution_v1','state','absent','reference',p_reference,'reason','canonical_place_not_found');
    end if;
    return jsonb_build_object('contractVersion','atlas_place_reference_resolution_v1','state','resolved','reference',p_reference,'entityId',v_entity.id,'displayName',v_entity.display_name,'placeKind',v_profile.place_kind,'countryCode',v_profile.country_code,'resolutionMode','canonical_entity_id');
  end if;

  if nullif(btrim(p_reference->>'identityNamespace'),'') is not null or nullif(btrim(p_reference->>'identityKey'),'') is not null then
    v_identity_namespace:=nullif(btrim(p_reference->>'identityNamespace'),'');
    v_identity_key:=nullif(btrim(p_reference->>'identityKey'),'');
    if v_identity_namespace is null or v_identity_key is null then raise exception 'identityNamespace and identityKey are both required.' using errcode='22023'; end if;
    v_resolution:=reality.resolve_place_identity_service_v1(v_identity_namespace,v_identity_key);
    return jsonb_build_object('contractVersion','atlas_place_reference_resolution_v1','state',v_resolution->>'state','reference',p_reference,'entityId',v_resolution->>'entityId','displayName',v_resolution->>'displayName','placeKind',v_resolution->>'placeKind','countryCode',v_resolution->>'countryCode','resolutionMode','source_identity_key','identityResolution',v_resolution);
  end if;

  v_name:=nullif(btrim(p_reference->>'name'),'');
  v_admin_hint:=nullif(upper(btrim(coalesce(p_reference->>'administrativeHint',''))),'');
  v_country_code:=nullif(upper(btrim(coalesce(p_reference->>'countryCode',''))),'');
  v_place_kind:=coalesce(nullif(lower(btrim(p_reference->>'placeKind')),''),'locality');
  if v_country_code is null then raise exception 'Named Place reference requires countryCode.' using errcode='22023'; end if;
  if v_place_kind='locality' and v_admin_hint is null then raise exception 'Named locality reference requires administrativeHint.' using errcode='22023'; end if;

  v_resolution:=atlas.resolve_or_admit_shared_geographic_area_service_v1(v_name,v_admin_hint,v_country_code,v_place_kind,jsonb_build_object('contractVersion','ATLAS_CONTACT_SET_PAIRED_GEOGRAPHY_V1','reference',p_reference));
  if v_resolution->>'state'='resolved' then
    return jsonb_build_object('contractVersion','atlas_place_reference_resolution_v1','state','resolved','reference',p_reference,'entityId',v_resolution->>'entityId','resolutionMode','shared_geographic_area_exact_match','resolution',v_resolution);
  end if;
  return jsonb_build_object('contractVersion','atlas_place_reference_resolution_v1','state',v_resolution->>'state','reference',p_reference,'resolutionMode','shared_geographic_area_exact_match','resolution',v_resolution);
end
$function$;

revoke all on function atlas.resolve_or_admit_place_reference_service_v1(jsonb) from public,anon,authenticated;
grant execute on function atlas.resolve_or_admit_place_reference_service_v1(jsonb) to service_role;
