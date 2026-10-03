-- ATLAS_REALITY_PLACE_CONTEXT_HARDENING_V1
-- Full FK support index plus registration-function parity with the canonical candidate.

create index if not exists reality_place_profiles_place_kind_fk_idx
  on reality.place_profiles(place_kind);

create or replace function reality.register_place_kind_service_v1(
  p_place_kind text,
  p_display_name text,
  p_description text default '',
  p_is_geographic_area boolean default false,
  p_can_contain_places boolean default false,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path to ''
as $function$
declare
  v_key text:=nullif(btrim(p_place_kind),'');
  v_existing reality.place_kinds%rowtype;
begin
  if v_key is null or nullif(btrim(p_display_name),'') is null then
    raise exception 'Place kind key and display name are required.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Place kind metadata must be a JSON object.' using errcode='22023';
  end if;
  select * into v_existing from reality.place_kinds where place_kind=v_key;
  if v_existing.place_kind is not null then
    if v_existing.kind_state='active'
       and v_existing.display_name=btrim(p_display_name)
       and v_existing.description=coalesce(p_description,'')
       and v_existing.is_geographic_area=p_is_geographic_area
       and v_existing.can_contain_places=p_can_contain_places
       and v_existing.metadata=p_metadata then
      return jsonb_build_object('contractVersion','reality_place_kind_registration_v1','placeKind',v_key,'state','existing');
    end if;
    raise exception 'Place kind % already exists with different semantics or state.',v_key using errcode='23505';
  end if;
  insert into reality.place_kinds(place_kind,display_name,description,is_geographic_area,can_contain_places,metadata)
  values(v_key,btrim(p_display_name),coalesce(p_description,''),p_is_geographic_area,p_can_contain_places,p_metadata);
  return jsonb_build_object('contractVersion','reality_place_kind_registration_v1','placeKind',v_key,'state','registered');
end
$function$;