insert into atlas.growing_objects(farm_id,zone_id,stable_key,label,object_type,object_mode,guest_visible,sort_order,metadata)
select f.id,z.id,'reference_propagation_bench','Reference Propagation Bench','seed_room','production',false,10,
       jsonb_build_object('system_fixture',true,'synthetic_truth',true,'reference_company_version',1,'fixture_role','propagation_location')
from atlas.farms f
join atlas.zones z on z.farm_id=f.id and z.stable_key='reference_propagation_room'
where f.stable_key='atlas_reference_farm'
on conflict(farm_id,stable_key) do update set
  zone_id=excluded.zone_id,label=excluded.label,object_type='seed_room',object_mode='production',metadata=atlas.growing_objects.metadata||excluded.metadata,updated_at=now();

insert into atlas.reference_company_fixture_registry(farm_id,fixture_key,entity_kind,entity_id,entity_stable_key,role,metadata)
select f.id,'propagation:reference_propagation_bench','growing_object',go.id,go.stable_key,'propagation_location',jsonb_build_object('system_fixture',true)
from atlas.farms f join atlas.growing_objects go on go.farm_id=f.id and go.stable_key='reference_propagation_bench'
where f.stable_key='atlas_reference_farm'
on conflict(farm_id,fixture_key) do update set entity_id=excluded.entity_id,entity_stable_key=excluded.entity_stable_key,role=excluded.role,metadata=atlas.reference_company_fixture_registry.metadata||excluded.metadata,updated_at=now();

create or replace function atlas.run_reference_company_scenario_v1(
  p_scenario_key text,
  p_source_revision text default null
)
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
  v_transplant_occurrence_id uuid;
  v_transplant_task_id uuid;
  v_establishment_occurrence_id uuid;
  v_establishment_task_id uuid;
  v_gate_id uuid;
  v_gate_before_transplant text;
  v_assignments uuid[]:='{}'::uuid[];
  v_assignment_id uuid;
  v_bed record;
  v_occ record;
  v_placements jsonb:='[]'::jsonb;
  v_stands jsonb:='[]'::jsonb;
  v_reconcile jsonb;
  v_hardening_result jsonb;
  v_readiness_result jsonb;
  v_transplant_result jsonb;
  v_establishment_result jsonb;
  v_assertions jsonb:='[]'::jsonb;
  v_result jsonb:='{}'::jsonb;
  v_fixture_completed boolean:=false;
  v_all_passed boolean:=false;
  v_error text;
  v_count integer;
  v_number numeric;
  v_text text;
begin
  select * into v_scenario from atlas.reference_company_scenarios where stable_key=p_scenario_key and active;
  if v_scenario.id is null then
    raise exception 'Reference company scenario was not found: %',p_scenario_key using errcode='P0002';
  end if;
  if p_scenario_key<>'propagation_golden_path_v1' then
    raise exception 'Reference company scenario is cataloged but not executable yet: %',p_scenario_key using errcode='22023';
  end if;

  select * into v_farm from atlas.farms where stable_key='atlas_reference_farm';
  if v_farm.id is null or not atlas.is_system_fixture_farm_v1(v_farm.id) then
    raise exception 'Atlas Reference Farm isolation contract is unavailable.' using errcode='23514';
  end if;
  select organization_id into v_org_id from atlas.farms where id=v_farm.id;
  select id into v_profile_id from atlas.crop_profiles where stable_key='atlas_reference_snapdragon_golden_v1';
  select id into v_propagation_object_id from atlas.growing_objects where farm_id=v_farm.id and stable_key='reference_propagation_bench';
  if v_profile_id is null then raise exception 'Reference propagation profile is unavailable.' using errcode='23514'; end if;
  if v_propagation_object_id is null then raise exception 'Reference propagation object is unavailable.' using errcode='23514'; end if;

  v_run_token:='reference:'||p_scenario_key||':'||replace(gen_random_uuid()::text,'-','');
  insert into atlas.reference_company_runs(scenario_id,farm_id,run_token,run_mode,status,source_revision,metadata)
  values(v_scenario.id,v_farm.id,v_run_token,'transactional','running',p_source_revision,
         jsonb_build_object('fixtureVersion',v_scenario.fixture_version,'systemFixture',true,'runner','run_reference_company_scenario_v1'))
  returning id into v_run_id;

  begin
    insert into atlas.production_programs(
      farm_id,stable_key,season_year,program_label,program_kind,promise_text,intended_uses,status,metadata
    ) values(
      v_farm.id,'reference_program_'||replace(v_run_id::text,'-',''),extract(year from v_today)::integer,
      'Reference propagation golden path','reference_fixture',
      'Exercise the complete synthetic transplant-start production path.',array['conformance'],'active',
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)
    ) returning id into v_program_id;

    insert into atlas.production_lots(
      farm_id,program_id,crop_profile_id,stable_key,lot_label,succession_number,
      planned_input_quantity,planned_input_unit,current_quantity,current_unit,current_stage,lifecycle_status,
      planned_sow_date,actual_sow_date,expected_transplant_start,expected_transplant_end,
      expected_harvest_start,expected_harvest_end,intended_uses,metadata
    ) values(
      v_farm.id,v_program_id,v_profile_id,'reference_lot_'||replace(v_run_id::text,'-',''),
      'Reference Snapdragon · Golden Path',1,720,'seeds',720,'seedlings','seedling_care','active',
      v_hardening_date-60,v_hardening_date-60,v_transplant_date,v_transplant_date+5,
      v_today+45,v_today+75,array['conformance'],
      jsonb_build_object(
        'system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true,
        'hardening_start_date',v_hardening_date,'destination_program','reference_bed_1..3',
        'warning','Synthetic reference-company lot; not customer production truth.'
      )
    ) returning id into v_lot_id;

    insert into atlas.crop_cycles(
      farm_id,object_id,crop_profile_id,crop_cycle_key,crop_label,variety,cycle_state,lifecycle_status,
      sown_date,germination_checked_date,coverage_kind,coverage_amount,coverage_unit,note,metadata
    ) values(
      v_farm.id,v_propagation_object_id,v_profile_id,'reference_cycle_'||replace(v_run_id::text,'-',''),
      'Reference Snapdragon','Golden Path','seedling_care','active',v_hardening_date-60,v_hardening_date-50,
      'viable_seedlings',720,'seedlings','Synthetic reference-company propagation cohort.',
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)
    ) returning id into v_cycle_id;

    insert into atlas.production_tray_batches(
      farm_id,production_lot_id,crop_cycle_id,batch_number,batch_label,container_kind,block_size_in,
      seeds_sown,seed_unit,tray_count,status,sown_date,expected_germination_start,expected_germination_end,
      germinated_date,viable_seedlings,current_quantity,current_unit,idempotency_key,source_object_id,metadata
    ) values(
      v_farm.id,v_lot_id,v_cycle_id,1,'Reference Snapdragon Tray Batch','3/4-inch soil blocks',0.75,
      720,'seeds',4,'seedling_care',v_hardening_date-60,v_hardening_date-53,v_hardening_date-46,
      v_hardening_date-50,720,720,'seedlings','reference-tray:'||v_run_id::text,v_propagation_object_id,
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true,'pot_up_required',false)
    ) returning id into v_batch_id;

    insert into atlas.production_lot_crop_cycles(production_lot_id,crop_cycle_id,relation_role,confidence,source,metadata)
    values(v_lot_id,v_cycle_id,'propagation_batch','confirmed','reference_company_runner',jsonb_build_object('reference_run_id',v_run_id));

    insert into atlas.production_capacity_requirements(
      farm_id,production_lot_id,stable_key,stage_key,capacity_kind,quantity_needed,unit,
      required_by_date,window_start,window_end,preparation_due_date,calculation_status,source,metadata
    ) values(
      v_farm.id,v_lot_id,'reference_bed_feet','transplant','bed_feet',null,'bed_ft',
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
    if v_hardening_task_id is not null then
      v_hardening_result:=atlas.record_production_hardening_v1(
        v_hardening_task_id,v_hardening_date,'Reference company golden-path hardening.',
        'reference-hardening:'||v_run_id::text
      );
    end if;

    select id into v_readiness_occurrence_id
    from atlas.planned_work_occurrences
    where farm_id=v_farm.id and occurrence_key='production:transplant-readiness:'||v_batch_id::text
    order by created_at desc limit 1;
    if v_readiness_occurrence_id is not null then
      v_readiness_task_id:=nullif((atlas.materialize_specific_work_occurrence_v1(v_readiness_occurrence_id,v_transplant_date)->>'taskId'),'')::uuid;
    end if;
    if v_readiness_task_id is not null then
      v_readiness_result:=atlas.record_production_readiness_v1(
        v_readiness_task_id,'ready',720,4,v_transplant_date,null,
        'Reference company golden-path readiness.','reference-readiness:'||v_run_id::text
      );
    end if;

    for v_bed in
      select go.id,go.stable_key from atlas.growing_objects go
      where go.farm_id=v_farm.id and go.stable_key in ('reference_bed_1','reference_bed_2','reference_bed_3')
      order by go.stable_key
    loop
      insert into atlas.production_bed_assignments(
        farm_id,production_lot_id,requirement_id,object_id,quantity_assigned,unit,planned_transplant_date,assignment_status,source,metadata
      ) values(
        v_farm.id,v_lot_id,v_requirement_id,v_bed.id,20,'bed_ft',v_transplant_date,'assigned','reference_company_runner',
        jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)
      ) returning id into v_assignment_id;
      v_assignments:=array_append(v_assignments,v_assignment_id);
      v_placements:=v_placements||jsonb_build_array(jsonb_build_object('assignmentId',v_assignment_id,'plants',240));
    end loop;

    v_reconcile:=atlas.reconcile_production_work_v1(v_lot_id,v_transplant_date);

    for v_occ in
      select pwo.id
      from atlas.planned_work_occurrences pwo
      where pwo.farm_id=v_farm.id
        and pwo.occurrence_key like 'production:bed-preparation:%'
        and pwo.source_id=any(v_assignments)
      order by pwo.occurrence_key
    loop
      v_text:=atlas.materialize_specific_work_occurrence_v1(v_occ.id,v_transplant_date)->>'taskId';
      if nullif(v_text,'') is not null then
        perform atlas.record_task_transition_v1_internal(
          v_text::uuid,'done','reference-bed-prep:'||v_run_id::text||':'||v_occ.id::text,
          null,'Synthetic fixture bed preparation completed.',null,'prepare','bed_preparation',
          jsonb_build_object('reference_run_id',v_run_id,'system_fixture',true),null
        );
      end if;
    end loop;

    v_reconcile:=atlas.reconcile_production_work_v1(v_lot_id,v_transplant_date);
    select gate_status,id into v_gate_before_transplant,v_gate_id
    from atlas.production_transplant_gates where production_lot_id=v_lot_id order by updated_at desc limit 1;
    select id into v_transplant_occurrence_id
    from atlas.planned_work_occurrences
    where farm_id=v_farm.id and occurrence_key='production:transplant:'||v_gate_id::text
    order by created_at desc limit 1;
    if v_transplant_occurrence_id is not null then
      v_transplant_task_id:=nullif((atlas.materialize_specific_work_occurrence_v1(v_transplant_occurrence_id,v_transplant_date)->>'taskId'),'')::uuid;
    end if;
    if v_transplant_task_id is not null then
      v_transplant_result:=atlas.record_production_transplant_v1(
        v_transplant_task_id,v_placements,v_transplant_date,'Reference company golden-path transplant.',
        'reference-transplant:'||v_run_id::text
      );
    end if;

    select id into v_establishment_occurrence_id
    from atlas.planned_work_occurrences
    where farm_id=v_farm.id and occurrence_key='production:establishment:'||v_gate_id::text
    order by created_at desc limit 1;
    if v_establishment_occurrence_id is not null then
      v_establishment_task_id:=nullif((atlas.materialize_specific_work_occurrence_v1(v_establishment_occurrence_id,v_today)->>'taskId'),'')::uuid;
    end if;

    select coalesce(jsonb_agg(jsonb_build_object(
      'placementId',p.id,
      'plantsAlive',p.plants_transplanted,
      'waterStatus',case go.stable_key when 'reference_bed_1' then 'needs_water' else 'adequate' end,
      'weedPressure',case go.stable_key when 'reference_bed_1' then 'moderate' when 'reference_bed_3' then 'heavy' else 'clear' end
    ) order by go.stable_key),'[]'::jsonb)
    into v_stands
    from atlas.production_transplant_placements p
    join atlas.growing_objects go on go.id=p.object_id
    where p.production_lot_id=v_lot_id;

    if v_establishment_task_id is not null then
      v_establishment_result:=atlas.record_production_establishment_v1(
        v_establishment_task_id,v_stands,'established',v_today,null,
        'Reference company golden-path establishment.','reference-establishment:'||v_run_id::text
      );
    end if;

    perform atlas.reconcile_production_work_v1(v_lot_id,v_today);
    perform atlas.reconcile_production_work_v1(v_lot_id,v_today);

    select count(*) into v_count from atlas.planned_work_occurrences
    where farm_id=v_farm.id and occurrence_key='production:hardening:'||v_batch_id::text;
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('key','hardening_derived_once','passed',v_count=1,'expected',1,'actual',v_count));

    select count(*) into v_count from atlas.planned_work_occurrences
    where farm_id=v_farm.id and occurrence_key='production:pot-up:'||v_batch_id::text and state<>'cancelled';
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('key','no_pot_up_created','passed',v_count=0,'expected',0,'actual',v_count));

    select container_kind into v_text from atlas.production_tray_batches where id=v_batch_id;
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('key','container_persists','passed',v_text='3/4-inch soil blocks','expected','3/4-inch soil blocks','actual',v_text));

    select quantity_needed into v_number from atlas.production_capacity_requirements where id=v_requirement_id;
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('key','synthetic_bed_math_60_ft','passed',v_number=60,'expected',60,'actual',v_number));

    select count(*) into v_count from atlas.planned_work_occurrences
    where farm_id=v_farm.id and occurrence_key like 'production:bed-preparation:%' and source_id=any(v_assignments);
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('key','three_bed_prep_obligations','passed',v_count=3,'expected',3,'actual',v_count));

    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('key','transplant_gate_ready_after_prep','passed',v_gate_before_transplant='ready','expected','ready','actual',v_gate_before_transplant));

    select count(*) into v_count from atlas.planned_work_occurrences where id=v_transplant_occurrence_id;
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('key','one_transplant_occurrence','passed',v_count=1,'expected',1,'actual',v_count));

    select count(*) into v_count from atlas.production_field_stands where production_lot_id=v_lot_id;
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('key','three_field_stands_created','passed',v_count=3,'expected',3,'actual',v_count));

    select current_stage into v_text from atlas.production_lots where id=v_lot_id;
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('key','establishment_reaches_field_care','passed',v_text='field_care','expected','field_care','actual',v_text));

    select count(*) into v_count from atlas.planned_work_occurrences
    where farm_id=v_farm.id and occurrence_key='production:field-water:'||v_lot_id::text||':'||v_today::text and state<>'cancelled';
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('key','water_need_derives_once','passed',v_count=1,'expected',1,'actual',v_count));

    select count(*) into v_count from atlas.planned_work_occurrences
    where farm_id=v_farm.id and occurrence_key='production:field-weed:'||v_lot_id::text||':'||v_today::text and state<>'cancelled';
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('key','weed_need_derives_once','passed',v_count=1,'expected',1,'actual',v_count));

    select count(*) into v_count from (
      select occurrence_key from atlas.planned_work_occurrences
      where farm_id=v_farm.id and coalesce(metadata->>'production_lot_id','')=v_lot_id::text
      group by occurrence_key having count(*)>1
    ) d;
    v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('key','reconciliation_has_no_duplicate_occurrence_keys','passed',v_count=0,'expected',0,'actual',v_count));

    v_result:=jsonb_build_object(
      'fixtureRolledBack',true,
      'hardeningResult',coalesce(v_hardening_result,'{}'::jsonb),
      'readinessResult',coalesce(v_readiness_result,'{}'::jsonb),
      'transplantResult',coalesce(v_transplant_result,'{}'::jsonb),
      'establishmentResult',coalesce(v_establishment_result,'{}'::jsonb),
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
    return jsonb_build_object('contractVersion','run_reference_company_scenario_v1','runId',v_run_id,'scenarioKey',p_scenario_key,'status','failed','error',v_error,'fixtureRolledBack',true);
  end if;

  insert into atlas.reference_company_assertions(run_id,assertion_key,passed,expected,actual,detail)
  select v_run_id,
         x->>'key',
         coalesce((x->>'passed')::boolean,false),
         jsonb_build_object('value',x->'expected'),
         jsonb_build_object('value',x->'actual'),
         null
  from jsonb_array_elements(v_assertions) x;

  select coalesce(bool_and(passed),false) into v_all_passed
  from atlas.reference_company_assertions where run_id=v_run_id;

  update atlas.reference_company_runs
  set status=case when v_all_passed then 'passed' else 'failed' end,
      completed_at=now(),
      result=v_result||jsonb_build_object('assertions',v_assertions,'allPassed',v_all_passed),
      error_text=case when v_all_passed then null else 'One or more conformance assertions failed.' end
  where id=v_run_id;

  return jsonb_build_object(
    'contractVersion','run_reference_company_scenario_v1',
    'runId',v_run_id,
    'scenarioKey',p_scenario_key,
    'status',case when v_all_passed then 'passed' else 'failed' end,
    'fixtureRolledBack',true,
    'assertions',v_assertions
  );
end;
$function$;