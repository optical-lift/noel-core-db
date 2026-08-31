-- Atlas person condition observation-only fixture
-- Verifies that an unregistered first-party condition can remain evidence only.

begin;

do $$
declare
  v_user_id uuid := gen_random_uuid();
  v_result jsonb;
  v_count integer;
begin
  insert into auth.users(id) values (v_user_id);
  perform set_config('request.jwt.claim.sub', v_user_id::text, true);

  v_result := atlas.record_person_condition_observation_api_v1(jsonb_build_object(
    'subjectDomain','body',
    'subjectKind','body_region',
    'subjectId','left_hip',
    'conditionState','tight_after_run',
    'sourceKey','fixture-observation-only-left-hip',
    'observedAt','2026-09-01T08:30:00-05:00',
    'note','Left hip felt tight afterward.',
    'metadata',jsonb_build_object('causeEstablished',false)
  ));

  if v_result->>'disposition' <> 'observe' then
    raise exception 'Unregistered first-party condition must default to neutral observe, got %', v_result->>'disposition';
  end if;
  if coalesce((v_result->>'inferredFromClock')::boolean,true) then
    raise exception 'Person condition observation must not be inferred from Clock';
  end if;

  select count(*)
  into v_count
  from atlas.care_current_state s
  where s.scope_kind='person'
    and s.scope_id=v_user_id
    and s.subject_domain='body'
    and s.subject_kind='body_region'
    and s.subject_id='left_hip'
    and s.condition_state='tight_after_run'
    and s.disposition='observe';

  if v_count <> 1 then
    raise exception 'Current state must preserve observation-only disposition';
  end if;

  -- Exact retry remains idempotent and does not promote the observation.
  v_result := atlas.record_person_condition_observation_api_v1(jsonb_build_object(
    'subjectDomain','body',
    'subjectKind','body_region',
    'subjectId','left_hip',
    'conditionState','tight_after_run',
    'sourceKey','fixture-observation-only-left-hip',
    'observedAt','2026-09-01T08:30:00-05:00',
    'note','Left hip felt tight afterward.',
    'metadata',jsonb_build_object('causeEstablished',false)
  ));

  if v_result->>'disposition' <> 'observe' then
    raise exception 'Exact retry must preserve observe disposition';
  end if;
end
$$;

rollback;
