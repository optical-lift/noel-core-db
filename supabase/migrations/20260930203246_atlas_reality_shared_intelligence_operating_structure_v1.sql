create or replace function atlas.propose_shared_intelligence_operating_structure_to_reality_service_v1(
  p_shared_relationship_id uuid,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path to ''
as $function$
declare
  v_source local_intel.entity_relationships%rowtype;
  v_subject reality.entities%rowtype;
  v_object reality.entities%rowtype;
  v_prop jsonb;
  v_prop_id uuid;
  v_key text;
begin
  if p_shared_relationship_id is null then raise exception 'Shared Intelligence relationship id is required.' using errcode='22023'; end if;
  select * into v_source from local_intel.entity_relationships where id=p_shared_relationship_id;
  if v_source.id is null then raise exception 'Shared Intelligence relationship not found.' using errcode='P0002'; end if;
  if v_source.relationship_kind not in ('location_of','branch_of','department_of','clinic_of','school_of') then
    raise exception 'Relationship kind is not a direct operating-structure kind in v1: %',v_source.relationship_kind using errcode='23514';
  end if;
  if not v_source.is_current or v_source.truth_state<>'accepted_current' or v_source.conflict_state<>'none' then
    raise exception 'Only current, accepted, conflict-free Shared Intelligence operating structure may be proposed.' using errcode='23514';
  end if;

  select * into v_subject from reality.entities where id=v_source.subject_entity_id and identity_state='canonical';
  if v_subject.id is null then raise exception 'Canonical Reality subject Entity required before operating-structure proposition.' using errcode='23514'; end if;
  select * into v_object from reality.entities where id=v_source.object_entity_id and identity_state='canonical';
  if v_object.id is null then raise exception 'Canonical Reality object Entity required before operating-structure proposition.' using errcode='23514'; end if;

  v_key:=coalesce(nullif(btrim(p_idempotency_key),''),'shared_intelligence_operating_structure:'||v_source.id::text);
  v_prop:=reality.record_relationship_proposition_service_v1(
    v_source.subject_entity_id,v_source.relationship_kind,v_source.object_entity_id,'observed',
    case when v_source.valid_from is null then null else v_source.valid_from::timestamptz end,
    case when v_source.valid_to is null then null else (v_source.valid_to+1)::timestamptz end,
    jsonb_build_object('adapterContract','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1','sharedIntelligenceRelationshipId',v_source.id,'truthState',v_source.truth_state,'verificationState',v_source.verification_state,'conflictState',v_source.conflict_state,'currentConfidence',v_source.current_confidence),
    jsonb_build_object('sourceSystem','shared_intelligence','sourceId',v_source.source_id,'sourceRelationshipId',v_source.id),
    v_key
  );
  v_prop_id:=(v_prop->>'propositionId')::uuid;

  if not exists(select 1 from reality.relationship_proposition_evidence e where e.proposition_id=v_prop_id and e.source_locator->>'sharedIntelligenceRelationshipId'=v_source.id::text) then
    perform reality.add_relationship_proposition_evidence_service_v1(
      v_prop_id,'shared_intelligence_relationship_assertion',
      jsonb_strip_nulls(jsonb_build_object('sharedIntelligenceRelationshipId',v_source.id,'sourceId',v_source.source_id)),
      jsonb_strip_nulls(jsonb_build_object('relationshipKind',v_source.relationship_kind,'roleTitle',v_source.role_title,'departmentName',v_source.department_name,'roleFunction',v_source.role_function,'truthState',v_source.truth_state,'verificationState',v_source.verification_state,'currentConfidence',v_source.current_confidence,'conflictState',v_source.conflict_state,'resolutionBasis',v_source.resolution_basis,'metadata',v_source.metadata)),
      'Shared Intelligence operating-structure assertion proposed for governed Reality adjudication.',
      coalesce(v_source.last_verified_at,v_source.updated_at),
      jsonb_build_object('adapterContract','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1')
    );
  end if;

  return jsonb_build_object('contractVersion','shared_intelligence_operating_structure_proposal_v1','sourceRelationshipId',v_source.id,'relationshipKind',v_source.relationship_kind,'propositionId',v_prop_id,'receipt',reality.relationship_proposition_receipt_v1(v_prop_id),'autoAdjudicated',false);
end
$function$;

revoke all on function atlas.propose_shared_intelligence_operating_structure_to_reality_service_v1(uuid,text) from public,anon,authenticated;
grant execute on function atlas.propose_shared_intelligence_operating_structure_to_reality_service_v1(uuid,text) to service_role;