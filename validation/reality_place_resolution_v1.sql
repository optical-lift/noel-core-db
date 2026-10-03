-- Rollback-only acceptance fixture for ATLAS_REALITY_PLACE_RESOLUTION_V1.

begin;
set local lock_timeout='3s';
set local statement_timeout='30s';

do $fixture$
declare
  v_springfield uuid:='ae278491-3c5b-4a11-873e-11b74846c06c';
  v_lebanon uuid:='68aaf043-4d0a-4330-9018-ca726b7b5ff1';
  v_springfield_assertion uuid:='372a6b10-9a5b-4469-887d-ad7b5b6d69a4';
  v_springfield_business uuid:='b425db2d-90da-4519-b03f-34bf4a3c5e95';
  v_converged_place uuid:='45000000-0000-4000-8000-000000000001';
  v_conflict_place uuid:='45000000-0000-4000-8000-000000000002';
  v_match jsonb;
  v_resolution jsonb;
  v_admission jsonb;
  v_second jsonb;
  v_prop jsonb;
  v_prop_id uuid;
  v_count integer;
  v_failed boolean;
begin
  -- Exact source lookup must resolve Springfield only with an administrative hint.
  v_match:=atlas.match_shared_geographic_area_reference_service_v1('Springfield','MO','locality');
  if v_match->>'state'<>'matched_source' or (v_match->>'sourceGeographicAreaId')::uuid<>v_springfield then
    raise exception 'Springfield source reference did not resolve deterministically.';
  end if;

  v_failed:=false;
  begin
    perform atlas.match_shared_geographic_area_reference_service_v1('Springfield',null,'locality');
  exception when sqlstate '22023' then
    v_failed:=true;
  end;
  if not v_failed then raise exception 'Name-only locality lookup must fail closed.'; end if;

  -- Fresh source-verified locality admission.
  v_admission:=atlas.resolve_or_admit_shared_geographic_area_service_v1(
    'Springfield','MO','US','locality',jsonb_build_object('fixture','reality_place_resolution_v1')
  );
  if v_admission->>'state'<>'resolved' or (v_admission->>'entityId')::uuid<>v_springfield then
    raise exception 'Fresh Springfield admission did not preserve source UUID as canonical Place identity.';
  end if;
  if not exists(select 1 from reality.place_profiles where entity_id=v_springfield and profile_state='active' and place_kind='locality' and country_code='US') then
    raise exception 'Springfield active locality profile missing.';
  end if;
  select count(*)::integer into v_count from reality.place_identity_keys where entity_id=v_springfield and identity_state='active';
  if v_count<>2 then raise exception 'Springfield should have exactly two source identity keys in fixture, got %.',v_count; end if;

  -- Idempotent reuse.
  v_second:=atlas.resolve_or_admit_shared_geographic_area_service_v1(
    'Springfield','MO','US','locality',jsonb_build_object('fixture','reality_place_resolution_v1')
  );
  if (v_second->>'entityId')::uuid<>v_springfield or coalesce((v_second->'admission'->>'inserted')::boolean,true) then
    raise exception 'Repeated Springfield resolution must reuse canonical Place without reinsertion.';
  end if;
  v_resolution:=reality.resolve_place_identity_service_v1('local_intel.geographic_areas.stable_key','mo-springfield');
  if v_resolution->>'state'<>'resolved' or (v_resolution->>'entityId')::uuid<>v_springfield then
    raise exception 'Stable-key identity resolution failed.';
  end if;

  -- Multi-source convergence: an already-canonical Place can claim the SI stable-key identity
  -- even when its canonical centroid evidence differs from the SI source.
  insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata)
  values(v_converged_place,'fixture:place:lebanon-converged','place','Lebanon canonical fixture','canonical','{}');
  perform reality.establish_place_profile_service_v1(
    v_converged_place,'locality','US',37.7010,-92.6420,'fixture_centroid','EPSG:4326',
    jsonb_build_object('fixture','alternate_source'),jsonb_build_object('fixture','alternate_source'),'{}'::jsonb
  );
  perform reality.register_place_identity_key_service_v1(
    v_converged_place,'local_intel.geographic_areas.stable_key','mo-lebanon',
    jsonb_build_object('fixture','pre_adjudicated_match'),jsonb_build_object('fixture','identity_convergence'),'{}'::jsonb
  );
  v_admission:=atlas.admit_shared_geographic_area_to_reality_service_v1(v_lebanon,'US',jsonb_build_object('fixture','identity_convergence'));
  if (v_admission->>'entityId')::uuid<>v_converged_place or coalesce((v_admission->>'inserted')::boolean,true) then
    raise exception 'Lebanon source identity did not converge onto existing canonical Place.';
  end if;
  if exists(select 1 from reality.entities where id=v_lebanon) then
    raise exception 'Converged source geography must not create a duplicate Place Entity.';
  end if;
  v_resolution:=reality.resolve_place_identity_service_v1('local_intel.geographic_areas.id',v_lebanon::text);
  if v_resolution->>'state'<>'resolved' or (v_resolution->>'entityId')::uuid<>v_converged_place then
    raise exception 'Source-id identity key did not bind to converged Place.';
  end if;

  -- One active source identity key cannot be rebound to a different Place.
  insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata)
  values(v_conflict_place,'fixture:place:identity-conflict','place','Identity conflict fixture','canonical','{}');
  perform reality.establish_place_profile_service_v1(
    v_conflict_place,'locality','US',null,null,null,null,
    jsonb_build_object('fixture','conflict'),jsonb_build_object('fixture','conflict'),'{}'::jsonb
  );
  v_failed:=false;
  begin
    perform reality.register_place_identity_key_service_v1(
      v_conflict_place,'local_intel.geographic_areas.id',v_springfield::text,
      jsonb_build_object('fixture','conflict'),jsonb_build_object('fixture','conflict'),'{}'::jsonb
    );
  exception when sqlstate '23505' then
    v_failed:=true;
  end;
  if not v_failed then raise exception 'Conflicting Place identity-key rebinding must fail closed.'; end if;

  -- Real SI entity geography uses the canonical Place identity but remains proposal-only.
  perform atlas.admit_shared_intelligence_entity_to_reality_service_v1(
    v_springfield_business,jsonb_build_object('fixture','reality_place_resolution_v1')
  );
  v_prop:=atlas.propose_shared_intelligence_entity_geography_to_reality_service(
    v_springfield_assertion,'fixture:reality_place_resolution_v1:springfield-business'
  );
  v_prop_id:=(v_prop->>'propositionId')::uuid;
  if v_prop->>'autoAdjudicated'<>'false' then raise exception 'Shared geography proposition must not auto-adjudicate.'; end if;
  if (v_prop->>'canonicalPlaceEntityId')::uuid<>v_springfield then raise exception 'Shared geography proposition used the wrong canonical Place.'; end if;
  if not exists(
    select 1 from reality.relationship_propositions
    where id=v_prop_id and proposition_state='open' and subject_entity_id=v_springfield_business
      and relationship_kind='located_in' and object_entity_id=v_springfield
  ) then raise exception 'Expected open located_in proposition missing.'; end if;
  if exists(
    select 1 from reality.entity_relationships
    where subject_entity_id=v_springfield_business and relationship_kind='located_in' and object_entity_id=v_springfield
      and relationship_state in ('observed','established')
  ) then raise exception 'Proposal-only Shared geography must not establish canonical spatial truth.'; end if;
end
$fixture$;

select jsonb_build_object(
  'contractVersion','atlas_reality_place_resolution_validation_v1',
  'status','passed',
  'springfieldPlaceProfilesInsideTransaction',(select count(*) from reality.place_profiles where entity_id='ae278491-3c5b-4a11-873e-11b74846c06c'::uuid),
  'springfieldIdentityKeysInsideTransaction',(select count(*) from reality.place_identity_keys where entity_id='ae278491-3c5b-4a11-873e-11b74846c06c'::uuid),
  'openGeographyPropositionsInsideTransaction',(select count(*) from reality.relationship_propositions where idempotency_key='fixture:reality_place_resolution_v1:springfield-business')
) as validation_receipt;

rollback;
