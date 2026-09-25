-- Smart Contacts person promotion validation.
-- Read-only checks against current production state.

with sellers as (
  select id
  from local_intel.entities
  where coalesce((metadata->>'seller_census_active')::boolean,false)=true
    and metadata->>'seller_census_batch'='elm_farm_60mi_cut_flower_seller_census_2026_09_24'
)
select
  count(*) as sellers,
  count(*) filter (where exists(
    select 1
    from local_intel.entity_relationships r
    join local_intel.entities p
      on p.id=r.subject_entity_id
     and p.entity_type='person'
    where r.object_entity_id=sellers.id
      and r.is_current
      and r.truth_state='accepted_current'
      and r.conflict_state='none'
  )) as with_canonical_current_person
from sellers;

select
  p.candidate_name,
  o.name as organization_name,
  p.review_state,
  p.matched_person_entity_id
from local_intel.person_discovery_candidates p
join local_intel.entities o on o.id=p.organization_entity_id
where p.metadata->>'canonicalization_contract'='person_discovery_candidate_promotion_v1'
order by o.name,p.candidate_name;

select count(er.id) as feast_guild_relationships
from atlas.organizations o
left join atlas.external_relationships er on er.organization_id=o.id
where o.stable_key='feast_guild';

select
  to_regprocedure('local_intel.preview_person_discovery_candidate_promotion_v1(uuid)') as preview_contract,
  to_regprocedure('local_intel.promote_person_discovery_candidate_service_v1(uuid,text)') as promotion_contract;
