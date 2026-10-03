-- Shared Intelligence custody cleanup v1 production validation.
-- Read-only. Expected results are documented in architecture/SHARED_INTELLIGENCE_CUSTODY_CLEANUP_V1.md.

select
  (select count(*) from local_intel.outreach_targets) as live_outreach_rows,
  (select count(*) from local_intel.legacy_outreach_targets_archive_v1) as archived_outreach_rows,
  (select count(*) from atlas.legacy_local_intel_outreach_target_mappings) as custody_receipts,
  (select count(*) from local_intel.v_outreach_contact_resolution_v1) as legacy_outreach_projection_rows;

select disposition,count(*) as n
from atlas.legacy_local_intel_outreach_target_mappings
group by disposition
order by disposition;

select count(*) as unmapped_archive_rows
from local_intel.legacy_outreach_targets_archive_v1 a
left join atlas.legacy_local_intel_outreach_target_mappings m
  on m.legacy_outreach_target_id=a.id
where m.id is null;

select count(*) as contaminated_question_families
from local_intel.question_families
where active
  and (
    coalesce(resident_intent,'') ilike '%elm%'
    or coalesce(answer_policy,'') ilike '%elm%'
    or coalesce(insufficient_data_policy,'') ilike '%elm%'
    or example_questions::text ilike '%at Elm%'
    or 'outreach_target'=any(primary_object_scopes)
  );

select
  count(*) as person_discovery_rows,
  count(*) filter (where outreach_target_count<>0) as rows_with_legacy_outreach_count,
  count(*) filter (where has_actionable_outreach_target) as rows_with_legacy_actionable_outreach
from local_intel.v_person_discovery_targets_v1;

select trigger_name,action_timing,event_manipulation
from information_schema.triggers
where event_object_schema='local_intel'
  and event_object_table='outreach_targets'
  and trigger_name='outreach_targets_retired_write_guard_v1'
order by event_manipulation;

select o.name,
       count(distinct c.id) filter (
         where c.stable_key in (
           'event_host_candidates',
           'audience_host_candidates',
           'holiday_market_partners_2026',
           'community_partner_candidates',
           'provider_referral_sources',
           'distribution_partner_candidates'
         )
       ) as migrated_contexts,
       count(m.id) filter (
         where c.stable_key in (
           'event_host_candidates',
           'audience_host_candidates',
           'holiday_market_partners_2026',
           'community_partner_candidates',
           'provider_referral_sources',
           'distribution_partner_candidates'
         )
         and m.membership_state='active'
       ) as migrated_active_memberships
from atlas.organizations o
left join atlas.organization_purpose_contexts c
  on c.organization_id=o.id
left join atlas.organization_purpose_context_memberships m
  on m.context_id=c.id
where o.stable_key='elm_farm'
group by o.name;

select o.name,
       (select count(*) from atlas.external_relationships er where er.organization_id=o.id) as relationships
from atlas.organizations o
where o.stable_key in ('elm_farm','feast_guild')
order by o.name;

select count(*) as mct_current_canonical_bindings
from atlas.identity_subject_external_identifiers i
join local_intel.entities e
  on e.id::text=i.identifier_normalized
join atlas.organizations o
  on o.id=i.organization_id
where o.stable_key='elm_farm'
  and e.stable_key='marshfield-community-theatre'
  and i.provider_key='local_intel'
  and i.identifier_type='entity_id'
  and i.is_current;
