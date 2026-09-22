begin;

do $validation$
declare
  v_assigned constant uuid := 'f4700000-0000-4000-8000-000000000001'::uuid;
  v_unassigned constant uuid := 'f4700000-0000-4000-8000-000000000002'::uuid;
  v_case constant uuid := 'f4700000-0000-4000-8000-000000000111'::uuid;
  v_crosswalk constant uuid := 'f4700000-0000-4000-8000-000000000141'::uuid;
  v_domain_fact constant uuid := 'f4700000-0000-4000-8000-000000000142'::uuid;
  v_high_consequence constant uuid := 'f4700000-0000-4000-8000-000000000143'::uuid;
  v_superseding constant uuid := 'f4700000-0000-4000-8000-000000000144'::uuid;
  v_reality constant uuid := 'f4700000-0000-4000-8000-000000000151'::uuid;
  v_request1 constant uuid := 'f4700000-0000-4000-8000-000000000301'::uuid;
  v_request2 constant uuid := 'f4700000-0000-4000-8000-000000000302'::uuid;
  v_request3 constant uuid := 'f4700000-0000-4000-8000-000000000303'::uuid;
  v_request4 constant uuid := 'f4700000-0000-4000-8000-000000000304'::uuid;
  v_request5 constant uuid := 'f4700000-0000-4000-8000-000000000305'::uuid;
  v_result jsonb;
  v_first_id uuid;
  v_count integer;
  v_status text;
  v_def text;
begin
  perform set_config('request.jwt.claim.sub',v_assigned::text,true);

  -- A configuration crosswalk may be governed for model use without claiming
  -- any canonical domain mutation.
  v_result:=public.adjudicate_implementation_finding_self_api_v1(
    v_crosswalk,
    'configuration_crosswalk',
    'govern_for_model',
    'Two independent implementation evidence streams support this crosswalk.',
    '{"sources":["testimony","record"],"validationFixture":true}'::jsonb,
    'implementation_finding_adjudication_v1',
    null,
    null,
    v_request1
  );

  if v_result->>'findingStatus'<>'governed'
     or not coalesce((v_result->>'modelEligible')::boolean,false)
     or coalesce((v_result->>'canonicalDomainMutation')::boolean,true)
     or (v_result->>'adjudicationNumber')::integer<>1 then
    raise exception 'Configuration-crosswalk governance result is incorrect: %',v_result;
  end if;

  v_first_id:=(v_result->>'adjudicationId')::uuid;

  select status into v_status
  from atlas.implementation_findings
  where id=v_crosswalk;

  if v_status<>'governed'
     or not atlas.implementation_finding_model_eligible_v1(v_crosswalk) then
    raise exception 'Governed Finding projection/model eligibility was not established.';
  end if;

  -- Exact retry must return the same immutable adjudication without a duplicate.
  v_result:=public.adjudicate_implementation_finding_self_api_v1(
    v_crosswalk,
    'configuration_crosswalk',
    'govern_for_model',
    'Two independent implementation evidence streams support this crosswalk.',
    '{"sources":["testimony","record"],"validationFixture":true}'::jsonb,
    'implementation_finding_adjudication_v1',
    null,
    null,
    v_request1
  );

  if not coalesce((v_result->>'alreadyAdjudicated')::boolean,false)
     or (v_result->>'adjudicationId')::uuid<>v_first_id
     or (v_result->>'adjudicationNumber')::integer<>1 then
    raise exception 'Finding adjudication retry was not idempotent: %',v_result;
  end if;

  select count(*) into v_count
  from atlas.implementation_finding_adjudications
  where implementation_finding_id=v_crosswalk;

  if v_count<>1 then
    raise exception 'Idempotent retry created duplicate adjudication evidence.';
  end if;

  -- A later unresolved decision must remain append-only and revoke current
  -- model eligibility through the latest adjudication projection.
  v_result:=public.adjudicate_implementation_finding_self_api_v1(
    v_crosswalk,
    'configuration_crosswalk',
    'mark_unresolved',
    'New contradictory evidence requires another implementation pass.',
    '{"contradiction":"validation","validationFixture":true}'::jsonb,
    'implementation_finding_adjudication_v1',
    null,
    null,
    v_request2
  );

  if v_result->>'findingStatus'<>'unresolved'
     or coalesce((v_result->>'modelEligible')::boolean,true)
     or (v_result->>'adjudicationNumber')::integer<>2
     or atlas.implementation_finding_model_eligible_v1(v_crosswalk) then
    raise exception 'Later unresolved adjudication did not supersede current model eligibility: %',v_result;
  end if;

  if not exists (
    select 1
    from atlas.implementation_finding_adjudications a2
    join atlas.implementation_finding_adjudications a1
      on a1.id=a2.previous_adjudication_id
    where a2.implementation_finding_id=v_crosswalk
      and a2.adjudication_number=2
      and a1.adjudication_number=1
  ) then
    raise exception 'Adjudication history chain is incomplete.';
  end if;

  -- Existing-domain facts cannot become model-eligible from Finding text alone.
  begin
    perform public.adjudicate_implementation_finding_self_api_v1(
      v_domain_fact,
      'existing_domain_fact',
      'govern_for_model',
      'Attempt without owning-domain consequence.',
      '{"validationFixture":true}'::jsonb,
      'implementation_finding_adjudication_v1',
      null,
      null,
      v_request3
    );
    raise exception 'Existing-domain fact incorrectly governed without promoted Reality Candidate.';
  exception
    when sqlstate '23514' then null;
  end;

  if (select status from atlas.implementation_findings where id=v_domain_fact)<>'proposed' then
    raise exception 'Failed existing-domain adjudication mutated Finding status.';
  end if;

  -- Once the same-case Reality Candidate is already promoted, the Finding may
  -- reference that canonical consequence for model use.
  v_result:=public.adjudicate_implementation_finding_self_api_v1(
    v_domain_fact,
    'existing_domain_fact',
    'govern_for_model',
    'The linked Reality Candidate already carries the owning-domain consequence.',
    '{"canonicalConsequenceWitnessed":true,"validationFixture":true}'::jsonb,
    'implementation_finding_adjudication_v1',
    v_reality,
    null,
    v_request3
  );

  if v_result->>'findingStatus'<>'governed'
     or not coalesce((v_result->>'modelEligible')::boolean,false)
     or (v_result->>'linkedRealityCandidateId')::uuid<>v_reality then
    raise exception 'Promoted Reality Candidate was not accepted as existing-domain consequence evidence: %',v_result;
  end if;

  -- High-consequence classes remain reviewable but cannot be promoted to model
  -- use by the initial one-practitioner seam.
  begin
    perform public.adjudicate_implementation_finding_self_api_v1(
      v_high_consequence,
      'decision_authority_fact',
      'govern_for_model',
      'Single-practitioner authority must be insufficient here.',
      '{"validationFixture":true}'::jsonb,
      'implementation_finding_adjudication_v1',
      null,
      null,
      v_request4
    );
    raise exception 'High-consequence Finding class incorrectly became model-eligible.';
  exception
    when sqlstate '42501' then null;
  end;

  if (select status from atlas.implementation_findings where id=v_high_consequence)<>'proposed' then
    raise exception 'Rejected high-consequence promotion attempt mutated Finding status.';
  end if;

  -- Supersession preserves the original adjudication history and requires a
  -- distinct same-case Finding.
  v_result:=public.adjudicate_implementation_finding_self_api_v1(
    v_domain_fact,
    'existing_domain_fact',
    'supersede',
    'Later evidence is represented by a distinct replacement Finding.',
    '{"validationFixture":true}'::jsonb,
    'implementation_finding_adjudication_v1',
    null,
    v_superseding,
    v_request5
  );

  if v_result->>'findingStatus'<>'superseded'
     or atlas.implementation_finding_model_eligible_v1(v_domain_fact) then
    raise exception 'Finding supersession did not terminate model eligibility: %',v_result;
  end if;

  -- Read membrane returns the immutable history only for the assigned case.
  v_result:=public.implementation_finding_review_self_api_v1(v_crosswalk);

  if not coalesce((v_result->>'ok')::boolean,false)
     or v_result#>>'{finding,status}'<>'unresolved'
     or jsonb_array_length(coalesce(v_result->'adjudications','[]'::jsonb))<>2
     or coalesce((v_result#>>'{finding,modelEligible}')::boolean,true) then
    raise exception 'Finding review read membrane returned incorrect current/history state: %',v_result;
  end if;

  -- A generally authorized practitioner who is not assigned to this exact case
  -- cannot adjudicate it.
  perform set_config('request.jwt.claim.sub',v_unassigned::text,true);

  begin
    perform public.adjudicate_implementation_finding_self_api_v1(
      v_high_consequence,
      'decision_authority_fact',
      'mark_unresolved',
      'Unauthorized cross-case review attempt.',
      '{"validationFixture":true}'::jsonb,
      'implementation_finding_adjudication_v1',
      null,
      null,
      'f4700000-0000-4000-8000-000000000306'::uuid
    );
    raise exception 'Unassigned practitioner was allowed to adjudicate another case.';
  exception
    when sqlstate '42501' then null;
  end;

  v_result:=public.implementation_finding_review_self_api_v1(v_crosswalk);
  if coalesce((v_result->>'ok')::boolean,true)
     or v_result->>'code'<>'assigned_practitioner_authority_required' then
    raise exception 'Read membrane failed open for unassigned practitioner: %',v_result;
  end if;

  perform set_config('request.jwt.claim.sub',v_assigned::text,true);

  -- Adjudication evidence itself is immutable even to a direct writer.
  begin
    update atlas.implementation_finding_adjudications
    set basis='forbidden rewrite'
    where id=v_first_id;
    raise exception 'Append-only adjudication row was mutable.';
  exception
    when sqlstate '42501' then null;
  end;

  begin
    delete from atlas.implementation_finding_adjudications
    where id=v_first_id;
    raise exception 'Append-only adjudication row was deletable.';
  exception
    when sqlstate '42501' then null;
  end;

  if has_table_privilege(
       'authenticated',
       'atlas.implementation_finding_adjudications',
       'SELECT'
     )
     or has_table_privilege(
       'authenticated',
       'atlas.implementation_finding_adjudications',
       'INSERT'
     )
     or has_table_privilege(
       'authenticated',
       'atlas.implementation_finding_adjudications',
       'UPDATE'
     )
     or has_table_privilege(
       'authenticated',
       'atlas.implementation_finding_adjudications',
       'DELETE'
     ) then
    raise exception 'Authenticated browser role has direct Finding-adjudication table privileges.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.adjudicate_implementation_finding_self_api_v1(uuid,text,text,text,jsonb,text,uuid,uuid,uuid)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'public.implementation_finding_review_self_api_v1(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated Finding adjudication membranes are not executable.';
  end if;

  if has_function_privilege(
       'anon',
       'public.adjudicate_implementation_finding_self_api_v1(uuid,text,text,text,jsonb,text,uuid,uuid,uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'public.implementation_finding_review_self_api_v1(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Anonymous role can execute Finding adjudication membranes.';
  end if;

  select lower(pg_get_functiondef(
    'atlas.adjudicate_implementation_finding_self_api_v1(uuid,text,text,text,jsonb,text,uuid,uuid,uuid)'::regprocedure
  ))
  into v_def;

  if v_def not like '%implementation_practitioner_assigned_to_case_self_v1%'
     or v_def not like '%candidate_state=''promoted''%'
     or v_def not like '%canonicaldomainmutation%'
     or v_def like '%update atlas.implementation_reality_candidates%'
     or v_def like '%insert into atlas.organizations%'
     or v_def like '%insert into atlas.people%'
     or v_def like '%insert into atlas.organization_responsibilities%'
     or v_def like '%insert into atlas.company_work%' then
    raise exception 'Finding adjudication function violated its authority boundary.';
  end if;
end;
$validation$;

rollback;
