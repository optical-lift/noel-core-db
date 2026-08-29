create or replace function atlas.run_reference_company_transplant_dependency_block_v1(p_source_revision text default null)
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
  v_measurement_id uuid;
  v_run_id uuid;
  v_run_token text;
  v_today date:=(now() at time zone 'America/Chicago')::date;
  v_hardening_date date:=((now() at time zone 'America/Chicago')::date)-17;
  v_transplant_date date:=((now() at time zone 'America/Chicago')::date)-3;
  v_program_id uuid;
  v_lot_id uuid;
  v_cycle_id uuid;
  v_batch_id uuid;
  v_requirement_id uuid;
  v_hardening_occurrence_id uuid;
  v_hardening_task_id uuid;
  v_readiness_occurrence_id uuid;
  v_readiness_task_id uuid;
  v_gate_id uuid;
  v_assignment_1 uuid;
  v_assignment_2 uuid;
  v_assignment_3 uuid;
  v_bed_1 uuid;
  v_bed_2 uuid;
  v_bed_3 uuid;
  v_bed_prep_occurrence_id uuid;
  v_bed_prep_task_id uuid;
  v_gate_status text;
  v_stage text;
  v_batch_status text;
  v_calc_status text;
  v_owner_math_occurrence_id uuid;
  v_reconcile jsonb;
  v_readiness_result jsonb;
  v_assertions jsonb:='[]'::jsonb;
  v_result jsonb:='{}'::jsonb;
  v_fixture_completed boolean:=false;
  v_all_passed boolean:=false;
  v_error text;
  v_count integer;
  v_number numeric;
  v_assigned numeric;
  v_prepared numeric;
  v_rows numeric;
  v_spacing numeric;
  v_expected_bed_feet numeric;
begin
  select * into v_scenario
  from atlas.reference_company_scenarios
  where stable_key='transplant_dependency_block_v1' and active;
  if v_scenario.id is null then
    raise exception 'Reference company transplant dependency scenario is unavailable.' using errcode='P0002';
  end if;

  select * into v_farm from atlas.farms where stable_key='atlas_reference_farm';
  if v_farm.id is null or not atlas.is_system_fixture_farm_v1(v_farm.id) then
    raise exception 'Atlas Reference Farm isolation contract is unavailable.' using errcode='23514';
  end if;
  select organization_id into v_org_id from atlas.farms where id=v_farm.id;
  select id into v_profile_id from atlas.crop_profiles where stable_key='atlas_reference_snapdragon_golden_v1';
  select id into v_propagation_object_id from atlas.growing_objects where farm_id=v_farm.id and stable_key='reference_propagation_bench';
  select id into v_bed_1 from atlas.growing_objects where farm_id=v_farm.id and stable_key='reference_bed_1';
  select id into v_bed_2 from atlas.growing_objects where farm_id=v_farm.id and stable_key='reference_bed_2';
  select id into v_bed_3 from atlas.growing_objects where farm_id=v_farm.id and stable_key='reference_bed_3';
  select id into v_measurement_id from atlas.capacity_measurements where farm_id=v_farm.id and stable_key='snapdragon_in_row_spacing_inches';
  if v_profile_id is null or v_propagation_object_id is null or v_bed_1 is null or v_bed_2 is null or v_bed_3 is null or v_measurement_id is null then
    raise exception 'Reference company transplant dependency fixtures are incomplete.' using errcode='23514';
  end if;

  v_run_token:='reference:transplant_dependency_block_v1:'||replace(gen_random_uuid()::text,'-','');
  insert into atlas.reference_company_runs(scenario_id,farm_id,run_token,run_mode,status,source_revision,metadata)
  values(v_scenario.id,v_farm.id,v_run_token,'transactional','running',p_source_revision,
         jsonb_build_object('fixtureVersion',v_scenario.fixture_version,'systemFixture',true,'runner','run_reference_company_transplant_dependency_block_v1'))
  returning id into v_run_id;

  begin
    insert into atlas.production_programs(
      farm_id,stable_key,season_year,program_label,program_kind,promise_text,intended_uses,status,metadata
    ) values(
      v_farm.id,'reference_dependency_program_'||replace(v_run_id::text,'-',''),extract(year from v_today)::integer,
      'Reference transplant dependency block','reference_fixture',
      'Exercise transplant dependency blocking and recovery without rolling back biological truth.',array['conformance'],'active',
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)
    ) returning id into v_program_id;

    insert into atlas.production_lots(
      farm_id,program_id,crop_profile_id,stable_key,lot_label,succession_number,
      planned_input_quantity,planned_input_unit,current_quantity,current_unit,current_stage,lifecycle_status,
      planned_sow_date,actual_sow_date,expected_transplant_start,expected_transplant_end,
      expected_harvest_start,expected_harvest_end,intended_uses,metadata
    ) values(
      v_farm.id,v_program_id,v_profile_id,'reference_dependency_lot_'||replace(v_run_id::text,'-',''),
      'Reference Snapdragon · Dependency Block',1,720,'seeds',720,'seedlings','seedling_care','active',
      v_hardening_date-60,v_hardening_date-60,v_transplant_date,v_transplant_date+5,
      v_today+45,v_today+75,array['conformance'],
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true,
        'hardening_start_date',v_hardening_date,'destination_program','reference_bed_1..3',
        'warning','Synthetic reference-company lot; not customer production truth.')
    ) returning id into v_lot_id;

    insert into atlas.crop_cycles(
      farm_id,object_id,crop_profile_id,crop_cycle_key,crop_label,variety,cycle_state,lifecycle_status,
      sown_date,germination_checked_date,coverage_kind,coverage_amount,coverage_unit,note,metadata
    ) values(
      v_farm.id,v_propagation_object_id,v_profile_id,'reference_dependency_cycle_'||replace(v_run_id::text,'-',''),
      'Reference Snapdragon','Dependency Block','seedling_care','active',v_hardening_date-60,v_hardening_date-50,
      'viable_seedlings',720,'seedlings','Synthetic reference-company dependency cohort.',
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)
    ) returning id into v_cycle_id;

    insert into atlas.production_tray_batches(
      farm_id,production_lot_id,crop_cycle_id,batch_number,batch_label,container_kind,block_size_in,
      seeds_sown,seed_unit,tray_count,status,sown_date,expected_germination_start,expected_germination_end,
      germinated_date,viable_seedlings,current_quantity,current_unit,idempotency_key,source_object_id,metadata
    ) values(
      v_farm.id,v_lot_id,v_cycle_id,1,'Reference Dependency Tray Batch','3/4-inch soil blocks',0.75,
      720,'seeds',4,'seedling_care',v_hardening_date-60,v_hardening_date-53,v_hardening_date-46,
      v_hardening_date-50,720,720,'seedlings','reference-dependency-tray:'||v_run_id::text,v_propagation_object_id,
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true,'pot_up_required',false)
    ) returning id into v_batch_id;

    insert into atlas.production_lot_crop_cycles(production_lot_id,crop_cycle_id,relation_role,confidence,source,metadata)
    values(v_lot_id,v_cycle_id,'propagation_batch','confirmed','reference_company_runner',jsonb_build_object('reference_run_id',v_run_id));

    insert into atlas.production_capacity_requirements(
      farm_id,production_lot_id,stable_key,stage_key,capacity_kind,quantity_needed,unit,
      required_by_date,window_start,window_end,preparation_due_date,calculation_status,source,metadata
    ) values(
      v_farm.id,v_lot_id,'reference_dependency_bed_feet','transplant','bed_feet',null,'bed_ft',
      v_transplant_date,v_transplant_date,v_transplant_date+5,v_transplant_date-1,'blocked','reference_company_runner',
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
    if v_hardening_task_id is null then raise exception 'Reference hardening task was not derived.' using errcode='23514'; end if;
    perform atlas.record_production_hardening_v1(
      v_hardening_task_id,v_hardening_date,'Reference dependency scenario hardening.',
      'reference-dependency-hardening:'||v_run_id::text
    );

    select id into v_readiness_occurrence_id
    from atlas.planned_work_occurrences
    where farm_id=v_farm.id and occurrence_key='production:transplant-readiness:'||v_batch_id::text
    order by created_at desc limit 1;
    if v_readiness_occurrence_id is not null then
      v_readiness_task_id:=nullif((atlas.materialize_specific_work_occurrence_v1(v_readiness_occurrence_id,v_transplant_date)->>'taskId'),'')::uuid;
    end if;
    if v_readiness_task_id is null then raise exception 'Reference readiness task was not derived.' using errcode='23514'; end if;

    update atlas.capacity_measurements
    set stable_key='reference_hidden_spacing_'||replace(v_run_id::text,'-',''),updated_at=now()
    where id=v_measurement_id;

    v_readiness_result:=atlas.record_production_readiness_v1(
      v_readiness_task_id,'ready',720,4,v_transplant_date,null,
      'Reference dependency scenario readiness with one capacity measurement intentionally unavailable.',
      'reference-dependency-readiness:'||v_run_id::text
    );

    select current_stage into v_stage from atlas.production_lots where id=v_lot_id;
    select status into v_batch_status from atlas.production_tray_batches where id=v_batch_id;
    select calculation_status,quantity_needed into v_calc_status,v_number from atlas.production_capacity_requirements where id=v_requirement_id;
    select id,gate_status into v_gate_id,v_gate_status from atlas.production_transplant_gates where production_lot_id=v_lot_id order by updated_at desc limit 1;
    select id into v_owner_math_occurrence_id from atlas.planned_work_occurrences
      where farm_id=v_farm.id and occurrence_key='production:owner-bed-math:'||v_lot_id::text order by created_at desc limit 1;
    select count(*) into v_count from atlas.planned_work_occurrences
      where farm_id=v_farm.id and v_gate_id is not null and occurrence_key='production:transplant:'||v_gate_id::text and state<>'cancelled';

    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','biology_persists_while_bed_math_unknown','passed',v_stage='transplant_ready' and v_batch_status='transplant_ready',
      'expected','lot+batch transplant_ready','actual',coalesce(v_stage,'null')||'+'||coalesce(v_batch_status,'null')));
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','unknown_bed_math_blocks_only_execution','passed',v_calc_status='blocked' and v_number is null and v_gate_status='waiting_bed_math' and v_count=0,
      'expected','blocked/null/waiting_bed_math/0 transplant occurrences',
      'actual',jsonb_build_object('calculationStatus',v_calc_status,'quantityNeeded',v_number,'gateStatus',v_gate_status,'transplantOccurrences',v_count)));
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','bed_math_decision_is_visible','passed',v_owner_math_occurrence_id is not null,'expected',true,'actual',v_owner_math_occurrence_id is not null));

    update atlas.capacity_measurements
    set stable_key='snapdragon_in_row_spacing_inches',updated_at=now()
    where id=v_measurement_id;

    select calculation_status,quantity_needed into v_calc_status,v_number from atlas.production_capacity_requirements where id=v_requirement_id;
    select gate_status into v_gate_status from atlas.production_transplant_gates where production_lot_id=v_lot_id order by updated_at desc limit 1;
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','restored_bed_math_self_heals_requirement','passed',v_calc_status in ('calculated','confirmed') and v_number=60 and v_gate_status='waiting_bed_assignment',
      'expected',jsonb_build_object('calculationStatus','confirmed','quantityNeeded',60,'gateStatus','waiting_bed_assignment'),
      'actual',jsonb_build_object('calculationStatus',v_calc_status,'quantityNeeded',v_number,'gateStatus',v_gate_status)));

    if not (v_calc_status in ('calculated','confirmed') and v_number=60) then
      select value into v_rows from atlas.capacity_measurements where farm_id=v_farm.id and stable_key='snapdragon_rows_per_three_foot_bed';
      select value into v_spacing from atlas.capacity_measurements where farm_id=v_farm.id and stable_key='snapdragon_in_row_spacing_inches';
      v_expected_bed_feet:=ceil((720*v_spacing/12.0)/v_rows);
      update atlas.production_capacity_requirements
      set quantity_needed=v_expected_bed_feet,calculation_status='confirmed',
          metadata=metadata||jsonb_build_object('reference_test_continuation_after_failed_self_heal',true),updated_at=now()
      where id=v_requirement_id;
      perform atlas.refresh_production_transplant_gate_v1(v_lot_id);
    end if;

    insert into atlas.production_bed_assignments(
      farm_id,production_lot_id,requirement_id,object_id,quantity_assigned,unit,planned_transplant_date,assignment_status,source,metadata
    ) values(
      v_farm.id,v_lot_id,v_requirement_id,v_bed_1,20,'bed_ft',v_transplant_date,'assigned','reference_company_runner',
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)
    ) returning id into v_assignment_1;
    v_reconcile:=atlas.reconcile_production_work_v1(v_lot_id,v_transplant_date);
    select gate_status,assigned_bed_feet,prepared_bed_feet into v_gate_status,v_assigned,v_prepared
      from atlas.production_transplant_gates where production_lot_id=v_lot_id order by updated_at desc limit 1;
    select count(*) into v_count from atlas.planned_work_occurrences
      where farm_id=v_farm.id and occurrence_key='production:bed-preparation:'||v_assignment_1::text and state<>'cancelled';
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','partial_assignment_remains_visible','passed',v_gate_status='waiting_bed_assignment' and v_assigned=20 and v_prepared=0 and v_count=1,
      'expected',jsonb_build_object('gateStatus','waiting_bed_assignment','assignedBedFeet',20,'preparedBedFeet',0,'bedPrepOccurrences',1),
      'actual',jsonb_build_object('gateStatus',v_gate_status,'assignedBedFeet',v_assigned,'preparedBedFeet',v_prepared,'bedPrepOccurrences',v_count)));

    insert into atlas.production_bed_assignments(
      farm_id,production_lot_id,requirement_id,object_id,quantity_assigned,unit,planned_transplant_date,assignment_status,source,metadata
    ) values
      (v_farm.id,v_lot_id,v_requirement_id,v_bed_2,20,'bed_ft',v_transplant_date,'assigned','reference_company_runner',jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)),
      (v_farm.id,v_lot_id,v_requirement_id,v_bed_3,20,'bed_ft',v_transplant_date,'assigned','reference_company_runner',jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true))
    returning id into v_assignment_2;
    select id into v_assignment_3 from atlas.production_bed_assignments
      where production_lot_id=v_lot_id and object_id=v_bed_3 and id<>v_assignment_2 order by created_at desc limit 1;
    if v_assignment_2 is null or v_assignment_3 is null then
      select id into v_assignment_2 from atlas.production_bed_assignments where production_lot_id=v_lot_id and object_id=v_bed_2 order by created_at desc limit 1;
      select id into v_assignment_3 from atlas.production_bed_assignments where production_lot_id=v_lot_id and object_id=v_bed_3 order by created_at desc limit 1;
    end if;

    v_reconcile:=atlas.reconcile_production_work_v1(v_lot_id,v_transplant_date);
    select gate_status,assigned_bed_feet,prepared_bed_feet,id into v_gate_status,v_assigned,v_prepared,v_gate_id
      from atlas.production_transplant_gates where production_lot_id=v_lot_id order by updated_at desc limit 1;
    select count(*) into v_count from atlas.planned_work_occurrences
      where farm_id=v_farm.id and occurrence_key='production:transplant:'||v_gate_id::text and state<>'cancelled';
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','unprepared_assigned_beds_block_transplant','passed',v_gate_status='waiting_bed_preparation' and v_assigned=60 and v_prepared=0 and v_count=0,
      'expected',jsonb_build_object('gateStatus','waiting_bed_preparation','assignedBedFeet',60,'preparedBedFeet',0,'transplantOccurrences',0),
      'actual',jsonb_build_object('gateStatus',v_gate_status,'assignedBedFeet',v_assigned,'preparedBedFeet',v_prepared,'transplantOccurrences',v_count)));

    for v_bed_prep_occurrence_id in
      select pwo.id from atlas.planned_work_occurrences pwo
      where pwo.farm_id=v_farm.id and pwo.occurrence_key in (
        'production:bed-preparation:'||v_assignment_1::text,
        'production:bed-preparation:'||v_assignment_2::text,
        'production:bed-preparation:'||v_assignment_3::text
      ) order by pwo.occurrence_key
    loop
      v_bed_prep_task_id:=nullif((atlas.materialize_specific_work_occurrence_v1(v_bed_prep_occurrence_id,v_transplant_date)->>'taskId'),'')::uuid;
      if v_bed_prep_task_id is null then raise exception 'Reference bed-preparation task did not materialize.' using errcode='23514'; end if;
      perform atlas.record_task_transition_v1_internal(
        v_bed_prep_task_id,'done',left('reference-dependency-bed-prep:'||v_run_id::text||':'||v_bed_prep_occurrence_id::text,160),
        null,'Synthetic dependency fixture bed preparation completed.',null,'prepare','bed_preparation',
        jsonb_build_object('reference_run_id',v_run_id,'system_fixture',true),null
      );
    end loop;

    select gate_status,assigned_bed_feet,prepared_bed_feet,id into v_gate_status,v_assigned,v_prepared,v_gate_id
      from atlas.production_transplant_gates where production_lot_id=v_lot_id order by updated_at desc limit 1;
    select count(*) into v_count from atlas.planned_work_occurrences
      where farm_id=v_farm.id and occurrence_key='production:transplant:'||v_gate_id::text and state<>'cancelled';
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','completed_preparation_self_heals_transplant_gate','passed',v_gate_status='ready' and v_prepared=60 and v_count=1,
      'expected',jsonb_build_object('gateStatus','ready','preparedBedFeet',60,'transplantOccurrences',1),
      'actual',jsonb_build_object('gateStatus',v_gate_status,'preparedBedFeet',v_prepared,'transplantOccurrences',v_count)));

    select current_stage into v_stage from atlas.production_lots where id=v_lot_id;
    select status into v_batch_status from atlas.production_tray_batches where id=v_batch_id;
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','biology_never_rolls_back_during_dependency_recovery','passed',v_stage='transplant_ready' and v_batch_status='transplant_ready',
      'expected','lot+batch transplant_ready','actual',coalesce(v_stage,'null')||'+'||coalesce(v_batch_status,'null')));

    perform atlas.reconcile_production_work_v1(v_lot_id,v_today);
    perform atlas.reconcile_production_work_v1(v_lot_id,v_today);
    select count(*) into v_count from (
      select occurrence_key from atlas.planned_work_occurrences
      where farm_id=v_farm.id and coalesce(metadata->>'production_lot_id','')=v_lot_id::text
      group by occurrence_key having count(*)>1
    ) d;
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object(
      'key','reconciliation_has_no_duplicate_occurrence_keys','passed',v_count=0,'expected',0,'actual',v_count));

    v_result:=jsonb_build_object(
      'fixtureRolledBack',true,
      'readinessResult',coalesce(v_readiness_result,'{}'::jsonb),
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
    return jsonb_build_object('contractVersion','run_reference_company_transplant_dependency_block_v1','runId',v_run_id,
      'scenarioKey','transplant_dependency_block_v1','status','failed','error',v_error,'fixtureRolledBack',true);
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
    'contractVersion','run_reference_company_transplant_dependency_block_v1','runId',v_run_id,
    'scenarioKey','transplant_dependency_block_v1','status',case when v_all_passed then 'passed' else 'failed' end,
    'fixtureRolledBack',true,'assertions',v_assertions
  );
end;
$function$;

revoke all on function atlas.run_reference_company_transplant_dependency_block_v1(text) from public,anon,authenticated;
grant execute on function atlas.run_reference_company_transplant_dependency_block_v1(text) to service_role;

update atlas.reference_company_scenarios
set expected_invariants=jsonb_build_array(
      'biology is not rolled back',
      'unknown bed math hard-blocks transplant',
      'partial assignment remains visible',
      'unprepared assigned beds prevent transplant',
      'resolved dependencies self-heal',
      'reconciliation creates no duplicates'
    ),
    metadata=metadata||jsonb_build_object(
      'implementation_state','executable',
      'runner','run_reference_company_transplant_dependency_block_v1',
      'runner_version',1,
      'fixture_contract','rollback_only'
    ),
    updated_at=now()
where stable_key='transplant_dependency_block_v1';