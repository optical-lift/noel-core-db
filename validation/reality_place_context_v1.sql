-- Rollback-only acceptance fixture for ATLAS_REALITY_PLACE_CONTEXT_V1.
-- Requires Reality Relationship Substrate v1, Entity Topology v1, and Ledger Target Intelligence v1.

begin;
set local lock_timeout='3s';
set local statement_timeout='30s';

insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata) values
  ('32000000-0000-4000-8000-000000000001','place-v1-root','test_node','Fixture Root','canonical','{}'),
  ('32000000-0000-4000-8000-000000000002','place-v1-site','test_node','Fixture Operating Site','canonical','{}'),
  ('32000000-0000-4000-8000-000000000003','place-v1-city','place','Fixture City','canonical','{}'),
  ('32000000-0000-4000-8000-000000000004','place-v1-state','place','Fixture State','canonical','{}'),
  ('32000000-0000-4000-8000-000000000005','place-v1-other','place','Fixture Other Place','canonical','{}'),
  ('32000000-0000-4000-8000-000000000006','place-v1-not-place','test_node','Fixture Not Place','canonical','{}');

select reality.establish_place_profile_service_v1(
  '32000000-0000-4000-8000-000000000003','locality','US',37.1000,-93.2000,'fixture_centroid','EPSG:4326',
  jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),jsonb_build_object('fixture',true)
);
select reality.establish_place_profile_service_v1(
  '32000000-0000-4000-8000-000000000004','administrative_area','US',38.5000,-92.5000,'fixture_centroid','EPSG:4326',
  jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),jsonb_build_object('fixture',true)
);
select reality.establish_place_profile_service_v1(
  '32000000-0000-4000-8000-000000000005','region','US',39.0000,-91.0000,'fixture_centroid','EPSG:4326',
  jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),jsonb_build_object('fixture',true)
);

-- Exact repeat is idempotent.
select reality.establish_place_profile_service_v1(
  '32000000-0000-4000-8000-000000000003','locality','US',37.1000,-93.2000,'fixture_centroid','EPSG:4326',
  jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),jsonb_build_object('fixture',true)
);

select reality.register_relationship_kind_service_v1(
  'fixture_place_operating_child','Fixture operating child','Synthetic operating topology for Place composition.',null,false,
  array['test_node'],array['test_node'],jsonb_build_object('fixture',true)
);
select reality.register_topology_axis_service_v1(
  'fixture_place_operating_structure','Fixture operating structure','Synthetic operating axis for nested Place target proof.',false,'acyclic',jsonb_build_object('fixture',true)
);
select reality.register_presence_class_service_v1(
  'fixture_place_operating_presence','Fixture operating presence','Synthetic direct operating presence.','direct',jsonb_build_object('fixture',true)
);
select reality.register_relationship_topology_semantics_service_v1(
  'fixture_place_operating_child','fixture_place_operating_structure',true,'subject_to_object',true,true,'fixture_place_operating_presence',jsonb_build_object('fixture',true)
);

do $fixture$
declare
  v_prop jsonb;
  v_prop_id uuid;
  v_failed boolean;
  v_count integer;
  v_eval jsonb;
  v_admit jsonb;
  v_proposal jsonb;
  v_si_place_id uuid:='ae278491-3c5b-4a11-873e-11b74846c06c'; -- existing SI Springfield geographic area
  v_si_assertion_id uuid:='b7d193a1-ecbf-43eb-8fd5-99965fca7343'; -- existing SI entity->Springfield assertion
  v_si_subject_id uuid:='2d12387c-799b-4f8e-af0f-10e47f6d4b39'; -- already-canonical external organization
  v_first_prop_id uuid;
begin
  -- Non-Place entities cannot receive a Place profile.
  v_failed:=false;
  begin
    perform reality.establish_place_profile_service_v1(
      '32000000-0000-4000-8000-000000000006','locality','US',null,null,null,null,'{}','{}','{}'
    );
  exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'Validation failed: non-Place Entity accepted a Place profile.'; end if;

  -- Conflicting Place profile requires explicit future supersession.
  v_failed:=false;
  begin
    perform reality.establish_place_profile_service_v1(
      '32000000-0000-4000-8000-000000000003','locality','US',37.2000,-93.2000,'fixture_centroid','EPSG:4326',
      jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),jsonb_build_object('fixture',true)
    );
  exception when unique_violation then v_failed:=true; when others then v_failed:=true; end;
  if not v_failed then raise exception 'Validation failed: conflicting Place profile did not fail closed.'; end if;

  -- Invalid coordinates fail closed.
  v_failed:=false;
  begin
    perform reality.establish_place_profile_service_v1(
      '32000000-0000-4000-8000-000000000005','region','US',91,-91,'fixture_centroid','EPSG:4326','{}','{}','{}'
    );
  exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'Validation failed: invalid coordinates were accepted.'; end if;

  -- Operating Site -> Root.
  v_prop:=reality.record_relationship_proposition_service_v1(
    '32000000-0000-4000-8000-000000000002','fixture_place_operating_child','32000000-0000-4000-8000-000000000001',
    'established',null,null,jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),'place-v1-site-root'
  );
  v_prop_id:=(v_prop->>'propositionId')::uuid;
  perform reality.add_relationship_proposition_evidence_service_v1(v_prop_id,'fixture_evidence',jsonb_build_object('source','synthetic'),jsonb_build_object('supports',true),'Synthetic.',now(),jsonb_build_object('fixture',true));
  perform reality.adjudicate_relationship_proposition_service_v1(v_prop_id,'accept','Synthetic operating edge.',jsonb_build_object('authority','validation_fixture'),null);

  -- Site -> City spatial membership.
  v_prop:=reality.record_relationship_proposition_service_v1(
    '32000000-0000-4000-8000-000000000002','located_in','32000000-0000-4000-8000-000000000003',
    'established',null,null,jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),'place-v1-site-city'
  );
  v_prop_id:=(v_prop->>'propositionId')::uuid;
  perform reality.add_relationship_proposition_evidence_service_v1(v_prop_id,'fixture_evidence',jsonb_build_object('source','synthetic'),jsonb_build_object('supports',true),'Synthetic.',now(),jsonb_build_object('fixture',true));
  perform reality.adjudicate_relationship_proposition_service_v1(v_prop_id,'accept','Synthetic located_in edge.',jsonb_build_object('authority','validation_fixture'),null);

  -- City -> State spatial containment.
  v_prop:=reality.record_relationship_proposition_service_v1(
    '32000000-0000-4000-8000-000000000003','contained_in','32000000-0000-4000-8000-000000000004',
    'established',null,null,jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),'place-v1-city-state'
  );
  v_prop_id:=(v_prop->>'propositionId')::uuid;
  perform reality.add_relationship_proposition_evidence_service_v1(v_prop_id,'fixture_evidence',jsonb_build_object('source','synthetic'),jsonb_build_object('supports',true),'Synthetic.',now(),jsonb_build_object('fixture',true));
  perform reality.adjudicate_relationship_proposition_service_v1(v_prop_id,'accept','Synthetic contained_in edge.',jsonb_build_object('authority','validation_fixture'),null);

  -- Spatial traversal composes located_in + contained_in transitively.
  select count(*) into v_count
  from reality.entity_topology_paths_service_v1('32000000-0000-4000-8000-000000000002','spatial_containment','ancestors',8,now(),true);
  if v_count<>2 then raise exception 'Validation failed: expected Site -> City -> State spatial path, got % rows.',v_count; end if;
  if not exists(
    select 1 from reality.entity_topology_paths_service_v1('32000000-0000-4000-8000-000000000002','spatial_containment','ancestors',8,now(),true)
    where related_entity_id='32000000-0000-4000-8000-000000000004' and depth=2 and array_length(path_relationship_ids,1)=2
  ) then raise exception 'Validation failed: transitive spatial proof to State missing.'; end if;

  -- Nested target: Root has operating presence whose spatial ancestry reaches State.
  v_eval:=ledger.evaluate_target_predicate_v1(
    '32000000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'op','topology_path_exists','topologyAxis','fixture_place_operating_structure','direction','descendants','maxDepth',8,'presenceOnly',true,
      'endpointPredicate',jsonb_build_object(
        'op','topology_path_exists','topologyAxis','spatial_containment','direction','ancestors','maxDepth',8,'presenceOnly',true,
        'endpointPredicate',jsonb_build_object('op','entity_id_is','entityId','32000000-0000-4000-8000-000000000004')
      )
    ),'$',0
  );
  if v_eval->>'state'<>'true' or jsonb_array_length(v_eval->'obligations')<>0 then
    raise exception 'Validation failed: nested operating->spatial target did not evaluate TRUE.';
  end if;

  -- Missing Other Place is UNKNOWN, not FALSE.
  v_eval:=ledger.evaluate_target_predicate_v1(
    '32000000-0000-4000-8000-000000000002',
    jsonb_build_object(
      'op','topology_path_exists','topologyAxis','spatial_containment','direction','ancestors','maxDepth',8,'presenceOnly',true,
      'endpointPredicate',jsonb_build_object('op','entity_id_is','entityId','32000000-0000-4000-8000-000000000005')
    ),'$',0
  );
  if v_eval->>'state'<>'unknown' then raise exception 'Validation failed: missing spatial membership did not remain UNKNOWN.'; end if;
  if (select count(*) from jsonb_array_elements(v_eval->'obligations') o where o->>'kind'='resolve_topology_path')<>1 then
    raise exception 'Validation failed: missing spatial membership did not emit one topology obligation.';
  end if;

  -- Shared Intelligence geographic-area admission preserves the source UUID and creates only Reality Place identity/profile.
  if exists(select 1 from reality.entities where id=v_si_place_id) then raise exception 'Validation fixture assumes SI Springfield area is not yet admitted to Reality.'; end if;
  v_admit:=atlas.admit_shared_intelligence_geographic_area_to_reality_service_v1(
    v_si_place_id,'locality','US',jsonb_build_object('validationFixture',true,'basisKind','source_identity_admission')
  );
  if (v_admit->>'entityId')::uuid<>v_si_place_id or v_admit->>'placeKind'<>'locality' then raise exception 'Validation failed: SI geographic-area admission did not preserve UUID/profile kind.'; end if;
  if not exists(select 1 from reality.entities where id=v_si_place_id and entity_kind='place' and identity_state='canonical') then raise exception 'Validation failed: admitted geographic area is not canonical Place.'; end if;
  if not exists(select 1 from reality.place_profiles where entity_id=v_si_place_id and place_kind='locality' and profile_state='active') then raise exception 'Validation failed: admitted geographic area lacks active Place profile.'; end if;
  if exists(select 1 from ledger.entity_contexts where entity_id=v_si_place_id) then raise exception 'Validation failed: Place admission created Ledger meaning.'; end if;

  -- Adapter creates an OPEN located_in proposition with evidence, not canonical relationship truth.
  v_proposal:=atlas.propose_shared_intelligence_entity_geography_to_reality_service_v1(v_si_assertion_id,null);
  v_first_prop_id:=(v_proposal->>'propositionId')::uuid;
  if coalesce((v_proposal->>'autoAdjudicated')::boolean,true) then raise exception 'Validation failed: geography adapter auto-adjudicated proposition.'; end if;
  if not exists(select 1 from reality.relationship_propositions where id=v_first_prop_id and proposition_state='open' and relationship_kind='located_in') then raise exception 'Validation failed: geography adapter did not leave proposition open.'; end if;
  if exists(select 1 from reality.entity_relationships where subject_entity_id=v_si_subject_id and object_entity_id=v_si_place_id and relationship_kind='located_in') then raise exception 'Validation failed: geography adapter created canonical relationship without adjudication.'; end if;
  if (select count(*) from reality.relationship_proposition_evidence where proposition_id=v_first_prop_id)<>1 then raise exception 'Validation failed: geography proposition evidence count is not one.'; end if;

  -- Exact adapter retry reuses proposition and does not duplicate evidence.
  v_proposal:=atlas.propose_shared_intelligence_entity_geography_to_reality_service_v1(v_si_assertion_id,null);
  if (v_proposal->>'propositionId')::uuid<>v_first_prop_id then raise exception 'Validation failed: geography adapter retry created duplicate proposition.'; end if;
  if (select count(*) from reality.relationship_proposition_evidence where proposition_id=v_first_prop_id)<>1 then raise exception 'Validation failed: geography adapter retry duplicated evidence.'; end if;

  -- Direct service-role writes remain closed.
  if has_table_privilege('service_role','reality.place_kinds','INSERT') or has_table_privilege('service_role','reality.place_profiles','INSERT') then
    raise exception 'Validation failed: service_role received direct Place-table INSERT authority.';
  end if;
end
$fixture$;

select jsonb_build_object(
  'contractVersion','atlas_reality_place_context_validation_v1',
  'status','passed',
  'syntheticPlaceProfilesInsideTransaction',(select count(*) from reality.place_profiles where entity_id::text like '32000000-%'),
  'syntheticSpatialRelationshipsInsideTransaction',(select count(*) from reality.entity_relationships where (subject_entity_id::text like '32000000-%' or object_entity_id::text like '32000000-%') and relationship_kind in ('located_in','contained_in')),
  'sharedIntelligencePlaceAdmittedInsideTransaction',(select count(*) from reality.entities where id='ae278491-3c5b-4a11-873e-11b74846c06c'),
  'sharedIntelligenceGeographyOpenPropositionsInsideTransaction',(select count(*) from reality.relationship_propositions where idempotency_key='shared_intelligence_entity_geography:b7d193a1-ecbf-43eb-8fd5-99965fca7343')
) as validation_receipt;

rollback;
