begin;

do $validation$
declare
  v_practitioner constant uuid := 'f4300000-0000-4000-8000-000000000001'::uuid;
  v_case constant uuid := 'f4300000-0000-4000-8000-000000000111'::uuid;
  v_org constant uuid := 'f4300000-0000-4000-8000-000000000201'::uuid;
  v_outside_org constant uuid := 'f4300000-0000-4000-8000-000000000202'::uuid;
  v_person constant uuid := 'f4300000-0000-4000-8000-000000000211'::uuid;
  v_outside_person constant uuid := 'f4300000-0000-4000-8000-000000000212'::uuid;
  v_candidate constant uuid := 'f4300000-0000-4000-8000-000000000301'::uuid;
  v_outside_candidate constant uuid := 'f4300000-0000-4000-8000-000000000302'::uuid;
  v_missing_basis_candidate constant uuid := 'f4300000-0000-4000-8000-000000000303'::uuid;
  v_sponsor_participant constant uuid := 'f4300000-0000-4000-8000-000000000122'::uuid;
  v_result jsonb;
  v_preview jsonb;
  v_record_id uuid;
  v_literal text;
  v_def text;
begin
  if to_regprocedure(
    'atlas.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)'
  ) is null then
    raise exception 'Internal Reality Candidate promotion preview is missing.';
  end if;

  if to_regprocedure(
    'atlas.promote_implementation_reality_candidate_self_api_v1(uuid)'
  ) is null then
    raise exception 'Internal Reality Candidate promotion command is missing.';
  end if;

  if to_regprocedure(
    'public.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)'
  ) is null then
    raise exception 'Public Reality Candidate promotion preview membrane is missing.';
  end if;

  if to_regprocedure(
    'public.promote_implementation_reality_candidate_self_api_v1(uuid)'
  ) is null then
    raise exception 'Public Reality Candidate promotion membrane is missing.';
  end if;

  perform set_config('request.jwt.claim.sub',v_practitioner::text,true);

  if exists(
    select 1
    from atlas.institutional_person_records ipr
    where ipr.organization_id=v_org
      and ipr.person_id=v_person
  ) then
    raise exception 'Promotion fixture unexpectedly begins with canonical Institutional Person truth.';
  end if;

  -- Sponsor governance is a live prerequisite, not implied by practitioner assignment.
  update atlas.implementation_case_participants
  set active=false,ended_at=now(),updated_at=now()
  where id=v_sponsor_participant;

  v_preview:=public.preview_implementation_reality_candidate_promotion_self_api_v1(
    v_candidate
  );

  if v_preview->>'state'<>'setup_sponsor_authority_required'
     or coalesce((v_preview->>'canPromote')::boolean,false) then
    raise exception 'Reality promotion ignored missing live setup-sponsor governance: %',v_preview;
  end if;

  update atlas.implementation_case_participants
  set active=true,ended_at=null,updated_at=now()
  where id=v_sponsor_participant;

  -- A fully resolved, sponsor-governed candidate is now promotable.
  v_preview:=public.preview_implementation_reality_candidate_promotion_self_api_v1(
    v_candidate
  );

  if v_preview->>'state'<>'ready'
     or not coalesce((v_preview->>'canPromote')::boolean,false)
     or not coalesce((v_preview->>'promotionCommandAvailable')::boolean,false)
     or not coalesce((v_preview->>'canExecutePromotion')::boolean,false)
     or v_preview->'consequence'->>'kind'<>'institutional_person_record'
     or v_preview->'consequence'->>'mode'<>'create_relation' then
    raise exception 'Valid Institutional Person Reality Candidate did not preview executable after mutation release: %',v_preview;
  end if;

  -- An equally canonical identity outside the case-bound Organization remains blocked.
  v_preview:=public.preview_implementation_reality_candidate_promotion_self_api_v1(
    v_outside_candidate
  );

  if v_preview->>'state'<>'outside_implementation_scope'
     or coalesce((v_preview->>'canPromote')::boolean,false) then
    raise exception 'Out-of-scope Reality Candidate became promotable: %',v_preview;
  end if;

  v_result:=public.promote_implementation_reality_candidate_self_api_v1(
    v_outside_candidate
  );

  if coalesce((v_result->>'promoted')::boolean,false)
     or exists(
       select 1
       from atlas.institutional_person_records ipr
       where ipr.organization_id=v_outside_org
         and ipr.person_id=v_outside_person
     ) then
    raise exception 'Out-of-scope Reality Candidate created canonical Institutional Person truth.';
  end if;

  -- Candidate promotion requires an explicit governed establishment basis.
  v_preview:=public.preview_implementation_reality_candidate_promotion_self_api_v1(
    v_missing_basis_candidate
  );

  if v_preview->>'state'<>'establishment_basis_required'
     or coalesce((v_preview->>'canPromote')::boolean,false) then
    raise exception 'Reality Candidate without establishment basis became promotable: %',v_preview;
  end if;

  select literal_statement
  into v_literal
  from atlas.implementation_reality_candidates
  where id=v_candidate;

  -- First real promotion.
  v_result:=public.promote_implementation_reality_candidate_self_api_v1(
    v_candidate
  );

  if not coalesce((v_result->>'ok')::boolean,false)
     or not coalesce((v_result->>'promoted')::boolean,false)
     or coalesce((v_result->>'alreadyPromoted')::boolean,false)
     or v_result->>'canonicalConsequenceKind'<>'institutional_person_record' then
    raise exception 'Valid Reality Candidate did not promote through owning domain command: %',v_result;
  end if;

  begin
    v_record_id:=(v_result->>'canonicalConsequenceRef')::uuid;
  exception when invalid_text_representation then
    raise exception 'Promotion did not return a canonical Institutional Person Record id: %',v_result;
  end;

  if not exists(
    select 1
    from atlas.institutional_person_records ipr
    where ipr.id=v_record_id
      and ipr.organization_id=v_org
      and ipr.person_id=v_person
      and ipr.status='active'
      and ipr.establishment_basis->>'contractVersion'='institutional_person_reality_promotion_v1'
      and (ipr.establishment_basis->>'realityCandidateId')::uuid=v_candidate
  ) then
    raise exception 'Owning Identity-domain command did not establish the expected Institutional Person Record.';
  end if;

  if not exists(
    select 1
    from atlas.implementation_reality_candidates c
    where c.id=v_candidate
      and c.candidate_state='promoted'
      and c.canonical_consequence_kind='institutional_person_record'
      and c.canonical_consequence_ref=v_record_id::text
      and c.promoted_at is not null
      and c.promoted_by_user_id=v_practitioner
      and c.literal_statement=v_literal
  ) then
    raise exception 'Candidate promotion receipt was not recorded atomically without rewriting authored text.';
  end if;

  -- Canonical rerender comes from source-domain truth, not the authored sentence.
  if v_result->'realityEntry'->>'sentence'
       <> 'Promotion Proof Organization knows Known Person as an institutional Person.' then
    raise exception 'Canonical Reality rerender did not derive from Organization + Person truth: %',v_result;
  end if;

  if v_result->'realityEntry'->>'sentence'=v_literal then
    raise exception 'Authored sentence text was incorrectly reused as canonical rerender.';
  end if;

  -- Knowing a Person does not manufacture login, membership, seat, appointment, or Work.
  if exists(
    select 1 from atlas.person_auth_credentials pac
    where pac.person_id=v_person and pac.status='active'
  ) then
    raise exception 'Institutional Person promotion manufactured an auth credential.';
  end if;

  if exists(
    select 1 from atlas.organization_memberships m
    where m.organization_id=v_org and m.person_id=v_person
  ) then
    raise exception 'Institutional Person promotion manufactured Organization Membership.';
  end if;

  if exists(
    select 1 from atlas.organization_employee_seats s
    where s.organization_id=v_org
      and s.institutional_person_record_id=v_record_id
  ) then
    raise exception 'Institutional Person promotion manufactured an employee seat.';
  end if;

  if exists(
    select 1 from atlas.organization_position_appointments a
    where a.organization_id=v_org
      and a.institutional_person_record_id=v_record_id
  ) then
    raise exception 'Institutional Person promotion manufactured a Position Appointment.';
  end if;

  -- Retry is idempotent and re-renders the same canonical consequence.
  v_result:=public.promote_implementation_reality_candidate_self_api_v1(
    v_candidate
  );

  if not coalesce((v_result->>'alreadyPromoted')::boolean,false)
     or (v_result->>'canonicalConsequenceRef')::uuid<>v_record_id then
    raise exception 'Reality Candidate promotion is not idempotent: %',v_result;
  end if;

  -- Browser/service roles cannot bypass the public membrane.
  if has_function_privilege(
       'authenticated',
       'atlas.promote_implementation_reality_candidate_self_api_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'atlas.promote_implementation_reality_candidate_self_api_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.establish_institutional_person_from_reality_internal_v1(uuid,uuid,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'atlas.establish_institutional_person_from_reality_internal_v1(uuid,uuid,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Reality promotion leaked direct owning-domain/internal execution authority.';
  end if;

  if has_function_privilege(
       'anon',
       'public.promote_implementation_reality_candidate_self_api_v1(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Anonymous role can promote Reality Candidates.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'public.promote_implementation_reality_candidate_self_api_v1(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated practitioner membrane is not executable.';
  end if;

  if to_regprocedure(
       'public.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)'
     ) is null
     or to_regprocedure(
       'public.promote_implementation_reality_candidate_self_api_v1(uuid)'
     ) is null then
    raise exception 'Promotion command requires the separate preview membrane and public promotion writer.';
  end if;

  select lower(pg_get_functiondef(
    'public.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)'::regprocedure
  )) into v_def;

  if v_def not like '%promotioncommandavailable%'
     or v_def not like '%canexecutepromotion%' then
    raise exception 'Separately released promotion preview lost dynamic command capability signaling.';
  end if;

  select lower(pg_get_functiondef(
    'atlas.promote_implementation_reality_candidate_self_api_v1(uuid)'::regprocedure
  )) into v_def;

  if v_def not like '%implementation_practitioner_assigned_to_case_self_v1%'
     or v_def not like '%preview_implementation_reality_candidate_promotion_self_api_v1%'
     or v_def not like '%establish_institutional_person_from_reality_internal_v1%'
     or v_def not like '%candidate_state=''promoted''%' then
    raise exception 'Reality promotion orchestration lost its authority, preview, owning-command, or receipt boundary.';
  end if;

  select lower(pg_get_functiondef(
    'atlas.establish_institutional_person_from_reality_internal_v1(uuid,uuid,jsonb)'::regprocedure
  )) into v_def;

  if v_def like '%organization_memberships%'
     or v_def like '%organization_employee_seats%'
     or v_def like '%organization_position_appointments%'
     or v_def like '%auth.users%' then
    raise exception 'Institutional Person owning-domain command widened into membership/access/appointment/login mutation.';
  end if;
end;
$validation$;

rollback;
