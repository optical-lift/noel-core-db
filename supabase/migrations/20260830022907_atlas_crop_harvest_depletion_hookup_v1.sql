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
  select 'event:'||ee.event_id::text depletion_event_key,ee.crop_cycle_id,ee.observed_date,ee.source_created_at,'crop_harvest_event_stems'::text source_kind,ee.known_removed_stems,true quantity_resolved,'exact_stem_quantities'::text quantity_basis,ee.event_id source_id,ee.harvest_batch_id,jsonb_build_object('exactStemQuantity',ee.known_removed_stems) metadata
  from exact_events ee
)
select * from exact_rows union all select * from bucket_rows;

create or replace view atlas.crop_cycle_harvest_depletion_v1 as
select crop_cycle_id,
  sum(known_removed_stems) filter(where quantity_resolved)::numeric known_removed_stems,
  count(*) filter(where quantity_resolved)::integer resolved_depletion_events,
  count(*) filter(where not quantity_resolved)::integer unresolved_depletion_events,
  max(observed_date) last_harvest_depletion_date
from atlas.crop_cycle_harvest_depletion_events_v1
group by crop_cycle_id;

create or replace view atlas.crop_cycle_yield_forecast as
with latest_impact as (
  select distinct on (i.crop_cycle_id) i.crop_cycle_id,i.impact_type,i.severity,i.viability_state,i.surviving_stand_percent,i.expected_yield_percent,i.estimated_remaining_stems,i.confidence impact_confidence,i.observed_date,i.created_at impact_created_at,i.note impact_note
  from atlas.crop_cycle_impacts i order by i.crop_cycle_id,i.observed_date desc,i.created_at desc
), base as (
  select cc.id crop_cycle_id,cc.farm_id,cc.object_id,go.zone_id,go.stable_key object_stable_key,go.label object_label,cc.crop_profile_id,cp.stable_key crop_profile_stable_key,cc.crop_label,cc.variety,cc.sown_date,cc.planted_date,cc.expected_harvest_watch_start,cc.expected_harvest_watch_end,cc.lifecycle_status,cc.cycle_state,
    cc.sown_date is not null or cc.planted_date is not null is_in_ground,
    coalesce(cc.coverage_amount,case when cc.coverage_kind='whole_object' then go.length_ft end,go.length_ft) effective_length_ft,
    cp.rows_per_3ft_bed,cp.in_row_spacing_in,coalesce(cp.expected_stems_per_plant,1::numeric) expected_stems_per_plant,
    case when coalesce(cc.coverage_amount,case when cc.coverage_kind='whole_object' then go.length_ft end,go.length_ft) is not null and cp.rows_per_3ft_bed is not null and cp.in_row_spacing_in is not null and cp.in_row_spacing_in>0 then floor(coalesce(cc.coverage_amount,case when cc.coverage_kind='whole_object' then go.length_ft end,go.length_ft)*cp.rows_per_3ft_bed*(12.0/cp.in_row_spacing_in)*coalesce(cp.expected_stems_per_plant,1::numeric))::integer end original_potential_stems
  from atlas.crop_cycles cc join atlas.growing_objects go on go.id=cc.object_id left join atlas.crop_profiles cp on cp.id=cc.crop_profile_id where cc.lifecycle_status='active'
), estimated as (
  select b.*,li.impact_type,li.severity impact_severity,li.viability_state,li.surviving_stand_percent,li.expected_yield_percent,li.estimated_remaining_stems,li.impact_confidence,li.observed_date impact_observed_date,li.impact_created_at,li.impact_note,
    case when not b.is_in_ground then b.original_potential_stems when li.crop_cycle_id is null then b.original_potential_stems when li.estimated_remaining_stems is not null then li.estimated_remaining_stems when li.expected_yield_percent is not null and b.original_potential_stems is not null then floor(b.original_potential_stems::numeric*li.expected_yield_percent/100.0)::integer when li.viability_state=any(array['not_viable','failed']) then 0 else null::integer end pre_harvest_adjusted_stems,
    case when not b.is_in_ground then 0 when li.crop_cycle_id is null then coalesce(b.original_potential_stems,0) when li.estimated_remaining_stems is not null then li.estimated_remaining_stems when li.expected_yield_percent is not null and b.original_potential_stems is not null then floor(b.original_potential_stems::numeric*li.expected_yield_percent/100.0)::integer when li.viability_state=any(array['not_viable','failed']) then 0 else 0 end pre_harvest_bankable_stems,
    case when not b.is_in_ground then 'planned_not_in_ground' when li.crop_cycle_id is null then 'baseline' when li.estimated_remaining_stems is not null or li.expected_yield_percent is not null then 'adjusted' when li.viability_state=any(array['not_viable','failed']) then 'zeroed' else 'assessment_required' end forecast_state
  from base b left join latest_impact li on li.crop_cycle_id=b.crop_cycle_id
), with_depletion as (
  select e.*,coalesce(h.known_removed_stems,0)::numeric known_removed_stems,coalesce(h.resolved_events,0)::integer resolved_harvest_depletion_events,coalesce(h.unresolved_events,0)::integer unresolved_harvest_depletion_events
  from estimated e
  left join lateral (
    select sum(d.known_removed_stems) filter(where d.quantity_resolved and (e.estimated_remaining_stems is null or e.impact_created_at is null or d.source_created_at>e.impact_created_at)) known_removed_stems,
      count(*) filter(where d.quantity_resolved and (e.estimated_remaining_stems is null or e.impact_created_at is null or d.source_created_at>e.impact_created_at)) resolved_events,
      count(*) filter(where not d.quantity_resolved and (e.estimated_remaining_stems is null or e.impact_created_at is null or d.source_created_at>e.impact_created_at)) unresolved_events
    from atlas.crop_cycle_harvest_depletion_events_v1 d where d.crop_cycle_id=e.crop_cycle_id
  ) h on true
)
select crop_cycle_id,farm_id,object_id,zone_id,object_stable_key,object_label,crop_profile_id,crop_profile_stable_key,crop_label,variety,sown_date,planted_date,expected_harvest_watch_start,expected_harvest_watch_end,lifecycle_status,cycle_state,is_in_ground,effective_length_ft,rows_per_3ft_bed,in_row_spacing_in,expected_stems_per_plant,original_potential_stems,impact_type,impact_severity,viability_state,surviving_stand_percent,expected_yield_percent,estimated_remaining_stems,impact_confidence,impact_observed_date,impact_note,
  case when pre_harvest_adjusted_stems is null then null else greatest(0,pre_harvest_adjusted_stems-round(known_removed_stems)::integer) end adjusted_expected_stems,
  greatest(0,pre_harvest_bankable_stems-round(known_removed_stems)::integer) bankable_stems,
  forecast_state,
  known_removed_stems,resolved_harvest_depletion_events,unresolved_harvest_depletion_events,
  case when pre_harvest_adjusted_stems is null then null else greatest(0,pre_harvest_adjusted_stems-round(known_removed_stems)::integer) end remaining_expected_stems,
  case when unresolved_harvest_depletion_events>0 then 'partial' when known_removed_stems>0 then 'applied' else 'none' end harvest_depletion_state
from with_depletion;