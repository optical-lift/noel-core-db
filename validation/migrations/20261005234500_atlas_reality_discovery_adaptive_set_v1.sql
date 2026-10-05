begin;

do $validation$
declare
  v_def text;
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

  -- The production-schema clone intentionally restores schema, not catalog data.
  -- Cluster metadata is a data migration over the live Discovery question catalog,
  -- so this clone proof verifies the executable set contract rather than asserting
  -- rows that are deliberately absent from the schema-only clone.
  select pg_get_functiondef('atlas.reality_discovery_question_set_for_encounter_self_api_v1(text,integer)'::regprocedure)
  into v_def;
  if position('encounterCluster' in v_def)=0 or position('encounterClusterLabel' in v_def)=0 then
    raise exception 'Adaptive set function does not consume encounter cluster metadata.';
  end if;
  if position('setRecomputesAfterEveryAnswer' in v_def)=0 then
    raise exception 'Adaptive set function does not preserve recomputation truth boundary.';
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
