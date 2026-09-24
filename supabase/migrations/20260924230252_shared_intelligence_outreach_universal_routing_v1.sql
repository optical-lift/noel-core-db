-- Reclassify universal research/acquisition rows from the retired mixed-custody carrier.

with classified as (
  select
    a.*,
    case
      when a.target_kind='availability_refresh' then 'availability_refresh'
      when a.target_kind in ('local_intel_verification','fact_verification','local_food_verification')
        then 'fact_verification'
      when a.target_kind in (
        'data_source','vendor_roster_source','community_program_source',
        'authoritative_business_census_source','community_sponsor_source',
        'future_vendor_network','nonprofit_public_events_source',
        'recurring_vendor_schedule_source','weekly_feature_source'
      ) then 'source_acquisition'
      else null
    end as enrichment_kind
  from local_intel.legacy_outreach_targets_archive_v1 a
),
grouped as (
  select
    entity_id,
    enrichment_kind,
    max(coalesce(priority,50)) as priority,
    case
      when bool_or(status='needs_contact_path') then 'blocked'
      when bool_and(status like 'hold%') then 'hold'
      else 'queued'
    end as status,
    'Legacy mixed-custody work reclassified as universal Shared Intelligence research. Resolve only source-backed external reality; no Atlas Organization relationship or intent is implied.'::text as rationale,
    nullif(
      string_agg(distinct nullif(btrim(proposed_format),'') , E'\n---\n')
        filter (where nullif(btrim(proposed_format),'') is not null),
      ''
    ) as source_hint,
    jsonb_build_object(
      'custody','shared_intelligence_research',
      'migration','shared_intelligence_outreach_universal_routing_v1',
      'legacyOutreachTargets',
      jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'legacyOutreachTargetId',id,
          'legacyTargetKind',target_kind,
          'legacyStatus',status,
          'priority',priority,
          'rationale',rationale,
          'proposedFormat',proposed_format,
          'proposedWindow',case when proposed_window is null then null else proposed_window::text end,
          'notes',notes,
          'personEntityId',person_entity_id,
          'contactPointId',contact_point_id,
          'sourceId',source_id,
          'legacyMetadata',metadata
        ))
        order by priority desc nulls last,id
      )
    ) as metadata
  from classified
  where enrichment_kind is not null
  group by entity_id,enrichment_kind
)
insert into local_intel.entity_enrichment_targets(
  id,entity_id,target_kind,priority,status,rationale,source_hint,metadata
)
select
  gen_random_uuid(),entity_id,enrichment_kind,priority,status,rationale,source_hint,metadata
from grouped
on conflict (entity_id,target_kind) do update
set priority=greatest(local_intel.entity_enrichment_targets.priority,excluded.priority),
    status=case
      when local_intel.entity_enrichment_targets.status='complete' then 'complete'
      when excluded.status='blocked' then 'blocked'
      when local_intel.entity_enrichment_targets.status='active' then 'active'
      when excluded.status='hold'
        and local_intel.entity_enrichment_targets.status='queued' then 'hold'
      else local_intel.entity_enrichment_targets.status
    end,
    rationale=case
      when local_intel.entity_enrichment_targets.rationale is null
        or btrim(local_intel.entity_enrichment_targets.rationale)=''
      then excluded.rationale
      else local_intel.entity_enrichment_targets.rationale
    end,
    source_hint=coalesce(local_intel.entity_enrichment_targets.source_hint,excluded.source_hint),
    metadata=coalesce(local_intel.entity_enrichment_targets.metadata,'{}'::jsonb)
      || excluded.metadata,
    updated_at=now();

insert into atlas.legacy_local_intel_outreach_target_mappings(
  legacy_outreach_target_id,disposition,enrichment_target_id,metadata
)
select
  a.id,
  'shared_intelligence_enrichment',
  et.id,
  jsonb_build_object(
    'legacyTargetKind',a.target_kind,
    'migration','shared_intelligence_outreach_universal_routing_v1'
  )
from local_intel.legacy_outreach_targets_archive_v1 a
join local_intel.entity_enrichment_targets et
  on et.entity_id=a.entity_id
 and et.target_kind=case
      when a.target_kind='availability_refresh' then 'availability_refresh'
      when a.target_kind in ('local_intel_verification','fact_verification','local_food_verification')
        then 'fact_verification'
      when a.target_kind in (
        'data_source','vendor_roster_source','community_program_source',
        'authoritative_business_census_source','community_sponsor_source',
        'future_vendor_network','nonprofit_public_events_source',
        'recurring_vendor_schedule_source','weekly_feature_source'
      ) then 'source_acquisition'
      else null
    end
where a.target_kind in (
  'availability_refresh',
  'local_intel_verification','fact_verification','local_food_verification',
  'data_source','vendor_roster_source','community_program_source',
  'authoritative_business_census_source','community_sponsor_source',
  'future_vendor_network','nonprofit_public_events_source',
  'recurring_vendor_schedule_source','weekly_feature_source'
)
on conflict (legacy_outreach_target_id) do nothing;
