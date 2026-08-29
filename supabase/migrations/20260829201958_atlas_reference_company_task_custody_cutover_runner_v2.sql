create or replace function atlas.run_reference_company_task_custody_cutover_v1(p_source_revision text default null)
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog, atlas
as $function$
declare
  v_scenario atlas.reference_company_scenarios%rowtype;
  v_farm atlas.farms%rowtype;
  v_org_id uuid;
  v_user_id uuid;
  v_membership_id uuid;
  v_task_id uuid;
  v_placement_id uuid;
  v_run_id uuid;
  v_run_token text;
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_due date := ((now() at time zone 'America/Chicago')::date)-3;
  v_service_date date := ((now() at time zone 'America/Chicago')::date)-1;
  v_due_after date;
  v_status_after text;
  v_placement_state text;
  v_placement_date date;
  v_visibility_reason text;
  v_reschedule_count integer := 0;
  v_roll_result jsonb := '{}'::jsonb;
  v_assertions jsonb := '[]'::jsonb;
  v_fixture_completed boolean := false;
  v_all_passed boolean := false;
  v_error text;
begin
  select * into v_scenario
  from atlas.reference_company_scenarios
  where stable_key='task_custody_cutover_v1' and active;
  if v_scenario.id is null then
    raise exception 'Reference company task custody scenario is unavailable.' using errcode='P0002';
  end if;

  select * into v_farm from atlas.farms where stable_key='atlas_reference_farm';
  if v_farm.id is null or not atlas.is_system_fixture_farm_v1(v_farm.id) then
    raise exception 'Atlas Reference Farm isolation contract is unavailable.' using errcode='23514';
  end if;
  v_org_id := v_farm.organization_id;

  select fm.user_id into v_user_id
  from atlas.farm_memberships fm
  where fm.active=true
  order by fm.created_at,fm.id
  limit 1;
  if v_user_id is null then
    raise exception 'Reference custody scenario requires one existing auth-backed Atlas membership.' using errcode='23514';
  end if;

  v_run_token := 'reference:task_custody_cutover_v1:'||replace(gen_random_uuid()::text,'-','');
  insert into atlas.reference_company_runs(scenario_id,farm_id,run_token,run_mode,status,source_revision,metadata)
  values(v_scenario.id,v_farm.id,v_run_token,'transactional','running',p_source_revision,
    jsonb_build_object('fixtureVersion',v_scenario.fixture_version,'systemFixture',true,'runner','run_reference_company_task_custody_cutover_v1'))
  returning id into v_run_id;

  begin
    insert into atlas.farm_memberships(user_id,farm_id,role,worker_key,active,permissions)
    values(v_user_id,v_farm.id,'farm_hand','reference_custody_worker_'||replace(v_run_id::text,'-',''),true,
      jsonb_build_object('system_fixture',true,'reference_fixture_membership',true,'reference_run_id',v_run_id))
    returning id into v_membership_id;

    insert into atlas.tasks(
      organization_id,farm_id,title,status,due_date,visibility_scope,assigned_membership_id,
      task_scope,origin_kind,work_lane,commitment_kind,metadata
    ) values(
      v_org_id,v_farm.id,'Reference overdue obligation','open',v_due,'assigned_worker',v_membership_id,
      'farm_operation','generated','required','hard_date',
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true,'custody_test',true)
    ) returning id into v_task_id;

    insert into atlas.worker_day_task_placements(
      organization_id,farm_id,membership_id,task_id,service_date,day_window,sort_order,placement_source,state,placement_reason
    ) values(
      v_org_id,v_farm.id,v_membership_id,v_task_id,v_service_date,'morning',100,'atlas','placed',
      'Synthetic elapsed placement for task-custody conformance test.'
    ) returning id into v_placement_id;

    v_roll_result := atlas.roll_expired_worker_tasks_v1(v_farm.id,v_membership_id,v_today);

    select due_date,status into v_due_after,v_status_after from atlas.tasks where id=v_task_id;
    select state,service_date into v_placement_state,v_placement_date
      from atlas.worker_day_task_placements where id=v_placement_id;
    select visibility_reason into v_visibility_reason
      from atlas.worker_day_visibility_floor_v1(v_farm.id,v_membership_id,v_today)
      where task_id=v_task_id
      limit 1;
    select count(*) into v_reschedule_count
      from atlas.task_transitions
      where task_id=v_task_id and transition='rescheduled';

    v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
      'key','overdue_due_date_preserved','passed',v_due_after=v_due,
      'expected',v_due,'actual',v_due_after));
    v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
      'key','unresolved_task_remains_open','passed',v_status_after='open',
      'expected','open','actual',v_status_after));
    v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
      'key','elapsed_placement_returns_without_date_rewrite','passed',v_placement_state='returned_to_atlas' and v_placement_date=v_service_date,
      'expected',jsonb_build_object('state','returned_to_atlas','serviceDate',v_service_date),
      'actual',jsonb_build_object('state',v_placement_state,'serviceDate',v_placement_date)));
    v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
      'key','overdue_visibility_survives_midnight','passed',v_visibility_reason='assigned_overdue',
      'expected','assigned_overdue','actual',v_visibility_reason));
    v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
      'key','generic_rollover_emits_no_reschedule_transition','passed',v_reschedule_count=0,
      'expected',0,'actual',v_reschedule_count));

    raise exception 'REFERENCE_FIXTURE_ROLLBACK' using errcode='P9001';
  exception
    when sqlstate 'P9001' then
      v_fixture_completed := true;
    when others then
      get stacked diagnostics v_error=message_text;
      v_fixture_completed := false;
  end;

  if not v_fixture_completed then
    update atlas.reference_company_runs
    set status='failed',completed_at=now(),error_text=v_error,
        result=jsonb_build_object('fixtureRolledBack',true,'runnerError',v_error)
    where id=v_run_id;
    return jsonb_build_object('contractVersion','run_reference_company_task_custody_cutover_v1','runId',v_run_id,
      'scenarioKey','task_custody_cutover_v1','status','failed','error',v_error,'fixtureRolledBack',true);
  end if;

  insert into atlas.reference_company_assertions(run_id,assertion_key,passed,expected,actual,detail)
  select v_run_id,x->>'key',coalesce((x->>'passed')::boolean,false),
         jsonb_build_object('value',x->'expected'),jsonb_build_object('value',x->'actual'),null
  from jsonb_array_elements(v_assertions) x;

  select coalesce(bool_and(passed),false) into v_all_passed
  from atlas.reference_company_assertions where run_id=v_run_id;

  update atlas.reference_company_runs
  set status=case when v_all_passed then 'passed' else 'failed' end,
      completed_at=now(),
      result=jsonb_build_object('fixtureRolledBack',true,'rollResult',v_roll_result,'assertions',v_assertions,'allPassed',v_all_passed),
      error_text=case when v_all_passed then null else 'One or more task custody assertions failed.' end
  where id=v_run_id;

  return jsonb_build_object(
    'contractVersion','run_reference_company_task_custody_cutover_v1','runId',v_run_id,
    'scenarioKey','task_custody_cutover_v1','status',case when v_all_passed then 'passed' else 'failed' end,
    'fixtureRolledBack',true,'assertions',v_assertions
  );
end;
$function$;

revoke all on function atlas.run_reference_company_task_custody_cutover_v1(text) from public, anon, authenticated;