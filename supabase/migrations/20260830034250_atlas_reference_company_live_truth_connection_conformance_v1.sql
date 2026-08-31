insert into atlas.reference_company_scenarios(
  stable_key,domain,title,purpose,run_mode,fixture_version,preconditions,expected_invariants,active,metadata
) values
(
  'production_bed_preparation_sync_v1','production','Production bed-preparation sync authority',
  'Prove any governed production program can author one durable bed-preparation occurrence per assignment without hidden caller context and without duplicates.',
  'transactional',1,'{}'::jsonb,
  jsonb_build_array('one_occurrence_per_assignment','standalone_sync_has_reconciler_authority','rerun_creates_no_duplicates','future_prep_does_not_materialize_early'),
  true,jsonb_build_object('runner','run_reference_company_production_bed_preparation_sync_v1','runner_version',1,'system_fixture',true,'fixture_contract','rollback_only','implementation_state','executable','portable',true)
),
(
  'harvest_depletion_ledger_v1','production','Harvest depletion ledger',
  'Prove exact harvested stems reduce remaining crop potential exactly once while coarse unmatched bucket evidence remains unresolved and never invents stem counts.',
  'transactional',1,'{}'::jsonb,
  jsonb_build_array('exact_removed_stems_deplete_forecast','seconds_and_discards_also_deplete_standing_crop','unresolved_bucket_never_invents_stems','read_replay_does_not_double_deplete'),
  true,jsonb_build_object('runner','run_reference_company_harvest_depletion_ledger_v1','runner_version',1,'system_fixture',true,'fixture_contract','rollback_only','implementation_state','executable','portable',true)
)
on conflict(stable_key) do update set
  domain=excluded.domain,title=excluded.title,purpose=excluded.purpose,run_mode=excluded.run_mode,fixture_version=excluded.fixture_version,
  preconditions=excluded.preconditions,expected_invariants=excluded.expected_invariants,active=true,metadata=atlas.reference_company_scenarios.metadata||excluded.metadata,updated_at=now();

create or replace function atlas.run_reference_company_production_bed_preparation_sync_v1(p_source_revision text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  s atlas.reference_company_scenarios%rowtype;
  f atlas.farms%rowtype;
  profile_id uuid; bed1 uuid; bed2 uuid; bed3 uuid;
  run_id uuid; token text; today date:=(now() at time zone 'America/Chicago')::date;
  program_id uuid; lot_id uuid; requirement_id uuid; a1 uuid; a2 uuid; a3 uuid;
  first_result jsonb; second_result jsonb; first_ids jsonb; second_ids jsonb;
  occurrence_count integer; duplicate_count integer; early_task_count integer; metadata_link_count integer;
  assertions jsonb:='[]'::jsonb; fixture_completed boolean:=false; all_passed boolean:=false; err text;
begin
  select * into s from atlas.reference_company_scenarios where stable_key='production_bed_preparation_sync_v1' and active;
  if s.id is null then raise exception 'Reference production bed-preparation sync scenario is unavailable.' using errcode='P0002'; end if;
  select * into f from atlas.farms where stable_key='atlas_reference_farm';
  if f.id is null or not atlas.is_system_fixture_farm_v1(f.id) then raise exception 'Atlas Reference Farm isolation contract is unavailable.' using errcode='23514'; end if;
  select id into profile_id from atlas.crop_profiles where stable_key='atlas_reference_snapdragon_golden_v1';
  select id into bed1 from atlas.growing_objects where farm_id=f.id and stable_key='reference_bed_1';
  select id into bed2 from atlas.growing_objects where farm_id=f.id and stable_key='reference_bed_2';
  select id into bed3 from atlas.growing_objects where farm_id=f.id and stable_key='reference_bed_3';
  if profile_id is null or bed1 is null or bed2 is null or bed3 is null then raise exception 'Reference production bed-preparation fixtures are incomplete.' using errcode='23514'; end if;

  token:='reference:production_bed_preparation_sync_v1:'||replace(gen_random_uuid()::text,'-','');
  insert into atlas.reference_company_runs(scenario_id,farm_id,run_token,run_mode,status,source_revision,metadata)
  values(s.id,f.id,token,'transactional','running',p_source_revision,jsonb_build_object('fixtureVersion',s.fixture_version,'systemFixture',true,'runner','run_reference_company_production_bed_preparation_sync_v1'))
  returning id into run_id;

  begin
    insert into atlas.production_programs(farm_id,stable_key,season_year,program_label,program_kind,promise_text,intended_uses,status,metadata)
    values(f.id,'reference_bed_prep_sync_'||replace(run_id::text,'-',''),extract(year from today)::integer,'Reference generic bed-prep sync','reference_fixture','Prove generic capacity assignments author governed preparation work.',array['conformance'],'active',jsonb_build_object('system_fixture',true,'reference_run_id',run_id,'synthetic_truth',true)) returning id into program_id;

    insert into atlas.production_lots(farm_id,program_id,crop_profile_id,stable_key,lot_label,succession_number,planned_input_quantity,planned_input_unit,current_quantity,current_unit,current_stage,lifecycle_status,expected_transplant_start,expected_transplant_end,intended_uses,metadata)
    values(f.id,program_id,profile_id,'reference_bed_prep_lot_'||replace(run_id::text,'-',''),'Reference Generic Production Lot',1,720,'seedlings',720,'seedlings','transplant_ready','active',today+5,today+8,array['conformance'],jsonb_build_object('system_fixture',true,'reference_run_id',run_id,'synthetic_truth',true)) returning id into lot_id;

    insert into atlas.production_capacity_requirements(farm_id,production_lot_id,stable_key,stage_key,capacity_kind,quantity_needed,unit,required_by_date,window_start,window_end,preparation_due_date,calculation_status,source,metadata)
    values(f.id,lot_id,'reference_bed_prep_req','transplant','bed_feet',60,'bed_ft',today+5,today+5,today+8,today+3,'confirmed','reference_company_runner',jsonb_build_object('system_fixture',true,'reference_run_id',run_id,'synthetic_truth',true)) returning id into requirement_id;

    insert into atlas.production_bed_assignments(farm_id,production_lot_id,requirement_id,object_id,quantity_assigned,unit,planned_transplant_date,assignment_status,source,metadata) values
      (f.id,lot_id,requirement_id,bed1,20,'bed_ft',today+5,'assigned','reference_company_runner',jsonb_build_object('system_fixture',true,'reference_run_id',run_id,'synthetic_truth',true)),
      (f.id,lot_id,requirement_id,bed2,20,'bed_ft',today+5,'assigned','reference_company_runner',jsonb_build_object('system_fixture',true,'reference_run_id',run_id,'synthetic_truth',true)),
      (f.id,lot_id,requirement_id,bed3,20,'bed_ft',today+5,'assigned','reference_company_runner',jsonb_build_object('system_fixture',true,'reference_run_id',run_id,'synthetic_truth',true));
    select id into a1 from atlas.production_bed_assignments where production_lot_id=lot_id and object_id=bed1;
    select id into a2 from atlas.production_bed_assignments where production_lot_id=lot_id and object_id=bed2;
    select id into a3 from atlas.production_bed_assignments where production_lot_id=lot_id and object_id=bed3;

    first_result:=atlas.sync_production_bed_preparation_tasks_v1(program_id);
    select coalesce(jsonb_agg(id order by source_id),'[]'::jsonb) into first_ids
    from atlas.planned_work_occurrences where farm_id=f.id and source_kind='production_bed_assignment' and source_id in (a1,a2,a3) and state<>'cancelled';
    second_result:=atlas.sync_production_bed_preparation_tasks_v1(program_id);
    select coalesce(jsonb_agg(id order by source_id),'[]'::jsonb) into second_ids
    from atlas.planned_work_occurrences where farm_id=f.id and source_kind='production_bed_assignment' and source_id in (a1,a2,a3) and state<>'cancelled';
    select count(*) into occurrence_count from atlas.planned_work_occurrences where farm_id=f.id and source_kind='production_bed_assignment' and source_id in (a1,a2,a3) and state<>'cancelled';
    select count(*) into duplicate_count from (
      select occurrence_key from atlas.planned_work_occurrences where farm_id=f.id and source_kind='production_bed_assignment' and source_id in (a1,a2,a3) group by occurrence_key having count(*)>1
    ) d;
    select count(*) into early_task_count from atlas.planned_work_occurrences where farm_id=f.id and source_kind='production_bed_assignment' and source_id in (a1,a2,a3) and released_task_id is not null;
    select count(*) into metadata_link_count from atlas.production_bed_assignments where id in (a1,a2,a3) and nullif(metadata->>'bed_preparation_occurrence_id','') is not null;

    assertions:=assertions||jsonb_build_array(jsonb_build_object('key','one_occurrence_per_assignment','passed',occurrence_count=3 and metadata_link_count=3,'expected',jsonb_build_object('occurrences',3,'linkedAssignments',3),'actual',jsonb_build_object('occurrences',occurrence_count,'linkedAssignments',metadata_link_count,'firstResult',first_result)));
    assertions:=assertions||jsonb_build_array(jsonb_build_object('key','standalone_sync_has_reconciler_authority','passed',coalesce((first_result->>'occurrencesAuthored')::integer,0)=3 and jsonb_array_length(first_ids)=3,'expected',3,'actual',jsonb_build_object('authored',first_result->>'occurrencesAuthored','ids',first_ids)));
    assertions:=assertions||jsonb_build_array(jsonb_build_object('key','rerun_creates_no_duplicates','passed',first_ids=second_ids and occurrence_count=3 and duplicate_count=0,'expected',jsonb_build_object('stableIds',true,'duplicates',0),'actual',jsonb_build_object('stableIds',first_ids=second_ids,'duplicates',duplicate_count,'secondResult',second_result)));
    assertions:=assertions||jsonb_build_array(jsonb_build_object('key','future_prep_does_not_materialize_early','passed',early_task_count=0,'expected',0,'actual',early_task_count));
    raise exception 'REFERENCE_FIXTURE_ROLLBACK' using errcode='P9001';
  exception when sqlstate 'P9001' then fixture_completed:=true; when others then get stacked diagnostics err=message_text; fixture_completed:=false; end;

  if not fixture_completed then
    update atlas.reference_company_runs set status='failed',completed_at=now(),error_text=err,result=jsonb_build_object('fixtureRolledBack',true,'runnerError',err) where id=run_id;
    return jsonb_build_object('contractVersion','run_reference_company_production_bed_preparation_sync_v1','runId',run_id,'scenarioKey','production_bed_preparation_sync_v1','status','failed','error',err,'fixtureRolledBack',true);
  end if;
  insert into atlas.reference_company_assertions(run_id,assertion_key,passed,expected,actual,detail)
  select run_id,x->>'key',coalesce((x->>'passed')::boolean,false),jsonb_build_object('value',x->'expected'),jsonb_build_object('value',x->'actual'),null from jsonb_array_elements(assertions) x;
  select coalesce(bool_and(passed),false) into all_passed from atlas.reference_company_assertions where run_id=run_id;
  update atlas.reference_company_runs set status=case when all_passed then 'passed' else 'failed' end,completed_at=now(),result=jsonb_build_object('fixtureRolledBack',true,'assertionCount',jsonb_array_length(assertions),'assertions',assertions,'allPassed',all_passed),error_text=case when all_passed then null else 'One or more conformance assertions failed.' end where id=run_id;
  return jsonb_build_object('contractVersion','run_reference_company_production_bed_preparation_sync_v1','runId',run_id,'scenarioKey','production_bed_preparation_sync_v1','status',case when all_passed then 'passed' else 'failed' end,'fixtureRolledBack',true,'assertions',assertions);
end;
$function$;

create or replace function atlas.run_reference_company_harvest_depletion_ledger_v1(p_source_revision text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  s atlas.reference_company_scenarios%rowtype; f atlas.farms%rowtype;
  profile_id uuid; bed_id uuid; run_id uuid; token text; today date:=(now() at time zone 'America/Chicago')::date;
  cycle_id uuid; batch_id uuid; observation_id uuid;
  before_row jsonb; after_row jsonb; replay_row jsonb;
  assertions jsonb:='[]'::jsonb; fixture_completed boolean:=false; all_passed boolean:=false; err text;
begin
  select * into s from atlas.reference_company_scenarios where stable_key='harvest_depletion_ledger_v1' and active;
  if s.id is null then raise exception 'Reference harvest depletion scenario is unavailable.' using errcode='P0002'; end if;
  select * into f from atlas.farms where stable_key='atlas_reference_farm';
  if f.id is null or not atlas.is_system_fixture_farm_v1(f.id) then raise exception 'Atlas Reference Farm isolation contract is unavailable.' using errcode='23514'; end if;
  select id into profile_id from atlas.crop_profiles where stable_key='sunflower_teddy';
  select id into bed_id from atlas.growing_objects where farm_id=f.id and stable_key='reference_bed_1';
  if profile_id is null or bed_id is null then raise exception 'Reference harvest depletion fixtures are incomplete.' using errcode='23514'; end if;
  token:='reference:harvest_depletion_ledger_v1:'||replace(gen_random_uuid()::text,'-','');
  insert into atlas.reference_company_runs(scenario_id,farm_id,run_token,run_mode,status,source_revision,metadata)
  values(s.id,f.id,token,'transactional','running',p_source_revision,jsonb_build_object('fixtureVersion',s.fixture_version,'systemFixture',true,'runner','run_reference_company_harvest_depletion_ledger_v1')) returning id into run_id;

  begin
    insert into atlas.crop_cycles(farm_id,object_id,crop_profile_id,crop_cycle_key,crop_label,variety,cycle_state,lifecycle_status,sown_date,planted_date,coverage_kind,note,metadata)
    values(f.id,bed_id,profile_id,'reference_harvest_depletion_'||replace(run_id::text,'-',''),'Reference Sunflower','Teddy','harvest_watch','active',today-60,today-55,'whole_object','Synthetic reference-company harvest depletion stand.',jsonb_build_object('system_fixture',true,'reference_run_id',run_id,'synthetic_truth',true)) returning id into cycle_id;
    select to_jsonb(yf) into before_row from atlas.crop_cycle_yield_forecast yf where yf.crop_cycle_id=cycle_id;

    insert into atlas.crop_harvest_events(farm_id,crop_cycle_id,event_kind,outcome,observed_date,marketable_quantity,seconds_quantity,discarded_quantity,unit,more_available,note,idempotency_key,metadata)
    values(f.id,cycle_id,'cut','harvested_amount',today,10,2,3,'stems',true,'Synthetic exact stem removal.','reference-harvest-exact:'||run_id::text,jsonb_build_object('system_fixture',true,'reference_run_id',run_id,'synthetic_truth',true));

    insert into atlas.flower_harvest_batches(farm_id,harvest_date,batch_key,metadata)
    values(f.id,today,'reference-harvest-bucket:'||run_id::text,jsonb_build_object('system_fixture',true,'reference_run_id',run_id,'synthetic_truth',true)) returning id into batch_id;
    insert into atlas.flower_harvest_bucket_observations(farm_id,batch_id,crop_cycle_id,observed_date,bucket_band,bucket_equivalent_floor,bucket_halves,idempotency_key,metadata)
    values(f.id,batch_id,cycle_id,today,'half',0.5,1,'reference-harvest-bucket-observation:'||run_id::text,jsonb_build_object('system_fixture',true,'reference_run_id',run_id,'synthetic_truth',true,'quantityExactness','bucket_only')) returning id into observation_id;

    select to_jsonb(yf) into after_row from atlas.crop_cycle_yield_forecast yf where yf.crop_cycle_id=cycle_id;
    select to_jsonb(yf) into replay_row from atlas.crop_cycle_yield_forecast yf where yf.crop_cycle_id=cycle_id;

    assertions:=assertions||jsonb_build_array(jsonb_build_object('key','exact_removed_stems_deplete_forecast','passed',(before_row->>'original_potential_stems')::integer=120 and (after_row->>'known_removed_stems')::numeric=15 and (after_row->>'remaining_expected_stems')::integer=105,'expected',jsonb_build_object('original',120,'removed',15,'remaining',105),'actual',jsonb_build_object('original',before_row->>'original_potential_stems','removed',after_row->>'known_removed_stems','remaining',after_row->>'remaining_expected_stems')));
    assertions:=assertions||jsonb_build_array(jsonb_build_object('key','seconds_and_discards_also_deplete_standing_crop','passed',(after_row->>'known_removed_stems')::numeric=15,'expected','10 marketable + 2 seconds + 3 discarded = 15 removed','actual',after_row->>'known_removed_stems'));
    assertions:=assertions||jsonb_build_array(jsonb_build_object('key','unresolved_bucket_never_invents_stems','passed',(after_row->>'unresolved_harvest_depletion_events')::integer=1 and (after_row->>'known_removed_stems')::numeric=15 and after_row->>'harvest_depletion_state'='partial','expected',jsonb_build_object('unresolvedEvents',1,'knownRemoved',15,'state','partial'),'actual',jsonb_build_object('unresolvedEvents',after_row->>'unresolved_harvest_depletion_events','knownRemoved',after_row->>'known_removed_stems','state',after_row->>'harvest_depletion_state')));
    assertions:=assertions||jsonb_build_array(jsonb_build_object('key','read_replay_does_not_double_deplete','passed',after_row=replay_row and (replay_row->>'remaining_expected_stems')::integer=105,'expected',jsonb_build_object('sameRow',true,'remaining',105),'actual',jsonb_build_object('sameRow',after_row=replay_row,'remaining',replay_row->>'remaining_expected_stems')));
    raise exception 'REFERENCE_FIXTURE_ROLLBACK' using errcode='P9001';
  exception when sqlstate 'P9001' then fixture_completed:=true; when others then get stacked diagnostics err=message_text; fixture_completed:=false; end;

  if not fixture_completed then
    update atlas.reference_company_runs set status='failed',completed_at=now(),error_text=err,result=jsonb_build_object('fixtureRolledBack',true,'runnerError',err) where id=run_id;
    return jsonb_build_object('contractVersion','run_reference_company_harvest_depletion_ledger_v1','runId',run_id,'scenarioKey','harvest_depletion_ledger_v1','status','failed','error',err,'fixtureRolledBack',true);
  end if;
  insert into atlas.reference_company_assertions(run_id,assertion_key,passed,expected,actual,detail)
  select run_id,x->>'key',coalesce((x->>'passed')::boolean,false),jsonb_build_object('value',x->'expected'),jsonb_build_object('value',x->'actual'),null from jsonb_array_elements(assertions) x;
  select coalesce(bool_and(passed),false) into all_passed from atlas.reference_company_assertions a where a.run_id=run_id;
  update atlas.reference_company_runs set status=case when all_passed then 'passed' else 'failed' end,completed_at=now(),result=jsonb_build_object('fixtureRolledBack',true,'assertionCount',jsonb_array_length(assertions),'assertions',assertions,'allPassed',all_passed),error_text=case when all_passed then null else 'One or more conformance assertions failed.' end where id=run_id;
  return jsonb_build_object('contractVersion','run_reference_company_harvest_depletion_ledger_v1','runId',run_id,'scenarioKey','harvest_depletion_ledger_v1','status',case when all_passed then 'passed' else 'failed' end,'fixtureRolledBack',true,'assertions',assertions);
end;
$function$;