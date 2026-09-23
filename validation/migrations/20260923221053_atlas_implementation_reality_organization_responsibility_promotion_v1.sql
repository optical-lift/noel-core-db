begin;

do $validation$
declare
  v_practitioner constant uuid:='f4800000-0000-4000-8000-000000000001'::uuid;
  v_candidate constant uuid:='f4800000-0000-4000-8000-000000000301'::uuid;
  v_blocked constant uuid:='f4800000-0000-4000-8000-000000000302'::uuid;
  v_duplicate constant uuid:='f4800000-0000-4000-8000-000000000303'::uuid;
  v_org constant uuid:='f4800000-0000-4000-8000-000000000201'::uuid;
  v_result jsonb;
  v_id uuid;
  v_before bigint;
  v_after bigint;
  v_candidate_row atlas.implementation_reality_candidates%rowtype;
  v_record atlas.organization_responsibilities%rowtype;
begin
  if to_regprocedure(
    'public.promote_implementation_reality_responsibility_self_api_v1(uuid)'
  ) is null then
    raise exception 'Public Responsibility promotion command is missing.';
  end if;

  if length('promote_implementation_reality_responsibility_self_api_v1')>63 then
    raise exception 'Responsibility promotion RPC exceeds PostgreSQL identifier limit.';
  end if;

  perform set_config('request.jwt.claim.sub',v_practitioner::text,true);

  select count(*) into v_before
  from atlas.organization_responsibilities
  where organization_id=v_org;

  v_result:=public.promote_implementation_reality_responsibility_self_api_v1(v_candidate);

  if not coalesce((v_result->>'ok')::boolean,false)
     or not coalesce((v_result->>'promoted')::boolean,false)
     or coalesce((v_result->>'alreadyPromoted')::boolean,true)
     or v_result->>'canonicalConsequenceKind'<>'organization_responsibility'
     or v_result->'receipt'->>'state'<>'established'
     or v_result->'realityEntry'->>'sentence'<>
        'Responsibility Command Proof has Responsibility Production stewardship (stewardship).' then
    raise exception 'Responsibility candidate did not promote lawfully: %',v_result;
  end if;

  v_id:=(v_result->>'canonicalConsequenceRef')::uuid;

  select * into v_candidate_row
  from atlas.implementation_reality_candidates where id=v_candidate;

  if v_candidate_row.candidate_state<>'promoted'
     or v_candidate_row.canonical_consequence_kind<>'organization_responsibility'
     or v_candidate_row.canonical_consequence_ref<>v_id::text
     or v_candidate_row.promoted_by_user_id<>v_practitioner
     or v_candidate_row.provenance->>'promotionContract'<>
        'organization_responsibility_reality_promotion_v1' then
    raise exception 'Responsibility promotion receipt/provenance was not recorded.';
  end if;

  select * into v_record
  from atlas.organization_responsibilities where id=v_id;

  if v_record.id is null
     or v_record.organization_id<>v_org
     or v_record.name<>'Production stewardship'
     or v_record.responsibility_kind<>'stewardship'
     or v_record.status<>'active'
     or nullif(btrim(v_record.stable_key),'') is null then
    raise exception 'Canonical Responsibility was not established correctly.';
  end if;

  if v_record.metadata->>'establishedBy'<>
       'organization_responsibility_reality_promotion_v1'
     or v_record.metadata->'establishmentBasis'->>'realityCandidateId'<>v_candidate::text then
    raise exception 'Canonical Responsibility lost establishment provenance.';
  end if;

  select count(*) into v_after
  from atlas.organization_responsibilities where organization_id=v_org;

  if v_after<>v_before+1 then
    raise exception 'Responsibility promotion created an unexpected row count.';
  end if;

  v_result:=public.promote_implementation_reality_responsibility_self_api_v1(v_candidate);
  if not coalesce((v_result->>'alreadyPromoted')::boolean,false)
     or v_result->>'canonicalConsequenceRef'<>v_id::text then
    raise exception 'Repeated Responsibility promotion was not idempotent: %',v_result;
  end if;

  v_result:=public.promote_implementation_reality_responsibility_self_api_v1(v_duplicate);
  if coalesce((v_result->>'promoted')::boolean,false)
     or v_result->'preview'->>'state'<>'canonical_identity_exists' then
    raise exception 'Duplicate Responsibility candidate bypassed identity: %',v_result;
  end if;

  select * into v_candidate_row
  from atlas.implementation_reality_candidates where id=v_duplicate;
  if v_candidate_row.candidate_state<>'unresolved' then
    raise exception 'Duplicate Responsibility candidate did not remain unresolved.';
  end if;

  v_result:=public.promote_implementation_reality_responsibility_self_api_v1(v_blocked);
  if coalesce((v_result->>'promoted')::boolean,false)
     or v_result->'preview'->>'state'<>'semantic_payload_required' then
    raise exception 'Missing responsibilityKind crossed command gate: %',v_result;
  end if;

  if has_function_privilege(
       'anon',
       'public.promote_implementation_reality_responsibility_self_api_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.promote_implementation_reality_responsibility_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'atlas.establish_organization_responsibility_from_reality_v1(uuid,text,text,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Responsibility mutation authority leaked around public membrane.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.promote_implementation_reality_responsibility_self_api_v1(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated practitioner cannot execute Responsibility promotion.';
  end if;
end;
$validation$;

rollback;
