begin;

do $validation$
declare
  v_def text;
begin
  if to_regprocedure('atlas.reality_discovery_apply_option_eligibility_v1(jsonb,jsonb)') is null then
    raise exception 'Missing Reality Discovery option-eligibility helper.';
  end if;

  if to_regprocedure('public.reality_discovery_editable_answer_self_api_v1(text)') is null then
    raise exception 'Missing authenticated editable-answer RPC.';
  end if;

  if to_regprocedure('public.correct_reality_discovery_answer_self_api_v1(jsonb)') is null then
    raise exception 'Missing authenticated Reality Discovery correction RPC.';
  end if;

  if to_regprocedure('public.update_personal_atlas_identity_name_self_api_v1(text)') is null then
    raise exception 'Missing authenticated Personal Atlas identity-name correction RPC.';
  end if;

  if has_function_privilege('anon','public.reality_discovery_editable_answer_self_api_v1(text)','EXECUTE')
     or has_function_privilege('anon','public.correct_reality_discovery_answer_self_api_v1(jsonb)','EXECUTE')
     or has_function_privilege('anon','public.update_personal_atlas_identity_name_self_api_v1(text)','EXECUTE') then
    raise exception 'Anonymous role must not execute correction RPCs.';
  end if;

  if not has_function_privilege('authenticated','public.reality_discovery_editable_answer_self_api_v1(text)','EXECUTE')
     or not has_function_privilege('authenticated','public.correct_reality_discovery_answer_self_api_v1(jsonb)','EXECUTE')
     or not has_function_privilege('authenticated','public.update_personal_atlas_identity_name_self_api_v1(text)','EXECUTE') then
    raise exception 'Authenticated role must execute correction RPCs.';
  end if;

  select pg_get_functiondef('atlas.reality_discovery_question_set_for_encounter_self_api_v1(text,integer)'::regprocedure)
  into v_def;
  if position('v_household_shape_known' in v_def)=0
     or position('foundationalTopologyMayOrderFirstEstablishment' in v_def)=0 then
    raise exception 'First-establishment question set does not preserve topology-first encounter ordering.';
  end if;
  if position('reality_discovery_apply_option_eligibility_v1' in v_def)=0 then
    raise exception 'Question set does not apply context-sensitive option eligibility.';
  end if;

  select pg_get_functiondef('atlas.answer_reality_discovery_question_self_api_v1(jsonb)'::regprocedure)
  into v_def;
  if position('Answer option is not eligible in the current reality context.' in v_def)=0 then
    raise exception 'Normal Discovery answers are not validated against context-sensitive options.';
  end if;

  select pg_get_functiondef('atlas.correct_reality_discovery_answer_self_api_v1(jsonb)'::regprocedure)
  into v_def;
  if position('previousAnswer' in v_def)=0
     or position('reality_discovery_correction' in v_def)=0
     or position('upsert_personal_residence_arrangement_self_api_v1' in v_def)=0 then
    raise exception 'Discovery correction does not preserve append-only evidence and owning-domain promotion.';
  end if;

  select pg_get_functiondef('atlas.update_personal_atlas_identity_name_self_api_v1(text)'::regprocedure)
  into v_def;
  if position('update atlas.people' in lower(v_def))=0
     or position('update atlas.principals' in lower(v_def))=0
     or position('update atlas.household_members' in lower(v_def))=0 then
    raise exception 'Identity-name correction does not update the required identity projections.';
  end if;
end;
$validation$;

rollback;
