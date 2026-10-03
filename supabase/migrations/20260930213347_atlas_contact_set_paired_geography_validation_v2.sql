-- ATLAS_CONTACT_SET_PAIRED_GEOGRAPHY_V1: strict envelope validation layered over contact-set v1.

create or replace function atlas.validate_paired_geography_shape_v1(
  p_geography jsonb
) returns jsonb
language plpgsql immutable set search_path to ''
as $function$
declare
  v_errors jsonb:='[]'::jsonb;
  v_side text;
  v_places jsonb;
  v_ref jsonb;
  v_modes integer;
  v_place_kind text;
  v_depth text;
begin
  if p_geography is null or jsonb_typeof(p_geography)<>'object' then
    return jsonb_build_object('valid',false,'errors',jsonb_build_array('paired_geography_object_required'),'contractVersion','paired_geography_shape_validation_v1');
  end if;
  if p_geography->>'mode'<>'paired_operating_presence' then
    v_errors:=v_errors||jsonb_build_array('paired_geography_mode_invalid');
  end if;
  if p_geography ? 'placeLabels' then
    v_errors:=v_errors||jsonb_build_array('paired_geography_must_not_use_place_labels');
  end if;

  foreach v_side in array array['sideA','sideB'] loop
    v_places:=p_geography#>array[v_side,'places'];
    if v_places is null or jsonb_typeof(v_places)<>'array' or jsonb_array_length(v_places)=0 or jsonb_array_length(v_places)>100 then
      v_errors:=v_errors||jsonb_build_array(v_side||'_places_must_contain_1_to_100_references');
    else
      for v_ref in select value from jsonb_array_elements(v_places) loop
        if jsonb_typeof(v_ref)<>'object' then
          v_errors:=v_errors||jsonb_build_array(v_side||'_place_reference_must_be_object');
        else
          v_modes:=0;
          if nullif(btrim(v_ref->>'placeEntityId'),'') is not null then v_modes:=v_modes+1; end if;
          if nullif(btrim(v_ref->>'identityNamespace'),'') is not null or nullif(btrim(v_ref->>'identityKey'),'') is not null then v_modes:=v_modes+1; end if;
          if nullif(btrim(v_ref->>'name'),'') is not null then v_modes:=v_modes+1; end if;
          if v_modes<>1 then v_errors:=v_errors||jsonb_build_array(v_side||'_place_reference_identity_mode_invalid'); end if;
          if nullif(btrim(v_ref->>'placeEntityId'),'') is not null then
            begin perform (v_ref->>'placeEntityId')::uuid;
            exception when invalid_text_representation then v_errors:=v_errors||jsonb_build_array(v_side||'_place_entity_id_invalid'); end;
          end if;
          if nullif(btrim(v_ref->>'identityNamespace'),'') is not null or nullif(btrim(v_ref->>'identityKey'),'') is not null then
            if nullif(btrim(v_ref->>'identityNamespace'),'') is null or nullif(btrim(v_ref->>'identityKey'),'') is null then v_errors:=v_errors||jsonb_build_array(v_side||'_identity_namespace_and_key_required_together'); end if;
          end if;
          if nullif(btrim(v_ref->>'name'),'') is not null then
            v_place_kind:=coalesce(nullif(lower(btrim(v_ref->>'placeKind')),''),'locality');
            if nullif(btrim(v_ref->>'countryCode'),'') is null then v_errors:=v_errors||jsonb_build_array(v_side||'_named_place_country_code_required'); end if;
            if v_place_kind='locality' and nullif(btrim(v_ref->>'administrativeHint'),'') is null then v_errors:=v_errors||jsonb_build_array(v_side||'_named_locality_administrative_hint_required'); end if;
          end if;
        end if;
      end loop;
    end if;
  end loop;

  foreach v_depth in array array['maxOperatingDepth','maxSpatialDepth'] loop
    if p_geography ? v_depth then
      begin
        if (p_geography->>v_depth)::integer not between 1 and 32 then v_errors:=v_errors||jsonb_build_array(lower(v_depth)||'_out_of_range'); end if;
      exception when invalid_text_representation then v_errors:=v_errors||jsonb_build_array(lower(v_depth)||'_must_be_integer'); end;
    end if;
  end loop;

  return jsonb_build_object('valid',jsonb_array_length(v_errors)=0,'errors',v_errors,'contractVersion','paired_geography_shape_validation_v1');
end
$function$;

create or replace function atlas.validate_contact_set_intent_v2(
  p_literal text,
  p_interpretation jsonb
) returns jsonb
language plpgsql immutable set search_path to ''
as $function$
declare
  v_base jsonb;
  v_geo jsonb;
  v_errors jsonb;
  v_paired jsonb:=null;
  v_valid boolean;
  v_ready boolean;
begin
  v_base:=atlas.validate_contact_set_intent_v1(p_literal,p_interpretation);
  v_errors:=coalesce(v_base->'errors','[]'::jsonb);
  if p_interpretation is not null and jsonb_typeof(p_interpretation)='object'
     and p_interpretation#>>'{geography,mode}'='paired_operating_presence' then
    v_geo:=p_interpretation->'geography';
    v_paired:=atlas.validate_paired_geography_shape_v1(v_geo);
    v_errors:=v_errors||coalesce(v_paired->'errors','[]'::jsonb);
    if jsonb_array_length(coalesce(p_interpretation#>'{target,personFunctions}','[]'::jsonb))>0
       or jsonb_array_length(coalesce(p_interpretation#>'{target,titles}','[]'::jsonb))>0 then
      v_errors:=v_errors||jsonb_build_array('paired_operating_presence_v1_requires_organization_first_target');
    end if;
  end if;
  v_valid:=jsonb_array_length(v_errors)=0;
  v_ready:=v_valid and coalesce((v_base->>'executionReady')::boolean,false);
  return (v_base - 'valid' - 'executionReady' - 'errors' - 'contractVersion') || jsonb_build_object(
    'valid',v_valid,'executionReady',v_ready,'errors',v_errors,
    'pairedGeographyValidation',v_paired,'contractVersion','contact_set_intent_validation_v2'
  );
end
$function$;

create or replace function atlas.interpret_contact_set_intent_service_v1(p_request_id uuid,p_interpretation jsonb,p_interpreter_kind text,p_interpreter_ref text) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','atlas'
as $function$
declare r atlas.contact_set_intent_requests%rowtype; v_validation jsonb; v_plan jsonb; v_state text;
begin
  if p_request_id is null or p_interpretation is null or jsonb_typeof(p_interpretation)<>'object' then raise exception 'request id and interpretation object are required.' using errcode='22023'; end if;
  if p_interpreter_kind not in ('ai','rule','self_authenticated','import') or nullif(btrim(coalesce(p_interpreter_ref,'')),'') is null then raise exception 'trusted interpreter provenance is required.' using errcode='22023'; end if;
  select * into r from atlas.contact_set_intent_requests x where x.id=p_request_id for update;
  if r.id is null then raise exception 'Contact-set intent request not found.' using errcode='P0002'; end if;
  if r.request_state<>'captured' then
    if r.interpretation is distinct from p_interpretation or r.interpreter_kind is distinct from p_interpreter_kind or r.interpreter_ref is distinct from btrim(p_interpreter_ref) then raise exception 'Interpretation retry does not match resolved contact-set intent request.' using errcode='23505'; end if;
    return jsonb_build_object('ok',true,'changed',false,'requestId',r.id,'requestState',r.request_state,'validation',r.validation,'executionPlan',r.execution_plan);
  end if;
  v_validation:=atlas.validate_contact_set_intent_v2(r.literal_request,p_interpretation);
  if not coalesce((v_validation->>'valid')::boolean,false) then raise exception 'Contact-set interpretation failed structural validation: %',v_validation using errcode='22023'; end if;
  if coalesce((v_validation->>'executionReady')::boolean,false) then v_state:='ready'; v_plan:=atlas.plan_contact_set_intent_v1(p_interpretation); else v_state:='needs_clarification'; v_plan:=null; end if;
  update atlas.contact_set_intent_requests set request_state=v_state,interpretation=p_interpretation,validation=v_validation,execution_plan=v_plan,interpreter_kind=p_interpreter_kind,interpreter_ref=btrim(p_interpreter_ref),updated_at=now() where id=r.id returning * into r;
  return jsonb_build_object('ok',true,'changed',true,'contractVersion','contact_set_intent_resolution_v1','requestId',r.id,'requestState',r.request_state,'validation',r.validation,'executionPlan',r.execution_plan,'truthBoundary',jsonb_build_object('interpreterOwnsNoCanonicalTruth',true,'planDoesNotExecuteResearch',true,'planDoesNotCreateLedgerRelationship',true,'planDoesNotAuthorizeCommunication',true));
end
$function$;
