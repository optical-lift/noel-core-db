-- Postconditions for Reality Discovery encounter admission.
-- Runs only in the governed disposable production-schema clone.

DO $$
DECLARE
  v_first_day jsonb;
  v_manual jsonb;
  v_public jsonb;
  v_count integer;
BEGIN
  perform set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
  perform set_config('request.jwt.claim.role','authenticated',true);

  select count(*)::integer into v_count
  from atlas.reality_discovery_encounter_admission;
  if v_count <> 16 then
    raise exception 'Expected all 16 current Discovery questions to have admission policy; found %',v_count;
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
    raise exception 'Riding-mower identity must be deferred specialization.';
  end if;

  v_first_day:=atlas.reality_discovery_next_question_for_encounter_self_api_v1('first_day');
  if coalesce((v_first_day->>'quiet')::boolean,false) is not true then
    raise exception 'First-day Discovery should be quiet when only deferred eligible reality remains: %',v_first_day;
  end if;
  if coalesce((v_first_day->>'eligibleUnansweredRemain')::boolean,false) is not true then
    raise exception 'First-day quiet must preserve the fact that eligible unanswered reality remains: %',v_first_day;
  end if;
  if coalesce((v_first_day->>'deferredCount')::integer,0) < 1 then
    raise exception 'First-day quiet must report at least one deferred question: %',v_first_day;
  end if;
  if v_first_day->'question' <> 'null'::jsonb then
    raise exception 'First-day encounter must not leak a deferred question merely because it has the highest score: %',v_first_day;
  end if;

  v_manual:=atlas.reality_discovery_next_question_for_encounter_self_api_v1('manual');
  if coalesce((v_manual->>'quiet')::boolean,true) is not false then
    raise exception 'Manual Discovery should retrieve broader unresolved reality: %',v_manual;
  end if;
  if v_manual#>>'{question,questionKey}' <> 'equipment.riding_mower_identity' then
    raise exception 'Manual Discovery should retrieve deferred mower identity; got %',v_manual;
  end if;
  if v_manual#>>'{question,admissionClass}' <> 'specialization' then
    raise exception 'Manual result must retain admission provenance: %',v_manual;
  end if;
  if coalesce((v_manual#>>'{question,score}')::integer,0) < 20000 then
    raise exception 'Fixture failed to prove ranking independence; mower specialization score was not deliberately dominant: %',v_manual;
  end if;

  -- Existing public/client contract remains first-day by default when no active
  -- session establishes a broader encounter kind.
  v_public:=atlas.reality_discovery_next_question_self_api_v1();
  if coalesce((v_public->>'quiet')::boolean,false) is not true
     or coalesce((v_public->>'eligibleUnansweredRemain')::boolean,false) is not true then
    raise exception 'Existing next-question contract did not preserve first-day admission semantics: %',v_public;
  end if;

  if has_table_privilege('authenticated','atlas.reality_discovery_encounter_admission','select')
     or has_table_privilege('authenticated','atlas.reality_discovery_encounter_admission','insert')
     or has_table_privilege('authenticated','atlas.reality_discovery_encounter_admission','update')
     or has_table_privilege('authenticated','atlas.reality_discovery_encounter_admission','delete') then
    raise exception 'Authenticated role must not have direct admission-policy table access.';
  end if;

  if has_function_privilege('authenticated','atlas.reality_discovery_ranked_questions_self_api_v1()','execute')
     or has_function_privilege('authenticated','atlas.reality_discovery_next_question_for_encounter_self_api_v1(text)','execute') then
    raise exception 'Internal ranking/admission helpers must remain service-only.';
  end if;

  if not has_function_privilege('service_role','atlas.reality_discovery_ranked_questions_self_api_v1()','execute')
     or not has_function_privilege('service_role','atlas.reality_discovery_next_question_for_encounter_self_api_v1(text)','execute') then
    raise exception 'Service role must retain governed internal helper execution.';
  end if;
END;
$$;
