begin;

do $validation$
declare
  v_def text;
  v_count integer;
begin
  if to_regprocedure('atlas.reality_discovery_question_set_for_encounter_self_api_v1(text,integer)') is null then
    raise exception 'Missing internal adaptive Reality Discovery question-set function.';
  end if;

  if to_regprocedure('atlas.reality_discovery_question_set_self_api_v1(integer)') is null then
    raise exception 'Missing authenticated adaptive Reality Discovery question-set function.';
  end if;

  if to_regprocedure('public.reality_discovery_question_set_self_api_v1(integer)') is null then
    raise exception 'Missing public RPC wrapper for adaptive Reality Discovery question sets.';
  end if;

  if has_function_privilege('anon','public.reality_discovery_question_set_self_api_v1(integer)','EXECUTE') then
    raise exception 'Anonymous role must not execute adaptive Reality Discovery question-set RPC.';
  end if;

  if not has_function_privilege('authenticated','public.reality_discovery_question_set_self_api_v1(integer)','EXECUTE') then
    raise exception 'Authenticated role must execute adaptive Reality Discovery question-set RPC.';
  end if;

  select count(*) into v_count
  from atlas.reality_discovery_questions
  where question_key in ('household.people_shape','home.tenure','home.major_repairs')
    and metadata->>'encounterCluster'='you_home'
    and metadata->>'encounterClusterLabel'='YOU + HOME';
  if v_count<>3 then
    raise exception 'YOU + HOME cluster metadata is incomplete.';
  end if;

  select pg_get_functiondef('atlas.answer_reality_discovery_question_self_api_v1(jsonb)'::regprocedure)
  into v_def;
  if position('reality_discovery_question_set_self_api_v1' in v_def)=0 then
    raise exception 'Discovery answer command does not validate against the current adaptive set.';
  end if;
  if position('current eligible encounter set' in v_def)=0 then
    raise exception 'Discovery answer command does not preserve stale-set rejection.';
  end if;
end;
$validation$;

rollback;
