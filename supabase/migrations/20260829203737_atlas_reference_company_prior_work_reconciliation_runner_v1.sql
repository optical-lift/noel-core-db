insert into atlas.reference_company_scenarios(
  stable_key,domain,title,purpose,run_mode,fixture_version,preconditions,expected_invariants,active,metadata
) values(
  'prior_work_reconciliation_v1','worker_day','Prior Worker Day reconciliation',
  'Prove first-open reconciliation is synthesized only from the immediately preceding Worker Day and that each explicit worker answer has bounded task-truth effects.',
  'transactional',1,
  jsonb_build_object('systemFixtureFarm','atlas_reference_farm','requiresExistingAuthUser',true),
  jsonb_build_array(
    'five_prior_placements_create_five_first_open_cues',
    'finished_closes_task',
    'partial_preserves_open_task_and_due_date',
    'still_open_preserves_open_task_and_due_date',
    'couldnt_do_preserves_open_task_and_due_date',
    'no_longer_needed_archives_task',
    'all_responses_are_audited',
    'all_cues_resolve_through_existing_worker_api'
  ),true,
  jsonb_build_object('system_fixture',true,'portable',true,'trust_recovery',true)
)
on conflict (stable_key) do update set
  domain=excluded.domain,title=excluded.title,purpose=excluded.purpose,run_mode=excluded.run_mode,
  fixture_version=excluded.fixture_version,preconditions=excluded.preconditions,
  expected_invariants=excluded.expected_invariants,active=excluded.active,
  metadata=atlas.reference_company_scenarios.metadata||excluded.metadata,updated_at=now();

create or replace function atlas.run_reference_company_prior_work_reconciliation_v1(p_source_revision text default null)
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog, atlas, auth
as $function$
declare
  v_scenario atlas.reference_company_scenarios%rowtype;
  v_farm atlas.farms%rowtype;
  v_org_id uuid;
  v_user_id uuid;
  v_membership_id uuid;
  v_run_id uuid;
  v_run_token text;
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_prior date;
  v_due date;
  v_names text[]:=array['finished','partial','still_open','couldnt_do','no_longer_needed'];
  v_task_ids uuid[]:='{}';
  v_placement_ids uuid[]:='{}';
  v_cue_ids uuid[]:='{}';
  v_name text;
  v_task_id uuid;
  v_placement_id uuid;
  v_cue_id uuid;
  v_sync jsonb:='{}'::jsonb;
  v_response jsonb;
  v_status text;
  v_due_after date;
  v_count integer;
  v_assertions jsonb:='[]'::jsonb;
  v_all_passed boolean:=false;
  v_fixture_completed boolean:=false;
  v_error text;
  i integer;
begin
  select * into v_scenario from atlas.reference_company_scenarios where stable_key='prior_work_reconciliation_v1' and active;
  if v_scenario.id is null then raise exception 'Reference prior-work scenario unavailable.' using errcode='P0002'; end if;
  select * into v_farm from atlas.farms where stable_key='atlas_reference_farm';
  if v_farm.id is null or not atlas.is_system_fixture_farm_v1(v_farm.id) then raise exception 'Atlas Reference Farm isolation contract unavailable.' using errcode='23514'; end if;
  v_org_id:=v_farm.organization_id;
  select fm.user_id into v_user_id from atlas.farm_memberships fm where fm.active=true and fm.user_id is not null order by fm.created_at,fm.id limit 1;
  if v_user_id is null then raise exception 'Reference prior-work scenario requires an auth-backed membership.' using errcode='23514'; end if;

  v_run_token:='reference:prior_work_reconciliation_v1:'||replace(gen_random_uuid()::text,'-','');
  insert into atlas.reference_company_runs(scenario_id,farm_id,run_token,run_mode,status,source_revision,metadata)
  values(v_scenario.id,v_farm.id,v_run_token,'transactional','running',p_source_revision,jsonb_build_object('fixtureVersion',1,'systemFixture',true,'runner','run_reference_company_prior_work_reconciliation_v1'))
  returning id into v_run_id;

  begin
    insert into atlas.farm_memberships(user_id,farm_id,role,worker_key,active,permissions)
    values(v_user_id,v_farm.id,'manager','reference_prior_work_'||replace(v_run_id::text,'-',''),true,
      jsonb_build_object('system_fixture',true,'reference_fixture_membership',true,'reference_run_id',v_run_id))
    returning id into v_membership_id;

    v_prior:=atlas.previous_worker_day_v1(v_farm.id,v_membership_id,v_today);
    v_due:=v_prior-2;

    foreach v_name in array v_names loop
      insert into atlas.tasks(
        organization_id,farm_id,title,status,due_date,visibility_scope,assigned_membership_id,
        task_scope,origin_kind,work_lane,commitment_kind,action_key,task_type,metadata
      ) values(
        v_org_id,v_farm.id,'Reference prior work — '||v_name,'open',v_due,'assigned_worker',v_membership_id,
        'farm_operation','generated','required','hard_date','reference_prior_work','general',
        jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'prior_work_case',v_name)
      ) returning id into v_task_id;
      v_task_ids:=array_append(v_task_ids,v_task_id);

      insert into atlas.worker_day_task_placements(
        organization_id,farm_id,membership_id,task_id,service_date,day_window,sort_order,placement_source,state,placement_reason
      ) values(
        v_org_id,v_farm.id,v_membership_id,v_task_id,v_prior,'morning',100+array_length(v_task_ids,1),'atlas','returned_to_atlas',
        'Synthetic prior Worker Day placement already returned to Atlas for reconciliation test.'
      ) returning id into v_placement_id;
      v_placement_ids:=array_append(v_placement_ids,v_placement_id);
    end loop;

    v_sync:=atlas.sync_prior_work_reconciliation_cues_v1(v_farm.id,v_membership_id,v_today);
    select array_agg(c.id order by c.result_contract->>'placementId') into v_cue_ids
    from atlas.worker_day_cues c
    where c.farm_id=v_farm.id and c.membership_id=v_membership_id and c.service_date=v_today
      and c.result_contract->>'kind'='prior_work_reconciliation_v1';

    select count(*) into v_count from atlas.worker_day_cues c
    where c.farm_id=v_farm.id and c.membership_id=v_membership_id and c.service_date=v_today
      and c.anchor_kind='first_open' and c.result_contract->>'kind'='prior_work_reconciliation_v1';
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('key','five_prior_placements_create_five_first_open_cues','passed',v_count=5,'expected',5,'actual',v_count));

    perform set_config('request.jwt.claim.sub',v_user_id::text,true);

    for i in 1..5 loop
      v_task_id:=v_task_ids[i];
      v_name:=v_names[i];
      select c.id into v_cue_id from atlas.worker_day_cues c
      where c.farm_id=v_farm.id and c.membership_id=v_membership_id and c.result_contract->>'taskId'=v_task_id::text
        and c.result_contract->>'kind'='prior_work_reconciliation_v1' limit 1;
      v_response:=jsonb_build_object('outcome',v_name,'note','Reference answer: '||v_name);
      perform atlas.worker_resolve_day_cue_api_v1(v_cue_id,v_response);
    end loop;

    select status,due_date into v_status,v_due_after from atlas.tasks where id=v_task_ids[1];
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('key','finished_closes_task','passed',v_status='done' and v_due_after=v_due,'expected',jsonb_build_object('status','done','dueDate',v_due),'actual',jsonb_build_object('status',v_status,'dueDate',v_due_after)));

    select status,due_date into v_status,v_due_after from atlas.tasks where id=v_task_ids[2];
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('key','partial_preserves_open_task_and_due_date','passed',v_status='open' and v_due_after=v_due,'expected',jsonb_build_object('status','open','dueDate',v_due),'actual',jsonb_build_object('status',v_status,'dueDate',v_due_after)));

    select status,due_date into v_status,v_due_after from atlas.tasks where id=v_task_ids[3];
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('key','still_open_preserves_open_task_and_due_date','passed',v_status='open' and v_due_after=v_due,'expected',jsonb_build_object('status','open','dueDate',v_due),'actual',jsonb_build_object('status',v_status,'dueDate',v_due_after)));

    select status,due_date into v_status,v_due_after from atlas.tasks where id=v_task_ids[4];
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('key','couldnt_do_preserves_open_task_and_due_date','passed',v_status='open' and v_due_after=v_due,'expected',jsonb_build_object('status','open','dueDate',v_due),'actual',jsonb_build_object('status',v_status,'dueDate',v_due_after)));

    select status,due_date into v_status,v_due_after from atlas.tasks where id=v_task_ids[5];
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('key','no_longer_needed_archives_task','passed',v_status='archived' and v_due_after=v_due,'expected',jsonb_build_object('status','archived','dueDate',v_due),'actual',jsonb_build_object('status',v_status,'dueDate',v_due_after)));

    select count(*) into v_count from atlas.task_outcome_events e where e.task_id=any(v_task_ids)
      and (e.source='prior_work_reconciliation' or e.metadata ? 'prior_work_reconciliation');
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('key','all_responses_are_audited','passed',v_count=5,'expected',5,'actual',v_count));

    select count(*) into v_count from atlas.worker_day_cues c where c.id=any(v_cue_ids) and c.status='resolved';
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('key','all_cues_resolve_through_existing_worker_api','passed',v_count=5,'expected',5,'actual',v_count));

    raise exception 'REFERENCE_FIXTURE_ROLLBACK' using errcode='P9001';
  exception
    when sqlstate 'P9001' then v_fixture_completed:=true;
    when others then get stacked diagnostics v_error=message_text; v_fixture_completed:=false;
  end;

  perform set_config('request.jwt.claim.sub','',true);

  if not v_fixture_completed then
    update atlas.reference_company_runs set status='failed',completed_at=now(),error_text=v_error,
      result=jsonb_build_object('fixtureRolledBack',true,'runnerError',v_error,'sync',v_sync) where id=v_run_id;
    return jsonb_build_object('contractVersion','run_reference_company_prior_work_reconciliation_v1','runId',v_run_id,'scenarioKey','prior_work_reconciliation_v1','status','failed','error',v_error,'fixtureRolledBack',true);
  end if;

  insert into atlas.reference_company_assertions(run_id,assertion_key,passed,expected,actual,detail)
  select v_run_id,x->>'key',coalesce((x->>'passed')::boolean,false),jsonb_build_object('value',x->'expected'),jsonb_build_object('value',x->'actual'),null
  from jsonb_array_elements(v_assertions) x;
  select coalesce(bool_and(passed),false) into v_all_passed from atlas.reference_company_assertions where run_id=v_run_id;
  update atlas.reference_company_runs set status=case when v_all_passed then 'passed' else 'failed' end,completed_at=now(),
    result=jsonb_build_object('fixtureRolledBack',true,'sync',v_sync,'assertions',v_assertions,'allPassed',v_all_passed),
    error_text=case when v_all_passed then null else 'One or more prior-work reconciliation assertions failed.' end where id=v_run_id;

  return jsonb_build_object('contractVersion','run_reference_company_prior_work_reconciliation_v1','runId',v_run_id,'scenarioKey','prior_work_reconciliation_v1',
    'status',case when v_all_passed then 'passed' else 'failed' end,'fixtureRolledBack',true,'assertions',v_assertions);
end;
$function$;

revoke all on function atlas.run_reference_company_prior_work_reconciliation_v1(text) from public,anon,authenticated;