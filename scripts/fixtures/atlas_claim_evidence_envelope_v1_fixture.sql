-- Atlas universal Claim / Evidence envelope v1 fixture
-- Proves accepted requirement, observed run, correction/supersession, idempotency,
-- and first-party authority boundaries. Everything rolls back.

begin;

do $$
declare
  v_user_id uuid := gen_random_uuid();
  v_requirement jsonb;
  v_run jsonb;
  v_run_correction jsonb;
  v_replay jsonb;
  v_state jsonb;
  v_run_claim_id uuid;
  v_corrected_claim_id uuid;
  v_count integer;
  v_rejected boolean := false;
begin
  insert into auth.users(id) values (v_user_id);
  perform set_config('request.jwt.claim.sub', v_user_id::text, true);

  -- The person explicitly accepts a requirement. Atlas may preserve that
  -- acceptance because the authority came from the person; it may not manufacture
  -- the requirement simply because a 5K Goal exists.
  v_requirement := atlas.record_person_claim_evidence_api_v1(jsonb_build_object(
    'sourceKey','fixture-5k-accepted-run-requirement',
    'subject',jsonb_build_object(
      'domain','training',
      'kind','goal_requirement',
      'id','fixture-5k:run-exposure'
    ),
    'evidence',jsonb_build_object(
      'kind','human_expression',
      'observedAt','2026-09-01T07:45:00-05:00',
      'value',jsonb_build_object(
        'rawLanguage','I accept that training runs are part of preparing for this 5K.'
      ),
      'provenance',jsonb_build_object('capture','fixture')
    ),
    'claim',jsonb_build_object(
      'claimType','goal_requirement',
      'lifecycleState','accepted',
      'value',jsonb_build_object(
        'requirementKey','training-run-exposure',
        'requirementKind','activity_evidence',
        'phase','progress',
        'required',true,
        'goalSubject',jsonb_build_object('domain','training','kind','training_goal','id','fixture-5k')
      )
    )
  ));

  if v_requirement->>'lifecycleState' <> 'accepted'
     or v_requirement->>'authorityKind' <> 'person_acceptance'
     or coalesce((v_requirement->'truthBoundary'->>'doesNotCreateClockPlacement')::boolean,false) is distinct from true then
    raise exception 'Accepted requirement did not preserve person authority / Clock boundary';
  end if;

  -- A real run is evidence with event time distinct from learned time. It is an
  -- observation, not proof that the 5K caused any later body condition.
  v_run := atlas.record_person_claim_evidence_api_v1(jsonb_build_object(
    'sourceKey','fixture-run-2026-09-01',
    'subject',jsonb_build_object(
      'domain','training',
      'kind','activity',
      'id','fixture-run-1'
    ),
    'evidence',jsonb_build_object(
      'kind','activity_observation',
      'observedAt','2026-09-01T08:00:00-05:00',
      'value',jsonb_build_object(
        'activityType','run',
        'distance',2.0,
        'distanceUnit','mile',
        'rawLanguage','Ran 2 miles this morning.'
      )
    ),
    'claim',jsonb_build_object(
      'claimType','activity_observation',
      'lifecycleState','observed',
      'value',jsonb_build_object(
        'activityType','run',
        'distance',2.0,
        'distanceUnit','mile'
      )
    )
  ));
  v_run_claim_id := (v_run->>'claimId')::uuid;

  if v_run->>'authorityKind' <> 'person_reported_observation' then
    raise exception 'Run observation widened first-party authority';
  end if;

  -- Exact retry is idempotent and preserves identity.
  v_replay := atlas.record_person_claim_evidence_api_v1(jsonb_build_object(
    'sourceKey','fixture-run-2026-09-01',
    'subject',jsonb_build_object('domain','training','kind','activity','id','fixture-run-1'),
    'evidence',jsonb_build_object(
      'kind','activity_observation',
      'observedAt','2026-09-01T08:00:00-05:00',
      'value',jsonb_build_object('activityType','run','distance',2.0,'distanceUnit','mile','rawLanguage','Ran 2 miles this morning.')
    ),
    'claim',jsonb_build_object(
      'claimType','activity_observation',
      'lifecycleState','observed',
      'value',jsonb_build_object('activityType','run','distance',2.0,'distanceUnit','mile')
    )
  ));

  if coalesce((v_replay->>'created')::boolean,true)
     or (v_replay->>'claimId')::uuid is distinct from v_run_claim_id then
    raise exception 'Exact run replay was not idempotent';
  end if;

  -- A correction preserves the original evidence and claim, then marks only the
  -- old claim superseded. It does not rewrite history.
  v_run_correction := atlas.record_person_claim_evidence_api_v1(jsonb_build_object(
    'sourceKey','fixture-run-2026-09-01-correction',
    'subject',jsonb_build_object('domain','training','kind','activity','id','fixture-run-1'),
    'evidence',jsonb_build_object(
      'kind','human_correction',
      'observedAt','2026-09-01T08:20:00-05:00',
      'value',jsonb_build_object(
        'rawLanguage','Correction: my watch says 2.1 miles.',
        'correctedDistance',2.1,
        'distanceUnit','mile'
      )
    ),
    'claim',jsonb_build_object(
      'claimType','activity_observation',
      'lifecycleState','observed',
      'supersedesClaimId',v_run_claim_id,
      'value',jsonb_build_object('activityType','run','distance',2.1,'distanceUnit','mile')
    )
  ));
  v_corrected_claim_id := (v_run_correction->>'claimId')::uuid;

  if v_run_correction->>'authorityKind' <> 'person_correction' then
    raise exception 'Correction did not use explicit person correction authority';
  end if;

  select count(*) into v_count
  from atlas.claim_records c
  where c.id=v_run_claim_id
    and c.lifecycle_state='superseded'
    and c.superseded_at is not null;
  if v_count <> 1 then raise exception 'Original run claim was not superseded'; end if;

  select count(*) into v_count
  from atlas.evidence_records e
  where e.scope_kind='person' and e.scope_id=v_user_id
    and e.source_key in ('fixture-run-2026-09-01','fixture-run-2026-09-01-correction');
  if v_count <> 2 then raise exception 'Correction rewrote or lost original evidence'; end if;

  select count(*) into v_count
  from atlas.claim_evidence_links l
  where l.claim_id=v_corrected_claim_id and l.relation_kind='corrects';
  if v_count <> 1 then raise exception 'Correction evidence relation missing'; end if;

  -- A first-party caller cannot label its own statement as an engine inference.
  begin
    perform atlas.record_person_claim_evidence_api_v1(jsonb_build_object(
      'sourceKey','fixture-illegal-inference',
      'subject',jsonb_build_object('domain','training','kind','activity','id','fixture-inference'),
      'evidence',jsonb_build_object('kind','human_expression','value',jsonb_build_object('text','maybe')),
      'claim',jsonb_build_object('claimType','causal_claim','lifecycleState','inferred','value',jsonb_build_object('cause','unknown'))
    ));
  exception when sqlstate '22023' then
    v_rejected := true;
  end;
  if not v_rejected then raise exception 'First-party capture was allowed to author inferred state'; end if;

  v_state := atlas.person_claim_evidence_state_api_v1();
  if jsonb_array_length(v_state->'evidenceRecords') <> 3 then
    raise exception 'Expected accepted requirement + run + correction evidence records';
  end if;
  if jsonb_array_length(v_state->'claims') <> 3 then
    raise exception 'Expected accepted requirement + full run claim history';
  end if;
  if jsonb_array_length(v_state->'currentClaims') <> 2 then
    raise exception 'Current claim projection did not exclude superseded run claim';
  end if;
  if coalesce((v_state->'truthBoundary'->>'clockPlacementAuthority')::boolean,true)
     or coalesce((v_state->'truthBoundary'->>'practitionerAccessGranted')::boolean,true) then
    raise exception 'Claim/Evidence read membrane widened Clock or practitioner authority';
  end if;
end
$$;

rollback;
