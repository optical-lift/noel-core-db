create or replace function atlas.run_reference_company_harvest_depletion_ledger_v1(p_source_revision text default null)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','atlas'
as $function$
declare
  s atlas.reference_company_scenarios%rowtype; f atlas.farms%rowtype; profile_id uuid; bed_id uuid; v_run_id uuid; token text;
  today date:=(now() at time zone 'America/Chicago')::date; cycle_id uuid; batch_id uuid; observation_id uuid; fixture_membership_id uuid;
  before_row jsonb; after_row jsonb; replay_row jsonb; assertions jsonb:='[]'::jsonb;
  fixture_completed boolean:=false; all_passed boolean:=false; err text;
begin
  select * into s from atlas.reference_company_scenarios where stable_key='harvest_depletion_ledger_v1' and active;
  select * into f from atlas.farms where stable_key='atlas_reference_farm';
  if s.id is null or f.id is null or not atlas.is_system_fixture_farm_v1(f.id) then raise exception 'Reference harvest depletion fixture unavailable.' using errcode='23514'; end if;
  select id into profile_id from atlas.crop_profiles where stable_key='sunflower_teddy';
  select id into bed_id from atlas.growing_objects where farm_id=f.id and stable_key='reference_bed_1';
  if profile_id is null or bed_id is null then raise exception 'Reference harvest depletion fixture objects incomplete.' using errcode='23514'; end if;
  token:='reference:harvest_depletion_ledger_v1:'||replace(gen_random_uuid()::text,'-','');
  insert into atlas.reference_company_runs(scenario_id,farm_id,run_token,run_mode,status,source_revision,metadata)
  values(s.id,f.id,token,'transactional','running',p_source_revision,jsonb_build_object('fixtureVersion',s.fixture_version,'systemFixture',true,'runner','run_reference_company_harvest_depletion_ledger_v1')) returning id into v_run_id;
  begin
    insert into atlas.farm_memberships(user_id,farm_id,role,worker_key,active,permissions)
    values(gen_random_uuid(),f.id,'farm_hand','reference_harvest_fixture',true,jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id))
    returning id into fixture_membership_id;

    insert into atlas.crop_cycles(farm_id,object_id,crop_profile_id,crop_cycle_key,crop_label,variety,cycle_state,lifecycle_status,sown_date,planted_date,coverage_kind,note,metadata)
    values(f.id,bed_id,profile_id,'reference_harvest_depletion_'||replace(v_run_id::text,'-',''),'Reference Sunflower','Teddy','harvest_watch','active',today-60,today-55,'whole_object','Synthetic reference-company harvest depletion stand.',jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)) returning id into cycle_id;
    select to_jsonb(yf) into before_row from atlas.crop_cycle_yield_forecast yf where yf.crop_cycle_id=cycle_id;
    insert into atlas.crop_harvest_events(farm_id,crop_cycle_id,event_kind,outcome,observed_date,marketable_quantity,seconds_quantity,discarded_quantity,unit,more_available,note,idempotency_key,metadata)
    values(f.id,cycle_id,'cut','harvested_amount',today,10,2,3,'stems',true,'Synthetic exact stem removal.','reference-harvest-exact:'||v_run_id::text,jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true));
    insert into atlas.flower_harvest_batches(farm_id,harvest_date,recorded_by_membership_id,batch_key,metadata)
    values(f.id,today,fixture_membership_id,'reference-harvest-bucket:'||v_run_id::text,jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)) returning id into batch_id;
    insert into atlas.flower_harvest_bucket_observations(farm_id,batch_id,crop_cycle_id,recorded_by_membership_id,observed_date,bucket_band,bucket_equivalent_floor,bucket_halves,idempotency_key,metadata)
    values(f.id,batch_id,cycle_id,fixture_membership_id,today,'half',0.5,1,'reference-harvest-bucket-observation:'||v_run_id::text,jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true,'quantityExactness','bucket_only')) returning id into observation_id;
    select to_jsonb(yf) into after_row from atlas.crop_cycle_yield_forecast yf where yf.crop_cycle_id=cycle_id;
    select to_jsonb(yf) into replay_row from atlas.crop_cycle_yield_forecast yf where yf.crop_cycle_id=cycle_id;
    assertions:=jsonb_build_array(
      jsonb_build_object('key','exact_removed_stems_deplete_forecast','passed',(before_row->>'original_potential_stems')::int=120 and (after_row->>'known_removed_stems')::numeric=15 and (after_row->>'remaining_expected_stems')::int=105,'expected',jsonb_build_object('original',120,'removed',15,'remaining',105),'actual',jsonb_build_object('original',before_row->>'original_potential_stems','removed',after_row->>'known_removed_stems','remaining',after_row->>'remaining_expected_stems')),
      jsonb_build_object('key','seconds_and_discards_also_deplete_standing_crop','passed',(after_row->>'known_removed_stems')::numeric=15,'expected','10 marketable + 2 seconds + 3 discarded = 15 removed','actual',after_row->>'known_removed_stems'),
      jsonb_build_object('key','unresolved_bucket_never_invents_stems','passed',(after_row->>'unresolved_harvest_depletion_events')::int=1 and (after_row->>'known_removed_stems')::numeric=15 and after_row->>'harvest_depletion_state'='partial','expected',jsonb_build_object('unresolvedEvents',1,'knownRemoved',15,'state','partial'),'actual',jsonb_build_object('unresolvedEvents',after_row->>'unresolved_harvest_depletion_events','knownRemoved',after_row->>'known_removed_stems','state',after_row->>'harvest_depletion_state')),
      jsonb_build_object('key','read_replay_does_not_double_deplete','passed',after_row=replay_row and (replay_row->>'remaining_expected_stems')::int=105,'expected',jsonb_build_object('sameRow',true,'remaining',105),'actual',jsonb_build_object('sameRow',after_row=replay_row,'remaining',replay_row->>'remaining_expected_stems'))
    );
    raise exception 'REFERENCE_FIXTURE_ROLLBACK' using errcode='P9001';
  exception when sqlstate 'P9001' then fixture_completed:=true; when others then get stacked diagnostics err=message_text; fixture_completed:=false; end;
  if not fixture_completed then update atlas.reference_company_runs set status='failed',completed_at=now(),error_text=err,result=jsonb_build_object('fixtureRolledBack',true,'runnerError',err) where id=v_run_id; return jsonb_build_object('runId',v_run_id,'scenarioKey','harvest_depletion_ledger_v1','status','failed','error',err,'fixtureRolledBack',true); end if;
  insert into atlas.reference_company_assertions(run_id,assertion_key,passed,expected,actual,detail)
  select v_run_id,x->>'key',coalesce((x->>'passed')::boolean,false),jsonb_build_object('value',x->'expected'),jsonb_build_object('value',x->'actual'),null from jsonb_array_elements(assertions)x;
  select coalesce(bool_and(a.passed),false) into all_passed from atlas.reference_company_assertions a where a.run_id=v_run_id;
  update atlas.reference_company_runs set status=case when all_passed then 'passed' else 'failed' end,completed_at=now(),result=jsonb_build_object('fixtureRolledBack',true,'assertionCount',jsonb_array_length(assertions),'assertions',assertions,'allPassed',all_passed),error_text=case when all_passed then null else 'One or more conformance assertions failed.' end where id=v_run_id;
  return jsonb_build_object('contractVersion','run_reference_company_harvest_depletion_ledger_v1','runId',v_run_id,'scenarioKey','harvest_depletion_ledger_v1','status',case when all_passed then 'passed' else 'failed' end,'fixtureRolledBack',true,'assertions',assertions);
end;$function$;