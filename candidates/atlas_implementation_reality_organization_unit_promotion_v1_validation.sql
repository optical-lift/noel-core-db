begin;

do $validation$
declare
  v_practitioner constant uuid:='f4500000-0000-4000-8000-000000000001'::uuid;
  v_candidate constant uuid:='f4500000-0000-4000-8000-000000000301'::uuid;
  v_blocked constant uuid:='f4500000-0000-4000-8000-000000000302'::uuid;
  v_parent constant uuid:='f4500000-0000-4000-8000-000000000211'::uuid;
  v_org constant uuid:='f4500000-0000-4000-8000-000000000201'::uuid;
  v_result jsonb;
  v_unit_id uuid;
  v_count_before bigint;
  v_count_after bigint;
  v_candidate_row atlas.implementation_reality_candidates%rowtype;
  v_unit atlas.organization_units%rowtype;
begin
  if to_regprocedure(
    'public.promote_implementation_reality_organization_unit_self_api_v1(uuid)'
  ) is null then
    raise exception 'Public Organization Unit promotion command is missing.';
  end if;

  if to_regprocedure(
    'public.preview_implementation_reality_organization_unit_promotion_self_api_v1(uuid)'
  ) is null then
    raise exception 'Organization Unit promotion command lost preview prerequisite.';
  end if;

  perform set_config('request.jwt.claim.sub',v_practitioner::text,true);

  select count(*)
  into v_count_before
  from atlas.organization_units
  where organization_id=v_org;

  v_result:=public.promote_implementation_reality_organization_unit_self_api_v1(
    v_candidate
  );

  if not coalesce((v_result->>'ok')::boolean,false)
     or not coalesce((v_result->>'promoted')::boolean,false)
     or coalesce((v_result->>'alreadyPromoted')::boolean,true)
     or v_result->>'canonicalConsequenceKind'<>'organization_unit'
     or v_result->'receipt'->>'state'<>'established'
     or v_result->'realityEntry'->>'consequenceKind'<>'organization_unit'
     or v_result->'realityEntry'->>'sentence'<>
        'Organization Unit Command Proof has Organization Unit Field Operations (program) inside Command Parent.' then
    raise exception 'Organization Unit candidate did not promote through owning-domain command: %',v_result;
  end if;

  v_unit_id:=(v_result->>'canonicalConsequenceRef')::uuid;

  select *
  into v_candidate_row
  from atlas.implementation_reality_candidates
  where id=v_candidate;

  if v_candidate_row.candidate_state<>'promoted'
     or v_candidate_row.canonical_consequence_kind<>'organization_unit'
     or v_candidate_row.canonical_consequence_ref<>v_unit_id::text
     or v_candidate_row.promoted_by_user_id<>v_practitioner
     or v_candidate_row.provenance->>'promotionContract'<>'organization_unit_reality_promotion_v1' then
    raise exception 'Promoted candidate receipt/provenance was not recorded correctly.';
  end if;

  select *
  into v_unit
  from atlas.organization_units
  where id=v_unit_id;

  if v_unit.id is null
     or v_unit.organization_id<>v_org
     or v_unit.parent_unit_id<>v_parent
     or v_unit.name<>'Field Operations'
     or v_unit.unit_kind<>'program'
     or v_unit.status<>'active'
     or nullif(btrim(v_unit.stable_key),'') is null
     or v_unit.stable_key='Field Operations' then
    raise exception 'Canonical Organization Unit was not established with owning-domain semantics.';
  end if;

  if v_unit.metadata->>'establishedBy'<>'organization_unit_reality_promotion_v1'
     or v_unit.metadata->'establishmentBasis'->>'realityCandidateId'<>v_candidate::text then
    raise exception 'Canonical Organization Unit lost establishment provenance.';
  end if;

  select count(*)
  into v_count_after
  from atlas.organization_units
  where organization_id=v_org;

  if v_count_after<>v_count_before+1 then
    raise exception 'Organization Unit promotion created an unexpected number of canonical Units.';
  end if;

  -- Candidate-level idempotence must return canonical truth without another write.
  v_result:=public.promote_implementation_reality_organization_unit_self_api_v1(
    v_candidate
  );

  if not coalesce((v_result->>'ok')::boolean,false)
     or not coalesce((v_result->>'promoted')::boolean,false)
     or not coalesce((v_result->>'alreadyPromoted')::boolean,false)
     or v_result->>'canonicalConsequenceRef'<>v_unit_id::text then
    raise exception 'Repeated Organization Unit promotion was not idempotent: %',v_result;
  end if;

  if (
    select count(*)
    from atlas.organization_units
    where organization_id=v_org
  )<>v_count_after then
    raise exception 'Repeated Organization Unit promotion created duplicate canonical truth.';
  end if;

  v_result:=public.promote_implementation_reality_organization_unit_self_api_v1(
    v_blocked
  );

  if coalesce((v_result->>'promoted')::boolean,false)
     or v_result->'preview'->>'state'<>'semantic_payload_required' then
    raise exception 'Blocked Organization Unit candidate crossed the semantic-payload gate: %',v_result;
  end if;

  select *
  into v_candidate_row
  from atlas.implementation_reality_candidates
  where id=v_blocked;

  if v_candidate_row.candidate_state<>'unresolved'
     or v_candidate_row.canonical_consequence_kind is not null
     or v_candidate_row.canonical_consequence_ref is not null then
    raise exception 'Blocked candidate did not remain noncanonical unresolved custody.';
  end if;

  if has_function_privilege(
       'anon',
       'public.promote_implementation_reality_organization_unit_self_api_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.promote_implementation_reality_organization_unit_self_api_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'atlas.establish_organization_unit_from_reality_internal_v1(uuid,uuid,text,text,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Organization Unit mutation authority leaked around its public membrane.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.promote_implementation_reality_organization_unit_self_api_v1(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated practitioner cannot execute Organization Unit promotion command.';
  end if;
end;
$validation$;

rollback;
