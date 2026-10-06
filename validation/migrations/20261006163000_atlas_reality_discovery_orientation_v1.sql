begin;

do $validation$
declare
  v_def text;
begin
  if to_regclass('atlas.reality_discovery_orientation_events') is null then
    raise exception 'Missing Reality Discovery orientation evidence table.';
  end if;

  if to_regprocedure('public.reality_discovery_orientation_self_api_v1()') is null
     or to_regprocedure('public.set_reality_discovery_orientation_self_api_v1(jsonb)') is null then
    raise exception 'Missing authenticated Reality Discovery orientation RPCs.';
  end if;

  if has_function_privilege('anon','public.reality_discovery_orientation_self_api_v1()','EXECUTE')
     or has_function_privilege('anon','public.set_reality_discovery_orientation_self_api_v1(jsonb)','EXECUTE') then
    raise exception 'Anonymous role must not execute orientation RPCs.';
  end if;

  if not has_function_privilege('authenticated','public.reality_discovery_orientation_self_api_v1()','EXECUTE')
     or not has_function_privilege('authenticated','public.set_reality_discovery_orientation_self_api_v1(jsonb)','EXECUTE') then
    raise exception 'Authenticated role must execute orientation RPCs.';
  end if;

  if not exists(
    select 1 from atlas.reality_discovery_questions
    where question_key='work.structure'
      and metadata->'orientationWorldDomains' ? 'business'
  ) then
    raise exception 'Business-oriented first-day question is missing.';
  end if;

  if not exists(
    select 1 from atlas.reality_discovery_questions
    where question_key='property.relationship'
      and metadata->'orientationWorldDomains' ? 'property'
  ) then
    raise exception 'Property-oriented first-day question is missing.';
  end if;

  if not exists(
    select 1 from atlas.reality_discovery_edges
    where question_key='business.count'
      and signal_key='work.structure'
      and effect_kind='require'
  ) then
    raise exception 'Business count lacks work-structure dependency.';
  end if;

  if not exists(
    select 1 from atlas.reality_discovery_edges
    where question_key='property.portfolio_size'
      and signal_key='property.relationship'
      and effect_kind='require'
  ) then
    raise exception 'Rental portfolio size lacks property relationship dependency.';
  end if;

  select pg_get_functiondef('atlas.reality_discovery_ranked_questions_self_api_v1()'::regprocedure)
  into v_def;
  if position('orientation_boost' in v_def)=0
     or position('orientationInfluenceDecaysWithEstablishedAnswers' in v_def)=0
     or position('v_answer_count>=12' in replace(v_def,' ',''))=0 then
    raise exception 'Ranking does not implement decaying cold-start orientation.';
  end if;

  select pg_get_functiondef('atlas.reality_discovery_question_set_for_encounter_self_api_v1(text,integer)'::regprocedure)
  into v_def;
  if position('v_orientation_captured' in v_def)=0
     or position('orientationMayChooseTheCurrentDiscoveryCluster' in v_def)=0 then
    raise exception 'First-day encounter does not allow orientation to choose the discovery domain.';
  end if;

  select pg_get_functiondef('atlas.reality_discovery_apply_option_eligibility_v1(jsonb,jsonb)'::regprocedure)
  into v_def;
  if position('partner + kids' in v_def)=0
     or position('transport.vehicle_count' in v_def)=0
     or (
       atlas.reality_discovery_apply_option_eligibility_v1(
         jsonb_build_object(
           'questionKey','household.people_shape',
           'options',jsonb_build_array(
             jsonb_build_object('key','just_me','label','just me'),
             jsonb_build_object('key','partner_children','label','partner + children')
           )
         ),
         '{}'::jsonb
       )#>>'{options,0,label}'
     ) <> 'me'
     or (
       atlas.reality_discovery_apply_option_eligibility_v1(
         jsonb_build_object(
           'questionKey','household.people_shape',
           'options',jsonb_build_array(
             jsonb_build_object('key','just_me','label','just me'),
             jsonb_build_object('key','partner_children','label','partner + children')
           )
         ),
         '{}'::jsonb
       )#>>'{options,1,label}'
     ) <> 'partner + kids' then
    raise exception 'Compact first-day option presentation is not enforced.';
  end if;
end;
$validation$;

rollback;
