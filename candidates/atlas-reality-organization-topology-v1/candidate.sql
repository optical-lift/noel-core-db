-- ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1
-- Universal direct operating structure and adapters for governed Atlas units / Shared Intelligence hierarchy evidence.

select reality.register_topology_axis_service_v1(
  'operating_structure',
  'Operating structure',
  'Direct operating containment for units, branches, locations, departments, clinics, and schools. Corporate control, franchise, chapter, and brand relationships are intentionally excluded.',
  false,
  'acyclic',
  jsonb_build_object('coreContract','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1')
);

select reality.register_presence_class_service_v1(
  'direct_operating_presence',
  'Direct operating presence',
  'The child is a direct operating component of the parent for topology and presence traversal. This does not assert legal identity equality or communication authority.',
  'direct',
  jsonb_build_object('coreContract','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1')
);

select reality.register_relationship_kind_service_v1(
  'operating_unit_of','Operating unit of','An Organization Unit is a direct operating unit of the canonical parent organization.',null,false,
  array['organization_unit'],array['business','organization','nonprofit'],
  jsonb_build_object('coreContract','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1','sourceClass','canonical_internal_structure')
);
select reality.register_relationship_kind_service_v1(
  'operating_unit_parent','Operating unit parent','A child Organization Unit is directly contained by its parent Organization Unit.',null,false,
  array['organization_unit'],array['organization_unit'],
  jsonb_build_object('coreContract','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1','sourceClass','canonical_internal_structure')
);

select reality.register_relationship_kind_service_v1(
  'location_of','Location of','The subject is a distinct operating location of the parent organization.',null,false,
  array['business','organization','nonprofit','place'],array['business','organization','nonprofit'],
  jsonb_build_object('coreContract','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1','sharedIntelligenceRelationshipKind','location_of')
);
select reality.register_relationship_kind_service_v1(
  'branch_of','Branch of','The subject is a local or operating branch of the parent organization.',null,false,
  array['business','organization','nonprofit'],array['business','organization','nonprofit'],
  jsonb_build_object('coreContract','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1','sharedIntelligenceRelationshipKind','branch_of')
);
select reality.register_relationship_kind_service_v1(
  'department_of','Department of','The subject is an internal department or division of the parent organization.',null,false,
  array['business','organization','nonprofit'],array['business','organization','nonprofit'],
  jsonb_build_object('coreContract','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1','sharedIntelligenceRelationshipKind','department_of')
);
select reality.register_relationship_kind_service_v1(
  'clinic_of','Clinic of','The subject clinic is part of the parent health system or practice group.',null,false,
  array['business','organization','nonprofit'],array['business','organization','nonprofit'],
  jsonb_build_object('coreContract','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1','sharedIntelligenceRelationshipKind','clinic_of')
);
select reality.register_relationship_kind_service_v1(
  'school_of','School of','The subject school is part of the parent district or educational system.',null,false,
  array['organization'],array['organization'],
  jsonb_build_object('coreContract','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1','sharedIntelligenceRelationshipKind','school_of')
);

select reality.register_relationship_topology_semantics_service_v1(
  'operating_unit_of','operating_structure',true,'subject_to_object',true,true,'direct_operating_presence',
  jsonb_build_object('coreContract','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1')
);
select reality.register_relationship_topology_semantics_service_v1(
  'operating_unit_parent','operating_structure',true,'subject_to_object',true,true,'direct_operating_presence',
  jsonb_build_object('coreContract','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1')
);
select reality.register_relationship_topology_semantics_service_v1(
  'location_of','operating_structure',true,'subject_to_object',true,true,'direct_operating_presence',
  jsonb_build_object('coreContract','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1')
);
select reality.register_relationship_topology_semantics_service_v1(
  'branch_of','operating_structure',true,'subject_to_object',true,true,'direct_operating_presence',
  jsonb_build_object('coreContract','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1')
);
select reality.register_relationship_topology_semantics_service_v1(
  'department_of','operating_structure',true,'subject_to_object',true,true,'direct_operating_presence',
  jsonb_build_object('coreContract','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1')
);
select reality.register_relationship_topology_semantics_service_v1(
  'clinic_of','operating_structure',true,'subject_to_object',true,true,'direct_operating_presence',
  jsonb_build_object('coreContract','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1')
);
select reality.register_relationship_topology_semantics_service_v1(
  'school_of','operating_structure',true,'subject_to_object',true,true,'direct_operating_presence',
  jsonb_build_object('coreContract','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1')
);

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
begin
  if p_organization_unit_id is null then raise exception 'Organization Unit id is required.' using errcode='22023'; end if;
  if p_admission_basis is null or jsonb_typeof(p_admission_basis)<>'object' then raise exception 'Admission basis must be a JSON object.' using errcode='22023'; end if;

  select * into v_unit from atlas.organization_units where id=p_organization_unit_id and status='active';
  if v_unit.id is null then raise exception 'Active canonical Atlas Organization Unit required.' using errcode='P0002'; end if;

  v_root_id:=atlas.reality_entity_for_legacy_organization_internal_v1(v_unit.organization_id);
  if v_root_id is null then raise exception 'Legacy Organization has no canonical Reality Entity binding.' using errcode='23514'; end if;
  select * into v_root from reality.entities where id=v_root_id and identity_state='canonical';
  if v_root.id is null or v_root.entity_kind not in ('business','organization','nonprofit') then
    raise exception 'Canonical Reality operating root must be business, organization, or nonprofit.' using errcode='23514';
  end if;

  if v_unit.parent_unit_id is not null then
    select * into v_parent from atlas.organization_units
    where id=v_unit.parent_unit_id and organization_id=v_unit.organization_id and status='active';
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
    values(
      v_unit.id,v_stable_key,'organization_unit',v_unit.name,'canonical',
      jsonb_build_object(
        'admittedFrom','atlas.organization_units',
        'legacyOrganizationUnitId',v_unit.id,
        'legacyOrganizationId',v_unit.organization_id,
        'legacyStableKey',v_unit.stable_key,
        'unitKind',v_unit.unit_kind,
        'admissionBasis',p_admission_basis
      )
    );
    v_inserted:=true;
  else
    if v_existing.identity_state<>'canonical' or v_existing.entity_kind<>'organization_unit' or v_existing.stable_key<>v_stable_key then
      raise exception 'Existing Reality Entity conflicts with canonical Organization Unit identity.' using errcode='23514';
    end if;
  end if;

  select * into v_existing_binding
  from compatibility.legacy_bindings
  where legacy_schema='atlas' and legacy_table='organization_units' and legacy_key=v_unit.id::text
  order by created_at,id limit 1;

  if v_existing_binding.id is null then
    insert into compatibility.legacy_bindings(
      id,legacy_schema,legacy_table,legacy_key,disposition,new_schema,new_table,new_id,basis
    ) values(
      gen_random_uuid(),'atlas','organization_units',v_unit.id::text,'maps_to','reality','entities',v_unit.id,
      jsonb_build_object('contractVersion','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1','admissionBasis',p_admission_basis)
    ) returning id into v_binding_id;
  else
    if v_existing_binding.disposition<>'maps_to' or v_existing_binding.new_schema<>'reality' or v_existing_binding.new_table<>'entities' or v_existing_binding.new_id<>v_unit.id then
      raise exception 'Existing Organization Unit compatibility binding conflicts with Reality admission.' using errcode='23514';
    end if;
    v_binding_id:=v_existing_binding.id;
  end if;

  if v_unit.parent_unit_id is null then
    v_relationship_kind:='operating_unit_of';
    v_relationship_object_id:=v_root.id;
  else
    v_relationship_kind:='operating_unit_parent';
    v_relationship_object_id:=v_parent_entity.id;
  end if;

  v_prop:=reality.record_relationship_proposition_service_v1(
    v_unit.id,v_relationship_kind,v_relationship_object_id,'established',null,null,
    jsonb_build_object(
      'contractVersion','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1',
      'sourceAuthority','canonical_atlas_organization_structure',
      'legacyOrganizationUnitId',v_unit.id,
      'legacyOrganizationId',v_unit.organization_id,
      'unitKind',v_unit.unit_kind
    ),
    jsonb_build_object('sourceSystem','atlas','sourceTable','organization_units','sourceId',v_unit.id),
    'legacy_organization_unit_structure:'||v_unit.id::text
  );
  v_prop_id:=(v_prop->>'propositionId')::uuid;

  if not exists(
    select 1 from reality.relationship_proposition_evidence e
    where e.proposition_id=v_prop_id and e.source_locator->>'legacyOrganizationUnitId'=v_unit.id::text
  ) then
    perform reality.add_relationship_proposition_evidence_service_v1(
      v_prop_id,'canonical_internal_structure',
      jsonb_build_object('legacySchema','atlas','legacyTable','organization_units','legacyOrganizationUnitId',v_unit.id),
      jsonb_build_object(
        'organizationId',v_unit.organization_id,'parentUnitId',v_unit.parent_unit_id,
        'stableKey',v_unit.stable_key,'name',v_unit.name,'unitKind',v_unit.unit_kind,'status',v_unit.status,'metadata',v_unit.metadata
      ),
      'Canonical Atlas Organization Unit admitted through Reality relationship governance.',
      v_unit.updated_at,
      jsonb_build_object('contractVersion','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1')
    );
  end if;

  select proposition_state into v_prop_state from reality.relationship_propositions where id=v_prop_id;
  if v_prop_state='open' then
    perform reality.adjudicate_relationship_proposition_service_v1(
      v_prop_id,'accept','Canonical governed Atlas Organization Unit structure admitted during Reality cutover.',
      jsonb_build_object('authority','canonical_internal_structure','contractVersion','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1'),null
    );
  elsif v_prop_state<>'accepted' then
    raise exception 'Organization Unit structure proposition is not admissible in its current state: %',v_prop_state using errcode='23514';
  end if;

  select r.id into v_relationship_id
  from reality.entity_relationships r
  where r.proposition_id=v_prop_id and r.relationship_state in ('observed','established')
  order by r.created_at,r.id limit 1;

  return jsonb_build_object(
    'contractVersion','atlas_legacy_organization_unit_reality_admission_v1',
    'organizationUnitId',v_unit.id,
    'realityEntityId',v_unit.id,
    'canonicalOperatingRootEntityId',v_root.id,
    'parentOrganizationUnitId',v_unit.parent_unit_id,
    'relationshipKind',v_relationship_kind,
    'relationshipObjectEntityId',v_relationship_object_id,
    'relationshipId',v_relationship_id,
    'compatibilityBindingId',v_binding_id,
    'inserted',v_inserted
  );
end
$function$;

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
    jsonb_build_object(
      'adapterContract','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1',
      'sharedIntelligenceRelationshipId',v_source.id,
      'truthState',v_source.truth_state,
      'verificationState',v_source.verification_state,
      'conflictState',v_source.conflict_state,
      'currentConfidence',v_source.current_confidence
    ),
    jsonb_build_object('sourceSystem','shared_intelligence','sourceId',v_source.source_id,'sourceRelationshipId',v_source.id),
    v_key
  );
  v_prop_id:=(v_prop->>'propositionId')::uuid;

  if not exists(
    select 1 from reality.relationship_proposition_evidence e
    where e.proposition_id=v_prop_id and e.source_locator->>'sharedIntelligenceRelationshipId'=v_source.id::text
  ) then
    perform reality.add_relationship_proposition_evidence_service_v1(
      v_prop_id,'shared_intelligence_relationship_assertion',
      jsonb_strip_nulls(jsonb_build_object('sharedIntelligenceRelationshipId',v_source.id,'sourceId',v_source.source_id)),
      jsonb_strip_nulls(jsonb_build_object(
        'relationshipKind',v_source.relationship_kind,
        'roleTitle',v_source.role_title,
        'departmentName',v_source.department_name,
        'roleFunction',v_source.role_function,
        'truthState',v_source.truth_state,
        'verificationState',v_source.verification_state,
        'currentConfidence',v_source.current_confidence,
        'conflictState',v_source.conflict_state,
        'resolutionBasis',v_source.resolution_basis,
        'metadata',v_source.metadata
      )),
      'Shared Intelligence operating-structure assertion proposed for governed Reality adjudication.',
      coalesce(v_source.last_verified_at,v_source.updated_at),
      jsonb_build_object('adapterContract','ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1')
    );
  end if;

  return jsonb_build_object(
    'contractVersion','shared_intelligence_operating_structure_proposal_v1',
    'sourceRelationshipId',v_source.id,
    'relationshipKind',v_source.relationship_kind,
    'propositionId',v_prop_id,
    'receipt',reality.relationship_proposition_receipt_v1(v_prop_id),
    'autoAdjudicated',false
  );
end
$function$;

create or replace function reality.entity_operating_roots_service_v1(
  p_entity_id uuid,
  p_max_depth integer default 8,
  p_as_of timestamptz default now()
) returns table(
  root_entity_id uuid,
  root_entity_kind text,
  root_display_name text,
  depth integer,
  path_entity_ids uuid[],
  path_relationship_ids uuid[],
  path_relationship_kinds text[]
)
language sql stable security definer set search_path to ''
as $function$
  select r.root_entity_id,e.entity_kind,e.display_name,r.depth,r.path_entity_ids,r.path_relationship_ids,r.path_relationship_kinds
  from reality.entity_topology_roots_service_v1(p_entity_id,'operating_structure',p_max_depth,p_as_of) r
  join reality.entities e on e.id=r.root_entity_id and e.identity_state='canonical'
  order by r.depth desc,r.root_entity_id
$function$;

revoke all on function atlas.admit_legacy_organization_unit_to_reality_service_v1(uuid,jsonb) from public,anon,authenticated;
revoke all on function atlas.propose_shared_intelligence_operating_structure_to_reality_service_v1(uuid,text) from public,anon,authenticated;
revoke all on function reality.entity_operating_roots_service_v1(uuid,integer,timestamptz) from public,anon,authenticated;
grant execute on function atlas.admit_legacy_organization_unit_to_reality_service_v1(uuid,jsonb) to service_role;
grant execute on function atlas.propose_shared_intelligence_operating_structure_to_reality_service_v1(uuid,text) to service_role;
grant execute on function reality.entity_operating_roots_service_v1(uuid,integer,timestamptz) to service_role;