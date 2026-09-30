-- ATLAS_REALITY_PLACE_RESOLUTION_V1: resolve Shared Intelligence geography through canonical Place identity

create or replace function atlas.propose_shared_intelligence_entity_geography_to_reality_service(
  p_entity_geographic_area_id uuid,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path to ''
as $function$
declare
  v_link local_intel.entity_geographic_areas%rowtype;
  v_subject reality.entities%rowtype;
  v_place_resolution jsonb;
  v_place_id uuid;
  v_place reality.entities%rowtype;
  v_prop jsonb;
  v_prop_id uuid;
  v_key text;
begin
  if p_entity_geographic_area_id is null then raise exception 'Shared Intelligence entity-geographic-area id is required.' using errcode='22023'; end if;
  select * into v_link from local_intel.entity_geographic_areas where id=p_entity_geographic_area_id;
  if v_link.id is null then raise exception 'Shared Intelligence entity-geographic-area assertion not found.' using errcode='P0002'; end if;
  if v_link.relation_kind<>'located_in' then raise exception 'V1 adapter supports only located_in assertions.' using errcode='23514'; end if;

  select * into v_subject from reality.entities where id=v_link.entity_id and identity_state='canonical';
  if v_subject.id is null then raise exception 'Canonical Reality subject Entity must exist before geography proposition.' using errcode='23514'; end if;

  v_place_resolution:=reality.resolve_place_identity_service_v1('local_intel.geographic_areas.id',v_link.geographic_area_id::text);
  if v_place_resolution->>'state'<>'resolved' then
    raise exception 'Shared Intelligence geographic area must resolve to a canonical Reality Place before geography proposition.' using errcode='23514';
  end if;
  v_place_id:=(v_place_resolution->>'entityId')::uuid;
  select * into v_place from reality.entities where id=v_place_id and identity_state='canonical' and entity_kind='place';
  if v_place.id is null then raise exception 'Canonical Reality Place required before geography proposition.' using errcode='23514'; end if;

  v_key:=coalesce(nullif(btrim(p_idempotency_key),''),'shared_intelligence_entity_geography:'||v_link.id::text);
  v_prop:=reality.record_relationship_proposition_service_v1(
    v_subject.id,'located_in',v_place.id,'observed',null,null,
    jsonb_build_object(
      'adapterContract','ATLAS_REALITY_PLACE_RESOLUTION_V1',
      'sharedIntelligenceEntityGeographicAreaId',v_link.id,
      'sourceGeographicAreaId',v_link.geographic_area_id,
      'evidenceBasis',v_link.evidence_basis,
      'verificationState',v_link.verification_state
    ),
    jsonb_build_object('sourceSystem','shared_intelligence','sourceId',v_link.source_id,'sourceAssertionId',v_link.id),
    v_key
  );
  v_prop_id:=(v_prop->>'propositionId')::uuid;

  if not exists(
    select 1 from reality.relationship_proposition_evidence e
    where e.proposition_id=v_prop_id and e.source_locator->>'sharedIntelligenceEntityGeographicAreaId'=v_link.id::text
  ) then
    perform reality.add_relationship_proposition_evidence_service_v1(
      v_prop_id,'shared_intelligence_geographic_assertion',
      jsonb_strip_nulls(jsonb_build_object(
        'sharedIntelligenceEntityGeographicAreaId',v_link.id,
        'sourceId',v_link.source_id,
        'sourceGeographicAreaId',v_link.geographic_area_id
      )),
      jsonb_build_object(
        'relationKind',v_link.relation_kind,
        'evidenceBasis',v_link.evidence_basis,
        'verificationState',v_link.verification_state,
        'metadata',v_link.metadata
      ),
      'Shared Intelligence geographic assertion proposed for governed Reality adjudication.',
      v_link.updated_at,
      jsonb_build_object('adapterContract','ATLAS_REALITY_PLACE_RESOLUTION_V1')
    );
  end if;

  return jsonb_build_object(
    'contractVersion','shared_intelligence_entity_geography_proposal_v2',
    'sourceAssertionId',v_link.id,
    'sourceGeographicAreaId',v_link.geographic_area_id,
    'canonicalPlaceEntityId',v_place.id,
    'propositionId',v_prop_id,
    'receipt',reality.relationship_proposition_receipt_v1(v_prop_id),
    'autoAdjudicated',false
  );
end
$function$;

revoke all on function atlas.propose_shared_intelligence_entity_geography_to_reality_service(uuid,text) from public,anon,authenticated;
grant execute on function atlas.propose_shared_intelligence_entity_geography_to_reality_service(uuid,text) to service_role;
