create or replace function atlas.run_reference_company_direct_sow_golden_path_v1(p_source_revision text default null)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  v_scenario atlas.reference_company_scenarios%rowtype;
  v_farm atlas.farms%rowtype;
  v_profile atlas.crop_profiles%rowtype;
  v_bed_id uuid;
  v_run_id uuid;
  v_run_token text;
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_sow_date date := ((now() at time zone 'America/Chicago')::date)-80;
  v_sow_task_id uuid;
  v_cycle_id uuid;
  v_germ_task_id uuid;
  v_watch_task_id uuid;
  v_finish_task_id uuid;
  v_clear_task_id uuid;
  v_req_id uuid;
  v_projection jsonb;
  v_continuity jsonb;
  v_pre_post jsonb;
  v_post_disposition jsonb;
  v_final_post jsonb;
  v_harvest_result jsonb;
  v_assertions jsonb := '[]'::jsonb;
  v_result jsonb := '{}'::jsonb;
  v_fixture_completed boolean := false;
  v_all_passed boolean := false;
  v_error text;
  v_count integer;
  v_text text;
begin
  select * into v_scenario from atlas.reference_company_scenarios
  where stable_key='direct_sow_golden_path_v1' and active;
  if v_scenario.id is null then
    raise exception 'Reference company direct-sow scenario is unavailable.' using errcode='P0002';
  end if;

  select * into v_farm from atlas.farms where stable_key='atlas_reference_farm';
  if v_farm.id is null or not atlas.is_system_fixture_farm_v1(v_farm.id) then
    raise exception 'Atlas Reference Farm isolation contract is unavailable.' using errcode='23514';
  end if;

  select * into v_profile from atlas.crop_profiles where stable_key='black_oil_sunflower';
  select id into v_bed_id from atlas.growing_objects where farm_id=v_farm.id and stable_key='reference_bed_1';
  if v_profile.id is null or v_profile.default_planting_method<>'direct_sow' or v_bed_id is null then
    raise exception 'Reference direct-sow fixtures are incomplete.' using errcode='23514';
  end if;

  v_run_token := 'reference:direct_sow_golden_path_v1:'||replace(gen_random_uuid()::text,'-','');
  insert into atlas.reference_company_runs(scenario_id,farm_id,run_token,run_mode,status,source_revision,metadata)
  values(v_scenario.id,v_farm.id,v_run_token,'transactional','running',p_source_revision,
    jsonb_build_object('fixtureVersion',v_scenario.fixture_version,'systemFixture',true,'runner','run_reference_company_direct_sow_golden_path_v1'))
  returning id into v_run_id;

  begin
    insert into atlas.tasks(
      farm_id,title,task_type,action_key,work_class,status,priority,due_date,visibility_scope,note,metadata
    ) values(
      v_farm.id,'Reference direct sow — Black Oil Sunflower','sowing','sow','crop_cycle','open','normal',v_sow_date,'system_internal',
      'Synthetic Reference Company direct-sow fixture.',
      jsonb_build_object(
        'system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true,
        'crop_profile_id',v_profile.id,'crop_profile_stable_key',v_profile.stable_key,
        'crop_label',v_profile.crop_label,'variety',v_profile.variety,
        'destination_object_id',v_bed_id,'default_planting_method','direct_sow',
        'actual_sow_date',v_sow_date,'warning','Synthetic Reference Company task; not customer production truth.'
      )
    ) returning id,metadata into v_sow_task_id,v_projection;

    insert into atlas.task_objects(task_id,object_id,role)
    values(v_sow_task_id,v_bed_id,'target') on conflict do nothing;

    select id into v_cycle_id from atlas.crop_cycles
    where source_task_id=v_sow_task_id and object_id=v_bed_id order by created_at limit 1;
    if v_cycle_id is null then raise exception 'Direct-sow planned crop cycle was not derived.' using errcode='23514'; end if;

    select disposition into v_text from atlas.v_crop_lifecycle_contract_v1
    where crop_profile_id=v_profile.id and stage_key='transplant' limit 1;
    v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
      'key','direct_sow_lifecycle_declares_transplant_not_applicable','passed',v_text='not_applicable',
      'expected','not_applicable','actual',v_text));

    v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
      'key','sow_projection_omits_transplant','passed',
        coalesce(v_projection->>'default_planting_method','')='direct_sow'
        and nullif(v_projection->>'projected_transplant_start','') is null
        and nullif(v_projection->>'projected_transplant_end','') is null
        and not exists(select 1 from jsonb_array_elements_text(coalesce(v_projection->'projection_detail_lines','[]'::jsonb)) x where lower(x) like '%transplant%'),
      'expected','direct_sow with null transplant projections and no transplant detail line',
      'actual',jsonb_build_object('plantingMethod',v_projection->>'default_planting_method','transplantStart',v_projection->>'projected_transplant_start','transplantEnd',v_projection->>'projected_transplant_end','detailLines',v_projection->'projection_detail_lines')));

    perform atlas.record_task_transition_v1_internal(
      v_sow_task_id,'done','reference-direct-sow:'||v_run_id::text,null,
      'Reference direct sow completed.',null,'sow','direct_sow',
      jsonb_build_object('reference_run_id',v_run_id,'system_fixture',true,'physical_effective_date',v_sow_date),null
    );

    update atlas.crop_cycles set
      sown_date=v_sow_date,
      expected_germination_start=v_sow_date+coalesce(v_profile.days_to_germination_min,7),
      expected_germination_end=v_sow_date+coalesce(v_profile.days_to_germination_max,14),
      expected_harvest_watch_start=v_sow_date+coalesce(v_profile.days_to_harvest_watch_min,55),
      expected_harvest_watch_end=v_sow_date+coalesce(v_profile.days_to_harvest_watch_max,75),
      expected_clear_date=v_sow_date+coalesce(v_profile.clear_offset_days,75),
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('reference_run_id',v_run_id,'system_fixture',true,'synthetic_time_progression',true),
      updated_at=now()
    where id=v_cycle_id;

    select t.id into v_germ_task_id
    from atlas.tasks t join atlas.task_crop_cycles tc on tc.task_id=t.id
    where tc.crop_cycle_id=v_cycle_id and t.task_type='germination_check' and t.status in ('open','blocked')
    order by t.created_at desc limit 1;
    if v_germ_task_id is null then raise exception 'Direct-sow germination observation carrier was not derived.' using errcode='23514'; end if;

    perform atlas.emit_germination_observation_v1(v_germ_task_id,'germinated','Synthetic Reference Company physical germination observation.');
    perform atlas.record_task_transition_v1_internal(
      v_germ_task_id,'done','reference-direct-germination:'||v_run_id::text,null,
      'Synthetic physical germination observed.',null,'observe','germination_check',
      jsonb_build_object('reference_run_id',v_run_id,'system_fixture',true,'physicalObservationRecorded',true,'timeClaimsPhysicalCondition',false),null
    );

    select cycle_state into v_text from atlas.crop_cycles where id=v_cycle_id;
    v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
      'key','physical_germination_observation_advances_biology','passed',v_text='germinated',
      'expected','germinated','actual',v_text));

    v_continuity := atlas.crop_cycle_stage_continuity_state_v1(v_cycle_id,v_today);
    v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
      'key','germination_observation_derives_lawful_care','passed',
        coalesce((v_continuity->>'applicable')::boolean,false)
        and coalesce(v_continuity->>'fittingOperation','') in ('inspect_field_care_and_growth','inspect_establishment_and_reclassify','inspect_crop_care_and_growth'),
      'expected','visible direct-sow field-care continuation after germination',
      'actual',v_continuity));

    select count(*) into v_count
    from atlas.task_crop_cycles tc join atlas.tasks t on t.id=tc.task_id
    where tc.crop_cycle_id=v_cycle_id
      and (lower(coalesce(t.task_type,'')) like '%transplant%' or lower(coalesce(t.action_key,'')) like '%transplant%');
    v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
      'key','no_transplant_machinery_created','passed',v_count=0,'expected',0,'actual',v_count));

    perform atlas.reconcile_crop_cycle_requirement_state_v1(v_cycle_id);
    select id into v_req_id from atlas.state_consequence_instances
    where subject_kind='crop_cycle' and subject_id=v_cycle_id and consequence_role='operation_requirement'
      and action_key='harvest' and status='open' order by created_at desc limit 1;
    v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
      'key','harvest_not_required_from_calendar_alone','passed',v_req_id is null,'expected','no open harvest requirement before physical readiness','actual',v_req_id));

    insert into atlas.tasks(
      farm_id,title,task_type,action_key,work_class,status,priority,due_date,visibility_scope,note,metadata
    ) values(
      v_farm.id,'Reference harvest readiness observation','observation','inspect','crop_cycle','open','normal',v_today,'system_internal',
      'Synthetic physical harvest-readiness observation carrier.',
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'task_style','harvest_watch','physical_observation_required',true,'harvest_watch_mode','boundary_observation','structured_result_required',true)
    ) returning id into v_watch_task_id;
    insert into atlas.task_crop_cycles(task_id,crop_cycle_id,role,confidence,source,metadata)
    values(v_watch_task_id,v_cycle_id,'observes','confirmed','reference_company_runner',jsonb_build_object('reference_run_id',v_run_id))
    on conflict do nothing;
    insert into atlas.task_objects(task_id,object_id,role) values(v_watch_task_id,v_bed_id,'primary_location') on conflict do nothing;

    v_harvest_result := atlas.record_harvest_watch_observation_core_v1(
      v_watch_task_id,null,'owner','harvestable',50,'stems',null,
      'Synthetic Reference Company physical harvestability observation.',
      'reference-direct-harvestable:'||v_run_id::text,true
    );

    select id into v_req_id from atlas.state_consequence_instances
    where subject_kind='crop_cycle' and subject_id=v_cycle_id and consequence_role='operation_requirement'
      and action_key='harvest' and status='open' order by created_at desc limit 1;
    select status into v_text from atlas.crop_harvest_availability where crop_cycle_id=v_cycle_id;
    v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
      'key','physical_readiness_derives_harvest_requirement','passed',v_text='harvestable' and v_req_id is not null,
      'expected',jsonb_build_object('availability','harvestable','harvestRequirementOpen',true),
      'actual',jsonb_build_object('availability',v_text,'harvestRequirementId',v_req_id)));

    insert into atlas.tasks(
      farm_id,title,task_type,action_key,work_class,status,priority,due_date,visibility_scope,note,metadata
    ) values(
      v_farm.id,'Reference terminal harvest observation','observation','inspect','crop_cycle','open','normal',v_today,'system_internal',
      'Synthetic terminal crop observation carrier.',
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'task_style','harvest_watch','physical_observation_required',true,'harvest_watch_mode','boundary_observation','structured_result_required',true)
    ) returning id into v_finish_task_id;
    insert into atlas.task_crop_cycles(task_id,crop_cycle_id,role,confidence,source,metadata)
    values(v_finish_task_id,v_cycle_id,'observes','confirmed','reference_company_runner',jsonb_build_object('reference_run_id',v_run_id))
    on conflict do nothing;
    insert into atlas.task_objects(task_id,object_id,role) values(v_finish_task_id,v_bed_id,'primary_location') on conflict do nothing;

    perform atlas.record_harvest_watch_observation_core_v1(
      v_finish_task_id,null,'owner','finished',null,null,null,
      'Synthetic Reference Company terminal harvest observation.',
      'reference-direct-finished:'||v_run_id::text,true
    );

    v_pre_post := atlas.crop_cycle_postproduction_state_v1(v_cycle_id,v_today);
    select count(*) into v_count from atlas.task_crop_cycles tc join atlas.tasks t on t.id=tc.task_id
    where tc.crop_cycle_id=v_cycle_id and tc.role='clears' and t.status in ('open','blocked');
    v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
      'key','terminal_observation_requires_disposition_before_turnover','passed',
        v_pre_post->>'state'='management_disposition_required' and v_count=0,
      'expected',jsonb_build_object('state','management_disposition_required','openClearTasks',0),
      'actual',jsonb_build_object('postproduction',v_pre_post,'openClearTasks',v_count)));

    insert into atlas.crop_cycle_management_events(
      farm_id,crop_cycle_id,event_date,management_purpose,disposition,biomass_destination,
      confidence,source_kind,source_id,note,idempotency_key,metadata
    ) values(
      v_farm.id,v_cycle_id,v_today,'reference_terminal_disposition','clear_and_compost','compost',
      'high','reference_company_runner',v_run_id::text,'Synthetic owner disposition after terminal observation.',
      'reference-direct-disposition:'||v_run_id::text,jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id)
    );

    v_post_disposition := atlas.crop_cycle_postproduction_state_v1(v_cycle_id,v_today);
    v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
      'key','clearance_follows_explicit_terminal_disposition','passed',v_post_disposition->>'state'='clearance_carrier_required',
      'expected','clearance_carrier_required','actual',v_post_disposition->>'state'));

    insert into atlas.tasks(
      farm_id,title,task_type,action_key,work_class,status,priority,due_date,visibility_scope,note,metadata
    ) values(
      v_farm.id,'Reference clear direct-sow crop','crop_clear','clear_crop','crop_cycle','open','normal',v_today,'system_internal',
      'Synthetic clearance operation created only after terminal disposition.',
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'biomass_destination','compost','structured_result_required',false)
    ) returning id into v_clear_task_id;
    insert into atlas.task_crop_cycles(task_id,crop_cycle_id,role,confidence,source,metadata)
    values(v_clear_task_id,v_cycle_id,'clears','confirmed','reference_company_runner',jsonb_build_object('reference_run_id',v_run_id))
    on conflict do nothing;
    insert into atlas.task_objects(task_id,object_id,role) values(v_clear_task_id,v_bed_id,'work_carrier') on conflict do nothing;

    perform atlas.record_task_transition_v1_internal(
      v_clear_task_id,'done','reference-direct-clear:'||v_run_id::text,null,
      'Synthetic direct-sow crop cleared to compost.',null,'clear','crop_clear',
      jsonb_build_object('reference_run_id',v_run_id,'system_fixture',true,'biomass_destination','compost'),null
    );

    v_final_post := atlas.crop_cycle_postproduction_state_v1(v_cycle_id,v_today);
    v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
      'key','turnover_completes_after_clearance','passed',v_final_post->>'state'='cleared_complete',
      'expected','cleared_complete','actual',v_final_post->>'state'));

    select count(*) into v_count from (
      select t.task_type,t.action_key,count(*) from atlas.task_crop_cycles tc join atlas.tasks t on t.id=tc.task_id
      where tc.crop_cycle_id=v_cycle_id and t.status in ('open','blocked')
      group by t.task_type,t.action_key,t.id having count(*)>1
    ) d;
    v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
      'key','direct_sow_fixture_has_no_duplicate_linked_operations','passed',v_count=0,'expected',0,'actual',v_count));

    v_result := jsonb_build_object('fixtureRolledBack',true,'harvestResult',coalesce(v_harvest_result,'{}'::jsonb),'assertionCount',jsonb_array_length(v_assertions));
    raise exception 'REFERENCE_FIXTURE_ROLLBACK' using errcode='P9001';
  exception
    when sqlstate 'P9001' then v_fixture_completed:=true;
    when others then
      get stacked diagnostics v_error=message_text;
      v_fixture_completed:=false;
  end;

  if not v_fixture_completed then
    update atlas.reference_company_runs
    set status='failed',completed_at=now(),error_text=v_error,result=jsonb_build_object('fixtureRolledBack',true,'runnerError',v_error)
    where id=v_run_id;
    return jsonb_build_object('contractVersion','run_reference_company_direct_sow_golden_path_v1','runId',v_run_id,'scenarioKey','direct_sow_golden_path_v1','status','failed','error',v_error,'fixtureRolledBack',true);
  end if;

  insert into atlas.reference_company_assertions(run_id,assertion_key,passed,expected,actual,detail)
  select v_run_id,x->>'key',coalesce((x->>'passed')::boolean,false),jsonb_build_object('value',x->'expected'),jsonb_build_object('value',x->'actual'),null
  from jsonb_array_elements(v_assertions) x;

  select coalesce(bool_and(passed),false) into v_all_passed from atlas.reference_company_assertions where run_id=v_run_id;

  update atlas.reference_company_runs
  set status=case when v_all_passed then 'passed' else 'failed' end,completed_at=now(),
      result=v_result||jsonb_build_object('assertions',v_assertions,'allPassed',v_all_passed),
      error_text=case when v_all_passed then null else 'One or more conformance assertions failed.' end
  where id=v_run_id;

  return jsonb_build_object('contractVersion','run_reference_company_direct_sow_golden_path_v1','runId',v_run_id,
    'scenarioKey','direct_sow_golden_path_v1','status',case when v_all_passed then 'passed' else 'failed' end,
    'fixtureRolledBack',true,'assertions',v_assertions);
end;
$function$;

update atlas.reference_company_scenarios
set metadata=metadata||jsonb_build_object('implementation_state','executable','runner','run_reference_company_direct_sow_golden_path_v1','runner_version',1),updated_at=now()
where stable_key='direct_sow_golden_path_v1';