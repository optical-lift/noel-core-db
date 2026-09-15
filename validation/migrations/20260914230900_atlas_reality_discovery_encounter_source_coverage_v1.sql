-- Package 1 postconditions: encounter admission and source coverage remain
-- independent policy layers over unresolved Reality Discovery.
-- Runs only against the disposable production-schema clone and rolls back.

begin;

do $$
declare
  v_first_day jsonb;
  v_manual jsonb;
  v_ranked jsonb;
  v_people jsonb;
  v_count integer;
begin
  perform set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
  perform set_config('request.jwt.claim.role','authenticated',true);

  select count(*)::integer into v_count
  from atlas.reality_discovery_encounter_admission;
  if v_count <> 16 then
    raise exception 'Expected all 16 current Discovery questions to have encounter policy; found %',v_count;
  end if;

  if not exists (
    select 1 from atlas.reality_discovery_encounter_admission
    where question_key='grounds.mowing_method'
      and admission_class='high_leverage'
      and first_day_disposition='admit'
  ) then
    raise exception 'Mowing method must remain high-leverage first-day discovery.';
  end if;

  if not exists (
    select 1 from atlas.reality_discovery_encounter_admission
    where question_key='equipment.riding_mower_identity'
      and admission_class='specialization'
      and first_day_disposition='defer'
  ) then
    raise exception 'Riding-mower identity must remain deferred specialization.';
  end if;

  v_first_day:=atlas.reality_discovery_next_question_for_encounter_self_api_v1('first_day');
  if coalesce((v_first_day->>'quiet')::boolean,false) is not true then
    raise exception 'First-day Discovery should be quiet when only deferred eligible reality remains: %',v_first_day;
  end if;
  if coalesce((v_first_day->>'eligibleUnansweredRemain')::boolean,false) is not true then
    raise exception 'First-day quiet must preserve unresolved eligible reality: %',v_first_day;
  end if;
  if coalesce((v_first_day->>'deferredCount')::integer,0) < 1 then
    raise exception 'First-day quiet must report deferred unresolved questions: %',v_first_day;
  end if;
  if v_first_day->'question' <> 'null'::jsonb then
    raise exception 'A high score must not bypass first-day encounter admission: %',v_first_day;
  end if;

  v_manual:=atlas.reality_discovery_next_question_for_encounter_self_api_v1('manual');
  if coalesce((v_manual->>'quiet')::boolean,true) is not false then
    raise exception 'Manual Discovery should retrieve broader unresolved reality: %',v_manual;
  end if;
  if v_manual#>>'{question,questionKey}' <> 'equipment.riding_mower_identity' then
    raise exception 'Manual Discovery should retrieve deferred mower identity; got %',v_manual;
  end if;
  if v_manual#>>'{question,admissionClass}' <> 'specialization' then
    raise exception 'Manual result must retain encounter-admission provenance: %',v_manual;
  end if;
  if coalesce((v_manual#>>'{question,score}')::integer,0) < 20000 then
    raise exception 'Fixture failed to prove score/admission independence: %',v_manual;
  end if;

  -- Re-open household shape as unresolved, then add a real connected/synced
  -- communication-capture source. Coverage must move the question later, while
  -- leaving it unanswered and present in the eligible ranked set.
  delete from atlas.reality_discovery_answer_events
  where owner_user_id='11111111-1111-4111-8111-111111111111'
    and question_key='household.people_shape';

  insert into atlas.connected_sources(
    id,custodian_user_id,provider_key,provider_account_key,display_label,
    authorization_state,granted_scopes,capabilities,last_sync_at,metadata
  ) values(
    '44444444-4444-4444-8444-444444444444',
    '11111111-1111-4111-8111-111111111111',
    'fixture-mail','fixture-account','Fixture Mail',
    'connected',array[]::text[],jsonb_build_object('communicationCapture',true),now(),'{}'::jsonb
  );

  v_ranked:=atlas.reality_discovery_ranked_questions_self_api_v1();
  select value into v_people
  from jsonb_array_elements(coalesce(v_ranked->'items','[]'::jsonb))
  where value->>'questionKey'='household.people_shape'
  limit 1;

  if v_people is null then
    raise exception 'Source coverage suppressed an unresolved household-shape question instead of merely reordering it: %',v_ranked;
  end if;
  if coalesce((v_people->>'sourceCoveragePenalty')::integer,0) <> 45 then
    raise exception 'Expected communication coverage penalty 45 without resolution; got %',v_people;
  end if;
  if not (coalesce(v_ranked#>'{context,sourceCoverage,keys}','[]'::jsonb) ? 'communication_capture') then
    raise exception 'Connected synced communication source did not establish coverage metadata: %',v_ranked;
  end if;
  if coalesce(v_ranked#>'{context,answers}','{}'::jsonb) ? 'household.people_shape' then
    raise exception 'Connecting a source incorrectly established a Discovery answer: %',v_ranked;
  end if;
  if coalesce((v_ranked#>>'{truthBoundary,sourceCoverageMayReorderButNeverSuppress}')::boolean,false) is not true
     or coalesce((v_ranked#>>'{truthBoundary,sourceCoverageDoesNotAnswerQuestions}')::boolean,false) is not true then
    raise exception 'Ranked result lost the source-coverage truth boundary: %',v_ranked;
  end if;

  if has_table_privilege('authenticated','atlas.reality_discovery_encounter_admission','select')
     or has_table_privilege('authenticated','atlas.reality_discovery_encounter_admission','insert')
     or has_table_privilege('authenticated','atlas.reality_discovery_encounter_admission','update')
     or has_table_privilege('authenticated','atlas.reality_discovery_encounter_admission','delete') then
    raise exception 'Authenticated role must not have direct encounter-policy table access.';
  end if;

  if has_function_privilege('authenticated','atlas.reality_discovery_ranked_questions_self_api_v1()','execute')
     or has_function_privilege('authenticated','atlas.reality_discovery_next_question_for_encounter_self_api_v1(text)','execute') then
    raise exception 'Internal ranking/admission helpers must remain service-only.';
  end if;
  if not has_function_privilege('service_role','atlas.reality_discovery_ranked_questions_self_api_v1()','execute')
     or not has_function_privilege('service_role','atlas.reality_discovery_next_question_for_encounter_self_api_v1(text)','execute') then
    raise exception 'Service role must retain governed internal helper execution.';
  end if;
  if not has_function_privilege('authenticated','atlas.reality_discovery_source_coverage_self_api_v1()','execute') then
    raise exception 'Signed-in Principal cannot read governed source coverage.';
  end if;
end;
$$;

rollback;