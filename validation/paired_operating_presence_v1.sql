-- Rollback-only acceptance fixture for ATLAS_PAIRED_OPERATING_PRESENCE_V1.
begin;
set local lock_timeout='3s';
set local statement_timeout='30s';

insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata) values
  ('34000000-0000-4000-8000-000000000001','paired-v1-root-good','business','Fixture Spanning Organization','canonical','{}'),
  ('34000000-0000-4000-8000-000000000002','paired-v1-branch-a','business','Fixture Branch A','canonical','{}'),
  ('34000000-0000-4000-8000-000000000003','paired-v1-branch-b','business','Fixture Branch B','canonical','{}'),
  ('34000000-0000-4000-8000-000000000004','paired-v1-root-a-only','business','Fixture A Only Organization','canonical','{}'),
  ('34000000-0000-4000-8000-000000000005','paired-v1-a-only-branch','business','Fixture A Only Branch','canonical','{}'),
  ('34000000-0000-4000-8000-000000000006','paired-v1-root-b-only','business','Fixture B Only Organization','canonical','{}'),
  ('34000000-0000-4000-8000-000000000007','paired-v1-b-only-branch','business','Fixture B Only Branch','canonical','{}'),
  ('34000000-0000-4000-8000-000000000010','paired-v1-city-a','place','Fixture City A','canonical','{}'),
  ('34000000-0000-4000-8000-000000000011','paired-v1-region-a','place','Fixture Region A','canonical','{}'),
  ('34000000-0000-4000-8000-000000000012','paired-v1-city-b','place','Fixture City B','canonical','{}');

select reality.establish_place_profile_service_v1('34000000-0000-4000-8000-000000000010','locality','US',37.1,-94.1,'fixture','EPSG:4326',jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),jsonb_build_object('fixture',true));
select reality.establish_place_profile_service_v1('34000000-0000-4000-8000-000000000011','region','US',37.2,-94.0,'fixture','EPSG:4326',jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),jsonb_build_object('fixture',true));
select reality.establish_place_profile_service_v1('34000000-0000-4000-8000-000000000012','locality','US',37.3,-92.1,'fixture','EPSG:4326',jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),jsonb_build_object('fixture',true));

do $fixture$
declare
  v_prop jsonb; v_prop_id uuid; v_eval jsonb; v_count integer; v_failed boolean;
  v_a_member uuid; v_b_member uuid;
begin
  -- Helper pattern repeated explicitly to preserve proposition/evidence/adjudication proof.
  v_prop:=reality.record_relationship_proposition_service_v1('34000000-0000-4000-8000-000000000002','branch_of','34000000-0000-4000-8000-000000000001','established',null,null,jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),'paired-v1-good-a');
  v_prop_id:=(v_prop->>'propositionId')::uuid; perform reality.add_relationship_proposition_evidence_service_v1(v_prop_id,'fixture_evidence',jsonb_build_object('source','synthetic'),jsonb_build_object('supports',true),'Synthetic.',now(),jsonb_build_object('fixture',true)); perform reality.adjudicate_relationship_proposition_service_v1(v_prop_id,'accept','Synthetic.',jsonb_build_object('authority','validation_fixture'),null);
  v_prop:=reality.record_relationship_proposition_service_v1('34000000-0000-4000-8000-000000000003','branch_of','34000000-0000-4000-8000-000000000001','established',null,null,jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),'paired-v1-good-b');
  v_prop_id:=(v_prop->>'propositionId')::uuid; perform reality.add_relationship_proposition_evidence_service_v1(v_prop_id,'fixture_evidence',jsonb_build_object('source','synthetic'),jsonb_build_object('supports',true),'Synthetic.',now(),jsonb_build_object('fixture',true)); perform reality.adjudicate_relationship_proposition_service_v1(v_prop_id,'accept','Synthetic.',jsonb_build_object('authority','validation_fixture'),null);
  v_prop:=reality.record_relationship_proposition_service_v1('34000000-0000-4000-8000-000000000005','branch_of','34000000-0000-4000-8000-000000000004','established',null,null,jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),'paired-v1-a-only');
  v_prop_id:=(v_prop->>'propositionId')::uuid; perform reality.add_relationship_proposition_evidence_service_v1(v_prop_id,'fixture_evidence',jsonb_build_object('source','synthetic'),jsonb_build_object('supports',true),'Synthetic.',now(),jsonb_build_object('fixture',true)); perform reality.adjudicate_relationship_proposition_service_v1(v_prop_id,'accept','Synthetic.',jsonb_build_object('authority','validation_fixture'),null);
  v_prop:=reality.record_relationship_proposition_service_v1('34000000-0000-4000-8000-000000000007','branch_of','34000000-0000-4000-8000-000000000006','established',null,null,jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),'paired-v1-b-only');
  v_prop_id:=(v_prop->>'propositionId')::uuid; perform reality.add_relationship_proposition_evidence_service_v1(v_prop_id,'fixture_evidence',jsonb_build_object('source','synthetic'),jsonb_build_object('supports',true),'Synthetic.',now(),jsonb_build_object('fixture',true)); perform reality.adjudicate_relationship_proposition_service_v1(v_prop_id,'accept','Synthetic.',jsonb_build_object('authority','validation_fixture'),null);

  -- Spatial facts. Branch A is in City A, and City A is in Region A; Branch B is in City B.
  v_prop:=reality.record_relationship_proposition_service_v1('34000000-0000-4000-8000-000000000002','located_in','34000000-0000-4000-8000-000000000010','established',null,null,jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),'paired-v1-good-a-city');
  v_prop_id:=(v_prop->>'propositionId')::uuid; perform reality.add_relationship_proposition_evidence_service_v1(v_prop_id,'fixture_evidence',jsonb_build_object('source','synthetic'),jsonb_build_object('supports',true),'Synthetic.',now(),jsonb_build_object('fixture',true)); perform reality.adjudicate_relationship_proposition_service_v1(v_prop_id,'accept','Synthetic.',jsonb_build_object('authority','validation_fixture'),null);
  v_prop:=reality.record_relationship_proposition_service_v1('34000000-0000-4000-8000-000000000010','contained_in','34000000-0000-4000-8000-000000000011','established',null,null,jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),'paired-v1-city-a-region-a');
  v_prop_id:=(v_prop->>'propositionId')::uuid; perform reality.add_relationship_proposition_evidence_service_v1(v_prop_id,'fixture_evidence',jsonb_build_object('source','synthetic'),jsonb_build_object('supports',true),'Synthetic.',now(),jsonb_build_object('fixture',true)); perform reality.adjudicate_relationship_proposition_service_v1(v_prop_id,'accept','Synthetic.',jsonb_build_object('authority','validation_fixture'),null);
  v_prop:=reality.record_relationship_proposition_service_v1('34000000-0000-4000-8000-000000000003','located_in','34000000-0000-4000-8000-000000000012','established',null,null,jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),'paired-v1-good-b-city');
  v_prop_id:=(v_prop->>'propositionId')::uuid; perform reality.add_relationship_proposition_evidence_service_v1(v_prop_id,'fixture_evidence',jsonb_build_object('source','synthetic'),jsonb_build_object('supports',true),'Synthetic.',now(),jsonb_build_object('fixture',true)); perform reality.adjudicate_relationship_proposition_service_v1(v_prop_id,'accept','Synthetic.',jsonb_build_object('authority','validation_fixture'),null);
  v_prop:=reality.record_relationship_proposition_service_v1('34000000-0000-4000-8000-000000000005','located_in','34000000-0000-4000-8000-000000000010','established',null,null,jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),'paired-v1-a-only-city');
  v_prop_id:=(v_prop->>'propositionId')::uuid; perform reality.add_relationship_proposition_evidence_service_v1(v_prop_id,'fixture_evidence',jsonb_build_object('source','synthetic'),jsonb_build_object('supports',true),'Synthetic.',now(),jsonb_build_object('fixture',true)); perform reality.adjudicate_relationship_proposition_service_v1(v_prop_id,'accept','Synthetic.',jsonb_build_object('authority','validation_fixture'),null);
  v_prop:=reality.record_relationship_proposition_service_v1('34000000-0000-4000-8000-000000000007','located_in','34000000-0000-4000-8000-000000000012','established',null,null,jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),'paired-v1-b-only-city');
  v_prop_id:=(v_prop->>'propositionId')::uuid; perform reality.add_relationship_proposition_evidence_service_v1(v_prop_id,'fixture_evidence',jsonb_build_object('source','synthetic'),jsonb_build_object('supports',true),'Synthetic.',now(),jsonb_build_object('fixture',true)); perform reality.adjudicate_relationship_proposition_service_v1(v_prop_id,'accept','Synthetic.',jsonb_build_object('authority','validation_fixture'),null);

  -- Evaluate from a branch: it must normalize to the shared root and prove both sides.
  v_eval:=reality.evaluate_operating_place_pair_service_v1(
    '34000000-0000-4000-8000-000000000002',
    array['34000000-0000-4000-8000-000000000011'::uuid],
    array['34000000-0000-4000-8000-000000000012'::uuid],8,8,now());
  if v_eval->>'state'<>'true' or (v_eval->>'canonicalOperatingRootEntityId')::uuid<>'34000000-0000-4000-8000-000000000001' then raise exception 'Validation failed: spanning organization did not evaluate TRUE under one normalized root.'; end if;
  if jsonb_array_length(v_eval->'sideA'->'proofs')=0 or jsonb_array_length(v_eval->'sideB'->'proofs')=0 or jsonb_array_length(v_eval->'obligations')<>0 then raise exception 'Validation failed: paired TRUE did not return both proof packets cleanly.'; end if;
  v_a_member:=(v_eval->'sideA'->'proofs'->0->>'operatingMemberEntityId')::uuid;
  v_b_member:=(v_eval->'sideB'->'proofs'->0->>'operatingMemberEntityId')::uuid;
  if v_a_member<>'34000000-0000-4000-8000-000000000002' or v_b_member<>'34000000-0000-4000-8000-000000000003' then raise exception 'Validation failed: paired proof did not preserve distinct operating members.'; end if;
  if (v_eval->'sideA'->'proofs'->0->>'spatialDepth')::integer<>2 then raise exception 'Validation failed: transitive City A -> Region A spatial proof depth was not preserved.'; end if;

  -- One-sided roots stay UNKNOWN with one precise obligation; they are never combined with each other.
  v_eval:=reality.evaluate_operating_place_pair_service_v1('34000000-0000-4000-8000-000000000004',array['34000000-0000-4000-8000-000000000011'::uuid],array['34000000-0000-4000-8000-000000000012'::uuid],8,8,now());
  if v_eval->>'state'<>'unknown' or jsonb_array_length(v_eval->'obligations')<>1 or v_eval->'obligations'->0->>'side'<>'B' then raise exception 'Validation failed: A-only organization did not remain UNKNOWN for side B.'; end if;
  v_eval:=reality.evaluate_operating_place_pair_service_v1('34000000-0000-4000-8000-000000000006',array['34000000-0000-4000-8000-000000000011'::uuid],array['34000000-0000-4000-8000-000000000012'::uuid],8,8,now());
  if v_eval->>'state'<>'unknown' or jsonb_array_length(v_eval->'obligations')<>1 or v_eval->'obligations'->0->>'side'<>'A' then raise exception 'Validation failed: B-only organization did not remain UNKNOWN for side A.'; end if;

  select count(*) into v_count
  from reality.operating_roots_spanning_place_sets_service_v1(array['34000000-0000-4000-8000-000000000011'::uuid],array['34000000-0000-4000-8000-000000000012'::uuid],8,8,now(),100)
  where root_entity_id::text like '34000000-%';
  if v_count<>1 then raise exception 'Validation failed: set search combined unrelated one-sided organizations or missed the true spanning root.'; end if;

  -- Explicitly overlapping side sets are invalid.
  v_failed:=false;
  begin
    perform reality.evaluate_operating_place_pair_service_v1('34000000-0000-4000-8000-000000000001',array['34000000-0000-4000-8000-000000000011'::uuid],array['34000000-0000-4000-8000-000000000011'::uuid],8,8,now());
  exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'Validation failed: overlapping side Place ids were accepted.'; end if;
end
$fixture$;

select jsonb_build_object(
  'contractVersion','atlas_paired_operating_presence_validation_v1','status','passed',
  'spanningRootsInsideTransaction',(select count(*) from reality.operating_roots_spanning_place_sets_service_v1(array['34000000-0000-4000-8000-000000000011'::uuid],array['34000000-0000-4000-8000-000000000012'::uuid],8,8,now(),100) where root_entity_id::text like '34000000-%')
) as validation_receipt;
rollback;