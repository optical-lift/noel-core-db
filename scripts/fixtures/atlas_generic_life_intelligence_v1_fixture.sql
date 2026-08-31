-- Atlas Generic Life Intelligence v1 fixture
-- Metadata-only verification for the first generic-life tranche. This fixture
-- does not require or mutate application data.

begin;

do $$
declare
  v_rls boolean;
  v_constraint text;
  v_policy_count integer;
  v_policy_qual text;
  v_trigger_count integer;
begin
  select c.relrowsecurity
    into v_rls
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'atlas'
    and c.relname = 'journal_event_subjects';

  if v_rls is distinct from true then
    raise exception 'journal_event_subjects must exist with RLS enabled';
  end if;

  select pg_get_constraintdef(c.oid)
    into v_constraint
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  join pg_namespace n on n.oid = t.relnamespace
  where n.nspname = 'atlas'
    and t.relname = 'journal_event_subjects'
    and c.conname = 'journal_event_subjects_identity_key';

  if v_constraint is null
     or v_constraint not like '%journal_event_id%subject_domain%subject_kind%subject_id%relation_kind%' then
    raise exception 'journal_event_subjects identity contract missing';
  end if;

  select count(*), max(p.qual)
    into v_policy_count, v_policy_qual
  from pg_policies p
  where p.schemaname = 'atlas'
    and p.tablename = 'journal_event_subjects'
    and p.policyname = 'journal_event_subjects_parent_event_read'
    and p.cmd = 'SELECT';

  if v_policy_count <> 1
     or coalesce(v_policy_qual, '') not like '%can_read_journal_event_v1%' then
    raise exception 'journal_event_subjects must inherit read custody from the parent Journal event';
  end if;

  select count(*)
    into v_trigger_count
  from pg_trigger tg
  join pg_class t on t.oid = tg.tgrelid
  join pg_namespace n on n.oid = t.relnamespace
  where n.nspname = 'atlas'
    and t.relname = 'journal_event_index'
    and tg.tgname = 'journal_event_index_mirror_generic_subjects_v1'
    and not tg.tgisinternal;

  if v_trigger_count <> 1 then
    raise exception 'legacy Journal pointer compatibility trigger missing';
  end if;
end
$$;

do $$
declare
  v_constraint text;
  v_policy_qual text;
  v_table text;
  v_function_exists boolean;
begin
  select pg_get_constraintdef(c.oid)
    into v_constraint
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  join pg_namespace n on n.oid = t.relnamespace
  where n.nspname = 'atlas'
    and t.relname = 'care_current_state'
    and c.conname = 'care_current_state_scoped_subject_key';

  if v_constraint is null
     or v_constraint not like '%scope_kind%scope_id%subject_domain%subject_kind%subject_id%' then
    raise exception 'care_current_state must key current state inside custody scope';
  end if;

  if exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'atlas'
      and t.relname = 'care_current_state'
      and c.conname = 'care_current_state_subject_key'
  ) then
    raise exception 'unscoped care_current_state subject key must be retired';
  end if;

  foreach v_table in array array[
    'care_observation_events',
    'care_current_state',
    'care_result_events'
  ] loop
    select p.qual
      into v_policy_qual
    from pg_policies p
    where p.schemaname = 'atlas'
      and p.tablename = v_table
      and p.policyname = v_table || '_scope_read'
      and p.cmd = 'SELECT';

    if v_policy_qual is null
       or v_policy_qual not like '%scope_kind%person%'
       or v_policy_qual not like '%auth.uid()%'
       or v_policy_qual not like '%household%'
       or v_policy_qual not like '%farm%' then
      raise exception '% read policy must preserve farm/household custody and add first-party person custody', v_table;
    end if;
  end loop;

  select to_regprocedure('atlas.record_person_condition_observation_api_v1(jsonb)') is not null
    into v_function_exists;

  if not v_function_exists then
    raise exception 'record_person_condition_observation_api_v1(jsonb) missing';
  end if;

  if not has_function_privilege(
      'authenticated',
      'atlas.record_person_condition_observation_api_v1(jsonb)',
      'EXECUTE'
    ) then
    raise exception 'authenticated must be able to execute person condition writer';
  end if;

  if has_function_privilege(
      'anon',
      'atlas.record_person_condition_observation_api_v1(jsonb)',
      'EXECUTE'
    ) then
    raise exception 'anon must not be able to execute person condition writer';
  end if;
end
$$;

rollback;
