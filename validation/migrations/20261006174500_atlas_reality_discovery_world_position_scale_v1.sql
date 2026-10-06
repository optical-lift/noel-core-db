begin;

do $validation$
declare
  v_def text;
begin
  if not exists(
    select 1
    from information_schema.columns
    where table_schema='atlas'
      and table_name='reality_discovery_orientation_events'
      and column_name='position_map'
      and data_type='jsonb'
  ) then
    raise exception 'Orientation evidence is missing POSITION storage.';
  end if;

  if exists(
    select 1
    from information_schema.columns
    where table_schema='atlas'
      and table_name='reality_discovery_orientation_events'
      and column_name='position_tags'
  ) then
    raise exception 'Superseded flat POSITION storage must not be introduced.';
  end if;

  if not exists(
    select 1
    from information_schema.columns
    where table_schema='atlas'
      and table_name='reality_discovery_orientation_events'
      and column_name='scale_map'
      and data_type='jsonb'
  ) then
    raise exception 'Orientation evidence is missing SCALE storage.';
  end if;

  if to_regprocedure('public.reality_discovery_orientation_profile_self_api_v1()') is null
     or to_regprocedure('public.set_reality_discovery_orientation_profile_self_api_v1(jsonb)') is null then
    raise exception 'Missing authenticated WORLD / POSITION / SCALE orientation RPCs.';
  end if;

  if has_function_privilege('anon','public.reality_discovery_orientation_profile_self_api_v1()','EXECUTE')
     or has_function_privilege('anon','public.set_reality_discovery_orientation_profile_self_api_v1(jsonb)','EXECUTE') then
    raise exception 'Anonymous role must not execute orientation profile RPCs.';
  end if;

  if not has_function_privilege('authenticated','public.reality_discovery_orientation_profile_self_api_v1()','EXECUTE')
     or not has_function_privilege('authenticated','public.set_reality_discovery_orientation_profile_self_api_v1(jsonb)','EXECUTE') then
    raise exception 'Authenticated role must execute orientation profile RPCs.';
  end if;

  select pg_get_functiondef('atlas.set_reality_discovery_orientation_profile_self_api_v1(jsonb)'::regprocedure)
  into v_def;
  if position('positionMap' in v_def)=0
     or position('position_map' in v_def)=0
     or position('v_position_world' in v_def)=0
     or position('jsonb_each' in v_def)=0
     or position('scaleMap' in v_def)=0
     or position('orientation_version' in v_def)=0
     or position('SCALE %=% is not coherent with WORLD / POSITION.' in v_def)=0 then
    raise exception 'Orientation profile writer does not enforce relational WORLD / POSITION / SCALE.';
  end if;

  select pg_get_functiondef('atlas.reality_discovery_ranked_questions_self_api_v1()'::regprocedure)
  into v_def;
  if position('orientationPositionPairs' in v_def)=0
     or position('orientationScaleKeys' in v_def)=0
     or position('orientationUsesWorldPositionScale' in v_def)=0
     or position('v_answer_count>=12' in replace(v_def,' ',''))=0 then
    raise exception 'Ranking does not use decaying WORLD / POSITION / SCALE orientation.';
  end if;

  if not exists(
    select 1 from atlas.reality_discovery_questions
    where question_key='hobbies.kind'
      and metadata->'orientationWorldDomains' ? 'hobbies'
  ) then
    raise exception 'Hobby-oriented first-day branch is missing.';
  end if;

  if not exists(
    select 1 from atlas.reality_discovery_questions
    where question_key='projects.kind'
      and metadata->'orientationWorldDomains' ? 'projects'
  ) then
    raise exception 'Project-oriented first-day branch is missing.';
  end if;

  if not exists(
    select 1 from atlas.reality_discovery_questions
    where question_key='money.scope'
      and metadata->'orientationWorldDomains' ? 'money'
  ) then
    raise exception 'Money-oriented first-day branch is missing.';
  end if;

  if exists(
    select 1 from atlas.reality_discovery_questions
    where metadata ? 'orientationCarryDomains'
  ) then
    raise exception 'Superseded carry-orientation metadata remains on the question catalog.';
  end if;
end;
$validation$;

rollback;
