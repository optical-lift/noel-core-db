create or replace function atlas.run_reference_company_reconciler_idempotency_v1(p_source_revision text default null)
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
  v_bed_1 uuid;
  v_bed_2 uuid;
  v_bed_3 uuid;
  v_run_id uuid;
  v_run_token text;
  v_today date:=(now() at time zone 'America/Chicago')::date;
  v_program_id uuid;
  v_lot_id uuid;
  v_cycle_id uuid;
  v_batch_id uuid;
  v_evidence_task_id uuid;
  v_observation_id uuid;
  v_requirement_id uuid;
  v_assignment_1 uuid;
  v_assignment_2 uuid;
  v_assignment_3 uuid;
  v_occurrence_id uuid;
  v_task_1 uuid;
  v_task_2 uuid;
  v_task_3 uuid;
  v_gate_id_1 uuid;
  v_gate_id_2 uuid;
  v_gate_status_1 text;
  v_gate_status_2 text;
  v_gate_count integer;
  v_duplicate_count integer;
  v_task_duplicate_count integer;
  v_occurrence_count integer;
  v_first_set jsonb;
  v_second_set jsonb;
  v_first_gate jsonb;
  v_second_gate jsonb;
  v_materialize_1 jsonb;
  v_materialize_2 jsonb;
  v_assertions jsonb:='[]'::jsonb;
  v_result jsonb:='{}'::jsonb;
  v_fixture_completed boolean:=false;
  v_all_passed boolean:=false;
  v_error text;
begin
  select * into v_scenario
  from atlas.reference_company_scenarios
  where stable_key='reconciler_idempotency_v1' and active;
  if v_scenario.id is null then
    raise exception 'Reference company reconciler idempotency scenario is unavailable.' using errcode='P0002';
  end if;

  select * into v_farm from atlas.farms where stable_key='atlas_reference_farm';
  if v_farm.id is null or not atlas.is_system_fixture_farm_v1(v_farm.id) then
    raise exception 'Atlas Reference Farm isolation contract is unavailable.' using errcode='23514';
  end if;
  v_org_id:=v_farm.organization_id;
  select id into v_profile_id from atlas.crop_profiles where stable_key='atlas_reference_snapdragon_golden_v1';
  select id into v_propagation_object_id from atlas.growing_objects where farm_id=v_farm.id and stable_key='reference_propagation_bench';
  select id into v_bed_1 from atlas.growing_objects where farm_id=v_farm.id and stable_key='reference_bed_1';
  select id into v_bed_2 from atlas.growing_objects where farm_id=v_farm.id and stable_key='reference_bed_2';
  select id into v_bed_3 from atlas.growing_objects where farm_id=v_farm.id and stable_key='reference_bed_3';
  if v_profile_id is null or v_propagation_object_id is null or v_bed_1 is null or v_bed_2 is null or v_bed_3 is null then
    raise exception 'Reference reconciler fixtures are incomplete.' using errcode='23514';
  end if;

  v_run_token:='reference:reconciler_idempotency_v1:'||replace(gen_random_uuid()::text,'-','');
  insert into atlas.reference_company_runs(scenario_id,farm_id,run_token,run_mode,status,source_revision,metadata)
  values(v_scenario.id,v_farm.id,v_run_token,'transactional','running',p_source_revision,
    jsonb_build_object('fixtureVersion',v_scenario.fixture_version,'systemFixture',true,'runner','run_reference_company_reconciler_idempotency_v1'))
  returning id into v_run_id;

  begin
    insert into atlas.production_programs(
      farm_id,stable_key,season_year,program_label,program_kind,promise_text,intended_uses,status,metadata
    ) values(
      v_farm.id,'reference_idempotency_program_'||replace(v_run_id::text,'-',''),extract(year from v_today)::integer,
      'Reference reconciler idempotency','reference_fixture',
      'Exercise repeated reconciliation over unchanged transplant-ready truth.',array['conformance'],'active',
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)
    ) returning id into v_program_id;

    insert into atlas.production_lots(
      farm_id,program_id,crop_profile_id,stable_key,lot_label,succession_number,
      planned_input_quantity,planned_input_unit,current_quantity,current_unit,current_stage,lifecycle_status,
      planned_sow_date,actual_sow_date,expected_transplant_start,expected_transplant_end,
      expected_harvest_start,expected_harvest_end,intended_uses,metadata
    ) values(
      v_farm.id,v_program_id,v_profile_id,'reference_idempotency_lot_'||replace(v_run_id::text,'-',''),
      'Reference Snapdragon · Reconciler Idempotency',1,720,'seeds',720,'seedlings','transplant_ready','active',
      v_today-65,v_today-65,v_today,v_today+5,v_today+45,v_today+75,array['conformance'],
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true,
        'warning','Synthetic reference-company lot; not customer production truth.')
    ) returning id into v_lot_id;

    insert into atlas.crop_cycles(
      farm_id,object_id,crop_profile_id,crop_cycle_key,crop_label,variety,cycle_state,lifecycle_status,
      sown_date,germination_checked_date,coverage_kind,coverage_amount,coverage_unit,note,metadata
    ) values(
      v_farm.id,v_propagation_object_id,v_profile_id,'reference_idempotency_cycle_'||replace(v_run_id::text,'-',''),
      'Reference Snapdragon','Reconciler Idempotency','transplant_ready','active',v_today-65,v_today-55,
      'viable_seedlings',720,'seedlings','Synthetic reference-company idempotency cohort.',
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)
    ) returning id into v_cycle_id;

    insert into atlas.production_tray_batches(
      farm_id,production_lot_id,crop_cycle_id,batch_number,batch_label,container_kind,block_size_in,
      seeds_sown,seed_unit,tray_count,status,sown_date,expected_germination_start,expected_germination_end,
      germinated_date,viable_seedlings,current_quantity,current_unit,idempotency_key,source_object_id,metadata
    ) values(
      v_farm.id,v_lot_id,v_cycle_id,1,'Reference Idempotency Tray Batch','3/4-inch soil blocks',0.75,
      720,'seeds',4,'transplant_ready',v_today-65,v_today-58,v_today-51,
      v_today-55,720,720,'seedlings','reference-idempotency-tray:'||v_run_id::text,v_propagation_object_id,
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true,'pot_up_required',false)
    ) returning id into v_batch_id;

    insert into atlas.production_lot_crop_cycles(production_lot_id,crop_cycle_id,relation_role,confidence,source,metadata)
    values(v_lot_id,v_cycle_id,'propagation_batch','confirmed','reference_company_runner',jsonb_build_object('reference_run_id',v_run_id));

    insert into atlas.tasks(
      farm_id,title,task_type,action_key,work_class,status,priority,due_date,visibility_scope,note,organization_id,metadata
    ) values(
      v_farm.id,'Reference counted transplant readiness','observation','observe','production_readiness','done','normal',v_today,'system_internal',
      'Synthetic counted readiness evidence for reconciler idempotency.',v_org_id,
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)
    ) returning id into v_evidence_task_id;

    insert into atlas.production_readiness_observations(
      farm_id,production_lot_id,tray_batch_id,task_id,observation_outcome,observed_date,
      surviving_seedlings,tray_count,confidence,note,idempotency_key,metadata
    ) values(
      v_farm.id,v_lot_id,v_batch_id,v_evidence_task_id,'ready',v_today,720,4,'counted',
      'Synthetic counted readiness evidence.','reference-idempotency-readiness:'||v_run_id::text,
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)
    ) returning id into v_observation_id;

    insert into atlas.production_capacity_requirements(
      farm_id,production_lot_id,stable_key,stage_key,capacity_kind,quantity_needed,unit,
      required_by_date,window_start,window_end,preparation_due_date,calculation_status,source,metadata
    ) values(
      v_farm.id,v_lot_id,'reference_idempotency_bed_feet','transplant','bed_feet',60,'bed_ft',
      v_today,v_today,v_today+5,v_today,'confirmed','reference_company_runner',
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)
    ) returning id into v_requirement_id;

    insert into atlas.production_bed_assignments(
      farm_id,production_lot_id,requirement_id,object_id,quantity_assigned,unit,planned_transplant_date,assignment_status,source,metadata
    ) values
      (v_farm.id,v_lot_id,v_requirement_id,v_bed_1,20,'bed_ft',v_today,'assigned','reference_company_runner',jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)),
      (v_farm.id,v_lot_id,v_requirement_id,v_bed_2,20,'bed_ft',v_today,'assigned','reference_company_runner',jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)),
      (v_farm.id,v_lot_id,v_requirement_id,v_bed_3,20,'bed_ft',v_today,'assigned','reference_company_runner',jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true));

    select id into v_assignment_1 from atlas.production_bed_assignments where production_lot_id=v_lot_id and object_id=v_bed_1;
    select id into v_assignment_2 from atlas.production_bed_assignments where production_lot_id=v_lot_id and object_id=v_bed_2;
    select id into v_assignment_3 from atlas.production_bed_assignments where production_lot_id=v_lot_id and object_id=v_bed_3;

    perform atlas.reconcile_production_work_v1(v_lot_id,v_today);

    select coalesce(jsonb_agg(jsonb_build_object(
      'id',id,'key',occurrence_key,'state',state,'due',planned_due_date,'notBefore',not_before_date,'hardFinish',hard_finish_date
    ) order by occurrence_key),'[]'::jsonb)
    into v_first_set
    from atlas.planned_work_occurrences
    where farm_id=v_farm.id and coalesce(metadata->>'production_lot_id','')=v_lot_id::text and state<>'cancelled';

    select id,gate_status,jsonb_build_object(
      'id',id,'status',gate_status,'required',required_bed_feet,'assigned',assigned_bed_feet,'prepared',prepared_bed_feet,
      'readinessObservationId',readiness_observation_id,'bedRequirementId',bed_requirement_id
    ) into v_gate_id_1,v_gate_status_1,v_first_gate
    from atlas.production_transplant_gates where production_lot_id=v_lot_id order by created_at limit 1;

    select id into v_occurrence_id
    from atlas.planned_work_occurrences
    where farm_id=v_farm.id and occurrence_key='production:bed-preparation:'||v_assignment_1::text
    order by created_at limit 1;
    if v_occurrence_id is null then
      raise exception 'Reference idempotency bed-preparation occurrence was not derived.' using errcode='23514';
    end if;

    v_materialize_1:=atlas.materialize_specific_work_occurrence_v1(v_occurrence_id,v_today);
    v_task_1:=nullif(v_materialize_1->>'taskId','')::uuid;
    if v_task_1 is null then
      raise exception 'Reference idempotency occurrence did not materialize a task: %',v_materialize_1 using errcode='23514';
    end if;
    v_materialize_2:=atlas.materialize_specific_work_occurrence_v1(v_occurrence_id,v_today);
    v_task_2:=nullif(v_materialize_2->>'taskId','')::uuid;

    perform atlas.reconcile_production_work_v1(v_lot_id,v_today);
    perform atlas.reconcile_production_work_v1(v_lot_id,v_today);

    select coalesce(jsonb_agg(jsonb_build_object(
      'id',id,'key',occurrence_key,'state',state,'due',planned_due_date,'notBefore',not_before_date,'hardFinish',hard_finish_date
    ) order by occurrence_key),'[]'::jsonb)
    into v_second_set
    from atlas.planned_work_occurrences
    where farm_id=v_farm.id and coalesce(metadata->>'production_lot_id','')=v_lot_id::text and state<>'cancelled';

    select id,gate_status,jsonb_build_object(
      'id',id,'status',gate_status,'required',required_bed_feet,'assigned',assigned_bed_feet,'prepared',prepared_bed_feet,
      'readinessObservationId',readiness_observation_id,'bedRequirementId',bed_requirement_id
    ) into v_gate_id_2,v_gate_status_2,v_second_gate
    from atlas.production_transplant_gates where production_lot_id=v_lot_id order by created_at limit 1;

    v_materialize_2:=atlas.materialize_specific_work_occurrence_v1(v_occurrence_id,v_today);
    v_task_3:=nullif(v_materialize_2->>'taskId','')::uuid;

    select count(*) into v_occurrence_count
    from atlas.planned_work_occurrences
    where farm_id=v_farm.id and coalesce(metadata->>'production_lot_id','')=v_lot_id::text and state<>'cancelled';

    select count(*) into v_duplicate_count from (
      select occurrence_key
      from atlas.planned_work_occurrences
      where farm_id=v_farm.id and coalesce(metadata->>'production_lot_id','')=v_lot_id::text
      group by occurrence_key having count(*)>1
    ) d;

    select count(*) into v_task_duplicate_count from (
      select planned_occurrence_id
      from atlas.tasks
      where farm_id=v_farm.id and planned_occurrence_id in (
        select id from atlas.planned_work_occurrences
        where farm_id=v_farm.id and coalesce(metadata->>'production_lot_id','')=v_lot_id::text
      )
      group by planned_occurrence_id having count(*)>1
    ) d;

    select count(*) into v_gate_count from atlas.production_transplant_gates where production_lot_id=v_lot_id;

    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','stable_occurrence_keys_and_active_obligation_set',
      'passed',v_first_set=v_second_set and v_occurrence_count=3,
      'expected',jsonb_build_object('sameSet',true,'activeOccurrences',3),
      'actual',jsonb_build_object('sameSet',v_first_set=v_second_set,'activeOccurrences',v_occurrence_count,'first',v_first_set,'second',v_second_set)));

    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','no_duplicate_occurrences',
      'passed',v_duplicate_count=0,
      'expected',0,'actual',v_duplicate_count));

    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','no_duplicate_tasks_and_materialization_is_idempotent',
      'passed',v_task_duplicate_count=0 and v_task_1=v_task_2 and v_task_2=v_task_3,
      'expected',jsonb_build_object('duplicateTaskGroups',0,'sameTaskAcrossMaterialization',true),
      'actual',jsonb_build_object('duplicateTaskGroups',v_task_duplicate_count,'firstTask',v_task_1,'secondTask',v_task_2,'thirdTask',v_task_3)));

    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','downstream_gate_identity_and_blocker_are_stable',
      'passed',v_gate_count=1 and v_gate_id_1=v_gate_id_2 and v_gate_status_1='waiting_bed_preparation' and v_gate_status_2=v_gate_status_1 and v_first_gate=v_second_gate,
      'expected',jsonb_build_object('gateRows',1,'sameGate',true,'status','waiting_bed_preparation','sameGateFacts',true),
      'actual',jsonb_build_object('gateRows',v_gate_count,'sameGate',v_gate_id_1=v_gate_id_2,'first',v_first_gate,'second',v_second_gate)));

    v_result:=jsonb_build_object('fixtureRolledBack',true,'assertionCount',jsonb_array_length(v_assertions));
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
    return jsonb_build_object('contractVersion','run_reference_company_reconciler_idempotency_v1','runId',v_run_id,
      'scenarioKey','reconciler_idempotency_v1','status','failed','error',v_error,'fixtureRolledBack',true);
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
    'contractVersion','run_reference_company_reconciler_idempotency_v1','runId',v_run_id,
    'scenarioKey','reconciler_idempotency_v1','status',case when v_all_passed then 'passed' else 'failed' end,
    'fixtureRolledBack',true,'assertions',v_assertions
  );
end;
$function$;

update atlas.reference_company_scenarios
set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
  'runner','run_reference_company_reconciler_idempotency_v1',
  'runner_version',1,
  'implementation_state','executable',
  'fixture_contract','rollback_only'
), updated_at=now()
where stable_key='reconciler_idempotency_v1';