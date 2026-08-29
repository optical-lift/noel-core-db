create or replace function atlas.run_reference_company_completed_history_immutability_v1(p_source_revision text default null)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  s atlas.reference_company_scenarios%rowtype;
  f atlas.farms%rowtype;
  org_id uuid; profile_id uuid; propagation_id uuid; bed1 uuid; bed2 uuid; bed3 uuid;
  run_id uuid; token text; today date:=(now() at time zone 'America/Chicago')::date; future_due date:=today+3;
  program_id uuid; lot_id uuid; cycle_id uuid; batch_id uuid; evidence_task_id uuid; requirement_id uuid;
  a1 uuid; a2 uuid; a3 uuid; occurrence_id uuid; task_id uuid; transition_id uuid; actual_id uuid;
  materialized jsonb; actual_result jsonb; transition_result jsonb;
  before_task jsonb; after_task jsonb; before_occurrence jsonb; after_occurrence jsonb;
  before_transition jsonb; after_transition jsonb; before_actual jsonb; after_actual jsonb;
  future_count integer; future_recomputed integer; duplicates integer;
  assertions jsonb:='[]'::jsonb; fixture_completed boolean:=false; all_passed boolean:=false; err text;
begin
  select * into s from atlas.reference_company_scenarios where stable_key='completed_history_immutability_v1' and active;
  if s.id is null then raise exception 'Reference company completed-history scenario is unavailable.' using errcode='P0002'; end if;
  select * into f from atlas.farms where stable_key='atlas_reference_farm';
  if f.id is null or not atlas.is_system_fixture_farm_v1(f.id) then raise exception 'Atlas Reference Farm isolation contract is unavailable.' using errcode='23514'; end if;
  org_id:=f.organization_id;
  select id into profile_id from atlas.crop_profiles where stable_key='atlas_reference_snapdragon_golden_v1';
  select id into propagation_id from atlas.growing_objects where farm_id=f.id and stable_key='reference_propagation_bench';
  select id into bed1 from atlas.growing_objects where farm_id=f.id and stable_key='reference_bed_1';
  select id into bed2 from atlas.growing_objects where farm_id=f.id and stable_key='reference_bed_2';
  select id into bed3 from atlas.growing_objects where farm_id=f.id and stable_key='reference_bed_3';
  if profile_id is null or propagation_id is null or bed1 is null or bed2 is null or bed3 is null then raise exception 'Reference completed-history fixtures are incomplete.' using errcode='23514'; end if;

  token:='reference:completed_history_immutability_v1:'||replace(gen_random_uuid()::text,'-','');
  insert into atlas.reference_company_runs(scenario_id,farm_id,run_token,run_mode,status,source_revision,metadata)
  values(s.id,f.id,token,'transactional','running',p_source_revision,jsonb_build_object('fixtureVersion',s.fixture_version,'systemFixture',true,'runner','run_reference_company_completed_history_immutability_v1'))
  returning id into run_id;

  begin
    insert into atlas.production_programs(farm_id,stable_key,season_year,program_label,program_kind,promise_text,intended_uses,status,metadata)
    values(f.id,'reference_history_program_'||replace(run_id::text,'-',''),extract(year from today)::integer,'Reference completed history immutability','reference_fixture','Prove completed production work remains historical while future obligations reforecast.',array['conformance'],'active',jsonb_build_object('system_fixture',true,'reference_run_id',run_id,'synthetic_truth',true)) returning id into program_id;

    insert into atlas.production_lots(farm_id,program_id,crop_profile_id,stable_key,lot_label,succession_number,planned_input_quantity,planned_input_unit,current_quantity,current_unit,current_stage,lifecycle_status,planned_sow_date,actual_sow_date,expected_transplant_start,expected_transplant_end,expected_harvest_start,expected_harvest_end,intended_uses,metadata)
    values(f.id,program_id,profile_id,'reference_history_lot_'||replace(run_id::text,'-',''),'Reference Snapdragon · Completed History',1,720,'seeds',720,'seedlings','transplant_ready','active',today-65,today-65,today+5,today+8,today+45,today+75,array['conformance'],jsonb_build_object('system_fixture',true,'reference_run_id',run_id,'synthetic_truth',true,'warning','Synthetic reference-company lot; not customer production truth.')) returning id into lot_id;

    insert into atlas.crop_cycles(farm_id,object_id,crop_profile_id,crop_cycle_key,crop_label,variety,cycle_state,lifecycle_status,sown_date,germination_checked_date,coverage_kind,coverage_amount,coverage_unit,note,metadata)
    values(f.id,propagation_id,profile_id,'reference_history_cycle_'||replace(run_id::text,'-',''),'Reference Snapdragon','Completed History','transplant_ready','active',today-65,today-55,'viable_seedlings',720,'seedlings','Synthetic reference-company completed-history cohort.',jsonb_build_object('system_fixture',true,'reference_run_id',run_id,'synthetic_truth',true)) returning id into cycle_id;

    insert into atlas.production_tray_batches(farm_id,production_lot_id,crop_cycle_id,batch_number,batch_label,container_kind,block_size_in,seeds_sown,seed_unit,tray_count,status,sown_date,expected_germination_start,expected_germination_end,germinated_date,viable_seedlings,current_quantity,current_unit,idempotency_key,source_object_id,metadata)
    values(f.id,lot_id,cycle_id,1,'Reference History Tray Batch','3/4-inch soil blocks',0.75,720,'seeds',4,'transplant_ready',today-65,today-58,today-51,today-55,720,720,'seedlings','reference-history-tray:'||run_id::text,propagation_id,jsonb_build_object('system_fixture',true,'reference_run_id',run_id,'synthetic_truth',true,'pot_up_required',false)) returning id into batch_id;

    insert into atlas.production_lot_crop_cycles(production_lot_id,crop_cycle_id,relation_role,confidence,source,metadata)
    values(lot_id,cycle_id,'propagation_batch','confirmed','reference_company_runner',jsonb_build_object('reference_run_id',run_id));

    insert into atlas.tasks(farm_id,title,task_type,action_key,work_class,status,priority,due_date,visibility_scope,note,organization_id,metadata)
    values(f.id,'Reference counted transplant readiness','observation','observe','production_readiness','done','normal',today,'system_internal','Synthetic counted readiness evidence for completed-history conformance.',org_id,jsonb_build_object('system_fixture',true,'reference_run_id',run_id,'synthetic_truth',true)) returning id into evidence_task_id;
    insert into atlas.production_lot_tasks(production_lot_id,task_id,link_role,source,metadata)
    values(lot_id,evidence_task_id,'transplant_readiness','reference_company_runner',jsonb_build_object('reference_run_id',run_id,'system_fixture',true));
    insert into atlas.production_readiness_observations(farm_id,production_lot_id,tray_batch_id,task_id,observation_outcome,observed_date,surviving_seedlings,tray_count,confidence,note,idempotency_key,metadata)
    values(f.id,lot_id,batch_id,evidence_task_id,'ready',today,720,4,'counted','Synthetic counted readiness evidence.','reference-history-readiness:'||run_id::text,jsonb_build_object('system_fixture',true,'reference_run_id',run_id,'synthetic_truth',true));

    insert into atlas.production_capacity_requirements(farm_id,production_lot_id,stable_key,stage_key,capacity_kind,quantity_needed,unit,required_by_date,window_start,window_end,preparation_due_date,calculation_status,source,metadata)
    values(f.id,lot_id,'reference_history_bed_feet','transplant','bed_feet',60,'bed_ft',today+5,today+5,today+8,today,'confirmed','reference_company_runner',jsonb_build_object('system_fixture',true,'reference_run_id',run_id,'synthetic_truth',true)) returning id into requirement_id;

    insert into atlas.production_bed_assignments(farm_id,production_lot_id,requirement_id,object_id,quantity_assigned,unit,planned_transplant_date,assignment_status,source,metadata) values
      (f.id,lot_id,requirement_id,bed1,20,'bed_ft',today+5,'assigned','reference_company_runner',jsonb_build_object('system_fixture',true,'reference_run_id',run_id,'synthetic_truth',true)),
      (f.id,lot_id,requirement_id,bed2,20,'bed_ft',today+5,'assigned','reference_company_runner',jsonb_build_object('system_fixture',true,'reference_run_id',run_id,'synthetic_truth',true)),
      (f.id,lot_id,requirement_id,bed3,20,'bed_ft',today+5,'assigned','reference_company_runner',jsonb_build_object('system_fixture',true,'reference_run_id',run_id,'synthetic_truth',true));
    select id into a1 from atlas.production_bed_assignments where production_lot_id=lot_id and object_id=bed1;
    select id into a2 from atlas.production_bed_assignments where production_lot_id=lot_id and object_id=bed2;
    select id into a3 from atlas.production_bed_assignments where production_lot_id=lot_id and object_id=bed3;

    perform atlas.reconcile_production_work_v1(lot_id,today);
    select id into occurrence_id from atlas.planned_work_occurrences where farm_id=f.id and occurrence_key='production:bed-preparation:'||a1::text order by created_at limit 1;
    if occurrence_id is null then raise exception 'Reference completed-history occurrence was not derived.' using errcode='23514'; end if;
    materialized:=atlas.materialize_specific_work_occurrence_v1(occurrence_id,today);
    task_id:=nullif(materialized->>'taskId','')::uuid;
    if task_id is null then raise exception 'Reference completed-history occurrence did not materialize a task: %',materialized using errcode='23514'; end if;

    actual_result:=atlas.record_production_operation_actual_v1(task_id,37,20,'bed_ft',today,'Reference bed preparation completed at original plan.','reference-history-actual:'||run_id::text);
    actual_id:=nullif(actual_result->>'actualId','')::uuid;
    transition_result:=atlas.record_task_transition_v1_internal_legacy(task_id,'done','reference-history-done:'||run_id::text,null,'Prepared 20 bed-ft under the original plan.',null,'process_continuation','bed-preparation',jsonb_build_object('actual_minutes',37,'prepared_bed_feet',20,'condition','ready','reference_marker','completed_history_immutability_v1'),null);
    transition_id:=nullif(transition_result->>'transitionId','')::uuid;

    select to_jsonb(t) into before_task from atlas.tasks t where id=task_id;
    select to_jsonb(o) into before_occurrence from atlas.planned_work_occurrences o where id=occurrence_id;
    select to_jsonb(tt) into before_transition from atlas.task_transitions tt where id=transition_id;
    select to_jsonb(a) into before_actual from atlas.production_operation_actuals a where id=actual_id;

    update atlas.production_capacity_requirements set preparation_due_date=future_due,required_by_date=today+7,window_start=today+7,window_end=today+10,metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('reference_plan_revision','shifted_after_completed_history'),updated_at=now() where id=requirement_id;
    update atlas.production_bed_assignments set planned_transplant_date=today+7,metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('reference_plan_revision','shifted_after_completed_history'),updated_at=now() where production_lot_id=lot_id;
    perform atlas.reconcile_production_work_v1(lot_id,today);

    select to_jsonb(t) into after_task from atlas.tasks t where id=task_id;
    select to_jsonb(o) into after_occurrence from atlas.planned_work_occurrences o where id=occurrence_id;
    select to_jsonb(tt) into after_transition from atlas.task_transitions tt where id=transition_id;
    select to_jsonb(a) into after_actual from atlas.production_operation_actuals a where id=actual_id;

    select count(*) into future_count from atlas.planned_work_occurrences o where o.farm_id=f.id and o.occurrence_key in ('production:bed-preparation:'||a2::text,'production:bed-preparation:'||a3::text) and o.state<>'cancelled';
    select count(*) into future_recomputed from atlas.planned_work_occurrences o where o.farm_id=f.id and o.occurrence_key in ('production:bed-preparation:'||a2::text,'production:bed-preparation:'||a3::text) and o.planned_due_date=future_due and o.task_payload->'metadata'->>'target_transplant_date'=(today+7)::text and o.state in ('planned','eligible','released');
    select count(*) into duplicates from (select occurrence_key from atlas.planned_work_occurrences where farm_id=f.id and coalesce(metadata->>'production_lot_id','')=lot_id::text group by occurrence_key having count(*)>1) d;

    assertions:=assertions||jsonb_build_array(jsonb_build_object('key','completed_work_remains_completed_and_frozen','passed',before_task=after_task and before_occurrence=after_occurrence and after_task->>'status'='done' and after_occurrence->>'state'='completed','expected',jsonb_build_object('taskUnchanged',true,'occurrenceUnchanged',true,'taskStatus','done','occurrenceState','completed'),'actual',jsonb_build_object('taskUnchanged',before_task=after_task,'occurrenceUnchanged',before_occurrence=after_occurrence,'taskStatus',after_task->>'status','occurrenceState',after_occurrence->>'state','completedDueDate',after_occurrence->>'planned_due_date')));
    assertions:=assertions||jsonb_build_array(jsonb_build_object('key','historical_result_payload_is_unchanged','passed',before_transition=after_transition and before_actual=after_actual,'expected',jsonb_build_object('transitionUnchanged',true,'operationActualUnchanged',true),'actual',jsonb_build_object('transitionUnchanged',before_transition=after_transition,'operationActualUnchanged',before_actual=after_actual)));
    assertions:=assertions||jsonb_build_array(jsonb_build_object('key','only_future_obligations_are_recomputed','passed',future_count=2 and future_recomputed=2 and duplicates=0 and (after_occurrence->>'planned_due_date')::date=today,'expected',jsonb_build_object('futureOccurrences',2,'futureRecomputed',2,'duplicateOccurrenceKeys',0,'completedDueDate',today),'actual',jsonb_build_object('futureOccurrences',future_count,'futureRecomputed',future_recomputed,'duplicateOccurrenceKeys',duplicates,'completedDueDate',after_occurrence->>'planned_due_date','newFutureDueDate',future_due)));
    raise exception 'REFERENCE_FIXTURE_ROLLBACK' using errcode='P9001';
  exception when sqlstate 'P9001' then fixture_completed:=true; when others then get stacked diagnostics err=message_text; fixture_completed:=false; end;

  if not fixture_completed then
    update atlas.reference_company_runs set status='failed',completed_at=now(),error_text=err,result=jsonb_build_object('fixtureRolledBack',true,'runnerError',err) where id=run_id;
    return jsonb_build_object('contractVersion','run_reference_company_completed_history_immutability_v1','runId',run_id,'scenarioKey','completed_history_immutability_v1','status','failed','error',err,'fixtureRolledBack',true);
  end if;

  insert into atlas.reference_company_assertions(run_id,assertion_key,passed,expected,actual,detail)
  select run_id,x->>'key',coalesce((x->>'passed')::boolean,false),jsonb_build_object('value',x->'expected'),jsonb_build_object('value',x->'actual'),null from jsonb_array_elements(assertions) x;
  select coalesce(bool_and(passed),false) into all_passed from atlas.reference_company_assertions where run_id=run_id;
  update atlas.reference_company_runs set status=case when all_passed then 'passed' else 'failed' end,completed_at=now(),result=jsonb_build_object('fixtureRolledBack',true,'assertionCount',jsonb_array_length(assertions),'assertions',assertions,'allPassed',all_passed),error_text=case when all_passed then null else 'One or more conformance assertions failed.' end where id=run_id;
  return jsonb_build_object('contractVersion','run_reference_company_completed_history_immutability_v1','runId',run_id,'scenarioKey','completed_history_immutability_v1','status',case when all_passed then 'passed' else 'failed' end,'fixtureRolledBack',true,'assertions',assertions);
end;
$function$;

update atlas.reference_company_scenarios
set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('runner','run_reference_company_completed_history_immutability_v1','runner_version',1,'implementation_state','executable','fixture_contract','rollback_only'),updated_at=now()
where stable_key='completed_history_immutability_v1';