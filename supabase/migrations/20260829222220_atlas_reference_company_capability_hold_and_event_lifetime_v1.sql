insert into atlas.reference_company_scenarios(
  stable_key,domain,title,purpose,run_mode,fixture_version,preconditions,expected_invariants,active,metadata
) values(
  'capability_hold_and_event_lifetime_v1','worker_day','Capability hold + event-bound lifetime',
  'Prove non-executable obligations can remain in custody outside Worker Day until capability returns, while explicit one-off event work retires after its event without claiming completion.',
  'transactional',1,
  jsonb_build_object('systemFixtureFarm','atlas_reference_farm','requiresExistingAuthUser',true),
  jsonb_build_array(
    'waiting_hold_preserves_due_truth',
    'waiting_hold_suppresses_worker_day',
    'waiting_hold_blocks_execution_readiness',
    'waiting_hold_is_visible_in_capability_pool',
    'release_preserves_original_due_truth',
    'release_restores_worker_day_visibility',
    'release_clears_external_readiness_block',
    'expired_event_task_archives',
    'expired_event_task_records_not_relevant_not_done',
    'expired_event_task_preserves_original_due_truth'
  ),true,
  jsonb_build_object('system_fixture',true,'portable',true,'trust_recovery',true,'capability_pool',true,'event_lifetime',true)
)
on conflict (stable_key) do update set
  domain=excluded.domain,title=excluded.title,purpose=excluded.purpose,run_mode=excluded.run_mode,
  fixture_version=excluded.fixture_version,preconditions=excluded.preconditions,
  expected_invariants=excluded.expected_invariants,active=excluded.active,
  metadata=atlas.reference_company_scenarios.metadata||excluded.metadata,updated_at=now();

create or replace function atlas.run_reference_company_capability_hold_and_event_lifetime_v1(p_source_revision text default null)
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog, atlas, auth
as $function$
declare
  v_scenario atlas.reference_company_scenarios%rowtype;
  v_farm atlas.farms%rowtype;
  v_user_id uuid;
  v_membership_id uuid;
  v_run_id uuid;
  v_run_token text;
  v_today date:=(now() at time zone 'America/Chicago')::date;
  v_due date;
  v_task_id uuid;
  v_program_id uuid;
  v_event_id uuid;
  v_event_task_id uuid;
  v_event_due date;
  v_status text;
  v_visibility text;
  v_due_after date;
  v_count integer;
  v_readiness jsonb;
  v_pool jsonb;
  v_assertions jsonb:='[]'::jsonb;
  v_all_passed boolean:=false;
  v_fixture_completed boolean:=false;
  v_error text;
begin
  select * into v_scenario from atlas.reference_company_scenarios where stable_key='capability_hold_and_event_lifetime_v1' and active;
  if v_scenario.id is null then raise exception 'Reference capability-hold scenario unavailable.' using errcode='P0002'; end if;
  select * into v_farm from atlas.farms where stable_key='atlas_reference_farm';
  if v_farm.id is null or not atlas.is_system_fixture_farm_v1(v_farm.id) then raise exception 'Atlas Reference Farm isolation contract unavailable.' using errcode='23514'; end if;
  select fm.user_id into v_user_id from atlas.farm_memberships fm where fm.user_id is not null and fm.active=true order by fm.created_at,fm.id limit 1;
  if v_user_id is null then raise exception 'Reference scenario requires an auth-backed membership.' using errcode='23514'; end if;

  v_run_token:='reference:capability_hold_and_event_lifetime_v1:'||replace(gen_random_uuid()::text,'-','');
  insert into atlas.reference_company_runs(scenario_id,farm_id,run_token,run_mode,status,source_revision,metadata)
  values(v_scenario.id,v_farm.id,v_run_token,'transactional','running',p_source_revision,jsonb_build_object('fixtureVersion',1,'systemFixture',true,'runner','run_reference_company_capability_hold_and_event_lifetime_v1'))
  returning id into v_run_id;

  begin
    insert into atlas.farm_memberships(user_id,farm_id,role,worker_key,active,permissions)
    values(v_user_id,v_farm.id,'manager','reference_capability_'||replace(v_run_id::text,'-',''),true,
      jsonb_build_object('system_fixture',true,'reference_fixture_membership',true,'reference_run_id',v_run_id))
    returning id into v_membership_id;

    v_due:=v_today-4;
    insert into atlas.tasks(
      organization_id,farm_id,title,status,due_date,visibility_scope,assigned_membership_id,assigned_user_id,
      task_scope,origin_kind,work_lane,commitment_kind,action_key,task_type,metadata
    ) values(
      v_farm.organization_id,v_farm.id,'Reference capability-held repair','open',v_due,'assigned_worker',v_membership_id,v_user_id,
      'farm_operation','generated','discretionary','floating','repair','infrastructure',
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'task_key','reference_capability_hold_'||v_run_id::text)
    ) returning id into v_task_id;

    perform atlas.set_task_capability_hold_internal_v1(
      v_task_id,'waiting',array['person','tool','travel'],
      'Waiting for the qualified person, tool, and travel window.',
      'Reference hold test.','reference_company'
    );

    select status,visibility_scope,due_date into v_status,v_visibility,v_due_after from atlas.tasks where id=v_task_id;
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','waiting_hold_preserves_due_truth','passed',v_status='blocked' and v_visibility='system_internal' and v_due_after=v_due,
      'expected',jsonb_build_object('status','blocked','visibility','system_internal','dueDate',v_due),
      'actual',jsonb_build_object('status',v_status,'visibility',v_visibility,'dueDate',v_due_after)
    ));

    select count(*) into v_count from atlas.worker_day_visibility_floor_v1(v_farm.id,v_membership_id,v_today) f where f.task_id=v_task_id;
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','waiting_hold_suppresses_worker_day','passed',v_count=0,'expected',0,'actual',v_count
    ));

    v_readiness:=atlas.task_execution_readiness_v1(v_task_id);
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','waiting_hold_blocks_execution_readiness','passed',coalesce((v_readiness->>'externalReadinessReady')::boolean,true)=false,
      'expected',false,'actual',coalesce((v_readiness->>'externalReadinessReady')::boolean,true)
    ));

    v_pool:=atlas.capability_hold_pool_v1(v_farm.id);
    select count(*) into v_count from jsonb_array_elements(coalesce(v_pool->'items','[]'::jsonb)) x where x->>'taskId'=v_task_id::text;
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','waiting_hold_is_visible_in_capability_pool','passed',v_count=1,'expected',1,'actual',v_count
    ));

    perform atlas.set_task_capability_hold_internal_v1(
      v_task_id,'ready',array['person','tool','travel'],null,
      'Reference capability is now available.','reference_company'
    );

    select status,visibility_scope,due_date into v_status,v_visibility,v_due_after from atlas.tasks where id=v_task_id;
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','release_preserves_original_due_truth','passed',v_status='open' and v_visibility='assigned_worker' and v_due_after=v_due,
      'expected',jsonb_build_object('status','open','visibility','assigned_worker','dueDate',v_due),
      'actual',jsonb_build_object('status',v_status,'visibility',v_visibility,'dueDate',v_due_after)
    ));

    select count(*) into v_count from atlas.worker_day_visibility_floor_v1(v_farm.id,v_membership_id,v_today) f where f.task_id=v_task_id;
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','release_restores_worker_day_visibility','passed',v_count=1,'expected',1,'actual',v_count
    ));

    v_readiness:=atlas.task_execution_readiness_v1(v_task_id);
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','release_clears_external_readiness_block','passed',coalesce((v_readiness->>'externalReadinessReady')::boolean,false)=true,
      'expected',true,'actual',coalesce((v_readiness->>'externalReadinessReady')::boolean,false)
    ));

    insert into atlas.community_programs(farm_id,stable_key,title,active,metadata)
    values(v_farm.id,'reference_event_program_'||replace(v_run_id::text,'-',''),'Reference Event Program',true,jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id))
    returning id into v_program_id;

    insert into atlas.community_events(farm_id,program_id,stable_key,title,event_kind,event_date,start_local_time,end_local_time,status,visibility_scope,metadata)
    values(v_farm.id,v_program_id,'reference_event_'||replace(v_run_id::text,'-',''),'Reference one-off event','reference_event',v_today-1,time '18:00',time '20:00','planned','farm_shared',jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id))
    returning id into v_event_id;

    v_event_due:=v_today-2;
    insert into atlas.tasks(
      organization_id,farm_id,title,status,due_date,visibility_scope,assigned_membership_id,assigned_user_id,
      task_scope,origin_kind,work_lane,commitment_kind,action_key,task_type,metadata
    ) values(
      v_farm.organization_id,v_farm.id,'Reference event-only prep','open',v_event_due,'assigned_worker',v_membership_id,v_user_id,
      'farm_operation','generated','required','hard_date','prepare','event_prep',
      jsonb_build_object(
        'system_fixture',true,'reference_run_id',v_run_id,'one_off_event_task',true,
        'community_event_id',v_event_id,'community_event_key','reference_event_'||replace(v_run_id::text,'-','')
      )
    ) returning id into v_event_task_id;

    perform atlas.reconcile_expired_event_bound_tasks_v1(v_farm.id,v_today);

    select status,due_date into v_status,v_due_after from atlas.tasks where id=v_event_task_id;
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','expired_event_task_archives','passed',v_status='archived','expected','archived','actual',v_status
    ));

    select count(*) into v_count from atlas.task_transitions tt
    where tt.task_id=v_event_task_id and tt.transition='not_relevant' and tt.payload->>'completion_source'='event_lifecycle_expiry';
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','expired_event_task_records_not_relevant_not_done','passed',v_count=1 and not exists(select 1 from atlas.task_transitions d where d.task_id=v_event_task_id and d.transition='done'),
      'expected',jsonb_build_object('notRelevant',1,'done',0),
      'actual',jsonb_build_object('notRelevant',v_count,'done',(select count(*) from atlas.task_transitions d where d.task_id=v_event_task_id and d.transition='done'))
    ));

    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','expired_event_task_preserves_original_due_truth','passed',v_due_after=v_event_due,'expected',v_event_due,'actual',v_due_after
    ));

    raise exception 'REFERENCE_FIXTURE_ROLLBACK' using errcode='P9001';
  exception
    when sqlstate 'P9001' then v_fixture_completed:=true;
    when others then get stacked diagnostics v_error=message_text; v_fixture_completed:=false;
  end;

  if not v_fixture_completed then
    update atlas.reference_company_runs set status='failed',completed_at=now(),error_text=v_error,
      result=jsonb_build_object('fixtureRolledBack',true,'runnerError',v_error) where id=v_run_id;
    return jsonb_build_object('contractVersion','run_reference_company_capability_hold_and_event_lifetime_v1','runId',v_run_id,'scenarioKey',v_scenario.stable_key,'status','failed','error',v_error,'fixtureRolledBack',true);
  end if;

  insert into atlas.reference_company_assertions(run_id,assertion_key,passed,expected,actual,detail)
  select v_run_id,x->>'key',coalesce((x->>'passed')::boolean,false),jsonb_build_object('value',x->'expected'),jsonb_build_object('value',x->'actual'),null
  from jsonb_array_elements(v_assertions) x;

  select coalesce(bool_and(passed),false) into v_all_passed from atlas.reference_company_assertions where run_id=v_run_id;
  update atlas.reference_company_runs set status=case when v_all_passed then 'passed' else 'failed' end,completed_at=now(),
    result=jsonb_build_object('fixtureRolledBack',true,'assertions',v_assertions,'allPassed',v_all_passed),
    error_text=case when v_all_passed then null else 'One or more capability-hold/event-lifetime assertions failed.' end
  where id=v_run_id;

  return jsonb_build_object(
    'contractVersion','run_reference_company_capability_hold_and_event_lifetime_v1','runId',v_run_id,
    'scenarioKey',v_scenario.stable_key,'status',case when v_all_passed then 'passed' else 'failed' end,
    'fixtureRolledBack',true,'assertions',v_assertions
  );
end;
$function$;

revoke all on function atlas.run_reference_company_capability_hold_and_event_lifetime_v1(text) from public,anon,authenticated;