begin;

do $validation$
declare
  v_practitioner constant uuid:='f4700000-0000-4000-8000-000000000001'::uuid;
  v_candidate constant uuid:='f4700000-0000-4000-8000-000000000301'::uuid;
  v_blocked constant uuid:='f4700000-0000-4000-8000-000000000302'::uuid;
  v_duplicate constant uuid:='f4700000-0000-4000-8000-000000000303'::uuid;
  v_org constant uuid:='f4700000-0000-4000-8000-000000000201'::uuid;
  v_unit constant uuid:='f4700000-0000-4000-8000-000000000211'::uuid;
  v_result jsonb;
  v_position_id uuid;
  v_count_before bigint;
  v_count_after bigint;
  v_candidate_row atlas.implementation_reality_candidates%rowtype;
  v_position atlas.organization_positions%rowtype;
begin
  if to_regprocedure('public.promote_implementation_reality_position_self_api_v1(uuid)') is null then
    raise exception 'Public Position promotion command is missing.';
  end if;

  if length('promote_implementation_reality_position_self_api_v1')>63 then
    raise exception 'Position promotion RPC exceeds PostgreSQL identifier limit.';
  end if;

  perform set_config('request.jwt.claim.sub',v_practitioner::text,true);

  select count(*) into v_count_before
  from atlas.organization_positions
  where organization_id=v_org and organization_unit_id=v_unit;

  v_result:=public.promote_implementation_reality_position_self_api_v1(v_candidate);

  if not coalesce((v_result->>'ok')::boolean,false)
     or not coalesce((v_result->>'promoted')::boolean,false)
     or coalesce((v_result->>'alreadyPromoted')::boolean,true)
     or v_result->>'canonicalConsequenceKind'<>'organization_position'
     or v_result->'receipt'->>'state'<>'established'
     or v_result->'realityEntry'->>'sentence'<>
        'Operations has Position Field Lead (operations).' then
    raise exception 'Position candidate did not promote through owning-domain command: %',v_result;
  end if;

  v_position_id:=(v_result->>'canonicalConsequenceRef')::uuid;

  select * into v_candidate_row
  from atlas.implementation_reality_candidates
  where id=v_candidate;

  if v_candidate_row.candidate_state<>'promoted'
     or v_candidate_row.canonical_consequence_kind<>'organization_position'
     or v_candidate_row.canonical_consequence_ref<>v_position_id::text
     or v_candidate_row.promoted_by_user_id<>v_practitioner
     or v_candidate_row.provenance->>'promotionContract'<>'organization_position_reality_promotion_v1' then
    raise exception 'Promoted Position candidate receipt/provenance was not recorded correctly.';
  end if;

  select * into v_position
  from atlas.organization_positions
  where id=v_position_id;

  if v_position.id is null
     or v_position.organization_id<>v_org
     or v_position.organization_unit_id<>v_unit
     or v_position.display_title<>'Field Lead'
     or v_position.position_kind<>'operations'
     or v_position.status<>'active'
     or nullif(btrim(v_position.stable_key),'') is null then
    raise exception 'Canonical Position was not established correctly.';
  end if;

  if v_position.metadata->>'establishedBy'<>'organization_position_reality_promotion_v1'
     or v_position.metadata->'establishmentBasis'->>'realityCandidateId'<>v_candidate::text then
    raise exception 'Canonical Position lost establishment provenance.';
  end if;

  select count(*) into v_count_after
  from atlas.organization_positions
  where organization_id=v_org and organization_unit_id=v_unit;

  if v_count_after<>v_count_before+1 then
    raise exception 'Position promotion created an unexpected number of canonical Positions.';
  end if;

  v_result:=public.promote_implementation_reality_position_self_api_v1(v_candidate);
  if not coalesce((v_result->>'alreadyPromoted')::boolean,false)
     or v_result->>'canonicalConsequenceRef'<>v_position_id::text then
    raise exception 'Repeated Position promotion was not candidate-idempotent: %',v_result;
  end if;

  if (
    select count(*) from atlas.organization_positions
    where organization_id=v_org and organization_unit_id=v_unit
  )<>v_count_after then
    raise exception 'Repeated Position promotion created duplicate canonical truth.';
  end if;

  v_result:=public.promote_implementation_reality_position_self_api_v1(v_duplicate);
  if coalesce((v_result->>'promoted')::boolean,false)
     or v_result->'preview'->>'state'<>'canonical_identity_exists' then
    raise exception 'Second same-role candidate bypassed canonical Position identity: %',v_result;
  end if;

  select * into v_candidate_row
  from atlas.implementation_reality_candidates where id=v_duplicate;
  if v_candidate_row.candidate_state<>'unresolved' then
    raise exception 'Duplicate Position candidate did not remain unresolved.';
  end if;

  v_result:=public.promote_implementation_reality_position_self_api_v1(v_blocked);
  if coalesce((v_result->>'promoted')::boolean,false)
     or v_result->'preview'->>'state'<>'semantic_payload_required' then
    raise exception 'Missing positionKind crossed command gate: %',v_result;
  end if;

  if has_function_privilege(
       'anon','public.promote_implementation_reality_position_self_api_v1(uuid)','EXECUTE'
     )
     or has_function_privilege(
       'authenticated','atlas.promote_implementation_reality_position_v1(uuid)','EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'atlas.establish_organization_position_from_reality_v1(uuid,text,text,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Position mutation authority leaked around public membrane.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.promote_implementation_reality_position_self_api_v1(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated practitioner cannot execute Position promotion command.';
  end if;
end;
$validation$;

rollback;
