create or replace function atlas.admit_legacy_organization_unit_to_reality_service_v1(
  p_organization_unit_id uuid,
  p_admission_basis jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path to ''
as $function$
declare
  v_unit atlas.organization_units%rowtype;
  v_parent atlas.organization_units%rowtype;
  v_root_id uuid;
  v_root reality.entities%rowtype;
  v_existing reality.entities%rowtype;
  v_parent_entity reality.entities%rowtype;
  v_collision uuid;
  v_stable_key text;
  v_inserted boolean:=false;
  v_binding_id uuid;
  v_existing_binding compatibility.legacy_bindings%rowtype;
  v_relationship_kind text;
  v_relationship_object_id uuid;
  v_prop jsonb;
  v_prop_id uuid;
  v_prop_state text;
  v_relationship_id uuid;
  v_final_receipt jsonb;
begin
  if p_organization_unit_id is null then raise exception 'Organization Unit id is required.' using errcode='22023'; end if;
  if p_admission_basis is null or jsonb_typeof(p_admission_basis)<>'object' then raise exception 'Admission basis must be a JSON object.' using errcode='22023'; end if;
  select * into v_unit from atlas.organization_units where id=p_organization_unit_id and status='active';
  if v_unit.id is null then raise exception 'Active canonical Atlas Organization Unit required.' using errcode='P0002'; end if;
  v_root_id:=atlas.reality_entity_for_legacy_organization_internal_v1(v_unit.organization_id);
  if v_root_id is null then raise exception 'Legacy Organization has no canonical Reality Entity binding.' using errcode='23514'; end if;
  select * into v_root from reality.entities where id=v_root_id and identity_state='canonical';
  if v_root.id is null or v_root.entity_kind not in ('business','organization','nonprofit') then raise exception 'Canonical Reality operating root must be business, organization, or nonprofit.' using errcode='23514'; end if;

  if v_unit.parent_unit_id is not null then
    select * into v_parent from atlas.organization_units where id=v_unit.parent_unit_id and organization_id=v_unit.organization_id and status='active';
    if v_parent.id is null then raise exception 'Active parent Organization Unit in the same Organization required.' using errcode='23514'; end if;
    select * into v_parent_entity from reality.entities where id=v_parent.id and identity_state='canonical' and entity_kind='organization_unit';
    if v_parent_entity.id is null then raise exception 'Parent Organization Unit must be admitted to Reality before its child.' using errcode='23514'; end if;
  end if;

  v_stable_key:='organization-unit:'||replace(v_unit.organization_id::text,'-','')||':'||v_unit.stable_key;
  select * into v_existing from reality.entities where id=v_unit.id;
  if v_existing.id is null then
    select id into v_collision from reality.entities where stable_key=v_stable_key and id<>v_unit.id limit 1;
    if v_collision is not null then raise exception 'Reality Organization Unit stable-key collision requires identity adjudication.' using errcode='23505'; end if;
    insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata)
    values(v_unit.id,v_stable_key,'organization_unit',v_unit.name,'canonical',jsonb_build_object('admittedFrom','atlas.organization_units','legacyOrganizationUnitId',v_unit.id,'legacyOrganizationId',v_unit.organization_id,'legacyStableKey',v_unit.stable_key,'unitKind',v_unit.unit_kind,'admissionBasis',p_admission_basis));
    v_inserted:=true;
  elsif v_existing.identity_state<>'canonical' or v_existing.entity_kind<>'organization_unit' or v_existing.stable_key<>v_stable_key then
    raise exception 'Existing Reality Entity conflicts with canonical Organization Unit identity.' using errcode='23514';
  end if;

  select * into v_existing_binding from compatibility.legacy_bindings where legacy_schema='atlas' and legacy_table='organization_units' and legacy_key=v_unit.id::text order by created_at,id limit 1;
  if v_existing_binding.id is null then
    insert into compatibility.legacy_bindings(id,legacy_schema,legacy_table,legacy_key,disposition,new_schema,new_table,new_id,basis)
    values(gen_random_uuid(),'atlas','organization_units',v_unit.id::text,'maps_to','reality','entities',v_unit.id,jsonb_build_object('contractVersion','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1','admissionBasis',p_admission_basis)) returning id into v_binding_id;
  else
    if v_existing_binding.disposition<>'maps_to' or v_existing_binding.new_schema<>'reality' or v_existing_binding.new_table<>'entities' or v_existing_binding.new_id<>v_unit.id then raise exception 'Existing Organization Unit compatibility binding conflicts with Reality admission.' using errcode='23514'; end if;
    v_binding_id:=v_existing_binding.id;
  end if;

  if v_unit.parent_unit_id is null then v_relationship_kind:='operating_unit_of'; v_relationship_object_id:=v_root.id;
  else v_relationship_kind:='operating_unit_parent'; v_relationship_object_id:=v_parent_entity.id; end if;

  v_prop:=reality.record_relationship_proposition_service_v1(
    v_unit.id,v_relationship_kind,v_relationship_object_id,'established',null,null,
    jsonb_build_object('contractVersion','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1','sourceAuthority','canonical_atlas_organization_structure','legacyOrganizationUnitId',v_unit.id,'legacyOrganizationId',v_unit.organization_id,'unitKind',v_unit.unit_kind),
    jsonb_build_object('sourceSystem','atlas','sourceTable','organization_units','sourceId',v_unit.id),
    'legacy_organization_unit_structure:'||v_unit.id::text);
  v_prop_id:=(v_prop->>'propositionId')::uuid;

  if not exists(select 1 from reality.relationship_proposition_evidence e where e.proposition_id=v_prop_id and e.source_locator->>'legacyOrganizationUnitId'=v_unit.id::text) then
    perform reality.add_relationship_proposition_evidence_service_v1(
      v_prop_id,'canonical_internal_structure',jsonb_build_object('legacySchema','atlas','legacyTable','organization_units','legacyOrganizationUnitId',v_unit.id),
      jsonb_build_object('organizationId',v_unit.organization_id,'parentUnitId',v_unit.parent_unit_id,'stableKey',v_unit.stable_key,'name',v_unit.name,'unitKind',v_unit.unit_kind,'status',v_unit.status,'metadata',v_unit.metadata),
      'Canonical Atlas Organization Unit admitted through Reality relationship governance.',v_unit.updated_at,jsonb_build_object('contractVersion','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1'));
  end if;

  select proposition_state into v_prop_state from reality.relationship_propositions where id=v_prop_id;
  if v_prop_state='open' then
    perform reality.adjudicate_relationship_proposition_service_v1(v_prop_id,'accept','Canonical governed Atlas Organization Unit structure admitted during Reality cutover.',jsonb_build_object('authority','canonical_internal_structure','contractVersion','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1'),null);
  elsif v_prop_state<>'accepted' then
    raise exception 'Organization Unit structure proposition is not admissible in its current state: %',v_prop_state using errcode='23514';
  end if;

  v_final_receipt:=reality.relationship_proposition_receipt_v1(v_prop_id);
  v_relationship_id:=nullif(v_final_receipt->'adjudication'->>'resultingRelationshipId','')::uuid;
  if v_relationship_id is null then raise exception 'Accepted Organization Unit proposition has no resulting canonical relationship.' using errcode='23514'; end if;

  return jsonb_build_object('contractVersion','atlas_legacy_organization_unit_reality_admission_v1','organizationUnitId',v_unit.id,'realityEntityId',v_unit.id,'canonicalOperatingRootEntityId',v_root.id,'parentOrganizationUnitId',v_unit.parent_unit_id,'relationshipKind',v_relationship_kind,'relationshipObjectEntityId',v_relationship_object_id,'relationshipId',v_relationship_id,'compatibilityBindingId',v_binding_id,'inserted',v_inserted);
end
$function$;