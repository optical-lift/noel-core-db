-- Atlas person Goal claim_count v1 regression fixture
-- Proves zero / partial / satisfied count reduction, correction supersession,
-- aggregate provenance, and unchanged claim_threshold behavior. Everything rolls back.

begin;

do $$
declare
  v_user_id uuid := gen_random_uuid();
  v_count_requirement jsonb;
  v_count_authorization jsonb;
  v_count_packet jsonb;
  v_count_result jsonb;
  v_book_receipt jsonb;
  v_first_book_claim_id uuid;
  v_threshold_requirement jsonb;
  v_threshold_authorization jsonb;
  v_threshold_packet jsonb;
  v_threshold_result jsonb;
  i integer;
begin
  insert into auth.users(id) values (v_user_id);
  perform set_config('request.jwt.claim.sub',v_user_id::text,true);

  v_count_requirement := jsonb_build_object(
    'requirementKey','complete_12_books',
    'requirementKind','claim_count',
    'phase','realize',
    'required',true,
    'evidenceSelector',jsonb_build_object(
      'subject',jsonb_build_object(
        'domain','learning',
        'kind','book_completion',
        'id','reading:12-books'
      ),
      'claimType','book_completed',
      'lifecycleStates',jsonb_build_array('observed'),
      'authorityKinds',jsonb_build_array('person_reported_observation','person_correction')
    ),
    'criterion',jsonb_build_object('operator','>=','value',12)
  );

  v_count_authorization := atlas.record_person_claim_evidence_api_v1(jsonb_build_object(
    'sourceKey','fixture-reading-12-books-requirement',
    'subject',jsonb_build_object(
      'domain','learning',
      'kind','reading_goal',
      'id','reading:12-books'
    ),
    'evidence',jsonb_build_object(
      'kind','human_expression',
      'observedAt','2026-08-31T18:00:00-05:00',
      'value',jsonb_build_object('rawLanguage','I accept completing 12 books as this goal requirement.'),
      'provenance',jsonb_build_object('capture','fixture')
    ),
    'claim',jsonb_build_object(
      'claimType','goal_requirement',
      'lifecycleState','accepted',
      'value',v_count_requirement
    )
  ));

  v_count_packet := jsonb_build_object(
    'contractVersion','life_goal_packet_v1',
    'scope',jsonb_build_object('kind','person','id',v_user_id),
    'subject',jsonb_build_object('domain','learning','kind','reading_goal','id','reading:12-books'),
    'requirements',jsonb_build_array(
      v_count_requirement || jsonb_build_object(
        'authorization',jsonb_build_object(
          'basis','person_accepted_goal_requirement_claim',
          'claimId',v_count_authorization->>'claimId',
          'evidenceId',v_count_authorization->>'evidenceId'
        )
      )
    )
  );

  -- Zero qualifying current Claims is unmet, not unknown.
  v_count_result := atlas.resolve_person_goal_requirement_results_v1(v_user_id,v_count_packet);
  if v_count_result->0->>'state'<>'unmet'
     or (v_count_result->0->'detail'->>'observedCount')::integer<>0
     or (v_count_result->0->'detail'->>'targetCount')::numeric<>12
     or v_count_result->0->'detail'->>'operator'<>'>='
     or (v_count_result->0->'source'->>'matchingClaimCount')::integer<>0 then
    raise exception 'claim_count zero-state regression failed: %',v_count_result;
  end if;
  if (v_count_result->0->'source') ? 'claimId'
     or (v_count_result->0->'source') ? 'evidenceId' then
    raise exception 'claim_count aggregate provenance falsely selected one Claim/Evidence witness: %',v_count_result;
  end if;

  for i in 1..3 loop
    v_book_receipt := atlas.record_person_claim_evidence_api_v1(jsonb_build_object(
      'sourceKey','fixture-reading-book-' || i::text,
      'subject',jsonb_build_object('domain','learning','kind','book_completion','id','reading:12-books'),
      'evidence',jsonb_build_object(
        'kind','completion_observation',
        'observedAt','2026-08-31T18:15:00-05:00',
        'value',jsonb_build_object('bookKey','fixture-book-' || i::text)
      ),
      'claim',jsonb_build_object(
        'claimType','book_completed',
        'lifecycleState','observed',
        'value',jsonb_build_object('bookKey','fixture-book-' || i::text)
      )
    ));
    if i=1 then v_first_book_claim_id := (v_book_receipt->>'claimId')::uuid; end if;
  end loop;

  v_count_result := atlas.resolve_person_goal_requirement_results_v1(v_user_id,v_count_packet);
  if v_count_result->0->>'state'<>'partial'
     or (v_count_result->0->'detail'->>'observedCount')::integer<>3
     or (v_count_result->0->'source'->>'matchingClaimCount')::integer<>3 then
    raise exception 'claim_count partial-state regression failed: %',v_count_result;
  end if;

  -- A correction supersedes one old Claim and replaces it with one current Claim;
  -- the aggregate must remain three rather than double-counting historical truth.
  perform atlas.record_person_claim_evidence_api_v1(jsonb_build_object(
    'sourceKey','fixture-reading-book-1-correction',
    'subject',jsonb_build_object('domain','learning','kind','book_completion','id','reading:12-books'),
    'evidence',jsonb_build_object(
      'kind','human_correction',
      'observedAt','2026-08-31T18:30:00-05:00',
      'value',jsonb_build_object('bookKey','fixture-book-1-corrected')
    ),
    'claim',jsonb_build_object(
      'claimType','book_completed',
      'lifecycleState','observed',
      'supersedesClaimId',v_first_book_claim_id,
      'value',jsonb_build_object('bookKey','fixture-book-1-corrected')
    )
  ));

  v_count_result := atlas.resolve_person_goal_requirement_results_v1(v_user_id,v_count_packet);
  if v_count_result->0->>'state'<>'partial'
     or (v_count_result->0->'detail'->>'observedCount')::integer<>3 then
    raise exception 'claim_count correction/supersession regression failed: %',v_count_result;
  end if;

  for i in 4..12 loop
    perform atlas.record_person_claim_evidence_api_v1(jsonb_build_object(
      'sourceKey','fixture-reading-book-' || i::text,
      'subject',jsonb_build_object('domain','learning','kind','book_completion','id','reading:12-books'),
      'evidence',jsonb_build_object(
        'kind','completion_observation',
        'observedAt','2026-08-31T18:45:00-05:00',
        'value',jsonb_build_object('bookKey','fixture-book-' || i::text)
      ),
      'claim',jsonb_build_object(
        'claimType','book_completed',
        'lifecycleState','observed',
        'value',jsonb_build_object('bookKey','fixture-book-' || i::text)
      )
    ));
  end loop;

  v_count_result := atlas.resolve_person_goal_requirement_results_v1(v_user_id,v_count_packet);
  if v_count_result->0->>'state'<>'satisfied'
     or (v_count_result->0->'detail'->>'observedCount')::integer<>12
     or (v_count_result->0->'source'->>'matchingClaimCount')::integer<>12 then
    raise exception 'claim_count satisfied-state regression failed: %',v_count_result;
  end if;

  -- The pre-existing claim_threshold reducer retains path + optional exact unit
  -- comparison semantics and does not inherit count behavior.
  v_threshold_requirement := jsonb_build_object(
    'requirementKey','run_5_km',
    'requirementKind','claim_threshold',
    'phase','realize',
    'required',true,
    'evidenceSelector',jsonb_build_object(
      'subject',jsonb_build_object('domain','training','kind','activity','id','fixture-5k-progress'),
      'claimType','run_distance',
      'lifecycleStates',jsonb_build_array('observed'),
      'authorityKinds',jsonb_build_array('person_reported_observation','person_correction')
    ),
    'criterion',jsonb_build_object(
      'path',jsonb_build_array('distance'),
      'operator','>=',
      'value',5,
      'unit','km',
      'unitPath',jsonb_build_array('unit')
    )
  );

  v_threshold_authorization := atlas.record_person_claim_evidence_api_v1(jsonb_build_object(
    'sourceKey','fixture-5k-threshold-requirement',
    'subject',jsonb_build_object('domain','training','kind','training_goal','id','fixture-5k'),
    'evidence',jsonb_build_object(
      'kind','human_expression',
      'observedAt','2026-08-31T19:00:00-05:00',
      'value',jsonb_build_object('rawLanguage','I accept completing five kilometers as the goal requirement.')
    ),
    'claim',jsonb_build_object(
      'claimType','goal_requirement',
      'lifecycleState','accepted',
      'value',v_threshold_requirement
    )
  ));

  perform atlas.record_person_claim_evidence_api_v1(jsonb_build_object(
    'sourceKey','fixture-5k-run-4km',
    'subject',jsonb_build_object('domain','training','kind','activity','id','fixture-5k-progress'),
    'evidence',jsonb_build_object(
      'kind','activity_observation',
      'observedAt','2026-08-31T19:15:00-05:00',
      'value',jsonb_build_object('distance',4,'unit','km')
    ),
    'claim',jsonb_build_object(
      'claimType','run_distance',
      'lifecycleState','observed',
      'value',jsonb_build_object('distance',4,'unit','km')
    )
  ));

  v_threshold_packet := jsonb_build_object(
    'contractVersion','life_goal_packet_v1',
    'scope',jsonb_build_object('kind','person','id',v_user_id),
    'subject',jsonb_build_object('domain','training','kind','training_goal','id','fixture-5k'),
    'requirements',jsonb_build_array(
      v_threshold_requirement || jsonb_build_object(
        'authorization',jsonb_build_object(
          'basis','person_accepted_goal_requirement_claim',
          'claimId',v_threshold_authorization->>'claimId',
          'evidenceId',v_threshold_authorization->>'evidenceId'
        )
      )
    )
  );

  v_threshold_result := atlas.resolve_person_goal_requirement_results_v1(v_user_id,v_threshold_packet);
  if v_threshold_result->0->>'state'<>'unmet'
     or (v_threshold_result->0->'detail'->>'observedValue')::numeric<>4
     or (v_threshold_result->0->'detail'->>'threshold')::numeric<>5
     or v_threshold_result->0->'detail'->>'unit'<>'km'
     or not ((v_threshold_result->0->'source') ? 'claimId')
     or not ((v_threshold_result->0->'source') ? 'evidenceId') then
    raise exception 'claim_threshold compatibility regression failed: %',v_threshold_result;
  end if;
end
$$;

rollback;
