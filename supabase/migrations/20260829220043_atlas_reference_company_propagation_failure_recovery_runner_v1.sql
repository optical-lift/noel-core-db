create or replace function atlas.run_reference_company_propagation_failure_recovery_v1(p_source_revision text default null)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  v_scenario atlas.reference_company_scenarios%rowtype;
  v_farm atlas.farms%rowtype;
  v_org_id uuid;
  v_profile_id uuid;
  v_propagation_object_id uuid;
  v_run_id uuid;
  v_run_token text;
  v_today date:=(now() at time zone 'America/Chicago')::date;
  v_hardening_date date:=((now() at time zone 'America/Chicago')::date)-17;
  v_failure_date date:=((now() at time zone 'America/Chicago')::date)-3;
  v_program_id uuid;
  v_lot_id uuid;
  v_cycle_id uuid;
  v_batch_id uuid;
  v_requirement_id uuid;
  v_hardening_occurrence_id uuid;
  v_hardening_task_id uuid;
  v_readiness_occurrence_id uuid;
  v_readiness_task_id uuid;
  v_failure_result jsonb;
  v_reconcile jsonb;
  v_assertions jsonb:='[]'::jsonb;
  v_result jsonb:='{}'::jsonb;
  v_fixture_completed boolean:=false;
  v_all_passed boolean:=false;
  v_error text;
  v_count integer;
  v_duplicate_count integer;
  v_lot_qty numeric;
  v_batch_qty numeric;
  v_cycle_qty numeric;
  v_obs_qty numeric;
  v_stage text;
  v_batch_status text;
  v_cycle_status text;
  v_recovery_state text;
begin
  select * into v_scenario
  from atlas.reference_company_scenarios
  where stable_key='propagation_failure_recovery_v1' and active;
  if v_scenario.id is null then
    raise exception 'Reference company propagation failure scenario is unavailable.' using errcode='P0002';
  end if;

  select * into v_farm from atlas.farms where stable_key='atlas_reference_farm';
  if v_farm.id is null or not atlas.is_system_fixture_farm_v1(v_farm.id) then
    raise exception 'Atlas Reference Farm isolation contract is unavailable.' using errcode='23514';
  end if;
  select organization_id into v_org_id from atlas.farms where id=v_farm.id;
  select id into v_profile_id from atlas.crop_profiles where stable_key='atlas_reference_snapdragon_golden_v1';
  select id into v_propagation_object_id from atlas.growing_objects where farm_id=v_farm.id and stable_key='reference_propagation_bench';
  if v_profile_id is null or v_propagation_object_id is null then
    raise exception 'Reference propagation failure fixtures are incomplete.' using errcode='23514';
  end if;

  v_run_token:='reference:propagation_failure_recovery_v1:'||replace(gen_random_uuid()::text,'-','');
  insert into atlas.reference_company_runs(scenario_id,farm_id,run_token,run_mode,status,source_revision,metadata)
  values(v_scenario.id,v_farm.id,v_run_token,'transactional','running',p_source_revision,
    jsonb_build_object('fixtureVersion',v_scenario.fixture_version,'systemFixture',true,'runner','run_reference_company_propagation_failure_recovery_v1'))
  returning id into v_run_id;

  begin
    insert into atlas.production_programs(
      farm_id,stable_key,season_year,program_label,program_kind,promise_text,intended_uses,status,metadata
    ) values(
      v_farm.id,'reference_failure_program_'||replace(v_run_id::text,'-',''),extract(year from v_today)::integer,
      'Reference propagation failure recovery','reference_fixture',
      'Exercise counted seedling failure and governed recovery without inventing surviving inventory.',array['conformance'],'active',
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)
    ) returning id into v_program_id;

    insert into atlas.production_lots(
      farm_id,program_id,crop_profile_id,stable_key,lot_label,succession_number,
      planned_input_quantity,planned_input_unit,current_quantity,current_unit,current_stage,lifecycle_status,
      planned_sow_date,actual_sow_date,expected_transplant_start,expected_transplant_end,
      expected_harvest_start,expected_harvest_end,intended_uses,metadata
    ) values(
      v_farm.id,v_program_id,v_profile_id,'reference_failure_lot_'||replace(v_run_id::text,'-',''),
      'Reference Snapdragon · Failure Recovery',1,720,'seeds',720,'seedlings','seedling_care','active',
      v_hardening_date-60,v_hardening_date-60,v_failure_date,v_failure_date+5,
      v_today+45,v_today+75,array['conformance'],
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true,
        'hardening_start_date',v_hardening_date,'destination_program','reference_bed_1..3',
        'warning','Synthetic reference-company lot; not customer production truth.')
    ) returning id into v_lot_id;

    insert into atlas.crop_cycles(
      farm_id,object_id,crop_profile_id,crop_cycle_key,crop_label,variety,cycle_state,lifecycle_status,
      sown_date,germination_checked_date,coverage_kind,coverage_amount,coverage_unit,note,metadata
    ) values(
      v_farm.id,v_propagation_object_id,v_profile_id,'reference_failure_cycle_'||replace(v_run_id::text,'-',''),
      'Reference Snapdragon','Failure Recovery','seedling_care','active',v_hardening_date-60,v_hardening_date-50,
      'viable_seedlings',720,'seedlings','Synthetic reference-company propagation failure cohort.',
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)
    ) returning id into v_cycle_id;

    insert into atlas.production_tray_batches(
      farm_id,production_lot_id,crop_cycle_id,batch_number,batch_label,container_kind,block_size_in,
      seeds_sown,seed_unit,tray_count,status,sown_date,expected_germination_start,expected_germination_end,
      germinated_date,viable_seedlings,current_quantity,current_unit,idempotency_key,source_object_id,metadata
    ) values(
      v_farm.id,v_lot_id,v_cycle_id,1,'Reference Failure Tray Batch','3/4-inch soil blocks',0.75,
      720,'seeds',4,'seedling_care',v_hardening_date-60,v_hardening_date-53,v_hardening_date-46,
      v_hardening_date-50,720,720,'seedlings','reference-failure-tray:'||v_run_id::text,v_propagation_object_id,
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true,'pot_up_required',false)
    ) returning id into v_batch_id;

    insert into atlas.production_lot_crop_cycles(production_lot_id,crop_cycle_id,relation_role,confidence,source,metadata)
    values(v_lot_id,v_cycle_id,'propagation_batch','confirmed','reference_company_runner',jsonb_build_object('reference_run_id',v_run_id));

    insert into atlas.production_capacity_requirements(
      farm_id,production_lot_id,stable_key,stage_key,capacity_kind,quantity_needed,unit,
      required_by_date,window_start,window_end,preparation_due_date,calculation_status,source,metadata
    ) values(
      v_farm.id,v_lot_id,'reference_failure_bed_feet','transplant','bed_feet',null,'bed_ft',
      v_failure_date,v_failure_date,v_failure_date+5,v_failure_date-1,'blocked','reference_company_runner',
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'quantity_truth','awaiting_counted_transplant_readiness')
    ) returning id into v_requirement_id;

    v_reconcile:=atlas.reconcile_production_work_v1(v_lot_id,v_hardening_date);
    select id into v_hardening_occurrence_id
    from atlas.planned_work_occurrences
    where farm_id=v_farm.id and occurrence_key='production:hardening:'||v_batch_id::text
    order by created_at desc limit 1;
    if v_hardening_occurrence_id is not null then
      v_hardening_task_id:=nullif((atlas.materialize_specific_work_occurrence_v1(v_hardening_occurrence_id,v_hardening_date)->>'taskId'),'')::uuid;
    end if;
    if v_hardening_task_id is null then
      raise exception 'Reference hardening task was not derived.' using errcode='23514';
    end if;
    perform atlas.record_production_hardening_v1(
      v_hardening_task_id,v_hardening_date,'Reference propagation failure scenario hardening.',
      'reference-failure-hardening:'||v_run_id::text
    );

    select id into v_readiness_occurrence_id
    from atlas.planned_work_occurrences
    where farm_id=v_farm.id and occurrence_key='production:transplant-readiness:'||v_batch_id::text
    order by created_at desc limit 1;
    if v_readiness_occurrence_id is not null then
      v_readiness_task_id:=nullif((atlas.materialize_specific_work_occurrence_v1(v_readiness_occurrence_id,v_failure_date)->>'taskId'),'')::uuid;
    end if;
    if v_readiness_task_id is null then
      raise exception 'Reference readiness task was not derived.' using errcode='23514';
    end if;

    v_failure_result:=atlas.record_production_readiness_v1(
      v_readiness_task_id,'failed',0,0,v_failure_date,null,
      'Reference propagation failure scenario: counted zero surviving seedlings.',
      'reference-failure-readiness:'||v_run_id::text
    );

    select current_quantity,current_stage into v_lot_qty,v_stage from atlas.production_lots where id=v_lot_id;
    select current_quantity,status into v_batch_qty,v_batch_status from atlas.production_tray_batches where id=v_batch_id;
    select coverage_amount,lifecycle_status into v_cycle_qty,v_cycle_status from atlas.crop_cycles where id=v_cycle_id;
    select surviving_seedlings into v_obs_qty from atlas.production_readiness_observations
      where production_lot_id=v_lot_id order by created_at desc limit 1;

    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','zero_survivors_preserved_as_zero',
      'passed',coalesce(v_lot_qty,-1)=0 and coalesce(v_batch_qty,-1)=0 and coalesce(v_cycle_qty,-1)=0 and coalesce(v_obs_qty,-1)=0,
      'expected',jsonb_build_object('lot',0,'batch',0,'cycle',0,'observation',0),
      'actual',jsonb_build_object('lot',v_lot_qty,'batch',v_batch_qty,'cycle',v_cycle_qty,'observation',v_obs_qty)));

    select count(*) into v_count
    from atlas.planned_work_occurrences
    where farm_id=v_farm.id
      and coalesce(metadata->>'production_lot_id','')=v_lot_id::text
      and state<>'cancelled'
      and (occurrence_key like 'production:transplant:%' or occurrence_key like 'production:bed-preparation:%');
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','failed_cohort_cannot_advance',
      'passed',v_stage='seedling_failure_decision' and v_batch_status='failed' and v_cycle_status='archived' and v_count=0,
      'expected',jsonb_build_object('lotStage','seedling_failure_decision','batchStatus','failed','cycleLifecycle','archived','downstreamExecution',0),
      'actual',jsonb_build_object('lotStage',v_stage,'batchStatus',v_batch_status,'cycleLifecycle',v_cycle_status,'downstreamExecution',v_count)));

    perform atlas.reconcile_production_work_v1(v_lot_id,v_today);
    perform atlas.reconcile_production_work_v1(v_lot_id,v_today);

    select count(*),min(state) into v_count,v_recovery_state
    from atlas.planned_work_occurrences
    where farm_id=v_farm.id and occurrence_key='production:owner-seedling-recovery:'||v_batch_id::text;
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','exactly_one_recovery_decision_exists',
      'passed',v_count=1 and v_recovery_state<>'cancelled',
      'expected',jsonb_build_object('count',1,'state','not_cancelled'),
      'actual',jsonb_build_object('count',v_count,'state',v_recovery_state)));

    select count(*) into v_duplicate_count from (
      select occurrence_key
      from atlas.planned_work_occurrences
      where farm_id=v_farm.id and coalesce(metadata->>'production_lot_id','')=v_lot_id::text
      group by occurrence_key having count(*)>1
    ) d;
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','reconciliation_has_no_duplicate_occurrence_keys','passed',v_duplicate_count=0,
      'expected',0,'actual',v_duplicate_count));

    v_result:=jsonb_build_object(
      'fixtureRolledBack',true,
      'failureResult',coalesce(v_failure_result,'{}'::jsonb),
      'assertionCount',jsonb_array_length(v_assertions)
    );

    raise exception 'REFERENCE_FIXTURE_ROLLBACK' using errcode='P9001';
  exception
    when sqlstate 'P9001' then
      v_fixture_completed:=true;
    when others then
      get stacked diagnostics v_error=message_text;
      v_fixture_completed:=false;
  end;

  if not v_fixture_completed then
    update atlas.reference_company_runs
    set status='failed',completed_at=now(),error_text=v_error,
        result=jsonb_build_object('fixtureRolledBack',true,'runnerError',v_error)
    where id=v_run_id;
    return jsonb_build_object('contractVersion','run_reference_company_propagation_failure_recovery_v1','runId',v_run_id,
      'scenarioKey','propagation_failure_recovery_v1','status','failed','error',v_error,'fixtureRolledBack',true);
  end if;

  insert into atlas.reference_company_assertions(run_id,assertion_key,passed,expected,actual,detail)
  select v_run_id,x->>'key',coalesce((x->>'passed')::boolean,false),
         jsonb_build_object('value',x->'expected'),jsonb_build_object('value',x->'actual'),null
  from jsonb_array_elements(v_assertions) x;

  select coalesce(bool_and(passed),false) into v_all_passed
  from atlas.reference_company_assertions where run_id=v_run_id;

  update atlas.reference_company_runs
  set status=case when v_all_passed then 'passed' else 'failed' end,
      completed_at=now(),result=v_result||jsonb_build_object('assertions',v_assertions,'allPassed',v_all_passed),
      error_text=case when v_all_passed then null else 'One or more conformance assertions failed.' end
  where id=v_run_id;

  return jsonb_build_object(
    'contractVersion','run_reference_company_propagation_failure_recovery_v1','runId',v_run_id,
    'scenarioKey','propagation_failure_recovery_v1','status',case when v_all_passed then 'passed' else 'failed' end,
    'fixtureRolledBack',true,'assertions',v_assertions
  );
end;
$function$;

update atlas.reference_company_scenarios
set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
  'runner','run_reference_company_propagation_failure_recovery_v1',
  'runner_version',1,
  'implementation_state','executable',
  'fixture_contract','rollback_only'
), updated_at=now()
where stable_key='propagation_failure_recovery_v1';