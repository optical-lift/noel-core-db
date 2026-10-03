-- ATLAS_CONTACT_SET_PAIRED_GEOGRAPHY_V1: resolve both sides into canonical Place sets.

create or replace function atlas.resolve_paired_operating_geography_service_v1(
  p_geography jsonb
) returns jsonb
language plpgsql security definer set search_path to ''
as $function$
declare
  v_mode text;
  v_side text;
  v_places jsonb;
  v_reference jsonb;
  v_resolution jsonb;
  v_side_a_ids uuid[]:='{}'::uuid[];
  v_side_b_ids uuid[]:='{}'::uuid[];
  v_side_a_receipts jsonb:='[]'::jsonb;
  v_side_b_receipts jsonb:='[]'::jsonb;
  v_gaps jsonb:='[]'::jsonb;
  v_entity_id uuid;
  v_max_operating_depth integer;
  v_max_spatial_depth integer;
begin
  if p_geography is null or jsonb_typeof(p_geography)<>'object' then raise exception 'Paired geography must be a JSON object.' using errcode='22023'; end if;
  v_mode:=nullif(btrim(p_geography->>'mode'),'');
  if v_mode<>'paired_operating_presence' then raise exception 'Geography mode must be paired_operating_presence.' using errcode='22023'; end if;
  begin
    v_max_operating_depth:=coalesce(nullif(p_geography->>'maxOperatingDepth','')::integer,8);
    v_max_spatial_depth:=coalesce(nullif(p_geography->>'maxSpatialDepth','')::integer,8);
  exception when invalid_text_representation then
    raise exception 'Paired traversal depths must be integers.' using errcode='22023';
  end;
  if v_max_operating_depth not between 1 and 32 or v_max_spatial_depth not between 1 and 32 then raise exception 'Paired traversal depths must be between 1 and 32.' using errcode='22023'; end if;

  foreach v_side in array array['A','B'] loop
    v_places:=case v_side when 'A' then p_geography#>'{sideA,places}' else p_geography#>'{sideB,places}' end;
    if v_places is null or jsonb_typeof(v_places)<>'array' or jsonb_array_length(v_places)=0 or jsonb_array_length(v_places)>100 then raise exception 'Each paired geography side must contain 1 to 100 Place references.' using errcode='22023'; end if;
    for v_reference in select value from jsonb_array_elements(v_places) loop
      v_resolution:=atlas.resolve_or_admit_place_reference_service_v1(v_reference);
      if v_side='A' then v_side_a_receipts:=v_side_a_receipts||jsonb_build_array(v_resolution); else v_side_b_receipts:=v_side_b_receipts||jsonb_build_array(v_resolution); end if;
      if v_resolution->>'state'='resolved' then
        begin v_entity_id:=(v_resolution->>'entityId')::uuid;
        exception when invalid_text_representation then raise exception 'Resolved Place reference returned invalid entityId.' using errcode='23514'; end;
        if v_side='A' then
          if not v_entity_id=any(v_side_a_ids) then v_side_a_ids:=array_append(v_side_a_ids,v_entity_id); end if;
        else
          if not v_entity_id=any(v_side_b_ids) then v_side_b_ids:=array_append(v_side_b_ids,v_entity_id); end if;
        end if;
      else
        v_gaps:=v_gaps||jsonb_build_array(jsonb_build_object('gapKind','geography_resolution_gap','side',v_side,'placeReference',v_reference,'resolutionState',v_resolution->>'state','resolution',v_resolution,'reason','Requested paired Place reference is not uniquely resolved to canonical Reality.'));
      end if;
    end loop;
  end loop;

  if cardinality(v_side_a_ids)>0 and cardinality(v_side_b_ids)>0 and v_side_a_ids && v_side_b_ids then raise exception 'Paired geography sides resolve to overlapping canonical Place identities.' using errcode='23514'; end if;

  return jsonb_build_object(
    'contractVersion','atlas_paired_operating_geography_resolution_v1',
    'state',case when jsonb_array_length(v_gaps)=0 then 'resolved' else 'needs_acquisition' end,
    'mode','paired_operating_presence','maxOperatingDepth',v_max_operating_depth,'maxSpatialDepth',v_max_spatial_depth,
    'sideA',jsonb_build_object('placeEntityIds',to_jsonb(v_side_a_ids),'receipts',v_side_a_receipts),
    'sideB',jsonb_build_object('placeEntityIds',to_jsonb(v_side_b_ids),'receipts',v_side_b_receipts),
    'researchTargets',v_gaps
  );
end
$function$;

revoke all on function atlas.resolve_paired_operating_geography_service_v1(jsonb) from public,anon,authenticated;
grant execute on function atlas.resolve_paired_operating_geography_service_v1(jsonb) to service_role;
