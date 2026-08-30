create or replace view atlas.crop_cycle_harvest_depletion_events_v1 as
with obs as (
  select fho.id observation_id,fho.crop_cycle_id,fho.batch_id,cc.crop_profile_id,fho.observed_date,fho.created_at source_created_at,coalesce(fho.bucket_equivalent_floor,0)::numeric bucket_equivalent
  from atlas.flower_harvest_bucket_observations fho
  join atlas.crop_cycles cc on cc.id=fho.crop_cycle_id
  where coalesce(fho.bucket_equivalent_floor,0)>0
), profile_bucket as (
  select batch_id,crop_profile_id,sum(bucket_equivalent) bucket_equivalent
  from obs group by batch_id,crop_profile_id
), prepared as (
  select fd.harvest_batch_id batch_id,fdl.crop_profile_id,sum((fdrl.actual_quantity::numeric)*(fdl.stems_per_unit::numeric)) prepared_stems
  from atlas.flower_preparation_directives fd
  join atlas.flower_preparation_directive_lines fdl on fdl.directive_id=fd.id
  join atlas.flower_preparation_directive_results fdr on fdr.directive_id=fd.id
  join atlas.flower_preparation_directive_result_lines fdrl on fdrl.result_id=fdr.id and fdrl.directive_line_id=fdl.id
  where fdrl.actual_quantity is not null and fdl.stems_per_unit is not null and fdl.crop_profile_id is not null
  group by fd.harvest_batch_id,fdl.crop_profile_id
), exact_events as (
  select e.id event_id,e.crop_cycle_id,e.observed_date,e.created_at source_created_at,
    (coalesce(e.marketable_quantity,0)+coalesce(e.seconds_quantity,0)+coalesce(e.discarded_quantity,0))::numeric known_removed_stems,
    nullif(e.metadata->>'flowerHarvestObservationId','')::uuid observation_id,
    nullif(e.metadata->>'flowerHarvestBatchId','')::uuid harvest_batch_id
  from atlas.crop_harvest_events e
  where lower(coalesce(e.unit,'')) in ('stem','stems')
    and (coalesce(e.marketable_quantity,0)+coalesce(e.seconds_quantity,0)+coalesce(e.discarded_quantity,0))>0
), bucket_rows as (
  select 'bucket:'||o.observation_id::text depletion_event_key,o.crop_cycle_id,o.observed_date,o.source_created_at,
    'flower_bucket_observation'::text source_kind,
    case when p.prepared_stems is not null and pb.bucket_equivalent>0 then round((p.prepared_stems*o.bucket_equivalent/pb.bucket_equivalent)::numeric,6) else 0::numeric end known_removed_stems,
    (p.prepared_stems is not null and pb.bucket_equivalent>0) quantity_resolved,
    case when p.prepared_stems is not null and pb.bucket_equivalent>0 then 'prepared_stems_allocated_by_bucket_share' else 'bucket_observed_stems_unresolved' end quantity_basis,
    o.observation_id source_id,o.batch_id harvest_batch_id,
    jsonb_build_object('bucketEquivalent',o.bucket_equivalent,'preparedProfileStems',p.prepared_stems,'profileBatchBucketEquivalent',pb.bucket_equivalent) metadata
  from obs o
  left join profile_bucket pb on pb.batch_id=o.batch_id and pb.crop_profile_id=o.crop_profile_id
  left join prepared p on p.batch_id=o.batch_id and p.crop_profile_id=o.crop_profile_id
  where not exists(select 1 from exact_events ee where ee.observation_id=o.observation_id)
), exact_rows as (
  select 'event:'||ee.event_id::text depletion_event_key,ee.crop_cycle_id,ee.observed_date,ee.source_created_at,
    'crop_harvest_event_stems'::text source_kind,ee.known_removed_stems,true quantity_resolved,
    'exact_stem_quantities'::text quantity_basis,ee.event_id source_id,ee.harvest_batch_id,
    jsonb_build_object('exactStemQuantity',ee.known_removed_stems) metadata
  from exact_events ee
), unresolved_event_rows as (
  select 'event-unresolved:'||e.id::text depletion_event_key,e.crop_cycle_id,e.observed_date,e.created_at source_created_at,
    'crop_harvest_event_quantity_unresolved'::text source_kind,0::numeric known_removed_stems,false quantity_resolved,
    'harvest_recorded_stems_unresolved'::text quantity_basis,e.id source_id,null::uuid harvest_batch_id,
    jsonb_build_object('eventKind',e.event_kind,'outcome',e.outcome,'quantityExactness',coalesce(e.metadata->>'quantityExactness','unresolved')) metadata
  from atlas.crop_harvest_events e
  where e.event_kind='cut'
    and e.outcome='harvested_amount'
    and (coalesce(e.marketable_quantity,0)+coalesce(e.seconds_quantity,0)+coalesce(e.discarded_quantity,0))=0
    and nullif(e.metadata->>'flowerHarvestObservationId','') is null
)
select * from exact_rows
union all select * from bucket_rows
union all select * from unresolved_event_rows;

create or replace function atlas.run_reference_company_harvest_depletion_ledger_v1(p_source_revision text default null)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','atlas'
as $function$
declare
  s atlas.reference_company_scenarios%rowtype; f atlas.farms%rowtype; profile_id uuid; bed_id uuid; v_run_id uuid; token text;
  today date:=(now() at time zone 'America/Chicago')::date; cycle_id uuid;
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
    insert into atlas.crop_cycles(farm_id,object_id,crop_profile_id,crop_cycle_key,crop_label,variety,cycle_state,lifecycle_status,sown_date,planted_date,coverage_kind,note,metadata)
    values(f.id,bed_id,profile_id,'reference_harvest_depletion_'||replace(v_run_id::text,'-',''),'Reference Sunflower','Teddy','harvest_watch','active',today-60,today-55,'whole_object','Synthetic reference-company harvest depletion stand.',jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)) returning id into cycle_id;
    select to_jsonb(yf) into before_row from atlas.crop_cycle_yield_forecast yf where yf.crop_cycle_id=cycle_id;

    insert into atlas.crop_harvest_events(farm_id,crop_cycle_id,event_kind,outcome,observed_date,marketable_quantity,seconds_quantity,discarded_quantity,unit,more_available,note,idempotency_key,metadata)
    values(f.id,cycle_id,'cut','harvested_amount',today,10,2,3,'stems',true,'Synthetic exact stem removal.','reference-harvest-exact:'||v_run_id::text,jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true));

    insert into atlas.crop_harvest_events(farm_id,crop_cycle_id,event_kind,outcome,observed_date,more_available,note,idempotency_key,metadata)
    values(f.id,cycle_id,'cut','harvested_amount',today,true,'Synthetic physical harvest with unresolved stem quantity.','reference-harvest-unresolved:'||v_run_id::text,jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true,'quantityExactness','unresolved'));

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