-- Rollback-only acceptance fixture for ATLAS_REALITY_ENTITY_TOPOLOGY_V1.
-- Requires Reality Relationship Substrate v1 and Ledger Target Intelligence v1.
-- Synthetic universal entities only. Leaves no fixture data behind.

begin;
set local lock_timeout='3s';
set local statement_timeout='30s';

insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata) values
  ('31000000-0000-4000-8000-000000000001','topology-v1-root-a','test_node','Topology Root A','canonical','{}'),
  ('31000000-0000-4000-8000-000000000002','topology-v1-child-b','test_node','Topology Child B','canonical','{}'),
  ('31000000-0000-4000-8000-000000000003','topology-v1-child-c','test_node','Topology Child C','canonical','{}'),
  ('31000000-0000-4000-8000-000000000004','topology-v1-root-d','test_node','Topology Root D','canonical','{}'),
  ('31000000-0000-4000-8000-000000000005','topology-v1-brand-e','test_node','Topology Brand E','canonical','{}');

select reality.register_relationship_kind_service_v1(
  'fixture_operating_parent','Fixture operating parent','Synthetic structural operating relationship.',null,false,
  array['test_node'],array['test_node'],jsonb_build_object('fixture',true)
);
select reality.register_relationship_kind_service_v1(
  'fixture_brand_parent','Fixture brand parent','Synthetic brand relationship.',null,false,
  array['test_node'],array['test_node'],jsonb_build_object('fixture',true)
);

select reality.register_topology_axis_service_v1(
  'fixture_operating_structure','Fixture operating structure','Synthetic single-parent acyclic axis.',false,'acyclic',jsonb_build_object('fixture',true)
);
select reality.register_topology_axis_service_v1(
  'fixture_brand_structure','Fixture brand structure','Synthetic multi-parent acyclic axis.',true,'acyclic',jsonb_build_object('fixture',true)
);

select reality.register_presence_class_service_v1(
  'fixture_direct_operational','Fixture direct operational','Synthetic direct operational presence.','direct',jsonb_build_object('fixture',true)
);
select reality.register_presence_class_service_v1(
  'fixture_contextual_brand','Fixture contextual brand','Synthetic contextual brand presence.','contextual',jsonb_build_object('fixture',true)
);

select reality.register_relationship_topology_semantics_service_v1(
  'fixture_operating_parent','fixture_operating_structure',true,'subject_to_object',true,true,'fixture_direct_operational',jsonb_build_object('fixture',true)
);
select reality.register_relationship_topology_semantics_service_v1(
  'fixture_brand_parent','fixture_brand_structure',true,'subject_to_object',true,true,'fixture_contextual_brand',jsonb_build_object('fixture',true)
);

-- Exact repeat registration is idempotent.
select reality.register_relationship_topology_semantics_service_v1(
  'fixture_operating_parent','fixture_operating_structure',true,'subject_to_object',true,true,'fixture_direct_operational',jsonb_build_object('fixture',true)
);

do $fixture$
declare
  v_prop jsonb;
  v_prop_id uuid;
  v_count integer;
  v_failed boolean;
  v_eval jsonb;
  v_rel_bc uuid;
  v_rel_ba uuid;
  v_path_count integer;
  v_root uuid;
begin
  -- Helper pattern: B -> A operating.
  v_prop:=reality.record_relationship_proposition_service_v1(
    '31000000-0000-4000-8000-000000000002','fixture_operating_parent','31000000-0000-4000-8000-000000000001',
    'established',null,null,jsonb_build_object('fixtureCase','b_to_a'),jsonb_build_object('fixture',true),'topology-v1-b-a'
  );
  v_prop_id:=(v_prop->>'propositionId')::uuid;
  perform reality.add_relationship_proposition_evidence_service_v1(v_prop_id,'fixture_evidence',jsonb_build_object('source','synthetic'),jsonb_build_object('supports',true),'Synthetic.',now(),jsonb_build_object('fixture',true));
  perform reality.adjudicate_relationship_proposition_service_v1(v_prop_id,'accept','Synthetic topology edge.',jsonb_build_object('authority','validation_fixture'),null);

  -- C -> B operating.
  v_prop:=reality.record_relationship_proposition_service_v1(
    '31000000-0000-4000-8000-000000000003','fixture_operating_parent','31000000-0000-4000-8000-000000000002',
    'established',null,null,jsonb_build_object('fixtureCase','c_to_b'),jsonb_build_object('fixture',true),'topology-v1-c-b'
  );
  v_prop_id:=(v_prop->>'propositionId')::uuid;
  perform reality.add_relationship_proposition_evidence_service_v1(v_prop_id,'fixture_evidence',jsonb_build_object('source','synthetic'),jsonb_build_object('supports',true),'Synthetic.',now(),jsonb_build_object('fixture',true));
  perform reality.adjudicate_relationship_proposition_service_v1(v_prop_id,'accept','Synthetic topology edge.',jsonb_build_object('authority','validation_fixture'),null);

  -- C -> E and C -> D on a multi-parent brand axis are both legal.
  v_prop:=reality.record_relationship_proposition_service_v1(
    '31000000-0000-4000-8000-000000000003','fixture_brand_parent','31000000-0000-4000-8000-000000000005',
    'established',null,null,jsonb_build_object('fixtureCase','c_to_e_brand'),jsonb_build_object('fixture',true),'topology-v1-c-e-brand'
  );
  v_prop_id:=(v_prop->>'propositionId')::uuid;
  perform reality.add_relationship_proposition_evidence_service_v1(v_prop_id,'fixture_evidence',jsonb_build_object('source','synthetic'),jsonb_build_object('supports',true),'Synthetic.',now(),jsonb_build_object('fixture',true));
  perform reality.adjudicate_relationship_proposition_service_v1(v_prop_id,'accept','Synthetic brand edge.',jsonb_build_object('authority','validation_fixture'),null);

  v_prop:=reality.record_relationship_proposition_service_v1(
    '31000000-0000-4000-8000-000000000003','fixture_brand_parent','31000000-0000-4000-8000-000000000004',
    'established',null,null,jsonb_build_object('fixtureCase','c_to_d_brand'),jsonb_build_object('fixture',true),'topology-v1-c-d-brand'
  );
  v_prop_id:=(v_prop->>'propositionId')::uuid;
  perform reality.add_relationship_proposition_evidence_service_v1(v_prop_id,'fixture_evidence',jsonb_build_object('source','synthetic'),jsonb_build_object('supports',true),'Synthetic.',now(),jsonb_build_object('fixture',true));
  perform reality.adjudicate_relationship_proposition_service_v1(v_prop_id,'accept','Synthetic brand edge.',jsonb_build_object('authority','validation_fixture'),null);

  -- Operating ancestor path C -> B -> A exists with proof depth 2.
  select count(*) into v_count
  from reality.entity_topology_paths_service_v1('31000000-0000-4000-8000-000000000003','fixture_operating_structure','ancestors',8,now(),false);
  if v_count<>2 then raise exception 'Validation failed: expected two operating ancestor paths, got %.',v_count; end if;

  select path_relationship_ids[1],path_relationship_ids[2]
  into v_rel_bc,v_rel_ba
  from reality.entity_topology_paths_service_v1('31000000-0000-4000-8000-000000000003','fixture_operating_structure','ancestors',8,now(),false)
  where related_entity_id='31000000-0000-4000-8000-000000000001' and depth=2;
  if v_rel_bc is null or v_rel_ba is null then raise exception 'Validation failed: two-hop proof path did not preserve relationship IDs.'; end if;

  -- Descendant traversal from A reaches B and C.
  select count(*) into v_count
  from reality.entity_topology_paths_service_v1('31000000-0000-4000-8000-000000000001','fixture_operating_structure','descendants',8,now(),false);
  if v_count<>2 then raise exception 'Validation failed: descendant traversal did not return B and C.'; end if;

  -- Root resolver returns A for C on operating axis.
  select root_entity_id into v_root
  from reality.entity_topology_roots_service_v1('31000000-0000-4000-8000-000000000003','fixture_operating_structure',8,now())
  limit 1;
  if v_root<>'31000000-0000-4000-8000-000000000001' then raise exception 'Validation failed: root resolver did not return A.'; end if;

  -- Presence projection traverses opted-in operating edges.
  select count(*) into v_count
  from reality.entity_presence_paths_service_v1('31000000-0000-4000-8000-000000000001','fixture_operating_structure',8,now());
  if v_count<>2 then raise exception 'Validation failed: operating presence projection expected two descendants.'; end if;

  if exists(
    select 1 from reality.entity_presence_paths_service_v1('31000000-0000-4000-8000-000000000001','fixture_operating_structure',8,now())
    where effective_presence_effect<>'direct'
  ) then raise exception 'Validation failed: direct operating presence effect degraded unexpectedly.'; end if;

  -- Single-parent axis rejects a second simultaneous operating parent for B.
  v_failed:=false;
  begin
    perform reality.record_relationship_proposition_service_v1(
      '31000000-0000-4000-8000-000000000002','fixture_operating_parent','31000000-0000-4000-8000-000000000004',
      'established',null,null,'{}',jsonb_build_object('fixture',true),'topology-v1-b-d-illegal'
    );
  exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'Validation failed: single-parent axis allowed second simultaneous parent.'; end if;

  -- Indirect cycle A -> C is rejected because C -> B -> A already exists.
  v_failed:=false;
  begin
    perform reality.record_relationship_proposition_service_v1(
      '31000000-0000-4000-8000-000000000001','fixture_operating_parent','31000000-0000-4000-8000-000000000003',
      'established',null,null,'{}',jsonb_build_object('fixture',true),'topology-v1-cycle'
    );
  exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'Validation failed: indirect topology cycle was not rejected.'; end if;

  -- Target topology existential TRUE for known descendant C.
  v_eval:=ledger.evaluate_target_predicate_v1(
    '31000000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'op','topology_path_exists','topologyAxis','fixture_operating_structure','direction','descendants','maxDepth',8,'presenceOnly',true,
      'endpointPredicate',jsonb_build_object('op','entity_id_is','entityId','31000000-0000-4000-8000-000000000003')
    ),'$',0
  );
  if v_eval->>'state'<>'true' or jsonb_array_length(v_eval->'obligations')<>0 then
    raise exception 'Validation failed: known topology path did not evaluate TRUE without obligations.';
  end if;

  -- Missing matching topology remains UNKNOWN with one precise topology obligation.
  v_eval:=ledger.evaluate_target_predicate_v1(
    '31000000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'op','topology_path_exists','topologyAxis','fixture_operating_structure','direction','descendants','maxDepth',8,'presenceOnly',true,
      'endpointPredicate',jsonb_build_object('op','entity_id_is','entityId','31000000-0000-4000-8000-000000000004')
    ),'$',0
  );
  if v_eval->>'state'<>'unknown' then raise exception 'Validation failed: missing topology path did not remain UNKNOWN.'; end if;
  if (select count(*) from jsonb_array_elements(v_eval->'obligations') o where o->>'kind'='resolve_topology_path')<>1 then
    raise exception 'Validation failed: missing topology path did not emit exactly one topology obligation.';
  end if;

  -- AT_LEAST_N becomes TRUE and prunes an irrelevant unknown branch.
  v_eval:=ledger.evaluate_target_predicate_v1(
    '31000000-0000-4000-8000-000000000001',
    jsonb_build_object('op','at_least_n','minimum',2,'predicates',jsonb_build_array(
      jsonb_build_object('op','entity_kind_is','entityKind','test_node'),
      jsonb_build_object('op','topology_path_exists','topologyAxis','fixture_operating_structure','direction','descendants','maxDepth',8,'presenceOnly',true,'endpointPredicate',jsonb_build_object('op','entity_id_is','entityId','31000000-0000-4000-8000-000000000003')),
      jsonb_build_object('op','topology_path_exists','topologyAxis','fixture_operating_structure','direction','descendants','maxDepth',8,'presenceOnly',true,'endpointPredicate',jsonb_build_object('op','entity_id_is','entityId','31000000-0000-4000-8000-000000000004'))
    )),'$',0
  );
  if v_eval->>'state'<>'true' or jsonb_array_length(v_eval->'obligations')<>0 then
    raise exception 'Validation failed: AT_LEAST_N did not prune irrelevant unknown obligation when already true.';
  end if;

  -- AT_LEAST_N becomes FALSE and prunes unknowns when threshold is impossible.
  v_eval:=ledger.evaluate_target_predicate_v1(
    '31000000-0000-4000-8000-000000000001',
    jsonb_build_object('op','at_least_n','minimum',3,'predicates',jsonb_build_array(
      jsonb_build_object('op','entity_kind_is','entityKind','wrong_kind'),
      jsonb_build_object('op','entity_id_is','entityId','31000000-0000-4000-8000-000000000002'),
      jsonb_build_object('op','topology_path_exists','topologyAxis','fixture_operating_structure','direction','descendants','maxDepth',8,'presenceOnly',true,'endpointPredicate',jsonb_build_object('op','entity_id_is','entityId','31000000-0000-4000-8000-000000000004'))
    )),'$',0
  );
  if v_eval->>'state'<>'false' or jsonb_array_length(v_eval->'obligations')<>0 then
    raise exception 'Validation failed: AT_LEAST_N did not prune obligations when threshold was impossible.';
  end if;

  -- Canonical topology tables are not directly writable by service_role.
  if has_table_privilege('service_role','reality.topology_axes','INSERT')
     or has_table_privilege('service_role','reality.presence_classes','INSERT')
     or has_table_privilege('service_role','reality.relationship_topology_semantics','INSERT') then
    raise exception 'Validation failed: service_role received direct topology-table INSERT authority.';
  end if;
end
$fixture$;

select jsonb_build_object(
  'contractVersion','atlas_reality_entity_topology_validation_v1',
  'status','passed',
  'canonicalFixtureRelationshipsInsideTransaction',(select count(*) from reality.entity_relationships where metadata->>'admissionContract'='ATLAS_REALITY_RELATIONSHIP_SUBSTRATE_V1' and (subject_entity_id::text like '31000000-%' or object_entity_id::text like '31000000-%')),
  'topologyAxesInsideTransaction',(select count(*) from reality.topology_axes where metadata->>'fixture'='true'),
  'topologySemanticsInsideTransaction',(select count(*) from reality.relationship_topology_semantics where metadata->>'fixture'='true')
) as validation_receipt;

rollback;
