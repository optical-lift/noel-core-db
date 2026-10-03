-- Rollback-only acceptance fixture for ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1.
begin;
set local lock_timeout='3s';
set local statement_timeout='30s';

insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata) values
  ('33000000-0000-4000-8000-000000000001','org-topology-v1-root-a','business','Fixture Operating Root A','canonical','{}'),
  ('33000000-0000-4000-8000-000000000002','org-topology-v1-root-b','business','Fixture Operating Root B','canonical','{}'),
  ('33000000-0000-4000-8000-000000000003','org-topology-v1-branch','business','Fixture Branch','canonical','{}');

do $fixture$
declare
  v_prop jsonb; v_prop_id uuid; v_failed boolean; v_count integer; v_root uuid;
  v_receipt jsonb; v_receipt2 jsonb; v_relationship_id uuid; v_internal_prop_id uuid;
  v_adjudication_count_before integer; v_adjudication_count_after integer;
  v_evidence_count_before integer; v_evidence_count_after integer;
  v_si_receipt jsonb; v_si_receipt2 jsonb; v_si_prop_id uuid; v_bad_rel uuid;
begin
  -- Multiple vocabularies to the same actual parent are allowed and normalize to one root.
  v_prop:=reality.record_relationship_proposition_service_v1(
    '33000000-0000-4000-8000-000000000003','branch_of','33000000-0000-4000-8000-000000000001',
    'established',null,null,jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),'org-topology-v1-branch-root-a');
  v_prop_id:=(v_prop->>'propositionId')::uuid;
  perform reality.add_relationship_proposition_evidence_service_v1(v_prop_id,'fixture_evidence',jsonb_build_object('source','synthetic'),jsonb_build_object('supports',true),'Synthetic.',now(),jsonb_build_object('fixture',true));
  perform reality.adjudicate_relationship_proposition_service_v1(v_prop_id,'accept','Synthetic direct operating edge.',jsonb_build_object('authority','validation_fixture'),null);

  v_prop:=reality.record_relationship_proposition_service_v1(
    '33000000-0000-4000-8000-000000000003','location_of','33000000-0000-4000-8000-000000000001',
    'established',null,null,jsonb_build_object('fixture',true,'secondVocabulary',true),jsonb_build_object('fixture',true),'org-topology-v1-location-root-a');
  v_prop_id:=(v_prop->>'propositionId')::uuid;
  perform reality.add_relationship_proposition_evidence_service_v1(v_prop_id,'fixture_evidence',jsonb_build_object('source','synthetic'),jsonb_build_object('supports',true),'Synthetic.',now(),jsonb_build_object('fixture',true));
  perform reality.adjudicate_relationship_proposition_service_v1(v_prop_id,'accept','Synthetic same-parent operating edge.',jsonb_build_object('authority','validation_fixture'),null);

  select count(*) into v_count from reality.entity_operating_roots_service_v1('33000000-0000-4000-8000-000000000003',8,now());
  select root_entity_id into v_root from reality.entity_operating_roots_service_v1('33000000-0000-4000-8000-000000000003',8,now()) limit 1;
  if v_count<>1 or v_root<>'33000000-0000-4000-8000-000000000001' then
    raise exception 'Validation failed: same-parent multi-vocabulary branch did not normalize to one root.';
  end if;

  -- A different simultaneous parent and a cycle both fail closed.
  v_failed:=false;
  begin
    perform reality.record_relationship_proposition_service_v1('33000000-0000-4000-8000-000000000003','department_of','33000000-0000-4000-8000-000000000002','established',null,null,jsonb_build_object('fixture',true),'{}','org-topology-v1-illegal-second-parent');
  exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'Validation failed: distinct second operating parent was allowed.'; end if;

  v_failed:=false;
  begin
    perform reality.record_relationship_proposition_service_v1('33000000-0000-4000-8000-000000000001','branch_of','33000000-0000-4000-8000-000000000003','established',null,null,jsonb_build_object('fixture',true),'{}','org-topology-v1-illegal-cycle');
  exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'Validation failed: operating cycle was allowed.'; end if;

  -- Existing governed Elm Unit resolves through the legacy-organization compatibility binding to canonical Elm Reality.
  v_receipt:=atlas.admit_legacy_organization_unit_to_reality_service_v1('1b65ac99-0f00-4ca2-9488-e8539cae2a1b',jsonb_build_object('validationFixture',true));
  if (v_receipt->>'canonicalOperatingRootEntityId')::uuid<>'de584041-a636-424d-b8f5-2ff90ba3685e' then raise exception 'Validation failed: Elm unit root mismatch.'; end if;
  if (v_receipt->>'realityEntityId')::uuid<>'1b65ac99-0f00-4ca2-9488-e8539cae2a1b' then raise exception 'Validation failed: unit UUID not preserved.'; end if;
  v_relationship_id:=(v_receipt->>'relationshipId')::uuid;
  if not exists(select 1 from reality.entity_relationships where id=v_relationship_id and subject_entity_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b' and object_entity_id='de584041-a636-424d-b8f5-2ff90ba3685e' and relationship_kind='operating_unit_of' and relationship_state='established') then raise exception 'Validation failed: Elm operating_unit_of missing.'; end if;
  if not exists(select 1 from compatibility.legacy_bindings where legacy_schema='atlas' and legacy_table='organization_units' and legacy_key='1b65ac99-0f00-4ca2-9488-e8539cae2a1b' and disposition='maps_to' and new_schema='reality' and new_table='entities' and new_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b') then raise exception 'Validation failed: unit compatibility binding missing.'; end if;

  -- Retry is idempotent across proposition evidence and adjudication.
  select id into v_internal_prop_id from reality.relationship_propositions where idempotency_key='legacy_organization_unit_structure:1b65ac99-0f00-4ca2-9488-e8539cae2a1b';
  select count(*) into v_adjudication_count_before from reality.relationship_proposition_adjudications where proposition_id=v_internal_prop_id;
  select count(*) into v_evidence_count_before from reality.relationship_proposition_evidence where proposition_id=v_internal_prop_id;
  v_receipt2:=atlas.admit_legacy_organization_unit_to_reality_service_v1('1b65ac99-0f00-4ca2-9488-e8539cae2a1b',jsonb_build_object('validationFixture',true));
  select count(*) into v_adjudication_count_after from reality.relationship_proposition_adjudications where proposition_id=v_internal_prop_id;
  select count(*) into v_evidence_count_after from reality.relationship_proposition_evidence where proposition_id=v_internal_prop_id;
  if v_adjudication_count_after<>v_adjudication_count_before or v_evidence_count_after<>v_evidence_count_before or (v_receipt2->>'relationshipId')::uuid<>v_relationship_id then raise exception 'Validation failed: unit retry duplicated truth.'; end if;

  select count(*) into v_count from reality.entity_operating_roots_service_v1('1b65ac99-0f00-4ca2-9488-e8539cae2a1b',8,now());
  select root_entity_id into v_root from reality.entity_operating_roots_service_v1('1b65ac99-0f00-4ca2-9488-e8539cae2a1b',8,now()) limit 1;
  if v_count<>1 or v_root<>'de584041-a636-424d-b8f5-2ff90ba3685e' then raise exception 'Validation failed: Elm unit did not normalize to Elm root.'; end if;

  -- A legacy Organization Unit whose Organization lacks a Reality binding cannot cross the membrane.
  v_failed:=false;
  begin
    perform atlas.admit_legacy_organization_unit_to_reality_service_v1('56d7a7da-b941-4137-8058-0bfc329f7122',jsonb_build_object('validationFixture',true));
  exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'Validation failed: unmapped legacy organization unit was admitted.'; end if;

  -- Real SI branch evidence remains only an open proposition.
  perform atlas.admit_shared_intelligence_entity_to_reality_service_v1('3a1c940e-a680-448d-858c-e5fd5c93b33a',jsonb_build_object('validationFixture',true));
  perform atlas.admit_shared_intelligence_entity_to_reality_service_v1('041b392e-9051-4e98-a38b-d7b6ce744daf',jsonb_build_object('validationFixture',true));
  v_si_receipt:=atlas.propose_shared_intelligence_operating_structure_to_reality_service_v1('9f90499d-c413-4e27-9b8f-935ab954a8b8','org-topology-v1-fixture-si-branch');
  v_si_prop_id:=(v_si_receipt->>'propositionId')::uuid;
  if coalesce((v_si_receipt->>'autoAdjudicated')::boolean,true) then raise exception 'Validation failed: SI hierarchy auto-adjudicated.'; end if;
  if not exists(select 1 from reality.relationship_propositions where id=v_si_prop_id and proposition_state='open' and relationship_kind='branch_of') then raise exception 'Validation failed: SI branch not open.'; end if;
  if exists(select 1 from reality.relationship_proposition_adjudications where proposition_id=v_si_prop_id) then raise exception 'Validation failed: SI branch was adjudicated.'; end if;

  select count(*) into v_evidence_count_before from reality.relationship_proposition_evidence where proposition_id=v_si_prop_id;
  v_si_receipt2:=atlas.propose_shared_intelligence_operating_structure_to_reality_service_v1('9f90499d-c413-4e27-9b8f-935ab954a8b8','org-topology-v1-fixture-si-branch');
  select count(*) into v_evidence_count_after from reality.relationship_proposition_evidence where proposition_id=v_si_prop_id;
  if (v_si_receipt2->>'propositionId')::uuid<>v_si_prop_id or v_evidence_count_after<>v_evidence_count_before then raise exception 'Validation failed: SI retry duplicated proposition/evidence.'; end if;

  -- Franchise/corporate/brand network kinds are not direct operating structure.
  select id into v_bad_rel from local_intel.entity_relationships where relationship_kind='franchise_of' and is_current and truth_state='accepted_current' and conflict_state='none' order by created_at,id limit 1;
  if v_bad_rel is not null then
    v_failed:=false;
    begin perform atlas.propose_shared_intelligence_operating_structure_to_reality_service_v1(v_bad_rel,'org-topology-v1-fixture-franchise-reject'); exception when others then v_failed:=true; end;
    if not v_failed then raise exception 'Validation failed: franchise_of entered direct operating topology.'; end if;
  end if;
  if exists(select 1 from reality.relationship_topology_semantics where relationship_kind in ('franchise_of','chapter_of','subsidiary_of','uses_brand','brand_used_by') and topology_axis='operating_structure' and semantics_state='active') then raise exception 'Validation failed: excluded affiliation/control kind leaked into operating_structure.'; end if;
end
$fixture$;

select jsonb_build_object(
  'contractVersion','atlas_reality_organization_topology_validation_v1','status','passed',
  'syntheticOperatingRelationshipsInsideTransaction',(select count(*) from reality.entity_relationships where subject_entity_id='33000000-0000-4000-8000-000000000003' and object_entity_id='33000000-0000-4000-8000-000000000001' and relationship_kind in ('branch_of','location_of')),
  'elmUnitRealityEntityInsideTransaction',(select count(*) from reality.entities where id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b' and entity_kind='organization_unit'),
  'sharedIntelligenceOpenPropositionInsideTransaction',(select count(*) from reality.relationship_propositions where idempotency_key='org-topology-v1-fixture-si-branch' and proposition_state='open')
) as validation_receipt;

rollback;